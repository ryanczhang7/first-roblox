--!strict
--[[
	VIEW-003: the two public payloads (`architecture.md` D15, §9.7). Everything
	here is something every player may know, so it goes to every client.

	`FacilityView`, built once per round, is the layout and each machine's
	STATIC public facts: room, slot, tag and key class (`roles.md` §3). No
	`requiredSetting`, no steps, tracks or finale marker, no `par`, no
	`attempt`. Doors are normalised to `a < b` and sorted by `a` then `b`.

	`RoundView`, sent on change and while a clock runs, is exactly ten keys:
	`phase`, `secondsLeft`, `players`, `playersMin`, `playersMax` (SLICE-003's
	five) and `progress`, `instability`, `dark`, `pings`, `machines`. The bar is
	exactly `{ committed, total }` (`mechanics.md` §3.2, T10 (c)): `total` is
	always `procedure_length`, `committed` the number of committed machines,
	which is steps committed because a decoy never commits.

	PROCEDURE FIELDS ONLY IN `Round` WITH A PROCEDURE (C-3). `Session` keeps the
	Procedure through `Resolution` and `Post`; there the view shows the
	defaults, not the finished round.

	A DIAL NEVER READS THE SECRET (AC-2, C-5). Its state is, by precedence,
	committed, armed, rejected (inside the reset window) or unset. Armed is
	asked before `Procedure.dial`, which reports an armed machine as unset. Its
	setting is nil when unset, and otherwise the setting of the LAST actuation
	log entry for the machine, whatever its result: that is the setting last
	turned onto it, `not_live` turns included. `requiredSetting` is never read.

	THE PARTNER LAMP is published, and only on the two finale machines (C-11):
	it is a world object anyone in the room can see. `false` with no ring.

	`secondsLeft` is relative, never an absolute deadline (§9.7). In `Round`
	with a Procedure it is the ceiling of `Procedure.deadline - now`, so a
	clock penalty shows; elsewhere the config's duration minus the time spent
	in the phase; nil where no clock runs (`Assignment`, `Resolution`, a
	`Lobby` below `playersMin`). Every value is clamped at 0.

	PURE, and it requires nothing that requires the composition root (C-2):
	that module builds its broadcast from this one. Every table in a view is
	fresh, so neither side can mutate the other (C-9).
]]

local Generator = require("../facility/Generator")
local Machines = require("../facility/Machines")
local MechanicsTuning = require("@shared/MechanicsTuning")
local PhaseMachine = require("./PhaseMachine")
local Pings = require("../channel/Pings")
local Procedure = require("../procedure/Procedure")
local Ring = require("../seats/Ring")

local RoundView = {}

export type DialState = "unset" | "rejected" | "armed" | "committed"

export type MachinePublic = {
	id: number,
	dial: { setting: number?, state: DialState },
	live: boolean,
	partnerLamp: boolean?, -- only on the two finale machines
}

export type RoundView = {
	phase: PhaseMachine.Phase,
	secondsLeft: number?,
	players: { string }, -- join order, which is seat order once dealt
	playersMin: number,
	playersMax: number,
	progress: { committed: number, total: number },
	instability: number,
	dark: { number }, -- room ids, ascending
	pings: { Pings.PingShown },
	machines: { MachinePublic }, -- ascending id; empty outside Round
}

export type FacilityView = {
	rooms: { { id: number, column: number, row: number } },
	doors: { { a: number, b: number } },
	spawnRoom: number,
	machines: { { id: number, room: number, slot: number, tag: number, keyClass: number } },
}

export type Input = {
	round: PhaseMachine.RoundState,
	procedure: Procedure.ProcedureState?,
	assignment: Ring.Assignment?,
	positions: { [string]: Procedure.Vec }, -- the ACCEPTED positions
	pings: { Pings.PingShown }, -- already shown
	tuning: MechanicsTuning.MechanicsTuning,
}

-- The placement's machines, ascending `id`, as a fresh list of the same records.
local function byId(facility: Generator.Facility): { Machines.Machine }
	local machines = table.clone(facility.placement.machines)
	table.sort(machines, function(a: Machines.Machine, b: Machines.Machine): boolean
		return a.id < b.id
	end)
	return machines
end

