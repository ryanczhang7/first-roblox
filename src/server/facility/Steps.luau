--!strict
--[[
	The Procedure, per GEN-003 and `docs/wiki/game/mechanics.md` §3.1-§3.2,
	§6.2. `tuning.md` §2 states the invariants this module keeps:
	`INV_balanced_steps`, `INV_every_class_has_a_step`, `INV_track_alternates`,
	`INV_finale` and `INV_k_essential`.

	A `Steps` value is `procedure_tracks` tracks of `steps_per_track` machine
	ids from a placement. Each class `c` contributes exactly
	`placement.stepsPerClass[c]` steps, consecutive steps in a track are of
	different classes, and the last step of each track is its half of the
	FINALE: two machines in rooms at least `paired_room_distance_min` apart,
	whose classes are held by players who are not ring neighbours, so the
	finale's two turners and two helpers are four distinct players.

	HOLDERS, HELPERS AND NEIGHBOURS ARE READ THROUGH `Ring` - `keyClasses`,
	`Ring.supplierOf`, `Ring.dependentOf` - and σ⁻¹ is never recomputed here.
	`Projection.luau`'s header says why a second copy of it is a defect.

	`draw` MAY RETURN AN INVALID CANDIDATE; the resample loop is `Generator`'s
	(GEN-004). It orders its choices to make that rare: the finale pair first,
	uniformly among the machine pairs that satisfy `INV_finale`; then each
	class's remaining steps; then an arrangement of the leading steps that
	alternates, found by a search over a shuffled order. No choice reads a
	machine's `requiredSetting`, so which settings end up as steps and which
	as decoys is not biased (`INV_settings_uniform`, decoys included).

	RANDOMNESS. `draw` derives exactly `"finale"`, `"choose"` and `"order"`
	from the rng it is handed, once each, and draws from nothing else.

	PURE. No module state, no Roblox API, and no argument is ever mutated. A
	`Steps` value is plain data - exactly `tracks` and `finale`.
]]

local Layout = require("./Layout")
local Machines = require("./Machines")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Ring = require("../seats/Ring")
local Rng = require("@game/ReplicatedStorage/Shared/Rng")

export type Steps = {
	tracks: { { number } }, -- tracks[t][i] = machine id
	finale: { number }, -- { tracks[1][last], tracks[2][last] }
}

type Tuning = MechanicsTuning.MechanicsTuning
type Machine = Machines.Machine

local Steps = {}

-- The finale is a pair: one machine closing each of two tracks.
local FINALE_TRACKS = 2

-- Who holds what, read through `Ring`. `classes` is the classes in play,
-- ascending; `holder[c]` the seated player whose `keyClasses` contains `c`.
type Seats = { classes: { number }, holder: { [number]: string } }

local function seatsOf(assignment: Ring.Assignment): Seats
	local holder: { [number]: string } = {}
	local classes: { number } = {}
	for _, p in assignment.players do
		local held: { Ring.KeyClass } = assignment.keyClasses[p] or {}
		for _, c in held do
			if holder[c] == nil then
				holder[c] = p
				table.insert(classes, c)
			end
		end
	end
	table.sort(classes)
	return { classes = classes, holder = holder }
end

-- Finale classes must be held by two different players who are not ring
-- neighbours (either way round).
local function finaleHoldersOk(assignment: Ring.Assignment, a: string, b: string): boolean
	return a ~= b and Ring.dependentOf(assignment, a) ~= b and Ring.dependentOf(assignment, b) ~= a
end

local function byIdOf(placement: Machines.Placement): { [number]: Machine }
	local byId: { [number]: Machine } = {}
	for _, m in placement.machines do
		byId[m.id] = m
	end
	return byId
end

--[[
	Every ordered pair of machines that would satisfy `INV_finale`. Ordered,
	so a uniform pick also decides which track closes on which machine.
	Distances are memoised per room pair: `Layout.distance` walks the graph.
]]
local function finalePairs(
	layout: Layout.Layout,
	placement: Machines.Placement,
	assignment: Ring.Assignment,
	seats: Seats,
	t: MechanicsTuning.InstanceTuning
): { { Machine } }
	local distance: { [string]: number } = {}
	local function far(a: number, b: number): boolean
		if a == b then
			return false
		end
		local key = `{a}/{b}`
		local d = distance[key]
		if d == nil then
			d = Layout.distance(layout, a, b)
			distance[key] = d
		end
		return d >= t.paired_room_distance_min
	end

	local found: { { Machine } } = {}
	for _, a in placement.machines do
		local ha = seats.holder[a.keyClass]
		for _, b in placement.machines do
			local hb = seats.holder[b.keyClass]
			if
				ha ~= nil
				and hb ~= nil
				and finaleHoldersOk(assignment, ha, hb)
				and far(a.room, b.room)
			then
				table.insert(found, { a, b })
			end
		end
	end
	return found
end

