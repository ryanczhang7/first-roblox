--!strict
--[[
	The wrong telemetry modules TEL-001's controls are aimed at, and the one
	baseline each of them is a single defect away from.

	THREE CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-3: "an implementation
	that defaults an unknown name to D1 must fail this". AC-5: "an
	implementation that lets the error propagate must fail this; one that
	swallows it with no count must fail the counted half". The rest are the
	mutations the story's `## Notes` asks the orchestrator to run at acceptance
	(`purchase` removed from `BUCKETS`) and the one-defect modules the
	remaining criteria would otherwise have no control for.

	It is a FACTORY over a table of defects, as `ProjectionStubs.luau` is, so
	that `defects` is empty for the baseline and has exactly ONE field set for
	every control: a control that fires is then attributable to that one field.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/shared/telemetry/` and
	not a sketch of it. The baseline is the Contract only as far as the checks
	can see - every type is `any`, and its error messages are whatever fell
	out. GREEN writes the modules from the story's `## Contract`, against the
	failing tests in `tests/shared/telemetry_event_test.luau` and
	`tests/shared/telemetry_sink_test.luau`; nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/shared/telemetry_controls_test.luau` records
	what each one actually did.
]]

local TelemetryStubs = {}

--[[
	One field per Event control, each a single edit to the module below.

	  * `defaultUnknownToD1`  - an unknown name gets bucket "D1" instead of a
	                            refusal (AC-3's control; mutation 1 of `## Notes`)
	  * `missingPurchase`     - `purchase` absent from BUCKETS (AC-2; mutation 3)
	  * `extraTenthEvent`     - a tenth, invented `level_up = "D1"` (AC-2, the
	                            other direction)
	  * `bounceInD2_7`        - `bounce_before_resolution` filed under D2_7
	                            (AC-2, the one event the story says to get right)
	  * `unfrozenBuckets`     - BUCKETS is a plain writable table (AC-2, frozen)
	  * `acceptNestedTable`   - a table value in `fields` is carried as-is (AC-6)
	  * `refuseWithoutKey`    - a non-scalar is refused, but the message names no
	                            key (AC-6, "naming the offending key")
	  * `atIsZero`            - `at` is 0 whatever was passed (AC-1)
]]
export type EventDefects = {
	defaultUnknownToD1: boolean?,
	missingPurchase: boolean?,
	extraTenthEvent: boolean?,
	bounceInD2_7: boolean?,
	unfrozenBuckets: boolean?,
	acceptNestedTable: boolean?,
	refuseWithoutKey: boolean?,
	atIsZero: boolean?,
}

local SCALAR: { [string]: boolean } = { string = true, number = true, boolean = true }

function TelemetryStubs.makeEvent(defects: EventDefects): any
	local buckets: { [string]: string } = {
		join = "D1",
		first_round_complete = "D1",
		bounce_before_resolution = if defects.bounceInD2_7 then "D2_7" else "D1",
		session_end = "D1",
		round_complete = "D2_7",
		rematch_accepted = "D2_7",
		day_n_return = "D8_28",
		co_play_with_known_player = "D8_28",
		purchase = "D8_28",
	}
	if defects.missingPurchase then
		buckets.purchase = nil
	end
	if defects.extraTenthEvent then
		buckets.level_up = "D1"
	end

	local Event = {}
	Event.BUCKETS = if defects.unfrozenBuckets then buckets else table.freeze(buckets)

	Event.new = function(name: any, at: any, sessionId: any, playerId: any, fields: any): any
		local bucket = buckets[name]
		if bucket == nil then
			if defects.defaultUnknownToD1 then
				bucket = "D1"
			else
				error(`TelemetryStubs.Event.new: "{tostring(name)}" is not a B6 event`, 2)
			end
		end

		local copied: { [string]: any } = {}
		for key, value in pairs((fields or {}) :: { [any]: any }) do
			local kind = typeof(value)
			local allowed = SCALAR[kind] or (defects.acceptNestedTable and kind == "table")
			if not allowed then
				if defects.refuseWithoutKey then
					error(
						"TelemetryStubs.Event.new: a field value is not a string, number or boolean",
						2
					)
				end
				error(
					`TelemetryStubs.Event.new: field "{tostring(key)}" is a {kind}, not a string, `
						.. `number or boolean`,
					2
				)
			end
			copied[key] = value
		end

		return {
			name = name,
			at = if defects.atIsZero then 0 else at,
			bucket = bucket,
			sessionId = sessionId,
			playerId = playerId,
			fields = copied,
		}
	end

	return Event
