--!strict
--[[
	The Procedure in play, per PROC-001 and `docs/wiki/game/mechanics.md` §1,
	§3.2, §5 (G12): a turn commits a live step on the right setting and says
	why it failed otherwise.

	LIVENESS (P-3). A step is live when it is the first uncommitted step of its
	track and is not that track's last entry - the finale step, which stays
	`waiting` until PROC-002 opens the finale window (`finale_live_together`).
	Decoys (machines in no track), committed machines and unknown ids are
	never live.

	A TURN IS REFUSED OR EVALUATED. The refusals run in this order and the
	first failure wins: `unknown_machine`, `not_key_holder`, `out_of_reach`,
	`committed`, `resetting`. A refused turn is free: it returns the state it
	was handed, unchanged, and writes no log entry. An evaluated turn commits a
	live step on its required setting; anything else is rejected as `not_live`
	(a waiting step or a decoy, whatever the setting - P-8) or `wrong_setting`,
	charged that reason's constant, logged, and the dial shows the rejected
	setting until `actuation_reset_seconds` have passed (half-open, P-6).

	TUNING LIVES IN THE STATE (P-1). `start` stores the tuning it is handed and
	every constant is read from `state.tuning`, never from `MechanicsTuning`.

	PURE (D3). No module state, no Roblox API, and no argument is ever mutated.
	Every evaluated turn returns a new state whose `committed`, `dials` and
	`log` are fresh tables; the facility and tuning are shared, read-only.
]]

local Generator = require("../facility/Generator")
local Machines = require("../facility/Machines")
local MechanicsTuning = require("@shared/MechanicsTuning")
local Ring = require("../seats/Ring")

export type Vec = { x: number, y: number, z: number }
export type DialView = { setting: number?, state: "unset" | "committed" | "rejected" }
export type TurnResult =
	{ kind: "committed", machineId: number }
	| { kind: "armed", machineId: number }
	| { kind: "rejected", machineId: number, reason: "wrong_setting" | "not_live" }
	| {
		kind: "refused",
		machineId: number?,
		reason: "unknown_machine"
			| "not_key_holder"
			| "out_of_reach"
			| "committed"
			| "resetting"
			| "armed",
	}
export type ActuationLogEntry = {
	playerId: string,
	machineId: number,
	setting: number,
	at: number,
	result: "committed" | "armed" | "wrong_setting" | "not_live",
}
export type Dial = { setting: number?, rejectedUntil: number? }
export type ProcedureState = {
	facility: Generator.Facility,
	committed: { [number]: boolean },
	dials: { [number]: Dial },
	instability: number,
	log: { ActuationLogEntry },
	tuning: MechanicsTuning.MechanicsTuning,
}

type RefusalReason = "not_key_holder" | "out_of_reach" | "committed" | "resetting"

local Procedure = {}

-- The machine with this `id` FIELD (P-2), or nil.
local function machineOf(facility: Generator.Facility, id: number): Machines.Machine?
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

function Procedure.start(
	facility: Generator.Facility,
	_now: number,
	tuning: MechanicsTuning.MechanicsTuning
): ProcedureState
	return {
		facility = facility,
		committed = {},
		dials = {},
		instability = 0,
		log = {},
		tuning = tuning,
	}
end

function Procedure.isLive(state: ProcedureState, machineId: number): boolean
	for _, track in state.facility.steps.tracks do
		for k, id in track do
			if not state.committed[id] then
				-- The first uncommitted step of this track: live unless it is
				-- the finale step, the track's last entry.
				if id == machineId then
					return k < #track
				end
				break
			end
		end
	end
	return false
end

-- Inside the reset window at `now`: `now < rejectedUntil` (P-6).
local function resetting(state: ProcedureState, machineId: number, now: number): boolean
	local d = state.dials[machineId]
	return d ~= nil and d.rejectedUntil ~= nil and now < d.rejectedUntil
end

