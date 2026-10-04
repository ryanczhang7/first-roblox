--!strict
--[[
	The wrong decline-and-refund bundles CHAN-003's controls are aimed at,
	and the one baseline each of them is a single defect away from.

	THE STORY NAMES ITS CONTROLS. AC-1: a handler that does not decline is
	rate on the second call - that one is inside the check itself; the stub
	beside it is a wrapper that returns `declined` without refunding
	(`declineNotRefunded`). AC-2: "an implementation that refunds the attempt
	limit on decline must fail this" - `refundsAttemptToo` (D-2). AC-3: "a
	refund that clears the key instead of restoring t0 must fail this" -
	`refundClearsKey` (D-1). D-3: a refund with the `acceptedAt` guard
	removed - `refundIgnoresAcceptedAt`. D-4: the clock read once per
	limiter - `readsClockPerLimiter`. The rest are one-defect bundles for the
	Contract clauses the remaining checks would otherwise have no control for.

	IT IS A LAYER OVER `PhaseStubs.correct()`, as `RateStubs` is - not a third
	copy of the pipeline. The baseline takes NET-002's correct phase-enforcing
	bundle and wraps ONE export, `Wrapper.guard`, which gains stage 5 with
	TWO limiters, the `CallControl` and the telemetry step, and ADDS one
	export, `RateLimiter`, a stub limiter with one level of refund history.
	`Remotes.define` is wrapped only to copy `attemptLimit`. The real
	`RejectionReporter` is carried as the bundle's reporter: it treats any
	non-rate reason alike, so AC-4's telemetry half needs no stub of it.

	WHAT THIS IS NOT: `src/net/` or a sketch of it. GREEN writes the real
	refund into `RateLimiter.luau` and the real stage 5 into `Wrapper.luau`
	from the story's `## Contract`. Nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/decline_controls_test.luau` records what
	each one actually did.
]]

local PhaseStubs = require("./PhaseStubs")
local RejectionReporter = require("../../src/net/RejectionReporter")

local DeclineStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  Wrapper
	  * `neverPassesCall`            - the handler gets two arguments: the
	                                   pre-CHAN-003 wrapper, and what the
	                                   real suite fails on arrival
	  * `declineNotRefunded`         - decline makes the result `declined`
	                                   but refunds nothing (AC-1)
	  * `refundsAttemptToo`          - decline refunds the attempt limiter as
	                                   well as the send limiter (AC-2; D-2)
	  * `sendBeforeAttempt`          - stage 5 consults the send limiter
	                                   first (AC-2's detail)
	  * `attemptDetailSaysCall`      - the attempt refusal uses the send
	                                   sentence (AC-2's whole-string needle)
	  * `consultsSendWhenAttemptRefuses` - the send limiter is asked, and
	                                   records, on a call the floor refused
	  * `attemptRefundedOnSendRefusal` - the attempt acceptance is unwound
	                                   when the send limiter refuses
	  * `readsClockPerLimiter`       - `context.clock.now()` once per
	                                   limiter (AC-5; D-4)
	  * `declineReturnsNil`          - the refund happens but the result is
	                                   nil (AC-4)
	  * `declinedDetailOmitsName`    - detail is "declined the call"
	  * `declineWithoutSendLimitIgnored` - with no send limiter decline does
	                                   nothing (the result is nil)
	  * `sharedCallControl`          - one CallControl table per guard
	  * `declineAfterReturnIgnored`  - a decline after the wrapper returned
	                                   refunds nothing
	  * `declineAfterReturnEmits`    - a decline after the wrapper returned
	                                   records and emits an event
	  * `declineSkipsTelemetry`      - a declined result is returned without
	                                   the telemetry step (AC-4)
	  Remotes
	  * `defineDropsAttemptLimit`    - define does not copy attemptLimit
	  RateLimiter
	  * `refundClearsKey`            - refund sets the key to nil (AC-3; D-1)
	  * `refundIgnoresAcceptedAt`    - refund unwinds whatever the last
	                                   acceptance was (D-3)
	  * `refundLeavesEmptyPlayer`    - an emptied player entry is kept, so
	                                   size() does not drop
	  * `refundRaisesOnUnknown`      - refund of an unknown player or key
	                                   raises
]]
export type Defects = {
	neverPassesCall: boolean?,
	declineNotRefunded: boolean?,
	refundsAttemptToo: boolean?,
	sendBeforeAttempt: boolean?,
	attemptDetailSaysCall: boolean?,
	consultsSendWhenAttemptRefuses: boolean?,
	attemptRefundedOnSendRefusal: boolean?,
	readsClockPerLimiter: boolean?,
	declineReturnsNil: boolean?,
	declinedDetailOmitsName: boolean?,
	declineWithoutSendLimitIgnored: boolean?,
	sharedCallControl: boolean?,
	declineAfterReturnIgnored: boolean?,
	declineAfterReturnEmits: boolean?,
	declineSkipsTelemetry: boolean?,
	defineDropsAttemptLimit: boolean?,
	refundClearsKey: boolean?,
	refundIgnoresAcceptedAt: boolean?,
	refundLeavesEmptyPlayer: boolean?,
	refundRaisesOnUnknown: boolean?,
}

