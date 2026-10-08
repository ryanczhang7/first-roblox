--!strict
--[[
	SLICE-005 AC-1..AC-6 and the story's Contract pins (C-1..C-5), written once
	as checks over a SESSION MODULE handed in as a parameter - the
	`SessionContract` arrangement, for the same reason: in RED the real module
	lacks every behaviour below, so `tests/server/session_round_test.luau` fails
	before any assertion here has been seen to accept or reject anything, and
	`tests/server/session_round_controls_test.luau` is where each check is
	EXECUTED against a reference stand-in and stand-ins wrong in exactly one
	way.

	THE ORACLE IS THE PURE MODULES THEMSELVES, STEPPED HERE, INDEPENDENTLY.
	`run` drives a plan through the session under test and, beside it, through
	the Contract's own composition of `PhaseMachine`, `Ring`, `Generator`,
	`Procedure` and `TurnRequests` (C-2, C-3): the facility is
	`Generator.generate(dealt, deal.seed, tuning, predicate)` for THAT
	AssignSeats effect, the Procedure is `Procedure.start(facility, now,
	tuning, deal.seed, config.roundSeconds)`, a turn is `TurnRequests.handle`
	on the stored positions, a Tick is `Procedure.tick`, and an outcome that
	appears is fed to the machine as `RoundResolved` in the same step. Nothing
	below reads an expected value off the session's own output.

	THE ORACLE PARTITION (story C-10). MECHANICAL, pinned exactly against the
	modules' outputs: AC-1, AC-2, AC-3, AC-6's deadline arithmetic, and
	C-3/C-4/C-5. SETTLED, a scripted outcome with a control that must fail:
	AC-4 (`ScriptedRound.win`, control `winFromSpawn`) and AC-5
	(`ScriptedRound.loseByInstability`). No check invents a metric. Every
	duration, count and penalty is READ from `RoundConfig.fromTuning(Tuning)`
	and `MechanicsTuning`; the only literals below are seeds, player names and
	sample coordinates.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Generator = require("../../src/server/facility/Generator")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PhaseMachine = require("../../src/server/round/PhaseMachine")
local Procedure = require("../../src/server/procedure/Procedure")
local Projection = require("../../src/server/seats/Projection")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local RoundConfig = require("../../src/server/round/RoundConfig")
local ScriptedRound = require("./ScriptedRound")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")
local TurnRequests = require("../../src/server/procedure/TurnRequests")

local SessionRoundContract = {}

export type Session = any

SessionRoundContract.SEED = 20261002
SessionRoundContract.ROUND_ID = "round-1"
SessionRoundContract.SESSION_ID = "session-A"
SessionRoundContract.PLAYERS = { "ann", "bob", "cat", "dan", "eve", "fay" }
SessionRoundContract.STRANGER = "zed"

-- AC-4's sweep: seeds 1..SEEDS at each n. C-8 measured generation success for
-- seeds 1-300 at n = 4, 5, 6; RED re-measured 1-50 (150/150) before relying on it.
SessionRoundContract.SEEDS = 50
SessionRoundContract.PLAYER_COUNTS = { 4, 5, 6 }
-- AC-5 and AC-6 are per-round properties with no distribution to sweep; a
-- handful of seeds at each n is enough to show they do not depend on one layout.
SessionRoundContract.LOSS_SEEDS = { 1, 2, 3 }

-- SLICE-006 C-2: the sight port every plan and script here runs with. A
-- constant true - headlessly there is no geometry to cast a ray through.
SessionRoundContract.PORTS = ScriptedRound.PORTS

SessionRoundContract.PLACED_KEYS = { "kind", "playerId", "position" }
SessionRoundContract.SEND_TO_KEYS = { "kind", "payload", "payloadKind", "playerId" }
SessionRoundContract.VEC_KEYS = { "x", "y", "z" }

-- The predicate AC-2 injects: refuses every attempt.
function SessionRoundContract.refuseAll(_facility: any): string?
	return "test:refused_by_predicate"
end

function SessionRoundContract.config(): RoundConfig.RoundConfig
	return RoundConfig.fromTuning(Tuning)
end

function SessionRoundContract.tuning(): any
	return MechanicsTuning
end

--[[ ------------------------------------------------------------------------
     Small instruments.
     --------------------------------------------------------------------- ]]

local function keysOf(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end
SessionRoundContract.keysOf = keysOf

local function ofKind(effects: { any }, kind: string, payloadKind: string?): { any }
	local out: { any } = {}
	for _, e in effects do
		if
			typeof(e) == "table"
			and e.kind == kind
			and (payloadKind == nil or e.payloadKind == payloadKind)
		then
			table.insert(out, e)
		end
	end
	return out
end

function SessionRoundContract.placedOf(effects: { any }): { any }
	return ofKind(effects, "Placed")
end

function SessionRoundContract.turnResultsOf(effects: { any }): { any }
	return ofKind(effects, "SendTo", "TurnResult")
end

function SessionRoundContract.seatViewsOf(effects: { any }): { any }
	return ofKind(effects, "SendTo", "SeatView")
end

function SessionRoundContract.roundViewsOf(effects: { any }): { any }
	return ofKind(effects, "Broadcast", "RoundView")
end

-- The spawn room's centre per C-2 and `Machines.luau`'s header.
function SessionRoundContract.spawnCentre(
	facility: any,
	tuning: any
): { x: number, y: number, z: number }
	return ScriptedRound.spawnCentre(facility, tuning)
end

local function contains(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local function requireModule(criterion: string, S: any)
	if typeof(S) ~= "table" then
		Contract.fail(`{criterion}: Session is {Deep.show(S)}, not a module table`)
	end
	for _, name in { "new", "step" } do
		if typeof(S[name]) ~= "function" then
			Contract.fail(`{criterion}: Session.{name} is {typeof(S[name])}, expected a function`)
		end
	end
end

--[[ ------------------------------------------------------------------------
     The oracle: the Contract's composition, stepped independently.
     --------------------------------------------------------------------- ]]

export type Oracle = {
	round: any,
	assignment: any?,
	facility: any?,
	procedure: any?,
	positions: { [string]: any },
	-- VIEW-004: the last accepted sample or placement per player, and when.
	-- Internal to the oracle; `tracks` on the subject is pinned by
	-- `PositionsContract`, not here.
	baselines: { [string]: { at: any, now: number } },
}

--[[
	VIEW-004: the oracle's sample rule, TOLERANCE-FREE. A sample is accepted
	iff the player has a baseline (the deal placed them) and the horizontal
	move from it is reachable at BARE walk speed over the elapsed time -
	`distance <= walkSpeed x dt`, no tolerance, no slack. That is strictly
	tighter than the Contract's bound for any TOLERANCE >= 1 and SLACK_STUDS
	>= 0, so every sample the plans below offer is accepted under the real
	constants whatever they are, and the oracle never needs to read them. A
	plan sample that is NOT reachable at bare walk speed is a precondition
	failure, not a refusal: the implausible cases live in `PositionsContract`,
	where the constants are read from the module. Players absent from a batch
	keep their position (a merge); a player with no baseline is absent.
]]
local function horizontalDistance(a: any, b: any): number
	local dx = b.x - a.x
	local dz = b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

local function acceptSamples(
	o: Oracle,
	samples: { [string]: any },
	now: number,
	tuning: any
): ({ [string]: any }, { [string]: { at: any, now: number } })
	local walkSpeed = tuning.instance.walk_speed_studs_per_second
	local positions = Deep.copy(o.positions)
	local baselines = table.clone(o.baselines)
	for p, v in samples do
		local base = baselines[p]
		if base == nil then
			continue
		end
		local dt = math.max(0, now - base.now)
		local d = horizontalDistance(base.at, v)
		if d > walkSpeed * dt then
			error(
				`plan precondition: the sample for {p} at {now} moves {d} studs in {dt} s, which is not reachable at bare walk speed {walkSpeed}; the plans must stay tolerance-free`,
				0
			)
		end
		positions[p] = { x = v.x, y = v.y, z = v.z }
		baselines[p] = { at = { x = v.x, y = v.y, z = v.z }, now = now }
	end
	return positions, baselines
end

export type Meta = {
	assign: any?, -- the AssignSeats effect on a dealing step
	dealt: any?, -- the ring dealt on that step
	generationFailed: boolean,
	placed: { any }, -- expected Placed effects, seat order
	centre: any?, -- the spawn centre on a successful deal
	seatViews: { string }, -- recipients of SeatView sends, in order
	turn: { playerId: string, procedureAfter: any, result: any, reply: any }?, -- a handled turn
	ignoredTurn: boolean, -- a TurnRequested outside Round / with no procedure
	sampled: boolean, -- a PositionsSampled
	ticked: boolean, -- Procedure.tick ran on this step
	routed: boolean, -- an outcome was fed to the machine this step
	entersLobby: boolean,
	wantsRoundView: boolean,
	passThrough: { any }, -- the machine's effects, every machine step, minus AssignSeats
	expectedEffects: { any }, -- the whole effect list the Contract says this step emits
	expectedSecondsLeft: any?, -- the RoundView's secondsLeft, when one is wanted
}

local function passInto(into: { any }, effects: { any })
	for _, e in effects do
		if e.kind ~= "AssignSeats" then
			table.insert(into, e)
		end
	end
end

local function seatView(assignment: any, playerId: string): any
	return {
		kind = "SendTo",
		playerId = playerId,
		payloadKind = "SeatView",
		payload = Projection.forPlayer(assignment, playerId),
	}
end

-- C-5: the Procedure's deadline in Round with a procedure; SLICE-003's
-- formula everywhere else. VIEW-003 C-7 clamps every non-nil value at 0;
-- no step of this plan reaches a negative value (a Round past its deadline
-- is resolved in the same step), so the clamp changes no number here.
local function secondsLeftOf(o: Oracle, now: number, config: RoundConfig.RoundConfig): number?
	local round = o.round
	if round.phase == "Round" and o.procedure ~= nil then
		return math.max(0, math.ceil(Procedure.deadline(o.procedure) - now))
	end
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
	return math.max(0, math.ceil(duration - (now - round.phaseEnteredAt)))
end

local function roundViewOf(o: Oracle, now: number, config: RoundConfig.RoundConfig): any
	return {
		kind = "Broadcast",
		payloadKind = "RoundView",
		payload = {
			phase = o.round.phase,
			secondsLeft = secondsLeftOf(o, now, config),
			players = table.clone(o.round.players),
			playersMin = config.playersMin,
			playersMax = config.playersMax,
		},
	}
end

local function newMeta(): Meta
	return {
		assign = nil,
		dealt = nil,
		generationFailed = false,
		placed = {},
		centre = nil,
		seatViews = {},
		turn = nil,
		ignoredTurn = false,
		sampled = false,
		ticked = false,
		routed = false,
		entersLobby = false,
		wantsRoundView = false,
		passThrough = {},
		expectedEffects = {},
		expectedSecondsLeft = nil,
	}
end

-- One Contract step of the oracle. Returns the new oracle state and what the
-- Contract says the step emits, piece by piece.
local function oracleStep(
	o: Oracle,
	event: any,
	now: number,
	config: RoundConfig.RoundConfig,
	tuning: any,
	predicate: any
): (Oracle, Meta)
	local meta = newMeta()

	if event.kind == "SeatsAssigned" then
		return o, meta
	end

	if event.kind == "PositionsSampled" then
		meta.sampled = true
		local positions, baselines = acceptSamples(o, event.samples, now, tuning)
		return {
			round = o.round,
			assignment = o.assignment,
			facility = o.facility,
			procedure = o.procedure,
			positions = positions,
			baselines = baselines,
		},
			meta
	end

	if event.kind == "TurnRequested" then
		if o.procedure == nil or o.round.phase ~= "Round" then
			meta.ignoredTurn = true
			return o, meta
		end
		local procedure, result = TurnRequests.handle(
			o.procedure,
			o.assignment,
			event.playerId,
			event.args,
			now,
			o.positions
		)
		local round = o.round
		local effects: { any } = {}
		if o.procedure.outcome == nil and procedure.outcome ~= nil then
			local resolved, more = PhaseMachine.step(
				round,
				{ kind = "RoundResolved", outcome = procedure.outcome },
				now
			)
			round = resolved
			passInto(effects, more)
			passInto(meta.passThrough, more)
			meta.routed = true
		end
		local reply = TurnRequests.reply(result)
		meta.turn = {
			playerId = event.playerId,
			procedureAfter = procedure,
			result = result,
			reply = reply,
		}
		table.insert(effects, {
			kind = "SendTo",
			playerId = event.playerId,
			payloadKind = "TurnResult",
			payload = reply,
		})
		local next_: Oracle = {
			round = round,
			assignment = o.assignment,
			facility = o.facility,
			procedure = procedure,
			positions = o.positions,
			baselines = o.baselines,
		}
		meta.wantsRoundView = round.phase ~= o.round.phase
		if meta.wantsRoundView then
			local view = roundViewOf(next_, now, config)
			meta.expectedSecondsLeft = view.payload.secondsLeft
			table.insert(effects, view)
		end
		meta.expectedEffects = effects
		return next_, meta
	end

	-- Every other event goes to the machine first, as SLICE-003 does.
	local before = o.round
	local round, machineEffects = PhaseMachine.step(before, event, now)
	local effects: { any } = {}
	passInto(effects, machineEffects)
	passInto(meta.passThrough, machineEffects)

	local assignment, facility, procedure, positions =
		o.assignment, o.facility, o.procedure, o.positions
	local baselines = o.baselines
	local sends: { any } = {}

	local deal: any = nil
	for _, e in machineEffects do
		if e.kind == "AssignSeats" then
			deal = e
		end
	end

	if deal ~= nil then
		local dealt = Ring.assign(deal.players, Rng.fromSeed(deal.seed))
		local seated, more = PhaseMachine.step(round, { kind = "SeatsAssigned" }, now)
		round = seated
		passInto(effects, more)
		passInto(meta.passThrough, more)
		assignment = dealt
		meta.assign = deal
		meta.dealt = dealt

		local result = Generator.generate(dealt, deal.seed, tuning, predicate)
		if result.kind == "facility" then
			facility = result.facility
			procedure = Procedure.start(facility, now, tuning, deal.seed, config.roundSeconds)
			local centre = ScriptedRound.spawnCentre(facility, tuning)
			meta.centre = centre
			positions = {}
			baselines = {}
			for _, p in dealt.players do
				positions[p] = { x = centre.x, y = centre.y, z = centre.z }
				baselines[p] = { at = { x = centre.x, y = centre.y, z = centre.z }, now = now }
				table.insert(meta.placed, {
					kind = "Placed",
					playerId = p,
					position = { x = centre.x, y = centre.y, z = centre.z },
				})
			end
		else
			meta.generationFailed = true
			local resolved, third = PhaseMachine.step(round, {
				kind = "RoundResolved",
				outcome = { result = "no_contest", reason = "generation_failed" },
			}, now)
			round = resolved
			passInto(effects, third)
			passInto(meta.passThrough, third)
		end
		for _, p in dealt.players do
			table.insert(sends, seatView(dealt, p))
			table.insert(meta.seatViews, p)
		end
	elseif
		event.kind == "PlayerLeft"
		and assignment ~= nil
		and contains(before.players, event.playerId)
		and not contains(round.players, event.playerId)
	then
		local old = assignment
		local withdrawn = Ring.withdraw(old, event.playerId)
		for _, p in withdrawn.players do
			local fresh = Projection.forPlayer(withdrawn, p)
			if not Deep.equal(fresh, Projection.forPlayer(old, p)) then
				table.insert(
					sends,
					{ kind = "SendTo", playerId = p, payloadKind = "SeatView", payload = fresh }
				)
				table.insert(meta.seatViews, p)
			end
		end
		assignment = withdrawn
	end

	-- C-3 step 4: the Procedure is advanced AFTER the machine took the Tick.
	if event.kind == "Tick" and procedure ~= nil and procedure.outcome == nil then
		local ticked = Procedure.tick(procedure, assignment, now, positions)
		meta.ticked = true
		if ticked.outcome ~= nil then
			local resolved, more =
				PhaseMachine.step(round, { kind = "RoundResolved", outcome = ticked.outcome }, now)
			round = resolved
			passInto(effects, more)
			passInto(meta.passThrough, more)
			meta.routed = true
		end
		procedure = ticked
	end

	if round.phase == "Lobby" and before.phase ~= "Lobby" then
		assignment = nil
		facility = nil
		procedure = nil
		meta.entersLobby = true
	end

	for _, e in meta.placed do
		table.insert(effects, e)
	end
	for _, e in sends do
		table.insert(effects, e)
	end

	local next_: Oracle = {
		round = round,
		assignment = assignment,
		facility = facility,
		procedure = procedure,
		positions = positions,
		baselines = baselines,
	}
	local timed = round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post"
	meta.wantsRoundView = round.phase ~= before.phase
		or #round.players ~= #before.players
		or (event.kind == "Tick" and timed)
	if meta.wantsRoundView then
		local view = roundViewOf(next_, now, config)
		meta.expectedSecondsLeft = view.payload.secondsLeft
		table.insert(effects, view)
	end
	meta.expectedEffects = effects
	return next_, meta
end

--[[ ------------------------------------------------------------------------
     The scripted run: the subject and the oracle, side by side.
     --------------------------------------------------------------------- ]]

-- A plan entry's event may be a FUNCTION of the oracle's state before the
-- step, for events that need the facility (a machine's position, a setting).
export type Plan = { { label: string, event: any, now: number } }

export type Step = {
	label: string,
	event: any,
	now: number,
	before: any, -- deep snapshot of the subject's state before the step
	beforeLive: any,
	eventSnapshot: any,
	after: any, -- deep snapshot after
	afterLive: any,
	effects: { any },
	oracleBefore: Oracle,
	oracleAfter: Oracle,
	meta: Meta,
}

export type RunOptions = { generatorPredicate: ((any) -> string?)? }

function SessionRoundContract.run(
	S: Session,
	criterion: string,
	plan: Plan,
	options: RunOptions?
): { Step }
	requireModule(criterion, S)
	local config = SessionRoundContract.config()
	local tuning = SessionRoundContract.tuning()
	local predicate = if options ~= nil then options.generatorPredicate else nil

	-- SLICE-006 C-2: ports fifth (required), options sixth (nil when none).
	local okNew, state = pcall(
		S.new,
		config,
		SessionRoundContract.SEED,
		SessionRoundContract.ROUND_ID,
		SessionRoundContract.SESSION_ID,
		SessionRoundContract.PORTS,
		options
	)
	if not okNew then
		Contract.fail(`{criterion}: Session.new RAISED: {tostring(state)}`)
	end
	if typeof(state) ~= "table" or typeof(state.round) ~= "table" then
		Contract.fail(
			`{criterion}: Session.new returned {Deep.show(state)}, expected a SessionState with a round`
		)
	end

	local oracle: Oracle = {
		round = PhaseMachine.initial(
			config,
			SessionRoundContract.SEED,
			SessionRoundContract.ROUND_ID,
			SessionRoundContract.SESSION_ID
		),
		assignment = nil,
		facility = nil,
		procedure = nil,
		positions = {},
		baselines = {},
	}
	local steps: { Step } = {}

	for _, planned in plan do
		local event = if typeof(planned.event) == "function"
			then planned.event(oracle)
			else planned.event
		local now = planned.now
		local stateSnapshot = Deep.copy(state)
		local eventSnapshot = Deep.copy(event)

		local oracleBefore = oracle
		local oracleAfter, meta = oracleStep(oracle, event, now, config, tuning, predicate)

		local ok, after, effects = pcall(S.step, state, event, now)
		if not ok then
			Contract.fail(
				`{criterion}: step "{planned.label}" ({Deep.show(event)} at {now}) RAISED: {tostring(
					after
				)}`
			)
		end
		if typeof(after) ~= "table" or typeof(after.round) ~= "table" then
			Contract.fail(
				`{criterion}: step "{planned.label}" returned {Deep.show(after)}, expected a SessionState with a round`
			)
		end
		if typeof(effects) ~= "table" then
			Contract.fail(
				`{criterion}: step "{planned.label}" returned effects {Deep.show(effects)}; an effect list is always a table`
			)
		end

		table.insert(steps, {
			label = planned.label,
			event = event,
			now = now,
			before = stateSnapshot,
			beforeLive = state,
			eventSnapshot = eventSnapshot,
			after = Deep.copy(after),
			afterLive = after,
			effects = effects,
			oracleBefore = oracleBefore,
			oracleAfter = oracleAfter,
			meta = meta,
		})

		state = after
		oracle = oracleAfter
	end

	return steps
end

--[[ ------------------------------------------------------------------------
     The plans. Every time and count is a function of the config and tuning.
     --------------------------------------------------------------------- ]]

local function join(label: string, playerId: string, now: number)
	return { label = label, event = { kind = "PlayerJoined", playerId = playerId }, now = now }
end

local function leave(label: string, playerId: string, now: number)
	return { label = label, event = { kind = "PlayerLeft", playerId = playerId }, now = now }
end

local function tick(label: string, now: number)
	return { label = label, event = { kind = "Tick" }, now = now }
end

local function sample(label: string, samples: any, now: number)
	return { label = label, event = { kind = "PositionsSampled", samples = samples }, now = now }
end

local function turn(label: string, playerId: string, machine: number, setting: number, now: number)
	return {
		label = label,
		event = {
			kind = "TurnRequested",
			playerId = playerId,
			args = { machine = machine, setting = setting },
		},
		now = now,
	}
end

-- A machine of the oracle's facility by track and index, with its turner and
-- its position; for the function-valued plan entries.
local function stepMachine(o: Oracle, track: number, index: number): (any, string)
	local facility = o.facility
	if facility == nil then
		error("the oracle has no facility: the plan reads a machine before the deal", 0)
	end
	local id = facility.steps.tracks[track][index]
	local m = ScriptedRound.machineOf(facility, id)
	return m, ScriptedRound.turnerOf(o.assignment, m)
end

local function machinePosition(o: Oracle, m: any): any
	return Machines.positionOf((o.facility :: any).layout, m, SessionRoundContract.tuning())
end

-- Everyone where the oracle last accepted them, except `moves` - what a
-- driver sampling every character would send (VIEW-004: a sample must be
-- walkable from the last accepted one, so nobody is sent back to the centre).
local function everyoneAt(o: Oracle, moves: { [string]: any }): { [string]: any }
	local samples: { [string]: any } = {}
	for p, v in o.positions do
		samples[p] = { x = v.x, y = v.y, z = v.z }
	end
	for p, v in moves do
		samples[p] = { x = v.x, y = v.y, z = v.z }
	end
	return samples
end

-- The whole seconds a walk between any two points of the layout can take at
-- bare walk speed; the lifecycle spaces its moves by this so that every
-- sample it offers is reachable without tolerance (VIEW-004).
local function walkSeconds(): number
	return ScriptedRound.maxMoveSeconds(SessionRoundContract.tuning())
end

--[[
	Two rounds with every kind of step the Contract names, at `playersMin`:

	  Lobby: a sample and a turn before anyone joined (stored / ignored), the
	  joins, the DEAL (facility, Procedure, Placed).
	  Round: a tick; after a whole walk's worth of seconds (W, the longest
	  move on the layout at bare walk speed) the turner of T1[1] sampled at
	  it and a CORRECT turn (committed); the turner of T2[1] sampled at it
	  and a WRONG turn (rejected, one point charged - the penalty every later
	  secondsLeft shows); a tick whose RoundView differs from the config
	  formula by that penalty; a stranger's turn (not_key_holder) and an
	  unknown machine; the turner of T2[1] sampled BACK at the spawn centre
	  (a walk away, W seconds later) followed by that turner's now-correct
	  turn (out_of_reach: the turn reads the stored position); a fractional
	  tick; a seated leave (quorum kept); the tick a second before the
	  Procedure's penalised deadline (still Round) and the tick ON it (lost /
	  clock, routed from the Procedure, before the machine's own backstop).
	  Resolution: a turn (ignored), a sample (accepted: the player has a
	  baseline and the clock has run), the tick into Post.
	  Post: a turn (ignored), the tick into Lobby (facility and procedure
	  cleared, positions kept).
	  Lobby again: a turn (ignored), a replacement joins, the second DEAL from
	  a different seed.

	  VIEW-004: every sample here is reachable at BARE walk speed from the
	  player's last accepted sample, so the oracle needs no tolerance; the
	  first sample, in the empty Lobby, has no baseline and is NOT stored.
	  SLICE-005's "sample that OMITS the turner" is gone: a batch merges, so
	  omission no longer moves anybody, and the out_of_reach turn is reached
	  by walking away instead.
]]
function SessionRoundContract.lifecycle(): Plan
	local c = SessionRoundContract.config()
	local t = SessionRoundContract.tuning()
	local P = SessionRoundContract.PLAYERS
	local penalty = t.actuation.instability_clock_penalty_seconds
	local reset = t.actuation.actuation_reset_seconds
	local W = walkSeconds()
	local plan: Plan = {}

	table.insert(plan, sample("sample in an empty Lobby", { [P[1]] = { x = 5, y = 0, z = 5 } }, 0))
	table.insert(plan, turn("turn in Lobby (no procedure)", P[1], 1, 1, 0))
	for i = 1, c.playersMin do
		table.insert(plan, join(`join {P[i]}`, P[i], 0))
	end
	local L = c.lobbySeconds
	table.insert(plan, tick("DEAL 1", L))
	table.insert(plan, tick("tick in Round", L + 1))

	local atT1 = L + 1 + W
	table.insert(plan, {
		label = "the turner of T1[1] sampled at it, a walk after the deal",
		now = atT1,
		event = function(o: Oracle)
			local m, turner = stepMachine(o, 1, 1)
			return {
				kind = "PositionsSampled",
				samples = everyoneAt(o, { [turner] = machinePosition(o, m) }),
			}
		end,
	})
	table.insert(plan, {
		label = "correct turn on T1[1] (committed)",
		now = atT1 + 1,
		event = function(o: Oracle)
			local m, turner = stepMachine(o, 1, 1)
			return {
				kind = "TurnRequested",
				playerId = turner,
				args = { machine = m.id, setting = m.requiredSetting },
			}
		end,
	})
	-- A whole walk after the T1[1] sample: the same player may hold both.
	local atT2 = atT1 + 1 + W
	table.insert(plan, {
		label = "the turner of T2[1] sampled at it, a walk later",
		now = atT2,
		event = function(o: Oracle)
			local m, turner = stepMachine(o, 2, 1)
			return {
				kind = "PositionsSampled",
				samples = everyoneAt(o, { [turner] = machinePosition(o, m) }),
			}
		end,
	})
	local wrongAt = atT2 + 1
	table.insert(plan, {
		label = "wrong turn on T2[1] (rejected, one point)",
		now = wrongAt,
		event = function(o: Oracle)
			local m, turner = stepMachine(o, 2, 1)
			local wrong = (m.requiredSetting % t.instance.dial_settings) + 1
			return {
				kind = "TurnRequested",
				playerId = turner,
				args = { machine = m.id, setting = wrong },
			}
		end,
	})
	table.insert(plan, tick("tick after the penalty", wrongAt + 1))
	table.insert(plan, {
		label = "stranger's turn (not_key_holder)",
		now = wrongAt + 2,
		event = function(o: Oracle)
			local m = stepMachine(o, 1, 2)
			return {
				kind = "TurnRequested",
				playerId = SessionRoundContract.STRANGER,
				args = { machine = m.id, setting = m.requiredSetting },
			}
		end,
	})
	table.insert(plan, {
		label = "turn on an unknown machine",
		now = wrongAt + 2,
		event = function(o: Oracle)
			local _, turner = stepMachine(o, 1, 2)
			return {
				kind = "TurnRequested",
				playerId = turner,
				args = { machine = 999, setting = 1 },
			}
		end,
	})
	-- A whole walk after the T2[1] sample, and past the reset window.
	local backAt = math.max(wrongAt + reset, atT2 + W)
	table.insert(plan, {
		label = "the turner of T2[1] sampled back at the spawn centre (walked away), alone in the batch",
		now = backAt,
		event = function(o: Oracle)
			local _, turner = stepMachine(o, 2, 1)
			local centre = ScriptedRound.spawnCentre(o.facility, SessionRoundContract.tuning())
			return { kind = "PositionsSampled", samples = { [turner] = centre } }
		end,
	})
	table.insert(plan, {
		label = "correct turn on T2[1] after walking away (out_of_reach)",
		now = backAt,
		event = function(o: Oracle)
			local m, turner = stepMachine(o, 2, 1)
			return {
				kind = "TurnRequested",
				playerId = turner,
				args = { machine = m.id, setting = m.requiredSetting },
			}
		end,
	})
	local late = math.max(L + 100, backAt + 1)
	table.insert(plan, tick("fractional tick in Round", late + 0.25))
	table.insert(plan, leave(`{P[3]} leaves the Round (quorum kept)`, P[3], late + 1))

	local deadline = L + c.roundSeconds - penalty
	table.insert(plan, tick("tick one second before the penalised deadline", deadline - 1))
	table.insert(plan, tick("tick ON the penalised deadline (lost / clock)", deadline))
	table.insert(plan, turn("turn in Resolution (ignored)", P[1], 1, 1, deadline + 1))
	table.insert(
		plan,
		sample("sample in Resolution", { [P[1]] = { x = 7, y = 0, z = 7 } }, deadline + 1)
	)
	local post = deadline + 2
	table.insert(plan, tick("Resolution -> Post", post))
	table.insert(plan, turn("turn in Post (ignored)", P[2], 1, 1, post + 1))
	local lobby = post + c.postRoundSeconds
	table.insert(plan, tick("Post -> Lobby (clears facility and procedure)", lobby))
	table.insert(plan, turn("turn in the new Lobby (ignored)", P[1], 1, 1, lobby + 1))
	table.insert(
		plan,
		join(`join {P[c.playersMin + 1]} (replaces the leaver)`, P[c.playersMin + 1], lobby + 1)
	)
	table.insert(plan, tick("DEAL 2", lobby + c.lobbySeconds))
	return plan
end

--[[
	`playersMin` players and a generator that refuses every attempt: the deal
	resolves `no_contest / generation_failed` in the same step; a turn there
	is ignored (no procedure); the next tick moves to Post.
]]
function SessionRoundContract.generationFailure(): Plan
	local c = SessionRoundContract.config()
	local P = SessionRoundContract.PLAYERS
	local plan: Plan = {}
	for i = 1, c.playersMin do
		table.insert(plan, join(`join {P[i]}`, P[i], 0))
	end
	table.insert(plan, tick("DEAL (generation fails)", c.lobbySeconds))
	table.insert(
		plan,
		turn(
			"turn in Resolution after a failed generation (ignored)",
			P[1],
			1,
			1,
			c.lobbySeconds + 1
		)
	)
	table.insert(plan, tick("Resolution -> Post", c.lobbySeconds + 2))
	return plan
end

local function dealSteps(steps: { Step }): { Step }
	local out: { Step } = {}
	for _, step in steps do
		if step.meta.assign ~= nil then
			table.insert(out, step)
		end
	end
	return out
end

local function fewProblems(criterion: string, headline: string, problems: { string })
	if #problems > 0 then
		Contract.fail(`{criterion}: {headline}:\n{Contract.firstFew(problems, 10)}`)
	end
end

--[[ ------------------------------------------------------------------------
     Contract: `new`, and the state following the oracle.
     --------------------------------------------------------------------- ]]

--[[
	C-1: `new` holds no facility, no procedure, `positions = {}` and (VIEW-004)
	`tracks = {}`; it also accepts an optional SIXTH `options` argument
	carrying `generatorPredicate` without raising (fifth until SLICE-006 C-2
	put the ports there), and still holds PhaseMachine.initial's round.
]]
function SessionRoundContract.newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions(
	S: Session
)
	requireModule("Contract", S)
	local config = SessionRoundContract.config()
	local problems: { string } = {}
	local ok, state = pcall(
		S.new,
		config,
		SessionRoundContract.SEED,
		SessionRoundContract.ROUND_ID,
		SessionRoundContract.SESSION_ID,
		SessionRoundContract.PORTS
	)
	if not ok then
		Contract.fail(`Contract: Session.new RAISED: {tostring(state)}`)
	end
	if state.facility ~= nil then
		table.insert(
			problems,
			`state.facility is {Deep.show(state.facility)} from new, expected nil`
		)
	end
	if state.procedure ~= nil then
		table.insert(
			problems,
			`state.procedure is {Deep.show(state.procedure)} from new, expected nil`
		)
	end
	if not Deep.equal(state.positions, {}) then
		table.insert(
			problems,
			`state.positions is {Deep.show(state.positions)} from new, expected \{} (C-1)`
		)
	end
	if not Deep.equal(state.tracks, {}) then
		table.insert(
			problems,
			`state.tracks is {Deep.show(state.tracks)} from new, expected \{} (VIEW-004)`
		)
	end
	local ok6, state6 = pcall(
		S.new,
		config,
		SessionRoundContract.SEED,
		SessionRoundContract.ROUND_ID,
		SessionRoundContract.SESSION_ID,
		SessionRoundContract.PORTS,
		{ generatorPredicate = SessionRoundContract.refuseAll }
	)
	if not ok6 then
		table.insert(
			problems,
			`Session.new with a sixth options argument RAISED: {tostring(state6)}`
		)
	elseif typeof(state6) ~= "table" or not Deep.equal(state6.round, state.round) then
		table.insert(problems, "Session.new with options returned a different round than without")
	end
	fewProblems(
		"Contract",
		"Session.new must hold facility = nil, procedure = nil, positions = {}, tracks = {} and accept options",
		problems
	)
end

--[[
	C-3: after every step of both plans, `round`, `assignment`, `facility`,
	`procedure` and `positions` deep-equal the oracle's.
]]
function SessionRoundContract.roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep(
	S: Session
)
	local problems: { string } = {}
	local plans = {
		{ SessionRoundContract.lifecycle(), nil },
		{
			SessionRoundContract.generationFailure(),
			{ generatorPredicate = SessionRoundContract.refuseAll },
		},
	}
	for _, pair in plans do
		for _, step in SessionRoundContract.run(S, "Contract", pair[1], pair[2]) do
			for _, field in { "round", "assignment", "facility", "procedure", "positions" } do
				local want = (step.oracleAfter :: any)[field]
				local got = step.after[field]
				if not Deep.equal(got, want) then
					table.insert(
						problems,
						`after "{step.label}": state.{field} differs from the Contract's composition:\n{Contract.firstFew(
							string.split(Deep.diff(want, got), "\n"),
							4
						)}`
					)
				end
			end
		end
	end
	fewProblems(
		"Contract",
		"state.round, assignment, facility, procedure and positions must follow PhaseMachine, Ring, Generator, Procedure and TurnRequests stepped on the same inputs",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-1: the facility, the Procedure and the Placed effects.
     --------------------------------------------------------------------- ]]

--[[
	On each of two deals: `facility` deep-equals `Generator.generate(dealt,
	effect.seed, tuning).facility` and `procedure` deep-equals
	`Procedure.start(facility, now, tuning, effect.seed, config.roundSeconds)`.
	The two seeds differ (asserted), so a session generating from a fixed or
	reused seed fails on the second.
]]
function SessionRoundContract.generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep(
	S: Session
)
	local steps = SessionRoundContract.run(S, "AC-1", SessionRoundContract.lifecycle())
	local deals = dealSteps(steps)
	if #deals ~= 2 then
		Contract.fail(`AC-1 precondition: the lifecycle produced {#deals} deal(s), expected 2`)
	end
	if deals[1].meta.assign.seed == deals[2].meta.assign.seed then
		Contract.fail(`AC-1 precondition: both deals carry seed {deals[1].meta.assign.seed}`)
	end
	local problems: { string } = {}
	for i, deal in deals do
		local seed = deal.meta.assign.seed
		if deal.after.facility == nil then
			table.insert(
				problems,
				`deal {i} ("{deal.label}"): state.facility is nil after the dealing step`
			)
		elseif not Deep.equal(deal.after.facility, deal.oracleAfter.facility) then
			table.insert(
				problems,
				`deal {i} ("{deal.label}"): state.facility is not Generator.generate(dealt, {seed}, tuning).facility:\n{Contract.firstFew(
					string.split(Deep.diff(deal.oracleAfter.facility, deal.after.facility), "\n"),
					4
				)}`
			)
		end
		if deal.after.procedure == nil then
			table.insert(
				problems,
				`deal {i} ("{deal.label}"): state.procedure is nil after the dealing step`
			)
		elseif not Deep.equal(deal.after.procedure, deal.oracleAfter.procedure) then
			table.insert(
				problems,
				`deal {i} ("{deal.label}"): state.procedure is not Procedure.start(facility, {deal.now}, tuning, {seed}, {SessionRoundContract.config().roundSeconds}):\n{Contract.firstFew(
					string.split(Deep.diff(deal.oracleAfter.procedure, deal.after.procedure), "\n"),
					4
				)}`
			)
		end
	end
	fewProblems(
		"AC-1",
		"the dealing step must hold Generator.generate(dealt, effect.seed) and Procedure.start(facility, now, tuning, effect.seed, roundSeconds)",
		problems
	)
end

--[[
	On each deal: one `Placed { playerId, position }` per seated player, in
	seat order, at the spawn room's centre, each in its own table and none
	aliasing `state.positions`; `state.positions` deep-equals `{ [p] = centre }`.
	No Placed on any other step.
]]
function SessionRoundContract.placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder(S: Session)
	local steps = SessionRoundContract.run(S, "AC-1", SessionRoundContract.lifecycle())
	local problems: { string } = {}
	local others = 0
	for _, step in steps do
		local placed = SessionRoundContract.placedOf(step.effects)
		if step.meta.assign == nil then
			others += 1
			if #placed > 0 then
				table.insert(
					problems,
					`"{step.label}": {#placed} Placed effect(s) on a step that dealt nothing`
				)
			end
			continue
		end
		local want = step.meta.placed
		local centre = step.meta.centre
		if #placed ~= #want then
			table.insert(
				problems,
				`"{step.label}": {#placed} Placed effect(s), expected {#want} (one per seated player) at the spawn centre {Deep.show(
					centre
				)}`
			)
		end
		local seen: { [any]: boolean } = {}
		for i, effect in placed do
			local keys = keysOf(effect)
			if not Deep.equal(keys, SessionRoundContract.PLACED_KEYS) then
				table.insert(
					problems,
					`"{step.label}": Placed key set is {Deep.show(keys)}, expected {Deep.show(
						SessionRoundContract.PLACED_KEYS
					)}`
				)
			end
			local expected = want[i]
			if expected ~= nil and effect.playerId ~= expected.playerId then
				table.insert(
					problems,
					`"{step.label}": Placed #{i} is for {Deep.show(effect.playerId)}, expected {expected.playerId} (seat order {Deep.show(
						step.meta.dealt.players
					)})`
				)
			end
			if typeof(effect.position) ~= "table" then
				table.insert(
					problems,
					`"{step.label}": Placed #{i}.position is {Deep.show(effect.position)}, not a table`
				)
				continue
			end
			if not Deep.equal(keysOf(effect.position), SessionRoundContract.VEC_KEYS) then
				table.insert(
					problems,
					`"{step.label}": Placed #{i}.position keys are {Deep.show(
						keysOf(effect.position)
					)}, expected x, y, z`
				)
			end
			if not Deep.equal(effect.position, centre) then
				table.insert(
					problems,
					`"{step.label}": Placed #{i} ({tostring(effect.playerId)}) is at {Deep.show(
						effect.position
					)}, expected the spawn room's centre {Deep.show(centre)}`
				)
			end
			if seen[effect.position] then
				table.insert(
					problems,
					`"{step.label}": Placed #{i}.position is the SAME table as another Placed's`
				)
			end
			seen[effect.position] = true
			local live = step.afterLive.positions
			if typeof(live) == "table" and rawequal(live[effect.playerId], effect.position) then
				table.insert(
					problems,
					`"{step.label}": Placed #{i}.position IS state.positions[{tostring(
						effect.playerId
					)}] (aliased)`
				)
			end
		end
		if not Deep.equal(step.after.positions, step.oracleAfter.positions) then
			table.insert(
				problems,
				`"{step.label}": state.positions after the deal is {Deep.show(step.after.positions)}, expected every seated player at the centre {Deep.show(
					centre
				)}`
			)
		end
	end
	if others < 10 then
		Contract.fail(`AC-1 precondition: only {others} non-dealing steps`)
	end
	fewProblems(
		"AC-1",
		"the dealing step must emit one Placed per seated player at the spawn room's centre, in seat order, each a fresh table",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-2: generation fails.
     --------------------------------------------------------------------- ]]

--[[
	With `options.generatorPredicate` refusing every attempt, the dealing
	step ends in Resolution with `no_contest / generation_failed`, holds no
	facility or procedure, emits no Placed, still sends every seat view, and
	its RoundView reads Resolution; the machine's effects equal the oracle's
	three machine steps. A later turn is ignored; the next tick moves to Post.
]]
function SessionRoundContract.resolvesAFailedGenerationAsNoContestInTheDealingStep(S: Session)
	local steps = SessionRoundContract.run(
		S,
		"AC-2",
		SessionRoundContract.generationFailure(),
		{ generatorPredicate = SessionRoundContract.refuseAll }
	)
	local deals = dealSteps(steps)
	if #deals ~= 1 or not deals[1].meta.generationFailed then
		Contract.fail("AC-2 precondition: the oracle's generation did not fail on the deal")
	end
	local deal = deals[1]
	local problems: { string } = {}
	local round = deal.after.round
	if round.phase ~= "Resolution" then
		table.insert(
			problems,
			`after the dealing step the phase is {Deep.show(round.phase)}, expected Resolution in the same step`
		)
	end
	if not Deep.equal(round.outcome, { result = "no_contest", reason = "generation_failed" }) then
		table.insert(
			problems,
			`state.round.outcome is {Deep.show(round.outcome)}, expected \{ no_contest, generation_failed }`
		)
	end
	if deal.after.facility ~= nil then
		table.insert(problems, "state.facility is not nil after a failed generation")
	end
	if deal.after.procedure ~= nil then
		table.insert(problems, "state.procedure is not nil after a failed generation")
	end
	if #SessionRoundContract.placedOf(deal.effects) > 0 then
		table.insert(
			problems,
			`{#SessionRoundContract.placedOf(deal.effects)} Placed effect(s) on a failed generation`
		)
	end
	local views = SessionRoundContract.seatViewsOf(deal.effects)
	local to: { string } = {}
	for _, v in views do
		table.insert(to, tostring(v.playerId))
	end
	if not Deep.equal(to, deal.meta.seatViews) then
		table.insert(
			problems,
			`SeatViews went to {Deep.show(to)}, expected every seated player {Deep.show(
				deal.meta.seatViews
			)} (the ring was dealt)`
		)
	end
	local rv = SessionRoundContract.roundViewsOf(deal.effects)
	if #rv ~= 1 then
		table.insert(problems, `{#rv} RoundView broadcast(s), expected 1`)
	elseif rv[1].payload.phase ~= "Resolution" or rv[1].payload.secondsLeft ~= nil then
		table.insert(
			problems,
			`the RoundView reads {Deep.show(rv[1].payload.phase)} / secondsLeft {Deep.show(
				rv[1].payload.secondsLeft
			)}, expected Resolution / nil`
		)
	end
	local pass: { any } = {}
	for _, e in deal.effects do
		if
			typeof(e) == "table"
			and (
				e.kind == "Emit"
				or e.kind == "PromptRematch"
				or e.kind == "ComputeTrace"
				or e.kind == "AssignSeats"
			)
		then
			table.insert(pass, e)
		end
	end
	if not Deep.equal(pass, deal.meta.passThrough) then
		table.insert(
			problems,
			`the machine's effects are {Deep.show(Deep.kinds(pass))}, expected {Deep.show(
				Deep.kinds(deal.meta.passThrough)
			)} (three machine steps, RoundResolved last)`
		)
	end
	local turnStep = steps[#steps - 1]
	if not Deep.equal(turnStep.after, turnStep.before) or #turnStep.effects ~= 0 then
		table.insert(
			problems,
			`"{turnStep.label}": a turn with no procedure changed the state or emitted {Deep.show(
				Deep.kinds(turnStep.effects)
			)}`
		)
	end
	if steps[#steps].after.round.phase ~= "Post" then
		table.insert(
			problems,
			`the tick after the failed deal left the phase at {Deep.show(
				steps[#steps].after.round.phase
			)}, expected Post`
		)
	end
	fewProblems(
		"AC-2",
		"a generator that fails every attempt must resolve no_contest / generation_failed in the dealing step, with seat views still sent",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-3: a turn.
     --------------------------------------------------------------------- ]]

--[[
	On every handled turn: `state.procedure` deep-equals the state
	`TurnRequests.handle(procedure, assignment, playerId, args, now,
	STORED positions)` returns; exactly one SendTo, to the caller, of kind
	TurnResult, payload deep-equal to `TurnRequests.reply(result)`; no Placed;
	a Broadcast only if the phase changed. The plan's turns resolve (asserted
	on the oracle) to committed, wrong_setting, not_key_holder,
	unknown_machine and - after the turner walked back to the spawn centre -
	out_of_reach: a session passing `{}`, the Placed centres, or a map that
	drops the players absent from a batch disagrees on at least one.
]]
function SessionRoundContract.handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone(
	S: Session
)
	local steps = SessionRoundContract.run(S, "AC-3", SessionRoundContract.lifecycle())
	local problems: { string } = {}
	local seenKinds: { string } = {}
	local handled = 0
	for _, step in steps do
		local t = step.meta.turn
		if t == nil then
			continue
		end
		handled += 1
		local result = t.result
		table.insert(
			seenKinds,
			if result.reason then `{result.kind}/{result.reason}` else result.kind
		)
		if not Deep.equal(step.after.procedure, t.procedureAfter) then
			table.insert(
				problems,
				`"{step.label}": state.procedure is not TurnRequests.handle(procedure, assignment, "{t.playerId}", args, {step.now}, state.positions) - the oracle's result was {Deep.show(
					t.reply
				)}:\n{Contract.firstFew(
					string.split(Deep.diff(t.procedureAfter, step.after.procedure), "\n"),
					4
				)}`
			)
		end
		local replies = SessionRoundContract.turnResultsOf(step.effects)
		-- NARROWED by SLICE-006 C-3: a turn that commits may also change a
		-- lens or a turn cue, and those ride as their own SendTos (C-6).
		-- Every other kind of SendTo on a turn is still a problem.
		local otherSends = 0
		for _, e in ofKind(step.effects, "SendTo") do
			if
				e.payloadKind ~= "TurnResult"
				and e.payloadKind ~= "LensView"
				and e.payloadKind ~= "TurnCues"
			then
				otherSends += 1
			end
		end
		if otherSends ~= 0 or #replies ~= 1 then
			table.insert(
				problems,
				`"{step.label}": {#replies} TurnResult SendTo(s) and {otherSends} SendTo(s) of a kind that is neither TurnResult, LensView nor TurnCues, expected exactly one TurnResult to the caller {t.playerId}; effects were {Deep.show(
					Deep.kinds(step.effects)
				)}`
			)
		end
		for _, r in replies do
			if r.playerId ~= t.playerId then
				table.insert(
					problems,
					`"{step.label}": a TurnResult was addressed to {Deep.show(r.playerId)}, not the caller {t.playerId}`
				)
			end
			local keys = keysOf(r)
			if not Deep.equal(keys, SessionRoundContract.SEND_TO_KEYS) then
				table.insert(
					problems,
					`"{step.label}": the TurnResult SendTo's key set is {Deep.show(keys)}, expected {Deep.show(
						SessionRoundContract.SEND_TO_KEYS
					)}`
				)
			end
			if not Deep.equal(r.payload, t.reply) then
				table.insert(
					problems,
					`"{step.label}": the TurnResult payload is {Deep.show(r.payload)}, expected TurnRequests.reply(result) = {Deep.show(
						t.reply
					)} - judged against the STORED positions`
				)
			end
		end
		if #SessionRoundContract.placedOf(step.effects) > 0 then
			table.insert(problems, `"{step.label}": a Placed effect on a turn`)
		end
		-- NARROWED by SLICE-006 C-3 (C-6): a RoundView may also ride on a turn
		-- whose phase did not change when the view changed - which a turn
		-- does exactly when it was EVALUATED (committed, armed, rejected: the
		-- dial, the progress bar or the live lamp moves). A REFUSED turn
		-- changes nothing, so it still broadcasts nothing.
		local broadcasts = ofKind(step.effects, "Broadcast")
		local evaluated = result.kind == "committed"
			or result.kind == "armed"
			or result.kind == "rejected"
		local want = if step.meta.wantsRoundView then 1 else 0
		local tolerated = if step.meta.wantsRoundView or not evaluated then want else 1
		if #broadcasts < want or #broadcasts > tolerated then
			table.insert(
				problems,
				`"{step.label}": {#broadcasts} Broadcast(s) on a {result.kind} turn whose phase {if step.meta.wantsRoundView
					then "changed"
					else "did not change"}, expected {if want == tolerated
					then tostring(want)
					else `{want} or {tolerated}`}`
			)
		end
	end
	for _, needed in
		{
			"committed",
			"rejected/wrong_setting",
			"refused/not_key_holder",
			"refused/unknown_machine",
			"refused/out_of_reach",
		}
	do
		if not contains(seenKinds, needed) then
			Contract.fail(
				`AC-3 precondition: the plan's turns resolve to {Deep.show(seenKinds)} on the oracle; {needed} is missing`
			)
		end
	end
	if handled < 5 then
		Contract.fail(`AC-3 precondition: only {handled} handled turns in the plan`)
	end
	fewProblems(
		"AC-3",
		"a TurnRequested in Round must be TurnRequests.handle on the STORED positions, with one private TurnResult to the caller carrying TurnRequests.reply(result)",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-3: samples, ignored turns, clearing.
     --------------------------------------------------------------------- ]]

--[[
	VIEW-004's rewrite of SLICE-005's C-3 check. Every PositionsSampled, in
	every phase: `state.positions` deep-equals the oracle's ACCEPTED
	positions - the batch merged into what was stored, a player with no
	baseline absent (the empty-Lobby sample), nobody dropped for being absent
	from a batch - and no stored entry is the event's own table; nothing is
	emitted (every sample in the plan is plausible, so no resync placement
	is due; in Round the only effect a sample may ever emit is `Placed`);
	`round`, `assignment`, `facility` and `procedure` are deep-equal to what
	they were. Against SLICE-005's Session, which stored every sample
	unfiltered and replaced the map, this fails on the empty-Lobby sample
	(stored without a baseline) and on every Round sample (the players
	absent from the batch are dropped).
]]
function SessionRoundContract.mergesAcceptedSamplesAndEmitsOnlyResyncPlacements(S: Session)
	local steps = SessionRoundContract.run(S, "Contract", SessionRoundContract.lifecycle())
	local problems: { string } = {}
	local sampled, unplaced, partial = 0, 0, 0
	for _, step in steps do
		if not step.meta.sampled then
			continue
		end
		sampled += 1
		local samples = step.event.samples
		local want = step.oracleAfter.positions
		local batch = 0
		for p in samples do
			batch += 1
			if step.oracleBefore.baselines[p] == nil then
				unplaced += 1
			end
		end
		local stored = 0
		for _ in want do
			stored += 1
		end
		if batch < stored then
			partial += 1
		end
		if not Deep.equal(step.after.positions, want) then
			table.insert(
				problems,
				`"{step.label}": state.positions is {Deep.show(step.after.positions)}, expected the accepted positions {Deep.show(
					want
				)} (the batch merged into the stored map; a player with no placement absent)`
			)
		end
		local live = step.afterLive.positions
		if typeof(live) == "table" then
			for p, v in samples do
				if rawequal(live[p], v) then
					table.insert(
						problems,
						`"{step.label}": state.positions[{p}] IS event.samples[{p}] (the same table); the Contract wants a copy`
					)
				end
			end
		end
		-- NARROWED by SLICE-006 C-3: a sample may also emit the LensView
		-- sends and the RoundView broadcast of that story's C-6 (a lens
		-- changes when its holder walks), and nothing else.
		for i, effect in step.effects do
			local allowed = typeof(effect) == "table"
				and (
					effect.kind == "Placed"
					or (effect.kind == "SendTo" and effect.payloadKind == "LensView")
					or (effect.kind == "Broadcast" and effect.payloadKind == "RoundView")
				)
			if not allowed then
				table.insert(
					problems,
					`"{step.label}": effect #{i} is {Deep.show(
						if typeof(effect) == "table"
							then `{effect.kind}/{tostring(effect.payloadKind)}`
							else effect
					)}; the only effects a PositionsSampled may emit are Placed, SendTo/LensView and Broadcast/RoundView`
				)
			end
		end
		if #SessionRoundContract.placedOf(step.effects) ~= 0 then
			table.insert(
				problems,
				`"{step.label}": {Deep.show(Deep.kinds(step.effects))} emitted on a PositionsSampled whose every sample was plausible, expected no Placed (no resync is due)`
			)
		end
		for _, field in { "round", "assignment", "facility", "procedure" } do
			if not Deep.equal(step.after[field], step.before[field]) then
				table.insert(
					problems,
					`"{step.label}": state.{field} changed on a PositionsSampled`
				)
			end
		end
	end
	if sampled < 5 or unplaced < 1 or partial < 2 then
		Contract.fail(
			`Contract precondition: {sampled} PositionsSampled steps, {unplaced} unplaced players sampled, {partial} partial batches in the plan; too few`
		)
	end
	fewProblems(
		"Contract",
		"PositionsSampled must merge the batch into the accepted positions as fresh copies, keep players absent from the batch, store nobody without a placement, and emit nothing but a due Placed",
		problems
	)
