--!strict
--[[
	Machine placement, per GEN-002 and `docs/wiki/game/mechanics.md` §1, §3.1
	(G2-G4, G12). `tuning.md` §2 states the invariants this module keeps:
	`INV_class_machines`, `INV_room_capacity`, `INV_tags_distinct_in_class` and
	`INV_settings_uniform`.

	A placement puts `actuator_redundancy` x `stepsPerClass[c]` machines of each
	key class `c` into the layout's rooms, one per quadrant slot, every room
	holding `machines_per_room_min..machines_per_room_max` of them. Steps are the
	balanced split of `procedure_length` over the classes in play; which classes
	get the ceiling is drawn. Each class's tags are distinct, drawn from
	`1..tag_alphabet_size`. Every machine has a `requiredSetting` - the game's
	central secret (`roles.md` §6), never replicated whole.

	PURE. No module state, no Roblox API, and no argument is ever mutated. A
	`Placement` is plain data - exactly `machines` and `stepsPerClass` - so two
	placements from the same rng, layout and classes deep-equal each other.

	RANDOMNESS. `generate` derives exactly `"counts"`, `"rooms"`, `"tags"` and
	`"settings"` from the rng it is handed, once each, and draws from nothing
	else. Settings read only `"settings"`: one `nextInteger(1, dial_settings)`
	per machine, in id order.

	IDS run `1..actuator_count` in ascending `(room, slot)` order, and
	`machines[i].id == i`. Slots are quadrants: 1 (-x,-z), 2 (+x,-z), 3 (-x,+z),
	4 (+x,+z). World coordinates are horizontal: a room's centre is
	`((column - 1) x room_pitch_studs, 0, (row - 1) x room_pitch_studs)`
	(`architecture.md` §9.8).
]]

local Layout = require("./Layout")
local MechanicsTuning = require("@shared/MechanicsTuning")
local Ring = require("../seats/Ring")
local Rng = require("@shared/Rng")

export type Machine = {
	id: number, -- 1..actuator_count, in (room id, slot) order
	room: number, -- Layout room id
	slot: number, -- 1..machine_slots_per_room
	keyClass: Ring.KeyClass,
	tag: number, -- 1..tag_alphabet_size
	requiredSetting: number, -- 1..dial_settings (SECRET: roles.md §6)
}
export type Placement = { machines: { Machine }, stepsPerClass: { [number]: number } }
export type Position = { x: number, y: number, z: number }

type Tuning = MechanicsTuning.MechanicsTuning
type InstanceTuning = MechanicsTuning.InstanceTuning

local Machines = {}

-- Quadrant signs (sx, sz) for slots 1..4.
local QUADRANT: { { number } } = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

local function isInteger(v: any): boolean
	return type(v) == "number" and v == math.floor(v)
end

local function roomById(layout: Layout.Layout, id: number): Layout.Room?
	for _, room in layout.rooms do
		if room.id == id then
			return room
		end
	end
	return nil
end

-- The balanced split of `procedure_length` over `n` classes.
local function split(n: number, t: InstanceTuning): (number, number, number)
	local length = t.procedure_length
	local low = length // n
	local high = if length % n == 0 then low else low + 1
	return low, high, length % n
end

