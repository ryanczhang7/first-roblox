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
	    4. phase    - NET-002
	    5. rate     - NET-003

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

	THE CONTEXT IS INJECTED - no `Players`, no RemoteEvent, no `game`, no
	clock read here - which is what lets the whole pipeline be tested with none
	of them. `phase` and `clock` are carried unread; NET-002 and NET-003 are
	the stories that consume them.

	`PlayerId` and `Phase` are re-declared rather than imported, per
	`architecture.md` section 1: `src/net/` may not require `src/server/`, and
	there is no alias that would spell it. `Clock` comes from `@shared/Clock`,
	which is the permitted direction.
]]

local Clock = require("@shared/Clock")
local Remotes = require("./Remotes")

local Wrapper = {}

export type PlayerId = string

export type Rejection = {
	reason: "identity" | "shape" | "range" | "phase" | "rate",
	detail: string,
}

export type GuardContext = {
	isSeated: (playerId: PlayerId) -> boolean,
	phase: () -> Remotes.Phase, -- consumed by NET-002
	clock: Clock.Clock, -- consumed by NET-003
}

type Reason = "identity" | "shape" | "range" | "phase" | "rate"

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
	Wraps `handler` in the validation pipeline declared by `definition`.

	The returned function is what a driver connects to a RemoteEvent. It takes
	the caller id and the single raw payload, and returns nil or a `Rejection`.
]]
function Wrapper.guard(
	definition: Remotes.RemoteDefinition,
	context: GuardContext,
	handler: (playerId: PlayerId, args: any) -> ()
): (playerId: PlayerId, rawArgs: any) -> Rejection?
	return function(playerId: PlayerId, rawArgs: any): Rejection?
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

		handler(playerId, rawArgs)
		return nil
	end
end

return Wrapper
