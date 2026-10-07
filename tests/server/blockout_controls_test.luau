--!strict
--[[
	The negative controls for MAP-001, and the proof that each check and each
	predicate in `tests/helpers/BlockoutContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `src/server/facility/
	Blockout.luau` does not exist, every test in `tests/server/blockout_test.luau`
	fails before its assertion runs, and so not one of that file's checks has
	been observed to accept or reject anything. These controls need only
	`Generator`, `Layout`, `Machines`, `Ring` and `MechanicsTuning`, which are
	merged, so the numbers printed below are MEASUREMENTS taken in RED rather
	than claims left for GREEN. The story's handoff carries them as a table.

	FOUR KINDS OF CONTROL:

	  * THE PREDICATES. C-5's overlap and containment and C-6's slab test are
	    run on hand-built boxes: touching faces, a corner column, a coincident
	    pair, a grazing segment, a segment ending on a face.
	  * THE REFERENCE. A correct builder is ACCEPTED by every check on the
	    hand-built tree block and on the whole 200-seed sweep at n = 4, 5, 6. A check that
	    rejects everything is indistinguishable from a broken one, and the
	    acceptance half is the one that is easy to leave out.
	  * THE WRONG BUILDERS. Each is REJECTED by the check aimed at it, with a
	    message naming the criterion and the defect, and each is then held to
	    the checks it SHOULD pass, so a control that fires is attributable to
	    its one defect.
	  * THE FIXTURE'S ASSUMPTIONS. The tree block assumes a grid of at least
	    2 × 2, a doorway narrower than half a room and lower than the ceiling,
	    and C-6's segment height under the doorway; each is checked against the
	    tuning as read, so a tuning change fails here with a name.
]]

local Contract = require("../helpers/BlockoutContract")
local Deep = require("../helpers/Deep")
local PlacementContract = require("../helpers/PlacementContract")
local Stubs = require("../helpers/BlockoutStubs")

local TUNING = Contract.TUNING
local T = Stubs.T
local ANCHOR = Stubs.ANCHOR_SIZE

local function refuses(run: () -> (), what: string): string
	local ok, err = pcall(run)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local function box(
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
): Contract.Box
	return Contract.boxFrom({ x = x0, y = y0, z = z0 }, { x = x1, y = y1, z = z1 })
end

local function v(x: number, y: number, z: number): Contract.Vec3
	return { x = x, y = y, z = z }
end

local fixture = Contract.treeBlockFacility()

-- The four checks, by name, over a builder on one facility.
local function checks(
	builder: Contract.Builder,
	facility: Contract.Facility
): { [string]: () -> () }
	local specs = builder(facility, TUNING)
	return {
		["AC-1"] = function()
			Contract.assertGeometry(specs, facility, TUNING, T)
		end,
		["AC-2"] = function()
			Contract.assertAnchors(specs, facility, TUNING, ANCHOR)
		end,
		["AC-3"] = function()
			Contract.assertSolids(specs, facility, TUNING, T)
		end,
		["AC-4"] = function()
			Contract.assertSight(specs, facility, TUNING)
		end,
	}
end

-- Every check except those in `fails` must pass on the fixture AND on the
-- sweep, so the control's defect is the only thing it trips.
local function heldToTheRest(builder: Contract.Builder, who: string, fails: { string })
	local failing: { [string]: boolean } = {}
	for _, ac in fails do
		failing[ac] = true
	end
	for ac, run in checks(builder, fixture) do
		if not failing[ac] then
			local ok, err = pcall(run)
			assert(
				ok,
				`{who} should pass {ac} on the tree block, its defect being elsewhere:\n{tostring(
					err
				)}`
			)
		end
	end
	local sweepChecks: { [string]: (specs: { Contract.PartSpec }, f: Contract.Facility, label: string) -> () } =
		{
			["AC-1"] = function(specs, f, label)
				Contract.assertGeometry(specs, f, TUNING, T, label)
			end,
			["AC-2"] = function(specs, f, label)
				Contract.assertAnchors(specs, f, TUNING, ANCHOR, label)
			end,
			["AC-3"] = function(specs, f, label)
				Contract.assertSolids(specs, f, TUNING, T, label)
			end,
			["AC-4"] = function(specs, f, label)
				Contract.assertSight(specs, f, TUNING, label)
			end,
		}
	for ac, check in sweepChecks do
		if not failing[ac] then
			local ok, err = pcall(Contract.overSweep, builder, check)
			assert(
				ok,
				`{who} should pass {ac} over the sweep, its defect being elsewhere:\n{tostring(err)}`
			)
		end
	end
end

return {
	--[[ ================================================================
	     The predicates (C-5, C-6), on hand-built boxes.
	     ================================================================ ]]

	["predicates / C-5: overlap is nil for boxes sharing a face, for boxes apart, and for a corner column of T/2 × T/2 it is allowed; a coincident pair and a T × P overlap are not allowed"] = function()
		local floor = box(-32, -1, -32, 32, 0, 32)
		local wall = box(-32, 0, 31.5, 32, 16, 32.5) -- along x on the line z = 32
		assert(
			Contract.overlap(floor, wall) == nil,
			"a floor and a wall sharing the face y = 0 must not overlap"
		)
		assert(
			Contract.overlap(floor, box(32, -1, -32, 96, 0, 32)) == nil,
			"two abutting floors must not overlap"
		)
		assert(
			Contract.overlap(floor, box(100, 0, 100, 101, 1, 101)) == nil,
			"boxes apart must not overlap"
		)
		-- The perpendicular wall at x = 32 meets `wall` in a T/2 × T/2 column.
		local corner = Contract.overlap(wall, box(31.5, 0, -32, 32.5, 16, 32))
		assert(
			corner ~= nil,
			"two perpendicular walls meeting at a vertex overlap in a corner column"
		)
		assert(
			Deep.equal(corner, v(0.5, 16, 0.5)),
			`the corner column measures {Deep.show(corner)}, expected 0.5 × 16 × 0.5`
		)
		assert(
			Contract.overlapAllowed(corner :: Contract.Vec3, T),
			"a T/2 × T/2 corner column is allowed"
		)
		local twin = Contract.overlap(wall, box(-32, 0, 31.5, 32, 16, 32.5))
		assert(
			twin ~= nil and Deep.equal(twin, v(64, 16, 1)),
			`coincident walls overlap by {Deep.show(twin)}`
		)
		assert(
			not Contract.overlapAllowed(twin :: Contract.Vec3, T),
			"a 64-stud overlap is not a corner column"
		)
		assert(
			not Contract.overlapAllowed(v(1, 16, 1 + 1e-3), T),
			"an extent of T + 0.001 is not allowed"
		)
		assert(
			Contract.overlapAllowed(v(1, 16, 1 + 1e-7), T),
			"an extent of T + 1e-7 is within the tolerance"
		)
	end,

	["predicates / C-5: contains accepts a box on the boundary (to 1e-6) and refuses one past it by 0.001"] = function()
		local cell = box(-32.5, -math.huge, -32.5, 32.5, math.huge, 32.5)
		assert(
			Contract.contains(cell, box(-32.5, 0, -32, 32.5, 16, 32)),
			"a box exactly on the boundary is contained"
		)
		assert(
			Contract.contains(cell, box(-32.5 - 1e-7, 0, -32, 32.5, 16, 32)),
			"1e-7 past the boundary is within tolerance"
		)
		assert(
			not Contract.contains(cell, box(-32.501, 0, -32, 32.5, 16, 32)),
			"0.001 past the boundary is not contained"
		)
		assert(
			not Contract.contains(cell, box(-32, 0, -32, 33, 16, 32)),
			"a box poking out on +x is not contained"
		)
	end,

	["predicates / C-6: the slab test crosses a box the segment passes through, and not one it grazes, runs along, ends on, or misses"] = function()
		local wall = box(31.5, 0, -32, 32.5, 16, 32) -- along z on the line x = 32
		assert(
			Contract.segmentCrosses(v(16, 3, -16), v(48, 3, 16), wall),
			"a segment through the wall crosses it"
		)
		assert(
			Contract.segmentCrosses(v(16, 3, 0), v(32, 3, 0), wall),
			"a segment ending inside the wall crosses it"
		)
		assert(
			not Contract.segmentCrosses(v(16, 3, -16), v(31.5, 3, 16), wall),
			"a segment ending ON the face does not cross"
		)
		assert(
			not Contract.segmentCrosses(v(31.5, 3, -16), v(31.5, 3, 16), wall),
			"a segment running along the face does not cross"
		)
		assert(
			not Contract.segmentCrosses(v(16, 3, 40), v(48, 3, 40), wall),
			"a segment past the wall's end does not cross"
		)
		assert(
			not Contract.segmentCrosses(v(16, 17, -16), v(48, 17, 16), wall),
			"a segment above the wall does not cross"
		)
		assert(
			not Contract.segmentCrosses(v(-16, 3, -16), v(16, 3, 16), wall),
			"a segment entirely on one side does not cross"
		)
		local floor = box(-32, -1, -32, 32, 0, 32)
		assert(
			not Contract.segmentCrosses(v(-16, 3, -16), v(16, 3, 16), floor),
			"the y = 3 segment does not cross a floor"
		)
	end,

	--[[ ================================================================
	     The fixture's assumptions.
	     ================================================================ ]]

	["fixture: the tree block assumes a grid of at least 2 × 2, a doorway narrower than half a room and lower than the ceiling, and C-6's segment height under the doorway"] = function()
		local t = TUNING.instance
		local problems: { string } = {}
		if t.layout_grid_columns < 2 or t.layout_grid_rows < 2 then
			table.insert(
				problems,
				`grid {t.layout_grid_columns} × {t.layout_grid_rows} cannot hold a 2 × 2 block`
			)
		end
		if not (t.doorway_width_studs < t.room_pitch_studs / 2) then
			table.insert(
				problems,
				`doorway_width_studs {t.doorway_width_studs} is not under half of room_pitch_studs`
			)
		end
		if not (t.doorway_height_studs < t.room_ceiling_studs) then
			table.insert(
				problems,
				`doorway_height_studs {t.doorway_height_studs} is not under room_ceiling_studs`
			)
		end
		if not (Contract.SEGMENT_Y < t.doorway_height_studs) then
			table.insert(
				problems,
				`SEGMENT_Y {Contract.SEGMENT_Y} is not under doorway_height_studs`
			)
		end
		if not (T < t.doorway_width_studs) then
			table.insert(problems, `T {T} is not under doorway_width_studs`)
		end
		assert(
			#problems == 0,
			`the fixture no longer matches the tuning:\n{table.concat(problems, "\n")}`
		)
		-- The non-door adjacency and the diagonal pair are what they claim.
		local edges = Contract.edgesOf(fixture.layout, TUNING)
		local kinds: { [string]: number } = { outer = 0, door = 0, solid = 0 }
		for _, e in edges do
			kinds[e.kind] += 1
		end
		assert(
			Deep.equal(kinds, { outer = 8, door = 3, solid = 1 }),
			`the tree block's edges are {Deep.show(kinds)}, expected 8 outer, 3 doored, 1 doorless`
		)
		local solid = Contract.edgeOfKind(fixture.layout, TUNING, "solid")
		assert(
			Deep.equal(solid.rooms, Contract.TREE_BLOCK.nonDoorPair),
			`the doorless edge joins {Deep.show(solid.rooms)}`
		)
		local same, noDoor = Contract.sightPairs(fixture)
		assert(
			#same == 1 and same[1][1].id == 1 and same[1][2].id == 2,
			"the same-room pair is machines 1 and 2"
		)
		assert(
			#noDoor == 1 and noDoor[1][1].id == 3 and noDoor[1][2].id == 5,
			"the doorless pair is machines 3 and 5"
		)
		-- The diagonal's midpoint IS the doorless edge's midpoint.
		local a = Contract.machineById(fixture, 3)
		local b = Contract.machineById(fixture, 5)
		local pa = PlacementContract.expectedPosition(fixture.layout, a.room, a.slot, TUNING)
		local pb = PlacementContract.expectedPosition(fixture.layout, b.room, b.slot, TUNING)
		local midpoint = Contract.pointOn(solid, 0, Contract.SEGMENT_Y)
		assert(
			(pa.x + pb.x) / 2 == midpoint.x and (pa.z + pb.z) / 2 == midpoint.z,
			`the diagonal's midpoint is ({(pa.x + pb.x) / 2}, {(pa.z + pb.z) / 2}), the edge midpoint ({midpoint.x}, {midpoint.z})`
		)
	end,

	["fixture: the sweep's edges include every kind on every n, so each AC-1 branch is exercised (measured counts printed), and the sweep time is recorded"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local totals = { outer = 0, door = 0, solid = 0, same = 0, noDoor = 0, facilities = 0 }
			local withSolid, withNoDoor = 0, 0
			for _, s in Contract.facilities(n) do
				totals.facilities += 1
				local solidHere = 0
				for _, e in Contract.edgesOf(s.facility.layout, TUNING) do
					totals[e.kind] += 1
					if e.kind == "solid" then
						solidHere += 1
					end
				end
				local same, noDoor = Contract.sightPairs(s.facility)
				totals.same += #same
				totals.noDoor += #noDoor
				withSolid += if solidHere > 0 then 1 else 0
				withNoDoor += if #noDoor > 0 then 1 else 0
			end
			print(
				`        [measured] sweep n = {n}: {totals.facilities} facilities in {string.format(
					"%.2f",
					Contract.sweepSeconds(n)
				)} s; edges {totals.outer} outer, {totals.door} doored, {totals.solid} doorless ({withSolid} facilities with a doorless edge); pairs {totals.same} same-room, {totals.noDoor} doorless-adjacent ({withNoDoor} facilities with one)`
			)
			assert(
				totals.door > 0 and totals.solid > 0 and totals.outer > 0,
				`n = {n}: an edge kind never occurs`
			)
			assert(totals.same > 0 and totals.noDoor > 0, `n = {n}: an AC-4 pair kind never occurs`)
		end
	end,

	--[[ ================================================================
	     The reference. Everything below is this builder with one defect.
	     ================================================================ ]]

	["baseline: the reference builder passes AC-1, AC-2, AC-3 and AC-4 on the tree block and over the whole sweep (measured: see the run log)"] = function()
		for ac, run in checks(Stubs.reference, fixture) do
			local ok, err = pcall(run)
			assert(ok, `the reference fails {ac} on the tree block:\n{tostring(err)}`)
		end
		heldToTheRest(Stubs.reference, "the reference", {})
		local specs = Stubs.reference(fixture, TUNING)
		local coverage = Contract.assertGeometry(specs, fixture, TUNING, T)
		local solids = Contract.assertSolids(specs, fixture, TUNING, T)
		local sight = Contract.assertSight(specs, fixture, TUNING)
		print(
			`        [measured] reference on the tree block: {Contract.describeCoverage(coverage)}; {Contract.describeSolids(
				solids
			)}; {Contract.describeSight(sight)}`
		)
		local door = Contract.edgeOfKind(fixture.layout, TUNING, "door")
		local D, W = TUNING.instance.doorway_height_studs, TUNING.instance.doorway_width_studs
		local below = Contract.openLengthAt(specs, door, D / 2, TUNING, T)
		local above = Contract.openLengthAt(specs, door, D + 1, TUNING, T)
		assert(
			below == W,
			`the reference's doorway is {below} wide at y = D/2, expected doorway_width_studs {W}`
		)
		assert(above == 0, `the reference's lintel leaves {above} open at y = D + 1`)
		print(
			`        [measured] reference doored edge: open {below} studs at y = {D / 2}, {above} at y = {D + 1}`
		)
	end,

	["baseline: the reference's specs have C-1's shape, and it is deterministic and does not mutate the facility"] = function()
		local before = Contract.snapshot(fixture)
		local a = Stubs.reference(fixture, TUNING)
		local b = Stubs.reference(fixture, TUNING)
		assert(
			Deep.equal(before, fixture),
			`the reference mutated the facility:\n{Deep.diff(before, fixture)}`
		)
		assert(Deep.equal(a, b), `two reference builds differ:\n{Deep.diff(a, b)}`)
		local problems = Contract.shapeProblems(a)
		assert(
			#problems == 0,
			`the reference's specs are malformed:\n{table.concat(problems, "\n")}`
		)
		-- And the shape check is not vacuous.
		local bad = Deep.copy(a)
		bad[1].size.y = 0
		bad[2].extra = true
		bad[3].kind = "roof"
		local found = Contract.shapeProblems(bad)
		assert(
			#found == 3,
			`shapeProblems found {#found} problems in a spec list with three, got:\n{table.concat(
				found,
				"\n"
			)}`
		)
	end,

	--[[ ================================================================
	     AC-1 controls.
	     ================================================================ ]]

	["AC-1 control: a builder that leaves a gap on every shared edge fails AC-1 on the tree block, whose edge 2-4 has no door - and passes AC-2 and AC-3"] = function()
		local specs = Stubs.gapEveryEdge(fixture, TUNING)
		local solid = Contract.edgeOfKind(fixture.layout, TUNING, "solid")
		local D, W = TUNING.instance.doorway_height_studs, TUNING.instance.doorway_width_studs
		local open = Contract.openLengthAt(specs, solid, D / 2, TUNING, T)
		assert(
			open == W,
			`the gap-everywhere builder leaves {open} studs open on the doorless edge, expected W = {W}`
		)
		local message = refuses(function()
			Contract.assertGeometry(specs, fixture, TUNING, T)
		end, "the gap-everywhere builder must fail AC-1 on a layout with a non-door adjacency")
		names(message, "AC-1", "the gap-everywhere builder fails")
		names(message, "has no door", "the gap-everywhere builder fails")
		names(message, "rooms 2 and 4", "the gap-everywhere builder fails on the doorless edge")
		local _, stats = Contract.coverage(specs, fixture.layout, TUNING, T)
		print(
			`        [measured] gap on every edge (tree block): doorless edge open {open} studs at y = {D / 2}; {Contract.describeCoverage(
				stats
			)}`
		)
		-- AC-4 is the diagonal pair's business (below); AC-2 and AC-3 must pass.
		heldToTheRest(Stubs.gapEveryEdge, "the gap-everywhere builder", { "AC-1", "AC-4" })
	end,

	["AC-1 control: a doorway W + 2 wide fails AC-1 naming the gap, on the tree block and over the sweep - and passes AC-2, AC-3 and AC-4"] = function()
		local specs = Stubs.gapTooWide(fixture, TUNING)
		local door = Contract.edgeOfKind(fixture.layout, TUNING, "door")
		local D, W = TUNING.instance.doorway_height_studs, TUNING.instance.doorway_width_studs
		local open = Contract.openLengthAt(specs, door, D / 2, TUNING, T)
		assert(
			open == W + 2,
			`the wide-gap builder's doorway is {open} wide, expected W + 2 = {W + 2}`
		)
		local message = refuses(function()
			Contract.assertGeometry(specs, fixture, TUNING, T)
		end, "the wide-gap builder must fail AC-1")
		names(message, "AC-1", "the wide-gap builder fails")
		names(message, "the gap in the", "the wide-gap builder fails naming the gap")
		names(message, "outside |u| <", "the wide-gap builder fails on a point outside the doorway")
		local sweepMessage = refuses(function()
			Contract.overSweep(Stubs.gapTooWide, function(s, f, label)
				Contract.assertGeometry(s, f, TUNING, T, label)
			end)
		end, "the wide-gap builder must fail AC-1 over the sweep")
		names(sweepMessage, "AC-1", "the wide-gap builder fails over the sweep")
		local _, stats = Contract.coverage(specs, fixture.layout, TUNING, T)
		print(
			`        [measured] gap W + 2 (tree block): doored edge open {open} studs at y = {D / 2} (threshold exactly {W}); {Contract.describeCoverage(
				stats
			)}`
		)
		heldToTheRest(Stubs.gapTooWide, "the wide-gap builder", { "AC-1" })
	end,

	["AC-1 control: an outer edge without its wall fails AC-1 naming the outer edge - and passes AC-2, AC-3 and AC-4"] = function()
		local specs = Stubs.outerEdgeMissing(fixture, TUNING)
		local reference = Stubs.reference(fixture, TUNING)
		assert(
			#Contract.ofKind(specs, "wall") == #Contract.ofKind(reference, "wall") - 1,
			"the control drops exactly one wall"
		)
		local message = refuses(function()
			Contract.assertGeometry(specs, fixture, TUNING, T)
		end, "the missing-outer-wall builder must fail AC-1")
		names(message, "AC-1", "the missing-outer-wall builder fails")
		names(
			message,
			"outer edge of room 1",
			"the missing-outer-wall builder fails on room 1's outer edge"
		)
		local _, stats = Contract.coverage(specs, fixture.layout, TUNING, T)
		print(
			`        [measured] outer edge missing (tree block): {Contract.describeCoverage(stats)}`
		)
		heldToTheRest(Stubs.outerEdgeMissing, "the missing-outer-wall builder", { "AC-1" })
	end,

	["AC-1 control: a ceiling whose centre is at H − T/2 (D-2's third mutation) fails AC-1 naming the bottom face - and passes AC-2 and AC-4; AC-3 fires too, because a slab inside [H − T, H] overlaps every wall that reaches H"] = function()
		local specs = Stubs.ceilingLow(fixture, TUNING)
		local H = TUNING.instance.room_ceiling_studs
		local lowest = math.huge
		for _, c in Contract.ofKind(specs, "ceiling") do
			lowest = math.min(lowest, Contract.boxOf(c).min.y)
		end
		assert(
			lowest == H - T,
			`the low ceiling's bottom face is at {lowest}, expected H − T = {H - T}`
		)
		local message = refuses(function()
			Contract.assertGeometry(specs, fixture, TUNING, T)
		end, "the low-ceiling builder must fail AC-1")
		names(message, "AC-1", "the low-ceiling builder fails")
		names(message, "ceiling", "the low-ceiling builder fails on the ceiling")
		names(
			message,
			`bottom face at y = {H - T}`,
			"the low-ceiling builder fails naming the face"
		)
		-- The physical consequence: the lowered slab sits inside the walls' y
		-- range, so AC-3 sees a T-deep overlap along every wall of every room.
		local _, solids = Contract.solidViolations(specs, fixture, TUNING, T)
		assert(solids.disallowed > 0, "a ceiling inside the walls' span must overlap them (AC-3)")
		assert(
			solids.worst ~= nil and (solids.worst :: Contract.Vec3).y == T,
			`the ceiling/wall overlap is {Deep.show(solids.worst)} deep, expected T = {T} on y`
		)
		print(
			`        [measured] ceiling low: bottom face y = {lowest}, expected room_ceiling_studs {H}; AC-3 also sees {solids.disallowed} ceiling/wall overlaps (worst {Deep.show(
				solids.worst
			)})`
		)
		heldToTheRest(Stubs.ceilingLow, "the low-ceiling builder", { "AC-1", "AC-3" })
	end,

	--[[ ================================================================
	     AC-2 controls.
	     ================================================================ ]]

	["AC-2 control: anchors at the room centre fail AC-2 naming positionOf - and pass AC-1, AC-3 and AC-4"] = function()
		local specs = Stubs.anchorAtCentre(fixture, TUNING)
		local drift = Contract.anchorDrift(specs, fixture, TUNING)
		local P = TUNING.instance.room_pitch_studs
		local want = P / 4 * math.sqrt(2)
		assert(
			math.abs(drift - want) < 1e-9,
			`anchors drift {drift} from positionOf, expected P/4 × √2 = {want}`
		)
		local message = refuses(function()
			Contract.assertAnchors(specs, fixture, TUNING, ANCHOR)
		end, "the centre-anchor builder must fail AC-2")
		names(message, "AC-2", "the centre-anchor builder fails")
		names(message, "positionOf", "the centre-anchor builder fails naming positionOf")
		print(
			`        [measured] anchors at room centre: drift {string.format("%.3f", drift)} studs from positionOf (threshold 0)`
		)
		heldToTheRest(Stubs.anchorAtCentre, "the centre-anchor builder", { "AC-2" })
	end,

	["AC-2 control: anchors named Machine<id> fail AC-2 naming the id - and pass AC-1, AC-3 and AC-4"] = function()
		local specs = Stubs.anchorNamedMachine(fixture, TUNING)
		local problems = Contract.anchorViolations(specs, fixture, TUNING, ANCHOR)
		assert(
			#problems == #fixture.placement.machines,
			`{#problems} problems for {#fixture.placement.machines} misnamed anchors`
		)
		local message = refuses(function()
			Contract.assertAnchors(specs, fixture, TUNING, ANCHOR)
		end, "the misnamed-anchor builder must fail AC-2")
		names(message, "AC-2", "the misnamed-anchor builder fails")
		names(message, 'named "1"', "the misnamed-anchor builder fails naming the id")
		names(message, "Machine1", "the misnamed-anchor builder fails showing the wrong name")
		print(
			`        [measured] anchors named Machine<id>: {#problems} of {#fixture.placement.machines} machines without an anchor named by id`
		)
		heldToTheRest(Stubs.anchorNamedMachine, "the misnamed-anchor builder", { "AC-2" })
	end,

	--[[ ================================================================
	     AC-3 controls.
	     ================================================================ ]]

	["AC-3 control: one wall per room per side puts two coincident walls on every shared edge and fails AC-3 as an overlap - and passes AC-1, AC-2 and AC-4"] = function()
		local specs = Stubs.wallPerRoom(fixture, TUNING)
		local _, stats = Contract.solidViolations(specs, fixture, TUNING, T)
		-- Each shared edge is built twice, piece for piece: the three doored
		-- edges carry two jambs and a lintel each, the doorless edge one slab.
		local expected = 3 * 3 + 1
		assert(
			stats.disallowed == expected,
			`{stats.disallowed} disallowed overlaps, expected one per duplicated piece = {expected}`
		)
		assert(
			stats.outside == 0,
			`{stats.outside} specs outside the footprint; the defect is overlap`
		)
		local message = refuses(function()
			Contract.assertSolids(specs, fixture, TUNING, T)
		end, "the wall-per-room builder must fail AC-3")
		names(message, "AC-3", "the wall-per-room builder fails")
		names(message, "overlap by", "the wall-per-room builder fails as an overlap")
		print(
			`        [measured] wall per room per side (tree block): {Contract.describeSolids(stats)}`
		)
		heldToTheRest(Stubs.wallPerRoom, "the wall-per-room builder", { "AC-3" })
	end,

	["AC-3 control: a wall on an unoccupied cell's edge fails AC-3 as outside the footprint - and passes AC-1, AC-2 and AC-4"] = function()
		local specs = Stubs.strayWall(fixture, TUNING)
		local _, stats = Contract.solidViolations(specs, fixture, TUNING, T)
		assert(
			stats.outside == 1,
			`{stats.outside} specs outside the footprint, expected exactly 1`
		)
		assert(
			stats.disallowed == 0,
			`{stats.disallowed} disallowed overlaps; the defect is footprint`
		)
		local message = refuses(function()
			Contract.assertSolids(specs, fixture, TUNING, T)
		end, "the stray-wall builder must fail AC-3")
		names(message, "AC-3", "the stray-wall builder fails")
		names(
			message,
			"outside the occupied cells' footprint",
			"the stray-wall builder fails as outside"
		)
		names(message, "WallStray", "the stray-wall builder fails naming the spec")
		print(`        [measured] stray wall (tree block): {Contract.describeSolids(stats)}`)
		heldToTheRest(Stubs.strayWall, "the stray-wall builder", { "AC-3" })
	end,

	--[[ ================================================================
	     AC-4 controls.
	     ================================================================ ]]

	["AC-4 control: no walls on shared edges lets the doorless pair see each other and fails AC-4's second clause - and passes AC-2 and AC-3 (AC-1 fails too, by construction)"] = function()
		local specs = Stubs.noSharedWalls(fixture, TUNING)
		local _, stats = Contract.sightViolations(specs, fixture, TUNING)
		assert(
			stats.noDoorPairs == 1 and stats.noDoorClear == 1,
			`{stats.noDoorClear} of {stats.noDoorPairs} doorless pairs clear, expected 1 of 1`
		)
		assert(stats.sameRoomCrossing == 0, "the same-room pair must still cross nothing")
		local message = refuses(function()
			Contract.assertSight(specs, fixture, TUNING)
		end, "the no-shared-walls builder must fail AC-4")
		names(message, "AC-4", "the no-shared-walls builder fails")
		names(
			message,
			"no door between them",
			"the no-shared-walls builder fails on the doorless pair"
		)
		names(message, "crosses no wall", "the no-shared-walls builder fails on the second clause")
		local sweepMessage = refuses(function()
			Contract.overSweep(Stubs.noSharedWalls, function(s, f, label)
				Contract.assertSight(s, f, TUNING, label)
			end)
		end, "the no-shared-walls builder must fail AC-4 over the sweep")
		names(sweepMessage, "AC-4", "the no-shared-walls builder fails over the sweep")
		print(`        [measured] no shared walls (tree block): {Contract.describeSight(stats)}`)
		heldToTheRest(Stubs.noSharedWalls, "the no-shared-walls builder", { "AC-1", "AC-4" })
	end,

	["AC-4 control: the gap-on-every-edge builder lets the diagonal pair across the doorless edge 2-4 - whose segment passes the edge midpoint - see each other, and fails AC-4"] = function()
		local specs = Stubs.gapEveryEdge(fixture, TUNING)
		local a = Contract.machineById(fixture, Contract.TREE_BLOCK.diagonalMachines[1])
		local b = Contract.machineById(fixture, Contract.TREE_BLOCK.diagonalMachines[2])
		local crossed = Contract.wallsCrossed(specs, fixture, a, b, TUNING)
		assert(
			#crossed == 0,
			`the diagonal pair crosses {#crossed} wall(s) through the illicit gap, expected 0`
		)
		local withReference =
			Contract.wallsCrossed(Stubs.reference(fixture, TUNING), fixture, a, b, TUNING)
		assert(#withReference >= 1, "with the reference the same pair must cross a wall")
		local message = refuses(function()
			Contract.assertSight(specs, fixture, TUNING)
		end, "the gap-everywhere builder must fail AC-4 on the diagonal pair")
		names(message, "AC-4", "the gap-everywhere builder fails AC-4")
		names(
			message,
			"machines 3 (room 2 slot 3) and 5 (room 4 slot 2)",
			"the gap-everywhere builder fails on the diagonal pair"
		)
		print(
			`        [measured] gap on every edge, diagonal pair 3-5: crosses {#crossed} walls (reference: {#withReference})`
		)
	end,

	["AC-4 positive control: on the tree block the reference's walls block the doorless pair exactly once and a doored pair off the doorway axis is blocked too - the door is a gap, not a missing wall"] = function()
		local specs = Stubs.reference(fixture, TUNING)
		local a = Contract.machineById(fixture, 3)
		local b = Contract.machineById(fixture, 5)
		local crossed = Contract.wallsCrossed(specs, fixture, a, b, TUNING)
		assert(
			#crossed == 1,
			`the doorless diagonal crosses {#crossed} wall(s), expected exactly 1`
		)
		-- Machines 2 (room 1, slot 4) and 3 (room 2, slot 3) straddle the
		-- doored edge 1-2 at z = +P/4, 16 studs off the doorway's centre.
		local c = Contract.machineById(fixture, 2)
		local throughDoorEdge = Contract.wallsCrossed(specs, fixture, c, a, TUNING)
		assert(
			#throughDoorEdge == 1,
			`the off-axis pair across the doored edge crosses {#throughDoorEdge} wall(s), expected 1 (a jamb)`
		)
		print(
			`        [measured] reference sight: doorless diagonal crosses {#crossed}; off-axis pair across a doored edge crosses {#throughDoorEdge}`
		)
	end,
}