--[[
	Arrange `pool` into the leading steps of each track so that every track
	alternates, its last leading step included against its finale machine.
	A depth-first search over `pool` in the order given; the first arrangement
	found wins. `nil` when none exists.
]]
local function arrange(pool: { Machine }, lasts: { Machine }, leading: number): { { Machine } }?
	local tracks: { { Machine } } = {}
	for ti = 1, #lasts do
		tracks[ti] = {}
	end
	local used: { boolean } = {}

	local function place(slot: number): boolean
		if slot > #lasts * leading then
			return true
		end
		local ti = (slot - 1) // leading + 1
		local i = (slot - 1) % leading + 1
		local track = tracks[ti]
		local before = if i > 1 then track[i - 1] else nil
		local after = if i == leading then lasts[ti] else nil
		for k, m in pool do
			if
				not used[k]
				and (before == nil or before.keyClass ~= m.keyClass)
				and (after == nil or after.keyClass ~= m.keyClass)
			then
				used[k] = true
				track[i] = m
				if place(slot + 1) then
					return true
				end
				used[k] = false
				track[i] = nil :: any
			end
		end
		return false
	end

	if #pool ~= #lasts * leading or not place(1) then
		return nil
	end
	return tracks
end

function Steps.draw(
	rng: Rng.Rng,
	layout: Layout.Layout,
	placement: Machines.Placement,
	assignment: Ring.Assignment,
	tuning: Tuning
): Steps
	local t = tuning.instance
	if t.procedure_tracks ~= FINALE_TRACKS then
		error(`Steps.draw: the finale is a pair, but procedure_tracks = {t.procedure_tracks}`, 2)
	end
	local finaleRng = rng:derive("finale")
	local chooseRng = rng:derive("choose")
	local orderRng = rng:derive("order")
	local seats = seatsOf(assignment)

	-- 1. The finale pair, uniformly among those that satisfy INV_finale. If
	--    none does, any two machines of different classes: the candidate is
	--    then invalid, and `check` says so.
	local options = finalePairs(layout, placement, assignment, seats, t)
	if #options == 0 then
		for _, a in placement.machines do
			for _, b in placement.machines do
				if a.keyClass ~= b.keyClass then
					table.insert(options, { a, b })
				end
			end
		end
	end
	local pair = options[finaleRng:nextInteger(1, #options)]
	local lasts: { Machine } = { pair[1], pair[2] }

	-- 2. Each class's remaining steps, uniformly among its other machines.
	local pool: { Machine } = {}
	for _, c in seats.classes do
		local need = placement.stepsPerClass[c] or 0
		local candidates: { Machine } = {}
		for _, m in placement.machines do
			if m.keyClass == c then
				if m == lasts[1] or m == lasts[2] then
					need -= 1
				else
					table.insert(candidates, m)
				end
			end
		end
		local chosen = chooseRng:shuffle(candidates)
		for i = 1, math.min(need, #chosen) do
			table.insert(pool, chosen[i])
		end
	end

	-- 3. The order: an alternating arrangement of the shuffled leading steps,
	--    or, if none exists, the shuffled order as it stands (invalid).
	local leading = t.steps_per_track - 1
	local shuffled = orderRng:shuffle(pool)
	local arranged = arrange(shuffled, lasts, leading)
	local tracks: { { number } } = {}
	for ti, last in lasts do
		local track: { number } = {}
		for i = 1, leading do
			local m = if arranged then arranged[ti][i] else shuffled[(ti - 1) * leading + i]
			if m ~= nil then
				table.insert(track, m.id)
			end
		end
		table.insert(track, last.id)
		tracks[ti] = track
	end

	return { tracks = tracks, finale = { lasts[1].id, lasts[2].id } }
end

--[[
	The Procedure's invariants: one string per violated invariant, headed
	`<INV>:<token> ` with the first violated clause in the Contract table's
	order, then free text. A valid candidate returns `{}`.

	A malformed candidate never raises. It is reported under
	`INV_balanced_steps:shape`, and the other invariants are evaluated over
	what is present: ids in the placement, tracks that are lists, and the
	`finale` field when it is two placement ids.
]]
function Steps.check(
	steps: Steps,
	layout: Layout.Layout,
	placement: Machines.Placement,
	assignment: Ring.Assignment,
	tuning: Tuning
): { string }
	local t = tuning.instance
	local report: { string } = {}
	local byId = byIdOf(placement)
	local seats = seatsOf(assignment)

	local function machineOf(id: any): Machine?
		return if type(id) == "number" then byId[id] else nil
	end

	-- INV_balanced_steps:shape. `present` is every distinct step machine found.
	local shapeBad: string? = nil
	local present: { Machine } = {}
	local lists: { { any } } = {}
	local lasts: { any } = {}
	local tracks: any = (steps :: any).tracks
	if type(tracks) ~= "table" then
		shapeBad = `tracks is {type(tracks)}, not a list`
	else
		if #tracks ~= t.procedure_tracks then
			shapeBad = `{#tracks} track(s), expected {t.procedure_tracks}`
		end
		local seen: { [number]: boolean } = {}
		for ti, track in ipairs(tracks :: { any }) do
			if type(track) ~= "table" then
				shapeBad = shapeBad or `track {ti} is {type(track)}, not a list`
				continue
			end
			table.insert(lists, track)
			table.insert(lasts, track[#track])
			if #track ~= t.steps_per_track then
				shapeBad = shapeBad
					or `track {ti} has {#track} step(s), expected {t.steps_per_track}`
			end
			for i, id in ipairs(track :: { any }) do
				local m = machineOf(id)
				if m == nil then
					shapeBad = shapeBad
						or `track {ti} step {i} is {tostring(id)}, not in the placement`
				elseif seen[m.id] then
					shapeBad = shapeBad or `machine {m.id} is a step twice`
				else
					seen[m.id] = true
					table.insert(present, m)
				end
			end
		end
	end
	local finale: any = (steps :: any).finale
	local finaleOk = type(finale) == "table" and #finale == #lasts
	if finaleOk then
		for i, last in lasts do
			if finale[i] ~= last then
				finaleOk = false
			end
		end
	end
	if not finaleOk then
		shapeBad = shapeBad or `finale is not the tracks' last steps, in track order`
	end

	-- INV_balanced_steps:count
	local perClass: { [number]: number } = {}
	for _, c in seats.classes do
		perClass[c] = 0
	end
	local countBad: string? = nil
	for _, m in present do
		if perClass[m.keyClass] == nil then
			countBad = countBad or `machine {m.id} is of class {m.keyClass}, which nobody holds`
		else
			perClass[m.keyClass] += 1
		end
	end
	local low, high = math.huge, -math.huge
	for _, c in seats.classes do
		local want = placement.stepsPerClass[c]
		if perClass[c] ~= want then
			countBad = countBad
				or `class {c} has {perClass[c]} step(s), stepsPerClass says {tostring(want)}`
		end
		low, high = math.min(low, perClass[c]), math.max(high, perClass[c])
	end
	if #seats.classes > 0 and high - low > 1 then
		countBad = countBad or `step counts range from {low} to {high}`
	end

	if shapeBad then
		table.insert(report, `INV_balanced_steps:shape {shapeBad}`)
	elseif countBad then
		table.insert(report, `INV_balanced_steps:count {countBad}`)
	end

	-- INV_every_class_has_a_step:missing
	for _, c in seats.classes do
		if perClass[c] == 0 then
			table.insert(report, `INV_every_class_has_a_step:missing class {c} has no step`)
			break
		end
	end

	-- INV_track_alternates:adjacent
	local adjacentBad: string? = nil
	for ti, track in lists do
		for i = 2, #track do
			local a, b = machineOf(track[i - 1]), machineOf(track[i])
			if a ~= nil and b ~= nil and a.keyClass == b.keyClass then
				adjacentBad = adjacentBad
					or `track {ti} steps {i - 1} and {i} are both class {a.keyClass}`
			end
		end
	end
	if adjacentBad then
		table.insert(report, `INV_track_alternates:adjacent {adjacentBad}`)
	end

	-- INV_finale:rooms, then :ring, over the finale field when it is two ids.
	if type(finale) == "table" and #finale == FINALE_TRACKS then
		local f1, f2 = machineOf(finale[1]), machineOf(finale[2])
		if f1 ~= nil and f2 ~= nil then
			local h1, h2 = seats.holder[f1.keyClass], seats.holder[f2.keyClass]
			if f1.room == f2.room then
				table.insert(
					report,
					`INV_finale:rooms machines {f1.id} and {f2.id} share room {f1.room}`
				)
			elseif Layout.distance(layout, f1.room, f2.room) < t.paired_room_distance_min then
				table.insert(
					report,
					`INV_finale:rooms rooms {f1.room} and {f2.room} are closer than {t.paired_room_distance_min}`
				)
			elseif h1 ~= nil and h2 ~= nil and not finaleHoldersOk(assignment, h1, h2) then
				table.insert(
					report,
					`INV_finale:ring classes {f1.keyClass} ({h1}) and {f2.keyClass} ({h2})`
				)
			end
		end
	end

	-- INV_k_essential:turn, then :read. The turner of a step is its class's
	-- holder; the helper is that holder's supplier, the player whose lens it is.
	local turners: { [string]: boolean } = {}
	local helpers: { [string]: boolean } = {}
	for _, m in present do
		local holder = seats.holder[m.keyClass]
		if holder ~= nil then
			turners[holder] = true
			helpers[Ring.supplierOf(assignment, holder)] = true
		end
	end
	local turnBad, readBad = nil :: string?, nil :: string?
	for _, p in assignment.players do
		if not turners[p] then
			turnBad = turnBad or `no step has a machine only {p} can turn`
		end
		if not helpers[p] then
			readBad = readBad or `no step has a machine whose setting only {p} can read`
		end
	end
	if turnBad then
		table.insert(report, `INV_k_essential:turn {turnBad}`)
	elseif readBad then
		table.insert(report, `INV_k_essential:read {readBad}`)
	end

	return report
end

return table.freeze(Steps)