function Procedure.dial(state: ProcedureState, machineId: number, now: number): DialView
	local d = state.dials[machineId]
	if state.committed[machineId] then
		return { setting = if d then d.setting else nil, state = "committed" }
	end
	if d ~= nil and resetting(state, machineId, now) then
		return { setting = d.setting, state = "rejected" }
	end
	return { setting = nil, state = "unset" }
end

local function holds(assignment: Ring.Assignment, playerId: string, keyClass: number): boolean
	local classes = assignment.keyClasses[playerId]
	if classes == nil then
		return false
	end
	return table.find(classes, keyClass) ~= nil
end

-- Horizontal distance to `Machines.positionOf`, inclusive of the range (P-4).
local function inReach(state: ProcedureState, machine: Machines.Machine, position: Vec?): boolean
	if position == nil then
		return false
	end
	local m = Machines.positionOf(state.facility.layout, machine, state.tuning)
	local dx = position.x - m.x
	local dz = position.z - m.z
	return math.sqrt(dx * dx + dz * dz) <= state.tuning.instance.turn_range_studs
end

-- The first refusal that applies to a known machine, in the Contract's order
-- after `unknown_machine` (which `turn` checks first), or nil.
local function refusal(
	state: ProcedureState,
	assignment: Ring.Assignment,
	playerId: string,
	machine: Machines.Machine,
	machineId: number,
	now: number,
	positions: { [string]: Vec }
): RefusalReason?
	if not holds(assignment, playerId, machine.keyClass) then
		return "not_key_holder"
	end
	if not inReach(state, machine, positions[playerId]) then
		return "out_of_reach"
	end
	if state.committed[machineId] then
		return "committed"
	end
	if resetting(state, machineId, now) then
		return "resetting"
	end
	return nil
end

-- A new state sharing no writable table with `state`.
local function copy(state: ProcedureState): ProcedureState
	local next_ = table.clone(state)
	next_.committed = table.clone(state.committed)
	next_.dials = table.clone(state.dials)
	next_.log = table.clone(state.log)
	return next_
end

-- A rejection (P-6, P-8): charged, logged, and the dial resetting.
local function rejected(
	state: ProcedureState,
	playerId: string,
	machineId: number,
	setting: number,
	now: number,
	reason: "wrong_setting" | "not_live"
): (ProcedureState, TurnResult)
	local actuation = state.tuning.actuation
	local next_ = copy(state)
	next_.instability += if reason == "not_live"
		then actuation.instability_per_out_of_order
		else actuation.instability_per_wrong_value
	next_.dials[machineId] = {
		setting = setting,
		rejectedUntil = now + actuation.actuation_reset_seconds,
	}
	table.insert(next_.log, {
		playerId = playerId,
		machineId = machineId,
		setting = setting,
		at = now,
		result = reason,
	})
	return next_, { kind = "rejected", machineId = machineId, reason = reason }
end

function Procedure.turn(
	state: ProcedureState,
	assignment: Ring.Assignment,
	playerId: string,
	machineId: number,
	setting: number,
	now: number,
	positions: { [string]: Vec }
): (ProcedureState, TurnResult)
	local machine = machineOf(state.facility, machineId)
	if machine == nil then
		return state, { kind = "refused", machineId = machineId, reason = "unknown_machine" }
	end
	local reason: RefusalReason? =
		refusal(state, assignment, playerId, machine, machineId, now, positions)
	if reason ~= nil then
		return state, { kind = "refused", machineId = machineId, reason = reason }
	end

	-- P-8: not_live wins over a wrong setting.
	if not Procedure.isLive(state, machineId) then
		return rejected(state, playerId, machineId, setting, now, "not_live")
	end
	if setting ~= machine.requiredSetting then
		return rejected(state, playerId, machineId, setting, now, "wrong_setting")
	end

	local next_ = copy(state)
	next_.committed[machineId] = true
	next_.dials[machineId] = { setting = setting }
	table.insert(next_.log, {
		playerId = playerId,
		machineId = machineId,
		setting = setting,
		at = now,
		result = "committed",
	})
	return next_, { kind = "committed", machineId = machineId }
end

return table.freeze(Procedure)
