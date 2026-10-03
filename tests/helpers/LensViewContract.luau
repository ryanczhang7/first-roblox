--!strict
--[[
	VIEW-001 AC-1 through AC-5 written once, as checks over a LENS VIEW
	FUNCTION rather than over `src/server/seats/Projection.luau` by name - the
	`ProjectionContract.luau` arrangement, for the same reason.

	`tests/server/lens_view_test.luau` applies these to the real
	`Projection.lensFor`. `tests/server/lens_view_controls_test.luau` applies
	them to a reference view and to the deliberately wrong views in
	`LensViewStubs.luau`, so that in RED - where `lensFor` does not exist, the
	real file fails at the export check, and not one assertion in it has
	executed against the module - every check here has still been EXECUTED and
	observed to reject the view it exists to catch.

	A `view` here is one plain function, called with a dot exactly as the
	story's Contract writes it:

	    view(assignment, procedure, playerId, position, lineOfSight) -> LensView
	    LensView    = { readings: { LensReading } }   -- ascending machineId
	    LensReading = { machineId: number, setting: number }

	THE ORACLE IS INDEPENDENT (story `## Contract`, "Oracle partition"). The
	five clauses are re-derived here from `Ring.lensOf`, `Machines.positionOf`,
	`Procedure.isDark` and `procedure.committed`, with the range arithmetic
	written in this file - never from `lensFor`. A view that compared against
	the player's own KEY (`keyClasses[p]`, the direction error `Ring.luau`'s
	header names) agrees with itself and disagrees with this. `clausesOf` is
	the readable statement of the five clauses; `evaluate` is the same five
	clauses on the hot path, without a table per machine, and the controls
	file holds the two to the same answer.

	THE SAMPLE IS GENERATED, AND IT EXERCISES EVERY CLAUSE. `Generator.generate`
	deals 200 real facilities at each n in { 4, 5, 6 }; each `ProcedureState`
	comes from the real `Procedure.start` and then has rooms darkened and
	machines committed by a seeded draw (the state is plain data, so this is a
	write to `state.dark` and `state.committed`, which is what a Procedure in
	play would have done). Positions are sampled NEAR machines - uniform over
	the whole map would almost never land in range - and the injected
	`lineOfSight` is a deterministic function of the two points that answers
	both ways. `audit` counts, for every clause, the machines it ALONE excluded,
	and the AC-1 check refuses a sample in which any clause excluded nothing.

	WHAT THE SAMPLE CANNOT REACH, measured in RED: no generated view ever holds
	two readings - machines of one class sit at least 32 studs apart and the
	lens range is 12 - so the ORDER of readings, and the boundary at exactly
	the range, are pinned on hand-built fixtures below, not on the sample.

	THE CONSTANT IS READ FROM `procedure.tuning`. The hand-built fixtures
	override `lens_read_range_studs` (shipped 12 -> 9), so a view that read the
	constant from `MechanicsTuning` directly fails the boundary check.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Generator = require("../../src/server/facility/Generator")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Procedure = require("../../src/server/procedure/Procedure")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/shared/Rng")

local LensViewContract = {}

export type View = any
export type Vec = { x: number, y: number, z: number }
export type LineOfSight = (Vec, Vec) -> boolean
export type Assignment = Ring.Assignment
export type Tuning = typeof(MechanicsTuning)

--[[ ------------------------------------------------------------------------
     The sample. AC-1's numbers verbatim: n in { 4, 5, 6 }, 200 facilities
     per n, 50 positions per facility - every player is evaluated at every
     position, so each player has 50 accepted positions per facility and AC-2
     has every pair of players at the same position.

     A check takes an optional `cases` list. The real module is held to the
     full sample; the controls file, which runs every check over nineteen
     views, hands in `sample(CONTROL_FACILITIES_PER_N)` - the same generator,
     the same seeds, the first facilities of each n - so that it shows each
     check FIRES in seconds rather than minutes.
     --------------------------------------------------------------------- ]]

LensViewContract.COUNTS = { 4, 5, 6 }
LensViewContract.FACILITIES_PER_N = 200
LensViewContract.POSITIONS_PER_FACILITY = 50
LensViewContract.CONTROL_FACILITIES_PER_N = 12

-- `Procedure.start`'s instant and round length. Nothing here reads a clock.
LensViewContract.NOW = 100
LensViewContract.ROUND_SECONDS = 1000

-- Each room is darkened and each machine committed with these odds, from a
-- stream derived from the facility seed. Both are drawn, not fixed, so that
-- the lit and committed clauses are exercised on a mix of states.
local DARK_ODDS = 1 / 3
local COMMITTED_ODDS = 1 / 4
-- Positions land within `POSITION_SPREAD x lens_read_range_studs` of a
-- uniformly chosen machine on each horizontal axis, so about half are in
-- range of it and half are not; `y` is drawn in +-20 and must not matter.
local POSITION_SPREAD = 1.25
local Y_SPREAD = 20

export type Case = {
	n: number,
	seed: number,
	assignment: Assignment,
	state: any,
	positions: { Vec },
	-- machine id -> world position, read ONCE through the real
	-- `Machines.positionOf` when the case is built
	positionOf: { [number]: Vec },
	-- `x|z` -> machine id, for the spy to name the machine a call was about
	machineAt: { [string]: number },
}

--[[
	The injected line of sight: a deterministic function of the two points,
	answering false for about one call in three. A hash of the integer parts
	rather than anything geometric, so that no view can reproduce it from the
	positions alone - it has to CALL the function it was handed.
]]
function LensViewContract.lineOfSight(from: Vec, to: Vec): boolean
	local h = math.floor(from.x * 7 + from.z * 13 + to.x * 3 + to.z * 5 + from.y)
	return h % 3 ~= 0
end

function LensViewContract.playersFor(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = `p{i}`
	end
	return out
end

local function posKey(p: Vec): string
	return `{p.x}|{p.z}`
end

local function buildCase(n: number, seed: number): Case
	local assignment = Ring.assign(LensViewContract.playersFor(n), Rng.fromSeed(seed))
	local result = Generator.generate(assignment, seed, MechanicsTuning)
	if result.kind ~= "facility" then
		Contract.fail(`the sample needs a facility at n = {n}, seed {seed}: {Deep.show(result)}`)
	end
	local facility = (result :: any).facility
	local state = Procedure.start(
		facility,
		LensViewContract.NOW,
		MechanicsTuning,
		seed,
		LensViewContract.ROUND_SECONDS
	)
	local draw = Rng.fromSeed(seed):derive("lens-view-sample")

	for _, room in facility.layout.rooms do
		if draw:nextNumber() < DARK_ODDS then
			state.dark[room.id] = true
		end
	end
	local machines = facility.placement.machines
	local positionOf: { [number]: Vec } = {}
	local machineAt: { [string]: number } = {}
	for _, m in machines do
		if draw:nextNumber() < COMMITTED_ODDS then
			state.committed[m.id] = true
		end
		local p = Machines.positionOf(facility.layout, m, MechanicsTuning)
		positionOf[m.id] = p
		machineAt[posKey(p)] = m.id
	end

	local range = MechanicsTuning.instance.lens_read_range_studs
	local positions: { Vec } = {}
	for _ = 1, LensViewContract.POSITIONS_PER_FACILITY do
		local m = machines[draw:nextInteger(1, #machines)]
		local at = positionOf[m.id]
		table.insert(positions, {
			x = at.x + (draw:nextNumber() * 2 - 1) * POSITION_SPREAD * range,
			y = (draw:nextNumber() * 2 - 1) * Y_SPREAD,
			z = at.z + (draw:nextNumber() * 2 - 1) * POSITION_SPREAD * range,
		})
	end

	return {
		n = n,
		seed = seed,
		assignment = assignment,
		state = state,
		positions = positions,
		positionOf = positionOf,
		machineAt = machineAt,
	}
end

local sampleCache: { [number]: { Case } } = {}

-- The first `perN` facilities of each n (default: the full AC-1 sample),
-- built once per process per size and SHARED: no check may mutate a case.
function LensViewContract.sample(perN: number?): { Case }
	local size = perN or LensViewContract.FACILITIES_PER_N
	local cached = sampleCache[size]
	if cached ~= nil then
		return cached
	end
	local full = sampleCache[LensViewContract.FACILITIES_PER_N]
	local cases: { Case } = {}
	for _, n in LensViewContract.COUNTS do
		for seed = 1, size do
			-- A sub-sample reuses the full sample's cases when it exists, so
			-- the two never disagree on a seed.
			local reused: Case? = nil
			if full ~= nil then
				for _, case in full do
					if case.n == n and case.seed == seed then
						reused = case
						break
					end
				end
			end
			table.insert(cases, reused or buildCase(n, seed))
		end
	end
	sampleCache[size] = cases
	return cases
end

--[[ ------------------------------------------------------------------------
     The oracle: the five clauses, read out independently.
     --------------------------------------------------------------------- ]]

LensViewContract.CLAUSES = { "class", "range", "lit", "committed", "sight" }

export type Clauses = {
	class: boolean,
	range: boolean,
	lit: boolean,
	committed: boolean, -- true when NOT committed, i.e. the clause passes
	sight: boolean,
}

-- Horizontal distance, `y` ignored, inclusive at `range`.
local function withinRange(position: Vec, machinePosition: Vec, range: number): boolean
	local dx = position.x - machinePosition.x
	local dz = position.z - machinePosition.z
	return math.sqrt(dx * dx + dz * dz) <= range
end

-- The readable statement of the five clauses, one machine at a time,
-- resolving everything from the state. Used off the hot path.
function LensViewContract.clausesOf(
	assignment: Assignment,
	state: any,
	playerId: string,
	position: Vec,
	machine: any,
	lineOfSight: LineOfSight
): Clauses
	local machinePosition = Machines.positionOf(state.facility.layout, machine, state.tuning)
	return {
		class = machine.keyClass == Ring.lensOf(assignment, playerId),
		range = withinRange(position, machinePosition, state.tuning.instance.lens_read_range_studs),
		lit = not Procedure.isDark(state, machine.room),
		committed = state.committed[machine.id] ~= true,
		sight = lineOfSight(position, machinePosition) == true,
	}
end

--[[
	The same five clauses on the hot path: the lens class is resolved once per
	player by the caller, the machine position is the case's cached
	`Machines.positionOf`, and nothing is allocated. Returns how many clauses
	failed and, when exactly one did, its name.
]]
local function evaluate(
	case: Case,
	lens: number,
	position: Vec,
	m: any,
	lineOfSight: LineOfSight
): (number, string?)
	local state = case.state
	local mp = case.positionOf[m.id]
	local failed = 0
	local sole: string? = nil
	if m.keyClass ~= lens then
		failed += 1
		sole = "class"
	end
	if not withinRange(position, mp, state.tuning.instance.lens_read_range_studs) then
		failed += 1
		sole = "range"
	end
	if Procedure.isDark(state, m.room) then
		failed += 1
		sole = "lit"
	end
	if state.committed[m.id] == true then
		failed += 1
		sole = "committed"
	end
	if lineOfSight(position, mp) ~= true then
		failed += 1
		sole = "sight"
	end
	return failed, if failed == 1 then sole else nil
end

local function passesAll(c: Clauses): boolean
	return c.class and c.range and c.lit and c.committed and c.sight
end

local function failedClauses(c: Clauses): { string }
	local out: { string } = {}
	for _, name in LensViewContract.CLAUSES do
		if not (c :: any)[name] then
			table.insert(out, name)
		end
	end
	return out
end

-- The expected view: every machine passing all five, ascending by id.
function LensViewContract.expected(
	assignment: Assignment,
	state: any,
	playerId: string,
	position: Vec?,
	lineOfSight: LineOfSight
): { { machineId: number, setting: number } }
	local out: { { machineId: number, setting: number } } = {}
	if position == nil then
		return out
	end
	for _, m in state.facility.placement.machines do
		if
			passesAll(
				LensViewContract.clausesOf(assignment, state, playerId, position, m, lineOfSight)
			)
		then
			table.insert(out, { machineId = m.id, setting = m.requiredSetting })
		end
	end
	table.sort(out, function(a, b)
		return a.machineId < b.machineId
	end)
	return out
end

--[[ ------------------------------------------------------------------------
     Reading a view's answer defensively: a view that returns the wrong shape
     is reported as such, never crashed on, so a missing export is a counted
     failure that names what came back.
     --------------------------------------------------------------------- ]]

local function readingIds(view: any): ({ number }?, string?)
	if typeof(view) ~= "table" then
		return nil, `the view is {typeof(view)} {Deep.show(view)}`
	end
	if typeof(view.readings) ~= "table" then
		return nil, `view.readings is {typeof(view.readings)}`
	end
	local ids: { number } = {}
	for i, r in ipairs(view.readings) do
		if typeof(r) ~= "table" or typeof(r.machineId) ~= "number" then
			return nil, `readings[{i}] is {Deep.show(r)}, not a reading with a machineId`
		end
		table.insert(ids, r.machineId)
	end
	return ids, nil
end

local function machineById(state: any, id: number): any
	for _, m in state.facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     AC-1: the audit. Every (case, player, position) is compared with the
     oracle; every extra reading is attributed to the clause(s) it violates
     and tallied, so a wrong view's failure names WHICH clause it ignored.
     --------------------------------------------------------------------- ]]

export type Audit = {
	cases: number,
	calls: number,
	nonEmptyExpected: number,
	-- clause -> machines that failed this clause ALONE (passed the other four)
	soleExclusions: { [string]: number },
	-- clause -> extra readings that violated it (an extra may count in several)
	extraBy: { [string]: number },
	extra: number,
	missing: number,
	malformed: number,
	violations: { string },
}

local function label(case: Case, playerId: string, i: number): string
	return `n = {case.n}, seed {case.seed}, {playerId} at position {i}`
end

function LensViewContract.audit(view: View, cases: { Case }?): Audit
	local sample = cases or LensViewContract.sample()
	local audit: Audit = {
		cases = #sample,
		calls = 0,
		nonEmptyExpected = 0,
		soleExclusions = {},
		extraBy = {},
		extra = 0,
		missing = 0,
		malformed = 0,
		violations = {},
	}
	for _, name in LensViewContract.CLAUSES do
		audit.soleExclusions[name] = 0
		audit.extraBy[name] = 0
	end
	local los = LensViewContract.lineOfSight
	local expectedIds: { [number]: boolean } = {}
	local seen: { [number]: boolean } = {}

	for _, case in sample do
		local machines = case.state.facility.placement.machines
		for _, playerId in case.assignment.players do
			local lens = Ring.lensOf(case.assignment, playerId)
			for i, position in case.positions do
				audit.calls += 1
				table.clear(expectedIds)
				local expectedCount = 0
				for _, m in machines do
					local failed, sole = evaluate(case, lens, position, m, los)
					if failed == 0 then
						expectedIds[m.id] = true
						expectedCount += 1
					elseif sole ~= nil then
						audit.soleExclusions[sole] += 1
					end
				end
				if expectedCount > 0 then
					audit.nonEmptyExpected += 1
				end

				local result = view(case.assignment, case.state, playerId, position, los)
				local ids, problem = readingIds(result)
				if ids == nil then
					audit.malformed += 1
					table.insert(
						audit.violations,
						`  {label(case, playerId, i)}: {problem :: string}`
					)
					continue
				end
				local problems: { string }? = nil
				table.clear(seen)
				for _, id in ids :: { number } do
					seen[id] = true
					if not expectedIds[id] then
						audit.extra += 1
						problems = problems or {}
						local m = machineById(case.state, id)
						if m == nil then
							table.insert(
								problems :: { string },
								`extra reading of unknown machine {id}`
							)
						else
							local failed = failedClauses(
								LensViewContract.clausesOf(
									case.assignment,
									case.state,
									playerId,
									position,
									m,
									los
								)
							)
							for _, name in failed do
								audit.extraBy[name] += 1
							end
							table.insert(
								problems :: { string },
								`extra reading of machine {id} (class {m.keyClass}), which violates: `
									.. table.concat(failed, "+")
							)
						end
					end
				end
				if expectedCount > 0 then
					for id in expectedIds do
						if not seen[id] then
							audit.missing += 1
							problems = problems or {}
							table.insert(
								problems :: { string },
								`missing reading of machine {id}, which passes all five clauses`
							)
						end
					end
				end
				if problems ~= nil then
					table.insert(
						audit.violations,
						`  {label(case, playerId, i)}: {table.concat(problems :: { string }, "; ")}`
					)
				end
			end
		end
	end
	return audit
end

-- The vacuity floors, per facility in the sample, so that they scale with the
-- sub-sample the controls hand in. Measured in RED against the reference view
-- over the full seeded sample (see the story's handoff: 2526 / 1562 / 2458
-- sole exclusions for lit / committed / sight over 600 facilities, 5392
-- non-empty views) and set at roughly a third of the smallest, so the floors
-- say "exercised", not "exactly this many".
LensViewContract.SOLE_EXCLUSIONS_PER_FACILITY = 1
LensViewContract.NON_EMPTY_PER_FACILITY = 3

function LensViewContract.describeAudit(audit: Audit): string
	local sole: { string } = {}
	local extra: { string } = {}
	for _, name in LensViewContract.CLAUSES do
		table.insert(sole, `{name} {audit.soleExclusions[name]}`)
		table.insert(extra, `{name} {audit.extraBy[name]}`)
	end
	return `{audit.cases} facilities, {audit.calls} calls, {audit.nonEmptyExpected} with a non-empty `
		.. `expected view; machines excluded by one clause alone: [{table.concat(sole, ", ")}]; `
		.. `extra readings by violated clause: [{table.concat(extra, ", ")}]; `
		.. `extra {audit.extra}, missing {audit.missing}, malformed {audit.malformed}`
end

--[[
	AC-1. Over the whole sample the view is exactly the five-clause filter:
	no reading missing, none extra. The sample is first refused if it failed
	to exercise a clause - a view that ignores darkness passes a sample with no
	dark rooms, and that must be the sample's failure, not a green run.
]]
function LensViewContract.viewIsExactlyTheFiveClauseFilter(view: View, cases: { Case }?)
	local audit = LensViewContract.audit(view, cases)
	local soleFloor = LensViewContract.SOLE_EXCLUSIONS_PER_FACILITY * audit.cases
	local nonEmptyFloor = LensViewContract.NON_EMPTY_PER_FACILITY * audit.cases
	local unexercised: { string } = {}
	for _, name in LensViewContract.CLAUSES do
		if audit.soleExclusions[name] < soleFloor then
			table.insert(unexercised, `{name} ({audit.soleExclusions[name]})`)
		end
	end
	if #unexercised > 0 then
		Contract.fail(
			`AC-1's sample is vacuous: clause(s) {table.concat(unexercised, ", ")} excluded fewer `
				.. `than {soleFloor} machines alone - the sample needs changing, not the check. `
				.. LensViewContract.describeAudit(audit)
		)
	end
	if audit.nonEmptyExpected < nonEmptyFloor then
		Contract.fail(
			`AC-1's sample is vacuous: only {audit.nonEmptyExpected} of {audit.calls} calls expect a `
				.. `non-empty view (floor {nonEmptyFloor}); positions are not landing near machines. `
				.. LensViewContract.describeAudit(audit)
		)
	end
	if #audit.violations > 0 then
		Contract.fail(
			`AC-1: the lens view is not the five-clause filter (class = Ring.lensOf, horizontal `
				.. `range <= lens_read_range_studs, lit, not committed, line of sight) in `
				.. `{#audit.violations} of {audit.calls} calls. {LensViewContract.describeAudit(
					audit
				)}\n`
				.. Contract.firstFew(audit.violations, 6)
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1, the call-order clause (Contract; D-4): `lineOfSight` is called
     only for machines that already pass class, range, lit and not-committed,
     at most once per machine per call, with the accepted position as `from`
     and the machine's `Machines.positionOf` as `to`.
     --------------------------------------------------------------------- ]]

export type SpyRecord = { calls: { { from: Vec, to: Vec } } }

-- The deterministic line of sight, wrapped: every call is recorded.
function LensViewContract.spy(): (LineOfSight, SpyRecord)
	local record: SpyRecord = { calls = {} }
	local function los(from: Vec, to: Vec): boolean
		table.insert(record.calls, { from = from, to = to })
		return LensViewContract.lineOfSight(from, to)
	end
	return los, record
end

local function sameVec(a: any, b: Vec): boolean
	return typeof(a) == "table" and a.x == b.x and a.y == b.y and a.z == b.z
end

local function alwaysSeen(_from: Vec, _to: Vec): boolean
	return true
end
LensViewContract.alwaysSeen = alwaysSeen

function LensViewContract.lineOfSightIsConsultedLastAndAtMostOnce(view: View, cases: { Case }?)
	local sample = cases or LensViewContract.sample()
	local violations: { string } = {}
	local calls, consulted, eligibleTotal = 0, 0, 0
	local eligible: { [number]: boolean } = {}
	local timesFor: { [number]: number } = {}

	for _, case in sample do
		for _, playerId in case.assignment.players do
			local lens = Ring.lensOf(case.assignment, playerId)
			for i, position in case.positions do
				calls += 1
				-- Which machines pass the FOUR cheaper clauses, by id: the
				-- oracle with sight always granted.
				table.clear(eligible)
				for _, m in case.state.facility.placement.machines do
					if evaluate(case, lens, position, m, alwaysSeen) == 0 then
						eligible[m.id] = true
						eligibleTotal += 1
					end
				end

				local spyLos, record = LensViewContract.spy()
				view(case.assignment, case.state, playerId, position, spyLos)
				consulted += #record.calls
				if #record.calls == 0 then
					continue
				end
				local problems: { string } = {}
				table.clear(timesFor)
				for _, call in record.calls do
					if not sameVec(call.from, position) then
						table.insert(
							problems,
							`lineOfSight called with from = {Deep.show(call.from)}, not the accepted `
								.. `position {Deep.show(position)}`
						)
					end
					local id = if typeof(call.to) == "table"
						then case.machineAt[posKey(call.to)]
						else nil
					if id == nil then
						table.insert(
							problems,
							`lineOfSight called with to = {Deep.show(call.to)}, which is no machine's `
								.. `Machines.positionOf`
						)
					else
						timesFor[id] = (timesFor[id] or 0) + 1
						if not eligible[id] then
							local four: { string } = {}
							for _, name in
								failedClauses(
									LensViewContract.clausesOf(
										case.assignment,
										case.state,
										playerId,
										position,
										machineById(case.state, id),
										alwaysSeen
									)
								)
							do
								table.insert(four, name)
							end
							table.insert(
								problems,
								`lineOfSight consulted for machine {id}, which already fails: `
									.. table.concat(four, "+")
							)
						end
					end
				end
				for id, times in timesFor do
					if times > 1 then
						table.insert(
							problems,
							`lineOfSight consulted {times} times for machine {id}`
						)
					end
				end
				if #problems > 0 then
					table.insert(
						violations,
						`  {label(case, playerId, i)}: {table.concat(problems, "; ")}`
					)
				end
			end
		end
	end

	local floor = LensViewContract.NON_EMPTY_PER_FACILITY * #sample
	if eligibleTotal < floor then
		Contract.fail(
			`AC-1's call-order sample is vacuous: only {eligibleTotal} machines passed the four `
				.. `cheaper clauses across {calls} calls (floor {floor})`
		)
	end
	if consulted == 0 then
		table.insert(
			violations,
			`  lineOfSight was never consulted across {calls} calls with {eligibleTotal} eligible `
				.. `machines - a view that never asks cannot be gating on sight`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-1: lineOfSight is not consulted last and at most once per machine - it must be `
				.. `called only for machines that pass class, range, lit and not-committed, with the `
				.. `accepted position and the machine's position - in {#violations} of {calls} calls `
				.. `({consulted} calls to lineOfSight, {eligibleTotal} eligible machines):\n`
				.. Contract.firstFew(violations, 6)
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2: two distinct players at the same position share no machine. Read
     off the views alone - no oracle - because the criterion is about the
     views disagreeing with each other, whatever either one says.
     --------------------------------------------------------------------- ]]

