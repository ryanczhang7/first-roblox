--!strict
--[[
	CHAN-003: a call its handler declines costs the attempt floor but not the
	send cooldown. AC-1 through AC-5 and the Contract's promises applied to
	the real `src/net/Wrapper.luau`, `src/net/RateLimiter.luau`,
	`src/net/Remotes.luau` and `src/net/RejectionReporter.luau`, driving the
	real `Schema`.

	EVERY MODULE EXISTS ON ARRIVAL, so every test below LOADS and RUNS and
	fails on its own assertion, each naming the half of the story it is for:

	  * the wrapper hands the handler no third argument, so a handler asked to
	    decline reports "received call = nil" and the call it should have
	    refunded is `rate` on the next call (AC-1, AC-3, AC-4, the Contract's
	    CallControl clauses);
	  * `Remotes.define` does not copy `attemptLimit` and the wrapper builds no
	    attempt limiter, so a second call inside the floor is ACCEPTED (AC-2)
	    and a declaration's `attemptLimit` is nil (Contract);
	  * `RateLimiter.refund` is nil, which the limiter-level checks name by
	    field (AC-3 and the Contract's refund clauses);
	  * a call that reaches stage 5 on a remote declaring both limits still
	    reads the clock once today, because the attempt floor is ignored - so
	    AC-5's clock count is green on arrival for that reason alone and is
	    earned by `readsClockPerLimiter` in the controls suite, where it is the
	    ONLY check that control fails. The same test's verdicts (an
	    attempt-refused call, a declined call) are red on arrival.

	THE CHECKS LIVE IN `tests/helpers/DeclineContract.luau`, and every one of
	them has been OBSERVED to fire in `tests/net/decline_controls_test.luau`
	against the bundle it exists to catch - including the ones the criteria
	and the deferred verifications name: AC-2 against a decline that refunds
	the attempt floor (D-2), AC-3 against a refund that clears the key (D-1),
	the stale-refund clause against a refund without the acceptedAt guard
	(D-3), AC-5 against a wrapper reading the clock once per limiter (D-4).

	NO ROBLOX, NO `Players`, NO ROUND, AND NO REAL TIME. `GuardContext` is
	injected with a counted `Clock.manual`; see the helper's header for why
	AC-3 sets the clock backwards to read the limiter's state.

	AC-5's first half - every existing `tests/net/` suite passes unchanged -
	is the rest of this directory under the same `lune run test`.
]]

local Contract = require("../helpers/DeclineContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/net/Wrapper")
local limiterLoaded, limiterResult = pcall(require, "../../src/net/RateLimiter")
local reporterLoaded, reporterResult = pcall(require, "../../src/net/RejectionReporter")

local function bundle(): Contract.Bundle
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	assert(wrapperLoaded, `src/net/Wrapper.luau did not load: {tostring(wrapperResult)}`)
	assert(limiterLoaded, `src/net/RateLimiter.luau did not load: {tostring(limiterResult)}`)
	assert(
		reporterLoaded,
		`src/net/RejectionReporter.luau did not load: {tostring(reporterResult)}`
	)
	return {
		Schema = schemaResult,
		Remotes = remotesResult,
		Wrapper = wrapperResult,
		RateLimiter = limiterResult,
		RejectionReporter = reporterResult,
	}
end

