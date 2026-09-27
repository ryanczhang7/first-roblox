--!strict
--[[
	The negative controls for TEL-003, and the proof that each check in
	`tests/helpers/RejectionContract.luau` refuses the bundle it exists to catch.

	THE STORY NAMES ITS CONTROLS, and each is asserted in the criterion's own
	terms. AC-2: an implementation emitting on every guarded call "passes AC-1
	and must fail this" - `emitsOnAccept`, held to pass AC-1/AC-3 and to fail
	AC-2. AC-4: one that puts `rawArgs` in `fields` "must fail this, and must
	also fail TEL-001's scalar-fields check when the payload is a table -
	assert both" - `rawArgsInFields`, refused by the needle check AND by the
	scalar check, each named; `detailInFields` for PO decision 2. AC-5: "the
	unbounded implementation produces 1,000 events" - `unbounded`, and the
	message says 1000; `## Notes` mutation 2 (drop the count) - `dropsCount`,
	which fails the SUM check and PASSES the bound check, as predicted.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, including
	NET-003's eight rate checks, held over every bundle here: the telemetry
	step is a layer the earlier suite cannot see unless it raises on a context
	without the field (`assumesTelemetry`), and a control failing this story's
	checks is a control with ONE defect rather than a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	MEASURED here rather than predicted - measured first outside the runner
	(`## Handoff`), then pinned. The envelope is compared exactly by most
	checks, so a defect in what an event CARRIES (`dropsCount`,
	`callerInFields`, `wrongBucket`) has a wide footprint; the count-of-events
	and the sum are what the story's predictions are about, and they are
	pinned by name.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The reporter stub is a
	reference of the Contract; the wrapper stub layers the telemetry step over
	the real, merged `Wrapper.guard`; events are checked against TEL-001's
	reference `Event` (which knows `remote_rejected`). So these controls
	EXECUTE in RED, while `rejection_test.luau`'s assertions against the real
	`src/net/` are red on their own terms.
]]

local RateContract = require("../helpers/RateContract")
local RejectionContract = require("../helpers/RejectionContract")
local Stubs = require("../helpers/RejectionStubs")

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

local STORY_CHECKS: { Named } = {
	{ label = "shape", check = RejectionContract.reporterExportsTheIntervalAndAConstructor },
	{ label = "AC-1 (reporter)", check = RejectionContract.nonRateReasonsAreNeverCoalesced },
	{ label = "AC-5 bound", check = RejectionContract.floodIsBoundedToElevenEvents },
	{ label = "AC-5 sum", check = RejectionContract.floodCountsSumToEveryRejection },
	{ label = "window", check = RejectionContract.windowIsInclusiveAndFlushLeavesItsStart },
	{ label = "AC-6", check = RejectionContract.coalescingIsPerPlayerAndPerRemote },
	{ label = "flush empty", check = RejectionContract.flushWithNothingPendingReturnsAnEmptyList },
	{ label = "wiring", check = RejectionContract.wrapperRecordsEachRejectionAndEmitsItsEventOnce },
	{ label = "AC-2", check = RejectionContract.acceptedCallProducesNoEventAndNoRecord },
	{ label = "no telemetry", check = RejectionContract.contextWithoutTelemetryIsUnchanged },
	{
		label = "AC-1/AC-3",
		check = RejectionContract.everyReasonProducesExactlyOneEventNamingRemoteReasonAndPlayer,
	},
	{ label = "AC-4", check = RejectionContract.noArgumentValueEntersTheEvent },
	{ label = "AC-4 scalar", check = RejectionContract.tablePayloadYieldsScalarFieldsAndNoRaise },
	{ label = "AC-5 wrapper", check = RejectionContract.floodThroughTheWrapperIsBoundedAndCounted },
	{ label = "table caller", check = RejectionContract.tableCallerIdIsNotPutInTheEvent },
}

-- NET-003's rate checks, held over every bundle here: the telemetry step
-- must be invisible to them unless it raises on a context without the field.
local NET003_CHECKS: { Named } = {
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
}

local ALL_CHECKS: { Named } = {}
for _, group in { STORY_CHECKS, NET003_CHECKS } do
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

