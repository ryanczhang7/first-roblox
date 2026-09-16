--!strict
--[[
	The negative controls for ROUND-005, and the proof that each check in
	`tests/helpers/RoundEndingContract.luau` refuses the implementation it exists
	to catch.

	TWO CRITERIA NAME THEIR CONTROL. AC-3: "an implementation that records a
	quorum failure as `lost` **must** fail this". AC-6: "an implementation that
	keeps ticking a finished round emits a second `ComputeTrace` and **must**
	fail this". Both are asserted below, and so are the controls for the two
	criteria whose wrong implementations the story's `## Notes` name as mutations
	to run at acceptance - the precedence list reordered so `clock` precedes
	`below_quorum` (AC-5, mutation 2) and `<=` where the Contract says `<` (AC-7,
	mutation 1) - plus one for AC-4, which the story does not name and which
	would otherwise have no control at all.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half is
	the one that is easy to leave out and worth the most: a stub that fails EVERY
	check proves only that the checks reject something, and a control that fails
	everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO EXPLICITLY, with the
	number measured here rather than predicted. Two of them do, and both are
	recorded in the story's `## Handoff` mutation table because the story's
	`## Notes` predicts a single red test for each mutation:

	  * `atOrBelow` (mutation 1) fails AC-7 AND AC-2, because AC-2's check
	    asserts the round survives every count at or above the threshold on its
	    way down to crossing it.
	  * `losing` (mutation 3) fails AC-3, AC-2 and AC-5, because AC-2 and AC-5
	    both compare the recorded outcome in full rather than only its reason.

	NOTHING HERE REQUIRES PRODUCTION CODE. Unlike an ordinary RED - where the
	module under test does not exist, the real suite fails at `require` and not
	one assertion in it has executed - `src/server/round/PhaseMachine.luau` is
	merged and `tests/server/round_ending_test.luau` loads. These controls would
	still run if it did not, which is why the numbers they produce are
	measurements rather than claims.
]]

local Deep = require("../helpers/Deep")
local Ending = require("../helpers/RoundEndingContract")
local Stubs = require("../helpers/RoundEndingStubs")

-- The same fixture the real suite injects. See `round_ending_test.luau`'s
-- header: settled numbers, read out of here and never written into an assertion.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

type Check = (any, any) -> ()

local function accepts(check: Check, machine: any, what: string)
	local ok, err = pcall(check, machine, CONFIG)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, machine: any, what: string): string
	local ok, err = pcall(check, machine, CONFIG)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

--[[
	The weak reading of AC-3 that `RoundEndingStubs.losing` is built to pass:
	the round ended, on the right step, and recorded an outcome.

	Written out here rather than described, because the whole point of the losing
	stub is that this is green for it while AC-3 is red. The criterion says so in
	as many words: "a test asserting only 'the round ended' cannot tell them
	apart".
]]
local function weakTheRoundEndedCheck(machine: any, config: any)
	local ended = Ending.endByQuorum(machine, config, "the weak check")
	assert(ended.phase == "Resolution", `the weak check: the round did not end`)
	assert(typeof(ended.outcome) == "table", `the weak check: no outcome was recorded`)
	assert(
		ended.outcome.reason == "below_quorum",
		`the weak check: the reason is {Deep.show(ended.outcome.reason)}`
	)
end

--[[
	The weak reading of AC-6 that `RoundEndingStubs.doubleTracing` is built to
	pass: a `ComputeTrace` was emitted, carrying the round id.

	"At least one" is the assertion everybody writes. AC-6 says EXACTLY one, over
	the whole ending sequence, and that word is the entire difference.
]]
local function weakAtLeastOneComputeTraceCheck(machine: any, config: any)
	local ended, endingEffects = Ending.endByClock(machine, config, "the weak check")
	local collected: { any } = {}
	for _, effect in endingEffects do
		table.insert(collected, effect)
	end
	local _, postEffects = machine.step(ended, Ending.tick(), ended.phaseEnteredAt)
	for _, effect in postEffects do
		table.insert(collected, effect)
	end

	local traces = 0
	for _, effect in collected do
		if effect.kind == "ComputeTrace" then
			traces += 1
			assert(
				effect.roundId == ended.roundId,
				`the weak check: a ComputeTrace carries {Deep.show(effect.roundId)}`
			)
		end
	end
	assert(traces >= 1, `the weak check: no ComputeTrace was emitted at all`)
