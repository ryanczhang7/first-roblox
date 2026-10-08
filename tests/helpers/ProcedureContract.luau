--!strict
--[[
	GEN-003's checks, statistics and fixtures, written once over a DRAW and a
	CHECK function rather than over `src/server/facility/Steps.luau` by name -
	the `PlacementContract` arrangement, for the same reason.

	`tests/server/steps_test.luau` applies these to the real module.
	`tests/server/steps_controls_test.luau` applies them to the deliberately
	wrong draws in `ProcedureStubs.luau`, so that in RED - where the module does
	not exist, the real file fails at `require`, and not one assertion in it has
	executed - every statistic here has been EXECUTED and observed to reject the
	draw it exists to catch, and to accept a reference that is correct.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE.

	  * SETTLED, EXACT PINNING. `INV_balanced_steps`, `INV_every_class_has_a_step`,
	    `INV_track_alternates`, `INV_finale` and `INV_k_essential` (`tuning.md`
	    §2) are re-derived INDEPENDENTLY in `violations` below, so the sweeps do
	    not take `Steps.check`'s word for it. The fixtures are hand-built: GEN-001's
	    square layout, GEN-002's hand-built placements, and a ring from
	    `Ring.assign` at a FIXED seed whose σ was READ BACK (see `FIXTURE_SIGMA`,
	    asserted by the controls file) and the tracks derived by hand from it.
	    Expected token sets are written by hand; the controls file shows each
	    fixture trips exactly its own clause in THIS checker.
	  * ORACLE-FREE WITH NEGATIVE CONTROL. `acceptance` (AC-6) and `settingPools`
	    (AC-7) are pure functions of a (draw, check) pair. Their floors, sample
	    sizes and bands are the Lead PO's, copied from the criteria verbatim; RED
	    may tighten one from a measured variance, GREEN may not move any.

	Every constant is READ from `MechanicsTuning.instance`; nothing below writes
	8, 4 or 2 where a constant is meant. The only literals are the statistics'
	own sample sizes and bands, and the hand-built fixtures, which say which
	shipped values they were drawn for and are checked against them.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local Layout = require("../../src/server/facility/Layout")
local LayoutContract = require("./LayoutContract")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PlacementContract = require("./PlacementContract")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")

local ProcedureContract = {}

export type Machine = PlacementContract.Machine
export type Placement = PlacementContract.Placement
export type Layout = LayoutContract.Layout
export type Tuning = typeof(MechanicsTuning)
export type Assignment = Ring.Assignment
export type Steps = { tracks: { { number } }, finale: { number } }
export type Draw = (
	rng: Rng.Rng,
	layout: Layout,
	placement: Placement,
	assignment: Assignment,
	tuning: Tuning
) -> Steps
export type Check = (
	steps: Steps,
	layout: Layout,
	placement: Placement,
	assignment: Assignment,
	tuning: Tuning
) -> { string }
export type World = {
	seed: number,
	n: number,
	layout: Layout,
	placement: Placement,
	assignment: Assignment,
}

-- The shipped tuning. Every check below reads `instance.procedure_tracks`,
-- `steps_per_track`, `paired_room_distance_min` and `dial_settings` from here.
ProcedureContract.TUNING = MechanicsTuning

-- AC-1 to AC-6 sweep seeds 1..SWEEP_SEEDS at each n in CLASS_COUNTS.
ProcedureContract.SWEEP_SEEDS = 1000
ProcedureContract.CLASS_COUNTS = { 4, 5, 6 }
-- AC-6's floor on first-draw acceptance (PO-2: generator_attempts_max's design acceptance).
ProcedureContract.ACCEPTANCE_FLOOR = 0.25
-- AC-7: each pool holds at least POOL_MIN settings, within POOL_SEED_CAP seeds (PO-3).
ProcedureContract.POOL_MIN = 16000
ProcedureContract.POOL_SEED_CAP = 20000
-- AC-7's band around 1/dial_settings. The Lead PO's; ~6 SE at 16,000 settings.
ProcedureContract.SETTING_TOLERANCE = 0.02

-- The eight `prefix:token` strings `check` may report, from the Contract's table.
ProcedureContract.TOKENS = {
	"INV_balanced_steps:shape",
	"INV_balanced_steps:count",
	"INV_every_class_has_a_step:missing",
	"INV_track_alternates:adjacent",
	"INV_finale:rooms",
	"INV_finale:ring",
	"INV_k_essential:turn",
	"INV_k_essential:read",
}

-- The three labels `draw` derives from the rng it is handed, sorted.
ProcedureContract.DERIVE_LABELS = { "choose", "finale", "order" }

--[[ ------------------------------------------------------------------------
     Sweep inputs, the Contract's derivation: for seed s and n, the layout is
     `Layout.generate(Rng.fromSeed(s):derive("layout"))`, the placement
     `Machines.generate(Rng.fromSeed(s):derive("machines"), layout, {1..n})`,
     the ring `Ring.assign({"p1".."pn"}, Rng.fromSeed(s))`, and draw's rng
     `Rng.fromSeed(s):derive("steps")`. Worlds for seeds 1..SWEEP_SEEDS are
     cached (AC-7's longer sweep rebuilds the rest on the fly, so a 20,000-seed
     cap does not pin 60,000 placements in memory). Cached values are SHARED:
     no caller may mutate one; the purity tests snapshot first.
     --------------------------------------------------------------------- ]]

function ProcedureContract.playersFor(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = `p{i}`
	end
	return out
end

function ProcedureContract.classesFor(n: number): { number }
	return PlacementContract.classesFor(n)
end

local layoutCache: { [number]: Layout } = {}
local worldCache: { [number]: { [number]: World } } = {}

function ProcedureContract.layoutFor(seed: number): Layout
	local cached = layoutCache[seed]
	if cached ~= nil then
		return cached
	end
	local layout = Layout.generate(Rng.fromSeed(seed):derive("layout"), MechanicsTuning)
	if seed <= ProcedureContract.SWEEP_SEEDS then
		layoutCache[seed] = layout
	end
	return layout
end

function ProcedureContract.assignmentFor(seed: number, n: number): Assignment
	return Ring.assign(ProcedureContract.playersFor(n), Rng.fromSeed(seed))
end

function ProcedureContract.rngFor(seed: number): Rng.Rng
	return Rng.fromSeed(seed):derive("steps")
end

function ProcedureContract.worldFor(seed: number, n: number): World
	local forN = worldCache[n]
	if forN ~= nil and forN[seed] ~= nil then
		return forN[seed]
	end
	local layout = ProcedureContract.layoutFor(seed)
	local world: World = {
		seed = seed,
		n = n,
		layout = layout,
		placement = Machines.generate(
			Rng.fromSeed(seed):derive("machines"),
			layout,
			ProcedureContract.classesFor(n),
			MechanicsTuning
		),
		assignment = ProcedureContract.assignmentFor(seed, n),
	}
	if seed <= ProcedureContract.SWEEP_SEEDS then
		worldCache[n] = worldCache[n] or {}
		worldCache[n][seed] = world
	end
	return world
end

-- An Rng that records every label derived from it and counts every draw
-- taken from it DIRECTLY. The Contract says `draw` derives exactly "choose",
-- "order" and "finale", once each, and draws from nothing else.
function ProcedureContract.recordingRng(
	seed: number
): (Rng.Rng, { labels: { string }, directDraws: number })
	local real = ProcedureContract.rngFor(seed)
	local record = { labels = {} :: { string }, directDraws = 0 }
	local spy = {}
	spy.nextInteger = function(_self, min: number, max: number): number
		record.directDraws += 1
		return real:nextInteger(min, max)
	end
	spy.nextNumber = function(_self): number
		record.directDraws += 1
		return real:nextNumber()
	end
	spy.shuffle = function<T>(_self, list: { T }): { T }
		record.directDraws += 1
		return real:shuffle(list)
	end
	spy.derive = function(_self, label: string): Rng.Rng
		table.insert(record.labels, label)
		return real:derive(label)
	end
	return (spy :: any) :: Rng.Rng, record
end

--[[ ------------------------------------------------------------------------
     The Contract's Terms, read through `Ring` as it says: the HOLDER of class
     c is the seated player whose `keyClasses` list contains c; the TURNER of
     a machine is its class's holder; the HELPER is `Ring.supplierOf(holder)`,
     the player whose lens is c; two classes are RING NEIGHBOURS when
     `Ring.dependentOf` of one holder is the other. σ⁻¹ is never recomputed
     here (`Projection.luau`'s header says why).
     --------------------------------------------------------------------- ]]

-- The classes in play: every class some seated player holds, ascending.
function ProcedureContract.classesInPlay(assignment: Assignment): { number }
	local seen: { [number]: boolean } = {}
	local out: { number } = {}
	for _, p in assignment.players do
		for _, c in assignment.keyClasses[p] or {} do
			if not seen[c] then
				seen[c] = true
				table.insert(out, c)
			end
		end
	end
	table.sort(out)
	return out
end

function ProcedureContract.holderOf(assignment: Assignment, class: number): string?
	for _, p in assignment.players do
		for _, c in assignment.keyClasses[p] or {} do
			if c == class then
				return p
			end
		end
	end
	return nil
end

function ProcedureContract.helperOf(assignment: Assignment, class: number): string?
	local holder = ProcedureContract.holderOf(assignment, class)
	if holder == nil then
		return nil
	end
	return Ring.supplierOf(assignment, holder)
end

-- Two players are ring neighbours when either is the other's dependent.
function ProcedureContract.ringNeighbours(assignment: Assignment, a: string, b: string): boolean
	return Ring.dependentOf(assignment, a) == b or Ring.dependentOf(assignment, b) == a
end

function ProcedureContract.machineById(placement: Placement): { [number]: Machine }
	local byId: { [number]: Machine } = {}
	for _, m in placement.machines do
		byId[m.id] = m
	end
	return byId
end

local function isInteger(x: any): boolean
	return typeof(x) == "number" and x == math.floor(x)
end

--[[ ------------------------------------------------------------------------
     The invariants, re-derived here. ONE string per violated invariant,
     headed `<INV>:<token> ` with the FIRST violated clause in the Contract
     table's order (shape before count; rooms before ring; turn before read),
     exactly as the Contract says `check` must, so the controls file can show
     which head each hand-built violation trips in OUR checker.

     On a malformed shape this checker goes on to evaluate the other
     invariants over what is present - ids that are in the placement, tracks
     that are lists, the `finale` field when it is two placement ids. The
     Contract lets `check` either do the same or stop at `shape`; the shape
     fixtures are built so both readings give exactly { shape }.
     --------------------------------------------------------------------- ]]

type Clause = { token: string, details: { string } }

local function clause(token: string): Clause
	return { token = token, details = {} }
end

local function report(out: { string }, invariant: string, clauses: { Clause })
	local first: Clause? = nil
	local also: { string } = {}
	for _, c in clauses do
		if #c.details == 0 then
			continue
		end
		if first == nil then
			first = c
		else
			table.insert(also, `{c.token}: {table.concat(c.details, "; ")}`)
		end
	end
	if first == nil then
		return
	end
	local text = `{invariant}:{first.token} {table.concat(first.details, "; ")}`
	if #also > 0 then
		text ..= ` (also {table.concat(also, " | ")})`
	end
	table.insert(out, text)
end

function ProcedureContract.violations(
	steps: Steps,
	layout: Layout,
	placement: Placement,
	assignment: Assignment,
	tuning: Tuning
): { string }
	local out: { string } = {}
	local t = tuning.instance
	local byId = ProcedureContract.machineById(placement)
	local classes = ProcedureContract.classesInPlay(assignment)

	-- INV_balanced_steps:shape
	local shape = clause("shape")
	local tracks: any = (steps :: any).tracks
	local stepMachines: { Machine } = {}
	local seen: { [number]: boolean } = {}
	local lasts: { any } = {}
	if typeof(tracks) ~= "table" then
		table.insert(shape.details, `tracks is {typeof(tracks)}, expected a list of tracks`)
	else
		if #tracks ~= t.procedure_tracks then
			table.insert(
				shape.details,
				`{#tracks} track(s), expected procedure_tracks = {t.procedure_tracks}`
			)
		end
		for ti, track in ipairs(tracks :: { any }) do
			if typeof(track) ~= "table" then
				table.insert(shape.details, `track {ti} is {typeof(track)}, expected a list`)
				continue
			end
			if #track ~= t.steps_per_track then
				table.insert(
					shape.details,
					`track {ti} has {#track} step(s), expected steps_per_track = {t.steps_per_track}`
				)
			end
			table.insert(lasts, track[#track])
			for i, id in ipairs(track :: { any }) do
				local m = if typeof(id) == "number" then byId[id] else nil
				if m == nil then
					table.insert(
						shape.details,
						`track {ti} step {i} is {tostring(id)}, not a machine id in the placement`
					)
				elseif seen[id] then
					table.insert(shape.details, `machine {id} is a step twice`)
				else
					seen[id] = true
					table.insert(stepMachines, m)
				end
			end
		end
	end
	local finale: any = (steps :: any).finale
	if not Deep.equal(finale, lasts) then
		table.insert(
			shape.details,
			`finale is {Deep.show(finale)}, expected the tracks' last steps {Deep.show(lasts)}`
		)
	end

	-- INV_balanced_steps:count
	local count = clause("count")
	local perClass: { [number]: number } = {}
	for _, c in classes do
		perClass[c] = 0
	end
	for _, m in stepMachines do
		if perClass[m.keyClass] == nil then
			table.insert(
				count.details,
				`machine {m.id} is of class {tostring(m.keyClass)}, which no seated player holds`
			)
		else
			perClass[m.keyClass] += 1
		end
	end
	local low, high = math.huge, -math.huge
	for _, c in classes do
		local want = placement.stepsPerClass[c]
		if perClass[c] ~= want then
			table.insert(
				count.details,
				`class {c} has {perClass[c]} step(s), stepsPerClass says {tostring(want)}`
			)
		end
		low, high = math.min(low, perClass[c]), math.max(high, perClass[c])
	end
	if #classes > 0 and high - low > 1 then
		table.insert(count.details, `step counts range from {low} to {high}, more than 1 apart`)
	end
	report(out, "INV_balanced_steps", { shape, count })

	-- INV_every_class_has_a_step:missing
	local missing = clause("missing")
	for _, c in classes do
		if perClass[c] == 0 then
			table.insert(missing.details, `class {c} has no step`)
		end
	end
	report(out, "INV_every_class_has_a_step", { missing })

	-- INV_track_alternates:adjacent
	local adjacent = clause("adjacent")
	if typeof(tracks) == "table" then
		for ti, track in ipairs(tracks :: { any }) do
			if typeof(track) ~= "table" then
				continue
			end
			for i = 2, #track do
				local a = if typeof(track[i - 1]) == "number" then byId[track[i - 1]] else nil
				local b = if typeof(track[i]) == "number" then byId[track[i]] else nil
				if a ~= nil and b ~= nil and a.keyClass == b.keyClass then
					table.insert(
						adjacent.details,
						`track {ti} steps {i - 1} and {i} (machines {a.id}, {b.id}) are both class {a.keyClass}`
					)
				end
			end
		end
	end
	report(out, "INV_track_alternates", { adjacent })

	-- INV_finale:rooms, then :ring - over the finale field when it is two ids.
	local rooms = clause("rooms")
	local ring = clause("ring")
	if typeof(finale) == "table" and #finale == 2 then
		local f1 = if typeof(finale[1]) == "number" then byId[finale[1]] else nil
		local f2 = if typeof(finale[2]) == "number" then byId[finale[2]] else nil
		if f1 ~= nil and f2 ~= nil then
			if f1.room == f2.room then
				table.insert(
					rooms.details,
					`finale machines {f1.id} and {f2.id} share room {f1.room}`
				)
			else
				local d = Layout.distance(layout, f1.room, f2.room)
				if d < t.paired_room_distance_min then
					table.insert(
						rooms.details,
						`finale rooms {f1.room} and {f2.room} are {d} apart, below paired_room_distance_min = {t.paired_room_distance_min}`
					)
				end
			end
			local h1 = ProcedureContract.holderOf(assignment, f1.keyClass)
			local h2 = ProcedureContract.holderOf(assignment, f2.keyClass)
			if h1 ~= nil and h2 ~= nil then
				if h1 == h2 then
					table.insert(
						ring.details,
						`finale classes {f1.keyClass} and {f2.keyClass} are both held by {h1}`
					)
				elseif ProcedureContract.ringNeighbours(assignment, h1, h2) then
					table.insert(
						ring.details,
						`finale classes {f1.keyClass} ({h1}) and {f2.keyClass} ({h2}) are held by ring neighbours`
					)
				end
			end
		end
	end
	report(out, "INV_finale", { rooms, ring })

	-- INV_k_essential:turn, then :read - per seated player.
	local turn = clause("turn")
	local read = clause("read")
	for _, p in assignment.players do
		local canTurn, canRead = false, false
		for _, m in stepMachines do
			if ProcedureContract.holderOf(assignment, m.keyClass) == p then
				canTurn = true
			end
			if ProcedureContract.helperOf(assignment, m.keyClass) == p then
				canRead = true
			end
		end
		if not canTurn then
			table.insert(turn.details, `no step has a machine only {p} can turn`)
		end
		if not canRead then
			table.insert(read.details, `no step has a machine whose setting only {p} can read`)
		end
	end
	report(out, "INV_k_essential", { turn, read })

	return out
end

-- AC-3's four bodies, read through the Terms: { turner 1, turner 2, helper 1,
-- helper 2 } of the finale field. Entries may be nil for an unheld class.
function ProcedureContract.finaleParticipants(
	steps: Steps,
	placement: Placement,
	assignment: Assignment
): { string? }
	local byId = ProcedureContract.machineById(placement)
	local out: { string? } = {}
	for i = 1, 2 do
		local m = byId[steps.finale[i]]
		local c = if m ~= nil then m.keyClass else nil
		out[i] = if c ~= nil then ProcedureContract.holderOf(assignment, c) else nil
		out[i + 2] = if c ~= nil then ProcedureContract.helperOf(assignment, c) else nil
	end
	return out
end

-- The violations whose string starts with `prefix` (an invariant name).
function ProcedureContract.withPrefix(strings: { string }, prefix: string): { string }
	return PlacementContract.withPrefix(strings, prefix)
end

-- The `prefix:token` heads in a list of `check` strings. A string that does
-- not have the Contract's shape - one of the eight heads, then a SPACE - goes
-- in `malformed`, so a needle can never be satisfied by text that merely
-- contains it (`rules.md`, "the needle is part of the assertion"). `tokens`
-- is the sorted list of DISTINCT heads found.
function ProcedureContract.parseTokens(
	strings: { string }
): { tokens: { string }, malformed: { string } }
	local found: { [string]: boolean } = {}
	local malformed: { string } = {}
	for _, s in strings do
		local matched = false
		if typeof(s) == "string" then
			for _, token in ProcedureContract.TOKENS do
				local head = `{token} `
				if string.sub(s, 1, #head) == head then
					found[token] = true
					matched = true
					break
				end
			end
		end
		if not matched then
			table.insert(malformed, tostring(s))
		end
	end
	local tokens: { string } = {}
	for token in pairs(found) do
		table.insert(tokens, token)
	end
	table.sort(tokens)
	return { tokens = tokens, malformed = malformed }
end

--[[ ------------------------------------------------------------------------
     The sweep. One candidate per seed - the FIRST draw, never resampled -
     with its `check` report. Memoised per (draw, check, n) for the full
     SWEEP_SEEDS, because every statistic re-walks the same seeds.
     --------------------------------------------------------------------- ]]

export type Candidate = { seed: number, world: World, steps: Steps, report: { string } }

local sweepCache: { [Draw]: { [Check]: { [number]: { Candidate } } } } = {}

local function candidateFor(draw: Draw, check: Check, seed: number, n: number): Candidate
	local world = ProcedureContract.worldFor(seed, n)
	local steps = draw(
		ProcedureContract.rngFor(seed),
		world.layout,
		world.placement,
		world.assignment,
		MechanicsTuning
	)
	local reported = check(steps, world.layout, world.placement, world.assignment, MechanicsTuning)
	return { seed = seed, world = world, steps = steps, report = reported }
end

function ProcedureContract.sweep(draw: Draw, check: Check, n: number): { Candidate }
	local forDraw = sweepCache[draw]
	if forDraw ~= nil and forDraw[check] ~= nil and forDraw[check][n] ~= nil then
		return forDraw[check][n]
	end
	local out: { Candidate } = {}
	for seed = 1, ProcedureContract.SWEEP_SEEDS do
		out[seed] = candidateFor(draw, check, seed, n)
	end
	sweepCache[draw] = sweepCache[draw] or {}
	sweepCache[draw][check] = sweepCache[draw][check] or {}
	sweepCache[draw][check][n] = out
	return out
end

-- The accepted candidates: those whose `check` report is `{}`.
function ProcedureContract.accepted(draw: Draw, check: Check, n: number): { Candidate }
	local out: { Candidate } = {}
	for _, c in ProcedureContract.sweep(draw, check, n) do
		if #c.report == 0 then
			table.insert(out, c)
		end
	end
	return out
end

--[[ ------------------------------------------------------------------------
     AC-6: first-draw acceptance.
     --------------------------------------------------------------------- ]]

export type AcceptanceStats = {
	n: number,
	seeds: number,
	accepted: number,
	rate: number,
	rejectedBy: { [string]: number }, -- head -> number of candidates reporting it
}

function ProcedureContract.acceptance(draw: Draw, check: Check, n: number): AcceptanceStats
	local candidates = ProcedureContract.sweep(draw, check, n)
	local acceptedCount = 0
	local rejectedBy: { [string]: number } = {}
	for _, c in candidates do
		if #c.report == 0 then
			acceptedCount += 1
		else
			for _, token in ProcedureContract.parseTokens(c.report).tokens do
				rejectedBy[token] = (rejectedBy[token] or 0) + 1
			end
		end
	end
	return {
		n = n,
		seeds = #candidates,
		accepted = acceptedCount,
		rate = if #candidates == 0 then 0 else acceptedCount / #candidates,
		rejectedBy = rejectedBy,
	}
end

function ProcedureContract.describeAcceptance(stats: AcceptanceStats): string
	local heads: { string } = {}
	for head in pairs(stats.rejectedBy) do
		table.insert(heads, head)
	end
	table.sort(heads)
	local parts: { string } = {}
	for _, head in heads do
		table.insert(parts, `{head} × {stats.rejectedBy[head]}`)
	end
	return `n = {stats.n}: {stats.accepted} of {stats.seeds} first draws accepted, rate {string.format(
		"%.4f",
		stats.rate
	)}; rejected by [{table.concat(parts, ", ")}]`
end

function ProcedureContract.assertAcceptance(draw: Draw, check: Check, n: number): AcceptanceStats
	local stats = ProcedureContract.acceptance(draw, check, n)
	assert(
		stats.rate >= ProcedureContract.ACCEPTANCE_FLOOR,
		`AC-6: first-draw acceptance at n = {n} is {string.format("%.4f", stats.rate)}, below the floor {ProcedureContract.ACCEPTANCE_FLOOR} - {ProcedureContract.describeAcceptance(
			stats
		)}`
	)
	return stats
end

--[[ ------------------------------------------------------------------------
     AC-7: required settings pooled over step machines and over decoys, per n,
     over the accepted candidates of seeds 1, 2, 3, ... until both pools hold
     POOL_MIN settings, capped at POOL_SEED_CAP seeds.
     --------------------------------------------------------------------- ]]

export type Pool = {
	name: string,
	count: number,
	missing: number, -- requiredSetting not an integer in 1..dial_settings
	counts: { [number]: number },
	frequencies: { [number]: number },
	min: number,
	max: number,
	minValue: number,
	maxValue: number,
}

export type PoolStats = {
	n: number,
	seedsUsed: number,
	accepted: number,
	capped: boolean,
	step: Pool,
	decoy: Pool,
}

local function newPool(name: string): Pool
	local counts: { [number]: number } = {}
	for v = 1, MechanicsTuning.instance.dial_settings do
		counts[v] = 0
	end
	return {
		name = name,
		count = 0,
		missing = 0,
		counts = counts,
		frequencies = {},
		min = math.huge,
		max = -math.huge,
		minValue = 0,
		maxValue = 0,
	}
end

local function addToPool(pool: Pool, setting: any)
	local d = MechanicsTuning.instance.dial_settings
	pool.count += 1
	if isInteger(setting) and setting >= 1 and setting <= d then
		pool.counts[setting] += 1
	else
		pool.missing += 1
	end
end

local function finishPool(pool: Pool)
	for v = 1, MechanicsTuning.instance.dial_settings do
		local f = if pool.count == 0 then 0 else pool.counts[v] / pool.count
		pool.frequencies[v] = f
		if f < pool.min then
			pool.min, pool.minValue = f, v
		end
		if f > pool.max then
			pool.max, pool.maxValue = f, v
		end
	end
end

local poolCache: { [Draw]: { [Check]: { [number]: PoolStats } } } = {}

function ProcedureContract.settingPools(draw: Draw, check: Check, n: number): PoolStats
	local forDraw = poolCache[draw]
	if forDraw ~= nil and forDraw[check] ~= nil and forDraw[check][n] ~= nil then
		return forDraw[check][n]
	end
	local first = ProcedureContract.sweep(draw, check, n)
	local step, decoy = newPool("step"), newPool("decoy")
	local seedsUsed, acceptedCount = 0, 0
	for seed = 1, ProcedureContract.POOL_SEED_CAP do
		seedsUsed = seed
		local c = if seed <= #first then first[seed] else candidateFor(draw, check, seed, n)
		if #c.report == 0 then
			acceptedCount += 1
			local isStep: { [number]: boolean } = {}
			for _, track in c.steps.tracks do
				for _, id in track do
					isStep[id] = true
				end
			end
			for _, m in c.world.placement.machines do
				addToPool(if isStep[m.id] then step else decoy, (m :: any).requiredSetting)
			end
		end
		if
			step.count >= ProcedureContract.POOL_MIN
			and decoy.count >= ProcedureContract.POOL_MIN
		then
			break
		end
	end
	finishPool(step)
	finishPool(decoy)
	local stats: PoolStats = {
		n = n,
		seedsUsed = seedsUsed,
		accepted = acceptedCount,
		capped = step.count < ProcedureContract.POOL_MIN
			or decoy.count < ProcedureContract.POOL_MIN,
		step = step,
		decoy = decoy,
	}
	poolCache[draw] = poolCache[draw] or {}
	poolCache[draw][check] = poolCache[draw][check] or {}
	poolCache[draw][check][n] = stats
	return stats
end

function ProcedureContract.describePool(pool: Pool): string
	local parts: { string } = {}
	for v = 1, MechanicsTuning.instance.dial_settings do
		table.insert(parts, `{v}: {string.format("%.4f", pool.frequencies[v] or 0)}`)
	end
	return `{pool.name} pool {pool.count} settings [{table.concat(parts, ", ")}], min {string.format(
		"%.4f",
		pool.min
	)} (setting {pool.minValue}), max {string.format("%.4f", pool.max)} (setting {pool.maxValue}), missing {pool.missing}`
end

function ProcedureContract.describePools(stats: PoolStats): string
	return `n = {stats.n}: {stats.accepted} accepted of {stats.seedsUsed} seeds{if stats.capped
		then " (CAPPED)"
		else ""}; {ProcedureContract.describePool(stats.step)}; {ProcedureContract.describePool(
		stats.decoy
	)}`
end

function ProcedureContract.assertSettingPools(draw: Draw, check: Check, n: number): PoolStats
	local stats = ProcedureContract.settingPools(draw, check, n)
	local d = MechanicsTuning.instance.dial_settings
	local target = 1 / d
	local lo = target - ProcedureContract.SETTING_TOLERANCE
	local hi = target + ProcedureContract.SETTING_TOLERANCE
	assert(
		not stats.capped,
		`AC-7: the seed cap of {ProcedureContract.POOL_SEED_CAP} was reached at n = {n} before both pools held {ProcedureContract.POOL_MIN} settings - {ProcedureContract.describePools(
			stats
		)}`
	)
	for _, pool in { stats.step, stats.decoy } do
		assert(
			pool.missing == 0,
			`AC-7: {pool.missing} settings in the {pool.name} pool at n = {n} are not integers in 1..{d} - {ProcedureContract.describePools(
				stats
			)}`
		)
		assert(
			pool.min >= lo and pool.max <= hi,
			`AC-7: the {pool.name} pool at n = {n} is not uniform within 1/{d} ± {ProcedureContract.SETTING_TOLERANCE} ([{string.format(
				"%.4f",
				lo
			)}, {string.format("%.4f", hi)}]) - {ProcedureContract.describePools(stats)}`
		)
	end
	return stats
end

--[[ ------------------------------------------------------------------------
     Hand-built fixtures.

     THE LAYOUT is GEN-001's "square": the 2 × 3 block, ids row-major

         1 2 3
         4 5 6

     with doors 1-2 1-4 2-3 2-5 4-5 5-6, so d(1,3) = d(1,5) = d(3,5) = d(2,4)
     = d(2,6) = d(4,6) = 2, d(1,6) = d(3,4) = d(3,6) = 3, every other pair 1.

     THE PLACEMENT is GEN-002's `validPlacement(n)`: 16 machines in (room,
     slot) order - rooms 1..4 hold three, rooms 5 and 6 two - classes dealt
     round-robin, settings a hand-written list. At n = 4 machine i is class
     ((i − 1) mod 4) + 1, so (id: class, room) reads
       1:c1 r1  2:c2 r1  3:c3 r1  4:c4 r2  5:c1 r2  6:c2 r2  7:c3 r3  8:c4 r3
       9:c1 r3 10:c2 r4 11:c3 r4 12:c4 r4 13:c1 r5 14:c2 r5 15:c3 r6 16:c4 r6
     and stepsPerClass is { 2, 2, 2, 2 }.

     THE RING is `Ring.assign({"p1".."pn"}, Rng.fromSeed(FIXTURE_RING_SEED))`.
     Key classes follow seat order (k(p_i) = i), and σ was READ BACK from the
     shipped `Ring` at seed 1 - `FIXTURE_SIGMA` below, asserted by the controls
     file, never assumed:
       n = 4: p1→p3→p2→p4→p1, so the class ring is 1→3→2→4→1 and the
              NON-adjacent class pairs are {1,2} and {3,4}.
       n = 5: p1→p4→p3→p5→p2→p1, class ring 1→4→3→5→2→1; {1,3} non-adjacent.
       n = 6: p1→p4→p3→p6→p2→p5→p1, class ring 1→4→3→6→2→5→1; {1,2} non-adjacent.

     THE VALID STEPS at n = 4, with A = 1, B = 2, C = 3, D = 4:
       track 1 [C, A, D, B] = machines  3,  5,  8, 14   (rooms 1 2 3 5)
       track 2 [D, B, C, A] = machines 12,  6,  7,  9   (rooms 4 2 3 3)
       finale { 14, 9 }: classes 2 and 1 (non-adjacent), rooms 5 and 3, d = 2
       = paired_room_distance_min exactly, so "≥" is pinned at its boundary.
     Each class twice, every track alternates, no machine twice.
     --------------------------------------------------------------------- ]]

ProcedureContract.FIXTURE_LAYOUT = PlacementContract.FIXTURE_LAYOUT
ProcedureContract.FIXTURE_RING_SEED = 1

-- σ as read back at FIXTURE_RING_SEED. The controls file asserts this
-- against `Ring.assign` so the comment above cannot drift from the code.
ProcedureContract.FIXTURE_SIGMA = {
	[4] = { p1 = "p3", p2 = "p4", p3 = "p2", p4 = "p1" },
	[5] = { p1 = "p4", p2 = "p1", p3 = "p5", p4 = "p3", p5 = "p2" },
	[6] = { p1 = "p4", p2 = "p5", p3 = "p6", p4 = "p3", p5 = "p1", p6 = "p2" },
}

local VALID_STEPS: { [number]: Steps } = {
	[4] = { tracks = { { 3, 5, 8, 14 }, { 12, 6, 7, 9 } }, finale = { 14, 9 } },
	-- n = 5: machines 1:c1 2:c2 3:c3 4:c4 5:c5 6:c1 7:c2 8:c3 9:c4 10:c5 11:c1
	-- 12:c2 13:c3 14:c1 15:c2 16:c3 (rooms as above); stepsPerClass 2,2,2,1,1.
	-- track 1 [c2, c3, c5, c1] = 2, 8, 10, 14; track 2 [c4, c1, c2, c3] =
	-- 4, 6, 12, 3; finale { 14 (r5), 3 (r1) }, classes 1 and 3, d = 2.
	[5] = { tracks = { { 2, 8, 10, 14 }, { 4, 6, 12, 3 } }, finale = { 14, 3 } },
	-- n = 6: machines 1:c1 2:c2 3:c3 4:c4 5:c5 6:c6 7:c1 8:c2 9:c3 10:c4 11:c5
	-- 12:c6 13:c1 14:c2 15:c1 16:c2; stepsPerClass 2,2,1,1,1,1.
	-- track 1 [c3, c2, c4, c1] = 3, 8, 10, 13; track 2 [c5, c1, c6, c2] =
	-- 5, 7, 12, 2; finale { 13 (r5), 2 (r1) }, classes 1 and 2, d = 2.
	[6] = { tracks = { { 3, 8, 10, 13 }, { 5, 7, 12, 2 } }, finale = { 13, 2 } },
}

-- What the hand-drawn fixtures were drawn for. The controls file asserts each
-- against the read constant; the test files never write these numbers.
ProcedureContract.FIXTURE_ASSUMES = {
	procedureTracks = 2,
	stepsPerTrack = 4,
	procedureLength = 8,
	pairedRoomDistanceMin = 2,
}

function ProcedureContract.fixtureWorld(n: number): World
	return {
		seed = ProcedureContract.FIXTURE_RING_SEED,
		n = n,
		layout = ProcedureContract.FIXTURE_LAYOUT,
		placement = PlacementContract.validPlacement(n),
		assignment = ProcedureContract.assignmentFor(ProcedureContract.FIXTURE_RING_SEED, n),
	}
end

-- A fresh valid Steps for n in 4..6.
function ProcedureContract.validSteps(n: number): Steps
	local s = VALID_STEPS[n]
	assert(s ~= nil, `no hand-built steps for n = {n}`)
	return Deep.copy(s)
end

-- A Steps of no shape at all. `check` must not raise on it and must report
-- `shape`; what else it reports is its own reading (see `violations`).
function ProcedureContract.emptySteps(): Steps
	return { tracks = {}, finale = {} }
end

--[[
	The violation fixtures. Each is the valid n = 4 (or n = 5) steps with the
	fewest edits that trip the clause it is named for, and `expect` is the
	EXACT sorted list of heads `check` must report - written by hand from the
	Contract's table and the σ above.

	Three tokens have NO sole fixture, and cannot:
	  * `INV_every_class_has_a_step:missing` - a class with no step has 0 ≠
	    stepsPerClass[c] ≥ 1 steps, so `count` fires with it; and its holder can
	    turn nothing, so `INV_k_essential` fires too.
	  * `INV_k_essential:turn` - with one class per player, "no step only p can
	    turn" is exactly "p's class has no step", which is `missing`.
	  * `INV_k_essential:read` - p reads class k(σ(p)); with one class per player
	    its holder σ(p) then cannot turn either, and `turn` is the first clause.
	    `read` alone needs a player holding two classes (a post-withdrawal
	    ring), which the Contract puts outside generation. It stays in the table
	    for that case and is pinned here only as an accepted head shape.
]]
export type Violation = { name: string, n: number, expect: { string }, steps: Steps }

ProcedureContract.NO_SOLE_FIXTURE = {
	["INV_every_class_has_a_step:missing"] = "a missing class also breaks count and k-essential",
	["INV_k_essential:turn"] = "with one class per player, a lost turn is a missing class",
	["INV_k_essential:read"] = "reachable only when a player holds two classes (not at generation)",
}

function ProcedureContract.violationFixtures(): { Violation }
	local out: { Violation } = {}

	local function add(name: string, n: number, expect: { string }, edit: (Steps) -> ())
		local s = ProcedureContract.validSteps(n)
		edit(s)
		table.sort(expect)
		table.insert(out, { name = name, n = n, expect = expect, steps = s })
	end

	-- INV_balanced_steps:shape. Every shape fixture keeps classes, counts,
	-- alternation and the finale pair intact wherever they can be read, so
	-- "stop at shape" and "evaluate the rest" both give exactly { shape }.

	-- Track 2's class-3 step becomes machine 3, already track 1's first step.
	add("a machine that is a step twice", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[2][3] = 3
	end)

	add("a step id above the placement", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[1][1] = 17
	end)

	add("a step id of 0", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[1][1] = 0
	end)

	-- Both tracks end to end; the join is class 2 then class 4.
	add("one track of eight steps", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks = { { 3, 5, 8, 14, 12, 6, 7, 9 } }
	end)

	-- A third track of the four unused classes' machines, one each.
	add("three tracks", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[3] = { 1, 2, 11, 4 }
	end)

	-- Track 2 loses its class-2 step: [c4, c3, c1]; the finale is untouched.
	add("a track of three steps", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[2] = { 12, 7, 9 }
	end)

	-- Track 2 gains class 4's unused machine 16: [c4, c2, c4, c3, c1].
	add("a track of five steps", 4, { "INV_balanced_steps:shape" }, function(s)
		s.tracks[2] = { 12, 6, 16, 7, 9 }
	end)

	add("finale listed in the wrong order", 4, { "INV_balanced_steps:shape" }, function(s)
		s.finale = { 9, 14 }
	end)

	-- Machine 1 is class 1 in room 1: d(5, 1) = 2, classes 2 and 1 - the pair
	-- is fine; it is simply not track 2's last step.
	add(
		"finale names a machine that is not a track's last step",
		4,
		{ "INV_balanced_steps:shape" },
		function(s)
			s.finale = { 14, 1 }
		end
	)

	-- INV_balanced_steps:count

	-- Track 2's class-3 step becomes class 4's machine 16: class 4 has three
	-- steps, class 3 one. [c4, c2, c4, c1] still alternates.
	add("a class with three steps and another with one", 4, {
		"INV_balanced_steps:count",
	}, function(s)
		s.tracks[2] = { 12, 6, 16, 9 }
	end)

	-- n = 5: track 2's class-1 step (6) becomes class 5's machine 5. Class 1
	-- has 1 step where stepsPerClass says 2, class 5 has 2 where it says 1 -
	-- the counts still differ by at most 1, so the stepsPerClass clause alone
	-- is what fires. [c4, c5, c2, c3] alternates; finale { 14, 3 } unchanged.
	add(
		"counts within one of each other but not placement.stepsPerClass",
		5,
		{ "INV_balanced_steps:count" },
		function(s)
			s.tracks[2] = { 4, 5, 12, 3 }
		end
	)

	-- INV_every_class_has_a_step:missing (never alone - see above)

	-- Both class-3 steps become class-4 machines (16 and 4): class 3 has no
	-- step, class 4 has four. [c4, c1, c4, c2] and [c4, c2, c4, c1] alternate;
	-- the finale is untouched. p3 holds class 3 and can turn nothing, so
	-- `turn` is the first k-essential clause.
	add("a class with no step", 4, {
		"INV_balanced_steps:count",
		"INV_every_class_has_a_step:missing",
		"INV_k_essential:turn",
	}, function(s)
		s.tracks[1] = { 16, 5, 8, 14 }
		s.tracks[2] = { 12, 6, 4, 9 }
	end)

	-- INV_track_alternates:adjacent (AC-2's control)

	-- Track 1 [C, C, D, A] = 3, 7, 8, 9; track 2 [A, B, D, B] = 5, 6, 12, 14.
	-- Each class still twice; finale { 9 (c1, r3), 14 (c2, r5) }, d = 2,
	-- classes 1 and 2 non-adjacent.
	add(
		"track 1 opens with two steps of one class, [c1, c1, c2, c3] (AC-2's control)",
		4,
		{ "INV_track_alternates:adjacent" },
		function(s)
			s.tracks[1] = { 3, 7, 8, 9 }
			s.tracks[2] = { 5, 6, 12, 14 }
			s.finale = { 9, 14 }
		end
	)

	-- INV_finale:rooms (AC-3's first control)

	-- Machines 6 (c2, room 2) and 9 (c1, room 3): d(2, 3) = 1. Track 1
	-- [c3, c1, c4, c2] = 3, 5, 8, 6; track 2 [c4, c2, c3, c1] = 12, 14, 7, 9.
	add("finale machines in adjacent rooms (AC-3's control)", 4, {
		"INV_finale:rooms",
	}, function(s)
		s.tracks[1] = { 3, 5, 8, 6 }
		s.tracks[2] = { 12, 14, 7, 9 }
		s.finale = { 6, 9 }
	end)

	-- Machine 13 is class 1 in room 5, the room of machine 14.
	add("finale machines in one room", 4, { "INV_finale:rooms" }, function(s)
		s.tracks[2] = { 12, 6, 7, 13 }
		s.finale = { 14, 13 }
	end)

	-- INV_finale:ring (AC-3's second control)

	-- Track 2 [D, B, A, C] = 12, 6, 9, 7: finale { 14 (c2, r5), 7 (c3, r3) },
	-- d = 2, but 3 → 2 on the class ring, so the holders p3 and p2 are
	-- neighbours.
	add("finale classes held by ring neighbours (AC-3's control)", 4, {
		"INV_finale:ring",
	}, function(s)
		s.tracks[2] = { 12, 6, 9, 7 }
		s.finale = { 14, 7 }
	end)

	-- Track 2 [D, A, C, B] = 12, 9, 7, 2: finale { 14 (c2, r5), 2 (c2, r1) },
	-- d = 2, both class 2 - one holder, one turner. Counts are still 2 each.
	add("finale classes held by one player", 4, { "INV_finale:ring" }, function(s)
		s.tracks[2] = { 12, 9, 7, 2 }
		s.finale = { 14, 2 }
	end)

	-- Track 2 [D, B, A, C] = 12, 6, 9, 11: finale { 14 (c2, r5), 11 (c3, r4) },
	-- d(4, 5) = 1 AND neighbours: one string, the first clause, `rooms`.
	add("finale in adjacent rooms and held by ring neighbours - rooms is the first clause", 4, {
		"INV_finale:rooms",
	}, function(s)
		s.tracks[2] = { 12, 6, 9, 11 }
		s.finale = { 14, 11 }
	end)

	return out
end

-- A deep snapshot, for the purity checks.
function ProcedureContract.snapshot(value: any): any
	return Deep.copy(value)
end

return ProcedureContract
