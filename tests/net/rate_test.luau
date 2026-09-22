--!strict
--[[
	NET-003: per-player rate limiting, position 5 of the fixed check order.
	AC-1 through AC-6 applied to the real `src/net/Wrapper.luau` and the new
	`src/net/RateLimiter.luau`, driving the real `Schema` and `Remotes` - the
	level at which the contract between them lives, so the level at which the
	flooded-call cases are asserted.

	THREE OF THE FOUR MODULES EXIST ON ARRIVAL: `src/net/` was built by
	NET-001 and NET-002 and declares `rateLimit` without reading it, so the
	wrapper-level tests below LOAD and RUN, and the ones that fail do so on
	their own assertion - "the same player at t + 1.4 -> ACCEPTED (returned
	nil)" - not on a missing import. `src/net/RateLimiter.luau` does NOT
	exist on arrival, and AC-6 is the one test that needs it: it is a unit
	criterion on the limiter, and its first assertion says so by name. The
	one wrapper test that passes on arrival (AC-4: no rateLimit, every call
	accepted, no clock read - what the wrapper does today for every remote)
	is earned by the controls suite: a wrapper that limits every remote fails
	AC-4 there and nowhere else among this story's checks, and one that
	rejects everything fails AC-1's first call.

	THE CHECKS LIVE IN `tests/helpers/RateContract.luau`, and every one of
	them has been OBSERVED to fire in `tests/net/rate_controls_test.luau`
	against the bundle it exists to catch - including the ones the criteria
	name: AC-2 against a shared timestamp, AC-3 against a limiter that records
	on rejection, AC-1's boundary against `>`.

	NO ROBLOX, NO `Players`, NO ROUND, AND NO REAL TIME. `GuardContext` is
	injected; `RateContract.world` builds one whose clock is `Clock.manual`
	with its reads counted. Every timed sequence here is a series of
	`clock:set` calls, so a hundred calls at 10 ms is instant.
]]

local Contract = require("../helpers/RateContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/net/Wrapper")
local limiterLoaded, limiterResult = pcall(require, "../../src/net/RateLimiter")

-- The three NET-001 modules are required for every check; `RateLimiter` is
-- carried as nil until GREEN writes it, so a wrapper-level test fails on its
-- own assertion rather than on the module AC-6 alone needs.
local function net(): Contract.Net
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	assert(wrapperLoaded, `src/net/Wrapper.luau did not load: {tostring(wrapperResult)}`)
	return {
		Schema = schemaResult,
		Remotes = remotesResult,
		Wrapper = wrapperResult,
		RateLimiter = if limiterLoaded then limiterResult else nil,
	}
end

return {
	--[[ AC-1 ]]

	["AC-1: a remote at minIntervalSeconds = 1.5 accepts a seated player at t, rejects the same player for rate at t + 1.4, and accepts them at exactly t + 1.5 - the comparison is inclusive"] = function()
		Contract.acceptsAtTheIntervalAndRejectsInsideIt(net())
	end,

	--[[ AC-2 ]]

	["AC-2: while player A is rate-limited, player B's call at the same instant is accepted, and each is then held to their own interval - one shared timestamp fails here"] = function()
		Contract.playersAreLimitedIndependently(net())
	end,

	--[[ AC-3 ]]

	["AC-3: the interval is measured from the last ACCEPTED call - a player rejected at t + 0.5, 1.0 and 1.4 is accepted at t + 1.6, and 320 calls at 10 ms after an acceptance are served exactly twice, not locked out"] = function()
		Contract.intervalIsMeasuredFromTheLastAcceptedCall(net())
	end,

	--[[ AC-4 ]]

	["AC-4: a remote declared with no rateLimit accepts fifty calls at one instant, runs the handler fifty times, and never reads context.clock.now() - not during guard() and not during any call"] = function()
		Contract.remoteWithoutRateLimitIsNeverLimited(net())
	end,

	--[[ AC-5 ]]

	["AC-5: calls rejected for identity, shape, range or phase read the clock zero times and do not advance the player's timestamp - a valid call 2.0 s later is accepted, an out-of-phase call outside the interval advances nothing, and a call 0.5 s after an acceptance is rate"] = function()
		Contract.earlierRejectionsDoNotAdvanceTheLimiter(net())
	end,

	--[[ AC-6 ]]

	["AC-6: RateLimiter.new(1.5) holds one entry per PLAYER across keys, forget removes the whole entry so the player is new again, forgetting a stranger is a no-op, and size() equals the seated count through a round of eight joins and eight leaves"] = function()
		Contract.forgetRemovesThePlayerAndSizeCountsSeatedPlayers(net())
	end,

	--[[ The Contract's own promises ]]

	["Contract: a rate rejection's detail is non-empty, names the remote and carries 1.5, and does not lead with a rate: prefix"] = function()
		Contract.rateRejectionDetailNamesTheRemoteAndTheInterval(net())
	end,

	["Contract: context.clock.now() is read zero times on a call identity, shape, range or phase rejected, at least once on a call that reaches check 5, and the value compared is the one that call returned"] = function()
		Contract.clockIsReadOnlyByCallsThatReachTheRateCheck(net())
	end,
}
