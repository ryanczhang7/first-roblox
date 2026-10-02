--!strict
--[[
	SLICE-003: the session deals seats and sends each player only their own
	seat view. AC-1 through AC-5 and the story's Contract pins, applied to the
	real `src/server/session/Session.luau` over the real `PhaseMachine`,
	`Ring`, `Projection`, `Rng` and `RoundConfig`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `turn_requests_test.luau` does. In RED it does not exist,
	and a bare top-level `require` would make this whole file a single LOAD
	FAIL. Per-criterion failures say which behaviours are missing. It is not a
	skip: every test below still FAILS, loudly, naming the module that did not
	load.

	THE CHECKS AND THE PLANS LIVE IN `tests/helpers/SessionContract.luau` and
	are exercised against a reference stand-in and deliberately wrong
	stand-ins in `tests/server/session_controls_test.luau`. That file is where
	each check is OBSERVED to fire - which matters in RED, because the pcall
	above means not one assertion in THIS file executes until GREEN writes the
	module.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-2, AC-3 and AC-5 are
	mechanical - every expected ring, view and effect list is computed by
	stepping `PhaseMachine`, `Ring.assign`, `Ring.withdraw` and
	`Projection.forPlayer` in the helper, never hand-copied. AC-4 is settled -
	durations and bounds are read through `RoundConfig.fromTuning(Tuning)`.

	WHAT THIS FILE DOES NOT PIN: how `Session` reaches the M1/M2 modules (a
	plain require is fine), extra keys on `SessionState` beyond `round` and
	`assignment`, the wording of any error, whether `RoundView` is built in
	this module or a helper, and anything about the interpreter or the
	driver, which are SLICE-004's.
]]

local Contract = require("../helpers/SessionContract")

local loaded, loadResult = pcall(require, "../../src/server/session/Session")

local function Session(): any
	assert(loaded, `src/server/session/Session.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The Contract's shape and the round's provenance. ]]

	["Contract: Session.new(config, seed, roundId, sessionId) holds exactly PhaseMachine.initial on the same arguments, with assignment nil"] = function()
		Contract.newHoldsPhaseMachineInitialWithNoAssignment(Session())
	end,

	["Contract: after every step of a two-round lifecycle and a quorum drop, state.round deep-equals PhaseMachine.step on the same inputs (both machine steps on a deal)"] = function()
		Contract.roundStateFollowsThePhaseMachineOnEveryStep(Session())
	end,

	--[[ AC-1 ]]

	["AC-1: with players_min joined and the lobby timer elapsed, one Tick reaches Round and state.assignment deep-equals Ring.assign(effect.players, Rng.fromSeed(effect.seed)) for the AssignSeats effect PhaseMachine.step emits"] = function()
		Contract.dealsRingAssignFromTheEffectsSeedAndReachesRoundInOneStep(Session())
	end,

	["AC-1: across two consecutive rounds (Round -> Resolution -> Post -> Lobby -> deal) the AssignSeats seeds differ and each deal equals Ring.assign from ITS OWN effect's seed - a fixed-seed session fails"] = function()
		Contract.dealsEachOfTwoConsecutiveRoundsFromItsOwnSeed(Session())
	end,

	--[[ AC-2 ]]

	["AC-2: on each dealing step there is exactly one SendTo/SeatView per seated player, addressed to them, payload deep-equal to Projection.forPlayer(assignment, p), nobody else addressed, and no Broadcast on any step carries a seat view by kind or by shape"] = function()
		Contract.sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone(Session())
	end,

	--[[ AC-3 ]]

	["AC-3: when a seated player leaves a six-player Round (quorum kept), state.assignment deep-equals Ring.withdraw(old, leaver) and a SeatView goes to exactly the remaining players whose Projection.forPlayer view changed, in new seat order, and never to the leaver"] = function()
		Contract.withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged(Session())
	end,

	["AC-3: with players_min seated, a leave that keeps quorum and then one that drops below it (resolving the round in the same step) both withdraw the leaver and send views to the remaining players"] = function()
		Contract.withdrawsOnTheLeaveThatDropsBelowQuorumToo(Session())
	end,

	["AC-3: a leave in Resolution or Post, a stranger's leave, a duplicate leave and every other step that unseats nobody send no SendTo at all and leave state.assignment deep-equal to what it was"] = function()
		Contract.sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated(Session())
	end,

	["AC-3 (Contract): the step that enters Lobby clears state.assignment to nil, and a seated player's leave in that Lobby sends no SeatView and leaves it nil"] = function()
		Contract.clearsTheAssignmentOnEnteringLobby(Session())
	end,

	--[[ AC-4 ]]

	["AC-4: exactly one Broadcast/RoundView on every step whose phase or #players changed and on every Tick ending in Lobby, Round or Post; none on a refused join, a stranger's leave, an ignored event, a rematch or a leave in Post"] = function()
		Contract.broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration(Session())
	end,

	["AC-4: every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax } by pairs; secondsLeft = ceil(RoundConfig duration - elapsed) in Lobby (at/above playersMin), Round and Post - 0.5 s in rounds UP, the dealing step says roundSeconds - and nil in Resolution and a short Lobby; players is a copy"] = function()
		Contract.roundViewCarriesExactlyTheFiveKeysWithACeilingSecondsLeftFromConfig(Session())
	end,

	--[[ AC-5 ]]

	["AC-5: on every step the non-SendTo, non-Broadcast effects deep-equal PhaseMachine.step's own effects on the same inputs minus AssignSeats, in order (Emit on join/leave/round end/rematch, ComputeTrace on Resolution -> Post, PromptRematch on Post -> Lobby), and AssignSeats never appears"] = function()
		Contract.passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats(Session())
	end,

	--[[ Contract: outside events, order, purity ]]

	["Contract: a SeatsAssigned event from outside (in Lobby, in Round, and on a hand-built Assignment-phase state) and every step the machine ignores return the same state with {} effects"] = function()
		Contract.ignoresASeatsAssignedEventFromOutsideAndEveryNoOp(Session())
	end,

	["Contract: within a step the effects are ordered pass-through first, then SendTo/SeatView in seat order, then at most one Broadcast last"] = function()
		Contract.ordersPassThroughThenSeatViewsThenRoundViewLast(Session())
	end,

	["Contract: step mutates neither its state nor its event - deep snapshots taken before each step deep-equal the arguments afterwards"] = function()
		Contract.stepMutatesNeitherStateNorEvent(Session())
	end,
}
