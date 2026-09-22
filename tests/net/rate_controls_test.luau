--!strict
--[[
	The negative controls for NET-003, and the proof that each check in
	`tests/helpers/RateContract.luau` refuses the bundle it exists to catch.

	THREE CRITERIA AND ONE CONTRACT BLOCK NAME THEIR CONTROL. AC-2: an
	implementation with one shared last-call timestamp "passes AC-1 and must
	fail this". AC-3: an implementation that updates the timestamp on
	rejection "must fail this". AC-1's boundary: `>` instead of `>=`. AC-6's
	pinned shape: `size()` counting pairs, `forget` a no-op. Each is asserted
	below in exactly those terms - the passes as well as the failure.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, including
	NET-002's eight phase checks and NET-001's twelve wrapper and registry
	checks, which is the half that is easy to leave out and worth the most:
	it shows the rate check is a layer the earlier suites cannot see unless
	it is wrong in a way that is not about timing (limiting a remote that
	declared no limit, rejecting everything), and that a control failing the
	rate checks is a control with ONE defect rather than a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	MEASURED here rather than predicted - measured first outside the runner
	(`## Handoff`), then pinned. Two measurements disagree with the story's
	table and are recorded rather than tuned away: the records-on-reject
	control fails AC-1 as well as AC-3, because AC-1's own three calls
	(rejected at t + 1.4, accepted at t + 1.5) are 0.1 s apart and a limiter
	that recorded the rejection refuses the acceptance; and the
	reject-everything control lives in the wrapper rather than in `allow`,
	because under the Contract's own design a remote with no `rateLimit` has
	no limiter, so an `allow` that is always false could never reach AC-4.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The bundles are
	`RateStubs.luau` over `PhaseStubs.luau` over `NetStubs.luau`, so these
	controls EXECUTE in RED, while `rate_test.luau`'s assertions against the
	real `src/net/` are red on their own terms.
]]

local NetContract = require("../helpers/NetContract")
local PhaseContract = require("../helpers/PhaseContract")
local RateContract = require("../helpers/RateContract")
local Stubs = require("../helpers/RateStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local function accepts(check: Check, subject: any, what: string)
	local ok, err = pcall(check, subject)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, subject: any, what: string): string
	local ok, err = pcall(check, subject)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local function lacks(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) == nil,
		`{what}, but the failure message mentions "{fragment}":\n{message}`
	)
end

local RATE_CHECKS: { Named } = {
	{ label = "AC-1", check = RateContract.acceptsAtTheIntervalAndRejectsInsideIt },
	{ label = "AC-2", check = RateContract.playersAreLimitedIndependently },
	{ label = "AC-3", check = RateContract.intervalIsMeasuredFromTheLastAcceptedCall },
	{ label = "AC-4", check = RateContract.remoteWithoutRateLimitIsNeverLimited },
	{ label = "AC-5", check = RateContract.earlierRejectionsDoNotAdvanceTheLimiter },
	{ label = "AC-6", check = RateContract.forgetRemovesThePlayerAndSizeCountsSeatedPlayers },
	{ label = "detail", check = RateContract.rateRejectionDetailNamesTheRemoteAndTheInterval },
	{ label = "clock", check = RateContract.clockIsReadOnlyByCallsThatReachTheRateCheck },
}

-- NET-002's phase checks, held over every bundle here: the rate layer must be
-- invisible to them unless it limits a remote that declared no limit.
local NET002_CHECKS: { Named } = {
	{ label = "NET-002 AC-1", check = PhaseContract.handlerRunsInTheOnlyLegalPhase },
	{ label = "NET-002 AC-2", check = PhaseContract.outOfPhaseCallIsRejectedForPhase },
	{ label = "NET-002 AC-3", check = PhaseContract.earlierChecksWinOverPhase },
	{
		label = "NET-002 AC-4",
		check = PhaseContract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse,
	},
	{ label = "NET-002 AC-5", check = PhaseContract.emptyLegalPhasesIsADeclarationError },
	{ label = "NET-002 AC-6", check = PhaseContract.phaseIsReadAtTheMomentOfEachCall },
	{
		label = "NET-002 detail",
		check = PhaseContract.phaseRejectionDetailNamesTheCurrentAndEveryLegalPhase,
	},
	{
		label = "NET-002 short-circuit",
		check = PhaseContract.phaseIsNotConsultedWhenAnEarlierCheckFails,
	},
}

