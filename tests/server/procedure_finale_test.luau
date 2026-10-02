--!strict
--[[
	PROC-002: the finale commits only when both machines are turned inside the
	window. AC-1 through AC-7, applied to the real
	`src/server/procedure/Procedure.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `procedure_test.luau` does. In this story's RED the module
	LOADS - PROC-001 wrote it - but has no `tick`, `partnerLamps` or
	`isComplete` and no finale behaviour, so every test below fails on its own
	assertion rather than at import: the F-1 shape test on the missing
	exports, the behaviour tests on the first thing the finale does not do
	(a finale machine is not live, so the scenario's arming turn is rejected
	`not_live`). Per-criterion failures say which behaviours are missing,
	which is what GREEN needs.

	THE CHECKS AND THE FIXTURE LIVE IN `tests/helpers/FinaleContract.luau`,
	reusing `TurnContract`'s facility, and are exercised against a reference
	stand-in and deliberately wrong stand-ins in
	`tests/server/procedure_finale_controls_test.luau`. That file is where each
	check is OBSERVED to fire and to accept.

	THE ORACLE PARTITION (story `## Contract`): every criterion is settled by
	`mechanics.md` §3.2 and §5 (G12) and pinned by F-1..F-12; each test is
	named after the case it pins. The tuning is the shipped one with seven
	overrides so every constant is distinct (F-2); AC-3 and AC-4 also run
	under the shipped tuning, where they read out literally.

	WHAT THIS FILE DOES NOT PIN: what `dial` answers for an ARMED machine
	(F-4 fixes `dials[id]`, not the view), the text of any error, how `tick`
	reads `assignment` and `positions` (unread in this story), any field
	PROC-003 adds, and how liveness or the lamps are computed internally.
]]

local Deep = require("../helpers/Deep")
local Finale = require("../helpers/FinaleContract")
local Turn = require("../helpers/TurnContract")

local loaded, loadResult = pcall(require, "../../src/server/procedure/Procedure")

