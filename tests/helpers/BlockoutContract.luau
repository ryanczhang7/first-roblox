--!strict
--[[
	MAP-001's checks, geometry predicates, sweep and fixtures, written once over
	a BUILDER - `(facility, tuning) -> { PartSpec }` - rather than over
	`src/server/facility/Blockout.luau` by name, the `PlacementContract`
	arrangement, for the same reason.

	`tests/server/blockout_test.luau` applies these to the real module.
	`tests/server/blockout_controls_test.luau` applies them to the deliberately
	wrong builders in `BlockoutStubs.luau`, so that in RED - where the module
	does not exist, the real file fails at `require`, and not one assertion in
	it has executed - every check here has been EXECUTED and observed to reject
	the defect it exists to catch, and to accept a reference that is correct.

	THE ORACLE PARTITION (story `## Contract`, C-8) IS HONOURED HERE.

	  * SETTLED (AC-1, AC-2). Every expected size, face and gap edge is
	    ARITHMETIC over `room_pitch_studs`, `room_ceiling_studs`,
	    `doorway_width_studs` and `doorway_height_studs` as read from
	    `MechanicsTuning`, and over the wall thickness `T` and anchor size the
	    caller hands in (the real test passes `Blockout.WALL_THICKNESS` and
	    `Blockout.ANCHOR_SIZE` after pinning them to C-1's values). Nothing is
	    read back from a builder's output and compared with itself. Machine
	    positions are the Contract's formula via `PlacementContract.expectedPosition`,
	    never `Machines.positionOf`.
	  * MECHANICAL (AC-3, AC-4). AABB overlap, containment and the strict
	    segment/box slab test are written HERE, exactly as C-5 and C-6 define
	    them, with a 1e-6 tolerance and no threshold to invent. The controls
	    file exercises each predicate on hand-built boxes before trusting it.

	WALL COVERAGE, NOT WALL COUNTS. C-3 leaves the decomposition of an edge into
	specs to the implementer, so AC-1 tests what an edge COVERS: sample points on
	the grid-line plane plus exact boundary probes at u = ±(W/2 ± 0.01) and
	y = D ± 0.01, each either required covered or required open. A single wall,
	three pieces (two jambs and a lintel) or thirty bricks pass alike if the
	union is right; a gap of W + 2, a blocked doorway or a missing outer wall
	does not.

	Every constant is READ from `MechanicsTuning.instance`; nothing below writes
	64, 16, 8 or 10 where a constant is meant. The only literals are the
	sampling step and probe offset, the tolerance, C-6's segment height, the
	sweep size, and the hand-built fixture, which says what it assumes.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local FacilityContract = require("./FacilityContract")
local Generator = require("../../src/server/facility/Generator")
local LayoutContract = require("./LayoutContract")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PlacementContract = require("./PlacementContract")
local Raise = require("./Contract")

local BlockoutContract = {}

export type Vec3 = { x: number, y: number, z: number }
export type PartSpec = { name: string, kind: string, cframe: Vec3, size: Vec3 }
export type Box = { min: Vec3, max: Vec3 }
export type Layout = LayoutContract.Layout
export type Machine = PlacementContract.Machine
export type Facility = FacilityContract.Facility
export type Tuning = typeof(MechanicsTuning)
export type Builder = (facility: Facility, tuning: Tuning) -> { PartSpec }
export type Swept = { seed: number, n: number, facility: Facility }

-- The shipped tuning. Every check reads `instance.room_pitch_studs`,
-- `room_ceiling_studs`, `doorway_width_studs`, `doorway_height_studs`,
-- `layout_grid_columns` and `layout_grid_rows` from here.
BlockoutContract.TUNING = MechanicsTuning

-- C-8: seeds 1..SWEEP_SEEDS at each n in CLASS_COUNTS, through the REAL
-- `Generator.generate` over `FacilityContract.ringFor(seed, n)`.
BlockoutContract.SWEEP_SEEDS = 200
-- Measured in RED: generating the 200 facilities takes about 0.06 s per n and
-- the whole controls file about 2.5 s at n = 4 alone, so C-8's "n = 5 and 6
-- if the run stays well inside the unit gate's budget" is comfortably met.
BlockoutContract.CLASS_COUNTS = { 4, 5, 6 }

-- C-5 / C-6: the one tolerance.
BlockoutContract.EPS = 1e-6
-- C-6: the segment's height, an avatar's chest, under `doorway_height_studs`.
BlockoutContract.SEGMENT_Y = 3
-- AC-1's sampling: a point every SAMPLE_STEP studs along and up each edge,
-- plus exact probes PROBE studs either side of every doorway boundary.
BlockoutContract.SAMPLE_STEP = 2
BlockoutContract.PROBE = 0.01

-- C-1's four kinds, and which of them are solid (C-4: anchors are not).
BlockoutContract.KINDS = { "floor", "ceiling", "wall", "machine" }
BlockoutContract.SOLID = { floor = true, ceiling = true, wall = true }

local EPS = BlockoutContract.EPS

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= EPS
end

local function fmt(v: number): string
	if v == math.floor(v) then
		return tostring(v)
	end
	return string.format("%.3f", v)
end

local function vec(v: Vec3): string
	return `({fmt(v.x)}, {fmt(v.y)}, {fmt(v.z)})`
end

--[[ ------------------------------------------------------------------------
     Geometry predicates, C-5 and C-6, over axis-aligned boxes.
     --------------------------------------------------------------------- ]]

function BlockoutContract.boxOf(spec: PartSpec): Box
	local c, s = spec.cframe, spec.size
	return {
		min = { x = c.x - s.x / 2, y = c.y - s.y / 2, z = c.z - s.z / 2 },
		max = { x = c.x + s.x / 2, y = c.y + s.y / 2, z = c.z + s.z / 2 },
	}
end

function BlockoutContract.boxFrom(min: Vec3, max: Vec3): Box
	return { min = min, max = max }
end

-- The intersection's extents on x, y, z when the two boxes OVERLAP - every
-- extent > EPS - and nil otherwise. Touching faces are not an overlap (C-5).
function BlockoutContract.overlap(a: Box, b: Box): Vec3?
	local ix = math.min(a.max.x, b.max.x) - math.max(a.min.x, b.min.x)
	local iy = math.min(a.max.y, b.max.y) - math.max(a.min.y, b.min.y)
	local iz = math.min(a.max.z, b.max.z) - math.max(a.min.z, b.min.z)
	if ix > EPS and iy > EPS and iz > EPS then
		return { x = ix, y = iy, z = iz }
	end
	return nil
end

-- C-5: an overlap is allowed iff its x and z extents are both ≤ T (+ EPS).
function BlockoutContract.overlapAllowed(extents: Vec3, T: number): boolean
	return extents.x <= T + EPS and extents.z <= T + EPS
end

-- `inner` lies within `outer` on every axis, to EPS.
function BlockoutContract.contains(outer: Box, inner: Box): boolean
	return inner.min.x >= outer.min.x - EPS
		and inner.max.x <= outer.max.x + EPS
		and inner.min.y >= outer.min.y - EPS
		and inner.max.y <= outer.max.y + EPS
		and inner.min.z >= outer.min.z - EPS
		and inner.max.z <= outer.max.z + EPS
end

-- The point lies in the CLOSED box, to EPS. AC-1's coverage test: a point on
-- the grid-line plane is inside a wall centred on that line.
function BlockoutContract.containsPoint(box: Box, x: number, y: number, z: number): boolean
	return x >= box.min.x - EPS
		and x <= box.max.x + EPS
		and y >= box.min.y - EPS
		and y <= box.max.y + EPS
		and z >= box.min.z - EPS
		and z <= box.max.z + EPS
end

--[[
	C-6: the segment a→b CROSSES the box when it meets the box's INTERIOR -
	the open box shrunk by EPS on every face. A slab test: the parameter
	interval on which p(t) = a + t(b − a) is strictly inside each axis's open
	slab, intersected over the three axes and with [0, 1]; non-empty means a
	crossing. A segment that grazes a face, runs along a face, or ends exactly
	on a face does not cross.
]]
function BlockoutContract.segmentCrosses(a: Vec3, b: Vec3, box: Box): boolean
	local t0, t1 = 0, 1
	for _, axis in { "x", "y", "z" } do
		local pa = (a :: any)[axis] :: number
		local pb = (b :: any)[axis] :: number
		local lo = (box.min :: any)[axis] + EPS
		local hi = (box.max :: any)[axis] - EPS
		if lo >= hi then
			return false
		end
		local d = pb - pa
		if math.abs(d) < EPS then
			if pa <= lo or pa >= hi then
				return false
			end
		else
			local ta, tb = (lo - pa) / d, (hi - pa) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			t0 = math.max(t0, ta)
			t1 = math.min(t1, tb)
			if t0 >= t1 then
				return false
			end
		end
	end
	return t0 < t1
end

--[[ ------------------------------------------------------------------------
     The layout's geometry, by hand: room centres (C-1's roomCentre formula),
     occupied cells, and every grid edge of an occupied cell classified as
     outer, doored or doorless (C-3).
     --------------------------------------------------------------------- ]]

function BlockoutContract.roomCentre(room: LayoutContract.Room, tuning: Tuning): Vec3
	local P = tuning.instance.room_pitch_studs
	return { x = (room.column - 1) * P, y = 0, z = (room.row - 1) * P }
end

export type Edge = {
	key: string,
	axis: "x" | "z", -- the THIN axis: the wall's plane is `axis = plane`
	plane: number, -- the grid-line coordinate on the thin axis
	mid: number, -- the edge midpoint on the along axis (the other one)
	rooms: { number }, -- one id for an outer edge, two for a shared edge
	kind: "outer" | "door" | "solid", -- solid: shared, no door
}

local function cellKey(column: number, row: number): string
	return `{column},{row}`
end

local function doorKey(a: number, b: number): string
	return if a < b then `{a}-{b}` else `{b}-{a}`
end

function BlockoutContract.edgesOf(layout: Layout, tuning: Tuning): { Edge }
	local P = tuning.instance.room_pitch_studs
	local byCell: { [string]: LayoutContract.Room } = {}
	for _, room in layout.rooms do
		byCell[cellKey(room.column, room.row)] = room
	end
	local doors: { [string]: boolean } = {}
	for _, d in layout.doors do
		doors[doorKey(d.a, d.b)] = true
	end
	local seen: { [string]: boolean } = {}
	local edges: { Edge } = {}
	-- Each side as (dc, dr): the neighbour cell offset.
	local sides = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for _, room in layout.rooms do
		local cx, cz = (room.column - 1) * P, (room.row - 1) * P
		for _, side in sides do
			local dc, dr = side[1], side[2]
			local neighbour = byCell[cellKey(room.column + dc, room.row + dr)]
			local axis: "x" | "z" = if dc ~= 0 then "x" else "z"
			local plane = if dc ~= 0 then cx + dc * P / 2 else cz + dr * P / 2
			local mid = if dc ~= 0 then cz else cx
			local key = `{axis}@{plane}|{mid}`
			if seen[key] then
				continue
			end
			seen[key] = true
			local edge: Edge = {
				key = key,
				axis = axis,
				plane = plane,
				mid = mid,
				rooms = { room.id },
				kind = "outer",
			}
			if neighbour ~= nil then
				edge.rooms = { math.min(room.id, neighbour.id), math.max(room.id, neighbour.id) }
				edge.kind = if doors[doorKey(room.id, neighbour.id)] then "door" else "solid"
			end
			table.insert(edges, edge)
		end
	end
	table.sort(edges, function(p: Edge, q: Edge): boolean
		return p.key < q.key
	end)
	return edges
end

function BlockoutContract.describeEdge(edge: Edge): string
	local where = `{edge.axis} = {fmt(edge.plane)}, along {fmt(edge.mid)} ± P/2`
	if edge.kind == "outer" then
		return `outer edge of room {edge.rooms[1]} ({where})`
	elseif edge.kind == "door" then
		return `doored edge between rooms {edge.rooms[1]} and {edge.rooms[2]} ({where})`
	end
	return `doorless edge between rooms {edge.rooms[1]} and {edge.rooms[2]} ({where})`
end

-- World coordinates of the point `u` along the edge from its midpoint, at
-- height `y`, on the grid-line plane.
function BlockoutContract.pointOn(edge: Edge, u: number, y: number): Vec3
	if edge.axis == "x" then
		return { x = edge.plane, y = y, z = edge.mid + u }
	end
	return { x = edge.mid + u, y = y, z = edge.plane }
end

--[[ ------------------------------------------------------------------------
     Specs: shape (C-1) and classification.
     --------------------------------------------------------------------- ]]

local function sortedKeys(value: any): { string }
	local keys: { string } = {}
	if typeof(value) == "table" then
		for key in pairs(value :: { [any]: any }) do
			table.insert(keys, tostring(key))
		end
	end
	table.sort(keys)
	return keys
end

BlockoutContract.sortedKeys = sortedKeys

local KIND_SET: { [string]: boolean } = {}
for _, kind in BlockoutContract.KINDS do
	KIND_SET[kind] = true
end

-- C-1: every spec is exactly { name, kind, cframe, size }, kind one of the
-- four, cframe and size exactly { x, y, z } numbers, every extent > 0.
function BlockoutContract.shapeProblems(specs: any): { string }
	local out: { string } = {}
	if typeof(specs) ~= "table" then
		return { `C-1: parts returned {typeof(specs)}, expected a list of specs` }
	end
	if #specs == 0 then
		table.insert(out, "C-1: parts returned an empty list")
	end
	for i, spec in ipairs(specs :: { any }) do
		local keys = sortedKeys(spec)
		if not Deep.equal(keys, { "cframe", "kind", "name", "size" }) then
			table.insert(
				out,
				`C-1: specs[{i}] carries {Deep.show(keys)}, expected exactly cframe, kind, name, size`
			)
			continue
		end
		if typeof(spec.name) ~= "string" then
			table.insert(out, `C-1: specs[{i}].name is {typeof(spec.name)}, expected a string`)
		end
		if not KIND_SET[spec.kind] then
			table.insert(
				out,
				`C-1: specs[{i}] ({tostring(spec.name)}).kind is {Deep.show(spec.kind)}, expected one of floor, ceiling, wall, machine`
			)
		end
		for _, field in { "cframe", "size" } do
			local v = spec[field]
			if not Deep.equal(sortedKeys(v), { "x", "y", "z" }) then
				table.insert(
					out,
					`C-1: specs[{i}] ({tostring(spec.name)}).{field} is {Deep.show(v)}, expected exactly x, y, z`
				)
			else
				for _, axis in { "x", "y", "z" } do
					if typeof(v[axis]) ~= "number" then
						table.insert(
							out,
							`C-1: specs[{i}] ({tostring(spec.name)}).{field}.{axis} is {typeof(
								v[axis]
							)}`
						)
					elseif field == "size" and not (v[axis] > 0) then
						table.insert(
							out,
							`C-1: specs[{i}] ({tostring(spec.name)}).size.{axis} is {tostring(
								v[axis]
							)}, expected > 0`
						)
					end
				end
			end
		end
		if #out > 12 then
			break
		end
	end
	return out
end

function BlockoutContract.ofKind(specs: { PartSpec }, kind: string): { PartSpec }
	local out: { PartSpec } = {}
	for _, spec in specs do
		if spec.kind == kind then
			table.insert(out, spec)
		end
	end
	return out
end

function BlockoutContract.solids(specs: { PartSpec }): { PartSpec }
	local out: { PartSpec } = {}
	for _, spec in specs do
		if BlockoutContract.SOLID[spec.kind] then
			table.insert(out, spec)
		end
	end
	return out
end

--[[ ------------------------------------------------------------------------
     AC-1: floors, ceilings and wall coverage.
     --------------------------------------------------------------------- ]]

-- C-2: for each room, exactly one floor and one ceiling centred on its cell,
-- sized (P, T, P), the floor's top face at y = 0 and the ceiling's bottom
-- face at y = H.
function BlockoutContract.slabViolations(
	specs: { PartSpec },
	layout: Layout,
	tuning: Tuning,
	T: number
): { string }
	local out: { string } = {}
	local P, H = tuning.instance.room_pitch_studs, tuning.instance.room_ceiling_studs
	for _, kind in { "floor", "ceiling" } do
		local all = BlockoutContract.ofKind(specs, kind)
		local face = if kind == "floor" then "top" else "bottom"
		local wantFace = if kind == "floor" then 0 else H
		local wantCentreY = if kind == "floor" then -T / 2 else H + T / 2
		for _, room in layout.rooms do
			local c = BlockoutContract.roomCentre(room, tuning)
			local mine: { PartSpec } = {}
			for _, spec in all do
				if near(spec.cframe.x, c.x) and near(spec.cframe.z, c.z) then
					table.insert(mine, spec)
				end
			end
			if #mine ~= 1 then
				table.insert(
					out,
					`AC-1: room {room.id} has {#mine} {kind} spec(s) centred on its cell {vec(c)}, expected exactly one`
				)
				continue
			end
			local spec = mine[1]
			if not (near(spec.size.x, P) and near(spec.size.y, T) and near(spec.size.z, P)) then
				table.insert(
					out,
					`AC-1: room {room.id}'s {kind} {spec.name} is sized {vec(spec.size)}, expected (room_pitch_studs {P}, T {T}, room_pitch_studs {P})`
				)
			end
			local box = BlockoutContract.boxOf(spec)
			local gotFace = if kind == "floor" then box.max.y else box.min.y
			if not near(gotFace, wantFace) then
				table.insert(
					out,
					`AC-1: room {room.id}'s {kind} {spec.name} has its {face} face at y = {fmt(
						gotFace
					)} (centre y = {fmt(spec.cframe.y)}), expected y = {wantFace}{if kind
							== "ceiling"
						then " = room_ceiling_studs"
						else ""} (centre y = {fmt(wantCentreY)})`
				)
			end
		end
	end
	return out
end

-- The grid line a wall is centred on, if it is a T-thick slab centred on
-- one: the thin axis, its plane, and the along-axis of the wall. Nil when the
-- spec is not such a slab.
local function wallLine(spec: PartSpec, T: number, P: number): ("x" | "z")?
	for _, axis in { "x", "z" } do
		local size = (spec.size :: any)[axis] :: number
		local centre = (spec.cframe :: any)[axis] :: number
		if near(size, T) then
			local q = centre / (P / 2)
			local k = math.floor(q + 0.5)
			if near(q, k) and k % 2 ~= 0 then
				return axis :: "x" | "z"
			end
		end
	end
	return nil
end

export type WallIndex = {
	byLine: { [string]: { Box } }, -- `axis@plane` -> wall boxes on that line
	count: number,
}

-- C-3's per-spec structure: every wall is a T-thick slab centred on a grid
-- line, spans y within [0, H], lies within one cell edge along the line, and
-- is named `Wall…`. Returns the index for the coverage test and the problems.
function BlockoutContract.indexWalls(
	specs: { PartSpec },
	tuning: Tuning,
	T: number
): (WallIndex, { string })
	local out: { string } = {}
	local P, H = tuning.instance.room_pitch_studs, tuning.instance.room_ceiling_studs
	local index: WallIndex = { byLine = {}, count = 0 }
	for _, spec in BlockoutContract.ofKind(specs, "wall") do
		index.count += 1
		if string.sub(spec.name, 1, 4) ~= "Wall" then
			table.insert(out, `AC-1: wall spec "{spec.name}" is not named Wall… (C-3)`)
		end
		local axis = wallLine(spec, T, P)
		if axis == nil then
			table.insert(
				out,
				`AC-1: wall {spec.name} at {vec(spec.cframe)} sized {vec(spec.size)} is not a slab of thickness T = {T} centred on a grid line (an odd multiple of room_pitch_studs / 2 = {P / 2})`
			)
			continue
		end
		local box = BlockoutContract.boxOf(spec)
		if box.min.y < -EPS or box.max.y > H + EPS then
			table.insert(
				out,
				`AC-1: wall {spec.name} spans y ∈ [{fmt(box.min.y)}, {fmt(box.max.y)}], outside [0, room_ceiling_studs {H}]`
			)
		end
		local along: "x" | "z" = if axis == "x" then "z" else "x"
		local a = (spec.cframe :: any)[along] :: number
		local mid = math.floor(a / P + 0.5) * P
		local lo, hi = (box.min :: any)[along] :: number, (box.max :: any)[along] :: number
		if lo < mid - P / 2 - EPS or hi > mid + P / 2 + EPS then
			table.insert(
				out,
				`AC-1: wall {spec.name} runs {along} ∈ [{fmt(lo)}, {fmt(hi)}], past the cell edge [{fmt(
					mid - P / 2
				)}, {fmt(mid + P / 2)}] (C-3: no extension past the vertex)`
			)
		end
		local plane = (spec.cframe :: any)[axis] :: number
		local key = `{axis}@{plane}`
		index.byLine[key] = index.byLine[key] or {}
		table.insert(index.byLine[key], box)
	end
	return index, out
end

local function covered(index: WallIndex, edge: Edge, u: number, y: number): boolean
	local boxes = index.byLine[`{edge.axis}@{edge.plane}`]
	if boxes == nil then
		return false
	end
	local p = BlockoutContract.pointOn(edge, u, y)
	for _, box in boxes do
		if BlockoutContract.containsPoint(box, p.x, p.y, p.z) then
			return true
		end
	end
	return false
end

export type Sample = { u: number, y: number }

-- The points AC-1 tests on every edge: a lattice every SAMPLE_STEP studs,
-- plus exact probes a hair either side of the doorway's edges and top, of
-- the edge's ends and of the floor and ceiling.
function BlockoutContract.samples(tuning: Tuning): { Sample }
	local t = tuning.instance
	local P, H, W, D =
		t.room_pitch_studs, t.room_ceiling_studs, t.doorway_width_studs, t.doorway_height_studs
	local step, pr = BlockoutContract.SAMPLE_STEP, BlockoutContract.PROBE
	local out: { Sample } = {}
	local u = -P / 2 + step / 2
	while u < P / 2 do
		local y = step / 2
		while y < H do
			table.insert(out, { u = u, y = y })
			y += step
		end
		u += step
	end
	local function add(us: { number }, ys: { number })
		for _, uu in us do
			for _, yy in ys do
				table.insert(out, { u = uu, y = yy })
			end
		end
	end
	add({ -(W / 2 + pr), -(W / 2 - pr), W / 2 - pr, W / 2 + pr }, { pr, D / 2, D - pr, D + pr })
	add({ 0 }, { pr, D - pr, D + pr, H - pr })
	add({ -(P / 2 - pr), P / 2 - pr }, { pr, H / 2, H - pr })
	return out
end

-- C-3: on a doored edge the doorway |u| < W/2, 0 ≤ y < D is open; every
-- other point of every edge is wall.
function BlockoutContract.mustBeOpen(edge: Edge, s: Sample, tuning: Tuning): boolean
	local W, D = tuning.instance.doorway_width_studs, tuning.instance.doorway_height_studs
	return edge.kind == "door" and math.abs(s.u) < W / 2 and s.y < D
end

export type CoverageStats = {
	edges: number,
	outer: number,
	door: number,
	solid: number,
	points: number,
	wrongOpen: number, -- points that must be wall and are open
	wrongWall: number, -- points that must be open and are wall
}

-- AC-1's wall half over one facility: every edge's coverage, as problems and
-- counts. Violations are accumulated; the caller asserts once.
function BlockoutContract.coverage(
	specs: { PartSpec },
	layout: Layout,
	tuning: Tuning,
	T: number
): ({ string }, CoverageStats)
	local index, out = BlockoutContract.indexWalls(specs, tuning, T)
	local t = tuning.instance
	local W, D = t.doorway_width_studs, t.doorway_height_studs
	local stats: CoverageStats =
		{ edges = 0, outer = 0, door = 0, solid = 0, points = 0, wrongOpen = 0, wrongWall = 0 }
	local samples = BlockoutContract.samples(tuning)
	for _, edge in BlockoutContract.edgesOf(layout, tuning) do
		stats.edges += 1
		if edge.kind == "outer" then
			stats.outer += 1
		elseif edge.kind == "door" then
			stats.door += 1
		else
			stats.solid += 1
		end
		local firstOpen: Sample? = nil
		local firstWall: Sample? = nil
		for _, s in samples do
			stats.points += 1
			local open = BlockoutContract.mustBeOpen(edge, s, tuning)
			local isCovered = covered(index, edge, s.u, s.y)
			if open and isCovered then
				stats.wrongWall += 1
				firstWall = firstWall or s
			elseif not open and not isCovered then
				stats.wrongOpen += 1
				firstOpen = firstOpen or s
			end
		end
		if firstWall ~= nil then
			local s = firstWall :: Sample
			table.insert(
				out,
				`AC-1: the doorway in the {BlockoutContract.describeEdge(edge)} is blocked: a door joins them, so |u| < doorway_width_studs / 2 = {W / 2}, y < doorway_height_studs = {D} must be open, but a wall covers u = {fmt(
					s.u
				)}, y = {fmt(s.y)} ({vec(BlockoutContract.pointOn(edge, s.u, s.y))})`
			)
		end
		if firstOpen ~= nil then
			local s = firstOpen :: Sample
			local p = BlockoutContract.pointOn(edge, s.u, s.y)
			if edge.kind == "door" then
				table.insert(
					out,
					`AC-1: the gap in the {BlockoutContract.describeEdge(edge)} is not exactly the doorway: no wall at u = {fmt(
						s.u
					)}, y = {fmt(s.y)} ({vec(p)}), which lies outside |u| < {W / 2}, y < {D} (doorway_width_studs {W} × doorway_height_studs {D})`
				)
			elseif edge.kind == "solid" then
				table.insert(
					out,
					`AC-1: the {BlockoutContract.describeEdge(edge)} has no door, so it must be solid wall, but no wall covers u = {fmt(
						s.u
					)}, y = {fmt(s.y)} ({vec(p)}) - a gap on an edge no door joins`
				)
			else
				table.insert(
					out,
					`AC-1: the {BlockoutContract.describeEdge(edge)} must be solid wall, but no wall covers u = {fmt(
						s.u
					)}, y = {fmt(s.y)} ({vec(p)})`
				)
			end
		end
	end
	return out, stats
end

function BlockoutContract.describeCoverage(stats: CoverageStats): string
	return `{stats.edges} edges ({stats.outer} outer, {stats.door} doored, {stats.solid} doorless), {stats.points} points: {stats.wrongOpen} open where wall is required, {stats.wrongWall} wall where open is required`
end

-- The total OPEN length along an edge at height `y`, in studs: the edge's
-- span minus the union of the along-axis ranges of walls on its line whose
-- y-range covers `y`. A measurement for the controls: a correct doored edge
-- reads doorway_width_studs below D and 0 above it.
function BlockoutContract.openLengthAt(
	specs: { PartSpec },
	edge: Edge,
	y: number,
	tuning: Tuning,
	T: number
): number
	local P = tuning.instance.room_pitch_studs
	local index = BlockoutContract.indexWalls(specs, tuning, T)
	local boxes = index.byLine[`{edge.axis}@{edge.plane}`] or {}
	local along: "x" | "z" = if edge.axis == "x" then "z" else "x"
	local lo, hi = edge.mid - P / 2, edge.mid + P / 2
	local ranges: { { number } } = {}
	for _, box in boxes do
		if y >= box.min.y - EPS and y <= box.max.y + EPS then
			local a = math.max(lo, (box.min :: any)[along] :: number)
			local b = math.min(hi, (box.max :: any)[along] :: number)
			if b > a then
				table.insert(ranges, { a, b })
			end
		end
	end
	table.sort(ranges, function(p: { number }, q: { number }): boolean
		return p[1] < q[1]
	end)
	local coveredLength, cursor = 0, lo
	for _, r in ranges do
		local a, b = math.max(r[1], cursor), r[2]
		if b > a then
			coveredLength += b - a
			cursor = b
		end
	end
	return (hi - lo) - coveredLength
end

function BlockoutContract.edgeOfKind(layout: Layout, tuning: Tuning, kind: string): Edge
	for _, edge in BlockoutContract.edgesOf(layout, tuning) do
		if edge.kind == kind then
			return edge
		end
	end
	error(`the layout has no {kind} edge`)
end

function BlockoutContract.edgeBetween(layout: Layout, tuning: Tuning, a: number, b: number): Edge
	for _, edge in BlockoutContract.edgesOf(layout, tuning) do
		if
			#edge.rooms == 2
			and edge.rooms[1] == math.min(a, b)
			and edge.rooms[2] == math.max(a, b)
		then
			return edge
		end
	end
	error(`rooms {a} and {b} share no edge`)
end

-- AC-1 as one assertion over one facility's specs.
function BlockoutContract.assertGeometry(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	T: number,
	label: string?
): CoverageStats
	local problems = BlockoutContract.slabViolations(specs, facility.layout, tuning, T)
	local walls, stats = BlockoutContract.coverage(specs, facility.layout, tuning, T)
	for _, p in walls do
		table.insert(problems, p)
	end
	if #problems > 0 then
		Raise.fail(
			`AC-1: {label or "the facility"}'s blockout is not the layout's geometry ({BlockoutContract.describeCoverage(
				stats
			)}):\n{Raise.firstFew(problems, 8)}`
		)
	end
	return stats
end

--[[ ------------------------------------------------------------------------
     AC-2: machine anchors (C-4).
     --------------------------------------------------------------------- ]]

function BlockoutContract.anchorViolations(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	anchorSize: Vec3
): { string }
	local out: { string } = {}
	local anchors = BlockoutContract.ofKind(specs, "machine")
	local machines = facility.placement.machines
	if #anchors ~= #machines then
		table.insert(
			out,
			`AC-2: {#anchors} machine anchor spec(s) for {#machines} machines, expected one each`
		)
	end
	for _, m in machines do
		local want = PlacementContract.expectedPosition(facility.layout, m.room, m.slot, tuning)
		local mine: { PartSpec } = {}
		for _, spec in anchors do
			if spec.name == tostring(m.id) then
				table.insert(mine, spec)
			end
		end
		if #mine ~= 1 then
			local names: { string } = {}
			for _, spec in anchors do
				table.insert(names, spec.name)
			end
			table.sort(names)
			table.insert(
				out,
				`AC-2: machine {m.id} has {#mine} anchor spec(s) named "{m.id}" (anchor names: {table.concat(
					names,
					", "
				)}); the anchor carries the machine's id as its name`
			)
			continue
		end
		local spec = mine[1]
		if not (near(spec.cframe.x, want.x) and near(spec.cframe.z, want.z)) then
			table.insert(
				out,
				`AC-2: machine {m.id}'s anchor is at x = {fmt(spec.cframe.x)}, z = {fmt(
					spec.cframe.z
				)}; positionOf (room {m.room} slot {m.slot}) gives x = {fmt(want.x)}, z = {fmt(
					want.z
				)}`
			)
		end
		if not near(spec.cframe.y, anchorSize.y / 2) then
			table.insert(
				out,
				`AC-2: machine {m.id}'s anchor is centred at y = {fmt(spec.cframe.y)}, expected ANCHOR_SIZE.y / 2 = {anchorSize.y / 2}`
			)
		end
		if
			not (
				near(spec.size.x, anchorSize.x)
				and near(spec.size.y, anchorSize.y)
				and near(spec.size.z, anchorSize.z)
			)
		then
			table.insert(
				out,
				`AC-2: machine {m.id}'s anchor is sized {vec(spec.size)}, expected ANCHOR_SIZE {vec(
					anchorSize
				)}`
			)
		end
	end
	return out
end

-- The greatest horizontal distance between any anchor and its machine's
-- positionOf, for the controls' table (0 when every anchor is placed).
function BlockoutContract.anchorDrift(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning
): number
	local worst = 0
	for _, m in facility.placement.machines do
		local want = PlacementContract.expectedPosition(facility.layout, m.room, m.slot, tuning)
		for _, spec in BlockoutContract.ofKind(specs, "machine") do
			if spec.name == tostring(m.id) then
				local dx, dz = spec.cframe.x - want.x, spec.cframe.z - want.z
				worst = math.max(worst, math.sqrt(dx * dx + dz * dz))
			end
		end
	end
	return worst
end

function BlockoutContract.assertAnchors(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	anchorSize: Vec3,
	label: string?
)
	local problems = BlockoutContract.anchorViolations(specs, facility, tuning, anchorSize)
	if #problems > 0 then
		Raise.fail(
			`AC-2: {label or "the facility"}'s machine anchors are not at positionOf under the machine's id:\n{Raise.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3: solids (C-5).
     --------------------------------------------------------------------- ]]

export type SolidStats = {
	solids: number,
	pairs: number,
	overlapping: number, -- pairs that overlap at all
	disallowed: number, -- of those, not a corner column
	worst: Vec3?, -- the disallowed overlap with the largest max(x, z) extent
	outside: number,
}

function BlockoutContract.solidViolations(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	T: number
): ({ string }, SolidStats)
	local out: { string } = {}
	local P = tuning.instance.room_pitch_studs
	local solids = BlockoutContract.solids(specs)
	local boxes: { Box } = {}
	for i, spec in solids do
		boxes[i] = BlockoutContract.boxOf(spec)
	end
	local stats: SolidStats =
		{ solids = #solids, pairs = 0, overlapping = 0, disallowed = 0, worst = nil, outside = 0 }
	local worstExtent = -1
	for i = 1, #solids do
		for j = i + 1, #solids do
			stats.pairs += 1
			local extents = BlockoutContract.overlap(boxes[i], boxes[j])
			if extents ~= nil then
				stats.overlapping += 1
				if not BlockoutContract.overlapAllowed(extents, T) then
					stats.disallowed += 1
					local e = math.max(extents.x, extents.z)
					if e > worstExtent then
						worstExtent, stats.worst = e, extents
					end
					if stats.disallowed <= 6 then
						table.insert(
							out,
							`AC-3: {solids[i].name} ({solids[i].kind}) and {solids[j].name} ({solids[j].kind}) overlap by {vec(
								extents
							)} (x × y × z); only a corner column with x and z extents ≤ T = {T} is allowed`
						)
					end
				end
			end
		end
	end
	-- Footprint: each occupied cell's square grown by T/2 on x and z, any y.
	local cells: { Box } = {}
	for _, room in facility.layout.rooms do
		local c = BlockoutContract.roomCentre(room, tuning)
		table.insert(cells, {
			min = { x = c.x - P / 2 - T / 2, y = -math.huge, z = c.z - P / 2 - T / 2 },
			max = { x = c.x + P / 2 + T / 2, y = math.huge, z = c.z + P / 2 + T / 2 },
		})
	end
	for i, spec in solids do
		local inside = false
		for _, cell in cells do
			if BlockoutContract.contains(cell, boxes[i]) then
				inside = true
				break
			end
		end
		if not inside then
			stats.outside += 1
			if stats.outside <= 6 then
				table.insert(
					out,
					`AC-3: {spec.name} ({spec.kind}) at {vec(spec.cframe)} sized {vec(spec.size)} lies outside the occupied cells' footprint: its box is contained in no single occupied cell grown by T / 2 = {T / 2} on x and z`
				)
			end
		end
	end
	return out, stats
end

function BlockoutContract.describeSolids(stats: SolidStats): string
	return `{stats.solids} solids, {stats.pairs} pairs, {stats.overlapping} overlapping, {stats.disallowed} disallowed (worst {if stats.worst
		then vec(stats.worst :: Vec3)
		else "none"}), {stats.outside} outside the footprint`
end

function BlockoutContract.assertSolids(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	T: number,
	label: string?
): SolidStats
	local problems, stats = BlockoutContract.solidViolations(specs, facility, tuning, T)
	if #problems > 0 then
		Raise.fail(
			`AC-3: {label or "the facility"}'s solids overlap or leave the footprint ({BlockoutContract.describeSolids(
				stats
			)}):\n{Raise.firstFew(problems, 8)}`
		)
	end
	return stats
end

--[[ ------------------------------------------------------------------------
     AC-4: line of sight between machines (C-6).
     --------------------------------------------------------------------- ]]

export type SightStats = {
	sameRoomPairs: number,
	sameRoomCrossing: number, -- must be 0
	noDoorPairs: number,
	noDoorClear: number, -- must be 0
}

-- Which wall specs the y = 3 segment between two machines crosses.
function BlockoutContract.wallsCrossed(
	specs: { PartSpec },
	facility: Facility,
	a: Machine,
	b: Machine,
	tuning: Tuning
): { PartSpec }
	local pa = PlacementContract.expectedPosition(facility.layout, a.room, a.slot, tuning)
	local pb = PlacementContract.expectedPosition(facility.layout, b.room, b.slot, tuning)
	local y = BlockoutContract.SEGMENT_Y
	local from: Vec3 = { x = pa.x, y = y, z = pa.z }
	local to: Vec3 = { x = pb.x, y = y, z = pb.z }
	local crossed: { PartSpec } = {}
	for _, spec in BlockoutContract.ofKind(specs, "wall") do
		if BlockoutContract.segmentCrosses(from, to, BlockoutContract.boxOf(spec)) then
			table.insert(crossed, spec)
		end
	end
	return crossed
end

-- Every pair of machines in one room, and every pair in adjacent rooms with
-- no door between them.
function BlockoutContract.sightPairs(facility: Facility): ({ { Machine } }, { { Machine } })
	local byRoom: { [number]: LayoutContract.Room } = {}
	for _, room in facility.layout.rooms do
		byRoom[room.id] = room
	end
	local doors: { [string]: boolean } = {}
	for _, d in facility.layout.doors do
		doors[doorKey(d.a, d.b)] = true
	end
	local same: { { Machine } } = {}
	local noDoor: { { Machine } } = {}
	local machines = facility.placement.machines
	for i = 1, #machines do
		for j = i + 1, #machines do
			local a, b = machines[i], machines[j]
			if a.room == b.room then
				table.insert(same, { a, b })
			else
				local ra, rb = byRoom[a.room], byRoom[b.room]
				if
					ra ~= nil
					and rb ~= nil
					and LayoutContract.gridAdjacent(ra, rb)
					and not doors[doorKey(a.room, b.room)]
				then
					table.insert(noDoor, { a, b })
				end
			end
		end
	end
	return same, noDoor
end

function BlockoutContract.sightViolations(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning
): ({ string }, SightStats)
	local out: { string } = {}
	local same, noDoor = BlockoutContract.sightPairs(facility)
	local stats: SightStats =
		{ sameRoomPairs = #same, sameRoomCrossing = 0, noDoorPairs = #noDoor, noDoorClear = 0 }
	local y = BlockoutContract.SEGMENT_Y
	for _, pair in same do
		local a, b = pair[1], pair[2]
		local crossed = BlockoutContract.wallsCrossed(specs, facility, a, b, tuning)
		if #crossed > 0 then
			stats.sameRoomCrossing += 1
			if stats.sameRoomCrossing <= 6 then
				table.insert(
					out,
					`AC-4: machines {a.id} (slot {a.slot}) and {b.id} (slot {b.slot}) are both in room {a.room}, yet the segment between them at y = {y} crosses wall {crossed[1].name}`
				)
			end
		end
	end
	for _, pair in noDoor do
		local a, b = pair[1], pair[2]
		local crossed = BlockoutContract.wallsCrossed(specs, facility, a, b, tuning)
		if #crossed == 0 then
			stats.noDoorClear += 1
			if stats.noDoorClear <= 6 then
				table.insert(
					out,
					`AC-4: machines {a.id} (room {a.room} slot {a.slot}) and {b.id} (room {b.room} slot {b.slot}) are in adjacent rooms with no door between them, yet the segment between them at y = {y} crosses no wall`
				)
			end
		end
	end
	return out, stats
end

function BlockoutContract.describeSight(stats: SightStats): string
	return `{stats.sameRoomPairs} same-room pairs ({stats.sameRoomCrossing} crossing a wall), {stats.noDoorPairs} doorless-adjacent pairs ({stats.noDoorClear} crossing none)`
end

function BlockoutContract.assertSight(
	specs: { PartSpec },
	facility: Facility,
	tuning: Tuning,
	label: string?
): SightStats
	local problems, stats = BlockoutContract.sightViolations(specs, facility, tuning)
	if #problems > 0 then
		Raise.fail(
			`AC-4: {label or "the facility"}'s walls do not give the line-of-sight port its geometric fact ({BlockoutContract.describeSight(
				stats
			)}):\n{Raise.firstFew(problems, 8)}`
		)
	end
	return stats
end

--[[ ------------------------------------------------------------------------
     The sweep (C-8): seeds 1..SWEEP_SEEDS at each n, the REAL Generator over
     the real ring. Memoised per n; facilities in the cache are shared, so no
     caller may mutate one.
     --------------------------------------------------------------------- ]]

local sweepCache: { [number]: { Swept } } = {}
local sweepSeconds: { [number]: number } = {}

function BlockoutContract.facilities(n: number): { Swept }
	local cached = sweepCache[n]
	if cached ~= nil then
		return cached
	end
	local started = os.clock()
	local out: { Swept } = {}
	for seed = 1, BlockoutContract.SWEEP_SEEDS do
		local result = Generator.generate(FacilityContract.ringFor(seed, n), seed, MechanicsTuning)
		assert(
			result.kind == "facility",
			`seed {seed} n = {n}: Generator.generate returned kind {tostring(result.kind)}; the sweep needs a facility`
		)
		out[seed] = { seed = seed, n = n, facility = (result :: any).facility }
	end
	sweepCache[n] = out
	sweepSeconds[n] = os.clock() - started
	return out
end

-- Wall-clock seconds the sweep at n took to generate, for the handoff.
function BlockoutContract.sweepSeconds(n: number): number
	BlockoutContract.facilities(n)
	return sweepSeconds[n]
end

-- Every facility of every n, labelled.
function BlockoutContract.allFacilities(): { Swept }
	local out: { Swept } = {}
	for _, n in BlockoutContract.CLASS_COUNTS do
		for _, s in BlockoutContract.facilities(n) do
			table.insert(out, s)
		end
	end
	return out
end

function BlockoutContract.labelOf(s: Swept): string
	return `n = {s.n} seed {s.seed}`
end

-- Run `check(specs, facility, label)` over every swept facility, collecting
-- the first failures, and raise once. `check` is one of the `assert*`
-- functions above, so the sweep failure quotes its message verbatim.
function BlockoutContract.overSweep(
	builder: Builder,
	check: (
		specs: { PartSpec },
		facility: Facility,
		label: string
	) -> ()
): number
	local problems: { string } = {}
	local count = 0
	for _, s in BlockoutContract.allFacilities() do
		count += 1
		local ok, err = pcall(function()
			check(builder(s.facility, MechanicsTuning), s.facility, BlockoutContract.labelOf(s))
		end)
		if not ok then
			table.insert(problems, tostring(err))
			if #problems >= 3 then
				break
			end
		end
	end
	if #problems > 0 then
		Raise.fail(
			`{#problems}{if #problems >= 3 then "+" else ""} of {count} swept facilities fail (first shown):\n{table.concat(
				problems,
				"\n---\n"
			)}`
		)
	end
	return count
end

--[[ ------------------------------------------------------------------------
     The hand-built fixture: a 2 × 2 block whose doors form a tree, so one
     adjacency - rooms 2 and 4 - has NO door (AC-1's control needs one that is
     guaranteed, not drawn).

         1 - 2
         |
         3 - 4          doors 1-2, 1-3, 3-4; rooms 2 and 4 abut without a door.

     Rooms are row-major on the 3 × 3 grid's top-left cells. Machines:
       1: room 1 slot 1 (−,−)   2: room 1 slot 4 (+,+)   - one room, a diagonal
       3: room 2 slot 3 (−,+)   4: room 3 slot 1 (−,−)
       5: room 4 slot 2 (+,−)
     Machines 3 and 5 straddle the doorless edge 2-4 on a diagonal whose
     midpoint is EXACTLY that edge's midpoint (room 2 centre (P, 0) + (−P/4,
     +P/4) and room 4 centre (P, P) + (+P/4, −P/4) average to (P, P/2)), so a
     builder that cuts a doorway into every shared edge lets that segment
     through the gap - AC-4's second clause catches what AC-1's might not.
     Machines 1 and 2 share room 1. The other fields of the facility are
     filler: `Blockout.parts` reads only the layout and the machines (C-1).
     --------------------------------------------------------------------- ]]

BlockoutContract.TREE_BLOCK = {
	nonDoorPair = { 2, 4 },
	diagonalMachines = { 3, 5 },
	sameRoomMachines = { 1, 2 },
	roomCount = 4,
}

function BlockoutContract.treeBlockFacility(): Facility
	local machines: { Machine } = {}
	for i, rs in { { 1, 1 }, { 1, 4 }, { 2, 3 }, { 3, 1 }, { 4, 2 } } do
		machines[i] = {
			id = i,
			room = rs[1],
			slot = rs[2],
			keyClass = (i - 1) % 4 + 1,
			tag = 1,
			requiredSetting = 1,
		}
	end
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 1, row = 2 },
				{ id = 4, column = 2, row = 2 },
			},
			doors = { { a = 1, b = 2 }, { a = 1, b = 3 }, { a = 3, b = 4 } },
			spawnRoom = 1,
		},
		placement = { machines = machines, stepsPerClass = { 1, 1, 1, 1 } },
		steps = { tracks = { { 1, 2 }, { 3, 4 } }, finale = { 2, 4 } },
		spawnRoom = 1,
		par = 0,
		attempt = 1,
	}
end

function BlockoutContract.machineById(facility: Facility, id: number): Machine
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	error(`no machine {id}`)
end

-- A deep snapshot, for the purity checks.
function BlockoutContract.snapshot(value: any): any
	return Deep.copy(value)
end

return BlockoutContract
