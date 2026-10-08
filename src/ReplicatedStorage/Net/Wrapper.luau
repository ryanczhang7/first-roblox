--!strict
--[[
	NET-001: the server-side validation wrapper every remote call passes
	through. `guard` takes a declaration, a context and a handler, and returns
	the function a driver connects: it answers `nil` when the call was accepted
	and the handler ran, and a `Rejection` naming the check that fired
	otherwise.

	THE CHECK ORDER IS FIXED and first failure wins (AC-6):

	    1. identity - is the sender a seated player in this round?
	    2. shape    - arity and types
	    3. range    - numeric domains
	    4. phase    - is the action legal in the round's current phase?
	    5. rate     - has this player called this remote too recently?
	                  First the attempt floor (`attemptLimit`), then the send
	                  limit (`rateLimit`); a refusal by the first never
	                  consults the second.

	So an unseated player sending a malformed payload is rejected for
	`identity`, and nothing after the failed check runs - the schema is not
	even consulted. Reordering needs an `## Amendments` entry: TEL-003 emits
	the reason, and a reason that moves makes every historical exploit metric
	incomparable.

	`shape` VERSUS `range` IS THE SCHEMA CALL, not this module. The `Schema`
	type is structural, so `args` may be any table with a `validate`, and the
	protocol is the failure string: it leads with the kind, and the wrapper
	relays it faithfully rather than re-deriving it.

	IT NEVER RAISES. An exploiter must not be able to error a server thread by
	sending a table where a number belongs, a function, a thread, a 100 KB
	string or a 40-deep table. Validation runs under `pcall` so that even a
	hand-written schema that raises becomes a rejection rather than an error on
	the caller thread. The handler is NOT wrapped: containing a handler error
	is a driver concern and this story does not claim it.

	THE CONTEXT IS INJECTED - no `Players`, no RemoteEvent, no `game`, no real
	clock read here - which is what lets the whole pipeline be tested with none
	of them. `phase` is read once per guarded call that reaches check 4 and
	`clock.now()` once per call that reaches check 5 (see below); neither is
	read by a call an earlier check has already rejected, and neither is read
	at construction. The one exception is TEL-003's: with `telemetry` in the
	context, a REJECTED call reads the clock to stamp its event.

	A HANDLER MAY DECLINE THE CALL (CHAN-003, `architecture.md` D18). The rate
	stage runs before the handler, so by the time a handler learns that a
	call is not a send - a ping refused for its target, a preset refused by
	its own phase list, a filter that failed - the send limit has already
	recorded it. So the handler is given a fresh `CallControl` per call, and
	`call.decline()` refunds the SEND limiter's acceptance at this call's own
	`now`, if it made one. The attempt floor is never refunded: it is what
	keeps a declined flood rate-limited once refunds exist. A decline during
	the handler - including after the handler yielded, since this call is
	still waiting on it - makes the result `declined`, which is recorded like
	every other rejection. A decline after this call has returned still
	refunds, and changes nothing else, because the result has already gone.
	Declining twice is a no-op the second time.

	`PlayerId` and `Phase` are re-declared rather than imported, per
	`architecture.md` section 1: `src/ReplicatedStorage/Net/` may not require `src/server/`, and
	there is no alias that would spell it. `Clock` comes from `@game/ReplicatedStorage/Shared/Clock`,
	which is the permitted direction.
]]

local Clock = require("@game/ReplicatedStorage/Shared/Clock")
local Event = require("@game/ReplicatedStorage/Shared/telemetry/Event")
local RateLimiter = require("./RateLimiter")
local RejectionReporter = require("./RejectionReporter")
local Remotes = require("./Remotes")

local Wrapper = {}

export type PlayerId = string

export type Rejection = {
	reason: "identity" | "shape" | "range" | "phase" | "rate" | "declined",
	detail: string,
}

-- CHAN-003. Handed to the handler as its third argument, fresh per call.
export type CallControl = { decline: () -> () }