return {
	--[[ AC-1 ]]

	["AC-1: a send-limited remote whose handler declines the call at t accepts the same player at t + 1.1, well inside the 10 s send limit, and the control - the same sequence with nothing declined - is rate on the second call"] = function()
		Contract.declinedCallDoesNotCostTheSendLimit(bundle())
	end,

	--[[ AC-2 ]]

	["AC-2: on a remote declaring attemptLimit 1 s and rateLimit 10 s, a second call at t + 0.9 is rate with exactly '\"<name>\" is limited to one attempt per 1 s per player' whether the first was declined or kept; at t + 1 it is rate with the send sentence, and the attempt acceptance that refused call made still stands at t + 1.1"] = function()
		Contract.attemptFloorIsNeverRefunded(bundle())
	end,

	["Contract (step 1): when the attempt floor refuses, the send limiter is not consulted and records nothing - after a decline at t and a floor refusal at t + 0.5, the call at t + 1.5 is accepted"] = function()
		Contract.sendLimiterIsNotConsultedWhenTheAttemptFloorRefuses(bundle())
	end,

	--[[ AC-3 ]]

	["AC-3: after an acceptance at t0 and a call at t1 = t0 + 10 accepted then declined, the send limiter holds t0 again - a call at t0 + 9.9 is refused and one at t0 + 10 is allowed"] = function()
		Contract.refundRestoresThePreviousAcceptance(bundle())
	end,

	["AC-3 (limiter): RateLimiter.refund(p, k, t1) after acceptances at t0 and t1 puts the key back to t0 - t0 + 9.9 refused, t0 + 10 allowed - and a second refund of t1, or a refund of an instant never accepted, is a no-op that leaves t0 in place"] = function()
		Contract.refundRestoresTheAcceptanceBeforeItOnTheLimiter(bundle())
	end,

	["Contract (stale refund): after acceptances at t0, t1 and t2, refund(p, k, t1) is a no-op - the key still holds t2 and t2 + 9.9 is refused"] = function()
		Contract.refundOfAStaleAcceptanceIsANoOp(bundle())
	end,

	["Contract (empty entry): refunding a player's only acceptance removes the key and the player - size() drops to 0 and the same instant is allowed again - while a player holding another key, or another player, stays held"] = function()
		Contract.refundOfAPlayersOnlyAcceptanceRemovesThePlayer(bundle())
	end,

	["Contract (unknown refund): refund for a stranger, an unused key or an instant that was never accepted is a no-op and never raises, and the state it names nothing in is unchanged"] = function()
		Contract.refundOfAnUnknownPlayerOrKeyNeverRaises(bundle())
	end,

	--[[ AC-4 ]]

	['AC-4: a declining handler makes the wrapper return exactly { reason = "declined", detail = \'"<name>" declined the call\' } - with a send limit, with both limits, with the attempt floor alone and with neither - and the handler\'s third argument is a CallControl with a decline function'] = function()
		Contract.declinedCallReturnsADeclinedRejection(bundle())
	end,

	['AC-4 (telemetry): a declined call calls reporter:record(playerId, remoteName, "declined", now) once and emit({ event }) once, and through the real RejectionReporter five declines at one instant are five remote_rejected events of count 1 with nothing left to flush'] = function()
		Contract.declinedIsRecordedLikeAnyOtherReason(bundle())
	end,

	["Contract (fresh call): the two CallControls of two calls are different tables with a decline function, and a call that is never declined returns nil and keeps its acceptance - the next call inside the send limit is rate"] = function()
		Contract.callControlIsFreshPerCallAndAnUndeclinedCallKeepsItsAcceptance(bundle())
	end,

	["Contract (decline twice): a call declined twice is declined once - after an acceptance at t0 the key holds t0, not nothing, and t0 + 9.9 is still refused"] = function()
		Contract.decliningTwiceIsANoOpTheSecondTime(bundle())
	end,

	["Contract (late decline): decline() after the wrapper returned still refunds - a call 5 s after the kept-and-declined t1 is accepted - and records and emits nothing"] = function()
		Contract.declineAfterTheWrapperReturnedStillRefundsAndEmitsNothing(bundle())
	end,

	--[[ AC-5 ]]

	["AC-5: a call reaching stage 5 reads context.clock.now() exactly once on a remote declaring both limits, the send limit alone or the attempt floor alone - accepted, attempt-refused, send-refused or declined - and a remote declaring neither reads it zero times across guard() and fifty calls"] = function()
		Contract.stageFiveReadsTheClockExactlyOnce(bundle())
	end,

	["Contract (define): Remotes.define copies attemptLimit as given, alongside rateLimit, and a declaration without one has attemptLimit = nil"] = function()
		Contract.defineCopiesTheAttemptLimit(bundle())
	end,
}
