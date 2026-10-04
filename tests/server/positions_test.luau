--!strict
--[[
	VIEW-004: an implausible position is not trusted for any range check.
	AC-1 through AC-4 and the Contract's purity, applied to the real
	`src/server/session/Positions.luau` - the pure rule, at the level where
	the logic lives.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `turn_cues_test.luau` does. In RED the module does not
	exist, so every test below fails at the export check, naming the missing
	module - a counted failure per criterion rather than one LOAD FAIL, which
	is what GREEN needs. It is not a skip: every test FAILS, loudly, until
	`Positions.luau` exists and holds the rule.

	THE CHECKS LIVE IN `tests/helpers/PositionsContract.luau` and are
	exercised against a reference rule and deliberately wrong rules in
	`tests/server/positions_controls_test.luau`. That file is where each
	check is OBSERVED to fire - which matters in RED, because the export
	check above means not one assertion in THIS file executes against the
	module until GREEN writes it.

	THE ORACLE PARTITION (story `## Contract`): everything here is MECHANICAL
	against the module's own constants, read from it and never restated. The
	only literal distances are AC-1's settled controls (200 studs in 0.1 s
	refused, 1.5 studs in 0.1 s accepted); every boundary is computed from
	`TOLERANCE`, `SLACK_STUDS`, `RESYNC_SECONDS` and the tuning's walk speed.

	WHAT THIS FILE DOES NOT PIN: the VALUES of the three constants beyond
	their floors (TOLERANCE >= 1, SLACK_STUDS >= 0, RESYNC_SECONDS > 0) and
	what the settled controls imply; how `offer` is written; the text of any
	error; whether `Track` carries `refusedSince = nil` explicitly or omits
	it (Deep.equal treats them alike).
]]

local Contract = require("../helpers/PositionsContract")

local loaded, loadResult = pcall(require, "../../src/server/session/Positions")

local function Positions(): any
	assert(
		loaded,
		`src/server/session/Positions.luau did not load: {tostring(loadResult)} - VIEW-004's Contract exports `
			.. `TOLERANCE, SLACK_STUDS, RESYNC_SECONDS, placed(track, at, now), `
			.. `offer(track, candidate, now, walkSpeed) -> (Track, boolean), needsResync(track, now)`
	)
	return loadResult
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Positions exports TOLERANCE >= 1, SLACK_STUDS >= 0 and RESYNC_SECONDS > 0 as numbers, and placed, offer and needsResync as functions"] = function()
		Contract.exportsTheContractShape(Positions())
	end,

	--[[ AC-1 ]]

	["AC-1: from a placement at the origin, a candidate 200 studs away 0.1 s later is refused (previous sample kept, one rejection counted, the run started) and one 1.5 studs away 0.1 s later is accepted"] = function()
		Contract.settledControlsRefuse200AndAccept1_5(Positions())
	end,

	["AC-1: a candidate at EXACTLY walkSpeed x TOLERANCE x dt + SLACK_STUDS is accepted and one a hair past it is refused - the bound is inclusive"] = function()
		Contract.boundIsInclusive(Positions())
	end,

	["AC-1: y is ignored - a candidate 500 studs straight up is accepted, and one at the horizontal bound with a 500-stud y offset is still accepted"] = function()
		Contract.yIsIgnored(Positions())
	end,

	["AC-1: dt is measured from the last ACCEPTED sample - a candidate just past the 3 s bound is refused at t = 3 and t = 3.5 (count and run grow, baseline kept) and accepted at t = 4, which clears the run and keeps the count"] = function()
		Contract.dtIsMeasuredFromTheLastAcceptedSample(Positions())
	end,

	["AC-1: a now before acceptedAt clamps dt to 0 - a candidate SLACK_STUDS away is accepted, one half a stud further refused (neither a negative nor an absolute dt)"] = function()
		Contract.nowBeforeAcceptedAtClampsDtToZero(Positions())
	end,

	--[[ AC-2 ]]

	["AC-2: placed(track, at, now) is the new baseline - a sample at a 300-stud placement right after is accepted and the same jump without the placement is refused; placed copies at, sets acceptedAt, clears the run and carries the refusal count"] = function()
		Contract.placedResetsTheBaseline(Positions())
	end,

	--[[ AC-3 ]]

	["AC-3: with no baseline (nil track, or a track never accepted) a sample is neither accepted nor stored nor counted as a refusal and starts no run; after a placement the next sample is accepted"] = function()
		Contract.noBaselineMeansNoAcceptanceAndNoRefusal(Positions())
	end,

	--[[ AC-4 ]]

	["AC-4: needsResync(track, now) is true only for an accepted track whose refusal run is STRICTLY longer than RESYNC_SECONDS - false at exactly RESYNC_SECONDS, true a hair later, false for nil, no baseline, no run, and after an acceptance"] = function()
		Contract.needsResyncIsStrictlyAfterResyncSeconds(Positions())
	end,

	--[[ Contract: purity ]]

	["Contract: placed, offer and needsResync mutate no argument, never return the track handed in, and never store the candidate or at table itself"] = function()
		Contract.isPureAndReturnsFreshTables(Positions())
	end,
}