-- The checks that compare the whole envelope exactly, which every defect in
-- what an event CARRIES fails together. Named once so the footprints below
-- read as "the envelope checks plus ...".
local ENVELOPE_CHECKS: { string } = {
	"AC-1 (reporter)",
	"window",
	"AC-6",
	"AC-1/AC-3",
	"AC-4",
	"AC-4 scalar",
	"table caller",
}

local function together(...: { string }): { string }
	local out: { string } = {}
	for _, list in { ... } do
		for _, label in list do
			table.insert(out, label)
		end
	end
	return out
end

return {
	--[[ The baseline. Every control below is this with exactly one defect set,
	     so a control that fires is attributable to that one thing. This is
	     also the proof that the checks are satisfiable at all - and that a
	     wrapper with the telemetry step still satisfies NET-003. ]]

	["baseline: a correct reporter and wrapper pass all 15 story checks and all 8 of NET-003's rate checks"] = function()
		assert(#ALL_CHECKS == 23, `expected 23 checks, found {#ALL_CHECKS}`)
		holdsExactly(Stubs.correct(), "the baseline", {})
	end,

	--[[ ---------------------------------------------------------------------
	     AC-5: the bound and the sum
	     --------------------------------------------------------------------- ]]

	--[[
		AC-5's control, named in the criterion: "the unbounded implementation
		produces 1,000 events". Measured: record returns 1000 over the flood
		and flush returns 0; through the wrapper, 993 emits for 993 rate
		rejections. It also fails the window, AC-6 and flush checks (nothing
		is ever pending) and the sum check's SCHEDULE half (the sum itself is
		1,000, one per event). 6 of 23.
	]]
	["AC-5 control: an unbounded reporter produces 1,000 events from 1,000 rate rejections - and 993 emits for 993 rate Rejections through the wrapper - failing the bound, sum schedule, window, AC-6, flush-empty and wrapper-flood checks (6 of 23)"] = function()
		local bundle = Stubs.with("unbounded")
		holdsExactly(
			bundle,
			"the unbounded reporter",
			{ "AC-5 bound", "AC-5 sum", "window", "AC-6", "flush empty", "AC-5 wrapper" }
		)

		local bound = refuses(checkNamed("AC-5 bound"), bundle, "unbounded must fail the bound")
		names(
			bound,
			"record returned 1000 event(s) over 1000 rate rejections at 100 Hz (10 s) and flush(10) returned 0; wanted 10 and 1",
			"the measured number is 1,000"
		)

		local sum =
			refuses(checkNamed("AC-5 sum"), bundle, "unbounded fails the sum's schedule half")
		names(sum, "the counts sum to 1000, but", "the sum itself is right: one per event")
		names(sum, "1000 event(s) in all; the schedule has 11", "the schedule half fires")

		local wrapper =
			refuses(checkNamed("AC-5 wrapper"), bundle, "unbounded must fail the wrapper flood")
		names(
			wrapper,
			"993 rate rejections produced 993 emit call(s) and 0 flushed event(s), 993 in all",
			"one emit per rate rejection through the wrapper"
		)
		lacks(wrapper, "sum(fields.count)", "the sum through the wrapper is still right")
	end,

	--[[
		`## Notes` mutation 2: the coalesced event carries no count. The SUM
		check fails - "is 0, and 11 of them carry no numeric count" - and the
		BOUND check passes, exactly as the story predicts. The count is also
		part of the exact envelope, so every envelope check fails with it, and
		so does the wrapper flood's sum. 9 of 23.
	]]
	["AC-5 control (mutation 2): a reporter that drops the count fails the sum check - 0 over 11 events, 11 carrying no count - and PASSES the bound check; the envelope checks and the wrapper flood's sum fail with it (9 of 23)"] = function()
		local bundle = Stubs.with("dropsCount")
		holdsExactly(
			bundle,
			"the count-dropping reporter",
			together(ENVELOPE_CHECKS, { "AC-5 sum", "AC-5 wrapper" })
		)

		local sum = refuses(checkNamed("AC-5 sum"), bundle, "dropping the count must fail the sum")
		names(
			sum,
			"the sum of fields.count over 11 event(s) (10 from record, 1 from flush) is 0, and 11 of them carry no numeric count",
			"the sum is the assertion that fires, and it says the count is missing"
		)
		accepts(
			checkNamed("AC-5 bound"),
			bundle,
			"the bound check is about how many and when, and stays green when the count is dropped"
		)

		local wrapper =
			refuses(checkNamed("AC-5 wrapper"), bundle, "the wrapper flood's sum sees it too")
		names(
			wrapper,
			"sum(fields.count) over 11 event(s) is 0 (11 carry no numeric count); the wrapper returned 993 rate Rejections",
			"the wrapper-level sum fires"
		)
		lacks(wrapper, "bounded means", "the wrapper-level bound is still satisfied")
	end,

	--[[
		PO decision 3, the other direction: EVERY reason coalesced. AC-1's
		reporter half sees four of five identity rejections answered nil; the
		wrapper checks lose events for range, phase and the hostile payloads;
		non-rate rejections become pending, so a flush after them is not
		empty. 5 of 23.
	]]
	["AC-1 control: a reporter that coalesces every reason fails AC-1 - identity rejections 2 to 5 at one instant answered nil - and the flush-empty, AC-1/AC-3 and both AC-4 checks (5 of 23)"] = function()
		local bundle = Stubs.with("coalescesAllReasons")
		holdsExactly(
			bundle,
			"the coalesce-everything reporter",
			{ "AC-1 (reporter)", "flush empty", "AC-1/AC-3", "AC-4", "AC-4 scalar" }
		)

		local message =
			refuses(checkNamed("AC-1 (reporter)"), bundle, "coalescing every reason must fail AC-1")
		names(
			message,
			"AC-1: 19 violation(s) over 20 non-rate rejections",
			"four of five, times four"
		)
		names(
			message,
			"identity rejection 2 of 5 at now = 3.25 -> record returned nil; only rate is coalesced (PO decision 3)",
			"the second identity rejection is suppressed"
		)
		lacks(
			message,
			"identity rejection 1 of 5 at now = 3.25 -> record returned nil",
			"the first is reported"
		)
	end,

	--[[ ---------------------------------------------------------------------
	     AC-6: per player AND per remote
	     --------------------------------------------------------------------- ]]

	["AC-6 control: a reporter keyed by player alone fails AC-6 alone - A's first rejection on a second remote is suppressed by A's flood on the first (1 of 23)"] = function()
		local bundle = Stubs.with("perPlayerOnly")
		holdsExactly(bundle, "the per-player reporter", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), bundle, "keying by player alone must fail AC-6")
		names(
			message,
			"AC-6: 3 violation(s) across 105 rejections",
			"the suppressed first, the flush, the tally"
		)
		names(
			message,
			"A's first on remote_alpha at 0.5, while A's remote_beta window is open -> record returned nil",
			"the other remote's first rejection is lost"
		)
		lacks(
			message,
			"A's first on remote_beta at 0, the instant B's window is open -> record returned nil",
			"players are still independent"
		)
	end,

	["AC-6 control: a reporter keyed by remote alone fails AC-6 alone - A's first rejection on a remote is suppressed by B's open window on it (1 of 23)"] = function()
		local bundle = Stubs.with("perRemoteOnly")
		holdsExactly(bundle, "the per-remote reporter", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), bundle, "keying by remote alone must fail AC-6")
		names(
			message,
			"AC-6: 3 violation(s) across 105 rejections",
			"the suppressed first, the flush, the tally"
		)
		names(
			message,
			"A's first on remote_beta at 0, the instant B's window is open -> record returned nil",
			"one player's flood suppresses another's first rejection"
		)
		lacks(
			message,
			"A's first on remote_alpha at 0.5, while A's remote_beta window is open -> record returned nil",
			"remotes are still independent"
		)
	end,

	["AC-6 control: a flush in insertion order fails AC-6 alone - B before A, beta before alpha (1 of 23)"] = function()
		local bundle = Stubs.with("flushInInsertionOrder")
		holdsExactly(bundle, "the insertion-order flush", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), bundle, "insertion order must fail AC-6")
		names(message, "AC-6: 1 violation(s) across 105 rejections", "only the order")
		names(
			message,
			'flush(1) returned [remote_rejected<"B">{ count = 2, reason = "rate", remote = "remote_beta" }',
			"B, inserted first, comes out first"
		)
		names(
			message,
			"expected (A, remote_alpha, 1), (A, remote_beta, 99), (B, remote_beta, 2) in that order",
			"the sorted order is named"
		)
	end,

	--[[ ---------------------------------------------------------------------
	     The window and the flush
	     --------------------------------------------------------------------- ]]

	["window control: a reporter comparing with > instead of >= fails the window check on the call at exactly one interval, and the flood's schedule in both AC-5 checks (3 of 23)"] = function()
		local bundle = Stubs.with("strictWindow")
		holdsExactly(
			bundle,
			"the strictly-greater reporter",
			{ "AC-5 bound", "AC-5 sum", "window" }
		)
		local message = refuses(checkNamed("window"), bundle, "> must fail the window check")
		names(
			message,
			"step 3: record at 6 returned nil; expected an event with count 2 (the window re-opens when now - w >= 1, inclusive)",
			"the boundary call is suppressed"
		)
		local bound =
			refuses(checkNamed("AC-5 bound"), bundle, "> shifts every window after the first")
		names(
			bound,
			"11 events, but 9 of them are not on the Contract's schedule",
			"still 11, at the wrong times"
		)
	end,

	["window control: a flush that moves the window start to its own now fails the window check alone - the call one interval after the real start is suppressed (1 of 23)"] = function()
		local bundle = Stubs.with("flushResetsWindow")
		holdsExactly(bundle, "the window-moving flush", { "window" })
		local message = refuses(checkNamed("window"), bundle, "moving the window must fail")
		names(
			message,
			"Contract: 2 violation(s) across 9 steps",
			"the suppressed call and its flush"
		)
		names(
			message,
			"step 8: record at 7 returned nil; expected an event with count 2",
			"7 - 6 == 1 re-opens the window, unless the flush moved it to 6.8"
		)
	end,

	["window control: a flush that reports the pending count but keeps it fails the window check - the next opening double-counts - and the flush-empty check (2 of 23)"] = function()
		local bundle = Stubs.with("flushKeepsPending")
		holdsExactly(bundle, "the pending-keeping flush", { "window", "flush empty" })
		local message = refuses(checkNamed("window"), bundle, "keeping the pending count must fail")
		names(
			message,
			"step 8: record at 7: the event is not the Contract's",
			"the re-opening carries the flushed count again"
		)
		names(message, "value.fields.count: expected 2, got 4", "double-counted")
		local empty = refuses(checkNamed("flush empty"), bundle, "a second flush is not empty")
		names(
			empty,
			"immediately after a flush that drained one pending rejection: flush(0.95) returned",
			"the drained rejection is reported twice"
		)
	end,

	--[[ ---------------------------------------------------------------------
	     The envelope
	     --------------------------------------------------------------------- ]]

	["envelope control: a reporter putting the caller in fields fails every envelope check and both AC-5 checks - fields carry a fourth key (9 of 23)"] = function()
		local bundle = Stubs.with("callerInFields")
		holdsExactly(
			bundle,
			"the caller-in-fields reporter",
			together(ENVELOPE_CHECKS, { "AC-5 bound", "AC-5 sum" })
		)
		local message = refuses(checkNamed("table caller"), bundle, "fields.caller must fail")
		names(
			message,
			'fields carry keys { 1 = "caller", 2 = "count", 3 = "reason", 4 = "remote" }; exactly { 1 = "count", 2 = "reason", 3 = "remote" } and nothing else',
			"the fourth key is named"
		)
		names(message, "fields mention the caller", "the table's rendering is in the log")
	end,

	["envelope control: a reporter putting a non-string caller id in playerId fails AC-1's reporter half and the table-caller check (2 of 23)"] = function()
		local bundle = Stubs.with("tableCallerInEnvelope")
		holdsExactly(
			bundle,
			"the table-in-envelope reporter",
			{ "AC-1 (reporter)", "table caller" }
		)
		local message = refuses(checkNamed("table caller"), bundle, "a table playerId must fail")
		names(
			message,
			'a table as the caller id -> playerId is { HOSTILE = "HOSTILE_7f3a" }; the envelope\'s playerId is string?',
			"the attacker-chosen id is in the envelope"
		)
		names(message, "a number as the caller id -> playerId is 424242", "and so is the number")
	end,

	["envelope control: a reporter filing the event under D2_7 fails every envelope check and the bound - Event.new rebuilds it under D1 (8 of 23)"] = function()
		local bundle = Stubs.with("wrongBucket")
		holdsExactly(
			bundle,
			"the wrong-bucket reporter",
			together(ENVELOPE_CHECKS, { "AC-5 bound" })
		)
		local message = refuses(checkNamed("AC-1 (reporter)"), bundle, "D2_7 must fail")
		names(
			message,
			"Event.new rebuilt the event differently",
			"TEL-001's own instrument disagrees"
		)
		names(message, 'value.bucket: expected "D2_7", got "D1"', "the bucket is named")
	end,

	--[[ ---------------------------------------------------------------------
	     The wrapper
	     --------------------------------------------------------------------- ]]

	--[[ The pre-TEL-003 wrapper: what the real suite fails on arrival for its
	     wrapper half, plus every end-to-end check. ]]

	["control: a wrapper with no telemetry step fails the wiring, AC-2's positive control, AC-1/AC-3, both AC-4 checks, the wrapper flood and the table-caller check, and passes every reporter check, the no-telemetry check and all 8 of NET-003's (7 of 23)"] = function()
		local bundle = Stubs.with("ignoresTelemetry")
		holdsExactly(bundle, "the telemetry-blind wrapper", {
			"wiring",
			"AC-2",
			"AC-1/AC-3",
			"AC-4",
			"AC-4 scalar",
			"AC-5 wrapper",
			"table caller",
		})
		local message =
			refuses(checkNamed("wiring"), bundle, "ignoring telemetry must fail the wiring")
		names(
			message,
			"Contract: 11 violation(s) across 5 rejected calls",
			"record and emit, five times, plus the nil case"
		)
		names(
			message,
			"unseated p2 at t -> identity -> reporter:record was called 0 time(s) during the call; exactly once per rejected call",
			"record is never called"
		)
		names(
			message,
			"unseated p2 at t -> identity -> emit was called 0 time(s) during the call",
			"emit is never called"
		)
		local flood =
			refuses(checkNamed("AC-5 wrapper"), bundle, "nothing is emitted for the flood")
		names(
			flood,
			"993 rate rejections produced 0 emit call(s) and 0 flushed event(s), 0 in all",
			"zero events is not bounded, it is absent"
		)
	end,

	--[[
		AC-2's control, named in the criterion: "an implementation emitting on
		every guarded call passes AC-1 and must fail this". Asserted word for
		word: AC-1/AC-3 passes, AC-2 fails on all ten accepted calls. The
		wrapper flood sees it too - seven acceptances become seven extra events,
		18 in all against a bound of 11. 2 of 23.
	]]
	["AC-2 control (mutation 1): a wrapper that records and emits on every guarded call passes AC-1/AC-3 and fails AC-2 - record and emit called 10 times over 10 accepted calls - and the wrapper flood, whose 7 acceptances add 7 events (2 of 23)"] = function()
		local bundle = Stubs.with("emitsOnAccept")
		holdsExactly(bundle, "the emit-on-accept wrapper", { "AC-2", "AC-5 wrapper" })
		accepts(checkNamed("AC-1/AC-3"), bundle, "emitting on every call passes AC-1")

		local message = refuses(checkNamed("AC-2"), bundle, "emitting on accepts must fail AC-2")
		names(message, "AC-2: 2 violation(s)", "both halves: record and emit")
		names(
			message,
			"reporter:record was called 10 time(s) over 10 accepted calls",
			"the reporter is touched on accepts"
		)
		names(message, "emit was called 10 time(s) over 10 accepted calls", "and so is emit")
		lacks(message, "the positive control", "the rejection still records and emits")

		local flood = refuses(checkNamed("AC-5 wrapper"), bundle, "acceptances add events")
		names(
			flood,
			"993 rate rejections produced 17 emit call(s) and 1 flushed event(s), 18 in all",
			"10 windows plus 7 acceptances"
		)
	end,

	["AC-3 control: a wrapper reporting shape and range as one collapsed reason fails the wiring and AC-1/AC-3 - fields.reason is not the Rejection's reason (2 of 23)"] = function()
		local bundle = Stubs.with("collapsesReason")
		holdsExactly(bundle, "the reason-collapsing wrapper", { "wiring", "AC-1/AC-3" })
		local message =
			refuses(checkNamed("AC-1/AC-3"), bundle, "a collapsed reason must fail AC-3")
		names(
			message,
			'AC-3: malformed {} at t -> shape -> fields.reason is "invalid" and the Rejection\'s reason is "shape"; the five strings are NET-001\'s contract and are not collapsed or reworded',
			"shape is reworded"
		)
		names(message, 'value.fields.reason: expected "range", got "invalid"', "and so is range")
		lacks(message, "identity -> fields.reason", "identity is intact")
		lacks(message, "phase -> fields.reason", "phase is intact")
		lacks(message, "rate -> fields.reason", "rate is intact")
	end,

	--[[
		AC-4's control, named in the criterion: rawArgs in fields "must fail
		this, and must also fail TEL-001's scalar-fields check when the payload
		is a table - assert both". Both, by name: the needle check finds the
		needle inside fields.rawArgs, and the scalar check finds a table where
		TEL-001 AC-6 allows only scalars. 5 of 23.
	]]
	["AC-4 control (mutation 3): a wrapper putting rawArgs in fields fails the needle check - the hostile string is in fields.rawArgs - AND the scalar check - fields.rawArgs is a table - plus the wiring, AC-1/AC-3 and the table-caller check (5 of 23)"] = function()
		local bundle = Stubs.with("rawArgsInFields")
		holdsExactly(
			bundle,
			"the rawArgs-in-fields wrapper",
			{ "wiring", "AC-1/AC-3", "AC-4", "AC-4 scalar", "table caller" }
		)

		local needle = refuses(checkNamed("AC-4"), bundle, "rawArgs in fields must fail AC-4")
		names(
			needle,
			'the needle "HOSTILE_7f3a" is in the event\'s fields: { count = 1, rawArgs = { flag = true, token = "HOSTILE_7f3a" }',
			"the hostile string reaches the log through rawArgs"
		)
		names(needle, 'the needle "424242" is in the event\'s fields', "and the hostile number")
		names(needle, "write primitive into the log", "and the reason it matters is said")

		local scalar = refuses(
			checkNamed("AC-4 scalar"),
			bundle,
			"a table payload in fields must fail the scalar check"
		)
		names(
			scalar,
			"fields.rawArgs is a table; TEL-001 AC-6: an event's fields are a flat map of string, number or boolean values",
			"TEL-001's rule fires"
		)
		names(
			scalar,
			"Event.new refuses the event the reporter produced",
			"and TEL-001's own constructor refuses it"
		)
	end,

	--[[
		PO decision 2: `detail` is NOT safe. `Schema.describe` quotes a string
		of up to 32 characters verbatim, so copying the detail leaks the needle
		exactly as copying rawArgs does - and the scalar check sees the fourth
		key even though a detail is a string. 5 of 23.
	]]
	["AC-4 control (PO decision 2): a wrapper copying Rejection.detail into fields fails the needle check - the schema quoted the hostile string into the detail - plus the fourth-key half of every event check (5 of 23)"] = function()
		local bundle = Stubs.with("detailInFields")
		holdsExactly(
			bundle,
			"the detail-in-fields wrapper",
			{ "wiring", "AC-1/AC-3", "AC-4", "AC-4 scalar", "table caller" }
		)

		local needle = refuses(checkNamed("AC-4"), bundle, "detail in fields must fail AC-4")
		names(
			needle,
			'the needle "HOSTILE_7f3a" is in the event\'s fields: { count = 1, detail = "shape: field "token": expected an integer in [1, 16], got "HOSTILE_7f3a""',
			"the detail carries the payload verbatim"
		)
		names(
			needle,
			'the needle "424242" is in the event\'s fields',
			"and the number: 424242 is outside [1, 16]"
		)

		local scalar =
			refuses(checkNamed("AC-4 scalar"), bundle, "the fourth key fails the key check")
		names(
			scalar,
			'fields carry keys { 1 = "count", 2 = "detail", 3 = "reason", 4 = "remote" }',
			"detail is a fourth key"
		)
		lacks(
			scalar,
			"is a table; TEL-001 AC-6",
			"a detail is a string, so the scalar rule itself is silent"
		)
	end,

	--[[
		The control that earns the green-on-arrival check: a wrapper indexing
		`context.telemetry` with no nil check raises on every context the
		earlier suites build. It fails the no-telemetry check and six of
		NET-003's eight (AC-4 never rejects and AC-6 never calls the wrapper).
		7 of 23.
	]]
	["control: a wrapper that indexes context.telemetry without a nil check fails the no-telemetry check and six of NET-003's eight - every rejected call on a context without the field raises (7 of 23)"] = function()
		local bundle = Stubs.with("assumesTelemetry")
		holdsExactly(bundle, "the telemetry-assuming wrapper", {
			"no telemetry",
			"NET-003 AC-1",
			"NET-003 AC-2",
			"NET-003 AC-3",
			"NET-003 AC-5",
			"NET-003 detail",
			"NET-003 clock",
		})
		local message = refuses(checkNamed("no telemetry"), bundle, "assuming the field must fail")
		names(
			message,
			"Contract: 7 violation(s)",
			"five raises, the outcome list, and the comparison"
		)
		names(
			message,
			"without telemetry: unseated p2 at t -> identity -> RAISED",
			"the first rejection raises"
		)
		names(message, "attempt to index nil with 'reporter'", "on the field that is not there")
		lacks(
			message,
			"with telemetry: unseated p2 at t -> identity -> RAISED",
			"with the field present nothing raises"
		)
	end,

	["control: a wrapper handing emit a bare event instead of a batch fails the wiring, AC-1/AC-3, both AC-4 checks, the wrapper flood and the table-caller check - a bare event iterates as six events (6 of 23)"] = function()
		local bundle = Stubs.with("emitsBareEvent")
		holdsExactly(
			bundle,
			"the bare-event wrapper",
			{ "wiring", "AC-1/AC-3", "AC-4", "AC-4 scalar", "AC-5 wrapper", "table caller" }
		)
		local message = refuses(checkNamed("wiring"), bundle, "a bare event must fail the wiring")
		names(
			message,
			"a batch of exactly one event, the shape Sink.dispatch consumes",
			"the batch shape is named"
		)
		local flood = refuses(checkNamed("AC-5 wrapper"), bundle, "the flood sees the bare event")
		names(
			flood,
			"10 emit call(s) and 1 flushed event(s), 61 in all",
			"10 bare events read as 60"
		)
		names(flood, "one event per batch", "the batch shape is named there too")
	end,

	["control: a wrapper emitting each event twice fails the wiring, AC-2's positive control, AC-1/AC-3, both AC-4 checks, the wrapper flood and the table-caller check (7 of 23)"] = function()
		local bundle = Stubs.with("emitsTwice")
		holdsExactly(bundle, "the emit-twice wrapper", {
			"wiring",
			"AC-2",
			"AC-1/AC-3",
			"AC-4",
			"AC-4 scalar",
			"AC-5 wrapper",
			"table caller",
		})
		local message = refuses(checkNamed("wiring"), bundle, "emitting twice must fail the wiring")
		names(
			message,
			"unseated p2 at t -> identity -> emit was called 2 time(s) during the call; exactly once",
			"twice is named"
		)
		local flood = refuses(checkNamed("AC-5 wrapper"), bundle, "twice doubles the flood")
		names(
			flood,
			"20 emit call(s) and 1 flushed event(s), 21 in all",
			"twenty emits for ten windows"
		)
		names(
			flood,
			"sum(fields.count) over 21 event(s) is 1889",
			"and the sum double-counts the emitted windows"
		)
	end,

	["control: a wrapper stamping now = 0 instead of the clock's value fails the wiring, AC-1/AC-3 and the table-caller check - record is called with the wrong now and the event's at is wrong (3 of 23)"] = function()
		local bundle = Stubs.with("stampsZero")
		holdsExactly(bundle, "the zero-stamping wrapper", { "wiring", "AC-1/AC-3", "table caller" })
		local message = refuses(checkNamed("wiring"), bundle, "a zero stamp must fail the wiring")
		names(message, "value.now: expected 20, got 0", "record's now is wrong")
		names(message, "value.at: expected 20, got 0", "and so is the emitted at")
	end,
}
