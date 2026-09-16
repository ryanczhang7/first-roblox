--!strict
--[[
	ROUND-005: a round ends on outcome, clock or quorum with a deterministic
	reason. AC-1 through AC-7, applied to the real machine.

	THIS IS NOT AN ORDINARY RED. `ROUND-003` and `ROUND-004` are merged, their
	154 tests are frozen and green, and `src/server/round/PhaseMachine.luau`
	already exists - so this file LOADS, every assertion in it RUNS, and the
	failures are real assertion failures rather than one import error wearing
	seven criteria. Two consequences, both recorded in the story:

	  * ONE test below is GREEN ON ARRIVAL. Today `PlayerLeft` is ignored in
	    every phase but the Lobby, so "a PlayerLeft naming somebody not seated is
	    ignored in Round" passes for a reason that has nothing to do with the
	    criterion. A test that has never been observed to fail is not a test, so
	    it is earned by a reverted `scripts/mutate.sh` probe of the specific
	    production behaviour it pins - probe 2 in the story's `## Regressions`.
	    The two AC-4 tests are green on arrival for the same class of reason (the
	    machine records the event's outcome and does not consult a clock it does
	    not have) and are earned by probe 3.
	  * the negative controls in
	    `tests/server/round_ending_controls_test.luau` run for real in RED rather
	    than being promised for GREEN, because they need no production code.

	WHAT THE REST OF THE SUITE DOES NOT COVER, and why these tests exist even
	though the Round phase is already exercised: today nothing ends a round
	except a `RoundResolved` event. There is no clock in `Round`, no quorum
	anywhere, and a mid-round departure does nothing at all.

	THE CONFIG IS INJECTED AND TINY, and it is deliberately the SAME fixture
	`tests/server/phase_machine_test.luau` and `tests/server/lobby_gate_test.luau`
	use: a whole lifecycle runs in simulated seconds, and a machine reaching for
	`Tuning` instead of the config it was handed fails rather than merely running
	slowly.

	THE NUMBERS ARE SETTLED AND NOTHING HERE CALIBRATES ONE. `round_seconds` and
	`min_players_to_continue` (3, derived: a 3-cycle ring is still a ring) come
	from `ROUND-002` through `RoundConfig` (`docs/wiki/game/tuning.md` section
	1). No assertion below writes one of them: every threshold is read out of
	`CONFIG`, through the checks in `tests/helpers/RoundEndingContract.luau`.
]]

local Deep = require("../helpers/Deep")
local Ending = require("../helpers/RoundEndingContract")
local PhaseMachine = require("../../src/server/round/PhaseMachine")

local Machine: any = PhaseMachine

-- Fixture durations and thresholds, not specification values. See the header.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

