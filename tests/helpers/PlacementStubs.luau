--!strict
--[[
	The wrong generators GEN-002's negative controls are aimed at, and the one
	reference each statistic must ACCEPT.

	THE CRITERIA NAME THEIR CONTROLS. AC-4: "a generator that leaves the last
	machine of each class (by id) without a setting must fail the first clause.
	One that draws settings from 1..dial_settings − 1 must fail the frequency
	check, with setting 4 at about 0". AC-6: "a generator that always gives the
	extra steps to classes 1..k must fail". AC-5's spacing clause has no named
	control, so this file supplies the obvious one: a `positionOf` that stacks
	every slot on the room centre.

	THE POSITIVE CONTROL is `reference`: the balanced split with the ceil
	classes shuffled from "counts"; one machine in every room first and the
	rest in shuffled free slots from "rooms", classes dealt by a shuffle of the
	same stream; per-class tags as a shuffled prefix of the alphabet from
	"tags"; one `nextInteger(1, dial_settings)` per machine from "settings".
	It exists so that each statistic is shown to ACCEPT a correct generator in
	RED: a statistic that rejects everything is indistinguishable from a broken
	one. Each wrong generator is the reference with EXACTLY ONE thing changed,
	so a control that fires is attributable to that one thing.

	WHAT THIS IS NOT: `src/server/facility/Machines.luau`, or a sketch of one.
	It has no `check`, no `positionOf` of its own, no exported types, and its
	room spread is one of several the Contract allows. GREEN writes the module
	from the story's Contract against `tests/server/machines_test.luau`;
	nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `Rng`, `MechanicsTuning`
	and `Layout` are merged - so these controls are EXECUTED in RED, and
	`tests/server/machines_controls_test.luau` records what each measured.

	NOT `MachineStubs.luau`: that file holds ROUND-003's phase-machine stubs.
]]

local Contract = require("./PlacementContract")
local Rng = require("../../src/shared/Rng")

type Machine = Contract.Machine
type Placement = Contract.Placement
type Layout = Contract.Layout
type Tuning = Contract.Tuning
type Position = Contract.Position

local PlacementStubs = {}

export type CountsRule = "draw" | "lowest"
export type SettingsRule = "draw" | "oneFewer" | "lastOfClassUnset"

type Seat = { room: number, slot: number }

-- The balanced split; the ceil classes are a shuffled prefix ("draw") or the
-- lowest classes ("lowest", AC-6's control).
local function stepsFor(
	rng: Rng.Rng,
	classes: { number },
	tuning: Tuning,
	rule: CountsRule
): { [number]: number }
	local split = Contract.expectedSplit(#classes, tuning)
	local steps: { [number]: number } = {}
	for _, c in classes do
		steps[c] = split.floor
	end
	local order = if rule == "lowest" then table.clone(classes) else rng:shuffle(classes)
	for i = 1, split.ceilCount do
		steps[order[i]] += 1
	end
	return steps
end

-- `count` seats over the layout's rooms: one per room first (a uniform slot),
-- then the rest from the remaining seats in shuffled order. Sorted by (room,
-- slot). Precondition: #rooms <= count <= #rooms × slots.
local function seatsFor(rng: Rng.Rng, layout: Layout, count: number, tuning: Tuning): { Seat }
	local slots = tuning.instance.machine_slots_per_room
	local taken: { [string]: boolean } = {}
	local out: { Seat } = {}
	for _, room in layout.rooms do
		local s = rng:nextInteger(1, slots)
		taken[`{room.id}/{s}`] = true
		table.insert(out, { room = room.id, slot = s })
	end
	local free: { Seat } = {}
	for _, room in layout.rooms do
		for s = 1, slots do
			if not taken[`{room.id}/{s}`] then
				table.insert(free, { room = room.id, slot = s })
			end
		end
	end
	local shuffled = rng:shuffle(free)
	for i = 1, count - #layout.rooms do
		table.insert(out, shuffled[i])
	end
	table.sort(out, function(a: Seat, b: Seat): boolean
		return if a.room ~= b.room then a.room < b.room else a.slot < b.slot
	end)
	return out
end

--[[
	A generator from a counts rule and a settings rule:

	    counts   "draw"             ceil classes shuffled          (the Contract)
	             "lowest"           ceil classes are 1..k          (AC-6's control)
	    settings "draw"             nextInteger(1, dial_settings)  (the Contract)
	             "oneFewer"         nextInteger(1, dial_settings − 1)
	             "lastOfClassUnset" as "draw", then the highest-id machine of
	                                each class loses its setting
]]
function PlacementStubs.generatorWith(counts: CountsRule, settings: SettingsRule): Contract.Generate
	return function(rng: Rng.Rng, layout: Layout, classes: { number }, tuning: Tuning): Placement
		local countsRng = rng:derive("counts")
		local roomsRng = rng:derive("rooms")
		local tagsRng = rng:derive("tags")
		local settingsRng = rng:derive("settings")
		local t = tuning.instance

		local steps = stepsFor(countsRng, classes, tuning, counts)

		local classList: { number } = {}
		for _, c in classes do
			for _ = 1, t.actuator_redundancy * steps[c] do
				table.insert(classList, c)
			end
		end

		local seats = seatsFor(roomsRng, layout, #classList, tuning)
		local dealt = roomsRng:shuffle(classList)
		local machines: { Machine } = {}
		for i, seat in seats do
			machines[i] = {
				id = i,
				room = seat.room,
				slot = seat.slot,
				keyClass = dealt[i],
				tag = 0,
				requiredSetting = 0,
			}
		end

		for _, c in classes do
			local alphabet: { number } = {}
			for v = 1, t.tag_alphabet_size do
				alphabet[v] = v
			end
			local perm = tagsRng:shuffle(alphabet)
			local k = 0
			for _, m in machines do
				if m.keyClass == c then
					k += 1
					m.tag = perm[k]
				end
			end
		end

		local top = if settings == "oneFewer" then t.dial_settings - 1 else t.dial_settings
		for _, m in machines do
			m.requiredSetting = settingsRng:nextInteger(1, top)
		end
		if settings == "lastOfClassUnset" then
			for _, c in classes do
				local last: Machine? = nil
				for _, m in machines do
					if m.keyClass == c then
						last = m
					end
				end
				if last ~= nil then
					(last :: any).requiredSetting = nil
				end
			end
		end

		return { machines = machines, stepsPerClass = steps }
	end
end

-- The positive control.
PlacementStubs.reference = PlacementStubs.generatorWith("draw", "draw")

-- AC-4's controls.
PlacementStubs.lastOfClassUnset = PlacementStubs.generatorWith("draw", "lastOfClassUnset")
PlacementStubs.settingsOneFewer = PlacementStubs.generatorWith("draw", "oneFewer")

-- AC-6's control.
PlacementStubs.extraToLowest = PlacementStubs.generatorWith("lowest", "draw")

-- AC-5's positive `positionOf`: the Contract's formula, as the helper derives it.
function PlacementStubs.referencePosition(
	layout: Layout,
	machine: Machine,
	tuning: Tuning
): Position
	return Contract.expectedPosition(layout, machine.room, machine.slot, tuning)
end

-- AC-5's control: every slot on the room centre. Right room, no quadrant.
function PlacementStubs.positionAtCentre(layout: Layout, machine: Machine, tuning: Tuning): Position
	local room = Contract.roomById(layout, machine.room)
	local pitch = tuning.instance.room_pitch_studs
	return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
end

return PlacementStubs