end

--[[
	One field per Sink control.

	  * `propagateEmitError`     - dispatch calls emit bare; a raise reaches the
	                               caller (AC-5's first control)
	  * `countRaiseAsDelivered`  - dispatch isolates emit but counts a raise as
	                               delivered, dropped stays 0 (AC-5's second
	                               control; mutation 2 of `## Notes`)
	  * `stopAtFirstError`       - dispatch isolates emit, counts the first raise
	                               as a drop, and returns without attempting the
	                               rest (AC-5, "isolates each emit")
	  * `recordingOutOfOrder`    - the recording sink prepends (AC-4, "in order")
	  * `recordingDropsFields`   - the recording sink stores the envelope without
	                               `fields` (AC-4, "fields intact")
]]
export type SinkDefects = {
	propagateEmitError: boolean?,
	countRaiseAsDelivered: boolean?,
	stopAtFirstError: boolean?,
	recordingOutOfOrder: boolean?,
	recordingDropsFields: boolean?,
}

function TelemetryStubs.makeSink(defects: SinkDefects): any
	local Sink = {}

	Sink.noop = function(): any
		return {
			emit = function(_event: any) end,
		}
	end

	Sink.recording = function(): any
		local sink: any = { events = {} }
		sink.emit = function(event: any)
			local stored = event
			if defects.recordingDropsFields then
				stored = {
					name = event.name,
					at = event.at,
					bucket = event.bucket,
					sessionId = event.sessionId,
					playerId = event.playerId,
				}
			end
			if defects.recordingOutOfOrder then
				table.insert(sink.events, 1, stored)
			else
				table.insert(sink.events, stored)
			end
		end
		sink.clear = function(self: any)
			table.clear(self.events)
		end
		return sink
	end

	Sink.dispatch = function(sink: any, events: { any }): any
		local delivered, dropped = 0, 0
		for _, event in events do
			if defects.propagateEmitError then
				sink.emit(event)
				delivered += 1
				continue
			end
			local ok = pcall(sink.emit, event)
			if ok or defects.countRaiseAsDelivered then
				delivered += 1
			elseif defects.stopAtFirstError then
				dropped += 1
				break
			else
				dropped += 1
			end
		end
		return { delivered = delivered, dropped = dropped }
	end

	return Sink
end

TelemetryStubs.correctEvent = TelemetryStubs.makeEvent({})
TelemetryStubs.defaultUnknownToD1 = TelemetryStubs.makeEvent({ defaultUnknownToD1 = true })
TelemetryStubs.missingPurchase = TelemetryStubs.makeEvent({ missingPurchase = true })
TelemetryStubs.extraTenthEvent = TelemetryStubs.makeEvent({ extraTenthEvent = true })
TelemetryStubs.bounceInD2_7 = TelemetryStubs.makeEvent({ bounceInD2_7 = true })
TelemetryStubs.unfrozenBuckets = TelemetryStubs.makeEvent({ unfrozenBuckets = true })
TelemetryStubs.acceptNestedTable = TelemetryStubs.makeEvent({ acceptNestedTable = true })
TelemetryStubs.refuseWithoutKey = TelemetryStubs.makeEvent({ refuseWithoutKey = true })
TelemetryStubs.atIsZero = TelemetryStubs.makeEvent({ atIsZero = true })

TelemetryStubs.correctSink = TelemetryStubs.makeSink({})
TelemetryStubs.propagateEmitError = TelemetryStubs.makeSink({ propagateEmitError = true })
TelemetryStubs.countRaiseAsDelivered = TelemetryStubs.makeSink({ countRaiseAsDelivered = true })
TelemetryStubs.stopAtFirstError = TelemetryStubs.makeSink({ stopAtFirstError = true })
TelemetryStubs.recordingOutOfOrder = TelemetryStubs.makeSink({ recordingOutOfOrder = true })
TelemetryStubs.recordingDropsFields = TelemetryStubs.makeSink({ recordingDropsFields = true })

return TelemetryStubs