local function Procedure(): any
	assert(loaded, `src/server/procedure/Procedure.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape (F-1). Pinned first because everything below depends
	     on it and a wrong guess here is a compile error rather than a puzzle. ]]

	["F-1: Procedure exports tick, partnerLamps and isComplete as plain field functions, alongside start, isLive, dial and turn"] = function()
		local P = Procedure()
		local missing: { string } = {}
		for _, name in { "start", "isLive", "dial", "turn", "tick", "partnerLamps", "isComplete" } do
			if typeof(P[name]) ~= "function" then
				table.insert(missing, `Procedure.{name} is {typeof(P[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["F-1: start opens no window (armed = nil), isComplete answers false, tick with no window returns a deep-equal state and nil, and partnerLamps has exactly the two finale ids as boolean keys - both false at start"] = function()
		Finale.startHasNoWindowAndTheNewExportsAnswerInShape(Procedure())
	end,

	["F-1: tick returns two values - a state and, in this story, nil"] = function()
		local P = Procedure()
		assert(
			typeof(P.tick) == "function",
			`Procedure.tick is {typeof(P.tick)}, expected a function`
		)
		local w = Finale.world()
		local state = P.start(w.facility, Finale.NOW, w.tuning, Turn.ROUND_SEED, Turn.ROUND_SECONDS)
		local next_, outcome = P.tick(state, w.assignment, Finale.NOW + 1, {})
		assert(typeof(next_) == "table", `tick's first return is {typeof(next_)}, expected a state`)
		assert(
			outcome == nil,
			`tick's second return is {Deep.show(outcome)}, expected nil in this story`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: with track 2's ordinary steps committed and one ordinary step left in track 1 neither finale machine is live; the moment it commits, both are (finale_live_together, F-3)"] = function()
		Finale.neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre(Procedure())
	end,

	["AC-1/F-3: an armed machine is still live and so is its partner; after the finale commits nothing is live"] = function()
		Finale.anArmedMachineIsStillLiveAndACommittedFinaleIsNot(Procedure())
	end,

	--[[ AC-2 ]]

	["AC-2/F-4: a correct turn on a live finale machine with neither armed returns armed, opens a window closing at now + simultaneous_window_seconds, sets the dial, charges nothing, commits nothing and logs one armed entry - whichever machine goes first"] = function()
		Finale.correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt(Procedure())
	end,

	["AC-2/F-5: with A armed at t, a correct turn on B at t, mid-window and just before the end commits BOTH at that instant, clears the window, logs one entry, charges nothing, and the Procedure is complete"] = function()
		Finale.correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth(Procedure())
	end,

	--[[ AC-7 ]]

	["AC-7: a correct turn on B at EXACTLY t + simultaneous_window_seconds commits both - the window is inclusive at its end"] = function()
		Finale.turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth(Procedure())
	end,

	["AC-7/F-8: tick at t, mid-window and at exactly closesAt returns a state deep-equal to the one passed, and nil - expiry is strictly now > closesAt"] = function()
		Finale.tickAtOrBeforeTheWindowsEndChangesNothing(Procedure())
	end,

	--[[ AC-3 ]]

	["AC-3/F-8: tick at t + simultaneous_window_seconds + epsilon with B unturned disarms both, charges exactly instability_per_failed_pair (the fixture's 4), dates A's rejection from the tick's now, leaves B's dial and the log untouched, and a late tick dates it from its own now"] = function()
		Finale.tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair(Procedure())
	end,

	["AC-3/F-8: after expiry the disarmed machine is refused / resetting inside actuation_reset_seconds (returning the state passed) and arms again at the boundary"] = function()
		Finale.afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain(Procedure())
	end,

	["AC-3 under the SHIPPED tuning: an expired window raises instability by exactly 1 (mechanics.md §5: both disarm, +1)"] = function()
		Finale.underTheShippedTuningAnExpiredWindowCostsExactlyOne(Procedure())
	end,

	--[[ AC-4 ]]

	["AC-4/F-7: with A armed, a wrong turn on B inside the window is rejected / wrong_setting, charged instability_per_wrong_value ONCE (1, not also failed_pair 4), disarms both into reset windows and logs one entry"] = function()
		Finale.wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth(Procedure())
	end,

	["AC-4 under the SHIPPED tuning: a wrong turn on B with A armed raises instability by exactly 1 in total, not 2 (mechanics.md §5: no second penalty)"] = function()
		Finale.underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo(Procedure())
	end,

	["AC-4/F-7: a wrong turn on a live finale machine with NO window open is an ordinary rejection - charged wrong_value, the other machine untouched"] = function()
		Finale.wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection(Procedure())
	end,

	--[[ AC-5 ]]

	["AC-5/F-6: a turn on the armed machine itself - right setting or wrong, inside the window or at its end - is refused / armed at no cost and returns the state passed"] = function()
		Finale.turnOnTheArmedMachineIsRefusedArmedAtNoCost(Procedure())
	end,

	["AC-5/F-6: armed is the last refusal checked - a non-holder or an out-of-reach holder on the armed machine is refused for that reason"] = function()
		Finale.armedIsTheLastRefusalChecked(Procedure())
	end,

	--[[ F-9 ]]

	["F-9: a correct turn on B after the window applies the expiry first (+failed_pair, A into a reset window) and then ARMS B - nothing commits"] = function()
		Finale.aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt(Procedure())
	end,

	["F-9: a turn on A after the window is refused / resetting and returns the POST-EXPIRY state (deep-equal to tick's at that now); a wrong turn on B after the window is expiry plus an ordinary rejection"] = function()
		Finale.aTurnAfterTheWindowReturnsThePostExpiryState(Procedure())
	end,

	--[[ AC-6 ]]

	["AC-6/F-11: both partner lamps are dark while the finale is not live - at start, with an ordinary step left, and after the finale committed - even with both holders at the partner machines"] = function()
		Finale.bothLampsAreDarkWhileTheFinaleIsNotLive(Procedure())
	end,

	["AC-6/F-11: with the finale live, A's lamp is lit exactly when the holder of B's class is within partner_lamp_range_studs (4, not turn range 7) of B, horizontally and inclusively, y ignored, absent = out of range; B's the same way round; armed does not change it"] = function()
		Finale.aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine(
			Procedure()
		)
	end,

	["AC-6/F-11: any holder of the partner's class in range lights the lamp, and one player holding both classes lights the lamp of the machine they are NOT standing at"] = function()
		Finale.anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase(
			Procedure()
		)
	end,

	--[[ F-10, F-12 ]]

	["F-10: isComplete is false at start, with every ordinary step committed and with A armed, and true once both finale machines commit"] = function()
		Finale.isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted(Procedure())
	end,

	["F-12: tick, partnerLamps, isComplete and every finale kind of turn leave their arguments deep-equal, and a later call on the new state does not reach back into the old"] = function()
		Finale.noFinaleCallMutatesItsArguments(Procedure())
	end,
}