end

--[[
	A TurnRequested in Lobby (no procedure), in Resolution and Post (procedure
	held, wrong phase), in the next Lobby (cleared) and in Resolution after a
	failed generation: the state deep-equal to its input and effects `{}`.
]]
function SessionRoundContract.ignoresATurnOutsideRoundOrWithoutAProcedure(S: Session)
	local problems: { string } = {}
	local ignored = 0
	local plans = {
		{ SessionRoundContract.lifecycle(), nil },
		{
			SessionRoundContract.generationFailure(),
			{ generatorPredicate = SessionRoundContract.refuseAll },
		},
	}
	for _, pair in plans do
		for _, step in SessionRoundContract.run(S, "Contract", pair[1], pair[2]) do
			if not step.meta.ignoredTurn then
				continue
			end
			ignored += 1
			if not Deep.equal(step.after, step.before) then
				table.insert(
					problems,
					`"{step.label}" ({step.oracleBefore.round.phase}, procedure {if step.oracleBefore.procedure
						then "held"
						else "nil"}): the state changed on an ignored turn:\n{Contract.firstFew(
						string.split(Deep.diff(step.before, step.after), "\n"),
						4
					)}`
				)
			end
			if #step.effects ~= 0 then
				table.insert(
					problems,
					`"{step.label}": {Deep.show(Deep.kinds(step.effects))} emitted on a turn outside Round, expected \{}`
				)
			end
		end
	end
	if ignored < 5 then
		Contract.fail(`Contract precondition: only {ignored} ignored turns in the plans`)
	end
	fewProblems(
		"Contract",
		"a TurnRequested with no procedure or outside Round must return the same state with {} effects",
		problems
	)
