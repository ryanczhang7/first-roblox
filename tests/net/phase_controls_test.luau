--!strict
--[[
	The negative controls for NET-002, and the proof that each check in
	`tests/helpers/PhaseContract.luau` refuses the bundle it exists to catch.

	TWO CRITERIA NAME THEIR CONTROL. AC-4: an implementation comparing only
	against the first entry of `legalPhases` "passes AC-1 and AC-2 and must
	fail this". AC-6: an implementation that captures the phase when the
	remote is guarded "passes every test that never changes phase, and must
	fail a test that guards once and calls in two different phases". Both are
	asserted below in exactly those terms - the passes as well as the failure.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, including
	NET-001's twelve wrapper and registry checks, which is the half that is
	easy to leave out and worth the most: it shows the phase check is a layer
	NET-001's suite cannot see unless it is wrong in a phase-independent way
	(rejecting everything), and that a control failing the phase checks is a
	control with ONE defect rather than a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	MEASURED here rather than predicted - measured first outside the runner
	(`## Handoff`), then pinned. The captured-phase control fails AC-6 and
	the Contract's short-circuit check, because the latter counts
	`context.phase()` reads per call and a captured phase reads none. The
	story's prediction "AC-6 goes red alone" holds among the criteria.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The bundles are
	`PhaseStubs.luau` over `NetStubs.luau`, so these controls EXECUTE in RED,
	while `phase_test.luau`'s assertions against the real `src/net/` are
	red on their own terms.
]]

local NetContract = require("../helpers/NetContract")
local PhaseContract = require("../helpers/PhaseContract")
local Stubs = require("../helpers/PhaseStubs")

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

local PHASE_CHECKS: { Named } = {
	{ label = "AC-1", check = PhaseContract.handlerRunsInTheOnlyLegalPhase },
	{ label = "AC-2", check = PhaseContract.outOfPhaseCallIsRejectedForPhase },
	{ label = "AC-3", check = PhaseContract.earlierChecksWinOverPhase },
	{ label = "AC-4", check = PhaseContract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse },
	{ label = "AC-5", check = PhaseContract.emptyLegalPhasesIsADeclarationError },
	{ label = "AC-6", check = PhaseContract.phaseIsReadAtTheMomentOfEachCall },
	{
		label = "detail",
		check = PhaseContract.phaseRejectionDetailNamesTheCurrentAndEveryLegalPhase,
	},
	{ label = "short-circuit", check = PhaseContract.phaseIsNotConsultedWhenAnEarlierCheckFails },
}

