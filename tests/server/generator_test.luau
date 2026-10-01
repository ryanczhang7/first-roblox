--!strict
--[[
	GEN-004: every generated facility can be finished inside the clock by a
	naive group. AC-2 through AC-6, applied to the real
	`src/server/facility/Generator.luau` (and, for AC-6's par clause, the real
	`Par.luau`).

	Both modules are required through a `pcall` at the top and re-checked
	inside every test, as `steps_test.luau` does. In RED neither exists, and a
	bare top-level `require` would make this whole file a single LOAD FAIL.
	Per-criterion failures say which behaviours are missing. It is not a skip:
	every test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS, THE RECOMPOSITION AND THE SWEEP LIVE IN
	`tests/helpers/FacilityContract.luau` and are exercised against
	deliberately wrong generators in `tests/server/facility_controls_test.luau`,
	which is where each check is OBSERVED to reject the defect it exists to
	catch and to accept a reference - which matters in RED, because the pcall
	above means not one assertion in THIS file executes until GREEN writes the
	modules.

	THE ORACLE PARTITION (story `## Contract`):
	  * AC-2, AC-3, AC-4 and AC-6 are MECHANICAL: the facility is compared BY
	    VALUE with an independent recomposition of its own attempt from
	    `Rng.fromSeed(seed):derive("instance"):derive("attempt-" .. i)` on the
	    C-4 sub-streams; every earlier attempt is recomposed and must fail;
	    failure records are compared verbatim with the recomposition's first
	    report string; AC-3's wrapper and spy are C-7's, through
	    `stagesOverride`.
	  * AC-5 is SETTLED for the invariants - `Layout.check`, `Machines.check`
	    and `Steps.check` re-run on the returned facility, par RECOMPUTED by the
	    test's own §6.3 (own BFS, own helper/turner lookup), `INV_traversal`
	    checked on that number, and `facility.par` required to equal it - and a
	    MEASUREMENT for the rate, printed in C-8's exact line and asserted only
	    against the bound. Below 0.25 the test still passes; the Lead PO reads
	    the number (AC-5).

	WHAT THIS FILE DOES NOT PIN: which seeds are rejected (C-9 is a baseline,
	not an oracle), the free text after `INV_traversal:par `, the order in
	which a facility's keys are written, or whether the facility is frozen.
]]

local Contract = require("../helpers/FacilityContract")
local Deep = require("../helpers/Deep")
local Raise = require("../helpers/Contract")

local TUNING = Contract.TUNING

local loadedGenerator, generatorResult = pcall(require, "../../src/server/facility/Generator")
local loadedPar, parResult = pcall(require, "../../src/server/facility/Par")

local function Generator(): any
	assert(
		loadedGenerator,
		`src/server/facility/Generator.luau did not load: {tostring(generatorResult)}`
	)
	return generatorResult
end

local function Par(): any
	assert(loadedPar, `src/server/facility/Par.luau did not load: {tostring(parResult)}`)
	return parResult
end

local function generate(): Contract.Generate
	return Generator().generate
end

