--!strict
--[[
	SLICE-005: the session runs the facility and the Procedure, and scripted
	turns win or lose a round. AC-1 through AC-6 and the story's Contract pins
	(C-1..C-5), applied to the real `src/server/session/Session.luau` over the
	real `PhaseMachine`, `Ring`, `Generator`, `Procedure` and `TurnRequests`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `session_test.luau` does. In RED it exists but holds none of
	this story's behaviour - no facility, no procedure, no Placed, no
	TurnResult - so every test below FAILS on its own assertion, naming what is
	missing. It is not a skip.

	THE CHECKS, THE ORACLE AND THE PLANS LIVE IN
	`tests/helpers/SessionRoundContract.luau`; the scripted players in
	`tests/helpers/ScriptedRound.luau` (shared with SLICE-006). Both are
	exercised against a reference stand-in and deliberately wrong stand-ins in
	`tests/server/session_round_controls_test.luau`, where each check is
	OBSERVED to fire. That matters in RED, because today's Session fails every
	check here before most assertions in them have run.

	THE ORACLE PARTITION (story C-10): AC-1, AC-2, AC-3, AC-6 and C-3/C-4/C-5
	are mechanical - the facility, Procedure, turn results and deadlines are
	computed by stepping the pure modules in the helper, never hand-copied.
	AC-4 and AC-5 are settled - a scripted outcome, each with a control.

	WHAT THIS FILE DOES NOT PIN: where `tuning` and `generatorPredicate` live
	on the state (any extra key is fine), the wording of any error, whether
	the RoundView or the centre is built in this module or a helper, and how
	`Session` reaches the pure modules.
]]

local Contract = require("../helpers/SessionRoundContract")

local loaded, loadResult = pcall(require, "../../src/server/session/Session")

local function Session(): any
	assert(loaded, `src/server/session/Session.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ C-1, C-3: the state's shape and provenance ]]

	["Contract (C-1): Session.new holds facility = nil, procedure = nil and positions = {}, and accepts an optional fifth options argument carrying generatorPredicate"] = function()
		Contract.newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions(Session())
	end,

	["Contract (C-3): after every step of a two-round lifecycle with samples, turns, a penalised clock-out and a failed generation, state.round, assignment, facility, procedure and positions deep-equal the Contract's own composition of PhaseMachine, Ring, Generator, Procedure and TurnRequests"] = function()
		Contract.roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep(Session())
	end,

	--[[ AC-1 ]]

	["AC-1: on each of two deals state.facility deep-equals Generator.generate(dealt, effect.seed, tuning).facility and state.procedure deep-equals Procedure.start(facility, now, tuning, effect.seed, config.roundSeconds) - the seeds differ, so a fixed or reused seed fails on the second"] = function()
		Contract.generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep(Session())
	end,

	["AC-1: the dealing step emits one Placed { playerId, position } per seated player in seat order at the spawn room's centre ((column - 1) x pitch, 0, (row - 1) x pitch), each a fresh table, and state.positions holds every seated player at that centre; no Placed on any other step"] = function()
		Contract.placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder(Session())
	end,

	--[[ AC-2 ]]

	["AC-2: with options.generatorPredicate refusing every attempt the dealing step ends in Resolution with no_contest / generation_failed, holds no facility or procedure, emits no Placed, still sends every seat view, broadcasts a Resolution RoundView; a later turn is ignored and the next Tick moves to Post"] = function()
		Contract.resolvesAFailedGenerationAsNoContestInTheDealingStep(Session())
	end,

	--[[ AC-3 ]]

	["AC-3: a TurnRequested in Round is TurnRequests.handle(procedure, assignment, caller, args, now, STORED positions) - committed when the sample put the turner in reach, out_of_reach after a sample that omitted them - and the caller alone receives one SendTo/TurnResult carrying TurnRequests.reply(result)"] = function()
		Contract.handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone(Session())
	end,

	--[[ C-3: samples, ignored turns, clearing ]]

	["Contract (C-3): PositionsSampled in Lobby, Round and Resolution replaces state.positions with a copy of the samples (not merged, not aliased), emits nothing, and leaves round, assignment, facility and procedure as they were"] = function()
		Contract.storesPositionSamplesAsAReplacingCopyAndEmitsNothing(Session())
	end,

	["Contract (C-3): a TurnRequested in Lobby, Resolution, Post, the next Lobby, and Resolution after a failed generation returns the same state with {} effects"] = function()
		Contract.ignoresATurnOutsideRoundOrWithoutAProcedure(Session())
	end,

	["Contract (C-3): the step that enters Lobby clears facility and procedure (both held through Post) and keeps positions"] = function()
		Contract.clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions(Session())
	end,

	--[[ C-4 ]]

	["Contract (C-4): within a step the effects are ordered pass-through, Placed in seat order, SendTo/SeatView, SendTo/TurnResult, then at most one Broadcast/RoundView last, and nothing of another kind"] = function()
		Contract.ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast(Session())
	end,

	--[[ C-5 ]]

	["Contract (C-5): every RoundView in Round carries secondsLeft = ceil(Procedure.deadline(procedure) - now), which after one wrong turn is instability_clock_penalty_seconds below the config formula"] = function()
		Contract.secondsLeftReadsTheProcedureDeadlineInRound(Session())
	end,

	--[[ AC-4 ]]

	["AC-4: over 50 seeds at each n in {4, 5, 6} the canonical-order script wins every round - every turn committed (the first finale machine armed), won / procedure_complete recorded in the step that takes the completing TurnRequested, Post on the next Tick"] = function()
		Contract.winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn(Session())
	end,

	["AC-4 (control): the same script with every turn sent from the spawn room never wins - every turn refused out_of_reach, still Round a second before the deadline, lost / clock on it"] = function()
		Contract.neverWinsFromTheSpawnRoomAndLosesToTheClock(Session())
	end,

	--[[ AC-5 ]]

	["AC-5: instability_max wrong turns on the live step, spaced a reset window apart, end the round lost / instability in the step that takes the last one; after each earlier one the next Tick's RoundView.secondsLeft is j x instability_clock_penalty_seconds below an unpenalised twin's at the same now"] = function()
		Contract.losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView(Session())
	end,

	--[[ AC-6 ]]

	["AC-6: with k points charged for each k in 0 .. instability_max - 1 and nothing else happening, the round resolves lost / clock on the tick at startedAt + roundSeconds - k x instability_clock_penalty_seconds, is still Round a second earlier, and for k >= 1 the backstop's tick is never reached"] = function()
		Contract.losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel(Session())
	end,

	--[[ Contract: purity ]]

	["Contract: step mutates neither its state nor its event on PositionsSampled, TurnRequested and every other step of both plans"] = function()
		Contract.stepMutatesNeitherStateNorEventOnRoundEvents(Session())
	end,
}
