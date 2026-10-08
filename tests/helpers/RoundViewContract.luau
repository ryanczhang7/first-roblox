--!strict
--[[
	VIEW-003 AC-1 through AC-5 and the story's Contract pins (C-3..C-9),
	written once as checks over a VIEW MODULE handed in as a parameter - the
	`LensViewContract.luau` arrangement, for the same reason.

	`tests/server/round_view_test.luau` applies these to the real
	`src/server/round/RoundView.luau`. `tests/server/round_view_controls_test.luau`
	applies them to a reference and to the deliberately wrong builders in
	`RoundViewStubs.luau`, so that in RED - where the module does not exist,
	the real file fails at the load check, and not one assertion in it has
	executed against the module - every check here has still been EXECUTED
	and observed to reject the builder it exists to catch.

	A `V` here is a table of two plain functions, called with a dot exactly
	as the story's Contract (C-2) writes them:

	    V.public(input, now) -> RoundView
	    V.facility(facility) -> FacilityView

	THE ORACLE PARTITION (story `## Contract`). AC-1 and AC-5 are SETTLED by
	`mechanics.md` §3.2's "must never show" table: the checks are named after
	its rows and every extra key is attributed to the row it breaks. AC-2,
	AC-3 and AC-4 are MECHANICAL: `expectedDial` is C-5's precedence written
	here over `procedure.committed`, `procedure.armed`, `Procedure.dial` and
	the actuation log; `expectedSecondsLeft` is C-7 over `Procedure.deadline`
	and `RoundConfig`; `expectedFacility` is C-8 over the layout and the
	placement. Nothing below reads an expected value off the view under test.

	THE SCENARIO IS PLAYED FOR REAL. `TurnContract`'s hand-built facility (7
	steps in two tracks, two decoys, `procedure_length` 8 - so `total` and
	`#steps` differ) goes through the real `Procedure.start` and `Procedure.turn`:
	a wrong turn on the live head of track 1 (REJECTED, with a turned setting
	that differs from the required one - AC-2's named fixture), the same state
	past the reset window (UNSET, with that turn still in the log), a turn on
	a decoy (not_live, charged 2 under the fixture tuning, so the blackout
	threshold is crossed and a room goes DARK), every ordinary step committed,
	the finale ARMED, a wrong turn on the other finale machine (both REJECTED,
	a second room dark), and the finale re-armed and COMMITTED (won). Each
	snapshot is an `Input` at a `now`, with the partner-lamp positions varied
	on the live-finale snapshot. A generated sample (`Generator.generate` at
	n in { 4, 5, 6 }) supplies 16-machine facilities for the shape and
	facility checks.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Generator = require("../../src/server/facility/Generator")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PhaseMachine = require("../../src/server/round/PhaseMachine")
local Procedure = require("../../src/server/procedure/Procedure")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local RoundConfig = require("../../src/server/round/RoundConfig")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")
local Turn = require("./TurnContract")

local RoundViewContract = {}

export type View = any
export type Input = any

export type Snapshot = {
	label: string,
	input: Input,
	now: number,
	-- What the snapshot was built to exercise, for the preconditions.
	tags: { [string]: boolean },
}

RoundViewContract.COUNTS = { 4, 5, 6 }
RoundViewContract.GENERATED_SEEDS = { 1, 2, 3, 4 }

-- The ten keys, sorted as `keysOf` sorts them. `secondsLeft` is absent when
-- nil, so the expected list is built per snapshot.
RoundViewContract.ROUND_VIEW_KEYS = {
	"dark",
	"instability",
	"machines",
	"phase",
	"pings",
	"players",
	"playersMax",
	"playersMin",
	"progress",
	"secondsLeft",
}
RoundViewContract.PROGRESS_KEYS = { "committed", "total" }
RoundViewContract.FACILITY_KEYS = { "doors", "machines", "rooms", "spawnRoom" }
RoundViewContract.FACILITY_MACHINE_KEYS = { "id", "keyClass", "room", "slot", "tag" }

-- `mechanics.md` §3.2, "The bar must never show": a key name -> the row it
-- breaks. The story adds the seat relation, the lens reading and the outcome
-- (AC-5), which travel elsewhere or nowhere.
local ROWS: { [string]: string } = {
	live = "which step is live or next, in any track",
	next = "which step is live or next, in any track",
	turnCues = "which step is live or next, in any track",
	cues = "which step is live or next, in any track",
	track = "per-track progress, or which track a commit belonged to",
	tracks = "per-track progress, or which track a commit belonged to",
	byTrack = "per-track progress, or which track a commit belonged to",
	perTrack = "per-track progress, or which track a commit belonged to",
	machine = "any machine, tag, room, key class, colour or player for any segment",
	machineId = "any machine, tag, room, key class, colour or player for any segment",
	tag = "any machine, tag, room, key class, colour or player for any segment",
	room = "any machine, tag, room, key class, colour or player for any segment",
	keyClass = "any machine, tag, room, key class, colour or player for any segment",
	colour = "any machine, tag, room, key class, colour or player for any segment",
	player = "any machine, tag, room, key class, colour or player for any segment",
	armed = "the finale's armed or partner-lamp state",
	partnerLamp = "the finale's armed or partner-lamp state",
	time = "time, pace, par, or a forecast",
	pace = "time, pace, par, or a forecast",
	par = "time, pace, par, or a forecast",
	forecast = "time, pace, par, or a forecast",
	deadline = "time, pace, par, or a forecast",
	outcome = "the outcome travels in TraceView (TRACE-002), never here",
	sigma = "the seat relation is a per-player secret (roles.md section 6)",
	seats = "the seat relation is a per-player secret (roles.md section 6)",
	seatOrder = "the seat relation is a per-player secret (roles.md section 6)",
	lens = "a lens reading is a per-player secret (roles.md section 6)",
	readings = "a lens reading is a per-player secret (roles.md section 6)",
	lensReadings = "a lens reading is a per-player secret (roles.md section 6)",
}

local function rowFor(key: string): string
	local row = ROWS[key]
	if row ~= nil then
		return `"{key}" breaks the row "{row}"`
	end
	return `"{key}" is not one of the keys the Contract names`
end

--[[ ------------------------------------------------------------------------
     Small instruments.
     --------------------------------------------------------------------- ]]

function RoundViewContract.keysOf(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

local function joined(list: { any }): string
	local parts: { string } = {}
	for _, item in list do
		table.insert(parts, tostring(item))
	end
	return "[" .. table.concat(parts, ", ") .. "]"
end

-- The keys of `got` that `want` does not have, and the reverse.
local function keyDiff(want: { string }, got: { string }): ({ string }, { string })
	local extra: { string } = {}
	local missing: { string } = {}
	for _, k in got do
		if table.find(want, k) == nil then
			table.insert(extra, k)
		end
	end
	for _, k in want do
		if table.find(got, k) == nil then
			table.insert(missing, k)
		end
	end
	return extra, missing
end

-- Every table reachable from `value`, keyed by identity.
local function tablesIn(value: any, seen: { [any]: boolean }): { [any]: boolean }
	if typeof(value) == "table" and not seen[value] then
		seen[value] = true
		for k, v in pairs(value :: { [any]: any }) do
			tablesIn(k, seen)
			tablesIn(v, seen)
		end
	end
	return seen
end

-- Every table reachable from both sides: the aliasing C-9 forbids.
local function sharedTables(a: any, b: any): number
	local left = tablesIn(a, {})
	local right = tablesIn(b, {})
	local shared = 0
	for t in pairs(left) do
		if right[t] then
			shared += 1
		end
	end
	return shared
end

local function fewProblems(criterion: string, headline: string, problems: { string })
	if #problems > 0 then
		Contract.fail(`{criterion}: {headline}:\n{Contract.firstFew(problems, 12)}`)
	end
end

local function machineById(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end
RoundViewContract.machineById = machineById

--[[ ------------------------------------------------------------------------
     The round state and the config.
     --------------------------------------------------------------------- ]]

function RoundViewContract.config(): RoundConfig.RoundConfig
	return RoundConfig.fromTuning(Tuning)
end

-- A `PhaseMachine.RoundState` in `phase`, entered at `enteredAt`, with
-- `players` seated. `PhaseMachine.initial` is the only honest source of the
-- other fields; the three the view reads are set on a clone.
function RoundViewContract.roundIn(phase: string, enteredAt: number, players: { string }): any
	local state: any = table.clone(
		PhaseMachine.initial(RoundViewContract.config(), 7, "round-view", "session-view")
	)
	state.phase = phase
	state.phaseEnteredAt = enteredAt
	state.players = table.clone(players)
	return state
end

-- The pings every snapshot carries: already shown, as `Pings.shown` returns
-- them. One with a setting, one without.
function RoundViewContract.pings(): { any }
	return {
		{ senderId = "amy", kind = "setting", target = 12, setting = 3 },
		{ senderId = "kim", kind = "doorway", target = 1 },
	}
end

local function input(
	round: any,
	procedure: any,
	assignment: any,
	positions: any,
	tuning: any,
	pings: any?
): Input
	return {
		round = round,
		procedure = procedure,
		assignment = assignment,
		positions = positions,
		pings = if pings ~= nil then pings else RoundViewContract.pings(),
		tuning = tuning,
	}
end
RoundViewContract.input = input

--[[ ------------------------------------------------------------------------
     The played scenario.
     --------------------------------------------------------------------- ]]

-- The holder of `id`, standing at it, turning it to `setting` at `now`;
-- the result must be `expect` or the scenario is not the one described.
local function turnBy(
	w: Turn.World,
	state: any,
	id: number,
	setting: number,
	now: number,
	expect: any
): any
	local holder = Turn.holderOf(w.facility, id)
	local next_, result = Procedure.turn(
		state,
		w.assignment,
		holder,
		id,
		setting,
		now,
		Turn.standingAt(w, holder, id)
	)
	if not Deep.equal(result, expect) then
		Contract.fail(
			`scenario: {holder} turning machine {id} to {setting} at {now} returned {Deep.show(
				result
			)}, expected {Deep.show(expect)}`
		)
	end
	return next_
end

local function rejected(id: number, reason: string): any
	return { kind = "rejected", machineId = id, reason = reason }
end

export type Scenario = {
	world: Turn.World,
	snapshots: { Snapshot },
	-- The ids the scenario promises, for the preconditions.
	rejectedId: number,
	decoyId: number,
	finale: { number },
}

--[[
	The scenario, rebuilt on every call (nothing here is shared between
	checks). Labels are the ones the controls grep for.
]]
function RoundViewContract.scenario(): Scenario
	local w = Turn.world()
	local tuning = w.tuning
	local round = RoundViewContract.roundIn("Round", Turn.NOW, Turn.PLAYERS)
	local t1, t2 = Turn.TRACK_1, Turn.TRACK_2
	local A, B = Turn.FINALE[1], Turn.FINALE[2]
	local decoy = Turn.DECOYS[2] -- 19: key class 1, kim's
	local snapshots: { Snapshot } = {}
	local function snap(
		label: string,
		state: any,
		now: number,
		positions: any,
		tags: { string },
		assignment: any?
	)
		local tagSet: { [string]: boolean } = {}
		for _, tag in tags do
			tagSet[tag] = true
		end
		table.insert(snapshots, {
			label = label,
			input = input(round, state, assignment, positions, tuning),
			now = now,
			tags = tagSet,
		})
	end
	local nobody: { [string]: any } = {}

	local s0 = Procedure.start(w.facility, Turn.NOW, tuning, Turn.ROUND_SEED, Turn.ROUND_SECONDS)
	snap("start: nothing turned", s0, Turn.NOW, nobody, { "unpenalised" }, w.assignment)

	-- A wrong turn on the live head of track 1: rejected, charged 1.
	local head = t1[1]
	local wrong = Turn.wrongSetting(w.facility, head, tuning)
	local s1 = turnBy(w, s0, head, wrong, Turn.NOW + 1, rejected(head, "wrong_setting"))
	snap(
		`rejected: machine {head} turned to {wrong} (required {Turn.requiredSetting(
			w.facility,
			head
		)}), inside its reset window`,
		s1,
		Turn.NOW + 2,
		nobody,
		{ "rejected", "penalised" },
		w.assignment
	)
	local reset = tuning.actuation.actuation_reset_seconds
	snap(
		`reset: machine {head} past its reset window, the wrong turn still in the log`,
		s1,
		Turn.NOW + 1 + reset + 1,
		nobody,
		{ "resetUnset", "penalised" },
		w.assignment
	)

	-- A decoy turned: not_live, charged 2 under the fixture tuning, so
	-- instability crosses the blackout threshold and a room goes dark.
	local decoyAt = Turn.NOW + 1 + reset + 1
	local s2 = turnBy(w, s1, decoy, 2, decoyAt, rejected(decoy, "not_live"))
	snap(
		`decoy: machine {decoy} turned to 2 and rejected not_live; one room dark`,
		s2,
		decoyAt + 1,
		nobody,
		{ "decoyRejected", "dark", "penalised" },
		w.assignment
	)

	-- Track 1's ordinary steps committed first: its finale step waits at
	-- position 0 and is NOT live (mechanics.md section 3.2, G12).
	local s3 = s2
	local at = decoyAt + reset + 1
	for _, id in { t1[1], t1[2] } do
		s3 = turnBy(
			w,
			s3,
			id,
			Turn.requiredSetting(w.facility, id),
			at,
			{ kind = "committed", machineId = id }
		)
		at += 1
	end
	snap(
		`one track done: machine {A} waits at position 0, not live`,
		s3,
		at,
		nobody,
		{ "oneTrackDone", "committed", "penalised" },
		w.assignment
	)
	-- Then track 2's, one second apart.
	for _, id in { t2[1], t2[2], t2[3] } do
		s3 = turnBy(
			w,
			s3,
			id,
			Turn.requiredSetting(w.facility, id),
			at,
			{ kind = "committed", machineId = id }
		)
		at += 1
	end
	local holderA, holderB = Turn.holderOf(w.facility, A), Turn.holderOf(w.facility, B)
	local both = { [holderA] = Turn.at(w, A), [holderB] = Turn.at(w, B) }
	local onlyA = { [holderA] = Turn.at(w, A) }
	snap(
		"finale live: both holders at their machines",
		s3,
		at,
		both,
		{ "finaleLive", "lampsBoth", "committed", "penalised" },
		w.assignment
	)
	snap(
		`finale live: only {holderA} at machine {A}`,
		s3,
		at,
		onlyA,
		{ "finaleLive", "lampsOne", "penalised" },
		w.assignment
	)
	snap(
		"finale live: nobody placed",
		s3,
		at,
		nobody,
		{ "finaleLive", "lampsNone", "penalised" },
		w.assignment
	)
	snap(
		"finale live: no assignment",
		s3,
		at,
		both,
		{ "finaleLive", "noAssignment", "penalised" },
		nil
	)

	-- The finale armed.
	local s4 = turnBy(
		w,
		s3,
		A,
		Turn.requiredSetting(w.facility, A),
		at + 1,
		{ kind = "armed", machineId = A }
	)
	snap(
		`armed: machine {A} armed, machine {B} untouched`,
		s4,
		at + 2,
		both,
		{ "armed", "penalised" },
		w.assignment
	)

	-- A wrong turn on the other finale machine: both rejected, a second room dark.
	local wrongB = Turn.wrongSetting(w.facility, B, tuning)
	local s5 = turnBy(w, s4, B, wrongB, at + 3, rejected(B, "wrong_setting"))
	snap(
		`disarmed: machine {B} turned to {wrongB} and rejected, machine {A} disarmed; two rooms dark`,
		s5,
		at + 4,
		both,
		{ "disarmed", "twoDark", "penalised" },
		w.assignment
	)

	-- Re-armed and committed together: won.
	local again = at + 3 + reset + 1
	local s6 = turnBy(
		w,
		s5,
		A,
		Turn.requiredSetting(w.facility, A),
		again,
		{ kind = "armed", machineId = A }
	)
	local s7 = turnBy(
		w,
		s6,
		B,
		Turn.requiredSetting(w.facility, B),
		again + 1,
		{ kind = "committed", machineId = B }
	)
	if s7.outcome == nil or s7.outcome.result ~= "won" then
		Contract.fail(
			`scenario: the completing turn left outcome {Deep.show(s7.outcome)}, expected won`
		)
	end
	snap("won: every step committed", s7, again + 2, both, { "won", "penalised" }, w.assignment)

	return {
		world = w,
		snapshots = snapshots,
		rejectedId = head,
		decoyId = decoy,
		finale = { A, B },
	}
end

--[[ ------------------------------------------------------------------------
     The generated sample: 16-machine facilities, at their start state.
     --------------------------------------------------------------------- ]]

local function playersFor(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = `p{i}`
	end
	return out
end

export type Generated = { n: number, seed: number, assignment: any, facility: any, procedure: any }

function RoundViewContract.generated(): { Generated }
	local out: { Generated } = {}
	for _, n in RoundViewContract.COUNTS do
		for _, seed in RoundViewContract.GENERATED_SEEDS do
			local assignment = Ring.assign(playersFor(n), Rng.fromSeed(seed))
			local result = Generator.generate(assignment, seed, MechanicsTuning)
			if result.kind ~= "facility" then
				Contract.fail(
					`the sample needs a facility at n = {n}, seed {seed}: {Deep.show(result)}`
				)
			end
			local facility = (result :: any).facility
			table.insert(out, {
				n = n,
				seed = seed,
				assignment = assignment,
				facility = facility,
				procedure = Procedure.start(
					facility,
					Turn.NOW,
					MechanicsTuning,
					seed,
					Turn.ROUND_SECONDS
				),
			})
		end
	end
	return out
end

-- The generated starts as snapshots, plus one with rooms darkened out of
-- order on a fresh copy (plain data), so `dark` has to be sorted.
local function generatedSnapshots(): { Snapshot }
	local out: { Snapshot } = {}
	for _, g in RoundViewContract.generated() do
		local round = RoundViewContract.roundIn("Round", Turn.NOW, g.assignment.players)
		table.insert(out, {
			label = `generated n = {g.n}, seed {g.seed}: start`,
			input = input(round, g.procedure, g.assignment, {}, MechanicsTuning),
			now = Turn.NOW + 3.5,
			tags = { generated = true, unpenalised = true },
		})
	end
	local g = RoundViewContract.generated()[1]
	local darkened: any = table.clone(g.procedure)
	darkened.dark = { [4] = true, [1] = true, [3] = true, [2] = false }
	table.insert(out, {
		label = `generated n = {g.n}, seed {g.seed}: dark written as 4, 1, 3 (and 2 = false)`,
		input = input(
			RoundViewContract.roundIn("Round", Turn.NOW, g.assignment.players),
			darkened,
			g.assignment,
			{},
			MechanicsTuning
		),
		now = Turn.NOW + 1,
		tags = { generated = true, darkUnordered = true },
	})
	return out
end

--[[ ------------------------------------------------------------------------
     The other phases (C-3, C-7).
     --------------------------------------------------------------------- ]]

local function phaseSnapshots(): { Snapshot }
	local scenario = RoundViewContract.scenario()
	local w = scenario.world
	local won = scenario.snapshots[#scenario.snapshots].input.procedure
	local c = RoundViewContract.config()
	local players = Turn.PLAYERS
	local few = { players[1], players[2] }
	if #few >= c.playersMin then
		Contract.fail(
			`the short-lobby fixture needs fewer than playersMin = {c.playersMin} players`
		)
	end
	if #players < c.playersMin or #players > c.playersMax then
		Contract.fail(`the fixture's {#players} players do not fit playersMin..playersMax`)
	end
	local out: { Snapshot } = {}
	local function snap(
		label: string,
		phase: string,
		enteredAt: number,
		who: { string },
		procedure: any,
		now: number,
		tags: { string }
	)
		local tagSet: { [string]: boolean } = { phase = true }
		for _, tag in tags do
			tagSet[tag] = true
		end
		table.insert(out, {
			label = label,
			input = input(
				RoundViewContract.roundIn(phase, enteredAt, who),
				procedure,
				if procedure then w.assignment else nil,
				{},
				w.tuning
			),
			now = now,
			tags = tagSet,
		})
	end
	snap("Lobby at playersMin, 1.5 s in", "Lobby", 50, players, nil, 51.5, { "lobbyTimed" })
	snap("Lobby below playersMin", "Lobby", 50, few, nil, 51.5, { "noClock" })
	snap(
		"Lobby past lobbySeconds",
		"Lobby",
		50,
		players,
		nil,
		50 + c.lobbySeconds + 4,
		{ "clamped" }
	)
	snap("Assignment", "Assignment", 50, players, nil, 51, { "noClock" })
	snap(
		"Round with no Procedure, 0.5 s in",
		"Round",
		50,
		players,
		nil,
		50.5,
		{ "roundNoProcedure" }
	)
	snap(
		"Round with no Procedure, past roundSeconds",
		"Round",
		50,
		players,
		nil,
		50 + c.roundSeconds + 2.25,
		{ "roundNoProcedure", "clamped" }
	)
	snap(
		"Resolution, the won Procedure still held",
		"Resolution",
		200,
		players,
		won,
		201,
		{ "noClock", "procedureHeld" }
	)
	snap(
		"Post, the won Procedure still held, 2 s in",
		"Post",
		200,
		players,
		won,
		202,
		{ "postTimed", "procedureHeld" }
	)
	snap(
		"Post past postRoundSeconds",
		"Post",
		200,
		players,
		nil,
		200 + c.postRoundSeconds + 1,
		{ "clamped" }
	)

	-- Round with a Procedure whose deadline has passed: the clamp (AC-4).
	local late: any = table.clone(won)
	late.startedAt = 0
	late.roundSeconds = 10
	late.penaltySeconds = 0
	late.outcome = nil
	table.insert(out, {
		label = "Round with a Procedure 90 s past its deadline",
		input = input(
			RoundViewContract.roundIn("Round", 0, players),
			late,
			w.assignment,
			{},
			w.tuning
		),
		now = 100,
		tags = { phase = true, pastDeadline = true, clamped = true },
	})
	return out
end

-- Every snapshot: the played scenario, the generated starts, the phases.
function RoundViewContract.snapshots(): { Snapshot }
	local out: { Snapshot } = {}
	for _, s in RoundViewContract.scenario().snapshots do
		table.insert(out, s)
	end
	for _, s in generatedSnapshots() do
		table.insert(out, s)
	end
	for _, s in phaseSnapshots() do
		table.insert(out, s)
	end
	return out
end

--[[ ------------------------------------------------------------------------
     The oracle: C-3 .. C-8, written here.
     --------------------------------------------------------------------- ]]

local function inRoundWithProcedure(inp: Input): boolean
	return inp.round.phase == "Round" and inp.procedure ~= nil
end

-- C-7, with the clamp.
function RoundViewContract.expectedSecondsLeft(inp: Input, now: number): number?
	local round = inp.round
	local c = round.config
	local raw: number
	if inRoundWithProcedure(inp) then
		raw = math.ceil(Procedure.deadline(inp.procedure) - now)
	else
		local duration: number? = nil
		if round.phase == "Lobby" and #round.players >= c.playersMin then
			duration = c.lobbySeconds
		elseif round.phase == "Round" then
			duration = c.roundSeconds
		elseif round.phase == "Post" then
			duration = c.postRoundSeconds
		end
		if duration == nil then
			return nil
		end
		raw = math.ceil(duration - (now - round.phaseEnteredAt))
	end
	return math.max(0, raw)
end

-- The setting of the LAST log entry for `id`: every entry is an evaluated
-- turn that moved the dial (C-5, as amended in RED - `not_live` included).
local function lastTurnedSetting(procedure: any, id: number): number?
	for i = #procedure.log, 1, -1 do
		local entry = procedure.log[i]
		if entry.machineId == id then
			return entry.setting
		end
	end
	return nil
end

-- C-5's precedence.
function RoundViewContract.expectedDial(procedure: any, id: number, now: number): any
	local state: string
	if procedure.committed[id] then
		state = "committed"
	elseif procedure.armed ~= nil and procedure.armed.machineId == id then
		state = "armed"
	elseif Procedure.dial(procedure, id, now).state == "rejected" then
		state = "rejected"
	else
		state = "unset"
	end
	local dial: any = { state = state }
	if state ~= "unset" then
		dial.setting = lastTurnedSetting(procedure, id)
	end
	return dial
end

local function sortedIds(facility: any): { number }
	local ids: { number } = {}
	for _, m in facility.placement.machines do
		table.insert(ids, m.id)
	end
	table.sort(ids)
	return ids
end

function RoundViewContract.expectedMachines(inp: Input, now: number): { any }
	local procedure = inp.procedure
	local facility = procedure.facility
	local lamps: { [number]: boolean } = {}
	if inp.assignment ~= nil then
		lamps = Procedure.partnerLamps(procedure, inp.assignment, inp.positions)
	end
	local out: { any } = {}
	for _, id in sortedIds(facility) do
		local record: any = {
			id = id,
			dial = RoundViewContract.expectedDial(procedure, id, now),
			live = Procedure.isLive(procedure, id),
		}
		if table.find(facility.steps.finale, id) ~= nil then
			record.partnerLamp = lamps[id] == true
		end
		table.insert(out, record)
	end
	return out
end

function RoundViewContract.expectedDark(procedure: any): { number }
	local out: { number } = {}
	for _, room in procedure.facility.layout.rooms do
		if procedure.dark[room.id] == true then
			table.insert(out, room.id)
		end
	end
	table.sort(out)
	return out
end

function RoundViewContract.expectedCommitted(procedure: any): number
	local n = 0
	for _, flag in pairs(procedure.committed) do
		if flag == true then
			n += 1
		end
	end
	return n
end

function RoundViewContract.expected(inp: Input, now: number): any
	local round = inp.round
	local view: any = {
		phase = round.phase,
		secondsLeft = RoundViewContract.expectedSecondsLeft(inp, now),
		players = table.clone(round.players),
		playersMin = round.config.playersMin,
		playersMax = round.config.playersMax,
		progress = { committed = 0, total = inp.tuning.instance.procedure_length },
		instability = 0,
		dark = {},
		pings = Deep.copy(inp.pings),
		machines = {},
	}
	if inRoundWithProcedure(inp) then
		view.instability = inp.procedure.instability
		view.dark = RoundViewContract.expectedDark(inp.procedure)
		view.progress.committed = RoundViewContract.expectedCommitted(inp.procedure)
		view.machines = RoundViewContract.expectedMachines(inp, now)
	end
	return view
end

-- C-8.
function RoundViewContract.expectedFacility(facility: any): any
	local rooms: { any } = {}
	for _, room in facility.layout.rooms do
		table.insert(rooms, { id = room.id, column = room.column, row = room.row })
	end
	table.sort(rooms, function(a: any, b: any): boolean
		return a.id < b.id
	end)
	local doors: { any } = {}
	for _, door in facility.layout.doors do
		table.insert(doors, { a = math.min(door.a, door.b), b = math.max(door.a, door.b) })
	end
	table.sort(doors, function(x: any, y: any): boolean
		if x.a ~= y.a then
			return x.a < y.a
		end
		return x.b < y.b
	end)
	local machines: { any } = {}
	for _, id in sortedIds(facility) do
		local m = machineById(facility, id)
		table.insert(
			machines,
			{ id = m.id, room = m.room, slot = m.slot, tag = m.tag, keyClass = m.keyClass }
		)
	end
	return {
		rooms = rooms,
		doors = doors,
		spawnRoom = facility.layout.spawnRoom,
		machines = machines,
	}
end

-- The facilities the AC-3 check runs over: the fixture, the fixture with its
-- doors listed out of order and one reversed, and the generated sample.
function RoundViewContract.facilities(): { { label: string, facility: any } }
	local out: { { label: string, facility: any } } = {}
	table.insert(out, { label = "the fixture facility", facility = Turn.facility() })
	local shuffled = Turn.facility()
	shuffled.layout.doors =
		{ { a = 3, b = 4 }, { a = 4, b = 2 }, { a = 1, b = 3 }, { a = 1, b = 2 } }
	table.insert(
		out,
		{ label = "the fixture with doors listed 3-4, 4-2, 1-3, 1-2", facility = shuffled }
	)
	for _, g in RoundViewContract.generated() do
		table.insert(out, { label = `generated n = {g.n}, seed {g.seed}`, facility = g.facility })
	end
	return out
end

--[[ ------------------------------------------------------------------------
     Running the view.
     --------------------------------------------------------------------- ]]

-- `V.public` on a snapshot, as a table, or a problem line.
local function build(V: View, s: Snapshot, criterion: string, problems: { string }): any?
	local ok, result = pcall(V.public, s.input, s.now)
	if not ok then
		table.insert(
			problems,
			`{criterion}: "{s.label}": public(input, {s.now}) raised: {tostring(result)}`
		)
		return nil
	end
	if typeof(result) ~= "table" then
		table.insert(
			problems,
			`{criterion}: "{s.label}": public(input, {s.now}) returned {Deep.show(result)}, not a table`
		)
		return nil
	end
	return result
end

local function needTag(snapshots: { Snapshot }, tag: string, criterion: string)
	for _, s in snapshots do
		if s.tags[tag] then
			return
		end
	end
	Contract.fail(
		`{criterion} precondition: no snapshot is tagged "{tag}", so the check would prove nothing`
	)
end

--[[ ------------------------------------------------------------------------
     AC-5 (settled by mechanics.md section 3.2): the ten keys and nothing else.
     --------------------------------------------------------------------- ]]

function RoundViewContract.topLevelKeysAreExactlyTheTen(V: View, snapshots: { Snapshot }?)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "phase", "AC-5")
	needTag(all, "finaleLive", "AC-5")
	for _, s in all do
		local view = build(V, s, "AC-5", problems)
		if view == nil then
			continue
		end
		local want = table.clone(RoundViewContract.ROUND_VIEW_KEYS)
		if RoundViewContract.expectedSecondsLeft(s.input, s.now) == nil then
			table.remove(want, table.find(want, "secondsLeft") :: number)
		end
		local got = RoundViewContract.keysOf(view)
		local extra, missing = keyDiff(want, got)
		for _, key in extra do
			table.insert(
				problems,
				`AC-5: "{s.label}": the view carries an extra top-level key {rowFor(key)}`
			)
		end
		for _, key in missing do
			table.insert(problems, `AC-5: "{s.label}": the view is missing "{key}"`)
		end
		if #extra == 0 and #missing == 0 and not Deep.equal(got, want) then
			table.insert(
				problems,
				`AC-5: "{s.label}": keys are {joined(got)}, expected {joined(want)}`
			)
		end
	end
	fewProblems(
		"AC-5",
		"a RoundView's top-level keys are exactly phase, secondsLeft (absent when nil), players, playersMin, playersMax, progress, instability, dark, pings, machines - no sigma, seat relation, turn cue, lens reading, par or outcome",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-1 (settled) and C-4: the bar is exactly { committed, total }.
     --------------------------------------------------------------------- ]]

function RoundViewContract.progressIsExactlyCommittedStepsOverProcedureLength(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "won", "AC-1")
	needTag(all, "committed", "AC-1")
	needTag(all, "phase", "AC-1")
	local fixture = Turn.facility()
	local steps = 0
	for _, track in fixture.steps.tracks do
		steps += #track
	end
	if steps == MechanicsTuning.instance.procedure_length then
		Contract.fail(
			`AC-1 precondition: the fixture has {steps} steps, equal to procedure_length; total = #steps would pass`
		)
	end
	for _, s in all do
		local view = build(V, s, "AC-1", problems)
		if view == nil then
			continue
		end
		local progress = view.progress
		if typeof(progress) ~= "table" then
			table.insert(
				problems,
				`AC-1: "{s.label}": progress is {Deep.show(progress)}, not a table`
			)
			continue
		end
		local got = RoundViewContract.keysOf(progress)
		local extra, missing = keyDiff(RoundViewContract.PROGRESS_KEYS, got)
		for _, key in extra do
			table.insert(
				problems,
				`AC-1: "{s.label}": progress carries an extra key {rowFor(key)}; the bar is exactly \{ committed, total }`
			)
		end
		for _, key in missing do
			table.insert(problems, `AC-1: "{s.label}": progress is missing "{key}"`)
		end
		local total = s.input.tuning.instance.procedure_length
		if progress.total ~= total then
			table.insert(
				problems,
				`AC-1: "{s.label}": progress.total is {Deep.show(progress.total)}, expected procedure_length = {total} (never #steps)`
			)
		end
		local committed = 0
		if inRoundWithProcedure(s.input) then
			committed = RoundViewContract.expectedCommitted(s.input.procedure)
		end
		if progress.committed ~= committed then
			local note = ""
			if inRoundWithProcedure(s.input) and progress.committed == #s.input.procedure.log then
				note = ` - that is #procedure.log, which counts rejected turns (C-4)`
			end
			table.insert(
				problems,
				`AC-1: "{s.label}": progress.committed is {Deep.show(progress.committed)}, expected {committed} committed steps{note}`
			)
		end
	end
	fewProblems(
		"AC-1",
		"the progress bar is exactly { committed = the number of committed steps, total = procedure_length } (mechanics.md section 3.2, 'steps committed, out of procedure_length')",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-2 (mechanical): the dial, by C-5's precedence, never from the secret.
     --------------------------------------------------------------------- ]]

function RoundViewContract.dialIsTheLastTurnedSettingNeverTheRequiredOne(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	for _, tag in { "rejected", "resetUnset", "decoyRejected", "armed", "disarmed", "won" } do
		needTag(all, tag, "AC-2")
	end
	local rejectedDiffers = 0
	for _, s in all do
		if not inRoundWithProcedure(s.input) then
			continue
		end
		local view = build(V, s, "AC-2", problems)
		if view == nil or typeof(view.machines) ~= "table" then
			continue
		end
		local procedure = s.input.procedure
		local byId: { [number]: any } = {}
		for _, record in view.machines do
			if typeof(record) == "table" and typeof(record.id) == "number" then
				byId[record.id] = record
			end
		end
		for _, id in sortedIds(procedure.facility) do
			local want = RoundViewContract.expectedDial(procedure, id, s.now)
			local required = machineById(procedure.facility, id).requiredSetting
			if want.state == "rejected" and want.setting ~= required then
				rejectedDiffers += 1
			end
			local record = byId[id]
			if record == nil then
				table.insert(problems, `AC-2: "{s.label}": no record for machine {id}`)
				continue
			end
			local dial = record.dial
			if typeof(dial) ~= "table" then
				table.insert(
					problems,
					`AC-2: "{s.label}": machine {id}'s dial is {Deep.show(dial)}, not a table`
				)
				continue
			end
			if Deep.equal(dial, want) then
				continue
			end
			if
				dial.setting == required
				and want.setting ~= required
				and dial.state == want.state
			then
				table.insert(
					problems,
					`AC-2: "{s.label}": machine {id}'s dial.setting is {required}, which is its requiredSetting; the setting last turned onto it was {Deep.show(
						want.setting
					)} (state {want.state})`
				)
			else
				table.insert(
					problems,
					`AC-2: "{s.label}": machine {id}'s dial is {Deep.show(dial)}, expected {Deep.show(
						want
					)}`
				)
			end
		end
	end
	if rejectedDiffers < 1 then
		Contract.fail(
			"AC-2 precondition: no snapshot has a rejected machine whose last turned setting differs from its requiredSetting"
		)
	end
	fewProblems(
		"AC-2",
		"dial.state is committed > armed > rejected (inside the reset window) > unset, and dial.setting is nil when unset and otherwise the setting of the machine's last actuation-log entry - never read from requiredSetting",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-5: one record per machine, ascending, exact keys, live, partner lamp.
     --------------------------------------------------------------------- ]]

function RoundViewContract.machineRecordsAreAscendingWithExactKeysLiveAndPartnerLampOnlyOnTheFinale(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	for _, tag in { "lampsBoth", "lampsOne", "lampsNone", "noAssignment", "generated" } do
		needTag(all, tag, "C-5")
	end
	local lit = 0
	for _, s in all do
		if not inRoundWithProcedure(s.input) then
			continue
		end
		local view = build(V, s, "C-5", problems)
		if view == nil then
			continue
		end
		local want = RoundViewContract.expectedMachines(s.input, s.now)
		-- Counted from the oracle, not from the records: the precondition is
		-- about the snapshots, and a builder that lists no machine must not
		-- turn it into "the sample proves nothing".
		for _, w in want do
			if w.partnerLamp == true then
				lit += 1
			end
		end
		local got = view.machines
		if typeof(got) ~= "table" then
			table.insert(problems, `C-5: "{s.label}": machines is {Deep.show(got)}, not a list`)
			continue
		end
		if #got ~= #want then
			table.insert(
				problems,
				`C-5: "{s.label}": {#got} machine records, expected {#want} (one per placement machine)`
			)
		end
		local finale = s.input.procedure.facility.steps.finale
		for i, record in ipairs(got) do
			local w = want[i]
			if w == nil then
				break
			end
			if typeof(record) ~= "table" then
				table.insert(problems, `C-5: "{s.label}": machines[{i}] is {Deep.show(record)}`)
				continue
			end
			if record.id ~= w.id then
				table.insert(
					problems,
					`C-5: "{s.label}": machines[{i}].id is {Deep.show(record.id)}, expected {w.id} (ascending id)`
				)
				continue
			end
			local keys = RoundViewContract.keysOf(record)
			local wantKeys = RoundViewContract.keysOf(w)
			if not Deep.equal(keys, wantKeys) then
				local isFinale = table.find(finale, w.id) ~= nil
				table.insert(
					problems,
					`C-5: "{s.label}": machine {w.id} has keys {joined(keys)}, expected exactly {joined(
						wantKeys
					)} ({if isFinale
						then "a finale machine carries partnerLamp"
						else "not a finale machine, so no partnerLamp"})`
				)
			end
			-- The dial itself (keys included) is AC-2's, compared whole there.
			if record.live ~= w.live then
				table.insert(
					problems,
					`C-5: "{s.label}": machine {w.id}.live is {Deep.show(record.live)}, Procedure.isLive says {Deep.show(
						w.live
					)}`
				)
			end
			if w.partnerLamp ~= nil then
				if record.partnerLamp ~= w.partnerLamp then
					table.insert(
						problems,
						`C-5: "{s.label}": machine {w.id}.partnerLamp is {Deep.show(
							record.partnerLamp
						)}, expected {Deep.show(w.partnerLamp)} ({if s.input.assignment
								== nil
							then "no assignment, so false"
							else "Procedure.partnerLamps with the given positions"})`
					)
				end
			end
		end
	end
	if lit < 2 then
		Contract.fail(
			`C-5 precondition: only {lit} lit partner lamp(s) expected across the snapshots; too few`
		)
	end
	fewProblems(
		"C-5",
		"machines is one { id, dial, live[, partnerLamp] } per placement machine in ascending id, dial has exactly setting (when non-nil) and state, live is Procedure.isLive, and partnerLamp is present only on the two finale machines as Procedure.partnerLamps(procedure, assignment, positions)[id] (false with no assignment)",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-3 (mechanical): the facility view.
     --------------------------------------------------------------------- ]]

function RoundViewContract.facilityViewIsExactlyTheLayoutAndEachMachinesStaticPublicFacts(V: View)
	local problems: { string } = {}
	local checked = 0
	for _, case in RoundViewContract.facilities() do
		local ok, view = pcall(V.facility, case.facility)
		if not ok then
			table.insert(
				problems,
				`AC-3: {case.label}: facility(facility) raised: {tostring(view)}`
			)
			continue
		end
		if typeof(view) ~= "table" then
			table.insert(
				problems,
				`AC-3: {case.label}: facility(facility) returned {Deep.show(view)}`
			)
			continue
		end
		checked += 1
		local want = RoundViewContract.expectedFacility(case.facility)
		local keys = RoundViewContract.keysOf(view)
		local extra, missing = keyDiff(RoundViewContract.FACILITY_KEYS, keys)
		for _, key in extra do
			table.insert(
				problems,
				`AC-3: {case.label}: the facility view carries an extra key "{key}"; it is exactly rooms, doors, spawnRoom, machines`
			)
		end
		for _, key in missing do
			table.insert(problems, `AC-3: {case.label}: the facility view is missing "{key}"`)
		end
		if typeof(view.machines) == "table" then
			for i, m in ipairs(view.machines) do
				if typeof(m) ~= "table" then
					continue
				end
				local mk = RoundViewContract.keysOf(m)
				local mExtra, mMissing = keyDiff(RoundViewContract.FACILITY_MACHINE_KEYS, mk)
				for _, key in mExtra do
					local why = if key == "requiredSetting"
						then " - the required setting is the game's central secret (roles.md section 6)"
						else ""
					table.insert(
						problems,
						`AC-3: {case.label}: machines[{i}] carries an extra key "{key}"{why}; a machine record is exactly id, room, slot, tag, keyClass`
					)
				end
				for _, key in mMissing do
					table.insert(problems, `AC-3: {case.label}: machines[{i}] is missing "{key}"`)
				end
			end
		end
		local diff = Deep.diff(want, view)
		if diff ~= "" then
			table.insert(
				problems,
				`AC-3: {case.label}: the facility view differs from the layout and the placement's public facts (rooms ascending by id, doors \{ a < b } sorted by a then b):\n  {diff}`
			)
		end
		local shared = sharedTables(view, case.facility)
		if shared > 0 then
			table.insert(
				problems,
				`AC-3: {case.label}: {shared} table(s) in the facility view are the facility's own (C-8: a fresh structure)`
			)
		end
	end
	if checked < 10 then
		Contract.fail(`AC-3 precondition: only {checked} facility views checked`)
	end
	fewProblems(
		"AC-3",
		"FacilityView is exactly { rooms = { id, column, row } ascending, doors = { a, b } with a < b sorted, spawnRoom, machines = { id, room, slot, tag, keyClass } ascending }, fresh, with no requiredSetting, steps, tracks, finale, par or attempt",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-4 (mechanical) and C-7: secondsLeft.
     --------------------------------------------------------------------- ]]

function RoundViewContract.secondsLeftIsTheCeilingOfTheDeadlineMinusNowClampedAtZero(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	for _, tag in
		{
			"penalised",
			"unpenalised",
			"pastDeadline",
			"clamped",
			"lobbyTimed",
			"noClock",
			"roundNoProcedure",
			"postTimed",
		}
	do
		needTag(all, tag, "AC-4")
	end
	local penalised = 0
	for _, s in all do
		local view = build(V, s, "AC-4", problems)
		if view == nil then
			continue
		end
		local want = RoundViewContract.expectedSecondsLeft(s.input, s.now)
		local got = view.secondsLeft
		if inRoundWithProcedure(s.input) then
			local p = s.input.procedure
			local unpenalised = math.max(0, math.ceil(p.startedAt + p.roundSeconds - s.now))
			local penalty = p.penaltySeconds
			if penalty > 0 and want ~= nil and want > 0 then
				penalised += 1
				if got ~= want then
					table.insert(
						problems,
						`AC-4: "{s.label}": secondsLeft is {Deep.show(got)}, expected ceil(Procedure.deadline - {s.now}) = {want}, which is {penalty} s of clock penalty below the unpenalised {unpenalised}{if got
								== unpenalised
							then " - the view ignores the penalty"
							else ""}`
					)
				end
				continue
			end
		end
		if got ~= want then
			local note = ""
			if s.tags.clamped and typeof(got) == "number" and got < 0 then
				note = " - a negative secondsLeft is unclamped (C-7: math.max(0, ...))"
			end
			table.insert(
				problems,
				`AC-4: "{s.label}": secondsLeft is {Deep.show(got)}, expected {Deep.show(want)}{note}`
			)
		end
	end
	if penalised < 3 then
		Contract.fail(`AC-4 precondition: only {penalised} penalised Round snapshot(s); too few`)
	end
	fewProblems(
		"AC-4",
		"in Round with a Procedure secondsLeft = max(0, ceil(Procedure.deadline - now)), so a clock penalty shows; elsewhere SLICE-003's config-duration rule, clamped at 0, nil where no clock runs",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-3: the procedure-derived fields exist only in Round with a Procedure.
     --------------------------------------------------------------------- ]]

function RoundViewContract.procedureFieldsExistOnlyInRoundWithAProcedure(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "procedureHeld", "C-3")
	needTag(all, "roundNoProcedure", "C-3")
	needTag(all, "dark", "C-3")
	for _, s in all do
		local view = build(V, s, "C-3", problems)
		if view == nil then
			continue
		end
		local want = RoundViewContract.expected(s.input, s.now)
		if inRoundWithProcedure(s.input) then
			-- The other checks pin dark, machines and progress in Round;
			-- instability is pinned here and nowhere else.
			if view.instability ~= want.instability then
				table.insert(
					problems,
					`C-3: "{s.label}": instability is {Deep.show(view.instability)}, expected procedure.instability = {want.instability}`
				)
			end
			if typeof(view.machines) ~= "table" or #view.machines == 0 then
				table.insert(
					problems,
					`C-3: "{s.label}": machines is {Deep.show(view.machines)} in Round with a Procedure`
				)
			end
			continue
		end
		for _, field in { "instability", "dark", "machines", "progress" } do
			local diff = Deep.diff(want[field], view[field])
			if diff ~= "" then
				table.insert(
					problems,
					`C-3: "{s.label}": {field} should be defaulted outside Round-with-a-Procedure ({s.input.round.phase}{if s.input.procedure
							~= nil
						then ", a Procedure still held"
						else ", no Procedure"}):\n  {diff}`
				)
			end
		end
	end
	fewProblems(
		"C-3",
		"instability, dark, machines and progress.committed come from the Procedure only when phase == Round and a Procedure is present; otherwise 0, {}, {} and 0, with total still procedure_length",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-6: dark, ascending.
     --------------------------------------------------------------------- ]]

function RoundViewContract.darkIsTheAscendingListOfDarkRoomIds(V: View, snapshots: { Snapshot }?)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "twoDark", "C-6")
	needTag(all, "darkUnordered", "C-6")
	local multi = 0
	for _, s in all do
		if not inRoundWithProcedure(s.input) then
			continue
		end
		local view = build(V, s, "C-6", problems)
		if view == nil then
			continue
		end
		local want = RoundViewContract.expectedDark(s.input.procedure)
		if #want > 1 then
			multi += 1
		end
		if not Deep.equal(view.dark, want) then
			table.insert(
				problems,
				`C-6: "{s.label}": dark is {Deep.show(view.dark)}, expected the ascending room ids {Deep.show(
					want
				)}`
			)
		end
	end
	if multi < 2 then
		Contract.fail(`C-6 precondition: only {multi} snapshot(s) with more than one dark room`)
	end
	fewProblems(
		"C-6",
		"dark is the ascending list of layout room ids r with procedure.dark[r] == true",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-1 / C-3: pings, as given, copied, in every phase.
     --------------------------------------------------------------------- ]]

