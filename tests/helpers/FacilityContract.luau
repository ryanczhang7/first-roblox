--!strict
--[[
	GEN-004's oracle, checks, statistics and fixtures, written once over a
	GENERATE function and a COMPUTE function rather than over
	`src/server/facility/Generator.luau` and `Par.luau` by name - the
	`ProcedureContract` arrangement, for the same reason.

	`tests/server/par_test.luau` and `tests/server/generator_test.luau` apply
	these to the real modules. `tests/server/facility_controls_test.luau`
	applies them to the deliberately wrong computes and generators in
	`FacilityStubs.luau`, so that in RED - where neither module exists, both
	real files fail at `require`, and not one assertion in them has executed -
	every check here has been EXECUTED and observed to reject the defect it
	exists to catch, and to accept a reference that is correct.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE.

	  * SETTLED. `par` below is the TEST'S OWN implementation of
	    `mechanics.md` §6.3 (Contract C-2, C-8): its own BFS over `layout.doors`
	    (`LayoutContract.bfs`, which imports nothing from `src/`), its own
	    helper/turner lookup from `assignment.lens` and `assignment.keyClasses`
	    (never `Ring.lensOf`, never `Layout.distance`). AC-1's four fixtures are
	    hand-built and their expected par is written as ARITHMETIC over
	    `room_traversal_seconds`, `par_ping_seconds` and `par_turn_seconds` as
	    read from `MechanicsTuning`, with the schedule derived step by step in
	    a comment. The controls file shows `par` reproduces that arithmetic, so
	    the sweep's oracle is itself pinned to the hand derivation.
	  * MECHANICAL. `recompose` is the independent recomposition of attempt `i`
	    from `Rng.fromSeed(seed):derive("instance"):derive("attempt-" .. i)` with
	    the real `Layout`, `Machines` and `Steps` (all merged) on the C-4
	    sub-streams, checked in C-4's order. AC-2, AC-3, AC-4 and AC-6 compare
	    a generator's output against it by value.
	  * MEASURED. `acceptance` prints the first-attempt rate per n in the exact
	    C-8 line. It asserts nothing about the rate: AC-5 says the Lead PO reads
	    the number. It does assert every seed is accepted within the bound and
	    every facility passes every invariant, par and traversal recomputed here.

	Every constant is READ from `MechanicsTuning.instance` or `Tuning.round`;
	the only literals are sample sizes and the hand-built fixtures, which say
	which shipped values they were drawn for.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local Raise = require("./Contract")
local Layout = require("../../src/server/facility/Layout")
local LayoutContract = require("./LayoutContract")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PlacementContract = require("./PlacementContract")
local ProcedureContract = require("./ProcedureContract")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local Steps = require("../../src/server/facility/Steps")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")

local FacilityContract = {}

export type Layout = LayoutContract.Layout
export type Placement = PlacementContract.Placement
export type Machine = PlacementContract.Machine
export type Steps = ProcedureContract.Steps
export type Assignment = Ring.Assignment
export type Tuning = typeof(MechanicsTuning)
export type Facility = {
	layout: Layout,
	placement: Placement,
	steps: Steps,
	spawnRoom: number,
	par: number,
	attempt: number,
}
export type Compute = (
	layout: Layout,
	placement: Placement,
	steps: Steps,
	assignment: Assignment,
	tuning: Tuning
) -> number
export type Stages = { layout: any?, machines: any?, steps: any? }
export type Generate = (
	assignment: Assignment,
	seed: number,
	tuning: Tuning,
	predicateOverride: ((Facility) -> string?)?,
	stagesOverride: Stages?
) -> any

-- The shipped tuning. `room_seconds` is read from ROUND-002's module, as C-3
-- says the generator must; `MechanicsTuning` does not carry it.
FacilityContract.TUNING = MechanicsTuning
FacilityContract.ROUND_SECONDS = Tuning.round.round_seconds

-- C-8: seeds 1..SWEEP_SEEDS at each n in CLASS_COUNTS.
FacilityContract.SWEEP_SEEDS = 1000
FacilityContract.CLASS_COUNTS = { 4, 5, 6 }
-- AC-5's stop rule. PRINTED, never asserted: below it the test still passes
-- and the Lead PO takes the number to the Game Designer.
FacilityContract.ACCEPTANCE_FLOOR = 0.25

-- C-5: the head of a traversal failure record. Includes the trailing space,
-- so a needle compared with `string.sub(s, 1, #head) == head` cannot float.
FacilityContract.TRAVERSAL_HEAD = "INV_traversal:par "

-- C-6: exactly these keys on a facility, sorted.
FacilityContract.FACILITY_KEYS = { "attempt", "layout", "par", "placement", "spawnRoom", "steps" }

--[[ ------------------------------------------------------------------------
     Sweep inputs, C-8: for seed s and n, the ring is
     `Ring.assign({"p1".."pn"}, Rng.fromSeed(s))` and attempt i draws from
     `Rng.fromSeed(s):derive("instance"):derive("attempt-" .. i)`.
     --------------------------------------------------------------------- ]]

function FacilityContract.playersFor(n: number): { string }
	return ProcedureContract.playersFor(n)
end

function FacilityContract.ringFor(seed: number, n: number): Assignment
	return Ring.assign(FacilityContract.playersFor(n), Rng.fromSeed(seed))
end

function FacilityContract.attemptRng(seed: number, attempt: number): Rng.Rng
	return Rng.fromSeed(seed):derive("instance"):derive(`attempt-{attempt}`)
end

-- C-4: the classes handed to the machines stage - the sorted union of every
-- list in `assignment.keyClasses`.
function FacilityContract.classesOf(assignment: Assignment): { number }
	return ProcedureContract.classesInPlay(assignment)
end

-- A copy of the shipped tuning with `instance` keys replaced, frozen like the
-- real module. C-3: a test that needs every attempt to fail `INV_traversal`
-- passes a large `schedule_slack`; it never edits `round_seconds`.
function FacilityContract.tuningWith(instanceOverrides: { [string]: any }): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for key, value in pairs(instanceOverrides) do
		fake.instance[key] = value
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

--[[ ------------------------------------------------------------------------
     The test's own §6.3, exactly as C-2 writes it.

       walk(a, b)  = edges on a shortest doorway path × room_traversal_seconds
       turner(s)   = the player whose keyClasses list contains the class
       helper(s)   = the player whose lens IS the class
       start       = layout.spawnRoom, the FIELD, for everyone
       order       = T1[1], T2[1], T1[2], T2[2], ... over tracks[t][1..#t-1];
                     a track that runs out first lets the other's rest follow
       each step   = max(helper walk, turner walk) + ping + turn; both move
       the finale  = max over both sub-steps of max(helper walk, turner walk)
                     + ping + turn, once

     Distances come from `LayoutContract.bfs` over `layout.doors`, never from
     `Layout.distance`; a Par that read distances wrongly would otherwise be
     agreed with by an oracle that read them the same way.
     --------------------------------------------------------------------- ]]

function FacilityContract.turnerOf(assignment: Assignment, class: number): string?
	for _, p in assignment.players do
		for _, c in assignment.keyClasses[p] or {} do
			if c == class then
				return p
			end
		end
	end
	return nil
end

function FacilityContract.helperOf(assignment: Assignment, class: number): string?
	for _, p in assignment.players do
		if assignment.lens[p] == class then
			return p
		end
	end
	return nil
end

-- Shortest-path edge counts, memoised per source room for one layout.
function FacilityContract.distanceFn(layout: Layout): (number, number) -> number
	local fromCache: { [number]: { number } } = {}
	return function(a: number, b: number): number
		if a == b then
			return 0
		end
		local dist = fromCache[a]
		if dist == nil then
			dist = LayoutContract.bfs(#layout.rooms, layout.doors, a)
			fromCache[a] = dist
		end
		local d = dist[b]
		assert(d ~= nil and d ~= math.huge, `room {b} is unreachable from room {a}`)
		return d
	end
end

-- The ordinary steps in C-2's interleaved order, then the finale ids.
function FacilityContract.scheduleOrder(steps: Steps): ({ number }, { number })
	local ordinary: { number } = {}
	local longest = 0
	for _, track in steps.tracks do
		longest = math.max(longest, #track - 1)
	end
	for i = 1, longest do
		for _, track in steps.tracks do
			if i <= #track - 1 then
				table.insert(ordinary, track[i])
			end
		end
	end
	return ordinary, table.clone(steps.finale)
end

export type Participants = { turner: string, helper: string, room: number }

-- Who walks to step `id` and where. Raises on an unknown id or an unheld
-- class, so a bad fixture fails here with a name rather than as a wrong sum.
function FacilityContract.participantsOf(
	placement: Placement,
	assignment: Assignment,
	id: number
): Participants
	local machine: Machine? = nil
	for _, m in placement.machines do
		if m.id == id then
			machine = m
			break
		end
	end
	assert(machine ~= nil, `step {id} is not a machine id in the placement`)
	local m = machine :: Machine
	local turner = FacilityContract.turnerOf(assignment, m.keyClass)
	local helper = FacilityContract.helperOf(assignment, m.keyClass)
	assert(turner ~= nil, `no seated player holds class {m.keyClass} (machine {id})`)
	assert(helper ~= nil, `no seated player's lens is class {m.keyClass} (machine {id})`)
	return { turner = turner :: string, helper = helper :: string, room = m.room }
end

function FacilityContract.par(
	layout: Layout,
	placement: Placement,
	steps: Steps,
	assignment: Assignment,
	tuning: Tuning
): number
	local t = tuning.instance
	local distance = FacilityContract.distanceFn(layout)
	local function walk(a: number, b: number): number
		return distance(a, b) * t.room_traversal_seconds
	end

	local pos: { [string]: number } = {}
	for _, p in assignment.players do
		pos[p] = layout.spawnRoom
	end

	local total = 0
	local ordinary, finale = FacilityContract.scheduleOrder(steps)
	for _, id in ordinary do
		local who = FacilityContract.participantsOf(placement, assignment, id)
		local d = math.max(walk(pos[who.helper], who.room), walk(pos[who.turner], who.room))
		total += d + t.par_ping_seconds + t.par_turn_seconds
		pos[who.helper] = who.room
		pos[who.turner] = who.room
	end

	local longest = 0
	for _, id in finale do
		local who = FacilityContract.participantsOf(placement, assignment, id)
		local d = math.max(walk(pos[who.helper], who.room), walk(pos[who.turner], who.room))
		longest = math.max(longest, d)
	end
	total += longest + t.par_ping_seconds + t.par_turn_seconds
	return total
end

-- C-3, as the test reads it: `par × schedule_slack ≤ round_seconds`, with
-- `≤`, so equality is accepted.
function FacilityContract.traversalOk(par: number, tuning: Tuning): boolean
	return par * tuning.instance.schedule_slack <= FacilityContract.ROUND_SECONDS
end

function FacilityContract.traversalFailure(par: number, tuning: Tuning): string
	return `{FacilityContract.TRAVERSAL_HEAD}{par} × {tuning.instance.schedule_slack} > round_seconds {FacilityContract.ROUND_SECONDS}`
end

-- `<INV>:<token>` of a report string, or nil when it has no such head.
function FacilityContract.headOf(s: any): string?
	if typeof(s) ~= "string" then
		return nil
	end
	return string.match(s, "^([%w_]+:[%w_]+) ")
end

function FacilityContract.isTraversal(s: any): boolean
	local head = FacilityContract.TRAVERSAL_HEAD
	return typeof(s) == "string" and string.sub(s, 1, #head) == head
end

--[[ ------------------------------------------------------------------------
     The independent recomposition of one attempt, C-4: the stages in order on
     their own sub-streams, the checks in order, the first non-empty report
     ends the attempt. `stage` names the check that failed, or "accepted".
     --------------------------------------------------------------------- ]]

export type Attempt = {
	attempt: number,
	stage: "layout" | "machines" | "steps" | "traversal" | "accepted",
	failure: string?,
	layout: Layout?,
	placement: Placement?,
	steps: Steps?,
	par: number?,
}

function FacilityContract.recompose(
	assignment: Assignment,
	seed: number,
	attempt: number,
	tuning: Tuning
): Attempt
	local a = FacilityContract.attemptRng(seed, attempt)
	local classes = FacilityContract.classesOf(assignment)
	local out: Attempt = { attempt = attempt, stage = "accepted" }

	local layout = Layout.generate(a:derive("layout"), tuning)
	out.layout = layout
	local report = Layout.check(layout, tuning)
	if #report > 0 then
		out.stage, out.failure = "layout", report[1]
		return out
	end

	local placement = Machines.generate(a:derive("machines"), layout, classes, tuning)
	out.placement = placement
	report = Machines.check(placement, layout, classes, tuning)
	if #report > 0 then
		out.stage, out.failure = "machines", report[1]
		return out
	end

	local steps = Steps.draw(a:derive("steps"), layout, placement, assignment, tuning)
	out.steps = steps
	report = Steps.check(steps, layout, placement, assignment, tuning)
	if #report > 0 then
		out.stage, out.failure = "steps", report[1]
		return out
	end

	local par = FacilityContract.par(layout, placement, steps, assignment, tuning)
	out.par = par
	if not FacilityContract.traversalOk(par, tuning) then
		out.stage, out.failure = "traversal", FacilityContract.traversalFailure(par, tuning)
	end
	return out
end

-- C-6: the facility an accepted attempt yields.
function FacilityContract.facilityOf(attempt: Attempt): Facility
	assert(attempt.stage == "accepted", `attempt {attempt.attempt} was not accepted`)
	local layout = attempt.layout :: Layout
	return {
		layout = layout,
		placement = attempt.placement :: Placement,
		steps = attempt.steps :: Steps,
		spawnRoom = layout.spawnRoom,
		par = attempt.par :: number,
		attempt = attempt.attempt,
	}
end

export type Expected = { accepted: Attempt?, earlier: { Attempt } }

local expectedCache: { [Tuning]: { [number]: { [number]: Expected } } } = {}

-- The first attempt in 1..generator_attempts_max the recomposition accepts,
-- and every failed attempt before it. Memoised per (tuning, n, seed).
function FacilityContract.expectedFor(seed: number, n: number, tuning: Tuning): Expected
	local forTuning = expectedCache[tuning]
	if forTuning ~= nil and forTuning[n] ~= nil and forTuning[n][seed] ~= nil then
		return forTuning[n][seed]
	end
	local assignment = FacilityContract.ringFor(seed, n)
	local earlier: { Attempt } = {}
	local accepted: Attempt? = nil
	for i = 1, tuning.instance.generator_attempts_max do
		local attempt = FacilityContract.recompose(assignment, seed, i, tuning)
		if attempt.stage == "accepted" then
			accepted = attempt
			break
		end
		table.insert(earlier, attempt)
	end
	local out: Expected = { accepted = accepted, earlier = earlier }
	expectedCache[tuning] = expectedCache[tuning] or {}
	expectedCache[tuning][n] = expectedCache[tuning][n] or {}
	expectedCache[tuning][n][seed] = out
	return out
end

--[[ ------------------------------------------------------------------------
     AC-5 / AC-6: everything a returned facility must satisfy, re-derived
     here. One string per problem; `{}` means valid.
     --------------------------------------------------------------------- ]]

local function sortedKeys(value: any): { string }
	local keys: { string } = {}
	if typeof(value) == "table" then
		for key in pairs(value :: { [any]: any }) do
			table.insert(keys, tostring(key))
		end
	end
	table.sort(keys)
	return keys
end

FacilityContract.sortedKeys = sortedKeys

function FacilityContract.facilityViolations(
	facility: any,
	assignment: Assignment,
	tuning: Tuning
): { string }
	local out: { string } = {}
	if typeof(facility) ~= "table" then
		return { `shape: facility is {typeof(facility)}` }
	end
	local keys = sortedKeys(facility)
	if not Deep.equal(keys, FacilityContract.FACILITY_KEYS) then
		table.insert(
			out,
			`AC-6 shape: facility carries {Deep.show(keys)}, the Contract names exactly {Deep.show(
				FacilityContract.FACILITY_KEYS
			)}`
		)
	end
	local layout, placement, steps = facility.layout, facility.placement, facility.steps
	if typeof(layout) ~= "table" or typeof(placement) ~= "table" or typeof(steps) ~= "table" then
		table.insert(out, "AC-6 shape: layout, placement and steps must all be tables")
		return out
	end
	local classes = FacilityContract.classesOf(assignment)
	for _, s in Layout.check(layout, tuning) do
		table.insert(out, `AC-5 layout: {s}`)
	end
	for _, s in Machines.check(placement, layout, classes, tuning) do
		table.insert(out, `AC-5 machines: {s}`)
	end
	for _, s in Steps.check(steps, layout, placement, assignment, tuning) do
		table.insert(out, `AC-5 steps: {s}`)
	end
	if #out > 0 then
		return out
	end
	local par = FacilityContract.par(layout, placement, steps, assignment, tuning)
	if facility.par ~= par then
		table.insert(
			out,
			`AC-5 par: facility.par is {tostring(facility.par)}, the test's own §6.3 gives {par}`
		)
	end
	if not FacilityContract.traversalOk(par, tuning) then
		table.insert(out, `AC-5 {FacilityContract.traversalFailure(par, tuning)}`)
	end
	if facility.spawnRoom ~= layout.spawnRoom then
		table.insert(
			out,
			`AC-6 spawnRoom: facility.spawnRoom is {tostring(facility.spawnRoom)}, layout.spawnRoom is {layout.spawnRoom}`
		)
	end
	local attempt = facility.attempt
	if
		typeof(attempt) ~= "number"
		or attempt ~= math.floor(attempt)
		or attempt < 1
		or attempt > tuning.instance.generator_attempts_max
	then
		table.insert(
			out,
			`AC-2 attempt: {tostring(attempt)} is not an integer in 1..{tuning.instance.generator_attempts_max}`
		)
	end
	return out
end

--[[ ------------------------------------------------------------------------
     The sweep: one `generate` per seed per n, memoised per (generate, n).
     --------------------------------------------------------------------- ]]

export type Swept = { seed: number, assignment: Assignment, result: any }

local sweepCache: { [Generate]: { [number]: { Swept } } } = {}

function FacilityContract.sweep(generate: Generate, n: number): { Swept }
	local forGenerate = sweepCache[generate]
	if forGenerate ~= nil and forGenerate[n] ~= nil then
		return forGenerate[n]
	end
	local out: { Swept } = {}
	for seed = 1, FacilityContract.SWEEP_SEEDS do
		local assignment = FacilityContract.ringFor(seed, n)
		out[seed] = {
			seed = seed,
			assignment = assignment,
			result = generate(assignment, seed, MechanicsTuning),
		}
	end
	sweepCache[generate] = sweepCache[generate] or {}
	sweepCache[generate][n] = out
	return out
end

-- The facility of a swept result, or nil with a reason.
local function facilityOfResult(result: any): (any, string?)
	if typeof(result) ~= "table" then
		return nil, `result is {typeof(result)}`
	end
	if result.kind ~= "facility" then
		return nil, `result.kind is {tostring(result.kind)}`
	end
	if typeof(result.facility) ~= "table" then
		return nil, `result.facility is {typeof(result.facility)}`
	end
	return result.facility, nil
end

FacilityContract.facilityOfResult = facilityOfResult

-- C-5: a facility result carries exactly { kind, facility }; a failed one
-- exactly { kind, failures }.
function FacilityContract.resultShapeProblem(result: any): string?
	if typeof(result) ~= "table" then
		return `result is {typeof(result)}`
	end
	local keys = sortedKeys(result)
	if result.kind == "facility" then
		if not Deep.equal(keys, { "facility", "kind" }) then
			return `a facility result carries {Deep.show(keys)}, expected exactly facility and kind`
		end
	elseif result.kind == "failed" then
		if not Deep.equal(keys, { "failures", "kind" }) then
			return `a failed result carries {Deep.show(keys)}, expected exactly failures and kind`
		end
	else
		return `result.kind is {Deep.show(result.kind)}, expected "facility" or "failed"`
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     AC-5: the acceptance measurement, and the invariants over the sweep.
     --------------------------------------------------------------------- ]]

export type AcceptanceStats = {
	n: number,
	seeds: number,
	facilities: number, -- results of kind "facility"
	firstAttempt: number, -- of those, accepted at attempt 1
	rate: number,
	maxAttempt: number,
	rejectedBy: { [string]: number }, -- head -> earlier attempts (by recomposition) reporting it
}

function FacilityContract.acceptance(generate: Generate, n: number): AcceptanceStats
	local swept = FacilityContract.sweep(generate, n)
	local facilities, firstAttempt, maxAttempt = 0, 0, 0
	local rejectedBy: { [string]: number } = {}
	for _, s in swept do
		local facility = facilityOfResult(s.result)
		if facility ~= nil then
			facilities += 1
			local attempt = facility.attempt
			if attempt == 1 then
				firstAttempt += 1
			end
			if typeof(attempt) == "number" then
				maxAttempt = math.max(maxAttempt, attempt)
				for _, e in FacilityContract.expectedFor(s.seed, n, MechanicsTuning).earlier do
					if e.attempt < attempt then
						local head = FacilityContract.headOf(e.failure) or "<no head>"
						rejectedBy[head] = (rejectedBy[head] or 0) + 1
					end
				end
			end
		end
	end
	return {
		n = n,
		seeds = #swept,
		facilities = facilities,
		firstAttempt = firstAttempt,
		rate = if #swept == 0 then 0 else firstAttempt / #swept,
		maxAttempt = maxAttempt,
		rejectedBy = rejectedBy,
	}
end

-- C-8's exact line, and nothing else on it.
function FacilityContract.describeAcceptance(stats: AcceptanceStats): string
	return `[measured] Generator acceptance: n = {stats.n}: {stats.firstAttempt} of {stats.seeds} first attempts accepted, rate {string.format(
		"%.4f",
		stats.rate
	)}; max attempt {stats.maxAttempt}`
end

function FacilityContract.describeRejections(stats: AcceptanceStats): string
	local heads: { string } = {}
	for head in pairs(stats.rejectedBy) do
		table.insert(heads, head)
	end
	table.sort(heads)
	local parts: { string } = {}
	for _, head in heads do
		table.insert(parts, `{head} × {stats.rejectedBy[head]}`)
	end
	return `n = {stats.n}: earlier attempts rejected by [{table.concat(parts, ", ")}]`
end

-- Every seed yields a facility within the bound, and every facility passes
-- every invariant as re-derived here. Returns the stats for printing.
function FacilityContract.assertSweepValid(generate: Generate, n: number): AcceptanceStats
	local problems: { string } = {}
	for _, s in FacilityContract.sweep(generate, n) do
		local facility, why = facilityOfResult(s.result)
		if facility == nil then
			table.insert(problems, `seed {s.seed}: no facility - {why}`)
		else
			for _, v in FacilityContract.facilityViolations(facility, s.assignment, MechanicsTuning) do
				table.insert(problems, `seed {s.seed}: {v}`)
			end
		end
		if #problems > 20 then
			break
		end
	end
	if #problems > 0 then
		Raise.fail(
			`AC-5: at n = {n} the sweep returned a facility that is missing or breaks an invariant:\n{Raise.firstFew(
				problems,
				20
			)}`
		)
	end
	return FacilityContract.acceptance(generate, n)
end

--[[ ------------------------------------------------------------------------
     AC-2: the facility is the first accepted attempt, by value.
     --------------------------------------------------------------------- ]]

function FacilityContract.assertRecomposition(generate: Generate, n: number)
	local problems: { string } = {}
	for _, s in FacilityContract.sweep(generate, n) do
		local facility, why = facilityOfResult(s.result)
		local expected = FacilityContract.expectedFor(s.seed, n, MechanicsTuning)
		if facility == nil then
			table.insert(problems, `seed {s.seed}: no facility - {why}`)
		elseif expected.accepted == nil then
			table.insert(
				problems,
				`seed {s.seed}: the recomposition accepts no attempt within the bound, yet a facility came back at attempt {tostring(
					facility.attempt
				)}`
			)
		else
			local want = FacilityContract.facilityOf(expected.accepted :: Attempt)
			if facility.attempt ~= want.attempt then
				table.insert(
					problems,
					`seed {s.seed}: facility.attempt is {tostring(facility.attempt)}; the first attempt the recomposition accepts is {want.attempt} (earlier attempts failed: {#expected.earlier})`
				)
			elseif not Deep.equal(want, facility) then
				-- Which top-level fields moved, in a fixed order, before the
				-- diff: the diff is long and a reader (or a needle) wants the
				-- summary first.
				local moved: { string } = {}
				for _, key in FacilityContract.FACILITY_KEYS do
					if not Deep.equal((want :: any)[key], (facility :: any)[key]) then
						table.insert(moved, key)
					end
				end
				table.insert(
					problems,
					`seed {s.seed}: the facility is not the recomposition of attempt {want.attempt} - fields differing: {table.concat(
						moved,
						", "
					)}:\n{Deep.diff(want, facility)}`
				)
			end
		end
		if #problems > 10 then
			break
		end
	end
	if #problems > 0 then
		Raise.fail(
			`AC-2: at n = {n} a facility is not the first attempt that passes every invariant, recomposed independently:\n{Raise.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- The first swept seed whose facility records an attempt of 2 or more.
function FacilityContract.seedAcceptedLater(generate: Generate, n: number): number?
	for _, s in FacilityContract.sweep(generate, n) do
		local facility = facilityOfResult(s.result)
		if facility ~= nil and typeof(facility.attempt) == "number" and facility.attempt >= 2 then
			return s.seed
		end
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     AC-3: sub-streams isolate stages, through `stagesOverride` (C-7).
     --------------------------------------------------------------------- ]]

-- C-7's wrapper: one extra number from the "machines" sub-stream.
function FacilityContract.wrappedMachines(
	rng: Rng.Rng,
	layout: Layout,
	classes: { number },
	tuning: Tuning
): Placement
	-- The one extra number, from the "machines" sub-stream, as AC-3 says.
	local extra = rng:nextNumber()
	--[[
		FOUND IN RED (C-7 amended): under the shipped `Rng`, consuming that
		number and then delegating on the same stream changes NOTHING. A
		derived stream's identity is `identityFor(parent identity, label)`,
		which reads the parent's identity and never its state, and
		`Machines.generate` derives all four of its streams and draws from the
		stream it is handed not at all. So the real stage, run on the advanced
		stream, produces a placement deep-equal to the plain one, and the
		needle below (C-7, "otherwise the wrapper changed nothing and the
		test is vacuous") fired on the REFERENCE generator. For the stage's
		draws to change, the number has to be USED: it names the sub-stream
		the real stage runs on. That is still one extra number consumed from
		the "machines" sub-stream, and the stage's draws now differ entirely,
		so par differs and the accepted attempt may move - the reading C-7's
		second bullet already provided for.
	]]
	return Machines.generate(rng:derive(`__wrapped-{extra}`), layout, classes, tuning)
end

-- C-7's spy: records `rng:derive("__spy"):nextNumber()` per call, then
-- delegates. `derive` reads only the stream's identity, so the draw is not
-- disturbed (verified against `Rng.luau`: `derive` builds a new stream from
-- `identityFor(identity, label)` and touches no state).
function FacilityContract.spySteps(record: { number })
	return function(
		rng: Rng.Rng,
		layout: Layout,
		placement: Placement,
		assignment: Assignment,
		tuning: Tuning
	): Steps
		table.insert(record, rng:derive("__spy"):nextNumber())
		return Steps.draw(rng, layout, placement, assignment, tuning)
	end
end

-- What the spy must record for attempt i if the steps stage is handed
-- `attempt-i`'s "steps" sub-stream.
function FacilityContract.expectedSpy(seed: number, attempt: number): number
	return FacilityContract.attemptRng(seed, attempt):derive("steps"):derive("__spy"):nextNumber()
end

export type IsolationStats = {
	n: number,
	seeds: number,
	placementsDiffer: number,
	sameAttempt: number,
}

function FacilityContract.assertStageIsolation(generate: Generate, n: number): IsolationStats
	local problems: { string } = {}
	local placementsDiffer, sameAttempt = 0, 0
	for _, s in FacilityContract.sweep(generate, n) do
		local plain = facilityOfResult(s.result)
		local wrappedResult = generate(
			s.assignment,
			s.seed,
			MechanicsTuning,
			nil,
			{ machines = FacilityContract.wrappedMachines }
		)
		local wrapped = facilityOfResult(wrappedResult)
		if plain == nil or wrapped == nil then
			table.insert(problems, `seed {s.seed}: plain or wrapped run returned no facility`)
		else
			local want = Layout.generate(
				FacilityContract.attemptRng(s.seed, wrapped.attempt):derive("layout"),
				MechanicsTuning
			)
			if not Deep.equal(want, wrapped.layout) then
				table.insert(
					problems,
					`seed {s.seed}: with the machines wrapper the layout of accepted attempt {wrapped.attempt} is not Layout.generate on that attempt's "layout" sub-stream:\n{Deep.diff(
						want,
						wrapped.layout
					)}`
				)
			end
			if plain.attempt == wrapped.attempt then
				sameAttempt += 1
				if not Deep.equal(plain.layout, wrapped.layout) then
					table.insert(
						problems,
						`seed {s.seed}: both runs accepted attempt {plain.attempt} but their layouts differ:\n{Deep.diff(
							plain.layout,
							wrapped.layout
						)}`
					)
				end
			end
			if not Deep.equal(plain.placement, wrapped.placement) then
				placementsDiffer += 1
			end
		end
		if #problems > 10 then
			break
		end
	end
	if #problems > 0 then
		Raise.fail(
			`AC-3: at n = {n} an extra draw from the "machines" sub-stream moved the layout of the accepted attempt:\n{Raise.firstFew(
				problems,
				10
			)}`
		)
	end
	-- The needle: the wrapper must have changed SOMETHING, or the test above
	-- was satisfied by a wrapper that was never called (or, as found in RED,
	-- by one whose extra draw the real stage could not see).
	if placementsDiffer == 0 then
		Raise.fail(
			`AC-3 needle: at n = {n} no seed's placement differs with the machines wrapper, so the wrapper changed nothing and the isolation test is vacuous`
		)
	end
	return {
		n = n,
		seeds = FacilityContract.SWEEP_SEEDS,
		placementsDiffer = placementsDiffer,
		sameAttempt = sameAttempt,
	}
end

-- The steps stage is handed `attempt-i`'s "steps" sub-stream, the same with
-- and without the machines wrapper, for every attempt up to the accepted one.
function FacilityContract.assertStepsStreamUnmoved(generate: Generate, n: number)
	local problems: { string } = {}
	for _, s in FacilityContract.sweep(generate, n) do
		local plainRecord: { number } = {}
		local wrappedRecord: { number } = {}
		local plainResult = generate(
			s.assignment,
			s.seed,
			MechanicsTuning,
			nil,
			{ steps = FacilityContract.spySteps(plainRecord) }
		)
		local wrappedResult = generate(s.assignment, s.seed, MechanicsTuning, nil, {
			machines = FacilityContract.wrappedMachines,
			steps = FacilityContract.spySteps(wrappedRecord),
		})
		if not Deep.equal(s.result, plainResult) then
			table.insert(
				problems,
				`seed {s.seed}: the spy alone changed the result:\n{Deep.diff(s.result, plainResult)}`
			)
		end
		local plain, wrapped = facilityOfResult(plainResult), facilityOfResult(wrappedResult)
		if plain == nil or wrapped == nil then
			table.insert(problems, `seed {s.seed}: a spied run returned no facility`)
		else
			-- Attempts whose layout or machines check failed never reach the
			-- steps stage (C-4), so the record is shorter by those.
			local expected = FacilityContract.expectedFor(s.seed, n, MechanicsTuning)
			local reached = 0
			for _, e in expected.earlier do
				if e.stage ~= "layout" and e.stage ~= "machines" then
					reached += 1
				end
			end
			reached += 1
			if #plainRecord ~= reached then
				table.insert(
					problems,
					`seed {s.seed}: the steps stage ran {#plainRecord} time(s) without the wrapper, expected {reached} (one per attempt that reached it, up to the accepted attempt {plain.attempt})`
				)
			end
			for i, v in plainRecord do
				local want = FacilityContract.expectedSpy(s.seed, i)
				if v ~= want then
					table.insert(
						problems,
						`seed {s.seed}: without the wrapper the steps stage at attempt {i} was handed a stream whose "__spy" draws {v}, not {want} - not attempt-{i}'s "steps" sub-stream`
					)
				end
			end
			local shared = math.min(#plainRecord, #wrappedRecord)
			for i = 1, shared do
				if plainRecord[i] ~= wrappedRecord[i] then
					table.insert(
						problems,
						`seed {s.seed}: attempt {i}'s steps stream differs with the machines wrapper ({wrappedRecord[i]}) and without ({plainRecord[i]})`
					)
				end
			end
			if shared == 0 then
				table.insert(problems, `seed {s.seed}: the steps stage never ran`)
			end
		end
		if #problems > 10 then
			break
		end
	end
	if #problems > 0 then
		Raise.fail(
			`AC-3: at n = {n} the steps stage is not handed the same "steps" sub-stream with and without the machines wrapper:\n{Raise.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4: the injected predicate and the failure records (C-4, C-5).
     --------------------------------------------------------------------- ]]

-- With an override that fails every attempt: exactly generator_attempts_max
-- records in attempt order; each attempt the recomposition accepts was handed
-- to the override as its facility and is recorded under the override's
-- string verbatim; each attempt the recomposition rejects is recorded under
-- the recomposition's first report string (traversal compared by head), and
-- the override was NOT called for it.
function FacilityContract.assertExhausts(
	generate: Generate,
	seed: number,
	n: number,
	verdict: string
)
	local assignment = FacilityContract.ringFor(seed, n)
	local calls: { any } = {}
	local result = generate(assignment, seed, MechanicsTuning, function(facility: any): string?
		table.insert(calls, Deep.copy(facility))
		return verdict
	end)
	local max = MechanicsTuning.instance.generator_attempts_max
	assert(
		typeof(result) == "table" and result.kind == "failed",
		`AC-4: with an override that fails every attempt, seed {seed} n = {n} returned kind {Deep.show(
			if typeof(result) == "table" then result.kind else result
		)}, expected "failed"`
	)
	local shape = FacilityContract.resultShapeProblem(result)
	assert(shape == nil, `AC-4 / C-5: {tostring(shape)}`)
	local failures = result.failures
	assert(
		typeof(failures) == "table" and #failures == max,
		`AC-4: seed {seed} n = {n}: {if typeof(failures) == "table"
			then #failures
			else typeof(failures)} failure record(s), expected exactly generator_attempts_max = {max}`
	)

	local problems: { string } = {}
	local expectedCalls: { Facility } = {}
	for i = 1, max do
		local attempt = FacilityContract.recompose(assignment, seed, i, MechanicsTuning)
		local record = failures[i]
		local keys = sortedKeys(record)
		if not Deep.equal(keys, { "attempt", "invariant" }) then
			table.insert(
				problems,
				`record {i} carries {Deep.show(keys)}, expected exactly attempt and invariant`
			)
			continue
		end
		if record.attempt ~= i then
			table.insert(problems, `record {i} names attempt {tostring(record.attempt)}`)
		end
		if attempt.stage == "accepted" then
			table.insert(expectedCalls, FacilityContract.facilityOf(attempt))
			if record.invariant ~= verdict then
				table.insert(
					problems,
					`attempt {i} passes every real invariant, so its record must carry the override's string {Deep.show(
						verdict
					)} verbatim; got {Deep.show(record.invariant)}`
				)
			end
		elseif attempt.stage == "traversal" then
			if not FacilityContract.isTraversal(record.invariant) then
				table.insert(
					problems,
					`attempt {i} fails INV_traversal by recomposition (par {attempt.par}); its record carries {Deep.show(
						record.invariant
					)}, which does not start with {Deep.show(FacilityContract.TRAVERSAL_HEAD)}`
				)
			end
		elseif record.invariant ~= attempt.failure then
			table.insert(
				problems,
				`attempt {i} fails {attempt.stage} by recomposition; its record carries {Deep.show(
					record.invariant
				)}, expected the report's first string verbatim {Deep.show(attempt.failure)}`
			)
		end
	end
	if #calls ~= #expectedCalls then
		table.insert(
			problems,
			`the override was called {#calls} time(s); the recomposition accepts {#expectedCalls} of the {max} attempts, and the override is called only after the real invariants pass`
		)
	else
		for k, want in expectedCalls do
			if not Deep.equal(want, calls[k]) then
				table.insert(
					problems,
					`override call {k} was not the facility of attempt {want.attempt}:\n{Deep.diff(
						want,
						calls[k]
					)}`
				)
			end
		end
	end
	if #problems > 0 then
		Raise.fail(
			`AC-4 / C-5: seed {seed} n = {n}, override failing every attempt:\n{Raise.firstFew(
				problems,
				12
			)}`
		)
	end
end

-- With an override that fails attempt 1 only: a facility, from the first
-- attempt ≥ 2 the recomposition accepts, by value.
function FacilityContract.assertSkipsFirst(generate: Generate, seed: number, n: number)
	local assignment = FacilityContract.ringFor(seed, n)
	local result = generate(assignment, seed, MechanicsTuning, function(facility: any): string?
		return if facility.attempt == 1 then "veto-1" else nil
	end)
	local facility, why = facilityOfResult(result)
	assert(
		facility ~= nil,
		`AC-4: with an override failing attempt 1 only, seed {seed} n = {n}: {why}`
	)
	local want: Facility? = nil
	for i = 2, MechanicsTuning.instance.generator_attempts_max do
		local attempt = FacilityContract.recompose(assignment, seed, i, MechanicsTuning)
		if attempt.stage == "accepted" then
			want = FacilityContract.facilityOf(attempt)
			break
		end
	end
	assert(
		want ~= nil,
		`seed {seed} n = {n}: the recomposition accepts no attempt ≥ 2 within the bound`
	)
	if not Deep.equal(want, facility) then
		Raise.fail(
			`AC-4: with an override failing attempt 1 only, seed {seed} n = {n} must yield the first attempt ≥ 2 that passes, {(
				want :: Facility
			).attempt}; got attempt {tostring(facility.attempt)}:\n{Deep.diff(want, facility)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1's hand-built fixtures.

     THE RING is n = 4 at `Ring.assign` seed 1, written out by hand from
     GEN-003's read-back (`ProcedureContract.FIXTURE_SIGMA[4]`):
       σ: p1→p3, p2→p4, p3→p2, p4→p1;  k(p_i) = i;  λ(p) = k(σ(p)):
       λ(p1) = 3, λ(p2) = 4, λ(p3) = 2, λ(p4) = 1.
     So TURNER(c) = p_c and HELPER(c) = the player whose lens is c:
       helper(1) = p4, helper(2) = p3, helper(3) = p1, helper(4) = p2.
     The controls file asserts this table deep-equals `Ring.assign`.
     Non-adjacent class pairs on the ring 1→3→2→4→1 are {1,2} and {3,4}; every
     fixture's finale is classes 3 and 4, so its four participants are
     p3, p4 (turners) and p1, p2 (helpers): four distinct players.

     THE LAYOUTS are GEN-001's: the "square" (spawnRoom 2; d(2,1) = d(2,3) =
     d(2,5) = 1, d(2,4) = d(2,6) = 2, d(1,4) = 1, d(3,4) = 3, d(4,2) = 2) and
     the "chain" 1-2-3-6-5-4 (spawnRoom 3, the centre: d(3,1) = 2, d(3,4) =
     3, d(1,4) = 5). Par reads `layout.spawnRoom` as a FIELD (C-2), so the
     fixture's value is what it starts from.

     THE PLACEMENTS are hand-built, eight machines (ids 1..8, two per class),
     because par reads only `id`, `room` and `keyClass` (C-2). Slots and tags
     are filler. Each fixture lists (id: class room) beside its schedule.

     THE SCHEDULE in every fixture is tracks {1,2,3,4} and {5,6,7,8} with the
     finale {4, 8}, so the C-2 order is m1 m5 m2 m6 m3 m7 then {m4, m8}.
     W = room_traversal_seconds, P = par_ping_seconds, T = par_turn_seconds.
     --------------------------------------------------------------------- ]]

export type ParFixture = {
	name: string,
	layout: Layout,
	placement: Placement,
	steps: Steps,
	assignment: Assignment,
	expected: number,
}

function FacilityContract.fixtureAssignment(): Assignment
	return {
		players = { "p1", "p2", "p3", "p4" },
		sigma = { p1 = "p3", p2 = "p4", p3 = "p2", p4 = "p1" },
		keyClasses = { p1 = { 1 }, p2 = { 2 }, p3 = { 3 }, p4 = { 4 } },
		lens = { p1 = 3, p2 = 4, p3 = 2, p4 = 1 },
	}
end

-- `{ class, room }` per id, in id order.
local function placementOf(spec: { { number } }): Placement
	local machines: { Machine } = {}
	local perRoom: { [number]: number } = {}
	local perClass: { [number]: number } = {}
	for id, cr in spec do
		local class, room = cr[1], cr[2]
		perRoom[room] = (perRoom[room] or 0) + 1
		perClass[class] = (perClass[class] or 0) + 1
		machines[id] = {
			id = id,
			room = room,
			slot = perRoom[room],
			keyClass = class,
			tag = perClass[class],
			requiredSetting = 1,
		}
	end
	return { machines = machines, stepsPerClass = { 2, 2, 2, 2 } }
end

local FIXTURE_STEPS: Steps = { tracks = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } }, finale = { 4, 8 } }

function FacilityContract.parFixtures(): { ParFixture }
	local t = MechanicsTuning.instance
	local W, P, T = t.room_traversal_seconds, t.par_ping_seconds, t.par_turn_seconds
	local square = LayoutContract.layoutOf(LayoutContract.FIXTURES[2])
	local chain = LayoutContract.layoutOf(LayoutContract.FIXTURES[1])
	assert(square.spawnRoom == 2 and chain.spawnRoom == 3, "the GEN-001 fixtures moved")

	return {
		--[[ 1. Everything in spawn_room (square, room 2). Every walk is 0, so
		     six ordinary steps and the finale each cost P + T.
		       1:c1 r2  2:c2 r2  3:c4 r2  4:c3 r2  5:c1 r2  6:c2 r2  7:c3 r2  8:c4 r2 ]]
		{
			name = "fixture 1: everything in spawn_room",
			layout = square,
			placement = placementOf({
				{ 1, 2 },
				{ 2, 2 },
				{ 4, 2 },
				{ 3, 2 },
				{ 1, 2 },
				{ 2, 2 },
				{ 3, 2 },
				{ 4, 2 },
			}),
			steps = Deep.copy(FIXTURE_STEPS),
			assignment = FacilityContract.fixtureAssignment(),
			expected = 7 * (P + T),
		},
		--[[ 2. The chain, spawnRoom 3, machines at the two ends:
		       1:c1 r1  2:c2 r4  3:c1 r4  4:c3 r1  5:c2 r1  6:c4 r1  7:c3 r4  8:c4 r4
		     Order m1 m5 m2 m6 m3 m7, finale {m4, m8}. Everyone starts at 3.
		       m1 c1 r1: p1 3→1 = 2, p4 3→1 = 2        → 2;  p1 = p4 = 1
		       m5 c2 r1: p2 3→1 = 2, p3 3→1 = 2        → 2;  p2 = p3 = 1
		       m2 c2 r4: p2 1→4 = 5, p3 1→4 = 5        → 5;  p2 = p3 = 4
		       m6 c4 r1: p4 at 1 = 0, p2 4→1 = 5       → 5;  p4 = p2 = 1
		       m3 c1 r4: p1 1→4 = 5, p4 1→4 = 5        → 5;  p1 = p4 = 4
		       m7 c3 r4: p3 at 4 = 0, p1 at 4 = 0      → 0;  p3 = p1 = 4
		       finale  m4 c3 r1: p3 4→1 = 5, p1 4→1 = 5 → 5
		               m8 c4 r4: p4 at 4 = 0, p2 1→4 = 5 → 5;  max = 5
		     24 edges. With the shipped values 24 × 8 + 7 × 13 = 283 s, and
		     283 × 1.5 = 424.5 > 420: a chain the generator must reject. ]]
		{
			name = "fixture 2: the chain layout, machines at both ends",
			layout = chain,
			placement = placementOf({
				{ 1, 1 },
				{ 2, 4 },
				{ 1, 4 },
				{ 3, 1 },
				{ 2, 1 },
				{ 4, 1 },
				{ 3, 4 },
				{ 4, 4 },
			}),
			steps = Deep.copy(FIXTURE_STEPS),
			assignment = FacilityContract.fixtureAssignment(),
			expected = (2 + 2 + 5 + 5 + 5 + 0 + 5) * W + 7 * (P + T),
		},
		--[[ 3. A finale whose two pairs walk different distances (square).
		     The six ordinary steps are all in room 2: zero walks, nobody moves.
		       1:c1 r2  2:c2 r2  3:c4 r2  4:c3 r1  5:c1 r2  6:c2 r2  7:c3 r2  8:c4 r6
		       finale  m4 c3 r1: p3 2→1 = 1, p1 2→1 = 1 → 1
		               m8 c4 r6: p4 2→6 = 2, p2 2→6 = 2 → 2;  max = 2 - only the longer counts.
		     A sequential finale would charge 1 + 2 edges and a second P + T. ]]
		{
			name = "fixture 3: a finale whose two pairs walk different distances",
			layout = square,
			placement = placementOf({
				{ 1, 2 },
				{ 2, 2 },
				{ 4, 2 },
				{ 3, 1 },
				{ 1, 2 },
				{ 2, 2 },
				{ 3, 2 },
				{ 4, 6 },
			}),
			steps = Deep.copy(FIXTURE_STEPS),
			assignment = FacilityContract.fixtureAssignment(),
			expected = 2 * W + 7 * (P + T),
		},
		--[[ 4. A helper and a turner starting in different rooms (square).
		       1:c1 r1  2:c2 r3  3:c3 r4  4:c3 r6  5:c4 r2  6:c1 r2  7:c2 r2  8:c4 r4
		     The tracks here are {1, 3, 6, 4} and {2, 5, 7, 8} (the fixed
		     shape above would put two class-3 steps together):
		       track 1: m1 c1 r1, m3 c3 r4, m6 c1 r2, m4 c3 r6     (c1 c3 c1 c3)
		       track 2: m2 c2 r3, m5 c4 r2, m7 c2 r2, m8 c4 r4     (c2 c4 c2 c4)
		       finale { m4 (c3, r6), m8 (c4, r4) }: d(6, 4) = 2, classes 3 and 4.
		     Order m1 m2 m3 m5 m6 m7, finale {m4, m8}. Everyone starts at 2.
		       m1 c1 r1: p1 2→1 = 1, p4 2→1 = 1               → 1;  p1 = p4 = 1
		       m2 c2 r3: p2 2→3 = 1, p3 2→3 = 1               → 1;  p2 = p3 = 3
		       m3 c3 r4: turner p3 3→4 = 3, helper p1 1→4 = 1 → 3 (a sum would be 4);  p3 = p1 = 4
		       m5 c4 r2: turner p4 1→2 = 1, helper p2 3→2 = 1 → 1 (a sum would be 2);  p4 = p2 = 2
		       m6 c1 r2: turner p1 4→2 = 2, helper p4 at 2 = 0 → 2;  p1 = p4 = 2
		       m7 c2 r2: turner p2 at 2 = 0, helper p3 4→2 = 2 → 2;  p2 = p3 = 2
		       finale  m4 c3 r6: p3 2→6 = 2, p1 2→6 = 2 → 2
		               m8 c4 r4: p4 2→4 = 2, p2 2→4 = 2 → 2;  max = 2
		     12 edges by the parallel rule; 16 if the two walks were summed. ]]
		{
			name = "fixture 4: a helper and a turner starting in different rooms",
			layout = square,
			placement = placementOf({
				{ 1, 1 },
				{ 2, 3 },
				{ 3, 4 },
				{ 3, 6 },
				{ 4, 2 },
				{ 1, 2 },
				{ 2, 2 },
				{ 4, 4 },
			}),
			steps = { tracks = { { 1, 3, 6, 4 }, { 2, 5, 7, 8 } }, finale = { 4, 8 } },
			assignment = FacilityContract.fixtureAssignment(),
			expected = (1 + 1 + 3 + 1 + 2 + 2 + 2) * W + 7 * (P + T),
		},
	}
end

function FacilityContract.fixtureNamed(fragment: string): ParFixture
	for _, f in FacilityContract.parFixtures() do
		if string.find(f.name, fragment, 1, true) ~= nil then
			return f
		end
	end
	error(`no par fixture is named "{fragment}"`)
end

-- AC-1 as one assertion over one fixture and one compute, so the controls
-- file can show it REJECTS the wrong computes the criterion names.
function FacilityContract.assertParFixture(compute: Compute, f: ParFixture)
	local got = compute(f.layout, f.placement, f.steps, f.assignment, MechanicsTuning)
	assert(
		got == f.expected,
		`AC-1: {f.name}: compute returned {tostring(got)}, the hand-worked canonical schedule gives {f.expected}`
	)
end

-- A deep snapshot, for the purity checks.
function FacilityContract.snapshot(value: any): any
	return Deep.copy(value)
end

return FacilityContract