end

--[[
	The step that enters Lobby: `facility` and `procedure` nil (they were
	held before it), `positions` deep-equal to what they were.
]]
function SessionRoundContract.clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions(S: Session)
	local steps = SessionRoundContract.run(S, "Contract", SessionRoundContract.lifecycle())
	local entered: Step? = nil
	for _, step in steps do
		if step.meta.entersLobby then
			entered = step
		end
	end
	if entered == nil then
		Contract.fail("Contract precondition: the lifecycle never re-entered Lobby")
	end
	local step = entered :: Step
	local problems: { string } = {}
	if step.before.facility == nil or step.before.procedure == nil then
		table.insert(
			problems,
			`before "{step.label}" facility is {if step.before.facility then "held" else "nil"} and procedure is {if step.before.procedure
				then "held"
				else "nil"}; both must still be held in Post (AC-1)`
		)
	end
	if step.after.facility ~= nil then
		table.insert(
			problems,
			`"{step.label}": state.facility is still held after entering Lobby, expected nil`
		)
	end
	if step.after.procedure ~= nil then
		table.insert(
			problems,
			`"{step.label}": state.procedure is still held after entering Lobby, expected nil`
		)
	end
	if not Deep.equal(step.after.positions, step.before.positions) then
		table.insert(
			problems,
			`"{step.label}": state.positions changed on entering Lobby; it is the driver's last sample and is kept`
		)
	end
	fewProblems(
		"Contract",
		"entering Lobby must clear facility and procedure and keep positions",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-4: the order within a step.
     --------------------------------------------------------------------- ]]