function RoundViewContract.pingsAreTheGivenListCopiedInEveryPhase(V: View, snapshots: { Snapshot }?)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "phase", "pings")
	for _, s in all do
		local view = build(V, s, "pings", problems)
		if view == nil then
			continue
		end
		if not Deep.equal(view.pings, s.input.pings) then
			table.insert(
				problems,
				`pings: "{s.label}": pings is {Deep.show(view.pings)}, expected the input's {Deep.show(
					s.input.pings
				)} in every phase`
			)
		elseif sharedTables(view.pings, s.input.pings) > 0 then
			table.insert(
				problems,
				`pings: "{s.label}": pings shares a table with input.pings; the Contract wants a copy`
			)
		end
	end
	-- The empty list, which Session passes until SLICE-006.
	local first = all[1]
	local empty = table.clone(first.input)
	empty.pings = {}
	local view = build(
		V,
		{ label = "pings = {}", input = empty, now = first.now, tags = {} },
		"pings",
		problems
	)
	if view ~= nil and not Deep.equal(view.pings, {}) then
		table.insert(
			problems,
			`pings: with input.pings = \{} the view's pings is {Deep.show(view.pings)}`
		)
	end
	fewProblems(
		"pings",
		"pings is input.pings copied (list and entries), in every phase, {} for {}",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-9: every table fresh; mutation crosses nothing.
     --------------------------------------------------------------------- ]]

