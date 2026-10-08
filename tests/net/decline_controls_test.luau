--!strict
--[[
	The negative controls for CHAN-003, and the proof that each check in
	`tests/helpers/DeclineContract.luau` refuses the bundle it exists to
	catch.

	THE CRITERIA AND THE DEFERRED VERIFICATIONS NAME THEIR CONTROLS. AC-1: a
	wrapper that answers `declined` without refunding. AC-2: "an
	implementation that refunds the attempt limit on decline must fail this"
	(D-2). AC-3: "a refund that clears the key instead of restoring t0 must
	fail this" (D-1), and AC-1 must still pass under it - asserted below in
	exactly those terms. D-3: a refund without the `acceptedAt` guard fails
	the stale-refund clause. D-4: a wrapper reading the clock once per
	limiter fails AC-5's clock count and NOTHING ELSE, which is what earns
	that count's green-on-arrival half (see `decline_test.luau`'s header).

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and the
	baseline is asserted to pass every check here AND NET-003's eight,
	four of TEL-003's and samples of NET-001's and NET-002's - the half that
	shows stage 5 with two limiters, a CallControl and a refund is a layer
	the earlier suites cannot see unless it is wrong, and that a control
	failing a check is a control with ONE defect rather than a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the set
	MEASURED outside the runner first (`## Handoff`) and pinned EXACTLY here:
	a control that starts failing a check it did not fail before is a change
	in what the suite discriminates, and worth a red line. Two of the
	measurements are properties of the checks rather than of the defects:
	`declineNotRefunded` fails AC-5 because that check's last step on the
	both-limits remote expects an acceptance after a decline, and
	`defineDropsAttemptLimit` fails AC-5 because the attempt-only remote
	then has no limiter and reads the clock zero times.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The bundles are
	`DeclineStubs.luau` over `PhaseStubs.luau` over `NetStubs.luau`, with the
	merged `RejectionReporter` and `Event`, so these controls EXECUTE in RED
	while `decline_test.luau`'s assertions against the real `src/ReplicatedStorage/Net/` are
	red on their own terms.
]]

local DeclineContract = require("../helpers/DeclineContract")
local NetContract = require("../helpers/NetContract")
local PhaseContract = require("../helpers/PhaseContract")
local RateContract = require("../helpers/RateContract")
local RejectionContract = require("../helpers/RejectionContract")
local Stubs = require("../helpers/DeclineStubs")

local Event = require("../../src/ReplicatedStorage/Shared/telemetry/Event")

type Check = (any) -> ()
type Named = { label: string, check: Check }

-- TEL-003's checks take a bundle with `Event`; every bundle here carries the
-- merged one, which knows `remote_rejected`.
local function bundle(defect: string?): any
	local built: any = if defect ~= nil then Stubs.with(defect :: string) else Stubs.correct()
	built.Event = Event
	return built
end

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

local DECLINE_CHECKS: { Named } = {
	{ label = "AC-1", check = DeclineContract.declinedCallDoesNotCostTheSendLimit },
	{ label = "AC-2", check = DeclineContract.attemptFloorIsNeverRefunded },
	{
		label = "step 1",
		check = DeclineContract.sendLimiterIsNotConsultedWhenTheAttemptFloorRefuses,
	},
	{ label = "AC-3", check = DeclineContract.refundRestoresThePreviousAcceptance },
	{
		label = "AC-3 limiter",
		check = DeclineContract.refundRestoresTheAcceptanceBeforeItOnTheLimiter,
	},
	{ label = "stale refund", check = DeclineContract.refundOfAStaleAcceptanceIsANoOp },
	{
		label = "empty entry",
		check = DeclineContract.refundOfAPlayersOnlyAcceptanceRemovesThePlayer,
	},
	{ label = "unknown refund", check = DeclineContract.refundOfAnUnknownPlayerOrKeyNeverRaises },
	{ label = "AC-4", check = DeclineContract.declinedCallReturnsADeclinedRejection },
	{ label = "AC-4 telemetry", check = DeclineContract.declinedIsRecordedLikeAnyOtherReason },
	{
		label = "fresh call",
		check = DeclineContract.callControlIsFreshPerCallAndAnUndeclinedCallKeepsItsAcceptance,
	},
	{ label = "decline twice", check = DeclineContract.decliningTwiceIsANoOpTheSecondTime },
	{
		label = "late decline",
		check = DeclineContract.declineAfterTheWrapperReturnedStillRefundsAndEmitsNothing,
	},
	{ label = "AC-5", check = DeclineContract.stageFiveReadsTheClockExactlyOnce },
	{ label = "define", check = DeclineContract.defineCopiesTheAttemptLimit },
}

