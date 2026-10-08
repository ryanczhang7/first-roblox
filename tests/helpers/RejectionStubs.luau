--!strict
--[[
	The wrong reporters and wrappers TEL-003's controls are aimed at, and the
	one baseline each of them is a single defect away from.

	THE STORY NAMES ITS CONTROLS. AC-2: "an implementation emitting on every
	guarded call passes AC-1 and must fail this" - `emitsOnAccept`. AC-4: "an
	implementation that puts rawArgs in fields must fail this, and must also
	fail TEL-001's scalar-fields check when the payload is a table" -
	`rawArgsInFields`; PO decision 2 adds the one that copies `detail` -
	`detailInFields`. AC-5: "the unbounded implementation produces 1,000
	events" - `unbounded`; `## Notes` mutation 2 drops the count -
	`dropsCount`. AC-6: coalescing keyed by player alone or by remote alone -
	`perPlayerOnly`, `perRemoteOnly`. The rest are one-defect bundles for the
	Contract clauses the remaining checks would otherwise have no control for.

	TWO STUBS, ONE BUNDLE. The REPORTER stub is a from-scratch reference of
	the Contract's `RejectionReporter` (there is nothing to wrap: the module
	does not exist). The WRAPPER stub is a layer over the real, merged
	`Wrapper.guard`: it calls the inner guard, and on a Rejection performs the
	telemetry step the Contract describes - `record` then `emit({ event })`.
	The real wrapper performs that step itself when it sees `telemetry` in
	the context, so the stub hands the inner guard a COPY OF THE CONTEXT WITH
	`telemetry = nil`: otherwise each rejection would be recorded and emitted
	twice, once per layer, and the baseline would fail the wiring check
	against a correct implementation (R1). With the field stripped, the stub
	is the sole author of its telemetry step, every earlier suite's check
	still holds over every bundle here except the one built to break it
	(`assumesTelemetry`), and a control that fires is attributable to one
	field of `defects`.

	WHAT THIS IS NOT: `src/ReplicatedStorage/Net/RejectionReporter.luau` or a sketch of it, and
	not the wrapper change either. GREEN writes both from the story's
	`## Contract` against the failing tests. Events here are built BY HAND as
	plain tables - deliberately not through `Event.new`, so that a defective
	stub can carry a table in `fields` and be observed failing the scalar
	check rather than raising before it is reached.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/rejection_controls_test.luau` records what
	each one actually did.
]]

local RateLimiter = require("../../src/ReplicatedStorage/Net/RateLimiter")
local Remotes = require("../../src/ReplicatedStorage/Net/Remotes")
local Schema = require("../../src/ReplicatedStorage/Net/Schema")
local TelemetryStubs = require("./TelemetryStubs")
local Wrapper = require("../../src/ReplicatedStorage/Net/Wrapper")

local Real: any = Wrapper

local RejectionStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  Reporter
	  * `unbounded`             - `rate` is never coalesced: one event per
	                              rejection (AC-5's named control)
	  * `dropsCount`            - the coalesced event carries no `count`
	                              (AC-5's sum; `## Notes` mutation 2)
	  * `coalescesAllReasons`   - every reason is coalesced, not only `rate`
	                              (PO decision 3 / AC-1)
	  * `perPlayerOnly`         - the window key is the player alone (AC-6)
	  * `perRemoteOnly`         - the window key is the remote alone (AC-6)
	  * `strictWindow`          - `>` instead of `>=` (the inclusive boundary)
	  * `flushResetsWindow`     - flush moves the window start to its `now`
	  * `flushKeepsPending`     - flush reports the pending count and keeps it
	  * `flushInInsertionOrder` - flush returns keys as first seen, not sorted
	  * `callerInFields`        - `fields.caller = tostring(playerId)`
	  * `tableCallerInEnvelope` - a non-string caller id goes into `playerId`
	  * `wrongBucket`           - the event is filed under D2_7
	  Wrapper
	  * `ignoresTelemetry`      - no telemetry step at all: the pre-TEL-003
	                              wrapper, and what the real suite fails on
	                              arrival
	  * `emitsOnAccept`         - the telemetry step runs on every guarded
	                              call, accepted or not (AC-2's named control;
	                              `## Notes` mutation 1)
	  * `collapsesReason`       - `shape` and `range` are both reported as
	                              "invalid" (AC-3)
	  * `rawArgsInFields`       - `fields.rawArgs = rawArgs` (AC-4's named
	                              control; `## Notes` mutation 3)
	  * `detailInFields`        - `fields.detail = rejection.detail` (AC-4,
	                              PO decision 2)
	  * `assumesTelemetry`      - indexes `context.telemetry` with no nil
	                              check, so a context without it raises
	  * `emitsBareEvent`        - `emit(event)` instead of `emit({ event })`
	  * `emitsTwice`            - `emit({ event })` twice per event
	  * `stampsZero`            - `now` is 0 rather than the clock's value
]]
export type Defects = {
	unbounded: boolean?,
	dropsCount: boolean?,
	coalescesAllReasons: boolean?,
	perPlayerOnly: boolean?,
	perRemoteOnly: boolean?,
	strictWindow: boolean?,
	flushResetsWindow: boolean?,
	flushKeepsPending: boolean?,
	flushInInsertionOrder: boolean?,
	callerInFields: boolean?,
	tableCallerInEnvelope: boolean?,
	wrongBucket: boolean?,
	ignoresTelemetry: boolean?,
	emitsOnAccept: boolean?,
	collapsesReason: boolean?,
	rawArgsInFields: boolean?,
	detailInFields: boolean?,
	assumesTelemetry: boolean?,
	emitsBareEvent: boolean?,
	emitsTwice: boolean?,
	stampsZero: boolean?,
}

