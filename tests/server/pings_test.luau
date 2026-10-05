--!strict
--[[
	CHAN-005: a ping is accepted only at a real target in range and in sight.
	AC-3, AC-4 (the `request` half) and AC-5, applied to the real
	`src/server/channel/Pings.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as every suite here does. In RED `Pings.luau` does not exist,
	and a bare top-level `require` would make this whole file a single LOAD
	FAIL - one line of red covering three criteria. Per-criterion failures say
	which behaviours are missing. It is not a skip: every test below still
	FAILS, loudly, naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/PingsContract.luau` and are exercised in
	`tests/server/pings_controls_test.luau` against `PingsStubs.luau`'s
	reference and implementations with exactly one defect each. That file is
	where each check is OBSERVED to fire - which matters in RED, because the
	pcall above means not one assertion in THIS file executes until GREEN
	writes the module.

	THE ORACLE PARTITION (story `## Contract`): every criterion here is
	mechanical. The fixture is hand-built (three rooms, two doorways, four
	machines with non-dense ids listed out of order) so every position is a
	number the controls file asserts; the range boundary is pinned at exactly
	`ping_range_studs` (accepted) and `+ 0.01` (refused), which D-2 depends
	on; AC-5 is a call count and two arguments, which D-3 depends on.

	WHAT THIS FILE DOES NOT PIN: how `validate` is organised internally, the
	text of anything (no refusal carries a detail), what `validate` does with
	a `kind` outside the three the schema admits (never driven), and how
	`request` is wired into `Session` (`SLICE-006`, `SLICE-007`).
]]

local Contract = require("../helpers/PingsContract")

local pingsLoaded, pingsResult = pcall(require, "../../src/server/channel/Pings")

local function pings(): any
	assert(pingsLoaded, `src/server/channel/Pings.luau did not load: {tostring(pingsResult)}`)
	return pingsResult
end

return {
	--[[ AC-3: accepted targets, each refusal, the order, the boundary, the positions. ]]

	["AC-3: validate accepts a machine, a setting on it and a doorway in range and in sight - including a machine in a dark room, a machine that is not live, a doorway judged from its midpoint, and a sender far below the floor (PO-5)"] = function()
		Contract.acceptsMachinesSettingsAndDoorwaysInRangeAndInSight(pings())
	end,

	["AC-3: validate refuses with each distinct reason - no_such_target (absent machine, setting on it, doorway > #doors, doorway 0), committed_machine (machine and setting), out_of_range, out_of_sight, setting_mismatch (three forms), no_position"] = function()
		Contract.refusesEachReasonDistinctly(pings())
	end,

	["AC-3: first failure wins in the Contract's order - setting before existence, existence before committed, committed before position, position before range and sight, range before sight"] = function()
		Contract.firstFailureWinsInTheContractsOrder(pings())
	end,

	["AC-3: range is horizontal and inclusive - exactly ping_range_studs along x or z, at any y, is accepted for a machine, a setting and a doorway; ping_range_studs + 0.01 is out_of_range"] = function()
		Contract.rangeIsHorizontalAndInclusiveAtPingRangeStuds(pings())
	end,

	["AC-3: range is procedure.tuning.channel.ping_range_studs - a procedure whose tuning fixes 20 accepts exactly 20 and a stand outside the module's 12"] = function()
		Contract.rangeIsReadFromTheProceduresTuning(pings())
	end,

	["AC-3 control: a payload carrying an in-range position field from a server position a room away is out_of_range - range is the server's, never the client's"] = function()
		Contract.rangeIsMeasuredFromTheServersPositionNotAPayloadField(pings())
	end,

	["AC-3: targetPosition is Machines.positionOf for a machine or a setting (setting not looked at), the midpoint of the two rooms' centres for a doorway, and nil for an absent machine or doorway"] = function()
		Contract.targetPositionIsPositionOfForMachinesAndTheMidpointForDoorways(pings())
	end,

	--[[ AC-5: the line-of-sight port. ]]

	["AC-5: for an otherwise-valid machine, setting or doorway, lineOfSight is called exactly once with (the sender's accepted position, the target's position); true accepts, false refuses out_of_sight"] = function()
		Contract.lineOfSightIsAskedOnceFromTheSenderToTheTarget(pings())
	end,

	["AC-5: lineOfSight is never called for a target that fails setting_mismatch, no_such_target, committed_machine, no_position or out_of_range"] = function()
		Contract.lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck(pings())
	end,

	--[[ AC-4: request. ]]

	["AC-4: on every refusal request calls call.decline() exactly once and returns exactly { reason }; procedure == nil is no_such_target; a sender absent from positions is no_position"] = function()
		Contract.requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal(pings())
	end,

	["AC-4: on an accepted ping request returns nil, never calls decline, and writes to neither positions nor the target"] = function()
		Contract.requestAcceptsWithoutDeclining(pings())
	end,
}