export type Bundle = {
	Schema: any,
	Remotes: any,
	Wrapper: any,
	RateLimiter: any,
	RejectionReporter: any,
}

type Slot = { last: number, previous: number? }

function DeclineStubs.build(defects: Defects): Bundle
	local base = PhaseStubs.correct()

	--[[ Remotes ]]

	local Remotes = {}

	function Remotes.define(name: string, spec: any): any
		local definition = base.Remotes.define(name, spec)
		if not defects.defineDropsAttemptLimit then
			definition.attemptLimit = spec.attemptLimit
		end
		return definition
	end

	function Remotes.all(): { any }
		return base.Remotes.all()
	end

	--[[ RateLimiter ]]

	local RateLimiter = {}

	function RateLimiter.new(minIntervalSeconds: number): any
		-- One entry per player, a slot per key: the last acceptance and the
		-- one it overwrote.
		local entries: { [any]: { [string]: Slot } } = {}
		local limiter = {}

		function limiter.allow(_self: any, playerId: any, key: string, now: number): boolean
			local byKey = entries[playerId]
			if byKey == nil then
				byKey = {}
				entries[playerId] = byKey
			end
			local slot = (byKey :: { [string]: Slot })[key]
			if slot ~= nil and now - slot.last < minIntervalSeconds then
				return false
			end
			(byKey :: { [string]: Slot })[key] = {
				last = now,
				previous = if slot ~= nil then slot.last else nil,
			}
			return true
		end

		function limiter.refund(_self: any, playerId: any, key: string, acceptedAt: number)
			local byKey = entries[playerId]
			local slot = if byKey ~= nil then byKey[key] else nil
			if slot == nil then
				if defects.refundRaisesOnUnknown then
					error(`refund: {tostring(playerId)} has no acceptance on {key}`, 2)
				end
				return
			end
			if slot.last ~= acceptedAt and not defects.refundIgnoresAcceptedAt then
				return
			end
			local keys = byKey :: { [string]: Slot }
			if slot.previous == nil or defects.refundClearsKey then
				keys[key] = nil
			else
				keys[key] = { last = slot.previous :: number, previous = nil }
			end
			if next(keys) == nil and not defects.refundLeavesEmptyPlayer then
				entries[playerId] = nil
			end
		end

		function limiter.forget(_self: any, playerId: any)
			entries[playerId] = nil
		end

		function limiter.size(_self: any): number
			local n = 0
			for _ in entries do
				n += 1
			end
			return n
		end

		return limiter
	end

	--[[ Wrapper ]]

	local Wrapper = {}

	function Wrapper.guard(definition: any, context: any, handler: any): any
		local sendLimit = definition.rateLimit
		local attemptLimit = definition.attemptLimit
		local send: any = if sendLimit ~= nil
			then RateLimiter.new(sendLimit.minIntervalSeconds)
			else nil
		local attempt: any = if attemptLimit ~= nil
			then RateLimiter.new(attemptLimit.minIntervalSeconds)
			else nil
		local name = definition.name

		local function sendDetail(): string
			return `"{name}" is limited to one call per {sendLimit.minIntervalSeconds} s per player`
		end

		local function attemptDetail(): string
			if defects.attemptDetailSaysCall then
				return `"{name}" is limited to one call per {attemptLimit.minIntervalSeconds} s per player`
			end
			return `"{name}" is limited to one attempt per {attemptLimit.minIntervalSeconds} s per player`
		end

		local function declinedRejection(): any
			return {
				reason = "declined",
				detail = if defects.declinedDetailOmitsName
					then "declined the call"
					else `"{name}" declined the call`,
			}
		end

		local function report(playerId: any, rejection: any)
			local telemetry = context.telemetry
			if telemetry == nil then
				return
			end
			local event =
				telemetry.reporter:record(playerId, name, rejection.reason, context.clock.now())
			if event ~= nil then
				telemetry.emit({ event })
			end
		end

		-- The shared control under `sharedCallControl`: one table, whose
		-- decline acts on whatever call was last in flight.
		local shared: any = nil
		local sharedDecline: (() -> ())? = nil

		-- `pending` carries stage 5's verdict out of the inner pipeline,
		-- whose handler is where stage 5 runs.
		local pending: any = nil

		local innerContext = table.clone(context)
		innerContext.telemetry = nil

		local inner = base.Wrapper.guard(
			definition,
			innerContext,
			function(playerId: any, args: any)
				-- Stage 5.
				local now: number? = nil
				if send ~= nil or attempt ~= nil then
					now = context.clock.now()
				end
				local function clockFor(): number
					if defects.readsClockPerLimiter then
						return context.clock.now()
					end
					return now :: number
				end

				local attemptNow: number? = nil
				local sendNow: number? = nil

				local function checkAttempt(): boolean
					if attempt == nil then
						return true
					end
					attemptNow = clockFor()
					if attempt:allow(playerId, name, attemptNow) then
						return true
					end
					pending = { reason = "rate", detail = attemptDetail() }
					if defects.consultsSendWhenAttemptRefuses and send ~= nil then
						send:allow(playerId, name, attemptNow)
					end
					return false
				end

				local function checkSend(): boolean
					if send == nil then
						return true
					end
					sendNow = clockFor()
					if send:allow(playerId, name, sendNow) then
						return true
					end
					pending = { reason = "rate", detail = sendDetail() }
					if
						defects.attemptRefundedOnSendRefusal
						and attempt ~= nil
						and attemptNow ~= nil
					then
						attempt:refund(playerId, name, attemptNow)
					end
					return false
				end

				if defects.sendBeforeAttempt then
					if not checkSend() or not checkAttempt() then
						return
					end
				else
					if not checkAttempt() or not checkSend() then
						return
					end
				end

				-- The handler, with its CallControl.
				local declined = false
				local returned = false
				local function decline()
					if declined then
						return
					end
					if returned and defects.declineAfterReturnIgnored then
						return
					end
					if send == nil and defects.declineWithoutSendLimitIgnored then
						return
					end
					if send ~= nil and sendNow ~= nil and not defects.declineNotRefunded then
						send:refund(playerId, name, sendNow)
					end
					if defects.refundsAttemptToo and attempt ~= nil and attemptNow ~= nil then
						attempt:refund(playerId, name, attemptNow)
					end
					local first = not declined
					declined = true
					if returned then
						if defects.declineAfterReturnEmits and first then
							report(playerId, declinedRejection())
						end
						return
					end
					if not defects.declineReturnsNil then
						pending = declinedRejection()
					end
				end

				local control: any
				if defects.sharedCallControl then
					if shared == nil then
						shared = {
							decline = function()
								if sharedDecline ~= nil then
									(sharedDecline :: () -> ())()
								end
							end,
						}
					end
					sharedDecline = decline
					control = shared
				else
					control = { decline = decline }
				end

				if defects.neverPassesCall then
					handler(playerId, args)
				else
					handler(playerId, args, control)
				end
				-- Marked on the way out of stage 5, which is what the wrapper
				-- returning means to the control.
				local function markReturned()
					returned = true
				end
				pending = { verdict = pending, markReturned = markReturned }
			end
		)

		return function(playerId: any, rawArgs: any): any
			pending = nil
			local result = inner(playerId, rawArgs)
			if result ~= nil then
				-- Identity, shape, range or phase: the inner stub's verdict,
				-- reported here because the inner context has no telemetry.
				report(playerId, result)
				return result
			end
			local verdict: any = nil
			if pending ~= nil then
				if pending.markReturned ~= nil then
					verdict = pending.verdict
					pending.markReturned()
				else
					verdict = pending
				end
			end
			if
				verdict ~= nil
				and not (verdict.reason == "declined" and defects.declineSkipsTelemetry)
			then
				report(playerId, verdict)
			end
			return verdict
		end
	end

	return {
		Schema = base.Schema,
		Remotes = Remotes,
		Wrapper = Wrapper,
		RateLimiter = RateLimiter,
		RejectionReporter = RejectionReporter,
	}
end

-- The baseline, and every control, as ready-made bundles. Each is built fresh
-- on access so that a check's declarations never collide across controls.
function DeclineStubs.correct(): Bundle
	return DeclineStubs.build({})
end

function DeclineStubs.with(defect: string): Bundle
	local defects: { [string]: boolean } = {}
	defects[defect] = true
	return DeclineStubs.build(defects :: any)
end

DeclineStubs.DEFECTS = {
	"neverPassesCall",
	"declineNotRefunded",
	"refundsAttemptToo",
	"sendBeforeAttempt",
	"attemptDetailSaysCall",
	"consultsSendWhenAttemptRefuses",
	"attemptRefundedOnSendRefusal",
	"readsClockPerLimiter",
	"declineReturnsNil",
	"declinedDetailOmitsName",
	"declineWithoutSendLimitIgnored",
	"sharedCallControl",
	"declineAfterReturnIgnored",
	"declineAfterReturnEmits",
	"declineSkipsTelemetry",
	"defineDropsAttemptLimit",
	"refundClearsKey",
	"refundIgnoresAcceptedAt",
	"refundLeavesEmptyPlayer",
	"refundRaisesOnUnknown",
}

return DeclineStubs
