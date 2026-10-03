--!strict
--[[
	SLICE-005 C-7: the scripted round. A TEST ORACLE that drives a Session
	through `Session.step` ALONE and may read the secret - the steps, the
	helpers and turners through `state.facility`, `state.assignment` and
	`Ring`, machine positions through `Machines.positionOf` - so that four to
	six scripted players can win a generated facility headlessly, lose it to
	instability, or let the clock run out at a chosen penalty level.

	Shared with SLICE-006, which extends it: the DRIVER below is generic
	(`step`, `tick`, `place`, `turn` and the facility readers), and the three
	scripts at the end are compositions of it. SLICE-006 adds pings and presets
	as further `step` calls on the same driver; nothing here needs to change for
	that.

	IT NEVER WRITES `state`. A player is "placed" by stepping a
	`PositionsSampled` whose sample puts them at a position; the sample always
	carries EVERY player the driver has placed so far, because the Contract
	(C-3) says a sample REPLACES the stored positions rather than merging into
	them. A turn is a `TurnRequested`. Time advances only through `tick`, and a
	script steps a `Tick` at least once per scripted second it spends.

	THE TRAPS C-7 NAMES. A rejected machine refuses further turns as
	`resetting` for `actuation_reset_seconds` after the rejection, so wrong
	turns on one machine are spaced at least that far apart - a "wrong turn"
	inside the window is a free refusal and instability never reaches the max.
	The finale's two turners turn at the SAME `now`, well inside
	`simultaneous_window_seconds`. The outcome is read from the MACHINE -
	`state.round.phase`, `state.round.outcome` - never only from
	`state.procedure`.

	NO ASSERTIONS LIVE HERE beyond preconditions that the script cannot proceed
	without (a facility after the deal, a turner for every machine). Those
	raise plain errors; `SessionRoundContract` catches them and names the
	criterion. Every number a script needs - the lobby length, the round
	length, the reset window, the dial range, the instability max - is READ
	from `RoundConfig.fromTuning(Tuning)` and the `MechanicsTuning` in use,
	never written as a literal.
]]

local Deep = require("./Deep")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Ring = require("../../src/server/seats/Ring")
local RoundConfig = require("../../src/server/round/RoundConfig")
local Tuning = require("../../src/shared/Tuning")

local ScriptedRound = {}

export type Session = any
export type Vec = { x: number, y: number, z: number }

export type Options = {
	tuning: any?,
	generatorPredicate: ((any) -> string?)?,
}

export type Driver = {
	S: Session,
	config: RoundConfig.RoundConfig,
	tuning: any,
	options: Options?,
	seed: number,
	players: { string },
	state: any,
	now: number,
	-- The driver's own view of where everyone is: what the last sample said.
	positions: { [string]: Vec },
	-- The `now` of the step that dealt - the Procedure's `startedAt`.
	startedAt: number?,
	steps: number,
}

export type TurnRecord = {
	playerId: string,
	machineId: number,
	setting: number,
	now: number,
	reply: any?, -- the TurnResult payload sent to the turner, or nil if none
	repliesTo: { string }, -- every playerId a TurnResult SendTo was addressed to
	effects: { any },
	phaseAfter: string,
	outcomeAfter: any?,
}

export type Unit = { kind: "step", id: number } | { kind: "finale", ids: { number } }

ScriptedRound.PLAYERS = { "ann", "bob", "cat", "dan", "eve", "fay" }
ScriptedRound.ROUND_ID = "scripted-round"
ScriptedRound.SESSION_ID = "scripted-session"

function ScriptedRound.config(): RoundConfig.RoundConfig
	return RoundConfig.fromTuning(Tuning)
end

--[[ ------------------------------------------------------------------------
     The driver.
     --------------------------------------------------------------------- ]]

-- A fresh session with `n` players NAMED but not yet joined.
function ScriptedRound.new(S: Session, seed: number, n: number, options: Options?): Driver
	local config = ScriptedRound.config()
	local tuning = if options ~= nil and options.tuning ~= nil
		then options.tuning
		else MechanicsTuning
	local state
	if options ~= nil then
		state = S.new(config, seed, ScriptedRound.ROUND_ID, ScriptedRound.SESSION_ID, options)
	else
		state = S.new(config, seed, ScriptedRound.ROUND_ID, ScriptedRound.SESSION_ID)
	end
	if typeof(state) ~= "table" or typeof(state.round) ~= "table" then
		error(`Session.new returned {Deep.show(state)}, expected a SessionState with a round`, 0)
	end
	local players: { string } = {}
	for i = 1, n do
		players[i] = ScriptedRound.PLAYERS[i]
	end
	return {
		S = S,
		config = config,
		tuning = tuning,
		options = options,
		seed = seed,
		players = players,
		state = state,
		now = 0,
		positions = {},
		startedAt = nil,
		steps = 0,
	}