-- NET-001's wrapper and registry checks, likewise.
local NET001_CHECKS: { Named } = {
	{ label = "NET-001 AC-1", check = NetContract.handlerRunsExactlyOnceWithTheValidatedArguments },
	{ label = "NET-001 AC-2", check = NetContract.malformedPayloadIsRejectedForShape },
	{ label = "NET-001 AC-3", check = NetContract.outOfRangeNumberIsRejectedForRange },
	{ label = "NET-001 AC-4", check = NetContract.unseatedPlayerIsRejectedForIdentity },
	{ label = "NET-001 AC-5", check = NetContract.validCallIsAccepted },
	{ label = "NET-001 AC-6 names", check = NetContract.rejectionNamesTheCheckThatFired },
	{ label = "NET-001 AC-6 order", check = NetContract.checksRunIdentityThenShapeThenRange },
	{ label = "NET-001 never raises", check = NetContract.guardedCallNeverRaises },
	{
		label = "NET-001 short-circuit",
		check = NetContract.identityFailureShortCircuitsBeforeTheSchema,
	},
	{
		label = "NET-001 kind mapping",
		check = NetContract.wrapperReadsTheKindFromTheSchemasFailureString,
	},
	{ label = "NET-001 define/all", check = NetContract.defineReturnsTheDeclarationAndAllListsIt },
	{ label = "NET-001 AC-8", check = NetContract.redeclaringANameFails },
}

local ALL_CHECKS: { Named } = {}
for _, group in { RATE_CHECKS, NET002_CHECKS, NET001_CHECKS } do
	for _, entry in group do
		table.insert(ALL_CHECKS, entry)
	end
end

local function checkNamed(label: string): Check
	for _, entry in ALL_CHECKS do
		if entry.label == label then
			return entry.check
		end
	end
	error(`no check labelled {label}`)
end

-- Every check, so a control is held to all of them except the ones it is
-- built to fail - and every one of those is asserted to fail, by name.
local function holdsExactly(subject: any, who: string, failing: { string })
	local except: { [string]: boolean } = {}
	for _, label in failing do
		except[label] = true
	end
	for _, entry in ALL_CHECKS do
		if except[entry.label] then
			refuses(entry.check, subject, `{entry.label} on {who} must fail`)
		else
			accepts(entry.check, subject, `{entry.label} on {who} must pass`)
		end
	end
end

