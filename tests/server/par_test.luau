--!strict
--[[
	GEN-004 AC-1: par is the duration of the canonical schedule of
	`mechanics.md` §6.3, exactly, applied to the real
	`src/server/facility/Par.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `steps_test.luau` does. In RED it does not exist, and a bare
	top-level `require` would make this whole file a single LOAD FAIL. Per-test
	failures say which behaviours are missing. It is not a skip: every test
	below still FAILS, loudly, naming the module that did not load.

	THE FIXTURES AND THE ORACLE LIVE IN `tests/helpers/FacilityContract.luau`
	and are exercised against deliberately wrong computes in
	`tests/server/facility_controls_test.luau`, which is where each fixture's
	hand arithmetic is OBSERVED to reject the control the criterion names and
	to be reproduced by the test's own §6.3.

	THE ORACLE PARTITION: AC-1 is settled. Each fixture's expected par is
	arithmetic over `room_traversal_seconds`, `par_ping_seconds` and
	`par_turn_seconds` as read from `MechanicsTuning`, with the schedule
	derived step by step beside the fixture. Nothing here invents a metric.

	WHAT THIS FILE DOES NOT PIN: how `Par` walks the graph (only that the
	result equals a shortest-path count times the constant), whether it reads
	`steps_per_track` or `#track` for the ordinary steps (they agree on every
	valid Steps), or what it does on a malformed Steps - the generator never
	hands it one (C-4).
]]

local Contract = require("../helpers/FacilityContract")
local Deep = require("../helpers/Deep")
local Raise = require("../helpers/Contract")

local TUNING = Contract.TUNING

local loaded, loadResult = pcall(require, "../../src/server/facility/Par")

local function Par(): any
	assert(loaded, `src/server/facility/Par.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local function fixtureTest(fragment: string): () -> ()
	return function()
		Contract.assertParFixture(Par().compute, Contract.fixtureNamed(fragment))
	end
end

return {
	--[[ The export shape, first: a wrong guess here is a compile error rather
	     than a puzzle. ]]

	["Contract: Par exports compute as a plain field function and the module table is frozen"] = function()
		local P = Par()
		assert(typeof(P) == "table", `Par is {typeof(P)}`)
		assert(typeof(P.compute) == "function", `Par.compute is {typeof(P.compute)}`)
		assert(table.isfrozen(P), "the Par module table is not frozen (C-1)")
	end,

	["Contract: compute returns a number, exact and unrounded, on every AC-1 fixture"] = function()
		for _, f in Contract.parFixtures() do
			local got = Par().compute(f.layout, f.placement, f.steps, f.assignment, TUNING)
			assert(typeof(got) == "number", `{f.name}: compute returned {typeof(got)}`)
		end
	end,

	--[[ AC-1: the four hand-built fixtures. Each expected value is arithmetic
	     over the tuning constants; see FacilityContract.parFixtures. ]]

	["AC-1 fixture 1: everything in spawn_room - six ordinary steps and the finale each cost exactly par_ping_seconds + par_turn_seconds, no walking"] = fixtureTest(
		"fixture 1"
	),

	["AC-1 fixture 2: the chain layout with machines at both ends - 24 edges of walking from the centre spawn room plus seven units of ping and turn"] = fixtureTest(
		"fixture 2"
	),

	["AC-1 fixture 3: a finale whose two pairs walk 1 and 2 edges - only the longer walk counts, and the finale pays ping and turn once"] = fixtureTest(
		"fixture 3"
	),

	["AC-1 fixture 4: a helper and a turner starting in different rooms - each step waits for the later arrival, never the sum of the two walks"] = fixtureTest(
		"fixture 4"
	),

	--[[ The oracle and the module, over real compositions: Par.compute must
	     equal the test's own §6.3 on every first attempt of the C-8 sweep, so
	     a Par that is right on four fixtures and wrong on a loop, a tie or a
	     longer track is still caught. ]]

	["AC-1: Par.compute equals the test's own §6.3 on the first attempt of seeds 1..1000 at n = 4, 5 and 6, recomposed from the real Layout, Machines and Steps"] = function()
		local compute = Par().compute
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			for seed = 1, Contract.SWEEP_SEEDS do
				local assignment = Contract.ringFor(seed, n)
				local a = Contract.recompose(assignment, seed, 1, TUNING)
				if a.stage == "layout" or a.stage == "machines" or a.stage == "steps" then
					continue
				end
				local got = compute(a.layout, a.placement, a.steps, assignment, TUNING)
				if got ~= a.par then
					table.insert(
						problems,
						`n = {n} seed {seed}: Par.compute {tostring(got)}, the test's own §6.3 {tostring(
							a.par
						)}`
					)
				end
				if #problems > 20 then
					break
				end
			end
		end
		if #problems > 0 then
			Raise.fail(
				`AC-1: Par.compute disagrees with the test's own canonical schedule:\n{Raise.firstFew(
					problems,
					20
				)}`
			)
		end
	end,

	["Contract: compute never mutates the layout, the placement, the steps, the assignment or the tuning it is handed"] = function()
		local compute = Par().compute
		for _, f in Contract.parFixtures() do
			local before = Contract.snapshot({ f.layout, f.placement, f.steps, f.assignment })
			compute(f.layout, f.placement, f.steps, f.assignment, TUNING)
			local after = { f.layout, f.placement, f.steps, f.assignment }
			assert(
				Deep.equal(before, after),
				`{f.name}: compute mutated an argument:\n{Deep.diff(before, after)}`
			)
		end
	end,
}