local function describeN(n: number): string
	return `n = {n}`
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Generator exports generate as a plain field function and the module table is frozen"] = function()
		local G = Generator()
		assert(typeof(G) == "table", `Generator is {typeof(G)}`)
		assert(typeof(G.generate) == "function", `Generator.generate is {typeof(G.generate)}`)
		assert(table.isfrozen(G), "the Generator module table is not frozen (C-1)")
	end,

	["Contract / C-5: every swept result at n = 4, 5, 6 carries exactly { kind, facility } or exactly { kind, failures }, never both"] = function()
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			for _, s in Contract.sweep(generate(), n) do
				local problem = Contract.resultShapeProblem(s.result)
				if problem ~= nil then
					table.insert(problems, `{describeN(n)} seed {s.seed}: {problem}`)
				end
				if #problems > 10 then
					break
				end
			end
		end
		if #problems > 0 then
			Raise.fail(`C-5: result shape:\n{Raise.firstFew(problems, 10)}`)
		end
	end,

	["Contract: generate never mutates the assignment or the tuning it is handed"] = function()
		local assignment = Contract.ringFor(11, 5)
		local before = Contract.snapshot({ assignment, TUNING })
		generate()(assignment, 11, TUNING)
		generate()(assignment, 11, TUNING, function(_facility: any): string?
			return "veto"
		end)
		local after = { assignment, TUNING }
		assert(
			Deep.equal(before, after),
			`generate mutated an argument:\n{Deep.diff(before, after)}`
		)
	end,

	--[[ AC-2 ]]

	["AC-2: over seeds 1..1000 at n = 4, 5, 6, the facility deep-equals the independent recomposition of its own attempt from attempt-i's sub-streams, and every earlier attempt, recomposed, fails an invariant"] = function()
		for _, n in Contract.CLASS_COUNTS do
			Contract.assertRecomposition(generate(), n)
		end
	end,

	["AC-2: the same seed and ring always give the same facility - twice on one ring, and on a second ring of equal content - at n = 4, 5, 6 and seeds 1, 2, 500, 1000"] = function()
		local g = generate()
		for _, n in Contract.CLASS_COUNTS do
			for _, seed in { 1, 2, 500, 1000 } do
				local ring = Contract.ringFor(seed, n)
				local a = g(ring, seed, TUNING)
				local b = g(ring, seed, TUNING)
				local c = g(Contract.ringFor(seed, n), seed, TUNING)
				assert(
					Deep.equal(a, b),
					`{describeN(n)} seed {seed}: two runs on one ring differ:\n{Deep.diff(a, b)}`
				)
				assert(
					Deep.equal(a, c),
					`{describeN(n)} seed {seed}: a second ring of equal content gives a different result:\n{Deep.diff(
						a,
						c
					)}`
				)
			end
		end
	end,

	["AC-2: some seed in 1..1000 is accepted at attempt 2 or later (found by search, not hard-coded), its facility records that attempt, and its attempt 1 fails INV_traversal by recomposition"] = function()
		local found: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			local seed = Contract.seedAcceptedLater(generate(), n)
			if seed ~= nil then
				local facility =
					Contract.facilityOfResult(Contract.sweep(generate(), n)[seed].result)
				local first = Contract.recompose(Contract.ringFor(seed, n), seed, 1, TUNING)
				assert(
					first.stage ~= "accepted",
					`{describeN(n)} seed {seed}: the facility records attempt {facility.attempt} but attempt 1 passes every invariant by recomposition`
				)
				table.insert(
					found,
					`{describeN(n)} seed {seed} attempt {facility.attempt} ({first.stage})`
				)
			end
		end
		print(`        [measured] seeds accepted after attempt 1: {table.concat(found, "; ")}`)
		assert(
			#found > 0,
			"AC-2: no seed in 1..1000 at any n was accepted after attempt 1, so the resample loop was never observed to resample (C-9 predicts 7 to 10 per n)"
		)
	end,

	["AC-2 / C-3: with a MechanicsTuning fake whose schedule_slack is huge, every attempt fails INV_traversal: kind failed, exactly generator_attempts_max records in attempt order, each headed `INV_traversal:par `"] = function()
		local fake = Contract.tuningWith({ schedule_slack = 1e9 })
		local max = fake.instance.generator_attempts_max
		-- A seed whose attempts are all structurally valid, so that nothing
		-- but traversal can reject one. Searched, not hard-coded.
		local chosen: number? = nil
		for seed = 1, Contract.SWEEP_SEEDS do
			local ring = Contract.ringFor(seed, 4)
			local allStructural = true
			for i = 1, max do
				local stage = Contract.recompose(ring, seed, i, fake).stage
				if stage ~= "traversal" and stage ~= "accepted" then
					allStructural = false
					break
				end
			end
			if allStructural then
				chosen = seed
				break
			end
		end
		assert(
			chosen ~= nil,
			"no seed in 1..1000 has generator_attempts_max structurally valid attempts"
		)
		local seed = chosen :: number
		local result = generate()(Contract.ringFor(seed, 4), seed, fake)
		assert(
			typeof(result) == "table" and result.kind == "failed",
			`seed {seed}: kind is {Deep.show(
				if typeof(result) == "table" then result.kind else result
			)}, expected "failed"`
		)
		local shape = Contract.resultShapeProblem(result)
		assert(shape == nil, `C-5: {tostring(shape)}`)
		assert(
			#result.failures == max,
			`seed {seed}: {#result.failures} failure record(s), expected generator_attempts_max = {max}`
		)
		local problems: { string } = {}
		for i, record in result.failures do
			if record.attempt ~= i then
				table.insert(problems, `record {i} names attempt {tostring(record.attempt)}`)
			end
			if not Contract.isTraversal(record.invariant) then
				table.insert(
					problems,
					`record {i} carries {Deep.show(record.invariant)}, which does not start with {Deep.show(
						Contract.TRAVERSAL_HEAD
					)}`
				)
			end
		end
		if #problems > 0 then
			Raise.fail(`C-3 / C-5: seed {seed}:\n{Raise.firstFew(problems, 10)}`)
		end
	end,

	--[[ AC-3 ]]

	["AC-3: at n = 4, 5, 6 over seeds 1..1000, a machines stage that draws one extra number leaves the layout of the accepted attempt equal to Layout.generate on that attempt's layout sub-stream, and at least one placement differs (the needle)"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.assertStageIsolation(generate(), n)
			print(
				`        [measured] stage isolation: n = {n}: placements differ on {stats.placementsDiffer} of {stats.seeds} seeds; same accepted attempt on {stats.sameAttempt}`
			)
		end
	end,

	["AC-3 / C-7: the steps stage is handed attempt-i's steps sub-stream - a spy's derive(\"__spy\") draw equals the expected value and is identical with and without the machines wrapper - at n = 4, 5, 6 over seeds 1..1000"] = function()
		for _, n in Contract.CLASS_COUNTS do
			Contract.assertStepsStreamUnmoved(generate(), n)
		end
	end,

	--[[ AC-4 ]]

	["AC-4: an override that fails every attempt exhausts exactly generator_attempts_max attempts - one { attempt = i, invariant } record each in order, the override's string verbatim where the real invariants passed, the first report string where they did not, and the override called only with facilities that passed (n = 4 seeds 1, 2, 3; n = 5, 6 seed 1)"] = function()
		local g = generate()
		Contract.assertExhausts(g, 1, 4, "AC-4: every attempt is refused")
		Contract.assertExhausts(g, 2, 4, "AC-4: every attempt is refused")
		Contract.assertExhausts(g, 3, 4, "AC-4: every attempt is refused")
		Contract.assertExhausts(g, 1, 5, "AC-4: every attempt is refused")
		Contract.assertExhausts(g, 1, 6, "AC-4: every attempt is refused")
	end,

	["AC-4: an override that fails attempt 1 only yields the first attempt at or after 2 that passes every invariant, by value (n = 4, 5, 6 seed 1)"] = function()
		local g = generate()
		for _, n in Contract.CLASS_COUNTS do
			Contract.assertSkipsFirst(g, 1, n)
		end
	end,

	["AC-4: an override that returns nil for every attempt gives exactly the result of passing no override (n = 4, 5, 6 seeds 1, 2, 500)"] = function()
		local g = generate()
		for _, n in Contract.CLASS_COUNTS do
			for _, seed in { 1, 2, 500 } do
				local ring = Contract.ringFor(seed, n)
				local plain = g(ring, seed, TUNING)
				local withNil = g(ring, seed, TUNING, function(_facility: any): string?
					return nil
				end)
				assert(
					Deep.equal(plain, withNil),
					`{describeN(n)} seed {seed}: a nil-returning override changed the result:\n{Deep.diff(
						plain,
						withNil
					)}`
				)
			end
		end
	end,

	--[[ AC-5. One test per n so each prints its own line. ]]

	["AC-5: at n = 4 over seeds 1..1000, every seed yields a facility within the bound and every facility passes every invariant with par recomputed by the test's own §6.3 (first-attempt rate printed, not asserted)"] = function()
		local stats = Contract.assertSweepValid(generate(), 4)
		print(`        {Contract.describeAcceptance(stats)}`)
		print(`        [measured] {Contract.describeRejections(stats)}`)
	end,

	["AC-5: at n = 5 over seeds 1..1000, every seed yields a facility within the bound and every facility passes every invariant with par recomputed by the test's own §6.3 (first-attempt rate printed, not asserted)"] = function()
		local stats = Contract.assertSweepValid(generate(), 5)
		print(`        {Contract.describeAcceptance(stats)}`)
		print(`        [measured] {Contract.describeRejections(stats)}`)
	end,

	["AC-5: at n = 6 over seeds 1..1000, every seed yields a facility within the bound and every facility passes every invariant with par recomputed by the test's own §6.3 (first-attempt rate printed, not asserted)"] = function()
		local stats = Contract.assertSweepValid(generate(), 6)
		print(`        {Contract.describeAcceptance(stats)}`)
		print(`        [measured] {Contract.describeRejections(stats)}`)
	end,

	["AC-5: the first-attempt acceptance rate at n = 4, 5, 6 is reported against the 0.25 stop rule (a line for the Lead PO; the test passes either way)"] = function()
		local g = generate()
		local below: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.acceptance(g, n)
			if stats.rate < Contract.ACCEPTANCE_FLOOR then
				table.insert(below, `n = {n}: {string.format("%.4f", stats.rate)}`)
			end
		end
		if #below > 0 then
			print(
				`        [measured] STOP RULE: first-attempt acceptance is below {Contract.ACCEPTANCE_FLOOR} at {table.concat(
					below,
					", "
				)} - the story stops at GATES and the Lead PO takes it to the Game Designer (AC-5)`
			)
		else
			print(
				`        [measured] first-attempt acceptance is at or above {Contract.ACCEPTANCE_FLOOR} at every n`
			)
		end
	end,

	--[[ AC-6 ]]

	["AC-6: every swept facility carries exactly layout, placement, steps, spawnRoom, par and attempt; spawnRoom == layout.spawnRoom; par == Par.compute on its own layout, placement, steps and ring"] = function()
		local compute = Par().compute
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			for _, s in Contract.sweep(generate(), n) do
				local facility, why = Contract.facilityOfResult(s.result)
				if facility == nil then
					table.insert(problems, `{describeN(n)} seed {s.seed}: {why}`)
				else
					local keys = Contract.sortedKeys(facility)
					if not Deep.equal(keys, Contract.FACILITY_KEYS) then
						table.insert(
							problems,
							`{describeN(n)} seed {s.seed}: keys {Deep.show(keys)}, expected exactly {Deep.show(
								Contract.FACILITY_KEYS
							)}`
						)
					elseif facility.spawnRoom ~= facility.layout.spawnRoom then
						table.insert(
							problems,
							`{describeN(n)} seed {s.seed}: spawnRoom {tostring(facility.spawnRoom)} ~= layout.spawnRoom {tostring(
								facility.layout.spawnRoom
							)}`
						)
					else
						local want = compute(
							facility.layout,
							facility.placement,
							facility.steps,
							s.assignment,
							TUNING
						)
						if facility.par ~= want then
							table.insert(
								problems,
								`{describeN(n)} seed {s.seed}: facility.par {tostring(facility.par)} ~= Par.compute {tostring(
									want
								)}`
							)
						end
					end
				end
				if #problems > 10 then
					break
				end
			end
		end
		if #problems > 0 then
			Raise.fail(`AC-6:\n{Raise.firstFew(problems, 10)}`)
		end
	end,
}