export type GuardContext = {
	isSeated: (playerId: PlayerId) -> boolean,
	phase: () -> Remotes.Phase, -- consumed by NET-002
	clock: Clock.Clock, -- consumed by NET-003
	-- TEL-003. The driver's reporter, shared across every remote it guards
	-- (the driver flushes it), and a batch emitter - expected to be
	-- `Sink.dispatch`, which is what contains a raising sink. nil: nothing is
	-- recorded or emitted.
	telemetry: {
		reporter: RejectionReporter.RejectionReporter,
		emit: ({ Event.TelemetryEvent }) -> (),
	}?,
}

type Reason = "identity" | "shape" | "range" | "phase" | "rate" | "declined"

--[[
	A caller id in a rejection detail. The parameter is typed `PlayerId`, but
	the value arrives from the wire: an exploiter can send a table, a number or
	nothing at all, so this never assumes it is a string.
]]
local function describeCaller(playerId: any): string
	if typeof(playerId) == "string" then
		return `player "{playerId}"`
	end
	return `a caller sending {typeof(playerId)} as a player id`
end

--[[
	The legal phases of a declaration, as a comma-separated list for a
	rejection detail. Copied into a `{ string }` rather than concatenated in
	place: `legalPhases` is a `{ Phase }`, and the copy is what makes the
	widening to `string` explicit under `--!strict`.
]]
local function describePhases(phases: { Remotes.Phase }): string
	local names: { string } = {}
	for _, phase in phases do
		table.insert(names, phase)
	end
	return table.concat(names, ", ")
end

