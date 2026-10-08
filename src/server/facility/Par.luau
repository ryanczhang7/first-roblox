--!strict
--[[
	Par, per GEN-004 and `docs/wiki/game/mechanics.md` §6.3: the duration of
	the canonical schedule a NAIVE group would keep. Everyone starts together
	in the layout's spawn room, the steps are taken one at a time, and nobody
	anticipates, guesses or presets. `INV_traversal` (`tuning.md` §2) bounds
	it: `par × schedule_slack ≤ round_seconds`, which `Generator` enforces.

	THE SCHEDULE.
	  * Ordinary steps are every track's steps but its last, interleaved
	    T1[1], T2[1], T1[2], T2[2], ...; when one track runs out, the rest of
	    the other follows in order. Each costs the LONGER of the helper's and
	    the turner's walk to the machine's room - they walk in parallel - plus
	    one `par_ping_seconds` and one `par_turn_seconds`. Both then stand in
	    that room. Nobody else moves.
	  * The finale (`steps.finale`, the last step of each track) is ONE unit:
	    the longest of its sub-steps' parallel walks, then one ping and one
	    turn, added once.

	`walk(a, b)` is `Layout.distance` in doorway edges times
	`room_traversal_seconds`. The start is the `spawnRoom` FIELD, never
	recomputed. The result is an exact sum of tuning products: no rounding.

	TURNER AND HELPER ARE READ THROUGH `Ring` and the assignment. The turner of
	a machine is the player whose `keyClasses` holds its class; the helper is
	that player's supplier, `Ring.supplierOf`, the player whose lens is that
	class. σ is never recomputed here.

	PURE. No module state, no Roblox API, and no argument is ever mutated.
]]

local Layout = require("./Layout")
local Machines = require("./Machines")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Ring = require("../seats/Ring")
local Steps = require("./Steps")

type Tuning = MechanicsTuning.MechanicsTuning

local Par = {}

function Par.compute(
	layout: Layout.Layout,
	placement: Machines.Placement,
	steps: Steps.Steps,
	assignment: Ring.Assignment,
	tuning: Tuning
): number
	local t = tuning.instance

	local roomOf: { [number]: number } = {}
	local turnerOf: { [number]: string } = {}
	for _, p in assignment.players do
		local held: { Ring.KeyClass } = assignment.keyClasses[p] or {}
		for _, c in held do
			if turnerOf[c] == nil then
				turnerOf[c] = p
			end
		end
	end
	local classOf: { [number]: number } = {}
	for _, m in placement.machines do
		roomOf[m.id] = m.room
		classOf[m.id] = m.keyClass
	end

	-- Distances memoised per room pair: `Layout.distance` walks the graph.
	local distance: { [string]: number } = {}
	local function walk(a: number, b: number): number
		local key = `{a}/{b}`
		local d = distance[key]
		if d == nil then
			d = Layout.distance(layout, a, b)
			distance[key] = d
		end
		return d * t.room_traversal_seconds
	end

	local position: { [string]: number } = {}
	for _, p in assignment.players do
		position[p] = layout.spawnRoom
	end

	-- The longer of the pair's two walks to machine `id`'s room, and the pair.
	local function parallelWalk(id: number): (number, number, string, string)
		local room = roomOf[id]
		local turner = turnerOf[classOf[id]]
		local helper = Ring.supplierOf(assignment, turner)
		local cost = math.max(walk(position[helper], room), walk(position[turner], room))
		return cost, room, helper, turner
	end

	local perStep = t.par_ping_seconds + t.par_turn_seconds
	local total = 0

	local leading = t.steps_per_track - 1
	for i = 1, leading do
		for _, track in steps.tracks do
			local id = track[i]
			if id ~= nil then
				local cost, room, helper, turner = parallelWalk(id)
				total += cost + perStep
				position[helper] = room
				position[turner] = room
			end
		end
	end

	local finaleWalk = 0
	for _, id in steps.finale do
		local cost = parallelWalk(id)
		finaleWalk = math.max(finaleWalk, cost)
	end
	return total + finaleWalk + perStep
end

return table.freeze(Par)
