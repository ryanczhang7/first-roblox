--!strict
--[[
	The negative controls for ROUND-001 AC-1 and the Clock Contract.

	AC-1 carries no control in the story's text - it is a mechanical criterion and
	the partition says "pin exactly". These exist anyway, for one reason: in RED
	`src/shared/Clock.luau` does not exist, so `clock_test.luau` fails at
	`require` and NOT ONE of its assertions has ever run. Applying the same checks
	to a clock that does not advance is how those assertions get observed rejecting
	something before GREEN starts.

	It also pre-verifies the second mutation in the story's `## Notes` - "make
	`advance` ignore its argument; predicted: AC-1 goes red" - so the orchestrator
	knows at acceptance what the answer should be.
]]

local ClockContract = require("../helpers/ClockContract")
local Fakes = require("../helpers/Fakes")

local function accepts(check: (any) -> (), factory: any, what: string)
	local ok, err = pcall(check, factory)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: (any) -> (), factory: any, what: string): string
	local ok, err = pcall(check, factory)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

return {
	["baseline: a correct manual clock passes every AC-1 and Contract check"] = function()
		accepts(ClockContract.advanceMovesNowByTheDelta, Fakes.manualClock, "AC-1 advance")
		accepts(ClockContract.zeroAdvanceChangesNothing, Fakes.manualClock, "AC-1 zero advance")
		accepts(
			ClockContract.negativeAdvanceIsAnError,
			Fakes.manualClock,
			"Contract negative advance"
		)
		accepts(ClockContract.setMayMoveBackwards, Fakes.manualClock, "Contract set")
	end,

	["AC-1 control: a clock whose advance ignores its delta is rejected"] = function()
		local message = refuses(
			ClockContract.advanceMovesNowByTheDelta,
			Fakes.frozenClock,
			"a clock that never advances must fail AC-1"
		)
		assert(
			string.find(message, "AC-1", 1, true) ~= nil,
			`the AC-1 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, "wanted 105", 1, true) ~= nil,
			`the AC-1 failure does not say what it wanted: {message}`
		)

		-- The other half: a frozen clock still satisfies advance(0), so the zero
		-- edge is not what catches it and the two checks are not duplicates.
		accepts(
			ClockContract.zeroAdvanceChangesNothing,
			Fakes.frozenClock,
			"a frozen clock must still pass the advance(0) check"
		)
	end,

	["Contract control: a clock that clamps a negative advance is rejected"] = function()
		accepts(
			ClockContract.advanceMovesNowByTheDelta,
			Fakes.clampingClock,
			"a clamping clock must pass AC-1 - it only misbehaves below zero"
		)

		local message = refuses(
			ClockContract.negativeAdvanceIsAnError,
			Fakes.clampingClock,
			"a clock that clamps advance(-1) to advance(0) must fail the Contract check"
		)
		assert(
			string.find(message, "advance(-1) was accepted", 1, true) ~= nil,
			`the negative-advance failure does not say what is wrong: {message}`
		)
	end,
}