export type Bundle = {
	Schema: any,
	Remotes: any,
	Wrapper: any,
	RateLimiter: any,
	RejectionReporter: any,
	Event: any,
}

type Window = { playerId: any, remoteName: string, w: number, p: number }

local function makeReporterModule(defects: Defects): any
	local Reporter = {}
	Reporter.INTERVAL_SECONDS = 1

	function Reporter.new(intervalSeconds: number, sessionId: string): any
		local windows: { [string]: Window } = {}
		local order: { string } = {}
		local reporter = {}

		local function event(
			playerId: any,
			remoteName: string,
			reason: string,
			count: number,
			now: number
		): any
			local fields: { [string]: any } =
				{ remote = remoteName, reason = reason, count = count }
			if defects.dropsCount then
				fields.count = nil
			end
			if defects.callerInFields then
				fields.caller = tostring(playerId)
			end
			local envelopeId: any = if typeof(playerId) == "string" then playerId else nil
			if defects.tableCallerInEnvelope then
				envelopeId = playerId
			end
			return {
				name = "remote_rejected",
				at = now,
				bucket = if defects.wrongBucket then "D2_7" else "D1",
				sessionId = sessionId,
				playerId = envelopeId,
				fields = fields,
			}
		end

		local function keyOf(playerId: any, remoteName: string): string
			if defects.perPlayerOnly then
				return tostring(playerId)
			end
			if defects.perRemoteOnly then
				return remoteName
			end
			return `{tostring(playerId)}\0{remoteName}`
		end

		function reporter.record(
			_self: any,
			playerId: any,
			remoteName: string,
			reason: string,
			now: number
		): any
			local coalesce = reason == "rate" or defects.coalescesAllReasons == true
			if defects.unbounded then
				coalesce = false
			end
			if not coalesce then
				return event(playerId, remoteName, reason, 1, now)
			end
			local key = keyOf(playerId, remoteName)
			local window = windows[key]
			local reopens: boolean
			if window == nil then
				reopens = true
			elseif defects.strictWindow then
				reopens = now - window.w > intervalSeconds
			else
				reopens = now - window.w >= intervalSeconds
			end
			if reopens then
				local pending = if window ~= nil then window.p else 0
				if window == nil then
					window = { playerId = playerId, remoteName = remoteName, w = now, p = 0 }
					windows[key] = window
					table.insert(order, key)
				end
				local open = window :: Window
				open.w = now
				open.p = 0
				return event(playerId, remoteName, reason, 1 + pending, now)
			end
			local inside = window :: Window
			inside.p += 1
			return nil
		end

		function reporter.flush(_self: any, now: number): { any }
			local keys = table.clone(order)
			if not defects.flushInInsertionOrder then
				table.sort(keys, function(a: string, b: string): boolean
					local wa, wb = windows[a], windows[b]
					local pa, pb = tostring(wa.playerId), tostring(wb.playerId)
					if pa ~= pb then
						return pa < pb
					end
					return wa.remoteName < wb.remoteName
				end)
			end
			local out: { any } = {}
			for _, key in keys do
				local window = windows[key]
				if window.p > 0 then
					table.insert(
						out,
						event(window.playerId, window.remoteName, "rate", window.p, now)
					)
					if not defects.flushKeepsPending then
						window.p = 0
					end
					if defects.flushResetsWindow then
						window.w = now
					end
				end
			end
			return out
		end

		return reporter
	end

	return Reporter
