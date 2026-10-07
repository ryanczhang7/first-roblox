--!strict
--[[
	The wrong builders MAP-001's negative controls are aimed at, and the one
	reference every check must ACCEPT.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a builder that leaves a gap on
	every shared edge must fail on a layout with a non-door adjacency". The
	story's RED brief adds the rest: a gap of W + 2, an outer edge without its
	wall, a ceiling at the wrong height (AC-1); an anchor at the room centre and
	an anchor named `Machine7` (AC-2); one wall per room per side, so shared
	edges carry two coincident walls, and a spec in an unoccupied cell (AC-3);
	no walls on shared edges at all (AC-4).

	THE POSITIVE CONTROL is `reference`: one floor and one ceiling per room;
	per EDGE (deduplicated), one wall for an outer or doorless edge and two
	jambs plus a lintel for a doored one; one anchor per machine at the
	Contract's position formula. It exists so that each check is shown to
	ACCEPT a correct builder in RED: a check that rejects everything is
	indistinguishable from a broken one. Each wrong builder is the reference
	with EXACTLY ONE option changed, so a control that fires is attributable to
	that one thing - and the controls file holds each to the checks it SHOULD
	still pass.

	THE EDGE ENUMERATION HERE IS WRITTEN SEPARATELY from
	`BlockoutContract.edgesOf`, on purpose: a reference that reused the
	oracle's enumeration would agree with it whatever either said.

	WHAT THIS IS NOT: `src/server/facility/Blockout.luau`, or a sketch of one.
	It exports no types, has no `WALL_THICKNESS` or `ANCHOR_SIZE` of its own
	beyond the values C-1 fixes for the controls, and its decomposition of a
	doored edge is one of several C-3 allows. GREEN writes the module from the
	story's Contract against `tests/server/blockout_test.luau`; nothing here is
	to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `Layout`, `Machines`,
	`Generator`, `Ring` and `MechanicsTuning` are merged - so these controls are
	EXECUTED in RED, and `tests/server/blockout_controls_test.luau` records what
	each measured.
]]

local Contract = require("./BlockoutContract")
local PlacementContract = require("./PlacementContract")

type Vec3 = Contract.Vec3
type PartSpec = Contract.PartSpec
type Facility = Contract.Facility
type Tuning = Contract.Tuning

local BlockoutStubs = {}

-- C-1's engineering constants, as the controls read them. The real module's
-- own values are pinned by `blockout_test.luau`, not here.
BlockoutStubs.T = 1
BlockoutStubs.ANCHOR_SIZE = { x = 4, y = 6, z = 4 } :: Vec3

export type Options = {
	gapEverywhere: boolean?, -- every shared edge gets a doorway, door or not
	doorWidth: number?, -- the doorway's width instead of doorway_width_studs
	skipFirstOuterEdge: boolean?, -- room 1's first outer edge has no wall
	ceilingLow: boolean?, -- ceiling centre at H − T/2 (bottom face at H − T)
	anchorAtCentre: boolean?, -- anchors on the room centre, not positionOf
	anchorPrefix: string?, -- anchor name = prefix .. id
	wallsPerRoom: boolean?, -- walls emitted per room per side, no dedupe
	extraOutsideWall: boolean?, -- one extra wall on an unoccupied cell's edge
	noSharedWalls: boolean?, -- shared edges get no wall at all
}

type Side = { dc: number, dr: number }
local SIDES: { Side } =
	{ { dc = 1, dr = 0 }, { dc = -1, dr = 0 }, { dc = 0, dr = 1 }, { dc = 0, dr = -1 } }

local function spec(name: string, kind: string, cframe: Vec3, size: Vec3): PartSpec
	return { name = name, kind = kind, cframe = cframe, size = size }
end

-- A wall piece on the line `axis = plane`, running `[lo, hi]` along the other
-- axis and `[y0, y1]` up.
local function wallPiece(
	name: string,
	axis: string,
	plane: number,
	lo: number,
	hi: number,
	y0: number,
	y1: number,
	T: number
): PartSpec
	local along, thick = (lo + hi) / 2, hi - lo
	if axis == "x" then
		return spec(
			name,
			"wall",
			{ x = plane, y = (y0 + y1) / 2, z = along },
			{ x = T, y = y1 - y0, z = thick }
		)
	end
	return spec(
		name,
		"wall",
		{ x = along, y = (y0 + y1) / 2, z = plane },
		{ x = thick, y = y1 - y0, z = T }
	)
end