-- NET-001's wrapper and registry checks, held over every bundle here: the
-- phase layer must be invisible to them unless it is wrong for every phase.
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
for _, group in { PHASE_CHECKS, NET001_CHECKS } do
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
	     phase-enforcing wrapper still satisfies NET-001. ]]

	["baseline: a correct phase-enforcing bundle passes all 8 phase checks and all 12 of NET-001's wrapper and registry checks"] = function()
		assert(#ALL_CHECKS == 20, `expected 20 checks, found {#ALL_CHECKS}`)
		holdsExactly(Stubs.correct(), "the baseline", {})
	end,

	--[[
		AC-4's control, named in the criterion: "passes AC-1 and AC-2 and must
		fail this". Asserted word for word, and it fails NOTHING ELSE of 20 -
		every other check declares a one-phase remote, for which the first
		entry is the list. Measured: 1 of 20, on the two legal phases that
		are not first.
	]]
	["AC-4 control: a wrapper comparing only the first entry of legalPhases passes AC-1, AC-2 and every other check, and fails AC-4 alone - on Round and Post, the two legal phases that are not first (1 of 20)"] = function()
		local net = Stubs.with("firstEntryOnly")
		holdsExactly(net, "the first-entry-only wrapper", { "AC-4" })

		local message =
			refuses(checkNamed("AC-4"), net, "comparing the first entry only must fail AC-4")
		names(message, "AC-4: 2 violation(s) across 5 phases", "exactly the two other legal phases")
		names(
			message,
			'a valid call while the phase is Round (legal) -> REJECTED: reason = "phase"',
			"Round, the middle entry, is refused"
		)
		names(
			message,
			'a valid call while the phase is Post (legal) -> REJECTED: reason = "phase"',
			"Post, the last entry, is refused"
		)
		lacks(message, "Lobby (legal) -> REJECTED", "Lobby, the first entry, is accepted")
		lacks(message, "(not legal) -> ACCEPTED", "the illegal phases are still refused")
	end,

	["AC-4 control (mirror): a wrapper comparing only the last entry fails AC-4 alone, on Lobby and Round (1 of 20)"] = function()
		local net = Stubs.with("lastEntryOnly")
		holdsExactly(net, "the last-entry-only wrapper", { "AC-4" })

		local message =
			refuses(checkNamed("AC-4"), net, "comparing the last entry only must fail AC-4")
		names(message, "AC-4: 2 violation(s) across 5 phases", "exactly the two other legal phases")
		names(message, "Lobby (legal) -> REJECTED", "Lobby is refused")
		names(message, "Round (legal) -> REJECTED", "Round is refused")
		lacks(message, "Post (legal) -> REJECTED", "Post, the last entry, is accepted")
	end,

	--[[
		AC-6's control, named in the criterion: "passes every test that never
		changes phase, and must fail a test that guards once and calls in two
		different phases". It PASSES AC-1, AC-2, AC-3, AC-4, AC-5, the detail
		check and all twelve of NET-001's - every one of which builds a fresh
		guard per phase - and FAILS AC-6, plus the Contract's short-circuit
		check, which counts `context.phase()` reads during the call and finds
		none. Measured: 2 of 20; among the criteria, AC-6 alone.
	]]
	["AC-6 control: a wrapper that captures the phase when guard() is called passes every check that never changes phase - AC-1 to AC-5, detail, and NET-001's twelve - and fails AC-6 on 5 of 7 calls, plus the short-circuit read count (2 of 20)"] = function()
		local net = Stubs.with("capturesPhaseAtGuard")
		holdsExactly(net, "the captured-phase wrapper", { "AC-6", "short-circuit" })

		local message = refuses(checkNamed("AC-6"), net, "a captured phase must fail AC-6")
		names(message, "AC-6: 5 violation(s) across 7 calls", "the moved-phase calls are reported")
		names(
			message,
			"captures the phase when the remote is guarded fails here",
			"the AC-6 failure says what it caught"
		)
		names(
			message,
			'guarded in Lobby, call 2 while the phase is Round -> REJECTED: reason = "phase", detail = "the phase is Lobby; legal in Round"',
			"the guard built in Lobby still sees Lobby once the world is in Round"
		)
		names(
			message,
			"guarded in Round, call 2 while the phase is Assignment -> ACCEPTED (returned nil)",
			"the guard built in Round still sees Round once the world is in Assignment"
		)
		names(
			message,
			"the handler ran 0 time(s) over 4 calls; 2 were in phase",
			"the first handler never ran"
		)

		local short = refuses(
			checkNamed("short-circuit"),
			net,
			"a captured phase reads context.phase() zero times during a call"
		)
		names(short, "short-circuit: 1 violation(s) across 4 calls", "only the read count fires")
		names(
			short,
			"context.phase() was not consulted, yet the call was judged on its phase",
			"the missing read is named"
		)
	end,

	--[[ The pre-NET-002 wrapper: what the real suite fails on arrival. ]]

	["control: a wrapper with no phase check fails AC-2, AC-3, AC-4, AC-6, detail and short-circuit, and passes AC-1, AC-5 and all of NET-001 (6 of 20)"] = function()
		local net = Stubs.with("ignoresPhase")
		holdsExactly(
			net,
			"the phase-blind wrapper",
			{ "AC-2", "AC-3", "AC-4", "AC-6", "detail", "short-circuit" }
		)

		local message = refuses(checkNamed("AC-2"), net, "ignoring the phase must fail AC-2")
		names(
			message,
			"AC-2: 5 violation(s) across 4 out-of-phase calls",
			"all four phases plus the handler"
		)
		for _, phase in { "Lobby", "Assignment", "Resolution", "Post" } do
			names(
				message,
				`while the phase is {phase} -> ACCEPTED (returned nil); the handler was reachable`,
				`{phase} is named`
			)
		end
		names(
			message,
			"the handler ran 4 time(s) across 4 out-of-phase calls; it must not run at all",
			"the handler count is reported"
		)
		local order = refuses(checkNamed("AC-3"), net, "ignoring the phase must fail AC-3")
		names(
			order,
			"AC-3: 5 violation(s) across 12 calls",
			"the two phase-only cases and the handler counts"
		)
		lacks(order, 'expected "shape"', "every shape case still passes: shape is not this defect")
	end,

	--[[ The mutations `## Notes` asks the orchestrator to run at acceptance. ]]

	["mutation 3 control: the phase check ahead of the schema fails AC-3 on 8 of 12 calls and short-circuit on 4 of 4, and passes AC-2, AC-4 and AC-6 - a valid payload cannot see the order (2 of 20)"] = function()
		local net = Stubs.with("phaseBeforeShape")
		holdsExactly(net, "the phase-before-shape wrapper", { "AC-3", "short-circuit" })

		local message = refuses(checkNamed("AC-3"), net, "phase before shape must fail AC-3")
		names(
			message,
			"AC-3: 8 violation(s) across 12 calls",
			"every malformed and out-of-range case"
		)
		names(
			message,
			'seated + {} (arity), out of phase -> shape -> rejected for "phase", expected "shape"',
			"the criterion's own case is named"
		)
		names(
			message,
			'seated + { token = 99, flag = true } (range), out of phase -> range -> rejected for "phase", expected "range"',
			"range is displaced too"
		)
		names(
			message,
			"the schema was consulted 0 time(s) before the phase rejection",
			"the spy schema saw nothing"
		)
		lacks(
			message,
			'-> identity -> rejected for "phase"',
			"identity still wins: this defect is behind the seat check"
		)

		local short =
			refuses(checkNamed("short-circuit"), net, "phase before shape reads the phase early")
		names(
			short,
			"short-circuit: 4 violation(s) across 4 calls",
			"shape and range each fire twice"
		)
		names(
			short,
			"a malformed payload (shape) -> context.phase() was consulted 1 time(s)",
			"the early read is counted"
		)
	end,

	["control: the phase check ahead of everything fails AC-3 on 9 of 12 - identity displaced as well - and short-circuit on 6 of 4 lines (2 of 20)"] = function()
		local net = Stubs.with("phaseBeforeIdentity")
		holdsExactly(net, "the phase-first wrapper", { "AC-3", "short-circuit" })

		local message = refuses(checkNamed("AC-3"), net, "phase first must fail AC-3")
		names(message, "AC-3: 9 violation(s) across 12 calls", "identity joins the displaced cases")
		names(
			message,
			'unseated + valid payload, out of phase -> identity -> rejected for "phase", expected "identity"',
			"the unseated case is named"
		)
		local short =
			refuses(checkNamed("short-circuit"), net, "phase first reads the phase for everyone")
		names(short, "short-circuit: 6 violation(s) across 4 calls", "three cases, two lines each")
		names(
			short,
			"an unseated caller (identity) -> context.phase() was consulted 1 time(s)",
			"the read for an unseated caller is counted"
		)
	end,

	--[[ The one-defect bundles the remaining checks would otherwise have no
	     control for. Each is a plausible wrong implementation. ]]

	["control: a wrapper that rejects out of phase but says shape fails AC-2 on 4 of 4, AC-3, AC-4, AC-6, detail and short-circuit, and passes AC-1, AC-5 and NET-001 (6 of 20)"] = function()
		local net = Stubs.with("phaseReasonIsShape")
		holdsExactly(
			net,
			"the wrong-reason wrapper",
			{ "AC-2", "AC-3", "AC-4", "AC-6", "detail", "short-circuit" }
		)
		local message = refuses(checkNamed("AC-2"), net, "the wrong reason must fail AC-2")
		names(message, "AC-2: 4 violation(s) across 4 out-of-phase calls", "every phase")
		names(
			message,
			'while the phase is Lobby -> rejected for "shape", expected "phase"',
			"the reason is named"
		)
		lacks(message, "the handler ran", "the handler did not run: only the reason is wrong")
	end,

	["control: a wrapper that runs the handler before rejecting for phase fails AC-2, AC-3, AC-4, AC-6 and short-circuit on handler counts alone, and passes detail (5 of 20)"] = function()
		local net = Stubs.with("runsHandlerOnPhaseReject")
		holdsExactly(
			net,
			"the handler-first wrapper",
			{ "AC-2", "AC-3", "AC-4", "AC-6", "short-circuit" }
		)
		local message = refuses(checkNamed("AC-2"), net, "running the handler must fail AC-2")
		names(message, "AC-2: 1 violation(s) across 4 out-of-phase calls", "only the handler count")
		names(
			message,
			"the handler ran 4 time(s) across 4 out-of-phase calls; it must not run at all",
			"the count is named"
		)
		lacks(message, "ACCEPTED", "every call was still rejected")
		local multi = refuses(checkNamed("AC-4"), net, "running the handler must fail AC-4")
		names(
			multi,
			"Assignment (not legal) -> the handler ran 1 time(s), expected 0",
			"per-phase handler counts"
		)
	end,

	--[[
		The positive control. A wrapper for which no phase is legal PASSES
		AC-2 - every out-of-phase call is rejected for phase - and fails the
		checks that accept a call: AC-1, AC-3's in-phase call, AC-4's three
		legal phases, AC-6's four in-phase calls, and NET-001's four positive
		checks. Measured: 8 of 20. This is what earns AC-1's green arrival.
	]]
	["control: a wrapper that rejects every phase passes AC-2, AC-5, detail and short-circuit, and fails AC-1, AC-3, AC-4, AC-6 and NET-001's AC-1, AC-5, short-circuit and kind mapping (8 of 20)"] = function()
		local net = Stubs.with("rejectsEveryPhase")
		holdsExactly(net, "the reject-every-phase wrapper", {
			"AC-1",
			"AC-3",
			"AC-4",
			"AC-6",
			"NET-001 AC-1",
			"NET-001 AC-5",
			"NET-001 short-circuit",
			"NET-001 kind mapping",
		})
		local message = refuses(checkNamed("AC-1"), net, "rejecting every phase must fail AC-1")
		names(
			message,
			'in the remote\'s only legal phase was rejected: reason = "phase", detail = "the phase is Round; legal in Round"',
			"AC-1 shows the rejection the in-phase call got"
		)
		local multi = refuses(checkNamed("AC-4"), net, "rejecting every phase must fail AC-4")
		names(multi, "AC-4: 3 violation(s) across 5 phases", "exactly the three legal phases")
	end,

	--[[ The Contract's `detail` block, one control per clause. ]]

	['detail control: a detail leading with "phase: " fails the detail check alone (1 of 20)'] = function()
		local net = Stubs.with("prefixedDetail")
		holdsExactly(net, "the prefixed-detail wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "a phase: prefix must fail")
		names(message, "detail failed in 1 way(s)", "one clause")
		names(message, 'detail leads with "phase:"', "the prefix is named")
	end,

	["detail control: a detail naming only the legal phases fails the detail check alone, missing Lobby (1 of 20)"] = function()
		local net = Stubs.with("detailOmitsCurrent")
		holdsExactly(net, "the no-current-phase wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "omitting the current phase must fail")
		names(message, "detail failed in 1 way(s)", "one clause")
		names(message, "detail does not name the current phase Lobby", "the missing half is named")
	end,

	["detail control: a detail naming only the current phase fails the detail check alone, missing Round and Post (1 of 20)"] = function()
		local net = Stubs.with("detailOmitsLegal")
		holdsExactly(net, "the no-legal-phases wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "omitting the legal phases must fail")
		names(message, "detail failed in 2 way(s)", "both legal phases")
		names(message, "detail does not name the legal phase Round", "Round is named")
		names(message, "detail does not name the legal phase Post", "Post is named")
	end,

	["detail control: a detail listing all five phases fails the detail check alone, on Assignment and Resolution - the negation that makes 'contains' mean something (1 of 20)"] = function()
		local net = Stubs.with("detailListsEveryPhase")
		holdsExactly(net, "the list-everything wrapper", { "detail" })
		local message = refuses(checkNamed("detail"), net, "listing every phase must fail")
		names(message, "detail failed in 2 way(s)", "the two phases that are neither")
		names(
			message,
			"detail names Assignment, which is neither the current phase nor a legal one",
			"Assignment"
		)
		names(
			message,
			"detail names Resolution, which is neither the current phase nor a legal one",
			"Resolution"
		)
	end,

	--[[ AC-5's controls: the pre-NET-002 registry, and a poisoning refusal. ]]

	["AC-5 control: a registry that accepts an empty legalPhases fails AC-5 alone (1 of 20)"] = function()
		local net = Stubs.with("acceptsEmptyLegalPhases")
		holdsExactly(net, "the accepting registry", { "AC-5" })
		local message = refuses(checkNamed("AC-5"), net, "accepting {} must fail AC-5")
		names(
			message,
			"with an empty legalPhases did not fail; define returned",
			"AC-5 reports the accepted declaration"
		)
	end,

	["AC-5 control: a registry that registers the name before refusing it fails AC-5 alone, on the registry count (1 of 20)"] = function()
		local net = Stubs.with("registersBeforeRefusing")
		holdsExactly(net, "the poisoning registry", { "AC-5" })
		local message =
			refuses(checkNamed("AC-5"), net, "registering before refusing must fail AC-5")
		names(
			message,
			"entries after the refused declaration; it had",
			"AC-5 reports the registry growing"
		)
	end,
}