-- The earlier suites' checks, held over the baseline: the new layer must be
-- invisible to them.
local EARLIER_CHECKS: { Named } = {
	{ label = "NET-003 AC-1", check = RateContract.acceptsAtTheIntervalAndRejectsInsideIt },
	{ label = "NET-003 AC-2", check = RateContract.playersAreLimitedIndependently },
	{ label = "NET-003 AC-3", check = RateContract.intervalIsMeasuredFromTheLastAcceptedCall },
	{ label = "NET-003 AC-4", check = RateContract.remoteWithoutRateLimitIsNeverLimited },
	{ label = "NET-003 AC-5", check = RateContract.earlierRejectionsDoNotAdvanceTheLimiter },
	{
		label = "NET-003 AC-6",
		check = RateContract.forgetRemovesThePlayerAndSizeCountsSeatedPlayers,
	},
	{
		label = "NET-003 detail",
		check = RateContract.rateRejectionDetailNamesTheRemoteAndTheInterval,
	},
	{ label = "NET-003 clock", check = RateContract.clockIsReadOnlyByCallsThatReachTheRateCheck },
	{
		label = "TEL-003 wiring",
		check = RejectionContract.wrapperRecordsEachRejectionAndEmitsItsEventOnce,
	},
	{ label = "TEL-003 AC-2", check = RejectionContract.acceptedCallProducesNoEventAndNoRecord },
	{
		label = "TEL-003 no telemetry",
		check = RejectionContract.contextWithoutTelemetryIsUnchanged,
	},
	{
		label = "TEL-003 AC-1/AC-3",
		check = RejectionContract.everyReasonProducesExactlyOneEventNamingRemoteReasonAndPlayer,
	},
	{ label = "NET-002 AC-2", check = PhaseContract.outOfPhaseCallIsRejectedForPhase },
	{ label = "NET-001 AC-6 order", check = NetContract.checksRunIdentityThenShapeThenRange },
	{ label = "NET-001 define/all", check = NetContract.defineReturnsTheDeclarationAndAllListsIt },
}

local function checkNamed(label: string): Check
	for _, entry in DECLINE_CHECKS do
		if entry.label == label then
			return entry.check
		end
	end
	error(`no check labelled {label}`)
end

--[[
	Runs every CHAN-003 check over the control and asserts the set of
	failing labels is EXACTLY `expected` - no check it should pass fails, no
	check it should fail passes - and that the first named failure's message
	carries `fragment`.
]]
local function failsExactly(defect: string, expected: { string }, fragment: string)
	local subject = bundle(defect)
	local expectedSet: { [string]: boolean } = {}
	for _, label in expected do
		expectedSet[label] = true
	end
	local failed: { string } = {}
	local messages: { [string]: string } = {}
	for _, entry in DECLINE_CHECKS do
		local ok, err = pcall(entry.check, subject)
		if not ok then
			table.insert(failed, entry.label)
			messages[entry.label] = tostring(err)
		end
	end
	local unexpected: { string } = {}
	for _, label in failed do
		if not expectedSet[label] then
			table.insert(unexpected, `{label} (failed, should pass): {messages[label]}`)
		end
	end
	for _, label in expected do
		if table.find(failed, label) == nil then
			table.insert(
				unexpected,
				`{label} (passed, should fail - the check is vacuous against it)`
			)
		end
	end
	assert(
		#unexpected == 0,
		`the "{defect}" control must fail exactly \{ {table.concat(expected, ", ")} \}; measured `
			.. `\{ {table.concat(failed, ", ")} \}:\n  {table.concat(unexpected, "\n  ")}`
	)
	names(
		messages[expected[1]],
		fragment,
		`the "{defect}" control's {expected[1]} failure must name what it did`
	)
end