--[[
	SLICE-005 C-4's order, WIDENED by SLICE-006 C-9 to the full list: the
	machine's pass-through, Placed, SeatView, the FacilityView broadcast, the
	caller's reply (TurnResult, PingRefused or PresetFailed), the PresetShown
	broadcast, the private views (LensView, TurnCues), and at most one
	RoundView broadcast last. A Broadcast is labelled by its payloadKind, as
	a SendTo is, so "last and at most one" reads the RoundView alone.
]]
local RANK: { [string]: number } = {
	Emit = 1,
	PromptRematch = 1,
	ComputeTrace = 1,
	Placed = 2,
	SeatView = 3,
	FacilityView = 4,
	TurnResult = 5,
	PingRefused = 5,
	PresetFailed = 5,
	PresetShown = 6,
	LensView = 7,
	TurnCues = 7,
	RoundView = 8,
}
SessionRoundContract.RANK = RANK

local function rankOf(effect: any): (number?, string)
	if typeof(effect) ~= "table" then
		return nil, "<not a table>"
	end
	local label = if effect.kind == "SendTo" or effect.kind == "Broadcast"
		then tostring(effect.payloadKind)
		else tostring(effect.kind)
	return RANK[label], label
end
SessionRoundContract.rankOf = rankOf

--[[
	On every step of both plans the effects are ordered pass-through, Placed
	(seat order), SendTo/SeatView, then SLICE-006's kinds in C-9's order,
	SendTo/TurnResult among them, at most one Broadcast/RoundView last - and
	every effect is one of those kinds.
]]
function SessionRoundContract.ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast(
	S: Session
)
	local problems: { string } = {}
	local withPlaced, withTurn = 0, 0
	local plans = {
		{ SessionRoundContract.lifecycle(), nil },
		{
			SessionRoundContract.generationFailure(),
			{ generatorPredicate = SessionRoundContract.refuseAll },
		},
	}
	for _, pair in plans do
		for _, step in SessionRoundContract.run(S, "Contract", pair[1], pair[2]) do
			local labels: { string } = {}
			local last = 0
			local broadcasts = 0
			local placedOrder: { string } = {}
			for i, effect in step.effects do
				local rank, label = rankOf(effect)
				table.insert(labels, label)
				if rank == nil then
					table.insert(
						problems,
						`"{step.label}": effect #{i} is {label}, not a kind the Contract names`
					)
					continue
				end
				if rank < last then
					table.insert(
						problems,
						`"{step.label}": {label} at #{i} comes after a later-ordered effect ({Deep.show(
							labels
						)}); the order is pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues, RoundView`
					)
				end
				last = math.max(last, rank)
				if label == "RoundView" then
					broadcasts += 1
					if i ~= #step.effects then
						table.insert(
							problems,
							`"{step.label}": a Broadcast/RoundView at #{i} of {#step.effects}; it must be last`
						)
					end
				elseif label == "Placed" then
					table.insert(placedOrder, tostring(effect.playerId))
				end
			end
			if broadcasts > 1 then
				table.insert(
					problems,
					`"{step.label}": {broadcasts} Broadcast/RoundViews, at most one is allowed`
				)
			end
			if #placedOrder > 0 then
				withPlaced += 1
				if
					step.meta.dealt ~= nil and not Deep.equal(placedOrder, step.meta.dealt.players)
				then
					table.insert(
						problems,
						`"{step.label}": Placed order is {Deep.show(placedOrder)}, expected seat order {Deep.show(
							step.meta.dealt.players
						)}`
					)
				end
			end
			if #SessionRoundContract.turnResultsOf(step.effects) > 0 then
				withTurn += 1
			end
		end
	end
	if withPlaced < 2 or withTurn < 5 then
		Contract.fail(
			`Contract precondition: only {withPlaced} steps with Placed and {withTurn} with a TurnResult`
		)
	end
	fewProblems(
		"Contract",
		"effects are ordered pass-through, Placed in seat order, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues, then at most one RoundView last",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-5: secondsLeft.
     --------------------------------------------------------------------- ]]