return {
	--[[ AC-1. The clock, at the boundary and either side of it. ]]

	["AC-1: the clock ends the round at exactly roundSeconds elapsed, as lost(clock), and not before"] = function()
		Ending.roundEndsOnTheClock(Machine, CONFIG)
	end,

	--[[ AC-2. Quorum, by each of the two events that consult it. ]]

	["AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step"] = function()
		Ending.roundEndsNoContestWhenTheCountFallsBelowTheThreshold(Machine, CONFIG)
	end,

	["AC-2: a Tick on a round already below min_players_to_continue ends it no_contest"] = function()
		Ending.quorumIsConsultedOnATick(Machine, CONFIG)
	end,

	--[[ AC-3. The difference a test asserting "the round ended" cannot see. ]]

	["AC-3: a round that ended below quorum records no_contest and never lost"] = function()
		Ending.quorumEndingIsDistinguishableFromALoss(Machine, CONFIG)
	end,

	--[[
		AC-4. ONE step on which two conditions hold, constructed directly.

		GREEN ON ARRIVAL: the machine already records a RoundResolved outcome
		verbatim (ROUND-003 AC-3) and has no round clock to lose to, so both of
		these pass today for a reason the criterion is not about. Earned by probe
		3 in the story's `## Regressions`, which makes the RoundResolved branch
		record `lost(clock)` instead of the outcome the event carried.
	]]

	["AC-4: a RoundResolved arriving on the step the clock expired records the outcome the event carried"] = function()
		Ending.resolvingEventOutranksTheClock(Machine, CONFIG)
	end,

	["AC-4: a RoundResolved outranks quorum and the clock when all three hold on one step"] = function()
		Ending.resolvingEventOutranksQuorumAndTheClock(Machine, CONFIG)
	end,

	--[[ AC-5. The pair the precedence list exists for, on one step and twice
	     over, because "the same on every run" is a claim about repetition. ]]

	["AC-5: when the clock and quorum both fall on one step the reason is below_quorum, on every run"] = function()
		Ending.quorumOutranksTheClockInOneStep(Machine, CONFIG)
	end,

	--[[ AC-6. Read over the ending SEQUENCE - the ending step plus every step
	     from it through Post and back to Lobby. See the check's own comment. ]]

	["AC-6: each of the three endings emits exactly one ComputeTrace, carrying the round id, across the ending sequence"] = function()
		Ending.endingSequenceEmitsExactlyOneComputeTrace(Machine, CONFIG)
	end,

	--[[ AC-7. The boundary: "below", not "at or below". ]]

	["AC-7: a departure to exactly min_players_to_continue leaves the round running"] = function()
		Ending.roundContinuesAtExactlyTheThreshold(Machine, CONFIG)
	end,

	--[[
		AC-7 stated directly on the comparison, in the shape a `<=`
		implementation cannot survive: the round that continues is a round of
		exactly `minPlayersToContinue`, and it still ends when one more leaves.
	]]
	["AC-7: a round at exactly min_players_to_continue still ends when one more player leaves"] = function()
		local round = Ending.roundOf(Machine, CONFIG, CONFIG.playersMin)
		local state = round
		local now = round.phaseEnteredAt

		for index = 1, CONFIG.playersMin - CONFIG.minPlayersToContinue + 1 do
			now = round.phaseEnteredAt + index
			state = Machine.step(state, Ending.left(`p{index + 1}`), now)
		end

		assert(
			state.phase == "Resolution",
			`AC-7: a round held at exactly minPlayersToContinue `
				.. `({CONFIG.minPlayersToContinue}) and then lost one more player is in `
				.. `{tostring(state.phase)} at now = {now}. "Below" is a threshold, not a floor `
				.. `the round sits on forever`
		)
		local expected = Ending.quorumOutcome()
		assert(
			Deep.equal(state.outcome, expected),
			`AC-7/AC-2: the round ended with {Deep.show(state.outcome)}:\n`
				.. Deep.diff(expected, state.outcome)
		)
	end,

	--[[ Contract pin 2: quorum is consulted on Tick and on PlayerLeft, and
	     never for an event the phase does not recognise. ROUND-003 AC-7 is
	     frozen and has no exception for a terminal condition that already
	     holds. ]]

	["Contract pin 2: an unrecognised event at a Round below quorum is ignored, and the next Tick ends the round"] = function()
		Ending.unrecognisedEventsAreIgnoredBelowQuorum(Machine, CONFIG)
	end,

	--[[ Contract pin 5: outcome is written once, by the step that ended the
	     round. ]]

	["Contract pin 5: a round that already resolved is not re-resolved by a clock that expired afterwards"] = function()
		Ending.aResolvedRoundIsNotReResolved(Machine, CONFIG)
	end,

	--[[
		Contract pin 1, the half AC-7 does not reach.

		GREEN ON ARRIVAL - see the header and the check's own comment. Earned by
		probe 2 in the story's `## Regressions`.
	]]
	["Contract pin 1: a PlayerLeft in Round naming a player who is not seated is ignored"] = function()
		Ending.aLeaveNamingSomebodyNotSeatedIsIgnoredInRound(Machine, CONFIG)
	end,
}
