--!strict
--[[
	NET-003: the per-player minimum-interval limiter behind check 5 of
	`Wrapper.guard`'s fixed order.

	IT NEVER READS A CLOCK. `now` is a parameter, so the whole of it is tested
	in simulated time and a flood of a hundred calls a second is an instant
	test rather than a sleeping one. `ROUND-001`'s source guard enumerates
	`src/` through the classifier and refuses `os.clock`, `tick` and
	`math.random` here, which is the mechanical half of the same rule.

	ONE ENTRY PER PLAYER, holding a timestamp per key:

	    entries: { [PlayerId]: { [string]: number } }

	so `size()` counts PLAYERS and not `(player, key)` pairs, and `forget`
	drops a player's whole entry. AC-6 is phrased against this shape: "the
	stored entry count after a full round of joins and leaves equals the number
	of currently seated players" is true under it whatever mix of remotes each
	player called, and false under a pair-keyed table for anyone who used two.
	A leaver stops existing, and "per remote" is not a question anyone asks
	about a player who has gone.

	THE TIMESTAMP MOVES ON ACCEPTANCE ALONE (AC-3). A limiter that recorded
	the rejected call too would lock a caller at 100 Hz out forever instead of
	serving them once per interval - a rate limit turned into a self-inflicted
	denial of service, and a bug that only appears under the load the module
	exists for. `entries[playerId]` is assigned on the accepting path only, so
	that is a property of the control flow rather than of a comment.

	THE COMPARISON IS INCLUSIVE: `now - lastAccepted >= minIntervalSeconds`.
	Exactly at the interval the call goes through.

	`PlayerId` IS RE-DECLARED rather than imported from `Wrapper`: `Wrapper`
	requires this module, and the reverse edge would be a cycle. It is the same
	string alias. `minIntervalSeconds` arrives from the remote's own
	declaration (`tuning.md` §3's `signal_rate_limit_seconds`, derived) and is
	never read out of `src/shared/Tuning.luau`, whose scope is §1 and §5.
]]

local RateLimiter = {}

export type PlayerId = string

export type RateLimiter = {
	allow: (self: RateLimiter, playerId: PlayerId, key: string, now: number) -> boolean,
	forget: (self: RateLimiter, playerId: PlayerId) -> (),
	size: (self: RateLimiter) -> number,
}

--[[
	A limiter permitting one call per `minIntervalSeconds` per player per key.

	The state is a closure upvalue rather than a field, so nothing a caller is
	handed can reach in and move a timestamp.
]]
function RateLimiter.new(minIntervalSeconds: number): RateLimiter
	local entries: { [PlayerId]: { [string]: number } } = {}

	local limiter: RateLimiter = {
		--[[
			True when this player has never been served on this key, or when at
			least `minIntervalSeconds` have passed since the last call that was
			ACCEPTED. Records `now` only on the true path.
		]]
		allow = function(_self: RateLimiter, playerId: PlayerId, key: string, now: number): boolean
			local keys: { [string]: number } = entries[playerId] or {}
			local lastAccepted = keys[key]
			if lastAccepted ~= nil and now - lastAccepted < minIntervalSeconds then
				return false
			end
			keys[key] = now
			entries[playerId] = keys
			return true
		end,

		--[[
			Drops the player's whole entry, every key with it, so their next
			call at any `now` - including the instant they were just refused -
			is allowed. A player the limiter never saw is a no-op and not a
			raise: a disconnect arrives for players who never called anything.
		]]
		forget = function(_self: RateLimiter, playerId: PlayerId)
			entries[playerId] = nil
		end,

		--[[
			The number of PLAYERS held. Counted by walking the table rather
			than kept in a parallel counter: a counter is a second place the
			truth lives, and AC-6 is precisely the criterion a counter that
			drifts from the table would satisfy while the table leaked.
		]]
		size = function(_self: RateLimiter): number
			local held = 0
			for _ in entries do
				held += 1
			end
			return held
		end,
	}

	return limiter
end

return RateLimiter