--[[
	Every RoundView emitted while the oracle is in Round with a procedure
	carries `secondsLeft = ceil(Procedure.deadline(procedure) - now)`. The
	plan charges one point early, so from then on this differs from the config
	formula by `instability_clock_penalty_seconds` (asserted on at least two
	ticks, one of them fractional).
]]
function SessionRoundContract.secondsLeftReadsTheProcedureDeadlineInRound(S: Session)
	local steps = SessionRoundContract.run(S, "Contract", SessionRoundContract.lifecycle())
	local c = SessionRoundContract.config()
	local problems: { string } = {}
	local penalised, checked = 0, 0
	for _, step in steps do
		local o = step.oracleAfter
		if not (o.round.phase == "Round" and o.procedure ~= nil and step.meta.wantsRoundView) then
			continue
		end
		checked += 1
		-- VIEW-003 C-7: clamped at 0 (never reached on this plan; see secondsLeftOf).
		local want = math.max(0, math.ceil(Procedure.deadline(o.procedure) - step.now))
		local configFormula = math.ceil(c.roundSeconds - (step.now - o.round.phaseEnteredAt))
		if want ~= configFormula then
			penalised += 1
		end
		local views = SessionRoundContract.roundViewsOf(step.effects)
		if #views ~= 1 then
			table.insert(problems, `"{step.label}": {#views} RoundView(s), expected 1`)
			continue
		end
		local got = views[1].payload.secondsLeft
		if got ~= want then
			table.insert(
				problems,
				`"{step.label}": RoundView.secondsLeft is {Deep.show(got)}, expected ceil(Procedure.deadline - {step.now}) = {want}{if want
						~= configFormula
					then ` (the config formula says {configFormula}; the Procedure carries {o.procedure.penaltySeconds} s of penalty)`
					else ""}`
			)
		end
	end
	if checked < 4 or penalised < 2 then
		Contract.fail(
			`Contract precondition: {checked} Round RoundViews, {penalised} of them penalised; too few`
		)
	end
	fewProblems(
		"Contract",
		"RoundView.secondsLeft in Round must be ceil(Procedure.deadline(procedure) - now) (C-5)",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-4: the scripted win, and its control.
     --------------------------------------------------------------------- ]]