end

-- One `Session.step` at the driver's `now`. The only way the state moves.
function ScriptedRound.step(d: Driver, event: any): { any }
	local after, effects = d.S.step(d.state, event, d.now)
	if typeof(after) ~= "table" or typeof(after.round) ~= "table" then
		error(
			`step {Deep.show(event)} at {d.now} returned {Deep.show(after)}, expected a SessionState with a round`,
			0
		)
	end
	if typeof(effects) ~= "table" then
		error(
			`step {Deep.show(event)} at {d.now} returned effects {Deep.show(effects)}, not a table`,
			0
		)
	end
	d.state = after
	d.steps += 1
	return effects
end

-- Advance the clock by `dt` seconds (default 1) and step a Tick.
function ScriptedRound.tick(d: Driver, dt: number?): { any }
	d.now += if dt == nil then 1 else dt
	return ScriptedRound.step(d, { kind = "Tick" })
end

-- Step a Tick at an absolute time, which must not be in the past.
function ScriptedRound.tickAt(d: Driver, at: number): { any }
	if at < d.now then
		error(`tickAt({at}) would move the clock backwards from {d.now}`, 0)
	end
	d.now = at
	return ScriptedRound.step(d, { kind = "Tick" })
end

-- One Tick per whole second from the current `now` up to and including `at`.
function ScriptedRound.tickEverySecondTo(d: Driver, at: number): { any }
	local effects: { any } = {}
	while d.now < at do
		effects = ScriptedRound.tick(d, 1)
	end
	return effects
end

-- Every named player joins at the current `now`.
function ScriptedRound.join(d: Driver)
	for _, p in d.players do
		ScriptedRound.step(d, { kind = "PlayerJoined", playerId = p })
	end
end

-- The dealing Tick, at `lobbySeconds` after the lobby was entered. Returns
-- the step's effects; records `startedAt`.
function ScriptedRound.deal(d: Driver): { any }
	local effects = ScriptedRound.tickAt(d, d.state.round.phaseEnteredAt + d.config.lobbySeconds)
	if d.state.round.phase ~= "Round" then
		error(
			`the dealing Tick at {d.now} left the machine in {tostring(d.state.round.phase)}, not Round`,
			0
		)
	end
	d.startedAt = d.now
	return effects
end

-- Join, deal, and require a facility to script against.
function ScriptedRound.start(
	S: Session,
	seed: number,
	n: number,
	options: Options?
): (Driver, { any })
	local d = ScriptedRound.new(S, seed, n, options)
	ScriptedRound.join(d)
	local effects = ScriptedRound.deal(d)
	if d.state.facility == nil then
		error(
			`state.facility is nil after the dealing step at {d.now} (AC-1: the session must hold the generated facility)`,
			0
		)
	end
	if d.state.assignment == nil then
		error(`state.assignment is nil after the dealing step at {d.now}`, 0)
	end
	return d, effects
end

-- Move players: `moves` is merged into the driver's own map, and the WHOLE
-- map is sampled, because a sample replaces the stored positions (C-3).
function ScriptedRound.place(d: Driver, moves: { [string]: Vec }): { any }
	for p, v in moves do
		d.positions[p] = { x = v.x, y = v.y, z = v.z }
	end
	return ScriptedRound.step(d, { kind = "PositionsSampled", samples = Deep.copy(d.positions) })
end

-- The TurnResult payload a step addressed to `playerId`, or nil.
function ScriptedRound.turnResultTo(effects: { any }, playerId: string): any?
	for _, e in effects do
		if
			typeof(e) == "table"
			and e.kind == "SendTo"
			and e.payloadKind == "TurnResult"
			and e.playerId == playerId
		then
			return e.payload
		end
	end
	return nil
end

-- The RoundView payload a step broadcast, or nil.
function ScriptedRound.roundView(effects: { any }): any?
	for _, e in effects do
		if typeof(e) == "table" and e.kind == "Broadcast" and e.payloadKind == "RoundView" then
			return e.payload
		end
	end
	return nil