function RoundViewContract.everyTableInTheViewIsFreshAndNeitherSideMutatesTheOther(
	V: View,
	snapshots: { Snapshot }?
)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	needTag(all, "disarmed", "C-9")
	for _, s in all do
		local view = build(V, s, "C-9", problems)
		if view == nil then
			continue
		end
		local shared = sharedTables(view, s.input)
		if shared > 0 then
			local which: { string } = {}
			for _, field in { "players", "pings", "dark", "machines", "progress" } do
				if
					rawequal(view[field], s.input.round.players)
					or rawequal(view[field], s.input.pings)
				then
					table.insert(which, field)
				end
			end
			table.insert(
				problems,
				`C-9: "{s.label}": {shared} table(s) in the view are the input's own{if #which
						> 0
					then ` ({table.concat(which, ", ")})`
					else ""}`
			)
			continue
		end
		-- Mutate the view; the input must not move.
		local before = Deep.copy(s.input)
		if typeof(view.players) == "table" then
			table.insert(view.players, "intruder")
		end
		if typeof(view.pings) == "table" then
			table.insert(view.pings, { senderId = "x", kind = "machine", target = 1 })
			if typeof(view.pings[1]) == "table" then
				view.pings[1].senderId = "mutated"
			end
		end
		if typeof(view.dark) == "table" then
			table.insert(view.dark, 99)
		end
		if typeof(view.machines) == "table" and typeof(view.machines[1]) == "table" then
			view.machines[1].id = -1
			if typeof(view.machines[1].dial) == "table" then
				view.machines[1].dial.setting = 42
			end
		end
		if typeof(view.progress) == "table" then
			view.progress.committed = 99
		end
		local diff = Deep.diff(before, s.input)
		if diff ~= "" then
			table.insert(
				problems,
				`C-9: "{s.label}": mutating the view changed the input:\n  {diff}`
			)
		end
		-- Mutate the input; a view built before must not move. On a deep copy
		-- of the input, so the snapshots stay what the other checks expect.
		local own: Snapshot =
			{ label = s.label, input = Deep.copy(s.input), now = s.now, tags = s.tags }
		local again = build(V, own, "C-9", problems)
		if again == nil then
			continue
		end
		local snapshot = Deep.copy(again)
		table.insert(own.input.round.players, "intruder")
		table.insert(own.input.pings, { senderId = "y", kind = "machine", target = 2 })
		if own.input.procedure ~= nil then
			own.input.procedure.dark[1] = true
			own.input.procedure.committed[1] = true
		end
		local viewDiff = Deep.diff(snapshot, again)
		if viewDiff ~= "" then
			table.insert(
				problems,
				`C-9: "{s.label}": mutating the input changed a view built before it:\n  {viewDiff}`
			)
		end
	end
	-- The facility view, the same way.
	local facility = Turn.facility()
	local ok, fview = pcall(V.facility, facility)
	if ok and typeof(fview) == "table" then
		local before = Deep.copy(facility)
		if typeof(fview.machines) == "table" and typeof(fview.machines[1]) == "table" then
			fview.machines[1].tag = 99
		end
		if typeof(fview.rooms) == "table" and typeof(fview.rooms[1]) == "table" then
			fview.rooms[1].column = 99
		end
		if typeof(fview.doors) == "table" then
			table.insert(fview.doors, { a = 1, b = 4 })
		end
		local diff = Deep.diff(before, facility)
		if diff ~= "" then
			table.insert(
				problems,
				`C-9: mutating the facility view changed the facility:\n  {diff}`
			)
		end
	end
	fewProblems(
		"C-9",
		"every list and record in a view is fresh - no table in the view is a table of the input, and mutating either side leaves the other unchanged",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     The whole view, deep-equal to the oracle (the one-line summary).
     --------------------------------------------------------------------- ]]

