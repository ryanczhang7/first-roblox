--!strict
--[[
	PROC-001: a turn commits a live step on the right setting and says why it
	failed otherwise. AC-1 through AC-6, applied to the real
	`src/server/procedure/Procedure.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `ring_test.luau` and `steps_test.luau` do. In RED it does
	not exist, and a bare top-level `require` would make this whole file a
	single LOAD FAIL - one line of red covering six criteria. Per-criterion
	failures say which behaviours are missing, which is what GREEN needs. It is
	not a skip: every test below still FAILS, loudly, naming the module that
	did not load.

	THE CHECKS AND THE FIXTURE LIVE IN `tests/helpers/TurnContract.luau` and are
	exercised against a reference stand-in and deliberately wrong stand-ins in
	`tests/server/procedure_controls_test.luau`. That file is where each check
	is OBSERVED to fire - which matters in RED, because the pcall above means
	not one assertion in THIS file executes until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`): AC-1 to AC-5 are settled by
	`mechanics.md` §3.2 and §5 (G12) and pinned by P-1..P-11; each test is
	named after the rule it pins. AC-6 is mechanical. The facility is
	hand-built; no test depends on a generator sample or an rng seed.

	WHAT THIS FILE DOES NOT PIN: how `isLive` walks a track, how a new state is
	copied, what `dials[id]` holds after a COMMIT (only the `dial` view is
	pinned), what `dial` answers for an unknown id, any field PROC-002 or
	PROC-003 adds to the state, and the text of any error.
]]

local Contract = require("../helpers/TurnContract")
local Deep = require("../helpers/Deep")

local loaded, loadResult = pcall(require, "../../src/server/procedure/Procedure")

local function Procedure(): any
	assert(loaded, `src/server/procedure/Procedure.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Procedure exports start, isLive, dial and turn as plain field functions"] = function()
		local P = Procedure()
		local missing: { string } = {}
		for _, name in { "start", "isLive", "dial", "turn" } do
			if typeof(P[name]) ~= "function" then
				table.insert(missing, `Procedure.{name} is {typeof(P[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's four exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract: start returns the ProcedureState the Contract names - facility, committed = {}, dials = {}, instability = 0, log = {}, and the tuning it was handed (P-1)"] = function()
		Contract.startReturnsTheContractState(Procedure())
	end,

	["Contract: turn returns two values - a state and a result table with a kind"] = function()
		local P = Procedure()
		local w = Contract.world()
		local state = P.start(w.facility, Contract.NOW, w.tuning)
		local next_, result = P.turn(
			state,
			w.assignment,
			"kim",
			11,
			Contract.requiredSetting(w.facility, 11),
			Contract.NOW,
			Contract.standingAt(w, "kim", 11)
		)
		assert(typeof(next_) == "table", `turn's first return is {typeof(next_)}, expected a state`)
		assert(
			typeof(result) == "table" and typeof(result.kind) == "string",
			`turn's second return is {Deep.show(result)}, expected a result with a string kind`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: at start exactly the first step of each track is live - not the finale steps, not a decoy, not an unknown id (P-3)"] = function()
		Contract.liveSetAtStartIsExactlyTheTrackHeads(Procedure())
	end,

	["AC-1: after the first step of track 1 commits, the second step of track 1 is live and track 2's head is unchanged"] = function()
		Contract.committingTheHeadOfTrackOneMakesItsSecondStepLive(Procedure())
	end,

	["AC-1: tracks advance independently and a finale step is never live in this story, even with every ordinary step committed (finale_live_together)"] = function()
		Contract.tracksAdvanceIndependentlyAndFinaleStepsStayWaiting(Procedure())
	end,

	--[[ AC-2 ]]

	["AC-2: the key holder, in reach, turning a live step to its required setting gets committed, the machine is committed, its dial reads committed with that setting, and the step behind it goes live"] = function()
		Contract.holderInReachOnTheRequiredSettingCommits(Procedure())
	end,

	["AC-2/P-4: reach is inclusive at exactly turn_range_studs (the fixture's 7, not the shipped 10), horizontal, and ignores y"] = function()
		Contract.reachIsInclusiveAtTurnRangeStudsAndIgnoresY(Procedure())
	end,

	--[[ AC-3 ]]

	["AC-3: a live step turned to the wrong setting is rejected / wrong_setting, charged exactly instability_per_wrong_value, and its dial shows that setting as rejected"] = function()
		Contract.wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue(Procedure())
	end,

	["AC-3: a waiting step - a track's second step, or a finale step - is rejected / not_live whatever the setting, charged exactly instability_per_out_of_order (P-8: not_live wins)"] = function()
		Contract.waitingStepIsNotLiveWhateverTheSetting(Procedure())
	end,

	["AC-3: a decoy is rejected / not_live whatever the setting, charged exactly instability_per_out_of_order"] = function()
		Contract.decoyIsNotLiveWhateverTheSetting(Procedure())
	end,

	["AC-3/P-1: charges accumulate and each reason charges ITS constant, read from state.tuning (wrong_value 1 + out_of_order 2 = 3)"] = function()
		Contract.chargesAccumulateByReason(Procedure())
	end,

	["AC-3/P-6: a rejected dial shows the setting as rejected for t < now + actuation_reset_seconds, is unset at exactly the boundary, and a turn at the boundary is evaluated"] = function()
		Contract.rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset(Procedure())
	end,

	--[[ AC-4 ]]

	["AC-4: an id that does not exist is refused / unknown_machine, echoing the id, with the state returned deep-equal"] = function()
		Contract.unknownMachineIsRefused(Procedure())
	end,

	["AC-4/P-5: a player without the machine's key class - seated or absent from keyClasses - is refused / not_key_holder in reach on the right setting, and charged nothing"] = function()
		Contract.nonHolderIsRefusedAndNotCharged(Procedure())
	end,

	["AC-4/P-4: the holder just past turn_range_studs horizontally, or with no accepted position, is refused / out_of_reach"] = function()
		Contract.holderOutOfHorizontalReachOrWithoutAPositionIsRefused(Procedure())
	end,

	["AC-4: a committed machine is refused / committed on any setting, not rejected"] = function()
		Contract.committedMachineIsRefused(Procedure())
	end,

	["AC-4: a dial inside its reset window is refused / resetting at 0, half and reset - 0.001 seconds after the rejection"] = function()
		Contract.resettingDialIsRefused(Procedure())
	end,

	["AC-4: the refusal checks run unknown_machine, not_key_holder, out_of_reach, committed, resetting in that order and the first failure wins"] = function()
		Contract.refusalChecksRunInOrderAndTheFirstFailureWins(Procedure())
	end,

	--[[ AC-5 ]]

	["AC-5: after Ring.withdraw moves the leaver's class to their supplier, the supplier is judged the key holder of that class - and was not before, and the leaver no longer is"] = function()
		Contract.supplierIsJudgedKeyHolderAfterWithdraw(Procedure())
	end,

	--[[ AC-6 ]]

	["AC-6/P-10: the log holds one { playerId, machineId, setting, at, result } per evaluated turn, in call order, and none for a refused one"] = function()
		Contract.logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals(Procedure())
	end,

	["P-11: no call mutates the state, assignment, positions or facility it is handed, and a new state shares no writable table with the old"] = function()
		Contract.noCallMutatesItsArguments(Procedure())
	end,
}