return {
	--[[ The baseline ]]

	["the correct bundle passes every CHAN-003 check and every earlier check held over it (NET-003's eight, TEL-003's wiring, accept, no-telemetry and end-to-end, NET-002 and NET-001 samples)"] = function()
		local subject = bundle(nil)
		for _, group in { DECLINE_CHECKS, EARLIER_CHECKS } do
			for _, entry in group do
				accepts(entry.check, subject, `the correct bundle must pass {entry.label}`)
			end
		end
	end,

	["every control is a single defect: each fails at least one CHAN-003 check and none fails NET-003's AC-4 or TEL-003's no-telemetry check, which the new layer cannot touch"] = function()
		for _, defect in Stubs.DEFECTS do
			local subject = bundle(defect)
			local failed = 0
			for _, entry in DECLINE_CHECKS do
				if not pcall(entry.check, subject) then
					failed += 1
				end
			end
			assert(
				failed > 0,
				`the "{defect}" control fails no CHAN-003 check; it is not a control`
			)
			accepts(
				RateContract.remoteWithoutRateLimitIsNeverLimited,
				subject,
				`the "{defect}" control must still pass NET-003 AC-4`
			)
			accepts(
				RejectionContract.contextWithoutTelemetryIsUnchanged,
				subject,
				`the "{defect}" control must still pass TEL-003's no-telemetry check`
			)
		end
	end,

	--[[ The pre-CHAN-003 wrapper ]]

	["neverPassesCall - the wrapper that hands the handler two arguments, what the real suite fails on arrival - fails AC-1, AC-2, step 1, AC-3, AC-4, AC-4 telemetry, fresh call, decline twice, late decline and AC-5, naming the nil third argument, and passes every limiter and define check"] = function()
		failsExactly("neverPassesCall", {
			"AC-1",
			"AC-2",
			"step 1",
			"AC-3",
			"AC-4",
			"AC-4 telemetry",
			"fresh call",
			"decline twice",
			"late decline",
			"AC-5",
		}, "received call = nil as its third argument")
	end,

	--[[ AC-1 ]]

	["AC-1 control: a decline that answers declined but refunds nothing fails AC-1 (the second call is rate), and with it step 1, AC-3, late decline and AC-5's post-decline acceptance; AC-2 and AC-4 pass"] = function()
		failsExactly(
			"declineNotRefunded",
			{ "AC-1", "step 1", "AC-3", "late decline", "AC-5" },
			'with the first call declined -> REJECTED: reason = "rate"'
		)
	end,

	--[[ AC-2 / D-2 ]]

	["AC-2 control (D-2): a decline that refunds the attempt limiter too fails AC-2 - the call inside the floor after a declined call is ACCEPTED - and step 1, and passes AC-1, AC-3 and AC-4"] = function()
		failsExactly(
			"refundsAttemptToo",
			{ "AC-2", "step 1" },
			"inside the attempt floor, after a DECLINED call -> ACCEPTED"
		)
	end,

	["AC-2 detail: an attempt refusal worded with the send sentence fails AC-2 and step 1 on the whole-string match, naming both sentences"] = function()
		local message = refuses(
			checkNamed("AC-2"),
			bundle("attemptDetailSaysCall"),
			"the attempt sentence spelled with 'call' must fail AC-2"
		)
		names(
			message,
			"is limited to one call per 1 s per player",
			"AC-2 must quote the detail it got"
		)
		names(
			message,
			"is limited to one attempt per 1 s per player",
			"AC-2 must quote the detail it expected"
		)
		failsExactly(
			"attemptDetailSaysCall",
			{ "AC-2", "step 1" },
			"is limited to one attempt per 1 s per player"
		)
	end,

	["stage-5 order: the send limiter consulted before the attempt floor fails AC-2 (the detail inside the floor is the send sentence) and step 1"] = function()
		failsExactly(
			"sendBeforeAttempt",
			{ "AC-2", "step 1" },
			"is limited to one attempt per 1 s per player"
		)
	end,

	["stage-5 step 1: a wrapper that consults the send limiter on a call the floor refused fails step 1 alone - the call at t + 1.5 is rate"] = function()
		failsExactly(
			"consultsSendWhenAttemptRefuses",
			{ "step 1" },
			"must not have recorded the refused attempt"
		)
	end,

	["stage-5 step 2: a wrapper that unwinds the attempt acceptance when the send limiter refuses fails AC-2 alone - the call inside that floor gets the send sentence"] = function()
		failsExactly("attemptRefundedOnSendRefusal", { "AC-2" }, "that attempt acceptance stands")
	end,

	--[[ AC-3 / D-1 / D-3 ]]

	["AC-3 control (D-1): a refund that clears the key fails AC-3 - t0 + 9.9 is ACCEPTED - with the limiter-level AC-3 and decline twice, and AC-1 STILL PASSES, as D-1 requires"] = function()
		failsExactly(
			"refundClearsKey",
			{ "AC-3", "AC-3 limiter", "decline twice" },
			"a refund that CLEARED the key would accept this -> ACCEPTED"
		)
		accepts(
			checkNamed("AC-1"),
			bundle("refundClearsKey"),
			"D-1: AC-1 must still pass under refundClearsKey"
		)
	end,

	["D-3 control: a refund without the acceptedAt guard fails the stale-refund clause - t2 + 9.9 is allowed - and with it the limiter-level AC-3's second refund and the unknown-refund no-ops; AC-3 through the wrapper passes"] = function()
		failsExactly(
			"refundIgnoresAcceptedAt",
			{ "AC-3 limiter", "stale refund", "unknown refund" },
			"the second refund did not unwind t0 as well"
		)
		local message = refuses(
			checkNamed("stale refund"),
			bundle("refundIgnoresAcceptedAt"),
			"D-3: the stale-refund clause must fail without the acceptedAt guard"
		)
		names(message, "a refund of t1 is a no-op", "the stale-refund failure must name the clause")
	end,

	["empty entry: a refund that keeps an emptied player entry fails the empty-entry check alone, on size()"] = function()
		failsExactly("refundLeavesEmptyPlayer", { "empty entry" }, "size() is 1; expected 0")
	end,

	["unknown refund: a refund that raises on an unknown player or key fails the unknown-refund check alone"] = function()
		failsExactly("refundRaisesOnUnknown", { "unknown refund" }, "refund never raises")
	end,

	--[[ AC-4 ]]

	["AC-4 control: a wrapper that refunds on decline but returns nil fails AC-4 and every check that expects a declined result, and passes the limiter, fresh-call, late-decline and define checks"] = function()
		failsExactly("declineReturnsNil", {
			"AC-1",
			"AC-2",
			"step 1",
			"AC-3",
			"AC-4",
			"AC-4 telemetry",
			"decline twice",
			"AC-5",
		}, 'expected a "declined" rejection')
	end,

	["AC-4 detail: a declined detail without the remote's name fails AC-4 alone, on the exact Rejection"] = function()
		failsExactly(
			"declinedDetailOmitsName",
			{ "AC-4" },
			'declined the call", got "declined the call"'
		)
	end,

	["AC-4 without a send limiter: a decline ignored when there is nothing to refund fails AC-4 (the attempt-only and no-limit remotes return nil) and AC-5's declined steps"] = function()
		failsExactly(
			"declineWithoutSendLimitIgnored",
			{ "AC-4", "AC-5" },
			"a remote with an attempt floor only, declined -> the result is not the Contract's Rejection"
		)
	end,

	["AC-4 telemetry control: a declined result returned without the telemetry step fails AC-4 telemetry alone - record and emit called 0 times"] = function()
		failsExactly(
			"declineSkipsTelemetry",
			{ "AC-4 telemetry" },
			"reporter:record was called 0 time(s) for one declined call"
		)
	end,

	["fresh call: one CallControl shared across calls fails the fresh-call check alone, naming the shared table"] = function()
		failsExactly("sharedCallControl", { "fresh call" }, "received the SAME CallControl table")
	end,

	["late decline: a decline after the wrapper returned that refunds nothing fails the late-decline check alone - the call 5 s later is rate"] = function()
		failsExactly(
			"declineAfterReturnIgnored",
			{ "late decline" },
			"the late decline refunded t1, so the key holds t0"
		)
	end,

	["late decline: a decline after the wrapper returned that records and emits an event fails the late-decline check alone"] = function()
		failsExactly(
			"declineAfterReturnEmits",
			{ "late decline" },
			"the late decline called reporter:record 1 time(s) and emit 1 time(s)"
		)
	end,

	--[[ AC-5 / D-4 ]]

	["AC-5 control (D-4): a wrapper reading context.clock.now() once per limiter fails AC-5 and NOTHING ELSE - 3 reads on an accepted both-limits call - which is what earns the clock count that is green on arrival"] = function()
		failsExactly(
			"readsClockPerLimiter",
			{ "AC-5" },
			"context.clock.now() was read 3 time(s) during the call"
		)
	end,

	--[[ The registry ]]

	["define: a Remotes.define that does not copy attemptLimit fails the define check (attemptLimit is nil), and with it AC-2, step 1 and AC-5, because the wrapper then builds no attempt limiter"] = function()
		failsExactly(
			"defineDropsAttemptLimit",
			{ "AC-2", "step 1", "AC-5", "define" },
			"inside the attempt floor, after a DECLINED call -> ACCEPTED"
		)
		local message = refuses(
			checkNamed("define"),
			bundle("defineDropsAttemptLimit"),
			"the define check must fail when attemptLimit is dropped"
		)
		names(
			message,
			"definition.attemptLimit differs from what was declared",
			"define must name the field"
		)
	end,
}
