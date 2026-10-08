--!strict
--[[
	The Procedure in play, per PROC-001, PROC-002 and
	`docs/wiki/game/mechanics.md` §1, §3.2, §5 (G12): a turn commits a live
	step on the right setting and says why it failed otherwise, and the finale
	commits only when both its machines are turned inside one window.

	LIVENESS (P-3, F-3). An ordinary step is live when it is the first
	uncommitted step of its track and is not that track's last entry. The two
	finale steps (`steps.finale`, each track's last entry) go live together
	once every ordinary step of every track is committed
	(`finale_live_together`); an armed finale machine is still live. Decoys,
	committed machines and unknown ids are never live.

	A TURN IS REFUSED OR EVALUATED. The refusals run in this order and the
	first failure wins: `round_over` (I-7), `unknown_machine`,
	`not_key_holder`, `out_of_reach`, `committed`, `resetting`, `armed`. A
	refused turn is free: it returns the state it was handed, unchanged (save
	an expiry or the clock ending the round in the same call, F-9 and I-6),
	and writes no log entry. An evaluated turn
	commits a live step on its required setting; anything else is rejected as
	`not_live` (a waiting step or a decoy, whatever the setting - P-8) or
	`wrong_setting`, charged that reason's constant, logged, and the dial shows
	the rejected setting until `actuation_reset_seconds` have passed
	(half-open, P-6).

	THE FINALE (F-4..F-9). A correct turn on a live finale machine with no
	window open ARMS it, opening a window to `now +
	simultaneous_window_seconds`. A correct turn on the other machine at or
	before that end commits both. A wrong turn on the other machine is an
	ordinary rejection that also disarms the armed one, with no second charge.
	A window past its end (strictly) disarms the armed machine and charges
	`instability_per_failed_pair`: `tick` applies that, and so does `turn`,
	before judging the turn, so a late turn cannot commit the finale.

	THE ROUND ENDS HERE (PROC-003, I-1..I-10). The deadline is `startedAt +
	roundSeconds - penaltySeconds`, and the clock is out at `now >= deadline`.
	Every point charged, by any path, costs `instability_clock_penalty_seconds`
	and may cross a multiple of `instability_blackout_threshold` below
	`instability_max`, each crossing darkening `blackout_rooms_per_threshold`
	rooms by a weighted draw (I-5). One event resolves in a fixed order: a
	decided round answers nothing (`round_over`); an expired window is charged;
	the clock is read; the turn is evaluated. After any charge, instability at
	the max is checked before the clock, and a completing commit wins.

	The blackout stream is never held in the state (I-1): a draw rebuilds
	`Rng.fromSeed(roundSeed):derive("blackout")` and skips the `blackoutDraws`
	values already used, so every copy of a state draws the same k-th value.

	TUNING LIVES IN THE STATE (P-1). `start` stores the tuning it is handed and
	every constant is read from `state.tuning`, never from `MechanicsTuning`.

	PURE (D3). No module state, no Roblox API, and no argument is ever mutated.
	Every evaluated turn returns a new state whose `committed`, `dials` and
	`log` are fresh tables; the facility and tuning are shared, read-only.
]]

local Generator = require("../facility/Generator")
local Machines = require("../facility/Machines")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local PhaseMachine = require("../round/PhaseMachine")
local Ring = require("../seats/Ring")
local Rng = require("@game/ReplicatedStorage/Shared/Rng")

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
			| "armed"
			| "round_over",
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
	-- The open finale window, or nil when none is (F-1).
	armed: { machineId: number, closesAt: number }?,
	startedAt: number,
	roundSeconds: number,
	-- Points charged x `instability_clock_penalty_seconds` (I-3).
	penaltySeconds: number,
	-- Layout room id -> dark. Never cleared (I-9).
	dark: { [number]: boolean },
	outcome: PhaseMachine.Outcome?,
	roundSeed: number,
	-- Values already drawn from the blackout stream (I-1).
	blackoutDraws: number,
}

type RefusalReason = "not_key_holder" | "out_of_reach" | "committed" | "resetting" | "armed"

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
	now: number,
	tuning: MechanicsTuning.MechanicsTuning,
	roundSeed: number,
	roundSeconds: number
): ProcedureState
	return {
		facility = facility,
		committed = {},
		dials = {},
		instability = 0,
		log = {},
		tuning = tuning,
		startedAt = now,
		roundSeconds = roundSeconds,
		penaltySeconds = 0,
		dark = {},
		roundSeed = roundSeed,
		blackoutDraws = 0,
	}
end

-- I-3: the round's deadline; the clock is out at `now >= deadline`.
function Procedure.deadline(state: ProcedureState): number
	return state.startedAt + state.roundSeconds - state.penaltySeconds
end

-- I-9: false for a lit room and for an unknown id.
function Procedure.isDark(state: ProcedureState, room: number): boolean
	return state.dark[room] == true
end

