--!strict
--[[
	VIEW-001: a player's lens view holds only the settings their lens may read
	from where they stand. AC-1 through AC-6, applied to the real
	`src/server/seats/Projection.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `projection_test.luau` does. In RED `Projection.luau` exists
	(SEAT-002) but exports no `lensFor`, so every behavioural test below fails
	at the export check, naming the missing function - a counted failure per
	criterion rather than one LOAD FAIL, which is what GREEN needs. It is not a
	skip: every test FAILS, loudly, until `lensFor` exists.

	THE CHECKS LIVE IN `tests/helpers/LensViewContract.luau` and are exercised
	against a reference view and deliberately wrong views in
	`tests/server/lens_view_controls_test.luau`. That file is where each check
	is OBSERVED to fire - which matters in RED, because the export check above
	means not one assertion in THIS file executes against the module until
	GREEN writes it.

	THE ORACLE PARTITION (story `## Contract`): AC-1 and AC-2 are mechanical
	properties over a generated sample, with the five clauses re-derived in the
	helper from `Ring.lensOf`, `Machines.positionOf`, `Procedure.isDark` and
	`procedure.committed` - never from `lensFor`. AC-3 to AC-5 are mechanical
	and exact. AC-6 is a text guard over the two files, whole-word anchored.

	THE SENTENCE THIS FILE IS FOR (`roles.md` §6): a required setting must not
	exist in any client's replicated state unless that client holds the lens
	for it, and is reading that machine. The view is built by naming what IS
	sent; everything here is written from the side of what must NOT be.

	WHAT THIS FILE DOES NOT PIN: what `lensFor` does for an unseated playerId
	(Contract: not constrained), how it iterates, and the text of any error.
]]

local Contract = require("../helpers/LensViewContract")
local SourceScan = require("../helpers/SourceScan")
local fs = require("../helpers/GatedFs")

local loaded, loadResult = pcall(require, "../../src/server/seats/Projection")

local function Projection(): any
	assert(loaded, `src/server/seats/Projection.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- The export the Contract names, or the failure that names it missing.
local function lensFor(): any
	local projection = Projection()
	assert(
		typeof(projection.lensFor) == "function",
		`Projection.lensFor is {typeof(projection.lensFor)} - VIEW-001's Contract exports `
			.. `lensFor(assignment, procedure, playerId, position, lineOfSight) -> LensView`
	)
	return projection.lensFor
end

local SEATS = "src/server/seats"
local PROJECTION = "src/server/seats/Projection.luau"
local RING = "src/server/seats/Ring.luau"
local STALE_WORDS = { "fragments", "pairings" }
local HEADER_NAMES = { "lensFor", "turnCuesFor" }

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Projection exports lensFor as a plain field function beside the unchanged forPlayer"] = function()
		local projection = Projection()
		assert(
			typeof(projection.forPlayer) == "function",
			`Projection.forPlayer is {typeof(projection.forPlayer)} - SEAT-002's export must stay`
		)
		lensFor()
	end,

	--[[ AC-1 ]]

	["AC-1: over 200 generated facilities at each n in 4..6 and 50 positions per player, every reading is of a machine of Ring.lensOf's class, within lens_read_range_studs horizontally, in sight, lit and not committed - and every such machine is read"] = function()
		Contract.viewIsExactlyTheFiveClauseFilter(lensFor())
	end,

	["AC-1: lineOfSight is consulted only for machines that already pass class, range, lit and not-committed, at most once per machine, with the accepted position and the machine's position (D-4)"] = function()
		Contract.lineOfSightIsConsultedLastAndAtMostOnce(lensFor())
	end,

	["AC-1: the range is inclusive at exactly lens_read_range_studs from procedure.tuning (the fixture's 9, not the shipped 12), horizontal, and a 500-stud y offset does not matter (D-3)"] = function()
		Contract.rangeIsInclusiveAtTheBoundaryAndIgnoresY(lensFor())
	end,

	--[[ AC-2 ]]

	["AC-2: two distinct players' lens views taken from the same position share no machine"] = function()
		Contract.distinctPlayersShareNoMachine(lensFor())
	end,

	--[[ AC-3 ]]

	["AC-3: a player with no accepted position gets exactly { readings = {} } and lineOfSight is never called"] = function()
		Contract.noPositionIsEmptyAndConsultsNothing(lensFor())
	end,

	--[[ AC-4 ]]

	["AC-4: a reading has exactly the keys machineId and setting with the machine's requiredSetting, the view has exactly the key readings, and the view is a fresh table on every call"] = function()
		Contract.readingsHaveExactlyTheContractShape(lensFor())
	end,

	["AC-4: a room holding four machines of the lens class, one committed, reads as exactly three readings ascending by machineId"] = function()
		Contract.manyReadingsAscendByMachineId(lensFor())
	end,

	--[[ AC-5 ]]

	["AC-5: a helper at a machine of their lens class in a lit room reads it, and once Procedure.isDark says the room is dark the next view no longer has that reading"] = function()
		Contract.darkRoomRemovesTheReading(lensFor())
	end,

	--[[ AC-6. The text guard. Two tests, the first of which is the vacuity
	     check: a guard over files that were not read, or are empty, passes
	     over nothing. ]]

	["AC-6: the harness's source list for src/server/seats contains both Projection.luau and Ring.luau, and both read non-empty, so the guard has its subjects"] = function()
		local files = SourceScan.sourceFilesIn(SEATS)
		for _, path in { PROJECTION, RING } do
			assert(
				SourceScan.contains(files, path),
				`{path} is not in the scanned set; a guard over nothing passes. `
					.. `classify.sh --list source {SEATS} said: {table.concat(files, ", ")}`
			)
			local text = fs.readFile(path)
			assert(#text > 0, `{path} read as an empty file; a guard over nothing passes`)
		end
	end,

	["AC-6: neither Projection.luau nor Ring.luau mentions fragments or pairings as a whole word, comments included, and Projection.luau's header names lensFor and turnCuesFor"] = function()
		local files = SourceScan.sourceFilesIn(SEATS)
		local problems: { string } = {}
		for _, path in { PROJECTION, RING } do
			-- Repeated here rather than trusted from the test above: a clean
			-- scan over a file the classifier dropped is the one way this
			-- assertion passes while proving nothing.
			assert(
				SourceScan.contains(files, path),
				`this assertion would pass without {path}, which the classifier did not return for `
					.. `{SEATS}: {table.concat(files, ", ")}`
			)
			local text = fs.readFile(path)
			assert(#text > 0, `{path} read as an empty file; a guard over nothing passes`)
			for _, word in STALE_WORDS do
				local lines = Contract.wholeWordHits(text, word)
				if #lines > 0 then
					table.insert(
						problems,
						`{path} mentions "{word}" on line(s) {table.concat(lines, ", ")}`
					)
				end
			end
		end

		local header = SourceScan.commentsOnly(fs.readFile(PROJECTION))
		for _, name in HEADER_NAMES do
			if #Contract.wholeWordHits(header, name) == 0 then
				table.insert(problems, `{PROJECTION}'s comments never name {name}`)
			end
		end

		assert(
			#problems == 0,
			`AC-6: the two files' text is stale - fragments are superseded and pairings became `
				.. `this view, and the "what M3 adds" paragraph must name lensFor and turnCuesFor `
				.. `instead:\n  {table.concat(problems, "\n  ")}`
		)
	end,
}