end

local function makeWrapperModule(defects: Defects): any
	local Stub = {}

	function Stub.guard(definition: any, context: any, handler: any): any
		-- The real wrapper records and emits on its own when it sees
		-- `telemetry`. It must not here: the stub is the sole author of the
		-- telemetry step, so the inner guard gets a copy without the field.
		local innerContext = table.clone(context)
		innerContext.telemetry = nil
		local inner = Real.guard(definition, innerContext, handler)

		return function(playerId: any, rawArgs: any): any
			local rejection = inner(playerId, rawArgs)
			if defects.ignoresTelemetry then
				return rejection
			end
			local telemetry = context.telemetry
			if telemetry == nil and not defects.assumesTelemetry then
				return rejection
			end
			if rejection == nil and not defects.emitsOnAccept then
				return nil
			end
			-- From here on `telemetry` is indexed: under `assumesTelemetry` a
			-- nil field raises, which is the defect.
			local reason: string = if rejection ~= nil then rejection.reason else "accepted"
			if defects.collapsesReason and (reason == "shape" or reason == "range") then
				reason = "invalid"
			end
			local now = if defects.stampsZero then 0 else context.clock.now()
			local event = telemetry.reporter:record(playerId, definition.name, reason, now)
			if event ~= nil then
				if defects.rawArgsInFields then
					event.fields.rawArgs = rawArgs
				end
				if defects.detailInFields and rejection ~= nil then
					event.fields.detail = rejection.detail
				end
				if defects.emitsBareEvent then
					telemetry.emit(event)
				else
					telemetry.emit({ event })
				end
				if defects.emitsTwice then
					telemetry.emit({ event })
				end
			end
			return rejection
		end
	end

	return Stub
end

function RejectionStubs.build(defects: Defects): Bundle
	return {
		Schema = Schema,
		Remotes = Remotes,
		Wrapper = makeWrapperModule(defects),
		RateLimiter = RateLimiter,
		RejectionReporter = makeReporterModule(defects),
		-- TEL-001's reference Event, which knows `remote_rejected` (D1): what
		-- the real `Event` will know once GREEN adds the operational entry.
		Event = TelemetryStubs.correctEvent,
	}
end

-- The baseline, and every control, as ready-made bundles. Each is built fresh
-- on access so that a check's declarations never collide across controls.
function RejectionStubs.correct(): Bundle
	return RejectionStubs.build({})
end

function RejectionStubs.with(defect: string): Bundle
	local defects: { [string]: boolean } = {}
	defects[defect] = true
	return RejectionStubs.build(defects :: any)
end

RejectionStubs.DEFECTS = {
	"unbounded",
	"dropsCount",
	"coalescesAllReasons",
	"perPlayerOnly",
	"perRemoteOnly",
	"strictWindow",
	"flushResetsWindow",
	"flushKeepsPending",
	"flushInInsertionOrder",
	"callerInFields",
	"tableCallerInEnvelope",
	"wrongBucket",
	"ignoresTelemetry",
	"emitsOnAccept",
	"collapsesReason",
	"rawArgsInFields",
	"detailInFields",
	"assumesTelemetry",
	"emitsBareEvent",
	"emitsTwice",
	"stampsZero",
}

return RejectionStubs