--[[
	Wraps `handler` in the validation pipeline declared by `definition`.

	The returned function is what a driver connects to a RemoteEvent. It takes
	the caller id and the single raw payload, and returns nil or a `Rejection`.
]]
function Wrapper.guard(
	definition: Remotes.RemoteDefinition,
	context: GuardContext,
	handler: (playerId: PlayerId, args: any, call: CallControl) -> ()
): (playerId: PlayerId, rawArgs: any) -> Rejection?
	-- ONE LIMITER PER `guard()` CALL AND PER LIMIT, here in the enclosing
	-- scope of the returned closure rather than inside it: a limiter built per
	-- call would be new every time and could never refuse anything. Each is
	-- built when and only when the remote declares its limit - a remote that
	-- declares neither gets no limiter, never consults the clock, and is
	-- never limited (AC-4). No clock is read here; the value compared is the
	-- one the call itself reads.
	local rateLimit = definition.rateLimit
	local limiter = if rateLimit ~= nil then RateLimiter.new(rateLimit.minIntervalSeconds) else nil
	local attemptLimit = definition.attemptLimit
	local attemptLimiter = if attemptLimit ~= nil
		then RateLimiter.new(attemptLimit.minIntervalSeconds)
		else nil

	local function check(playerId: PlayerId, rawArgs: any): Rejection?
		-- 1. identity. First, and short-circuiting: an unseated caller never
		-- reaches the schema, so a malformed payload from one is `identity`.
		if context.isSeated(playerId) ~= true then
			local rejection: Rejection = {
				reason = "identity",
				detail = `{describeCaller(playerId)} is not seated in the current round`,
			}
			return rejection
		end

		-- 2 and 3. shape then range, both inside `validate`: the schema runs
		-- its structural pass over the whole payload before its domain pass
		-- over any of it, so a structural failure anywhere wins.
		local ok, accepted, failure = pcall(definition.args.validate, rawArgs)
		if not ok then
			local rejection: Rejection = {
				reason = "shape",
				detail = `the schema for "{definition.name}" raised: {tostring(accepted)}`,
			}
			return rejection
		end

		if accepted ~= true then
			local detail = "the schema rejected the payload without naming a check"
			if typeof(failure) == "string" and failure ~= "" then
				detail = failure :: string
			end
			-- The kind LEADS the failure string. Anchored at the start, because
			-- a substring search would be a needle whose negation also matches.
			local reason: Reason = "shape"
			if string.match(detail, "^(%l+):") == "range" then
				reason = "range"
			end
			local rejection: Rejection = { reason = reason, detail = detail }
			return rejection
		end

		-- 4. phase (NET-002). READ AT THE MOMENT OF THE CALL, not when `guard`
		-- was called: a guarded function outlives the phase it was built in,
		-- and a phase captured at construction would accept a call the round
		-- has already moved past. The read happens HERE and not earlier, so a
		-- call identity, shape or range has already rejected never asks the
		-- context for the phase - first failure wins, as it does above.
		local currentPhase = context.phase()
		if table.find(definition.legalPhases, currentPhase) == nil then
			-- No `"phase: "` prefix: `reason` already names the check, and a
			-- second encoding is one a later refactor can let drift. The
			-- detail carries both halves an operator needs - the phase that
			-- was current and every phase that was legal - and no other.
			local legal = describePhases(definition.legalPhases)
			local rejection: Rejection = {
				reason = "phase",
				detail = `the phase is {currentPhase}; legal in {legal}`,
			}
			return rejection
		end

		-- 5. rate (NET-003). LAST, so a malformed or out-of-phase flood is
		-- rejected for what it is and never consumes the caller's own budget
		-- (AC-5) - and so TEL-003 counts it as malformed rather than losing it
		-- behind a rate rejection. The clock is read HERE, at the moment of
		-- the call: a value captured when `guard` was called sees zero seconds
		-- elapsed forever and refuses every call after the first.
		-- The clock is read ONCE, and that one value serves both limiters and
		-- the refund (CHAN-003): a second read would let the two limits
		-- judge one call at two instants.
		local now: number? = nil
		if limiter ~= nil or attemptLimiter ~= nil then
			now = context.clock.now()
		end

		-- The attempt floor first. A refusal here is not recorded in the
		-- send limiter, which is never consulted.
		if attemptLimiter ~= nil and attemptLimit ~= nil and now ~= nil then
			if attemptLimiter:allow(playerId, definition.name, now) ~= true then
				local rejection: Rejection = {
					reason = "rate",
					detail = `"{definition.name}" is limited to one attempt per `
						.. `{attemptLimit.minIntervalSeconds} s per player`,
				}
				return rejection
			end
		end

		-- Then the send limit. The attempt acceptance above stands when this
		-- refuses: the floor is never refunded.
		local sentAt: number? = nil
		if limiter ~= nil and rateLimit ~= nil and now ~= nil then
			if limiter:allow(playerId, definition.name, now) ~= true then
				-- No `"rate: "` prefix, for the reason the phase detail gives
				-- above. What an operator reading a spike needs is the remote
				-- and the interval it is held to; how long this caller
				-- actually waited is deliberately left out, being a float
				-- difference whose formatting would pin a rounding error.
				local rejection: Rejection = {
					reason = "rate",
					detail = `"{definition.name}" is limited to one call per `
						.. `{rateLimit.minIntervalSeconds} s per player`,
				}
				return rejection
			end
			sentAt = now
		end

		-- A fresh control per call, closing over THIS call's acceptance. Only
		-- the send limiter is refunded, and only once.
		local declined = false
		local call: CallControl = {
			decline = function()
				if declined then
					return
				end
				declined = true
				if limiter ~= nil and sentAt ~= nil then
					limiter:refund(playerId, definition.name, sentAt)
				end
			end,
		}

		handler(playerId, rawArgs, call)
		-- Read once the handler has returned: a decline after this point
		-- refunds, but the result has already gone.
		if declined then
			local rejection: Rejection = {
				reason = "declined",
				detail = `"{definition.name}" declined the call`,
			}
			return rejection
		end
		return nil
	end

	-- TEL-003. Every rejection, and only a rejection, is recorded, and the
	-- event the reporter answers with (a coalesced `rate` rejection answers
	-- nil) is emitted before the Rejection is returned. The arguments and the
	-- detail are never passed on: both can quote hostile input (AC-4). The
	-- clock is read for the stamp only when `telemetry` is present, so a
	-- context without it reads the clock exactly as NET-003 pins.
	return function(playerId: PlayerId, rawArgs: any): Rejection?
		local rejection = check(playerId, rawArgs)
		local telemetry = context.telemetry
		if rejection ~= nil and telemetry ~= nil then
			local event = telemetry.reporter:record(
				playerId,
				definition.name,
				rejection.reason,
				context.clock.now()
			)
			if event ~= nil then
				telemetry.emit({ event })
			end
		end
		return rejection
	end
end

return Wrapper