end

return {
	--[[ The baseline. Every control below is this machine with exactly one
	     defect set, so a control that fires is attributable to that one thing. ]]

	["baseline: a machine that ends a round on outcome, clock or quorum in the Contract's order passes every ROUND-005 check"] = function()
		local machine = Stubs.ending
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the ending machine")
		accepts(
			Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
			machine,
			"AC-2 on the ending machine"
		)
		accepts(
			Ending.quorumIsConsultedOnATick,
			machine,
			"AC-2 (the Tick half) on the ending machine"
		)
		accepts(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"AC-3 on the ending machine"
		)
		accepts(Ending.resolvingEventOutranksTheClock, machine, "AC-4 on the ending machine")
		accepts(
			Ending.resolvingEventOutranksQuorumAndTheClock,
			machine,
			"AC-4 (all three conditions) on the ending machine"
		)
		accepts(Ending.quorumOutranksTheClockInOneStep, machine, "AC-5 on the ending machine")
		accepts(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"AC-6 on the ending machine"
		)
		accepts(Ending.roundContinuesAtExactlyTheThreshold, machine, "AC-7 on the ending machine")
		accepts(
			Ending.unrecognisedEventsAreIgnoredBelowQuorum,
			machine,
			"Contract pin 2 on the ending machine"
		)
		accepts(
			Ending.aResolvedRoundIsNotReResolved,
			machine,
			"Contract pin 5 on the ending machine"
		)
		accepts(
			Ending.aLeaveNamingSomebodyNotSeatedIsIgnoredInRound,
			machine,
			"Contract pin 1 on the ending machine"
		)
	end,

	--[[
		AC-3's control, named in the criterion itself: a quorum failure recorded
		as `lost`.

		It ends the round on the right step, with the right reason, and passes
		the weak "the round ended" check - which is exactly the reading AC-3
		exists to refuse. It also passes AC-1, AC-4, AC-6 and AC-7, so the
		failure is attributable to the one field that differs.
	]]
	["AC-3 control: a machine that records the quorum ending as lost passes a the-round-ended check and fails AC-3"] = function()
		local machine = Stubs.losing
		accepts(
			weakTheRoundEndedCheck,
			machine,
			"a machine that records the quorum ending as lost still ends the round below quorum, "
				.. "with reason below_quorum"
		)
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the losing machine")
		accepts(Ending.resolvingEventOutranksTheClock, machine, "AC-4 on the losing machine")
		accepts(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"AC-6 on the losing machine"
		)
		accepts(Ending.roundContinuesAtExactlyTheThreshold, machine, "AC-7 on the losing machine")

		local message = refuses(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"a machine that records a quorum failure as lost must fail AC-3"
		)
		names(message, "AC-3", "the AC-3 control fires")
		--[[
			The MEASURED value, pinned here rather than described in the story:
			the control records `lost` where the Contract says `no_contest`, and
			this is the fragment GREEN confirms against the shipped module.
		]]
		names(
			message,
			'the result recorded is "lost"',
			"the AC-3 failure names the result the control actually recorded"
		)
	end,

	--[[
		The two other checks `losing` fails, measured rather than predicted.

		AC-2 and AC-5 both compare the recorded outcome in full - `result` as
		well as `reason` - so mutation 3 of the story's `## Notes` makes three
		tests red, not one. Recorded here so the orchestrator running that
		mutation at acceptance reads a number it was told to expect.
	]]
	["AC-3 control: the losing machine also fails AC-2 and AC-5, because both compare the whole outcome"] = function()
		local machine = Stubs.losing
		names(
			refuses(
				Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
				machine,
				"AC-2 compares the whole outcome, so a lost result fails it too"
			),
			"AC-2",
			"AC-2 fires on the losing machine"
		)
		names(
			refuses(
				Ending.quorumOutranksTheClockInOneStep,
				machine,
				"AC-5 asserts result no_contest as well as reason below_quorum"
			),
			'recorded result "lost", wanted "no_contest"',
			"AC-5's failure on the losing machine names the result it measured"
		)
	end,

	--[[
		AC-6's control, named in the criterion: a machine that keeps ticking a
		finished round.

		It emits a `ComputeTrace` on the way out of `Round` and another on the
		`Resolution -> Post` tick. Every outcome it records is correct, so AC-1
		through AC-5 and AC-7 are green for it, and the weak "at least one
		ComputeTrace" check is green for it too. Only counting sees it.
	]]
	["AC-6 control: a machine that emits a ComputeTrace on the way out of Round passes an at-least-one check and fails AC-6"] = function()
		local machine = Stubs.doubleTracing
		accepts(
			weakAtLeastOneComputeTraceCheck,
			machine,
			"a machine that traces twice still emits a ComputeTrace carrying the round id"
		)
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the double-tracing machine")
		accepts(
			Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
			machine,
			"AC-2 on the double-tracing machine"
		)
		accepts(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"AC-3 on the double-tracing machine"
		)
		accepts(
			Ending.resolvingEventOutranksTheClock,
			machine,
			"AC-4 on the double-tracing machine"
		)
		accepts(
			Ending.quorumOutranksTheClockInOneStep,
			machine,
			"AC-5 on the double-tracing machine"
		)
		accepts(
			Ending.roundContinuesAtExactlyTheThreshold,
			machine,
			"AC-7 on the double-tracing machine"
		)

		local message = refuses(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"a machine that emits a ComputeTrace on the way out of Round must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
		-- The MEASURED count: two, where the criterion says exactly one.
		names(
			message,
			"emitted 2 ComputeTrace effect(s)",
			"the AC-6 failure carries the number of traces it actually counted"
		)
	end,

	--[[
		AC-5's control: the precedence list reordered so `clock` precedes
		`below_quorum`, and nothing else changed.

		This is mutation 2 of the story's `## Notes`. It still ends a round
		`no_contest` when the count falls before the clock is due, and a
		`RoundResolved` still wins, so AC-1, AC-2, AC-3, AC-4, AC-6 and AC-7 are
		all green for it. Only the single step on which BOTH conditions hold
		tells them apart - which is why AC-5 is checked on one step and not on
		two.
	]]
	["AC-5 control: a machine whose precedence puts clock before below_quorum passes AC-1 to AC-4 and fails AC-5"] = function()
		local machine = Stubs.clockFirst
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the clock-first machine")
		accepts(
			Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
			machine,
			"AC-2 on the clock-first machine"
		)
		accepts(
			Ending.quorumIsConsultedOnATick,
			machine,
			"AC-2 (the Tick half, with the clock not yet due) on the clock-first machine"
		)
		accepts(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"AC-3 on the clock-first machine"
		)
		accepts(Ending.resolvingEventOutranksTheClock, machine, "AC-4 on the clock-first machine")
		accepts(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"AC-6 on the clock-first machine"
		)
		accepts(
			Ending.roundContinuesAtExactlyTheThreshold,
			machine,
			"AC-7 on the clock-first machine"
		)

		local message = refuses(
			Ending.quorumOutranksTheClockInOneStep,
			machine,
			"a machine that evaluates the clock before quorum must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
		-- The MEASURED reason: `clock`, where the precedence list says
		-- `below_quorum`.
		names(
			message,
			'the reason recorded is "clock"',
			"the AC-5 failure names the reason the control actually recorded"
		)
	end,

	--[[
		AC-7's control: `<=` where the Contract says `<`.

		This is mutation 1 of the story's `## Notes`, and the off-by-one that
		would silently end every three-player round. Whenever it does end a
		round the outcome is right, so AC-1, AC-3, AC-5 and AC-6 are green for
		it.
	]]
	["AC-7 control: a machine comparing with <= instead of < passes AC-1, AC-3, AC-5 and AC-6 and fails AC-7"] = function()
		local machine = Stubs.atOrBelow
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the at-or-below machine")
		accepts(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"AC-3 on the at-or-below machine"
		)
		accepts(Ending.quorumOutranksTheClockInOneStep, machine, "AC-5 on the at-or-below machine")
		accepts(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"AC-6 on the at-or-below machine"
		)

		local message = refuses(
			Ending.roundContinuesAtExactlyTheThreshold,
			machine,
			"a machine that ends the round AT minPlayersToContinue must fail AC-7"
		)
		names(message, "AC-7", "the AC-7 control fires")
		-- The MEASURED phase: the round the criterion says continues has ended.
		names(
			message,
			"and the phase is Resolution",
			"the AC-7 failure names the phase the control actually reached"
		)
	end,

	--[[
		The second check `atOrBelow` fails, measured rather than predicted.

		AC-2's check asserts the round survives every count at or above the
		threshold on its way down to crossing it, so mutation 1 makes two tests
		red and not the one the story's `## Notes` predicts. That is a stronger
		suite, not a defect, and the number belongs in the story rather than in a
		surprise at acceptance.
	]]
	["AC-7 control: the at-or-below machine also fails AC-2, which asserts the descent as well as the crossing"] = function()
		names(
			refuses(
				Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
				Stubs.atOrBelow,
				"AC-2 asserts the round is still in Round at exactly minPlayersToContinue"
			),
			"AC-2",
			"AC-2 fires on the at-or-below machine"
		)
		names(
			refuses(
				Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
				Stubs.atOrBelow,
				"AC-2 asserts the round is still in Round at exactly minPlayersToContinue"
			),
			"and the phase is already Resolution",
			"AC-2's failure on the at-or-below machine names the phase it measured"
		)
	end,

	--[[
		AC-4's control, which the story does not name and which AC-4 would
		otherwise be without: the clock outranking a `RoundResolved` that arrived
		on the same step.

		Every ending that is not simultaneous with the clock is correct, so AC-1,
		AC-2, AC-3, AC-5, AC-6 and AC-7 are green for it. So is the test everyone
		writes first - advance the clock, THEN send the event - because by then
		the round has already ended and the event is arriving at a `Resolution`,
		where ROUND-003 AC-7 ignores it. That reading is asserted here, because
		it is the reason AC-4 is checked on one step.
	]]
	["AC-4 control: a machine where the clock outranks a simultaneous RoundResolved passes a two-step test and fails AC-4"] = function()
		local machine = Stubs.eventLoses
		accepts(Ending.roundEndsOnTheClock, machine, "AC-1 on the event-loses machine")
		accepts(
			Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold,
			machine,
			"AC-2 on the event-loses machine"
		)
		accepts(
			Ending.quorumEndingIsDistinguishableFromALoss,
			machine,
			"AC-3 on the event-loses machine"
		)
		accepts(Ending.quorumOutranksTheClockInOneStep, machine, "AC-5 on the event-loses machine")
		accepts(
			Ending.endingSequenceEmitsExactlyOneComputeTrace,
			machine,
			"AC-6 on the event-loses machine"
		)
		accepts(
			Ending.roundContinuesAtExactlyTheThreshold,
			machine,
			"AC-7 on the event-loses machine"
		)

		-- The two-step reading, which is green for this machine and green for a
		-- correct one: the round ends on the clock, and the event that arrives
		-- afterwards is ignored in Resolution.
		local round = Ending.roundOf(machine, CONFIG, CONFIG.playersMin)
		local expired = round.phaseEnteredAt + CONFIG.roundSeconds + 5
		local ended = machine.step(round, Ending.tick(), expired)
		local afterwards = machine.step(ended, Ending.resolved(Ending.eventOutcome()), expired + 1)
		assert(
			Deep.equal(ended.outcome, afterwards.outcome),
			`the two-step reading must be green for this machine, or it is not the control AC-4 `
				.. `needs: the outcome changed from {Deep.show(ended.outcome)} to `
				.. `{Deep.show(afterwards.outcome)}`
		)

		local message = refuses(
			Ending.resolvingEventOutranksTheClock,
			machine,
			"a machine in which the clock outranks a simultaneous RoundResolved must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires")
		-- The MEASURED outcome: the clock's, where the event's was carried in.
		names(
			message,
			'the outcome recorded is { reason = "clock", result = "lost" }',
			"the AC-4 failure names the outcome the control actually recorded"
		)

		names(
			refuses(
				Ending.resolvingEventOutranksQuorumAndTheClock,
				machine,
				"the same machine must fail AC-4's three-condition step"
			),
			"AC-4",
			"the AC-4 control fires on the three-condition step too"
		)
	end,
}