local function outcomeIs(outcome: any, result: string, reason: string): boolean
	return typeof(outcome) == "table" and outcome.result == result and outcome.reason == reason
end

local function scripted<T>(criterion: string, what: string, f: () -> T): T
	local ok, value = pcall(f)
	if not ok then
		Contract.fail(`{criterion}: the script could not run {what}: {tostring(value)}`)
	end
	return value
end

--[[
	Over `SEEDS` seeds at each n in `PLAYER_COUNTS`: every turn commits (or
	arms, for the first finale machine); the completing turn's step ends in
	Resolution with `won / procedure_complete`; the next Tick moves to Post;
	the completing step's effects are pass-through, then the TurnResult, then
	the RoundView.
]]
function SessionRoundContract.winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn(S: Session)
	requireModule("AC-4", S)
	local problems: { string } = {}
	local rounds, won, sameStep = 0, 0, 0
	for _, n in SessionRoundContract.PLAYER_COUNTS do
		for seed = 1, SessionRoundContract.SEEDS do
			rounds += 1
			local run = scripted("AC-4", `the winning script (seed {seed}, n = {n})`, function()
				return ScriptedRound.win(S, seed, n)
			end)
			local tag = `seed {seed}, n = {n}`
			local ok = true
			for i, t in run.turns do
				local kind = if typeof(t.reply) == "table" then t.reply.kind else nil
				local isFirstFinale = i == #run.turns - 1
				local want = if isFirstFinale then "armed" else "committed"
				if kind ~= want then
					ok = false
					table.insert(
						problems,
						`{tag}: turn #{i} by {t.playerId} on machine {t.machineId} at {t.now} replied {Deep.show(
							t.reply
						)}, expected {want}`
					)
				end
				if i < #run.turns and t.phaseAfter ~= "Round" then
					ok = false
					table.insert(
						problems,
						`{tag}: after turn #{i} the phase is {t.phaseAfter}, expected Round`
					)
				end
			end
			local c = run.completing
			if
				c.phaseAfter == "Resolution"
				and outcomeIs(c.outcomeAfter, "won", "procedure_complete")
			then
				sameStep += 1
			else
				ok = false
				table.insert(
					problems,
					`{tag}: after the completing turn (#{#run.turns}, at {c.now}) the machine is {c.phaseAfter} / {Deep.show(
						c.outcomeAfter
					)}, expected Resolution / won procedure_complete IN THAT STEP`
				)
			end
			if run.afterNextTick.phase ~= "Post" then
				ok = false
				table.insert(
					problems,
					`{tag}: the Tick after the completing turn left the machine in {run.afterNextTick.phase}, expected Post`
				)
			end
			local labels: { string } = {}
			for _, e in c.effects do
				local _, label = rankOf(e)
				table.insert(labels, label)
			end
			local n_ = #labels
			if n_ < 2 or labels[n_] ~= "RoundView" or labels[n_ - 1] ~= "TurnResult" then
				ok = false
				table.insert(
					problems,
					`{tag}: the completing step's effects are {Deep.show(labels)}, expected the machine's Emits, then the TurnResult, then the RoundView last`
				)
			end
			if ok then
				won += 1
			end
		end
	end
	print(
		`        [measured] AC-4: {won}/{rounds} scripted rounds won; {sameStep}/{rounds} resolved in the completing turn's step`
	)
	fewProblems(
		"AC-4",
		`every scripted round ({rounds}) must end won / procedure_complete in the step that takes the completing TurnRequested, and move to Post on the next Tick`,
		problems
	)