end

-- A TurnRequested at the current `now`, recorded with what came back.
function ScriptedRound.turn(
	d: Driver,
	playerId: string,
	machineId: number,
	setting: number
): TurnRecord
	local effects = ScriptedRound.step(d, {
		kind = "TurnRequested",
		playerId = playerId,
		args = { machine = machineId, setting = setting },
	})
	local repliesTo: { string } = {}
	for _, e in effects do
		if typeof(e) == "table" and e.kind == "SendTo" and e.payloadKind == "TurnResult" then
			table.insert(repliesTo, tostring(e.playerId))
		end
	end
	return {
		playerId = playerId,
		machineId = machineId,
		setting = setting,
		now = d.now,
		reply = ScriptedRound.turnResultTo(effects, playerId),
		repliesTo = repliesTo,
		effects = effects,
		phaseAfter = d.state.round.phase,
		outcomeAfter = Deep.copy(d.state.round.outcome),
	}
end

--[[ ------------------------------------------------------------------------
     Reading the secret.
     --------------------------------------------------------------------- ]]

function ScriptedRound.machineOf(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	error(`machine {id} is not in the facility`, 0)
end

-- The holder of the machine's key class: the one seated player whose
-- `keyClasses` contains it (one, while nobody has withdrawn).
function ScriptedRound.turnerOf(assignment: any, machine: any): string
	for _, p in assignment.players do
		if table.find(assignment.keyClasses[p] or {}, machine.keyClass) ~= nil then
			return p
		end
	end
	error(`no seated player holds key class {machine.keyClass} (machine {machine.id})`, 0)
end

-- The helper: the turner's supplier, whose lens reads the turner's class.
function ScriptedRound.helperOf(assignment: any, turner: string): string
	return Ring.supplierOf(assignment, turner)
end

function ScriptedRound.machinePosition(d: Driver, machine: any): Vec
	return Machines.positionOf(d.state.facility.layout, machine, d.tuning)
end

-- The spawn room's centre, per `Machines.luau`'s header and C-2.
function ScriptedRound.spawnCentre(facility: any, tuning: any): Vec
	local pitch = tuning.instance.room_pitch_studs
	for _, room in facility.layout.rooms do
		if room.id == facility.spawnRoom then
			return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
		end
	end
	error(`spawn room {facility.spawnRoom} is not in the layout`, 0)
end

-- `Par`'s canonical order: ordinary steps interleaved T1[1], T2[1], T1[2],
-- T2[2], ..., the rest of the longer track in order, then the finale as one
-- unit.
function ScriptedRound.canonicalOrder(steps: any): { Unit }
	local units: { Unit } = {}
	local longest = 0
	for _, track in steps.tracks do
		longest = math.max(longest, #track - 1)
	end
	for i = 1, longest do
		for _, track in steps.tracks do
			if i <= #track - 1 then
				table.insert(units, { kind = "step", id = track[i] })
			end
		end
	end
	table.insert(units, { kind = "finale", ids = table.clone(steps.finale) })
	return units
end

-- A setting in 1..dial_settings that is not `required`.
function ScriptedRound.wrongSetting(d: Driver, required: number): number
	local dials = d.tuning.instance.dial_settings
	return (required % dials) + 1
end

function ScriptedRound.outcome(d: Driver): { phase: string, outcome: any? }
	return { phase = d.state.round.phase, outcome = Deep.copy(d.state.round.outcome) }
end

--[[ ------------------------------------------------------------------------
     The scripts.
     --------------------------------------------------------------------- ]]

export type WinRun = {
	seed: number,
	n: number,
	fromSpawn: boolean,
	turns: { TurnRecord },
	-- The record of the turn that completed the Procedure (the last one).
	completing: TurnRecord,
	-- After the Tick that follows the completing turn.
	afterNextTick: { phase: string, outcome: any? },
	-- For the control only: the ticks that end the round by the clock.
	clock: {
		deadline: number,
		phaseOneSecondBefore: string,
		phaseAtDeadline: string,
		outcomeAtDeadline: any?,
	}?,
}

--[[
	For each unit in canonical order, place the helper and the turner at the
	machine (or, with `fromSpawn`, leave everyone at the spawn room's centre)
	and turn it to its required setting. The finale's two turners turn at the
	same `now`. With `fromSpawn`, after every turn has been refused the clock
	is run out coarsely: one Tick a second before the deadline, one on it.
]]
local function playThrough(
	S: Session,
	seed: number,
	n: number,
	fromSpawn: boolean,
	options: Options?
): WinRun
	local d = ScriptedRound.start(S, seed, n, options)
	local facility = d.state.facility
	local assignment = d.state.assignment
	local centre = ScriptedRound.spawnCentre(facility, d.tuning)
	local turns: { TurnRecord } = {}

	if fromSpawn then
		local everyone: { [string]: Vec } = {}
		for _, p in d.players do
			everyone[p] = centre
		end
		ScriptedRound.place(d, everyone)
	end

	local function placePair(id: number): (any, string)
		local m = ScriptedRound.machineOf(facility, id)
		local turner = ScriptedRound.turnerOf(assignment, m)
		local helper = ScriptedRound.helperOf(assignment, turner)
		if not fromSpawn then
			local at = ScriptedRound.machinePosition(d, m)
			ScriptedRound.place(d, { [turner] = at, [helper] = at })
		end
		return m, turner
	end

	for _, unit in ScriptedRound.canonicalOrder(facility.steps) do
		if unit.kind == "step" then
			local m, turner = placePair(unit.id)
			ScriptedRound.tick(d, 1)
			table.insert(turns, ScriptedRound.turn(d, turner, unit.id, m.requiredSetting))
		else
			local pairs_: { { any } } = {}
			for _, id in unit.ids do
				local m, turner = placePair(id)
				table.insert(pairs_, { m, turner })
			end
			ScriptedRound.tick(d, 1)
			for _, pair in pairs_ do
				local m, turner = pair[1], pair[2]
				table.insert(turns, ScriptedRound.turn(d, turner, m.id, m.requiredSetting))
			end
		end
	end

	local completing = turns[#turns]
	ScriptedRound.tick(d, 1)
	local afterNextTick = ScriptedRound.outcome(d)

	local clock = nil
	if fromSpawn then
		local deadline = (d.startedAt :: number) + d.config.roundSeconds
		ScriptedRound.tickAt(d, deadline - 1)
		local before = d.state.round.phase
		ScriptedRound.tickAt(d, deadline)
		clock = {
			deadline = deadline,
			phaseOneSecondBefore = before,
			phaseAtDeadline = d.state.round.phase,
			outcomeAtDeadline = Deep.copy(d.state.round.outcome),
		}
	end

	return {
		seed = seed,
		n = n,
		fromSpawn = fromSpawn,
		turns = turns,
		completing = completing,
		afterNextTick = afterNextTick,
		clock = clock,
	}
end

function ScriptedRound.win(S: Session, seed: number, n: number, options: Options?): WinRun
	return playThrough(S, seed, n, false, options)
end

-- AC-4's control: the same script with every turn sent from the spawn room.
function ScriptedRound.winFromSpawn(S: Session, seed: number, n: number, options: Options?): WinRun
	return playThrough(S, seed, n, true, options)
end

export type WrongTurn = {
	j: number,
	turn: TurnRecord,
	-- The Tick one second after the turn, for the first `instability_max - 1`
	-- wrong turns: the penalised RoundView and an unpenalised twin's at the
	-- same `now`.
	nextTick: { now: number, secondsLeft: any?, unpenalisedSecondsLeft: any? }?,
}

export type LoseRun = {
	seed: number,
	n: number,
	machineId: number,
	turner: string,
	wrongTurns: { WrongTurn },
	final: { phase: string, outcome: any? },
}

-- Charge `k` points: `k` wrong turns on the first live step by its turner,
-- spaced `actuation_reset_seconds` apart with a Tick every second between.
-- `onTurn` sees each record; `twin`, when given, is ticked in lockstep.
local function chargeWrongTurns(
	d: Driver,
	k: number,
	twin: Driver?,
	onTurn: ((j: number, turn: TurnRecord) -> ())?
)
	local facility = d.state.facility
	local id = facility.steps.tracks[1][1]
	local m = ScriptedRound.machineOf(facility, id)
	local turner = ScriptedRound.turnerOf(d.state.assignment, m)
	ScriptedRound.place(d, { [turner] = ScriptedRound.machinePosition(d, m) })
	local wrong = ScriptedRound.wrongSetting(d, m.requiredSetting)
	local reset = d.tuning.actuation.actuation_reset_seconds
	for j = 1, k do
		ScriptedRound.tick(d, 1)
		if twin then
			ScriptedRound.tick(twin, 1)
		end
		local turn = ScriptedRound.turn(d, turner, id, wrong)
		if onTurn then
			onTurn(j, turn)
		end
		if j < k then
			-- Space the next wrong turn a whole reset window away.
			for _ = 1, reset - 1 do
				ScriptedRound.tick(d, 1)
				if twin then
					ScriptedRound.tick(twin, 1)
				end
			end
		end
	end
	return id, turner
end

--[[
	Turn the live step to a wrong setting `instability_max` times, spaced a
	reset window apart. After each of the first `instability_max - 1` the next
	second's Tick is recorded beside an unpenalised twin session (same seed,
	same n, ticked in lockstep, never turned) at the same `now`.
]]
function ScriptedRound.loseByInstability(
	S: Session,
	seed: number,
	n: number,
	options: Options?
): LoseRun
	local d = ScriptedRound.start(S, seed, n, options)
	local twin = ScriptedRound.start(S, seed, n, options)
	local max = d.tuning.actuation.instability_max
	local wrongTurns: { WrongTurn } = {}

	local id, turner = chargeWrongTurns(d, max, twin, function(j: number, turn: TurnRecord)
		local record: WrongTurn = { j = j, turn = turn, nextTick = nil }
		if j < max then
			local effects = ScriptedRound.tick(d, 1)
			local twinEffects = ScriptedRound.tick(twin, 1)
			local view = ScriptedRound.roundView(effects)
			local twinView = ScriptedRound.roundView(twinEffects)
			record.nextTick = {
				now = d.now,
				secondsLeft = if view then view.secondsLeft else nil,
				unpenalisedSecondsLeft = if twinView then twinView.secondsLeft else nil,
			}
			-- `chargeWrongTurns` adds `reset - 1` ticks and one more before the
			-- next turn; with this tick the wrong turns are `reset + 1` seconds
			-- apart, which is still at least a whole reset window.
		end
		table.insert(wrongTurns, record)
	end)

	return {
		seed = seed,
		n = n,
		machineId = id,
		turner = turner,
		wrongTurns = wrongTurns,
		final = ScriptedRound.outcome(d),
	}
end

export type ClockRun = {
	seed: number,
	n: number,
	k: number,
	startedAt: number,
	-- The phase machine's own backstop: startedAt + roundSeconds.
	backstopAt: number,
	-- The first tick at which the machine left Round, or nil if it never did
	-- before (and including) the backstop.
	resolvedAt: number?,
	phaseOneSecondBefore: string?,
	-- The phase at `resolvedAt`: Resolution when the machine took the Tick
	-- before the Procedure's outcome reached it (C-3), Post when it did not.
	phaseAtResolution: string?,
	outcome: any?,
	reachedBackstop: boolean,
}

--[[
	Charge `k` points through real wrong turns, then do nothing but tick once
	a second until the machine leaves Round or the backstop's tick has been
	taken. With `k >= 1` the Procedure's deadline comes first.
]]
function ScriptedRound.clockOut(
	S: Session,
	seed: number,
	n: number,
	k: number,
	options: Options?
): ClockRun
	local d = ScriptedRound.start(S, seed, n, options)
	local startedAt = d.startedAt :: number
	if k > 0 then
		chargeWrongTurns(d, k, nil, nil)
	end
	local backstopAt = startedAt + d.config.roundSeconds
	local resolvedAt: number? = nil
	local phaseBefore: string? = nil
	local phaseAtResolution: string? = nil
	local reachedBackstop = false
	while d.state.round.phase == "Round" and d.now < backstopAt do
		phaseBefore = d.state.round.phase
		ScriptedRound.tick(d, 1)
		if d.now >= backstopAt then
			reachedBackstop = true
		end
		if d.state.round.phase ~= "Round" then
			resolvedAt = d.now
			phaseAtResolution = d.state.round.phase
		end
	end
	return {
		seed = seed,
		n = n,
		k = k,
		startedAt = startedAt,
		backstopAt = backstopAt,
		resolvedAt = resolvedAt,
		phaseOneSecondBefore = phaseBefore,
		phaseAtResolution = phaseAtResolution,
		outcome = Deep.copy(d.state.round.outcome),
		reachedBackstop = reachedBackstop,
	}
end

return ScriptedRound