function RoundViewContract.viewDeepEqualsTheOracleOnEverySnapshot(V: View, snapshots: { Snapshot }?)
	local all = snapshots or RoundViewContract.snapshots()
	local problems: { string } = {}
	for _, s in all do
		local view = build(V, s, "oracle", problems)
		if view == nil then
			continue
		end
		local diff = Deep.diff(RoundViewContract.expected(s.input, s.now), view)
		if diff ~= "" then
			table.insert(problems, `oracle: "{s.label}":\n  {diff}`)
		end
	end
	fewProblems(
		"oracle",
		"public(input, now) deep-equals the Contract's own composition of C-3..C-7 on every snapshot",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     The battery, for the controls.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (View, { Snapshot }?) -> () }

RoundViewContract.CHECKS = {
	{
		name = "topLevelKeysAreExactlyTheTen",
		ac = "AC-5",
		run = RoundViewContract.topLevelKeysAreExactlyTheTen,
	},
	{
		name = "progressIsExactlyCommittedStepsOverProcedureLength",
		ac = "AC-1",
		run = RoundViewContract.progressIsExactlyCommittedStepsOverProcedureLength,
	},
	{
		name = "dialIsTheLastTurnedSettingNeverTheRequiredOne",
		ac = "AC-2",
		run = RoundViewContract.dialIsTheLastTurnedSettingNeverTheRequiredOne,
	},
	{
		name = "machineRecordsAreAscendingWithExactKeysLiveAndPartnerLampOnlyOnTheFinale",
		ac = "C-5",
		run = RoundViewContract.machineRecordsAreAscendingWithExactKeysLiveAndPartnerLampOnlyOnTheFinale,
	},
	{
		name = "facilityViewIsExactlyTheLayoutAndEachMachinesStaticPublicFacts",
		ac = "AC-3",
		run = function(V: View, _snapshots: { Snapshot }?)
			RoundViewContract.facilityViewIsExactlyTheLayoutAndEachMachinesStaticPublicFacts(V)
		end,
	},
	{
		name = "secondsLeftIsTheCeilingOfTheDeadlineMinusNowClampedAtZero",
		ac = "AC-4",
		run = RoundViewContract.secondsLeftIsTheCeilingOfTheDeadlineMinusNowClampedAtZero,
	},
	{
		name = "procedureFieldsExistOnlyInRoundWithAProcedure",
		ac = "C-3",
		run = RoundViewContract.procedureFieldsExistOnlyInRoundWithAProcedure,
	},
	{
		name = "darkIsTheAscendingListOfDarkRoomIds",
		ac = "C-6",
		run = RoundViewContract.darkIsTheAscendingListOfDarkRoomIds,
	},
	{
		name = "pingsAreTheGivenListCopiedInEveryPhase",
		ac = "pings",
		run = RoundViewContract.pingsAreTheGivenListCopiedInEveryPhase,
	},
	{
		name = "everyTableInTheViewIsFreshAndNeitherSideMutatesTheOther",
		ac = "C-9",
		run = RoundViewContract.everyTableInTheViewIsFreshAndNeitherSideMutatesTheOther,
	},
	{
		name = "viewDeepEqualsTheOracleOnEverySnapshot",
		ac = "oracle",
		run = RoundViewContract.viewDeepEqualsTheOracleOnEverySnapshot,
	},
} :: { Check }

function RoundViewContract.failures(V: View): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	local snapshots = RoundViewContract.snapshots()
	for _, check in RoundViewContract.CHECKS do
		local ok, err = pcall(check.run, V, snapshots)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return RoundViewContract
