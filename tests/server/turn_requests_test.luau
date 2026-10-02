--!strict
--[[
	PROC-005: a guarded Turn call becomes a `Procedure.turn` judged against the
	server's accepted positions, and a private reply. AC-4 and AC-5, applied to
	the real `src/server/procedure/TurnRequests.luau` over the real
	`src/server/procedure/Procedure.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `procedure_test.luau` does. In RED it does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL.
	Per-criterion failures say which behaviours are missing. It is not a skip:
	every test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS AND THE FIXTURE LIVE IN `tests/helpers/TurnRequestsContract.luau`
	and are exercised against a reference stand-in and deliberately wrong
	stand-ins in `tests/server/turn_requests_controls_test.luau`. That file is
	where each check is OBSERVED to fire - which matters in RED, because the
	pcall above means not one assertion in THIS file executes until GREEN
	writes the module. The AC-5 key-set checker is also run there directly on
	hand-written bad replies, the story's named control among them.

	THE ORACLE PARTITION (story `## Contract`): AC-4 and AC-5 are mechanical.
	AC-4's oracle is BEHAVIOURAL through the real Procedure: the accepted
	positions and a position smuggled into the payload disagree about reach,
	and the result says which one was read. Nothing spies on `Procedure.turn`.

	WHAT THIS FILE DOES NOT PIN: how `handle` reaches `Procedure.turn` (a
	direct require is fine; no module field is replaced here), the `TurnReply`
	type's spelling beyond its key set, or anything about Session wiring and
	Transport, which are SLICE-005's.
]]

local Contract = require("../helpers/TurnRequestsContract")

local loaded, loadResult = pcall(require, "../../src/server/procedure/TurnRequests")

local function TurnRequests(): any
	assert(loaded, `src/server/procedure/TurnRequests.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape, and the Contract's pass-through. ]]

	["Contract: TurnRequests exports handle and reply as plain field functions, and handle returns the (state, result) pair Procedure.turn returns on the same inputs"] = function()
		Contract.handleReturnsTheStateAndResultProcedureTurnReturns(TurnRequests())
	end,

	--[[ AC-4 ]]

	["AC-4: with the accepted positions out of reach and an in-reach position smuggled into args (position, positions, x/y/z) the turn is refused / out_of_reach with the state unchanged; with accepted positions in reach and a far one smuggled, it commits - both equal to a direct Procedure.turn"] = function()
		Contract.handleJudgesReachAgainstTheAcceptedPositionsNotThePayload(TurnRequests())
	end,

	["AC-4: args.machine and args.setting are forwarded as given - a wrong setting on machine 11 is rejected / wrong_setting with that setting on the dial, and bob turning machine 14 commits 14"] = function()
		Contract.handleForwardsTheRequestedMachineAndSettingUnswapped(TurnRequests())
	end,

	["AC-4: the turn is judged for the CALLER's id - kim with args.player = zed commits, zed with args.player = kim is refused / not_key_holder"] = function()
		Contract.handleUsesTheCallersIdNotAPlayerKeyInThePayload(TurnRequests())
	end,

	["AC-4: handle mutates none of its arguments - state, assignment, args and positions deep-equal their snapshots afterwards"] = function()
		Contract.handleDoesNotMutateItsArguments(TurnRequests())
	end,

	--[[ AC-5 ]]

	["AC-5: reply maps committed and armed results to exactly { machineId, kind } - key set enumerated with pairs, values equal"] = function()
		Contract.replyToCommittedAndArmedIsExactlyMachineIdAndKind(TurnRequests())
	end,

	["AC-5: reply maps rejected (wrong_setting, not_live) and refused (every reason) results to exactly { machineId, kind, reason } with the reason unchanged"] = function()
		Contract.replyToRejectedAndRefusedIsExactlyMachineIdKindAndReason(TurnRequests())
	end,

	["AC-5: the reply to a REAL wrong_setting rejection from Procedure.turn is exactly { machineId, kind, reason } and carries no requiredSetting or setting; a real commit and a real out_of_reach refusal map exactly too"] = function()
		Contract.replyToARealWrongSettingRejectionCarriesNoRequiredSetting(TurnRequests())
	end,

	["Contract (D8): reply is built field by field - an extra field on the result does not reach the reply, and the reply is a fresh table rather than the result itself"] = function()
		Contract.replyIsBuiltFieldByFieldNotByCopyingTheResult(TurnRequests())
	end,
}