function BlockoutStubs.builderWith(options: Options): Contract.Builder
	return function(facility: Facility, tuning: Tuning): { PartSpec }
		local t = tuning.instance
		local P, H = t.room_pitch_studs, t.room_ceiling_studs
		local W, D = options.doorWidth or t.doorway_width_studs, t.doorway_height_studs
		local T = BlockoutStubs.T
		local layout = facility.layout
		local out: { PartSpec } = {}

		local byCell: { [string]: number } = {}
		for _, room in layout.rooms do
			byCell[`{room.column},{room.row}`] = room.id
		end
		local doored: { [string]: boolean } = {}
		for _, d in layout.doors do
			doored[`{math.min(d.a, d.b)}-{math.max(d.a, d.b)}`] = true
		end

		for _, room in layout.rooms do
			local cx, cz = (room.column - 1) * P, (room.row - 1) * P
			table.insert(
				out,
				spec(
					`Floor{room.id}`,
					"floor",
					{ x = cx, y = -T / 2, z = cz },
					{ x = P, y = T, z = P }
				)
			)
			local cy = if options.ceilingLow then H - T / 2 else H + T / 2
			table.insert(
				out,
				spec(
					`Ceiling{room.id}`,
					"ceiling",
					{ x = cx, y = cy, z = cz },
					{ x = P, y = T, z = P }
				)
			)
		end

		local emitted: { [string]: boolean } = {}
		local skipped = false
		for _, room in layout.rooms do
			local cx, cz = (room.column - 1) * P, (room.row - 1) * P
			for _, side in SIDES do
				local neighbour = byCell[`{room.column + side.dc},{room.row + side.dr}`]
				local axis = if side.dc ~= 0 then "x" else "z"
				local plane = if side.dc ~= 0 then cx + side.dc * P / 2 else cz + side.dr * P / 2
				local mid = if side.dc ~= 0 then cz else cx
				local key = `{axis}:{plane}:{mid}`
				if emitted[key] and not options.wallsPerRoom then
					continue
				end
				emitted[key] = true
				local shared = neighbour ~= nil
				if not shared and options.skipFirstOuterEdge and not skipped then
					skipped = true
					continue
				end
				if shared and options.noSharedWalls then
					continue
				end
				local hasDoor = shared
					and (
						options.gapEverywhere
						or doored[`{math.min(room.id, neighbour :: number)}-{math.max(
							room.id,
							neighbour :: number
						)}`]
					)
				local base =
					`Wall{room.id}{if shared then `-{neighbour}` else `-{axis}{side.dc + side.dr}`}`
				if hasDoor then
					table.insert(
						out,
						wallPiece(`{base}a`, axis, plane, mid - P / 2, mid - W / 2, 0, H, T)
					)
					table.insert(
						out,
						wallPiece(`{base}b`, axis, plane, mid + W / 2, mid + P / 2, 0, H, T)
					)
					table.insert(
						out,
						wallPiece(`{base}lintel`, axis, plane, mid - W / 2, mid + W / 2, D, H, T)
					)
				else
					table.insert(
						out,
						wallPiece(base, axis, plane, mid - P / 2, mid + P / 2, 0, H, T)
					)
				end
			end
		end

		if options.extraOutsideWall then
			-- An unoccupied cell with an unoccupied (or off-grid) neighbour: a
			-- wall on the edge between them touches nothing occupied.
			local placed = false
			for row = 1, t.layout_grid_rows do
				for column = 1, t.layout_grid_columns do
					if placed or byCell[`{column},{row}`] ~= nil then
						continue
					end
					for _, side in SIDES do
						if byCell[`{column + side.dc},{row + side.dr}`] == nil then
							local cx, cz = (column - 1) * P, (row - 1) * P
							local axis = if side.dc ~= 0 then "x" else "z"
							local plane = if side.dc ~= 0
								then cx + side.dc * P / 2
								else cz + side.dr * P / 2
							local mid = if side.dc ~= 0 then cz else cx
							table.insert(
								out,
								wallPiece(
									"WallStray",
									axis,
									plane,
									mid - P / 2,
									mid + P / 2,
									0,
									H,
									T
								)
							)
							placed = true
							break
						end
					end
				end
			end
			assert(
				placed,
				"no unoccupied cell with a free side; the outside control cannot be placed"
			)
		end

		local anchor = BlockoutStubs.ANCHOR_SIZE
		for _, m in facility.placement.machines do
			local position: Vec3
			if options.anchorAtCentre then
				local room = PlacementContract.roomById(layout, m.room)
				position = { x = (room.column - 1) * P, y = 0, z = (room.row - 1) * P }
			else
				position = PlacementContract.expectedPosition(layout, m.room, m.slot, tuning)
			end
			table.insert(
				out,
				spec(
					`{options.anchorPrefix or ""}{m.id}`,
					"machine",
					{ x = position.x, y = anchor.y / 2, z = position.z },
					{ x = anchor.x, y = anchor.y, z = anchor.z }
				)
			)
		end
		return out
	end
end

-- The positive control.
BlockoutStubs.reference = BlockoutStubs.builderWith({})

-- AC-1's controls.
BlockoutStubs.gapEveryEdge = BlockoutStubs.builderWith({ gapEverywhere = true })
BlockoutStubs.outerEdgeMissing = BlockoutStubs.builderWith({ skipFirstOuterEdge = true })
BlockoutStubs.ceilingLow = BlockoutStubs.builderWith({ ceilingLow = true })
-- The gap is W + 2 wide; built per tuning, so it reads W at call time.
BlockoutStubs.gapTooWide = function(facility: Facility, tuning: Tuning): { PartSpec }
	return BlockoutStubs.builderWith({ doorWidth = tuning.instance.doorway_width_studs + 2 })(
		facility,
		tuning
	)
end

-- AC-2's controls.
BlockoutStubs.anchorAtCentre = BlockoutStubs.builderWith({ anchorAtCentre = true })
BlockoutStubs.anchorNamedMachine = BlockoutStubs.builderWith({ anchorPrefix = "Machine" })

-- AC-3's controls.
BlockoutStubs.wallPerRoom = BlockoutStubs.builderWith({ wallsPerRoom = true })
BlockoutStubs.strayWall = BlockoutStubs.builderWith({ extraOutsideWall = true })

-- AC-4's control.
BlockoutStubs.noSharedWalls = BlockoutStubs.builderWith({ noSharedWalls = true })

return BlockoutStubs