local function secondsLeftIn(
	round: PhaseMachine.RoundState,
	procedure: Procedure.ProcedureState?,
	now: number
): number?
	local config = round.config
	local raw: number
	if round.phase == "Round" and procedure ~= nil then
		raw = math.ceil(Procedure.deadline(procedure) - now)
	else
		local duration: number? = nil
		if round.phase == "Lobby" and #round.players >= config.playersMin then
			duration = config.lobbySeconds
		elseif round.phase == "Round" then
			duration = config.roundSeconds
		elseif round.phase == "Post" then
			duration = config.postRoundSeconds
		end
		if duration == nil then
			return nil
		end
		raw = math.ceil(duration - (now - round.phaseEnteredAt))
	end
	return math.max(0, raw)
end

-- The setting of the last actuation log entry for `id`, any result.
local function lastTurned(procedure: Procedure.ProcedureState, id: number): number?
	for index = #procedure.log, 1, -1 do
		local entry = procedure.log[index]
		if entry.machineId == id then
			return entry.setting
		end
	end
	return nil
end

local function dialStateOf(procedure: Procedure.ProcedureState, id: number, now: number): DialState
	if procedure.committed[id] then
		return "committed"
	end
	local armed = procedure.armed
	if armed ~= nil and armed.machineId == id then
		return "armed"
	end
	if Procedure.dial(procedure, id, now).state == "rejected" then
		return "rejected"
	end
	return "unset"
end

local function machinesOf(
	input: Input,
	procedure: Procedure.ProcedureState,
	now: number
): { MachinePublic }
	local finale = procedure.facility.steps.finale
	local lamps: { [number]: boolean } = {}
	if input.assignment ~= nil then
		lamps = Procedure.partnerLamps(procedure, input.assignment, input.positions)
	end
	local out: { MachinePublic } = {}
	for _, machine in byId(procedure.facility) do
		local id = machine.id
		local state: DialState = dialStateOf(procedure, id, now)
		local setting = if state == "unset" then nil else lastTurned(procedure, id)
		local record: MachinePublic = {
			id = id,
			dial = { setting = setting, state = state },
			live = Procedure.isLive(procedure, id),
		}
		if table.find(finale, id) ~= nil then
			record.partnerLamp = lamps[id] == true
		end
		table.insert(out, record)
	end
	return out
end

local function darkOf(procedure: Procedure.ProcedureState): { number }
	local out: { number } = {}
	for _, room in procedure.facility.layout.rooms do
		if procedure.dark[room.id] == true then
			table.insert(out, room.id)
		end
	end
	table.sort(out)
	return out
end

local function committedOf(procedure: Procedure.ProcedureState): number
	local count = 0
	for _, flag in procedure.committed do
		if flag == true then
			count += 1
		end
	end
	return count
end

local function pingsOf(pings: { Pings.PingShown }): { Pings.PingShown }
	local out: { Pings.PingShown } = {}
	for _, ping in pings do
		table.insert(out, {
			senderId = ping.senderId,
			kind = ping.kind,
			target = ping.target,
			setting = ping.setting,
		})
	end
	return out
end

function RoundView.public(input: Input, now: number): RoundView
	local round = input.round
	local procedure = if round.phase == "Round" then input.procedure else nil
	local committed = 0
	local instability = 0
	local dark: { number } = {}
	local machines: { MachinePublic } = {}
	if procedure ~= nil then
		committed = committedOf(procedure)
		instability = procedure.instability
		dark = darkOf(procedure)
		machines = machinesOf(input, procedure, now)
	end
	local total = input.tuning.instance.procedure_length
	return {
		phase = round.phase,
		secondsLeft = secondsLeftIn(round, input.procedure, now),
		players = table.clone(round.players),
		playersMin = round.config.playersMin,
		playersMax = round.config.playersMax,
		progress = { committed = committed, total = total },
		instability = instability,
		dark = dark,
		pings = pingsOf(input.pings),
		machines = machines,
	}
end

function RoundView.facility(facility: Generator.Facility): FacilityView
	local layout = facility.layout
	local rooms = {}
	for _, room in layout.rooms do
		table.insert(rooms, { id = room.id, column = room.column, row = room.row })
	end
	table.sort(rooms, function(a, b): boolean
		return a.id < b.id
	end)

	local doors = {}
	for _, door in layout.doors do
		table.insert(doors, { a = math.min(door.a, door.b), b = math.max(door.a, door.b) })
	end
	table.sort(doors, function(x, y): boolean
		if x.a ~= y.a then
			return x.a < y.a
		end
		return x.b < y.b
	end)

	local machines = {}
	for _, m in byId(facility) do
		table.insert(
			machines,
			{ id = m.id, room = m.room, slot = m.slot, tag = m.tag, keyClass = m.keyClass }
		)
	end

	return {
		rooms = rooms,
		doors = doors,
		spawnRoom = layout.spawnRoom,
		machines = machines,
	}
end

return RoundView