end

--[[
	The control: the same script from the spawn room. Every turn is refused
	out_of_reach, the round is still undecided afterwards, still Round one
	second before the deadline, and `lost / clock` on it.
]]
function SessionRoundContract.neverWinsFromTheSpawnRoomAndLosesToTheClock(S: Session)
	requireModule("AC-4", S)
	local problems: { string } = {}
	local rounds, refusedAll, lostToClock = 0, 0, 0
	for _, n in SessionRoundContract.PLAYER_COUNTS do
		for seed = 1, SessionRoundContract.SEEDS do
			rounds += 1
			local run = scripted("AC-4", `the control script (seed {seed}, n = {n})`, function()
				return ScriptedRound.winFromSpawn(S, seed, n)
			end)
			local tag = `control seed {seed}, n = {n}`
			local allRefused = true
			for i, t in run.turns do
				local r = t.reply
				if
					not (
						typeof(r) == "table"
						and r.kind == "refused"
						and r.reason == "out_of_reach"
					)
				then
					allRefused = false
					table.insert(
						problems,
						`{tag}: turn #{i} from the spawn room replied {Deep.show(r)}, expected refused / out_of_reach`
					)
				end
				if t.phaseAfter ~= "Round" or t.outcomeAfter ~= nil then
					allRefused = false
					table.insert(
						problems,
						`{tag}: after turn #{i} the machine is {t.phaseAfter} / {Deep.show(
							t.outcomeAfter
						)}; a refused turn decides nothing`
					)
				end
			end
			if allRefused then
				refusedAll += 1
			end
			local clock = run.clock :: any
			if clock.phaseOneSecondBefore ~= "Round" then
				table.insert(
					problems,
					`{tag}: at {clock.deadline - 1} the phase is {clock.phaseOneSecondBefore}, expected Round`
				)
			end
			if
				clock.phaseAtDeadline == "Resolution"
				and outcomeIs(clock.outcomeAtDeadline, "lost", "clock")
			then
				lostToClock += 1
			else
				table.insert(
					problems,
					`{tag}: at the deadline {clock.deadline} the machine is {clock.phaseAtDeadline} / {Deep.show(
						clock.outcomeAtDeadline
					)}, expected Resolution / lost clock`
				)
			end
		end
	end
	print(
		`        [measured] AC-4 control: {refusedAll}/{rounds} rounds had every turn refused; {lostToClock}/{rounds} ended lost / clock on the deadline tick`
	)
	fewProblems(
		"AC-4",
		"the control - turns sent from the spawn room - must never win: every turn refused, and lost / clock on the deadline",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-5: the scripted loss by instability.
     --------------------------------------------------------------------- ]]