-- Every ordinary step (all but each track's last entry) committed (F-3).
local function ordinaryDone(state: ProcedureState): boolean
	for _, track in state.facility.steps.tracks do
		for k = 1, #track - 1 do
			if not state.committed[track[k]] then
				return false
			end
		end
	end
	return true
end

function Procedure.isLive(state: ProcedureState, machineId: number): boolean
	for _, track in state.facility.steps.tracks do
		for k, id in track do
			if not state.committed[id] then
				-- The first uncommitted step of this track. An ordinary step is
				-- live; the finale step, the track's last entry, waits on the
				-- ordinary steps of every track.
				if id == machineId then
					return k < #track or ordinaryDone(state)
				end
				break
			end
		end
	end
	return false
end

-- The finale is live: both its steps, or neither (F-3).
local function finaleLive(state: ProcedureState): boolean
	local finale = state.facility.steps.finale
	return Procedure.isLive(state, finale[1]) and Procedure.isLive(state, finale[2])
end

function Procedure.isComplete(state: ProcedureState): boolean
	for _, track in state.facility.steps.tracks do
		for _, id in track do
			if not state.committed[id] then
				return false
			end
		end
	end
	return true
end

-- I-5: every lit room -> the sum over its uncommitted track machines of the
-- live weight (armed included) or the waiting weight. Decoys weigh 0, and a
-- lit room with nothing to weigh is present at 0.
function Procedure.blackoutWeights(state: ProcedureState): { [number]: number }
	local actuation = state.tuning.actuation
	local weights: { [number]: number } = {}
	for _, room in state.facility.layout.rooms do
		if not state.dark[room.id] then
			weights[room.id] = 0
		end
	end
	for _, track in state.facility.steps.tracks do
		for _, id in track do
			local m = machineOf(state.facility, id)
			if m ~= nil and weights[m.room] ~= nil and not state.committed[id] then
				weights[m.room] += if Procedure.isLive(state, id)
					then actuation.blackout_weight_live_step
					else actuation.blackout_weight_waiting_step
			end
		end
	end
	return weights
end

-- I-5: one `nextInteger` per non-nil draw. Rooms in ascending id; with a
-- positive total the first whose cumulative weight reaches the draw (so a
-- zero-weight room is never returned), otherwise uniform among them.
function Procedure.drawRoom(weights: { [number]: number }, rng: Rng.Rng): number?
	local rooms: { number } = {}
	local total = 0
	for room, w in weights do
		table.insert(rooms, room)
		total += w
	end
	if #rooms == 0 then
		return nil
	end
	table.sort(rooms)
	if total <= 0 then
		return rooms[rng:nextInteger(1, #rooms)]
	end
	local r = rng:nextInteger(1, total)
	local cumulative = 0
	for _, room in rooms do
		cumulative += weights[room]
		if cumulative >= r then
			return room
		end
	end
	return nil
end

-- I-1: the blackout stream as it stands after this state's draws.
local function blackoutStream(state: ProcedureState): Rng.Rng
	local rng = Rng.fromSeed(state.roundSeed):derive("blackout")
	for _ = 1, state.blackoutDraws do
		rng:nextNumber()
	end
	return rng
end

-- I-3, I-4 and I-6's post-charge check, on a fresh copy `next_`: the clock
-- penalty, every crossing below the max in ascending order, then instability
-- at the max before the clock (read after the penalty).
local function charge(next_: ProcedureState, points: number, now: number)
	local actuation = next_.tuning.actuation
	local old = next_.instability
	next_.instability += points
	next_.penaltySeconds += points * actuation.instability_clock_penalty_seconds
	for v = old + 1, next_.instability do
		if v % actuation.instability_blackout_threshold == 0 and v < actuation.instability_max then
			for _ = 1, actuation.blackout_rooms_per_threshold do
				local room =
					Procedure.drawRoom(Procedure.blackoutWeights(next_), blackoutStream(next_))
				if room == nil then
					break
				end
				next_.dark[room] = true
				next_.blackoutDraws += 1
			end
		end
	end
	if next_.instability >= actuation.instability_max then
		next_.outcome = { result = "lost", reason = "instability" }
	elseif now >= Procedure.deadline(next_) then
		next_.outcome = { result = "lost", reason = "clock" }
	end
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

-- Horizontal distance to `Machines.positionOf`, inclusive of `range` (P-4).
local function within(
	state: ProcedureState,
	machine: Machines.Machine,
	position: Vec?,
	range: number
): boolean
	if position == nil then
		return false
	end
	local m = Machines.positionOf(state.facility.layout, machine, state.tuning)
	local dx = position.x - m.x
	local dz = position.z - m.z
	return math.sqrt(dx * dx + dz * dz) <= range
end

local function inReach(state: ProcedureState, machine: Machines.Machine, position: Vec?): boolean
	return within(state, machine, position, state.tuning.instance.turn_range_studs)
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
	if state.armed ~= nil and state.armed.machineId == machineId then
		return "armed"
	end
	return nil
end

-- A new state sharing no writable table with `state`.
local function copy(state: ProcedureState): ProcedureState
	local next_ = table.clone(state)
	next_.committed = table.clone(state.committed)
	next_.dials = table.clone(state.dials)
	next_.log = table.clone(state.log)
	next_.dark = table.clone(state.dark)
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
	charge(
		next_,
		if reason == "not_live"
			then actuation.instability_per_out_of_order
			else actuation.instability_per_wrong_value,
		now
	)
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

-- Close the open window: the armed machine's dial shows its setting rejected
-- until `actuation_reset_seconds` after `now` (F-7, F-8). Mutates `next_`, a
-- fresh copy; charges nothing and logs nothing.
local function disarm(next_: ProcedureState, now: number)
	local armed = next_.armed
	if armed == nil then
		return
	end
	local d = next_.dials[armed.machineId]
	next_.dials[armed.machineId] = {
		setting = if d then d.setting else nil,
		rejectedUntil = now + next_.tuning.actuation.actuation_reset_seconds,
	}
	next_.armed = nil
end

-- The state with a window past its end (strictly - the end is inclusive)
-- closed and `instability_per_failed_pair` charged; otherwise `state` (F-8).
local function expire(state: ProcedureState, now: number): ProcedureState
	if state.armed == nil or now <= state.armed.closesAt then
		return state
	end
	local next_ = copy(state)
	disarm(next_, now)
	charge(next_, state.tuning.actuation.instability_per_failed_pair, now)
	return next_
end

-- I-6 steps 2 and 3 on an undecided round: expire an open window, then end
-- the round by the clock if nothing has ended it yet.
local function settle(state: ProcedureState, now: number): ProcedureState
	state = expire(state, now)
	if state.outcome == nil and now >= Procedure.deadline(state) then
		state = copy(state)
		state.outcome = { result = "lost", reason = "clock" }
	end
	return state
end

function Procedure.tick(
	state: ProcedureState,
	_assignment: Ring.Assignment,
	now: number,
	_positions: { [string]: Vec }
): (ProcedureState, PhaseMachine.Outcome?)
	-- I-6 step 1: a decided round stays decided (AC-7).
	if state.outcome == nil then
		state = settle(state, now)
	end
	return state, state.outcome
end

-- Finale machine id -> lit: the partner machine's key holder is within
-- `partner_lamp_range_studs` of the PARTNER machine, while the finale is live
-- (F-11).
function Procedure.partnerLamps(
	state: ProcedureState,
	assignment: Ring.Assignment,
	positions: { [string]: Vec }
): { [number]: boolean }
	local finale = state.facility.steps.finale
	local live = finaleLive(state)
	local range = state.tuning.instance.partner_lamp_range_studs
	local lamps: { [number]: boolean } = {}
	for i, id in finale do
		local partner = machineOf(state.facility, finale[3 - i])
		local lit = false
		if live and partner ~= nil then
			for playerId, position in positions do
				if
					holds(assignment, playerId, partner.keyClass)
					and within(state, partner, position, range)
				then
					lit = true
					break
				end
			end
		end
		lamps[id] = lit
	end
	return lamps
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
	-- I-6 step 1: a decided round answers nothing, before any other refusal.
	if state.outcome ~= nil then
		return state, { kind = "refused", machineId = machineId, reason = "round_over" }
	end
	-- F-9: a window that ended before this turn closes first, whatever the
	-- turn turns out to be; every result below is judged against that state.
	-- Then the clock (I-6 steps 2, 3): a turn on a round that just ended is
	-- refused like one on a round that ended earlier.
	state = settle(state, now)
	if state.outcome ~= nil then
		return state, { kind = "refused", machineId = machineId, reason = "round_over" }
	end

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
		-- F-7: with a window open this is the other finale machine (the armed
		-- one was refused above); the window closes, charged only once.
		local next_, result = rejected(state, playerId, machineId, setting, now, "wrong_setting")
		disarm(next_, now)
		return next_, result
	end

	local next_ = copy(state)
	local result: TurnResult = { kind = "committed", machineId = machineId }
	local logged: "committed" | "armed" = "committed"
	if table.find(state.facility.steps.finale, machineId) == nil then
		next_.committed[machineId] = true
	elseif state.armed == nil then
		-- F-4: the first finale machine arms and opens the window.
		next_.armed = {
			machineId = machineId,
			closesAt = now + state.tuning.instance.simultaneous_window_seconds,
		}
		result = { kind = "armed", machineId = machineId }
		logged = "armed"
	else
		-- F-5: the other one, inside the window, commits both together.
		next_.committed[state.armed.machineId] = true
		next_.committed[machineId] = true
		next_.armed = nil
	end
	next_.dials[machineId] = { setting = setting }
	table.insert(next_.log, {
		playerId = playerId,
		machineId = machineId,
		setting = setting,
		at = now,
		result = logged,
	})
	-- I-6 step 4: a commit charges nothing, so the win is decided first.
	if Procedure.isComplete(next_) then
		next_.outcome = { result = "won", reason = "procedure_complete" }
	end
	return next_, result
end

return table.freeze(Procedure)