function LensViewContract.distinctPlayersShareNoMachine(view: View, cases: { Case }?)
	local sample = cases or LensViewContract.sample()
	local violations: { string } = {}
	local pairs_ = 0
	local nonEmpty = 0
	local los = LensViewContract.lineOfSight
	local holders: { [number]: string } = {}

	for _, case in sample do
		local n = #case.assignment.players
		for i, position in case.positions do
			table.clear(holders)
			for _, playerId in case.assignment.players do
				local ids = readingIds(view(case.assignment, case.state, playerId, position, los))
				if ids == nil then
					continue
				end
				if #ids > 0 then
					nonEmpty += 1
				end
				for _, id in ids :: { number } do
					local other = holders[id]
					if other ~= nil and other ~= playerId then
						table.insert(
							violations,
							`  n = {case.n}, seed {case.seed}, position {i}: machine {id} is read by both `
								.. `{other} and {playerId}`
						)
					end
					holders[id] = playerId
				end
			end
			pairs_ += n * (n - 1) / 2
		end
	end

	local floor = LensViewContract.NON_EMPTY_PER_FACILITY * #sample
	if nonEmpty < floor then
		Contract.fail(
			`AC-2's sample is vacuous: only {nonEmpty} non-empty views across {pairs_} player pairs `
				.. `(floor {floor})`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2: two distinct players' lens views from the same position share a machine in `
				.. `{#violations} case(s) over {pairs_} player pairs:\n{Contract.firstFew(
					violations,
					6
				)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3: no accepted position -> exactly `{ readings = {} }`, and the line
     of sight is never asked.
     --------------------------------------------------------------------- ]]

-- Every player of the first facilities at each n: enough to cover lit and
-- dark rooms and committed machines, cheap enough to be exact.
LensViewContract.NO_POSITION_FACILITIES_PER_N = 8

function LensViewContract.noPositionIsEmptyAndConsultsNothing(view: View)
	local violations: { string } = {}
	local count = 0
	for _, case in LensViewContract.sample(LensViewContract.NO_POSITION_FACILITIES_PER_N) do
		for _, playerId in case.assignment.players do
			count += 1
			local spyLos, record = LensViewContract.spy()
			local result = view(case.assignment, case.state, playerId, nil, spyLos)
			local problems: { string } = {}
			local diff = Deep.diff({ readings = {} }, result)
			if diff ~= "" then
				table.insert(
					problems,
					`returned {Deep.show(result)}, not exactly \{ readings = \{} }`
				)
			end
			if #record.calls > 0 then
				table.insert(problems, `called lineOfSight {#record.calls} time(s)`)
			end
			if #problems > 0 then
				table.insert(
					violations,
					`  n = {case.n}, seed {case.seed}, {playerId} with no position: `
						.. table.concat(problems, "; ")
				)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3: a player with no accepted position does not get exactly \{ readings = \{} } with `
				.. `lineOfSight never called, in {#violations} of {count} cases:\n`
				.. Contract.firstFew(violations, 6)
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4: the shape. A reading has exactly `machineId` and `setting`; the
     view has exactly `readings`; readings ascend by machineId; the setting
     is the machine's `requiredSetting`; and the view is a fresh table on
     every call (Contract). Checked over the sample, because a shape defect
     that appears only in a non-empty view is invisible on an empty one - and
     then on the crowded fixture, because the sample never has two readings.
     --------------------------------------------------------------------- ]]

local function keysOf(t: any): { string }
	local keys: { string } = {}
	for k in pairs(t :: { [any]: any }) do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

-- The shape problems of one view, against the state its machines live in.
local function shapeProblems(state: any, result: any, problems: { string }): boolean
	if typeof(result) ~= "table" then
		table.insert(problems, `the view is {typeof(result)} {Deep.show(result)}`)
		return false
	end
	local viewKeys = table.concat(keysOf(result), ",")
	if viewKeys ~= "readings" then
		table.insert(problems, `the view's keys are [{viewKeys}], not exactly [readings]`)
	end
	if typeof(result.readings) ~= "table" then
		table.insert(problems, `readings is {typeof(result.readings)}`)
		return false
	end
	local previous: number? = nil
	for k, r in ipairs(result.readings) do
		if typeof(r) ~= "table" then
			table.insert(problems, `readings[{k}] is {Deep.show(r)}`)
			continue
		end
		local rk = table.concat(keysOf(r), ",")
		if rk ~= "machineId,setting" then
			table.insert(
				problems,
				`readings[{k}] has keys [{rk}], not exactly [machineId, setting]`
			)
		end
		local m = if typeof(r.machineId) == "number" then machineById(state, r.machineId) else nil
		if m == nil then
			table.insert(problems, `readings[{k}].machineId {Deep.show(r.machineId)} is no machine`)
		elseif r.setting ~= m.requiredSetting then
			table.insert(
				problems,
				`readings[{k}].setting is {Deep.show(r.setting)}, machine {m.id}'s requiredSetting `
					.. `is {m.requiredSetting}`
			)
		end
		if previous ~= nil and typeof(r.machineId) == "number" and r.machineId <= previous then
			table.insert(
				problems,
				`readings[{k}].machineId {r.machineId} does not ascend past {previous}`
			)
		end
		if typeof(r.machineId) == "number" then
			previous = r.machineId
		end
	end
	return #result.readings > 0
end

-- The freshness pin calls the view a second time; done on every 4th position
-- rather than every one, since the answer does not change with the position.
LensViewContract.FRESHNESS_STRIDE = 4

function LensViewContract.readingsHaveExactlyTheContractShape(view: View, cases: { Case }?)
	local sample = cases or LensViewContract.sample()
	local violations: { string } = {}
	local calls, nonEmpty = 0, 0
	local los = LensViewContract.lineOfSight

	for _, case in sample do
		for _, playerId in case.assignment.players do
			for i, position in case.positions do
				calls += 1
				local result = view(case.assignment, case.state, playerId, position, los)
				local problems: { string } = {}
				if shapeProblems(case.state, result, problems) then
					nonEmpty += 1
				end
				if i % LensViewContract.FRESHNESS_STRIDE == 1 and typeof(result) == "table" then
					-- A fresh table on every call: the same arguments again
					-- must not hand back the same table or the same list.
					local again = view(case.assignment, case.state, playerId, position, los)
					if again == result then
						table.insert(problems, "the same view table was returned twice")
					elseif typeof(again) == "table" and again.readings == result.readings then
						table.insert(problems, "the same readings list was returned twice")
					end
				end
				if #problems > 0 then
					table.insert(
						violations,
						`  {label(case, playerId, i)}: {table.concat(problems, "; ")}`
					)
				end
			end
		end
	end

	local floor = LensViewContract.NON_EMPTY_PER_FACILITY * #sample
	if nonEmpty < floor then
		Contract.fail(
			`AC-4's sample is vacuous: only {nonEmpty} of {calls} views were non-empty (floor `
				.. `{floor}), so the reading shape was barely inspected`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-4: a reading is not exactly \{ machineId, setting } with the machine's requiredSetting, `
				.. `or the view is not exactly \{ readings } ascending by machineId and fresh per call, `
				.. `in {#violations} of {calls} calls:\n{Contract.firstFew(violations, 6)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The hand-built fixtures.

     BOTH SHARE one ring - p1 -> p2 -> p3 -> p4 -> p1, class i at seat i, so
     p1's lens is class 2 - and one tuning: the shipped one with
     `lens_read_range_studs` 12 -> 9, so a view that reads the constant from
     `MechanicsTuning` rather than from `procedure.tuning` reads at the wrong
     boundary here (P-1).

     THE BOUNDARY FIXTURE (D-3, AC-5): four rooms on a 2 x 2 block at the
     shipped pitch, two machines per room, so that from any machine every
     other machine is at least 32 studs away and the view at a stand holds
     at most that one reading.

     THE CROWDED FIXTURE (AC-4's order): one room at a pitch of 24, so its
     four quadrant slots are 6 studs off centre on each axis and all four
     are 6 x sqrt(2) = 8.49 studs from the room's centre - inside the 9-stud
     range. Every machine is class 2 and one is committed, so p1 at the
     centre reads exactly three, and their ORDER is observable.
     --------------------------------------------------------------------- ]]

LensViewContract.FIXTURE_LENS_RANGE = 9
LensViewContract.CROWDED_PITCH = 24

export type Fixture = { assignment: Assignment, state: any, tuning: Tuning }

local function tuningWith(overrides: { [string]: any }): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for key, value in pairs(overrides) do
		fake.instance[key] = value
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

function LensViewContract.fixtureTuning(): Tuning
	return tuningWith({ lens_read_range_studs = LensViewContract.FIXTURE_LENS_RANGE })
end

function LensViewContract.crowdedTuning(): Tuning
	return tuningWith({
		lens_read_range_studs = LensViewContract.FIXTURE_LENS_RANGE,
		room_pitch_studs = LensViewContract.CROWDED_PITCH,
	})
end

function LensViewContract.fixtureAssignment(): Assignment
	return {
		players = { "p1", "p2", "p3", "p4" },
		sigma = { p1 = "p2", p2 = "p3", p3 = "p4", p4 = "p1" },
		keyClasses = { p1 = { 1 }, p2 = { 2 }, p3 = { 3 }, p4 = { 4 } },
		lens = { p1 = 2, p2 = 3, p3 = 4, p4 = 1 },
	}
end

-- Machine ids by role: room 1 holds classes 1 and 2, room 2 classes 3 and 4,
-- room 3 classes 1 and 2 again, room 4 classes 3 and 4 again.
LensViewContract.FIXTURE_P1_LENS_MACHINE = 2 -- class 2, room 1, slot 2
LensViewContract.FIXTURE_P1_LENS_MACHINE_SETTING = 3
LensViewContract.FIXTURE_P1_LENS_ROOM = 1
LensViewContract.FIXTURE_P1_OTHER_LENS_MACHINE = 6 -- class 2, room 3, slot 3
LensViewContract.FIXTURE_P1_OTHER_LENS_MACHINE_SETTING = 1

local FIXTURE_MACHINES = {
	{ id = 1, room = 1, slot = 1, keyClass = 1, tag = 1, requiredSetting = 1 },
	{ id = 2, room = 1, slot = 2, keyClass = 2, tag = 1, requiredSetting = 3 },
	{ id = 3, room = 2, slot = 1, keyClass = 3, tag = 1, requiredSetting = 2 },
	{ id = 4, room = 2, slot = 2, keyClass = 4, tag = 1, requiredSetting = 4 },
	{ id = 5, room = 3, slot = 1, keyClass = 1, tag = 2, requiredSetting = 2 },
	{ id = 6, room = 3, slot = 3, keyClass = 2, tag = 2, requiredSetting = 1 },
	{ id = 7, room = 4, slot = 1, keyClass = 3, tag = 2, requiredSetting = 4 },
	{ id = 8, room = 4, slot = 4, keyClass = 4, tag = 2, requiredSetting = 2 },
}

function LensViewContract.fixtureFacility(): any
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 1, row = 2 },
				{ id = 4, column = 2, row = 2 },
			},
			doors = { { a = 1, b = 2 }, { a = 1, b = 3 }, { a = 2, b = 4 }, { a = 3, b = 4 } },
			spawnRoom = 1,
		},
		placement = {
			machines = Deep.copy(FIXTURE_MACHINES),
			stepsPerClass = { [1] = 2, [2] = 2, [3] = 2, [4] = 2 },
		},
		steps = { tracks = { { 1, 4, 5, 8 }, { 3, 2, 7, 6 } }, finale = { 8, 6 } },
		spawnRoom = 1,
		par = 60,
		attempt = 1,
	}
end

-- The crowded room: ids deliberately NOT in slot order (slot 4 is id 1), so
-- that "ascending by machineId" and "in slot order" are different answers.
-- Settings differ per machine so a swapped setting shows by value.
LensViewContract.CROWDED_COMMITTED = 3
LensViewContract.CROWDED_EXPECTED = {
	{ machineId = 1, setting = 4 },
	{ machineId = 2, setting = 1 },
	{ machineId = 4, setting = 2 },
}

-- Listed OUT of id order as well (3, 1, 4, 2): `Machines.generate` happens to
-- put `machines[i].id == i`, and a view that walked the placement in list
-- order without sorting would be ascending by accident on every generated
-- facility. Here it is not.
local CROWDED_MACHINES = {
	{ id = 3, room = 1, slot = 1, keyClass = 2, tag = 3, requiredSetting = 3 },
	{ id = 1, room = 1, slot = 4, keyClass = 2, tag = 1, requiredSetting = 4 },
	{ id = 4, room = 1, slot = 3, keyClass = 2, tag = 4, requiredSetting = 2 },
	{ id = 2, room = 1, slot = 2, keyClass = 2, tag = 2, requiredSetting = 1 },
}

function LensViewContract.crowdedFacility(): any
	return {
		layout = { rooms = { { id = 1, column = 1, row = 1 } }, doors = {}, spawnRoom = 1 },
		placement = { machines = Deep.copy(CROWDED_MACHINES), stepsPerClass = { [2] = 4 } },
		steps = { tracks = { { 1, 2 }, { 3, 4 } }, finale = { 2, 4 } },
		spawnRoom = 1,
		par = 30,
		attempt = 1,
	}
end

-- A fresh fixture every call: AC-5 writes `dark` on one and must not see it
-- on the next.
local function start(facility: any, tuning: Tuning): Fixture
	local state = Procedure.start(
		facility,
		LensViewContract.NOW,
		tuning,
		LensViewContract.NOW,
		LensViewContract.ROUND_SECONDS
	)
	return { assignment = LensViewContract.fixtureAssignment(), state = state, tuning = tuning }
end

function LensViewContract.fixture(): Fixture
	return start(LensViewContract.fixtureFacility(), LensViewContract.fixtureTuning())
end

function LensViewContract.crowded(): Fixture
	local f = start(LensViewContract.crowdedFacility(), LensViewContract.crowdedTuning())
	f.state.committed[LensViewContract.CROWDED_COMMITTED] = true
	return f
end

-- The fixture machine's world position through the real `Machines.positionOf`,
-- plus an offset. Reach tests never hardcode geometry.
function LensViewContract.fixtureAt(f: Fixture, id: number, dx: number, dy: number, dz: number): Vec
	local m = machineById(f.state, id)
	local p = Machines.positionOf(f.state.facility.layout, m, f.tuning)
	return { x = p.x + dx, y = p.y + dy, z = p.z + dz }
end

--[[
	AC-1's boundary (Contract, D-3): the range is inclusive at exactly
	`lens_read_range_studs` horizontally, read from `procedure.tuning`, and `y`
	is ignored. Six stands by p1 about machine 2 (p1's lens class, lit, not
	committed, always in sight):

	  at half the range            -> read
	  at exactly the range         -> read      (`<` instead of `<=` fails here)
	  at exactly the range, y+500  -> read      (a 3-D distance fails here)
	  just past the range          -> not read
	  exactly the range along z    -> read
	  exactly the range, -x, y-500 -> read

	Each expectation is the EXACT view, so a second machine wandering in would
	show too.
]]
function LensViewContract.rangeIsInclusiveAtTheBoundaryAndIgnoresY(view: View)
	local f = LensViewContract.fixture()
	local id = LensViewContract.FIXTURE_P1_LENS_MACHINE
	local range = f.tuning.instance.lens_read_range_studs
	if range == MechanicsTuning.instance.lens_read_range_studs then
		Contract.fail(
			`the fixture's lens_read_range_studs ({range}) equals the shipped value, so a view `
				.. `reading MechanicsTuning directly could not be told apart`
		)
	end
	local reading = {
		{ machineId = id, setting = LensViewContract.FIXTURE_P1_LENS_MACHINE_SETTING },
	}
	local stands = {
		{ what = `half the range ({range / 2} studs)`, at = { range / 2, 0, 0 }, want = reading },
		{ what = `exactly the range ({range} studs)`, at = { range, 0, 0 }, want = reading },
		{
			what = `exactly the range ({range} studs) with y + 500`,
			at = { range, 500, 0 },
			want = reading,
		},
		{
			what = `just past the range ({range} + 0.001 studs)`,
			at = { range + 0.001, 0, 0 },
			want = {},
		},
		{ what = "exactly the range along z", at = { 0, 0, range }, want = reading },
		{ what = "exactly the range along -x, y - 500", at = { -range, -500, 0 }, want = reading },
	}
	local violations: { string } = {}
	for _, stand in stands do
		local position = LensViewContract.fixtureAt(f, id, stand.at[1], stand.at[2], stand.at[3])
		local result = view(f.assignment, f.state, "p1", position, alwaysSeen)
		local diff = Deep.diff({ readings = stand.want }, result)
		if diff ~= "" then
			table.insert(
				violations,
				`  p1 standing {stand.what} from machine {id}: expected `
					.. `{Deep.show({ readings = stand.want })}, got {Deep.show(result)}`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-1: the range is not inclusive at exactly lens_read_range_studs ({range}, from `
				.. `procedure.tuning) horizontally with y ignored, in {#violations} of {#stands} stands:\n`
				.. table.concat(violations, "\n")
		)
	end
end

--[[
	AC-4, many readings: p1 at the centre of the crowded room reads exactly
	the three uncommitted class-2 machines, ascending by machineId with each
	machine's own setting - the exact list, so an order, a setting or an
	extra field is all one diff.
]]
function LensViewContract.manyReadingsAscendByMachineId(view: View)
	local f = LensViewContract.crowded()
	local room = f.state.facility.layout.rooms[1]
	local pitch = f.tuning.instance.room_pitch_studs
	local centre = { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
	-- The fixture's own premise, checked rather than assumed: every machine is
	-- within range of the centre through the real `Machines.positionOf`.
	for _, m in f.state.facility.placement.machines do
		local p = Machines.positionOf(f.state.facility.layout, m, f.tuning)
		if not withinRange(centre, p, f.tuning.instance.lens_read_range_studs) then
			Contract.fail(
				`the crowded fixture's machine {m.id} is out of range of the room centre: `
					.. `{Deep.show(p)} vs {Deep.show(centre)} at range `
					.. f.tuning.instance.lens_read_range_studs
			)
		end
	end
	local want = { readings = Deep.copy(LensViewContract.CROWDED_EXPECTED) }
	local result = view(f.assignment, f.state, "p1", centre, alwaysSeen)
	local diff = Deep.diff(want, result)
	if diff ~= "" then
		Contract.fail(
			`AC-4: p1 at the centre of a room holding four class-2 machines (machine `
				.. `{LensViewContract.CROWDED_COMMITTED} committed) does not read exactly `
				.. `{Deep.show(want)}, ascending by machineId with each machine's requiredSetting; `
				.. `got {Deep.show(result)}:\n{diff}`
		)
	end
end

--[[
	AC-5. p1, standing at machine 2 (p1's lens class) in lit room 1, reads it;
	after room 1 goes dark - `Procedure.isDark` answers true - the next view
	no longer has that reading, and p1's reading of machine 6 in still-lit
	room 3 is unaffected.
]]
function LensViewContract.darkRoomRemovesTheReading(view: View)
	local id = LensViewContract.FIXTURE_P1_LENS_MACHINE
	local room = LensViewContract.FIXTURE_P1_LENS_ROOM
	local setting = LensViewContract.FIXTURE_P1_LENS_MACHINE_SETTING
	local violations: { string } = {}

	local lit = LensViewContract.fixture()
	local at = LensViewContract.fixtureAt(lit, id, 0, 0, 0)
	if Procedure.isDark(lit.state, room) then
		Contract.fail(`the fixture's room {room} is dark before anything darkened it`)
	end
	local before = view(lit.assignment, lit.state, "p1", at, alwaysSeen)
	local wantBefore = { readings = { { machineId = id, setting = setting } } }
	local diff = Deep.diff(wantBefore, before)
	if diff ~= "" then
		table.insert(
			violations,
			`  p1 at machine {id} in lit room {room}: expected {Deep.show(wantBefore)}, got `
				.. Deep.show(before)
		)
	end

	local dark = LensViewContract.fixture()
	dark.state.dark[room] = true
	if not Procedure.isDark(dark.state, room) then
		Contract.fail(
			`Procedure.isDark does not report room {room} dark after state.dark[{room}] = true`
		)
	end
	local after = view(dark.assignment, dark.state, "p1", at, alwaysSeen)
	diff = Deep.diff({ readings = {} }, after)
	if diff ~= "" then
		table.insert(
			violations,
			`  p1 at machine {id} after room {room} went dark: expected \{ readings = \{} }, got `
				.. Deep.show(after)
		)
	end

	-- The other room is untouched: p1's lens machine in room 3 still reads.
	local other = LensViewContract.FIXTURE_P1_OTHER_LENS_MACHINE
	local atOther = LensViewContract.fixtureAt(dark, other, 0, 0, 0)
	local elsewhere = view(dark.assignment, dark.state, "p1", atOther, alwaysSeen)
	local wantElsewhere = {
		readings = {
			{
				machineId = other,
				setting = LensViewContract.FIXTURE_P1_OTHER_LENS_MACHINE_SETTING,
			},
		},
	}
	diff = Deep.diff(wantElsewhere, elsewhere)
	if diff ~= "" then
		table.insert(
			violations,
			`  p1 at machine {other} in still-lit room 3 while room {room} is dark: expected `
				.. `{Deep.show(wantElsewhere)}, got {Deep.show(elsewhere)}`
		)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-5: a reading in a room that went dark (Procedure.isDark) is not gone from the next `
				.. `view, or a lit room's reading went with it, in {#violations} case(s):\n`
				.. table.concat(violations, "\n")
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-6's matcher: every line of `text` on which `word` appears as a WHOLE
     WORD - frontier-anchored on both sides, so `pairingsX`, `subfragments`
     and `my_pairings` are not hits and `pairings`, `(pairings)` and
     `pairings.` are. Over the RAW text, comments included: the criterion is
     about what the header SAYS. The controls file probes the needle both ways.
     --------------------------------------------------------------------- ]]

function LensViewContract.wholeWordHits(text: string, word: string): { number }
	local pattern = `%f[%w_]{word}%f[^%w_]`
	local lines: { number } = {}
	local lineNumber = 0
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		lineNumber += 1
		if string.find(line, pattern) ~= nil then
			table.insert(lines, lineNumber)
		end
	end
	return lines
end

return LensViewContract