--[[
	For a few seeds at each n: each of the first `instability_max - 1` wrong
	turns is rejected wrong_setting, leaves the phase in Round, and the
	RoundView on the next Tick has a `secondsLeft` exactly
	`j x instability_clock_penalty_seconds` below an unpenalised twin's at the
	same `now`; the `instability_max`-th is rejected AND ends the round
	`lost / instability` in that step.
]]
function SessionRoundContract.losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView(
	S: Session
)
	requireModule("AC-5", S)
	local t = SessionRoundContract.tuning().actuation
	local max = t.instability_max
	local penalty = t.instability_clock_penalty_seconds
	local problems: { string } = {}
	local rounds, sameStep, dropsRight = 0, 0, 0
	for _, n in SessionRoundContract.PLAYER_COUNTS do
		for _, seed in SessionRoundContract.LOSS_SEEDS do
			rounds += 1
			local run = scripted("AC-5", `the instability script (seed {seed}, n = {n})`, function()
				return ScriptedRound.loseByInstability(S, seed, n)
			end)
			local tag = `seed {seed}, n = {n}`
			if #run.wrongTurns ~= max then
				table.insert(
					problems,
					`{tag}: the script made {#run.wrongTurns} wrong turns, expected instability_max = {max}`
				)
				continue
			end
			local allDrops = true
			for _, w in run.wrongTurns do
				local r = w.turn.reply
				if
					not (
						typeof(r) == "table"
						and r.kind == "rejected"
						and r.reason == "wrong_setting"
					)
				then
					table.insert(
						problems,
						`{tag}: wrong turn #{w.j} at {w.turn.now} replied {Deep.show(r)}, expected rejected / wrong_setting`
					)
				end
				if w.j < max then
					if w.turn.phaseAfter ~= "Round" then
						table.insert(
							problems,
							`{tag}: after wrong turn #{w.j} the phase is {w.turn.phaseAfter}, expected Round`
						)
					end
					local nt = w.nextTick :: any
					local want = if typeof(nt.unpenalisedSecondsLeft) == "number"
						then nt.unpenalisedSecondsLeft - w.j * penalty
						else nil
					if nt.secondsLeft ~= want or want == nil then
						allDrops = false
						table.insert(
							problems,
							`{tag}: after wrong turn #{w.j}, the RoundView at {nt.now} has secondsLeft {Deep.show(
								nt.secondsLeft
							)}; an unpenalised round at the same now has {Deep.show(
								nt.unpenalisedSecondsLeft
							)}, so {Deep.show(want)} was expected ({w.j} x {penalty} s lower)`
						)
					end
				else
					if
						w.turn.phaseAfter == "Resolution"
						and outcomeIs(w.turn.outcomeAfter, "lost", "instability")
					then
						sameStep += 1
					else
						table.insert(
							problems,
							`{tag}: after the {max}th wrong turn (at {w.turn.now}) the machine is {w.turn.phaseAfter} / {Deep.show(
								w.turn.outcomeAfter
							)}, expected Resolution / lost instability IN THAT STEP`
						)
					end
				end
			end
			if allDrops then
				dropsRight += 1
			end
		end
	end
	print(
		`        [measured] AC-5: {sameStep}/{rounds} rounds lost to instability in the {max}th wrong turn's step; {dropsRight}/{rounds} showed every {penalty} s drop`
	)
	fewProblems(
		"AC-5",
		`{max} wrong turns must end the round lost / instability in the step that takes the last one, each earlier one lowering the next RoundView's secondsLeft by {penalty} s per point`,
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-6: the clock, at every penalty level.
     --------------------------------------------------------------------- ]]

--[[
	For k in 0 .. instability_max - 1, at a few seeds: after k wrong turns and
	nothing else, the round resolves `lost / clock` on the tick at
	`startedAt + roundSeconds - k x instability_clock_penalty_seconds`, is
	still Round one second earlier, and for k >= 1 the machine's backstop tick
	is never reached.
]]
function SessionRoundContract.losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel(S: Session)
	requireModule("AC-6", S)
	local c = SessionRoundContract.config()
	local t = SessionRoundContract.tuning().actuation
	local problems: { string } = {}
	local checked, exact = 0, 0
	local n = SessionRoundContract.PLAYER_COUNTS[1]
	for k = 0, t.instability_max - 1 do
		for _, seed in { SessionRoundContract.LOSS_SEEDS[1], SessionRoundContract.LOSS_SEEDS[2] } do
			checked += 1
			local run = scripted("AC-6", `the clock script (k = {k}, seed {seed})`, function()
				return ScriptedRound.clockOut(S, seed, n, k)
			end)
			local expected = run.startedAt
				+ c.roundSeconds
				- k * t.instability_clock_penalty_seconds
			local tag = `k = {k} (seed {seed})`
			local good = true
			if run.resolvedAt ~= expected then
				good = false
				table.insert(
					problems,
					`{tag}: the round left Round at {Deep.show(run.resolvedAt)}, expected the tick at startedAt {run.startedAt} + roundSeconds {c.roundSeconds} - {k} x {t.instability_clock_penalty_seconds} = {expected}{if run.reachedBackstop
						then " (the machine's backstop tick was reached)"
						else ""}`
				)
			end
			if run.phaseOneSecondBefore ~= "Round" then
				good = false
				table.insert(
					problems,
					`{tag}: the tick one second before resolution found {Deep.show(
						run.phaseOneSecondBefore
					)}, expected Round`
				)
			end
			if run.resolvedAt ~= nil and run.phaseAtResolution ~= "Resolution" then
				good = false
				table.insert(
					problems,
					`{tag}: the resolving tick left the machine in {Deep.show(run.phaseAtResolution)}, expected Resolution - the Tick goes to the machine BEFORE the Procedure (C-3), or a clock-ended round moves straight on to Post`
				)
			end
			if not outcomeIs(run.outcome, "lost", "clock") then
				good = false
				table.insert(
					problems,
					`{tag}: the outcome is {Deep.show(run.outcome)}, expected lost / clock`
				)
			end
			if k >= 1 and run.reachedBackstop then
				good = false
				table.insert(
					problems,
					`{tag}: the backstop's tick at {run.backstopAt} was reached; the Procedure's deadline comes {k * t.instability_clock_penalty_seconds} s earlier`
				)
			end
			if good then
				exact += 1
			end
		end
	end
	print(
		`        [measured] AC-6: {exact}/{checked} (k, seed) cases resolved lost / clock exactly on the Procedure's deadline tick`
	)
	fewProblems(
		"AC-6",
		"with k points charged the round must resolve lost / clock on the tick at startedAt + roundSeconds - k x penalty, still Round a second earlier, the backstop never reached",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     Contract: purity.
     --------------------------------------------------------------------- ]]

function SessionRoundContract.stepMutatesNeitherStateNorEventOnRoundEvents(S: Session)
	local problems: { string } = {}
	local plans = {
		{ SessionRoundContract.lifecycle(), nil },
		{
			SessionRoundContract.generationFailure(),
			{ generatorPredicate = SessionRoundContract.refuseAll },
		},
	}
	for _, pair in plans do
		for _, step in SessionRoundContract.run(S, "Contract", pair[1], pair[2]) do
			if not Deep.equal(step.beforeLive, step.before) then
				table.insert(
					problems,
					`"{step.label}": step mutated its state argument:\n{Contract.firstFew(
						string.split(Deep.diff(step.before, step.beforeLive), "\n"),
						4
					)}`
				)
			end
			if not Deep.equal(step.event, step.eventSnapshot) then
				table.insert(
					problems,
					`"{step.label}": step mutated its event argument:\n{Deep.diff(
						step.eventSnapshot,
						step.event
					)}`
				)
			end
		end
	end
	fewProblems(
		"Contract",
		"step must mutate neither state nor event, PositionsSampled and TurnRequested included",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     The battery, named.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Session) -> () }

SessionRoundContract.CHECKS = {
	{
		name = "newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions",
		ac = "Contract",
		run = SessionRoundContract.newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions,
	},
	{
		name = "roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep",
		ac = "Contract",
		run = SessionRoundContract.roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep,
	},
	{
		name = "generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep",
		ac = "AC-1",
		run = SessionRoundContract.generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep,
	},
	{
		name = "placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder",
		ac = "AC-1",
		run = SessionRoundContract.placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder,
	},
	{
		name = "resolvesAFailedGenerationAsNoContestInTheDealingStep",
		ac = "AC-2",
		run = SessionRoundContract.resolvesAFailedGenerationAsNoContestInTheDealingStep,
	},
	{
		name = "handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone",
		ac = "AC-3",
		run = SessionRoundContract.handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone,
	},
	{
		name = "mergesAcceptedSamplesAndEmitsOnlyResyncPlacements",
		ac = "Contract",
		run = SessionRoundContract.mergesAcceptedSamplesAndEmitsOnlyResyncPlacements,
	},
	{
		name = "ignoresATurnOutsideRoundOrWithoutAProcedure",
		ac = "Contract",
		run = SessionRoundContract.ignoresATurnOutsideRoundOrWithoutAProcedure,
	},
	{
		name = "clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions",
		ac = "Contract",
		run = SessionRoundContract.clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions,
	},
	{
		name = "ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast",
		ac = "Contract",
		run = SessionRoundContract.ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast,
	},
	{
		name = "secondsLeftReadsTheProcedureDeadlineInRound",
		ac = "Contract",
		run = SessionRoundContract.secondsLeftReadsTheProcedureDeadlineInRound,
	},
	{
		name = "winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn",
		ac = "AC-4",
		run = SessionRoundContract.winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn,
	},
	{
		name = "neverWinsFromTheSpawnRoomAndLosesToTheClock",
		ac = "AC-4",
		run = SessionRoundContract.neverWinsFromTheSpawnRoomAndLosesToTheClock,
	},
	{
		name = "losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView",
		ac = "AC-5",
		run = SessionRoundContract.losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView,
	},
	{
		name = "losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel",
		ac = "AC-6",
		run = SessionRoundContract.losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel,
	},
	{
		name = "stepMutatesNeitherStateNorEventOnRoundEvents",
		ac = "Contract",
		run = SessionRoundContract.stepMutatesNeitherStateNorEventOnRoundEvents,
	},
} :: { Check }

function SessionRoundContract.failures(S: Session): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in SessionRoundContract.CHECKS do
		local ok, err = pcall(check.run, S)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return SessionRoundContract
