--!strict
--[[
	The facility as blockout geometry, per MAP-001 and `tuning.md` §2 ("The
	layout"): rooms `room_pitch_studs` apart on the grid, abutting, with no
	corridors; ceilings `room_ceiling_studs` high; doorways
	`doorway_width_studs` x `doorway_height_studs`, centred in the shared wall;
	machines at the quadrant slots. The walls are what the line-of-sight port
	raycasts against (`architecture.md` §9.6), so this is game rules, not only
	looks.

	PURE. No module state, no Roblox API, and no argument is ever mutated.
	`parts` reads only `facility.layout` (rooms, doors) and
	`facility.placement.machines`, and returns plain tables. `BlockoutBuilder`
	turns them into Parts.

	GEOMETRY (story MAP-001, C-2 to C-4). Every spec is an axis-aligned box,
	`cframe` its centre and `size` its full extents:
	  * per room, a floor whose top face is y = 0 and a ceiling whose bottom
	    face is y = room_ceiling_studs, each `pitch x T x pitch` on the cell;
	  * per grid edge of an occupied cell, ONE set of walls, `T` thick and
	    centred on the grid line, spanning y = 0..ceiling and exactly the cell
	    edge along the line. An outer or doorless shared edge is one solid
	    wall; a doored edge is two full-height jambs and a lintel above the
	    doorway, which is open for |u| < width / 2 and y < height;
	  * per machine, an anchor `ANCHOR_SIZE` standing on the floor at
	    `Machines.positionOf`, named by its id.
]]

local Generator = require("./Generator")
local Layout = require("./Layout")
local Machines = require("./Machines")
local MechanicsTuning = require("@shared/MechanicsTuning")

export type Vec3 = { x: number, y: number, z: number }
export type PartSpec = {
	name: string,
	kind: "floor" | "ceiling" | "wall" | "machine",
	cframe: Vec3, -- the part's CENTRE; axis-aligned, no rotation
	size: Vec3, -- full extents, all > 0
}

type Tuning = MechanicsTuning.MechanicsTuning
type Kind = "floor" | "ceiling" | "wall" | "machine"

local Blockout = {}

-- Engineering, not tuning: a wall's thickness, centred on its grid line.
Blockout.WALL_THICKNESS = 1
-- Engineering placeholder for HUD-002's machine visuals.
Blockout.ANCHOR_SIZE = table.freeze({ x = 4, y = 6, z = 4 }) :: Vec3

-- The four sides of a cell: the neighbour's (column, row) step and the axis the
-- shared grid line is constant on.
type Side = { dc: number, dr: number, axis: "x" | "z", label: string }
local SIDES: { Side } = {
	{ dc = 1, dr = 0, axis = "x", label = "East" },
	{ dc = -1, dr = 0, axis = "x", label = "West" },
	{ dc = 0, dr = 1, axis = "z", label = "South" },
	{ dc = 0, dr = -1, axis = "z", label = "North" },
}

local function spec(name: string, kind: Kind, cframe: Vec3, size: Vec3): PartSpec
	return { name = name, kind = kind, cframe = cframe, size = size }
end

-- A wall piece on the grid line `axis = plane`, covering `[lo, hi]` along the
-- line and `[bottom, top]` up.
local function wall(
	name: string,
	axis: "x" | "z",
	plane: number,
	lo: number,
	hi: number,
	bottom: number,
	top: number
): PartSpec
	local T = Blockout.WALL_THICKNESS
	local along, length = (lo + hi) / 2, hi - lo
	local y, height = (bottom + top) / 2, top - bottom
	if axis == "x" then
		return spec(
			name,
			"wall",
			{ x = plane, y = y, z = along },
			{ x = T, y = height, z = length }
		)
	end
	return spec(name, "wall", { x = along, y = y, z = plane }, { x = length, y = height, z = T })
end

function Blockout.parts(facility: Generator.Facility, tuning: Tuning): { PartSpec }
	local t = tuning.instance
	local P, H = t.room_pitch_studs, t.room_ceiling_studs
	local W, D = t.doorway_width_studs, t.doorway_height_studs
	local T = Blockout.WALL_THICKNESS
	local layout: Layout.Layout = facility.layout
	local out: { PartSpec } = {}

	local byCell: { [string]: number } = {}
	for _, room in layout.rooms do
		byCell[`{room.column},{room.row}`] = room.id
	end
	local doored: { [string]: boolean } = {}
	for _, door in layout.doors do
		doored[`{math.min(door.a, door.b)}-{math.max(door.a, door.b)}`] = true
	end

	for _, room in layout.rooms do
		local centre = Machines.roomCentre(layout, room.id, tuning)
		table.insert(
			out,
			spec(
				`Floor{room.id}`,
				"floor",
				{ x = centre.x, y = -T / 2, z = centre.z },
				{ x = P, y = T, z = P }
			)
		)
		table.insert(
			out,
			spec(
				`Ceiling{room.id}`,
				"ceiling",
				{ x = centre.x, y = H + T / 2, z = centre.z },
				{ x = P, y = T, z = P }
			)
		)

		for _, side in SIDES do
			local neighbour = byCell[`{room.column + side.dc},{room.row + side.dr}`]
			-- One set of walls per edge: a shared edge belongs to its lower id.
			if neighbour == nil or room.id < neighbour then
				local plane, mid
				if side.axis == "x" then
					plane, mid = centre.x + side.dc * P / 2, centre.z
				else
					plane, mid = centre.z + side.dr * P / 2, centre.x
				end
				local lo, hi = mid - P / 2, mid + P / 2
				if neighbour ~= nil and doored[`{room.id}-{neighbour}`] then
					local name = `Wall{room.id}-{neighbour}`
					table.insert(out, wall(`{name}JambA`, side.axis, plane, lo, mid - W / 2, 0, H))
					table.insert(out, wall(`{name}JambB`, side.axis, plane, mid + W / 2, hi, 0, H))
					if D < H then
						table.insert(
							out,
							wall(`{name}Lintel`, side.axis, plane, mid - W / 2, mid + W / 2, D, H)
						)
					end
				elseif neighbour ~= nil then
					table.insert(
						out,
						wall(`Wall{room.id}-{neighbour}`, side.axis, plane, lo, hi, 0, H)
					)
				else
					table.insert(
						out,
						wall(`Wall{room.id}{side.label}`, side.axis, plane, lo, hi, 0, H)
					)
				end
			end
		end
	end

	local anchor = Blockout.ANCHOR_SIZE
	for _, machine in facility.placement.machines do
		local at = Machines.positionOf(layout, machine, tuning)
		table.insert(
			out,
			spec(
				tostring(machine.id),
				"machine",
				{ x = at.x, y = anchor.y / 2, z = at.z },
				{ x = anchor.x, y = anchor.y, z = anchor.z }
			)
		)
	end

	return out
end

return table.freeze(Blockout)
