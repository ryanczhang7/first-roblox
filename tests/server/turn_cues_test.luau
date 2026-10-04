--!strict
--[[
	VIEW-002: a player's turn cues name only their own live and next machines.
	AC-1 through AC-6, applied to the real `src/server/seats/Projection.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `lens_view_test.luau` does. In RED `Projection.luau` exists
	(SEAT-002, VIEW-001) but exports no `turnCuesFor`, so every test below
	fails at the export check, naming the missing function - a counted failure
	per criterion rather than one LOAD FAIL, which is what GREEN needs. It is
	not a skip: every test FAILS, loudly, until `turnCuesFor` exists.

	THE CHECKS LIVE IN `tests/helpers/TurnCuesContract.luau` and are exercised
	against a reference view and deliberately wrong views in
	`tests/server/turn_cues_controls_test.luau`. That file is where each check
	is OBSERVED to fire - which matters in RED, because the export check above
	means not one assertion in THIS file executes against the module until
	GREEN writes it.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-2 and AC-6 are
	mechanical - ownership from `keyClasses`, liveness from `Procedure.isLive`
	called in the helper, the shape read key by key. AC-3 to AC-5 are settled
	by `mechanics.md` §3.2 (G12), with the position computed in the helper
	from `steps.tracks` and `committed`, never from `turnCuesFor`.

	THE SENTENCE THIS FILE IS FOR (`mechanics.md` §3.2, `loop.md` §1.7):
	nobody sees the whole order. A cue is a machine id of the player's own,
	and the view carries nothing else - no step index, no track, nobody
	else's anything.

	WHAT THIS FILE DOES NOT PIN: what `turnCuesFor` does for an unseated
	playerId or a state whose outcome is decided (Contract: not constrained),
	how it iterates, and the text of any error.
]]

local Contract = require("../helpers/TurnCuesContract")

local loaded, loadResult = pcall(require, "../../src/server/seats/Projection")

local function Projection(): any
	assert(loaded, `src/server/seats/Projection.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- The export the Contract names, or the failure that names it missing.
local function turnCuesFor(): any
	local projection = Projection()
	assert(
		typeof(projection.turnCuesFor) == "function",
		`Projection.turnCuesFor is {typeof(projection.turnCuesFor)} - VIEW-002's Contract exports `
			.. `turnCuesFor(assignment, procedure, playerId) -> TurnCues`
	)
	return projection.turnCuesFor
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Projection exports turnCuesFor as a plain field function beside the unchanged forPlayer and lensFor"] = function()
		local projection = Projection()
		assert(
			typeof(projection.forPlayer) == "function",
			`Projection.forPlayer is {typeof(projection.forPlayer)} - SEAT-002's export must stay`
		)
		assert(
			typeof(projection.lensFor) == "function",
			`Projection.lensFor is {typeof(projection.lensFor)} - VIEW-001's export must stay`
		)
		turnCuesFor()
	end,

	--[[ AC-1 ]]

	["AC-1: over 200 generated facilities at each n in 4..6 and every state of three scripted commit orders, every live and next cue names a machine whose key class is in that player's keyClasses"] = function()
		Contract.cuesNameOnlyTheirOwnMachines(turnCuesFor())
	end,

	--[[ AC-2 ]]

	["AC-2: over the same states, live is exactly the player's machines for which Procedure.isLive is true - an armed finale machine included"] = function()
		Contract.liveIsExactlyProcedureIsLive(turnCuesFor())
	end,

	--[[ AC-3 ]]

	["AC-3: over the same states, next is exactly the player's uncommitted, not-live step machines at position <= turn_cue_lookahead (inclusive), and a decoy is never a cue"] = function()
		Contract.nextIsExactlyTheLookaheadWindow(turnCuesFor())
	end,

	["AC-3: on a state whose procedure.tuning has turn_cue_lookahead = 2 (shipped 1), the cues include the position-2 machines that lookahead 1 excludes, exactly"] = function()
		Contract.lookaheadTwoSeesTheExtraCue(turnCuesFor())
	end,

	--[[ AC-4 ]]

	["AC-4: a finale step whose track's ordinary steps are done while the other track's are not is in its holder's next and not live; once both are done it is live and not next"] = function()
		Contract.waitingFinaleIsNextNotLive(turnCuesFor())
	end,

	["AC-4: on the hand-built fixture at the shipped lookahead, the waiting finale is next at S1 and S2, live at S3 and when armed at S4, and a two-cue list reads [4, 9] ascending, not [9, 4] by track"] = function()
		Contract.fixtureCuesAtShippedLookahead(turnCuesFor())
	end,

	--[[ AC-5 ]]

	["AC-5: after the real Ring.withdraw, the supplier's cues include the transferred class's machines on every scripted state, and every remaining player's cues are exactly the oracle's"] = function()
		Contract.supplierCuesIncludeTheTransferredClass(turnCuesFor())
	end,

	--[[ AC-6 ]]

	["AC-6: a cue set has exactly the keys live and next, each a fresh list of machine ids ascending and unique, with no step index, track or other player's anything"] = function()
		Contract.cuesHaveExactlyTheContractShape(turnCuesFor())
	end,
}