-- Steps per class: `floor` each, plus one for `L mod n` classes drawn from "counts".
local function stepsFor(rng: Rng.Rng, classes: { number }, t: InstanceTuning): { [number]: number }
	local low, _, extra = split(#classes, t)
	local steps: { [number]: number } = {}
	for _, c in classes do
		steps[c] = low
	end
	local order = rng:shuffle(classes)
	for i = 1, extra do
		steps[order[i]] += 1
	end
	return steps
end

-- Machines per room: every room starts at `machines_per_room_min`; each
-- remaining machine goes to a uniform room with a free slot left. Indexed by
-- the rooms sorted by id. Precondition: the rooms can hold `total`.
local function roomCounts(
	rng: Rng.Rng,
	roomCount: number,
	total: number,
	t: InstanceTuning
): { number }
	local cap = math.min(t.machines_per_room_max, t.machine_slots_per_room)
	local counts: { number } = {}
	local open: { number } = {}
	for i = 1, roomCount do
		counts[i] = t.machines_per_room_min
		if counts[i] < cap then
			table.insert(open, i)
		end
	end
	for _ = 1, total - roomCount * t.machines_per_room_min do
		local k = rng:nextInteger(1, #open)
		local i = open[k]
		counts[i] += 1
		if counts[i] >= cap then
			table.remove(open, k)
		end
	end
	return counts
end

function Machines.generate(
	rng: Rng.Rng,
	layout: Layout.Layout,
	classes: { number },
	tuning: Tuning
): Placement
	local t = tuning.instance
	local countsRng = rng:derive("counts")
	local roomsRng = rng:derive("rooms")
	local tagsRng = rng:derive("tags")
	local settingsRng = rng:derive("settings")

	local steps = stepsFor(countsRng, classes, t)

	local classList: { number } = {}
	for _, c in classes do
		for _ = 1, t.actuator_redundancy * steps[c] do
			table.insert(classList, c)
		end
	end

	-- Seats in ascending (room, slot) order: each room's slots are a sorted
	-- uniform subset of its quadrants.
	local rooms = table.clone(layout.rooms)
	table.sort(rooms, function(a: Layout.Room, b: Layout.Room): boolean
		return a.id < b.id
	end)
	local counts = roomCounts(roomsRng, #rooms, #classList, t)
	local quadrants: { number } = {}
	for s = 1, t.machine_slots_per_room do
		quadrants[s] = s
	end
	local machines: { Machine } = {}
	local dealt = roomsRng:shuffle(classList)
	for i, room in rooms do
		local chosen = table.move(roomsRng:shuffle(quadrants), 1, counts[i], 1, {})
		table.sort(chosen)
		for _, slot in chosen do
			local id = #machines + 1
			machines[id] = {
				id = id,
				room = room.id,
				slot = slot,
				keyClass = dealt[id],
				tag = 0,
				requiredSetting = 0,
			}
		end
	end

	-- Tags: per class in `classes` order, a uniform draw without replacement.
	local alphabet: { number } = {}
	for v = 1, t.tag_alphabet_size do
		alphabet[v] = v
	end
	for _, c in classes do
		local perm = tagsRng:shuffle(alphabet)
		local k = 0
		for _, m in machines do
			if m.keyClass == c then
				k += 1
				m.tag = perm[k]
			end
		end
	end

	for _, m in machines do
		m.requiredSetting = settingsRng:nextInteger(1, t.dial_settings)
	end

	return { machines = machines, stepsPerClass = steps }
end

--[[
	The placement invariants, one string per violated clause, each starting
	`<INV>:<token> `. A valid placement returns `{}`. The frequency half of
	`INV_settings_uniform` is a sweep property and is not checked here.
]]
function Machines.check(
	placement: Placement,
	layout: Layout.Layout,
	classes: { number },
	tuning: Tuning
): { string }
	local t = tuning.instance
	local report: { string } = {}
	local machines = placement.machines
	local steps = placement.stepsPerClass

	-- INV_class_machines:steps
	local inPlay: { [number]: boolean } = {}
	for _, c in classes do
		inPlay[c] = true
	end
	local low, high = split(#classes, t)
	local stepsBad: string? = nil
	local sum = 0
	for c, s in steps do
		if not inPlay[c] then
			stepsBad = `class {c} is not in play`
		elseif s ~= low and s ~= high then
			stepsBad = `class {c} has {s} steps, expected {low} or {high}`
		end
		sum += s
	end
	for _, c in classes do
		if steps[c] == nil then
			stepsBad = `class {c} has no step count`
		end
	end
	if stepsBad == nil and sum ~= t.procedure_length then
		stepsBad = `steps sum to {sum}, expected {t.procedure_length}`
	end
	if stepsBad then
		table.insert(report, `INV_class_machines:steps {stepsBad}`)
	end

	-- INV_class_machines:count
	local perClass: { [number]: number } = {}
	local countBad: string? = nil
	for _, m in machines do
		if not inPlay[m.keyClass] then
			countBad = `machine {m.id} has class {m.keyClass}, not in play`
		else
			perClass[m.keyClass] = (perClass[m.keyClass] or 0) + 1
		end
	end
	for _, c in classes do
		local want = t.actuator_redundancy * (steps[c] or 0)
		if (perClass[c] or 0) ~= want then
			countBad = `class {c} has {perClass[c] or 0} machines, expected {want}`
		end
	end
	if #machines ~= t.actuator_count then
		countBad = `{#machines} machines, expected {t.actuator_count}`
	end
	if countBad then
		table.insert(report, `INV_class_machines:count {countBad}`)
	end

	-- INV_room_capacity:slot, then :count
	local slotBad: string? = nil
	local seen: { [string]: number } = {}
	local perRoom: { [number]: number } = {}
	for _, m in machines do
		local key = `{m.room}/{m.slot}`
		if roomById(layout, m.room) == nil then
			slotBad = `machine {m.id} names unknown room {m.room}`
		elseif not isInteger(m.slot) or m.slot < 1 or m.slot > t.machine_slots_per_room then
			slotBad = `machine {m.id} has slot {m.slot}, outside 1..{t.machine_slots_per_room}`
		elseif seen[key] then
			slotBad = `machines {seen[key]} and {m.id} share room {m.room} slot {m.slot}`
		end
		seen[key] = m.id
		perRoom[m.room] = (perRoom[m.room] or 0) + 1
	end
	if slotBad then
		table.insert(report, `INV_room_capacity:slot {slotBad}`)
	end
	for _, room in layout.rooms do
		local held = perRoom[room.id] or 0
		if held < t.machines_per_room_min or held > t.machines_per_room_max then
			table.insert(
				report,
				`INV_room_capacity:count room {room.id} holds {held}, expected {t.machines_per_room_min}..{t.machines_per_room_max}`
			)
			break
		end
	end

	-- INV_tags_distinct_in_class:tag
	local tagBad: string? = nil
	local tags: { [string]: number } = {}
	for _, m in machines do
		local key = `{m.keyClass}/{m.tag}`
		if not isInteger(m.tag) or m.tag < 1 or m.tag > t.tag_alphabet_size then
			tagBad = `machine {m.id} has tag {m.tag}, outside 1..{t.tag_alphabet_size}`
		elseif tags[key] then
			tagBad = `machines {tags[key]} and {m.id} of class {m.keyClass} share tag {m.tag}`
		end
		tags[key] = m.id
	end
	if tagBad then
		table.insert(report, `INV_tags_distinct_in_class:tag {tagBad}`)
	end

	-- INV_settings_uniform:setting (shape only)
	for _, m in machines do
		local v: any = m.requiredSetting
		if not isInteger(v) or v < 1 or v > t.dial_settings then
			table.insert(
				report,
				`INV_settings_uniform:setting machine {m.id} has setting {v}, outside 1..{t.dial_settings}`
			)
			break
		end
	end

	return report
end

-- The machine's world position: its room's centre plus the slot's quadrant
-- offset of ± `room_pitch_studs` / 4 on each axis. Reads only `room` and `slot`.
function Machines.positionOf(layout: Layout.Layout, machine: Machine, tuning: Tuning): Position
	local room = roomById(layout, machine.room)
	if room == nil then
		error(`Machines: room {machine.room} is not in the layout`, 2)
	end
	local quadrant = QUADRANT[machine.slot]
	if quadrant == nil then
		error(`Machines: slot {machine.slot} is not a quadrant`, 2)
	end
	local pitch = tuning.instance.room_pitch_studs
	return {
		x = (room.column - 1) * pitch + quadrant[1] * pitch / 4,
		y = 0,
		z = (room.row - 1) * pitch + quadrant[2] * pitch / 4,
	}
end

return table.freeze(Machines)
