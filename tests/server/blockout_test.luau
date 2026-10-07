--!strict
--[[
	MAP-001: a generated facility becomes blockout geometry the players can
	walk. AC-1 through AC-4 and the Contract's C-1, applied to the real
	`src/server/facility/Blockout.luau` and to the one new export of
	`src/server/facility/Machines.luau`, `roomCentre`.

	`Blockout` is required through a `pcall` at the top and re-checked inside
	every test, as `generator_test.luau` does. In RED it does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering four criteria. Per-criterion failures say which
	behaviours are missing, which is what GREEN needs. It is not a skip: every
	test below still FAILS, loudly, naming the module that did not load.
	`Machines` exists already, so its two tests fail on the missing export.

	THE CHECKS, PREDICATES, SWEEP AND FIXTURE LIVE IN
	`tests/helpers/BlockoutContract.luau` and are exercised against
	deliberately wrong builders in `tests/server/blockout_controls_test.luau`.
	That file is where each check is OBSERVED to reject its control and accept
	a reference - which matters in RED, because the pcall above means not one
	assertion in THIS file executes until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`, C-8):
	  * AC-1 and AC-2 are SETTLED: every expected size, face, gap edge and
	    position is arithmetic over `MechanicsTuning` and over
	    `Blockout.WALL_THICKNESS` / `ANCHOR_SIZE`, which the first test pins to
	    C-1's values (1 and { 4, 6, 4 }) before anything reads them.
	  * AC-3 and AC-4 are MECHANICAL: C-5's overlap and containment and C-6's
	    slab test, written in the helper with a 1e-6 tolerance.
	  * The sweep is seeds 1..200 at n = 4, the real `Generator.generate` over
	    `FacilityContract.ringFor`.

	WHAT THIS FILE DOES NOT PIN: how an edge is cut into wall specs (one slab,
	jambs and a lintel, or bricks - C-3 tests coverage), the names of floors,
	ceilings and walls beyond the `Wall` prefix, the order of the returned
	list, whether the module table is frozen, and anything about
	`BlockoutBuilder` (D-1, Studio).
]]

local Contract = require("../helpers/BlockoutContract")
local Deep = require("../helpers/Deep")
local LayoutContract = require("../helpers/LayoutContract")
local PlacementContract = require("../helpers/PlacementContract")
local Raise = require("../helpers/Contract")

local TUNING = Contract.TUNING

local loaded, loadResult = pcall(require, "../../src/server/facility/Blockout")
local Machines = require("../../src/server/facility/Machines")

local function Blockout(): any
	assert(loaded, `src/server/facility/Blockout.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- C-1's constants, read from the module AFTER the first test has pinned them
-- to the Contract's values; the geometry checks take them as arguments.
local function T(): number
	return Blockout().WALL_THICKNESS
end

local function anchorSize(): Contract.Vec3
	return Blockout().ANCHOR_SIZE
end

local function parts(): Contract.Builder
	return Blockout().parts
end

local fixture = Contract.treeBlockFacility()

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract / C-1: Blockout exports parts as a plain field function, WALL_THICKNESS = 1 and ANCHOR_SIZE = exactly { x = 4, y = 6, z = 4 }"] = function()
		local B = Blockout()
		assert(typeof(B) == "table", `Blockout is {typeof(B)}`)
		assert(typeof(B.parts) == "function", `Blockout.parts is {typeof(B.parts)}`)
		assert(
			B.WALL_THICKNESS == 1,
			`Blockout.WALL_THICKNESS is {tostring(B.WALL_THICKNESS)}, the Contract fixes 1`
		)
		assert(
			Deep.equal(B.ANCHOR_SIZE, { x = 4, y = 6, z = 4 }),
			`Blockout.ANCHOR_SIZE is {Deep.show(B.ANCHOR_SIZE)}, the Contract fixes exactly x = 4, y = 6, z = 4`
		)
	end,

	["Contract / C-1: parts returns plain specs - exactly { name, kind, cframe, size }, kind one of floor, ceiling, wall, machine, every extent > 0 - deep-equal across two calls, without mutating the facility (tree block and seeds 1, 2, 3)"] = function()
		local build = parts()
		local items = { { label = "tree block", facility = fixture } }
		for seed = 1, 3 do
			table.insert(
				items,
				{ label = `n = 4 seed {seed}`, facility = Contract.facilities(4)[seed].facility }
			)
		end
		for _, item in items do
			local before = Contract.snapshot(item.facility)
			local a = build(item.facility, TUNING)
			local b = build(item.facility, TUNING)
			assert(
				Deep.equal(before, item.facility),
				`{item.label}: parts mutated the facility:\n{Deep.diff(before, item.facility)}`
			)
			local problems = Contract.shapeProblems(a)
			if #problems > 0 then
				Raise.fail(`{item.label}: {Raise.firstFew(problems, 8)}`)
			end
			assert(
				Deep.equal(a, b),
				`{item.label}: two calls on the same facility differ:\n{Deep.diff(a, b)}`
			)
		end
	end,

	["Contract / C-1: parts reads only facility.layout and facility.placement.machines - a facility stripped to exactly those gives deep-equal specs"] = function()
		local build = parts()
		local full = build(fixture, TUNING)
		local stripped: any = {
			layout = Deep.copy(fixture.layout),
			placement = { machines = Deep.copy(fixture.placement.machines) },
		}
		local got = build(stripped, TUNING)
		assert(
			Deep.equal(full, got),
			`parts read something beyond layout and placement.machines - the stripped facility builds differently:\n{Deep.diff(
				full,
				got
			)}`
		)
	end,

	["Contract / C-1: Machines.roomCentre is a function returning exactly { x = (column − 1) × pitch, y = 0, z = (row − 1) × pitch } for every room of the square and plus fixtures, and positionOf is roomCentre plus the slot's quadrant offset"] = function()
		assert(
			typeof(Machines.roomCentre) == "function",
			`Machines.roomCentre is {typeof(Machines.roomCentre)}, expected a function (C-1's one new export)`
		)
		local P = TUNING.instance.room_pitch_studs
		local problems: { string } = {}
		for _, item in
			{
				{ name = "square", layout = PlacementContract.FIXTURE_LAYOUT },
				{ name = "plus", layout = PlacementContract.PLUS_LAYOUT },
			}
		do
			for _, room in item.layout.rooms do
				local got = Machines.roomCentre(item.layout, room.id, TUNING)
				local want = { x = (room.column - 1) * P, y = 0, z = (room.row - 1) * P }
				if not Deep.equal(got, want) then
					table.insert(
						problems,
						`{item.name} room {room.id} at ({room.column}, {room.row}): roomCentre = {Deep.show(
							got
						)}, expected {Deep.show(want)}`
					)
				end
				for slot = 1, TUNING.instance.machine_slots_per_room do
					local q = PlacementContract.QUADRANTS[slot]
					local machine = {
						id = 1,
						room = room.id,
						slot = slot,
						keyClass = 1,
						tag = 1,
						requiredSetting = 1,
					}
					local pos = Machines.positionOf(item.layout, machine, TUNING)
					local fromCentre = { x = got.x + q.sx * P / 4, y = 0, z = got.z + q.sz * P / 4 }
					if not Deep.equal(pos, fromCentre) then
						table.insert(
							problems,
							`{item.name} room {room.id} slot {slot}: positionOf = {Deep.show(pos)} is not roomCentre + quadrant offset {Deep.show(
								fromCentre
							)}`
						)
					end
				end
			end
		end
		if #problems > 0 then
			Raise.fail(
				`C-1: roomCentre disagrees with the Contract's formula:\n{Raise.firstFew(
					problems,
					8
				)}`
			)
		end
	end,

	["Contract / C-1: Machines.roomCentre raises, naming the id, for a room not in the layout, and does not mutate the layout"] = function()
		assert(
			typeof(Machines.roomCentre) == "function",
			`Machines.roomCentre is {typeof(Machines.roomCentre)}, expected a function (C-1's one new export)`
		)
		local layout = LayoutContract.layoutOf(LayoutContract.FIXTURES[2])
		local before = Contract.snapshot(layout)
		for _, id in { 7, 0, 99 } do
			local ok, err = pcall(Machines.roomCentre, layout, id, TUNING)
			assert(
				ok == false,
				`roomCentre returned {Deep.show(err)} for room {id}, which is not in the layout; it must raise`
			)
			assert(
				string.find(tostring(err), tostring(id), 1, true) ~= nil,
				`roomCentre's error for room {id} does not name the id: {tostring(err)}`
			)
		end
		assert(
			Deep.equal(before, layout),
			`roomCentre mutated the layout:\n{Deep.diff(before, layout)}`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: over seeds 1..200 at n = 4, 5, 6, every room has one floor (top face y = 0) and one ceiling (bottom face y = room_ceiling_studs) sized (P, T, P) on its cell; every outer and doorless edge is solid wall from floor to ceiling across the whole cell edge; every doored edge is open exactly in |u| < W/2, 0 ≤ y < D and wall everywhere else, lintel included"] = function()
		local build = parts()
		local thickness = T()
		local count = Contract.overSweep(build, function(specs, facility, label)
			Contract.assertGeometry(specs, facility, TUNING, thickness, label)
		end)
		print(
			`        [measured] AC-1 held on {count} facilities; sweep generated in {string.format(
				"%.2f",
				Contract.sweepSeconds(4)
			)} s`
		)
	end,

	["AC-1: on the hand-built 2 × 2 tree block (doors 1-2, 1-3, 3-4; rooms 2 and 4 abut with no door) the doorless edge is solid, the three doored edges are open exactly in the doorway, and all eight outer edges are solid"] = function()
		local stats = Contract.assertGeometry(
			parts()(fixture, TUNING),
			fixture,
			TUNING,
			T(),
			"the tree block"
		)
		assert(
			stats.solid == 1 and stats.door == 3 and stats.outer == 8,
			`the tree block has {Contract.describeCoverage(stats)}`
		)
	end,

	--[[ AC-2 ]]

	["AC-2: over seeds 1..200 at n = 4, 5, 6 and on the tree block, each machine has exactly one spec of kind machine named tostring(id), sized ANCHOR_SIZE, centred at positionOf's x and z with y = ANCHOR_SIZE.y / 2, and there are no other machine specs"] = function()
		local build = parts()
		local size = anchorSize()
		Contract.assertAnchors(build(fixture, TUNING), fixture, TUNING, size, "the tree block")
		Contract.overSweep(build, function(specs, facility, label)
			Contract.assertAnchors(specs, facility, TUNING, size, label)
		end)
	end,

	--[[ AC-3 ]]

	["AC-3: over seeds 1..200 at n = 4, 5, 6 and on the tree block, no two solid specs (floor, ceiling, wall) overlap except in a corner column whose x and z extents are both ≤ T, and every solid spec lies within one occupied cell's square grown by T/2"] = function()
		local build = parts()
		local thickness = T()
		local stats = Contract.assertSolids(
			build(fixture, TUNING),
			fixture,
			TUNING,
			thickness,
			"the tree block"
		)
		print(`        [measured] AC-3 on the tree block: {Contract.describeSolids(stats)}`)
		Contract.overSweep(build, function(specs, facility, label)
			Contract.assertSolids(specs, facility, TUNING, thickness, label)
		end)
	end,

	--[[ AC-4 ]]

	["AC-4: over seeds 1..200 at n = 4, 5, 6, the y = 3 segment between two machines of one room crosses no wall spec, and between two machines of adjacent rooms with no door it crosses at least one; both clauses are exercised (counts printed, zero of either fails)"] = function()
		local build = parts()
		local same, noDoor = 0, 0
		Contract.overSweep(build, function(specs, facility, label)
			local stats = Contract.assertSight(specs, facility, TUNING, label)
			same += stats.sameRoomPairs
			noDoor += stats.noDoorPairs
		end)
		print(
			`        [measured] AC-4 pairs over the sweep: {same} same-room, {noDoor} doorless-adjacent`
		)
		assert(
			same > 0 and noDoor > 0,
			`AC-4 needle: {same} same-room and {noDoor} doorless-adjacent pairs; a clause was never exercised`
		)
	end,

	["AC-4: on the tree block, machines 3 and 5 straddle the doorless edge 2-4 on a diagonal through its midpoint and the segment crosses a wall; machines 1 and 2 share room 1 and their segment crosses none"] = function()
		local specs = parts()(fixture, TUNING)
		local stats = Contract.assertSight(specs, fixture, TUNING, "the tree block")
		assert(
			stats.sameRoomPairs == 1 and stats.noDoorPairs == 1,
			`the tree block exercises {Contract.describeSight(stats)}; expected one pair of each`
		)
	end,
}