return {
	--[[ The baseline. Every control below is this with exactly one defect set,
	     so a control that fires is attributable to that one thing. This is
	     also the proof that the checks are satisfiable at all - and that a
	     rate-limiting wrapper still satisfies NET-001 and NET-002. ]]

	["baseline: a correct rate-limiting bundle passes all 8 rate checks, all 8 of NET-002's phase checks and all 12 of NET-001's wrapper and registry checks"] = function()
		assert(#ALL_CHECKS == 28, `expected 28 checks, found {#ALL_CHECKS}`)
		holdsExactly(Stubs.correct(), "the baseline", {})
	end,

	--[[
		AC-2's control, named in the criterion: "passes AC-1 and must fail
		this". Asserted word for word, and it fails NOTHING ELSE of 28 -
		every other check drives one player per guard. Measured: 1 of 28, on
		B's call at the instant A is limited.
	]]
	["AC-2 control: a wrapper with one shared last-accepted timestamp passes AC-1 and every other check, and fails AC-2 alone - B is refused at the instant A is limited (1 of 28)"] = function()
		local net = Stubs.with("sharedTimestamp")
		holdsExactly(net, "the shared-timestamp wrapper", { "AC-2" })

		local message = refuses(checkNamed("AC-2"), net, "a shared timestamp must fail AC-2")
		names(
			message,
			"AC-2: 2 violation(s) across 5 calls by two players",
			"B's call and the count"
		)
		names(
			message,
			'B at t + 0.5, the same instant A is rate-limited -> REJECTED: reason = "rate"',
			"B is refused against A's timestamp"
		)
		names(message, "the handler ran 1 time(s) over 5 calls; 2 were accepted", "only A ran")
		lacks(message, "A at t -> REJECTED", "A's first call is still accepted")
		lacks(message, "-> ACCEPTED", "every inside-the-interval call is still refused")
	end,

	--[[
		AC-3's control, named in the criterion: "an implementation that updates
		the timestamp on rejection must fail this". It does - at t + 1.6 (0.2 s
		after the recorded rejection) and on the load case, where the 100 Hz
		caller is served 0 times in 3.2 s. It ALSO fails AC-1, and cannot not:
		AC-1's own calls at t + 1.4 and t + 1.5 are 0.1 s apart. Measured: 2 of
		28, the story's "AC-3 alone" corrected to "AC-3 and AC-1".
	]]
	["AC-3 control: a limiter that records the timestamp on rejection fails AC-3 - refused at t + 1.6 and served 0 times over 320 calls at 10 ms - and AC-1's t + 1.5 call, and passes AC-2, AC-4, AC-5, AC-6, detail, clock and all 20 earlier checks (2 of 28)"] = function()
		local net = Stubs.with("recordsOnReject")
		holdsExactly(net, "the records-on-reject limiter", { "AC-1", "AC-3" })

		local message = refuses(checkNamed("AC-3"), net, "recording on rejection must fail AC-3")
		names(
			message,
			"AC-3: 3 violation(s) across 326 calls",
			"the t + 1.6 call, the count, the load"
		)
		names(
			message,
			't + 1.6: 1.6 s after the last ACCEPTED call, 0.2 s after the last attempt -> REJECTED: reason = "rate"',
			"the criterion's own case: measured from the last attempt instead"
		)
		names(
			message,
			"the player was served 0 time(s); a limit of one call per 1.5 s serves them 2 times",
			"locked out forever under load"
		)
		lacks(
			message,
			"rejected at t + 0.5 -> ACCEPTED",
			"the inside-the-interval calls are still refused"
		)

		local boundary = refuses(checkNamed("AC-1"), net, "recording on rejection also fails AC-1")
		names(
			boundary,
			'the same player at t + 1.5, exactly the interval -> REJECTED: reason = "rate"',
			"t + 1.5 is 0.1 s after the recorded t + 1.4"
		)
	end,

	--[[
		AC-1's boundary control: `>` where the Contract says `>=`. It fails
		exactly one line of AC-1 - the call at exactly t + 1.5 - and nothing
		else of 28, because every other check keeps its acceptances clear of
		the boundary. Measured: 1 of 28, one call.
	]]
	["AC-1 control: a limiter comparing with > instead of >= fails AC-1 on the call at exactly t + 1.5 and nothing else of 28 - the first call and t + 1.4 are unaffected (1 of 28)"] = function()
		local net = Stubs.with("strictlyGreater")
		holdsExactly(net, "the strictly-greater limiter", { "AC-1" })

		local message = refuses(checkNamed("AC-1"), net, "> must fail AC-1's boundary")
		names(
			message,
			"AC-1: 2 violation(s) across 3 calls at minIntervalSeconds = 1.5",
			"one call, one count"
		)
		names(
			message,
			'the same player at t + 1.5, exactly the interval -> REJECTED: reason = "rate"',
			"the boundary call is refused"
		)
		names(
			message,
			"the handler ran 1 time(s) over 3 calls; 2 were outside the interval",
			"one run short"
		)
		lacks(message, "the first call, at t -> REJECTED", "the first call is accepted")
		lacks(message, "t + 1.4 -> ACCEPTED", "t + 1.4 is still refused")
	end,

	--[[ The pre-NET-003 wrapper: what the real suite fails on arrival, plus
	     AC-6 there because the limiter module does not exist. ]]

	["control: a wrapper with no rate check fails AC-1, AC-2, AC-3, AC-5, detail and clock, and passes AC-4, AC-6 and all 20 earlier checks (6 of 28)"] = function()
		local net = Stubs.with("ignoresRateLimit")
		holdsExactly(
			net,
			"the rate-blind wrapper",
			{ "AC-1", "AC-2", "AC-3", "AC-5", "detail", "clock" }
		)

		local message = refuses(checkNamed("AC-1"), net, "ignoring the rate limit must fail AC-1")
		names(message, "AC-1: 2 violation(s) across 3 calls", "t + 1.4 and the handler count")
		names(
			message,
			"the same player at t + 1.4 -> ACCEPTED (returned nil); the handler was reachable",
			"the inside-the-interval call goes through"
		)
		names(
			message,
			"the handler ran 3 time(s) over 3 calls; 2 were outside the interval",
			"three runs"
		)

		local load = refuses(checkNamed("AC-3"), net, "ignoring the rate limit must fail AC-3")
		names(
			load,
			"the player was served 320 time(s)",
			"every one of 320 calls at 10 ms went through"
		)

		local fifth = refuses(checkNamed("AC-5"), net, "ignoring the rate limit must fail AC-5")
		names(
			fifth,
			"AC-5: 2 violation(s) across 9 calls",
			"only the positive control inside AC-5 fires"
		)
		names(
			fifth,
			"valid at t + 5.5 -> rate (the limiter is measured from t + 5.0) -> ACCEPTED (returned nil)",
			"the one call that must be rate is accepted; every earlier reason is still right"
		)
	end,

	--[[
		AC-4's control: a wrapper that limits a remote that declared no
		rateLimit. It fails AC-4 - 49 of 50 refused and the clock read 50
		times - and it is the one control the EARLIER suites can see: three of
		their checks call one guard repeatedly at a clock frozen at 0, which is
		exactly what `## Callers of changed signatures` said would break.
		Measured: 4 of 28; among this story's checks, AC-4 alone.
	]]
	["AC-4 control: a wrapper that limits a remote declaring no rateLimit fails AC-4 - 49 of 50 refused, the clock read 50 times - and three earlier checks that call one guard repeatedly at a frozen clock: NET-002 AC-6, NET-001 AC-1 and AC-5 (4 of 28)"] = function()
		local net = Stubs.with("limitsWithoutRateLimit")
		holdsExactly(
			net,
			"the limit-everything wrapper",
			{ "AC-4", "NET-002 AC-6", "NET-001 AC-1", "NET-001 AC-5" }
		)

		local message =
			refuses(checkNamed("AC-4"), net, "limiting an unlimited remote must fail AC-4")
		names(
			message,
			"AC-4: 3 violation(s) for a remote with no rateLimit",
			"refusals, runs, reads"
		)
		names(
			message,
			'49 of 50 calls were not accepted; the first: AC-4: call 2 at the same instant -> REJECTED: reason = "rate"',
			"the second call at the same instant is refused"
		)
		names(message, "the handler ran 1 time(s) over 50 calls", "one run")
		names(
			message,
			"context.clock.now() was read 50 time(s) across guard() and 50 calls; a remote with no rateLimit never reads the clock",
			"the structural form: the clock was read"
		)

		local earlier =
			refuses(checkNamed("NET-001 AC-1"), net, "the earlier suite sees this defect")
		names(
			earlier,
			'a second valid call was not accepted: reason = "rate"',
			"NET-001's repeated call is refused"
		)
	end,

	--[[
		AC-5's control: check 5 moved ahead of check 4. An out-of-phase call
		inside the interval is refused for rate rather than phase and reads
		the clock; an out-of-phase call OUTSIDE the interval is accepted by the
		limiter, recorded, and only then refused for phase - so the legal call
		1.0 s later is refused and the call 0.5 s after that is accepted.
		Measured: 2 of 28 - AC-5 and the Contract's read-count check, which
		counts one clock read on a phase-rejected call. Identity, shape and
		range are NOT displaced: this defect sits behind them.
	]]
	["AC-5 control: the rate check ahead of the phase check fails AC-5 on 5 lines - an out-of-phase call refused for rate, the clock read on two phase-rejected calls, and the timestamp advanced by one - and the clock check on 3, and passes AC-1 to AC-4, AC-6, detail and all 20 earlier checks (2 of 28)"] = function()
		local net = Stubs.with("rateBeforePhase")
		holdsExactly(net, "the rate-before-phase wrapper", { "AC-5", "clock" })

		local message = refuses(checkNamed("AC-5"), net, "rate before phase must fail AC-5")
		names(message, "AC-5: 5 violation(s) across 9 calls", "five lines")
		names(
			message,
			'valid but out of phase (Lobby) at t + 1.0 -> phase -> rejected for "rate", expected "phase"',
			"the wrong reason inside the interval"
		)
		names(
			message,
			"valid but out of phase (Lobby) at t + 4.0, outside the interval -> phase -> context.clock.now() was read 1 time(s)",
			"the clock is read on a call phase should have refused first"
		)
		names(
			message,
			'valid at t + 5.0 -> accepted (the phase-rejected call advanced nothing) -> REJECTED: reason = "rate"',
			"the phase-rejected call at t + 4.0 advanced the timestamp"
		)
		names(
			message,
			"valid at t + 5.5 -> rate (the limiter is measured from t + 5.0) -> ACCEPTED (returned nil)",
			"and so the call that should be rate is accepted"
		)
		lacks(
			message,
			'unseated caller at t + 1.0 -> identity -> rejected for "rate"',
			"identity still wins"
		)
		lacks(
			message,
			'malformed {} at t + 1.0 -> shape -> rejected for "rate"',
			"shape still wins"
		)
		lacks(message, '(range) at t + 1.0 -> range -> rejected for "rate"', "range still wins")

		local reads = refuses(checkNamed("clock"), net, "rate before phase reads the clock early")
		names(reads, "clock: 3 violation(s) across 7 calls", "the early read and its consequences")
		names(
			reads,
			"a valid payload out of phase (phase) -> context.clock.now() was read 1 time(s); an earlier check fails first",
			"the read on a phase-rejected call is counted"
		)
	end,

	--[[
		The positive control. A wrapper that refuses every call reaching check
		5, whether or not the remote declared a limit, FAILS AC-1's first call
		and AC-4 - the two things green the moment a limiter is absent, and so
		not earned by RED's red - and passes AC-6 (the limiter itself is
		correct) and every check that only ever refuses. Measured: 15 of 28,
		as NET-002's reject-every-phase control measured 8 of 20.
	]]
	["control: a wrapper that rejects every call reaching check 5 fails AC-1 on its FIRST call, AC-4 on all 50, AC-2, AC-3, AC-5, detail, clock and 8 positive earlier checks, and passes AC-6 and every check that only refuses (15 of 28)"] = function()
		local net = Stubs.with("rejectsEverything")
		holdsExactly(net, "the reject-everything wrapper", {
			"AC-1",
			"AC-2",
			"AC-3",
			"AC-4",
			"AC-5",
			"detail",
			"clock",
			"NET-002 AC-1",
			"NET-002 AC-3",
			"NET-002 AC-4",
			"NET-002 AC-6",
			"NET-001 AC-1",
			"NET-001 AC-5",
			"NET-001 short-circuit",
			"NET-001 kind mapping",
		})

		local message = refuses(checkNamed("AC-1"), net, "rejecting everything must fail AC-1")
		names(message, "AC-1: 3 violation(s) across 3 calls", "both acceptances and the count")
		names(
			message,
			'the first call, at t -> REJECTED: reason = "rate"',
			"the first call is refused"
		)
		names(message, "the handler ran 0 time(s) over 3 calls", "nothing ran")

		local unlimited = refuses(checkNamed("AC-4"), net, "rejecting everything must fail AC-4")
		names(
			unlimited,
			"50 of 50 calls were not accepted",
			"every call to the unlimited remote is refused"
		)
		lacks(
			unlimited,
			"context.clock.now() was read",
			"no limiter, so no clock read - the verdict is the defect"
		)
	end,

	--[[ The clock captured when guard() is called: NET-002's captured phase
	     in a different hat. Every timed check that moves the clock past the
	     interval fails; AC-2 passes because it never does. ]]

	["control: a wrapper that reads context.clock.now() once at guard() fails AC-1, AC-3, AC-5 and the clock check - every call after the first sees 0 s elapsed - and passes AC-2, AC-4, AC-6, detail and all 20 earlier checks (4 of 28)"] = function()
		local net = Stubs.with("capturesClockAtGuard")
		holdsExactly(net, "the captured-clock wrapper", { "AC-1", "AC-3", "AC-5", "clock" })

		local message = refuses(checkNamed("clock"), net, "a captured clock reads nothing per call")
		names(
			message,
			"clock: 5 violation(s) across 7 calls",
			"three unread calls, one refusal, the count"
		)
		names(
			message,
			"the guard having been built at t (accepted) -> context.clock.now() was not read during the call",
			"the accepted call did not read the clock"
		)
		names(
			message,
			'2.5 s after the acceptance (accepted - the clock of the moment, not the clock at guard()) -> REJECTED: reason = "rate"',
			"the call the criterion is about is refused"
		)
	end,

	--[[ The Contract's `detail` block, one control per clause. ]]

	['detail control: a detail leading with "rate: " fails the detail check alone (1 of 28)'] = function()
		local net = Stubs.with("prefixedDetail")
		holdsExactly(net, "the prefixed-detail wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "a rate: prefix must fail")
		names(message, "detail failed in 1 way(s)", "one clause")
		names(message, 'detail leads with "rate:"', "the prefix is named")
	end,

	["detail control: a detail that names the remote but not the interval fails the detail check alone (1 of 28)"] = function()
		local net = Stubs.with("detailOmitsInterval")
		holdsExactly(net, "the no-interval wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "omitting the interval must fail")
		names(message, "detail failed in 1 way(s)", "one clause")
		names(
			message,
			"detail does not carry the required interval 1.5",
			"the missing number is named"
		)
	end,

	["detail control: a detail that names the interval but not the remote fails the detail check alone (1 of 28)"] = function()
		local net = Stubs.with("detailOmitsName")
		holdsExactly(net, "the no-name wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "omitting the remote's name must fail")
		names(message, "detail failed in 1 way(s)", "one clause")
		names(message, "detail does not name the remote", "the missing name is named")
	end,

	--[[ AC-6's controls: the two limiter shapes the Contract pins against. ]]

	["AC-6 control: a limiter whose forget is a no-op fails AC-6 alone - size() never falls, and the forgotten player is still refused (1 of 28)"] = function()
		local net = Stubs.with("neverForgets")
		holdsExactly(net, "the never-forgetting limiter", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), net, "a no-op forget must fail AC-6")
		names(message, "AC-6: 20 violation(s)", "every size after a leave, and the reset")
		names(message, "size() is 2 after forget(p1); expected 1", "the first forget did nothing")
		names(
			message,
			'allow("p1", "remoteA", 0.5) returned false (p1 is new again after forget: allowed at the instant p1 was just refused); expected true',
			"the forgotten player is still limited"
		)
		names(
			message,
			"size() is 10 after player1 left, with 0 seated; expected 0",
			"nobody ever leaves"
		)
	end,

	["AC-6 control: a limiter whose size() counts (player, key) pairs fails AC-6 alone - 2 after one player used two remotes, 16 with eight seated (1 of 28)"] = function()
		local net = Stubs.with("sizeCountsKeys")
		holdsExactly(net, "the pair-counting limiter", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), net, "counting pairs must fail AC-6")
		names(message, "AC-6: 17 violation(s)", "every size with a two-remote player")
		names(
			message,
			"size() is 2 after p1 used a second remote - one entry per PLAYER, not per (player, key); expected 1",
			"the shape the Contract pins"
		)
		names(message, "size() is 16 with 8 seated; expected 8", "twice the seated count")
		lacks(
			message,
			"returned false",
			"every allow answer is still right: only the count is wrong"
		)
	end,
}
