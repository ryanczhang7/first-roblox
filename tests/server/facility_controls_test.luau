--!strict
--[[
	The negative controls for GEN-004, and the proof that each check, each
	fixture and the oracle in `tests/helpers/FacilityContract.luau` mean what
	they say.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `src/server/facility/
	Par.luau` and `Generator.luau` do not exist, every test in `par_test.luau`
	and `generator_test.luau` fails before its assertion runs, and so not one
	of those files' checks has been observed to accept or reject anything.
	These controls need only `Rng`, `MechanicsTuning`, `Tuning`, `Layout`,
	`Machines`, `Steps` and `Ring`, which are merged, so the numbers asserted
	below are MEASUREMENTS taken in RED rather than claims left for GREEN. The
	story's handoff carries them as a table.

	FOUR KINDS OF CONTROL:

	  * THE ORACLE. The test's own §6.3 (`Contract.par`) is shown to reproduce
	    AC-1's hand arithmetic on all four fixtures, and to agree with a second,
	    independently written compute (`FacilityStubs.computeReference`) on the
	    fixtures and on 3,000 real compositions. A sweep that trusted an
	    oracle nobody had pinned could not see D-1.
	  * AC-1's named controls. The sum-of-walks compute is shown to FAIL
	    fixture 4 and the sequential-finale compute to FAIL fixture 3, through
	    the same `assertParFixture` the real file uses - and each is shown to
	    PASS the fixture that does not exercise its defect, so the control is
	    attributable.
	  * THE GENERATOR CHECKS. Each is shown to ACCEPT the reference generator
	    and to REJECT the one-defect generator aimed at it: the shared-stream
	    generator (AC-3), and the shapes D-1 to D-4 will mutate into the real
	    module in GATES, so that the sweep is known to be able to see them.
	  * THE FIXTURES' ASSUMPTIONS. The hand-built ring is checked against
	    `Ring.assign`, the fixture steps against GEN-003's own checker, and the
	    needles against strings that must not satisfy them.
]]

local Contract = require("../helpers/FacilityContract")
local Deep = require("../helpers/Deep")
local LayoutContract = require("../helpers/LayoutContract")
local ProcedureContract = require("../helpers/ProcedureContract")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/shared/Rng")
local Stubs = require("../helpers/FacilityStubs")

local TUNING = Contract.TUNING

local function refuses(run: () -> (), what: string): string
	local ok, err = pcall(run)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

-- Which AC-1 fixtures a compute fails, by name fragment, for the record.
local function fixturesFailedBy(compute: Contract.Compute): { string }
	local failed: { string } = {}
	for _, f in Contract.parFixtures() do
		local ok = pcall(Contract.assertParFixture, compute, f)
		if not ok then
			table.insert(failed, string.match(f.name, "^fixture %d") or f.name)
		end
	end
	return failed
end

return {
	--[[ ================================================================
	     The oracle.
	     ================================================================ ]]

	["oracle: the test's own §6.3 reproduces the hand arithmetic of all four AC-1 fixtures"] = function()
		for _, f in Contract.parFixtures() do
			Contract.assertParFixture(Contract.par, f)
		end
		local t = TUNING.instance
		print(
			`        [measured] oracle par per fixture (W = {t.room_traversal_seconds}, P = {t.par_ping_seconds}, T = {t.par_turn_seconds}): {table.concat(
				(function(): { string }
					local out: { string } = {}
					for _, f in Contract.parFixtures() do
						table.insert(out, `{string.match(f.name, "^fixture %d")} = {f.expected}`)
					end
					return out
				end)(),
				", "
			)}`
		)
	end,

	["oracle: a second, independently written compute agrees with the test's own §6.3 on the fixtures and on the first attempt of seeds 1..1000 at n = 4, 5, 6"] = function()
		for _, f in Contract.parFixtures() do
			Contract.assertParFixture(Stubs.computeReference, f)
		end
		local problems: { string } = {}
		local compared = 0
		for _, n in Contract.CLASS_COUNTS do
			for seed = 1, Contract.SWEEP_SEEDS do
				local assignment = Contract.ringFor(seed, n)
				local a = Contract.recompose(assignment, seed, 1, TUNING)
				if a.par == nil then
					continue
				end
				compared += 1
				local other = Stubs.computeReference(
					a.layout :: Contract.Layout,
					a.placement :: Contract.Placement,
					a.steps :: Contract.Steps,
					assignment,
					TUNING
				)
				if other ~= a.par then
					table.insert(problems, `n = {n} seed {seed}: {a.par} vs {other}`)
				end
				if #problems > 10 then
					break
				end
			end
		end
		assert(compared >= 2900, `only {compared} compositions reached par`)
		assert(
			#problems == 0,
			`the two writings of §6.3 disagree:\n{table.concat(problems, "\n")}`
		)
	end,

	["oracle: the chain fixture's par exceeds INV_traversal under the shipped tuning, so a chain is a layout the generator must reject (measured, printed)"] = function()
		local f = Contract.fixtureNamed("fixture 2")
		local ok = Contract.traversalOk(f.expected, TUNING)
		print(
			`        [measured] chain fixture: par {f.expected} × schedule_slack {TUNING.instance.schedule_slack} = {f.expected * TUNING.instance.schedule_slack} against round_seconds {Contract.ROUND_SECONDS}: {if ok
				then "ACCEPTED"
				else "rejected"}`
		)
		assert(
			not ok,
			`the chain fixture passes INV_traversal at par {f.expected}; tuning.md's schedule_slack rationale says a chain must not - report, do not retune`
		)
	end,

	--[[ ================================================================
	     AC-1's named controls.
	     ================================================================ ]]

	["AC-1 control: a compute that sums the helper's and the turner's walks fails fixture 4, and passes fixture 1 where nobody walks (measured: which fixtures it fails)"] = function()
		local message = refuses(function()
			Contract.assertParFixture(Stubs.computeSumWalks, Contract.fixtureNamed("fixture 4"))
		end, "the sum-of-walks compute must fail fixture 4")
		names(message, "AC-1", "the sum-of-walks compute fails")
		names(message, "fixture 4", "the sum-of-walks compute fails")
		Contract.assertParFixture(Stubs.computeSumWalks, Contract.fixtureNamed("fixture 1"))
		print(
			`        [measured] sum-of-walks fails {Deep.show(
				fixturesFailedBy(Stubs.computeSumWalks)
			)}`
		)
	end,

	["AC-1 control: a compute that takes the finale's two sub-steps one after the other fails fixture 3 (measured: which fixtures it fails - every one, since each has a finale)"] = function()
		local message = refuses(function()
			Contract.assertParFixture(
				Stubs.computeSequentialFinale,
				Contract.fixtureNamed("fixture 3")
			)
		end, "the sequential-finale compute must fail fixture 3")
		names(message, "AC-1", "the sequential-finale compute fails")
		names(message, "fixture 3", "the sequential-finale compute fails")
		print(
			`        [measured] sequential-finale fails {Deep.show(
				fixturesFailedBy(Stubs.computeSequentialFinale)
			)}`
		)
	end,

	["extra control: a compute that takes all of track 1 before track 2 fails fixture 2 and passes fixtures 1, 3 and 4 - so the chain fixture is what pins C-2's interleaved order"] = function()
		local message = refuses(function()
			Contract.assertParFixture(Stubs.computeTrackwise, Contract.fixtureNamed("fixture 2"))
		end, "the trackwise compute must fail fixture 2")
		names(message, "fixture 2", "the trackwise compute fails")
		assert(
			Deep.equal(fixturesFailedBy(Stubs.computeTrackwise), { "fixture 2" }),
			`the trackwise compute fails {Deep.show(fixturesFailedBy(Stubs.computeTrackwise))}, expected only fixture 2`
		)
	end,

	--[[ ================================================================
	     The fixtures' assumptions.
	     ================================================================ ]]

	["fixtures: the hand-built ring deep-equals Ring.assign({p1..p4}, Rng.fromSeed(1)), so helper(c) and turner(c) are what the derivations say"] = function()
		local real = Ring.assign(Contract.playersFor(4), Rng.fromSeed(1))
		local hand = Contract.fixtureAssignment()
		assert(
			Deep.equal(real, hand),
			`the hand-built ring is not Ring.assign at seed 1:\n{Deep.diff(real, hand)}`
		)
		-- The derivations' helper table, read back through the own lookup.
		local want = { [1] = "p4", [2] = "p3", [3] = "p1", [4] = "p2" }
		for c = 1, 4 do
			assert(Contract.turnerOf(hand, c) == `p{c}`, `turner of class {c} is not p{c}`)
			assert(
				Contract.helperOf(hand, c) == want[c],
				`helper of class {c} is {tostring(Contract.helperOf(hand, c))}, the derivation says {want[c]}`
			)
		end
	end,

	["fixtures: the square and chain layouts' spawnRoom fields are 2 and 3 and equal the test's own least-eccentricity rule, and the distances the derivations use are the test's own BFS"] = function()
		local square = LayoutContract.layoutOf(LayoutContract.FIXTURES[2])
		local chain = LayoutContract.layoutOf(LayoutContract.FIXTURES[1])
		assert(square.spawnRoom == 2 and chain.spawnRoom == 3, "the fixture spawn rooms moved")
		assert(LayoutContract.spawnRoomOf(#square.rooms, square.doors) == 2, "square spawn")
		assert(LayoutContract.spawnRoomOf(#chain.rooms, chain.doors) == 3, "chain spawn")
		local ds = Contract.distanceFn(square)
		local dc = Contract.distanceFn(chain)
		local expect = {
			{ ds, 2, 1, 1 },
			{ ds, 2, 3, 1 },
			{ ds, 2, 6, 2 },
			{ ds, 3, 4, 3 },
			{ ds, 1, 4, 1 },
			{ ds, 4, 2, 2 },
			{ ds, 4, 6, 2 },
			{ dc, 3, 1, 2 },
			{ dc, 3, 4, 3 },
			{ dc, 1, 4, 5 },
			{ dc, 4, 1, 5 },
		}
		for _, e in expect do
			local fn = e[1] :: (number, number) -> number
			assert(
				fn(e[2] :: number, e[3] :: number) == e[4],
				`d({e[2]}, {e[3]}) is {fn(e[2] :: number, e[3] :: number)}, the derivation uses {e[4]}`
			)
		end
	end,

	["fixtures: fixtures 2, 3 and 4 are valid Steps by GEN-003's own checker, and fixture 1 (everything in one room) trips exactly INV_finale:rooms"] = function()
		for _, f in Contract.parFixtures() do
			local found =
				ProcedureContract.violations(f.steps, f.layout, f.placement, f.assignment, TUNING)
			local parsed = ProcedureContract.parseTokens(found)
			if string.find(f.name, "fixture 1", 1, true) then
				assert(
					Deep.equal(parsed.tokens, { "INV_finale:rooms" }),
					`{f.name}: GEN-003's checker reports {Deep.show(parsed.tokens)}, expected only INV_finale:rooms`
				)
			else
				assert(
					#found == 0,
					`{f.name}: GEN-003's checker reports {table.concat(found, " | ")}`
				)
			end
		end
	end,

	--[[ ================================================================
	     The reference generator: every check accepts it (measured).
	     ================================================================ ]]

	["baseline: the reference generator passes AC-2's recomposition, AC-5's sweep, AC-3's isolation and spy, AC-4's exhaustion and skip, and C-5's shape at n = 4, 5, 6 - with the first-attempt rate printed (the RED reading of C-9)"] = function()
		local g = Stubs.reference
		for _, n in Contract.CLASS_COUNTS do
			Contract.assertRecomposition(g, n)
			local stats = Contract.assertSweepValid(g, n)
			print(`        {Contract.describeAcceptance(stats)}`)
			print(`        [measured] {Contract.describeRejections(stats)}`)
			assert(
				stats.facilities == Contract.SWEEP_SEEDS,
				`n = {n}: {stats.facilities} facilities`
			)
			local iso = Contract.assertStageIsolation(g, n)
			print(
				`        [measured] reference isolation: n = {n}: placements differ on {iso.placementsDiffer} seeds, same attempt on {iso.sameAttempt}`
			)
			Contract.assertStepsStreamUnmoved(g, n)
			Contract.assertExhausts(g, 1, n, "refused")
			Contract.assertSkipsFirst(g, 1, n)
			for _, s in Contract.sweep(g, n) do
				assert(Contract.resultShapeProblem(s.result) == nil, `n = {n} seed {s.seed}: shape`)
			end
			local later = Contract.seedAcceptedLater(g, n)
			assert(later ~= nil, `n = {n}: no seed accepted after attempt 1`)
		end
	end,

	--[[ ================================================================
	     AC-3's control, and the D-shapes.
	     ================================================================ ]]

	["AC-3 control: a generator that hands every stage the same un-derived attempt stream is rejected by AC-3's isolation check (the layout is not the layout sub-stream's) and by AC-2's recomposition"] = function()
		local message = refuses(function()
			Contract.assertStageIsolation(Stubs.sharedStream, 4)
		end, "the shared-stream generator must fail AC-3")
		names(message, "AC-3", "the shared-stream generator fails")
		names(message, "layout", "the shared-stream generator fails")
		local message2 = refuses(function()
			Contract.assertRecomposition(Stubs.sharedStream, 4)
		end, "the shared-stream generator must fail AC-2")
		names(message2, "AC-2", "the shared-stream generator fails")
	end,

	["D-3's shape: a generator whose machines stage is handed the layout sub-stream is rejected by AC-2's recomposition (AC-3's layout check alone cannot see it: derive reads identity, not state - measured)"] = function()
		local message = refuses(function()
			Contract.assertRecomposition(Stubs.machinesOnLayoutStream, 4)
		end, "the machines-on-layout-stream generator must fail AC-2")
		names(message, "AC-2", "the machines-on-layout-stream generator fails")
		names(message, "placement", "the machines-on-layout-stream generator fails")
		local ok = pcall(Contract.assertStageIsolation, Stubs.machinesOnLayoutStream, 4)
		print(
			`        [measured] D-3 shape under AC-3's isolation check alone: {if ok
				then "NOT caught (AC-2 catches it)"
				else "caught"}`
		)
	end,

	["D-4's shape: a generator whose attempt i draws from attempt-(i + 1) is rejected by AC-2's recomposition"] = function()
		local message = refuses(function()
			Contract.assertRecomposition(Stubs.attemptOffByOne, 4)
		end, "the off-by-one generator must fail AC-2")
		names(message, "AC-2", "the off-by-one generator fails")
	end,

	["D-2's shape: a generator that never checks INV_traversal is rejected by AC-5's sweep at n = 4, 5 and 6, naming INV_traversal (measured: how many seeds the sweep can see it on)"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local message = refuses(function()
				Contract.assertSweepValid(Stubs.noTraversal, n)
			end, `the no-traversal generator must fail AC-5 at n = {n}`)
			names(message, "AC-5", "the no-traversal generator fails")
			names(message, "INV_traversal:par ", "the no-traversal generator fails")
			local visible = 0
			for _, s in Contract.sweep(Stubs.noTraversal, n) do
				local facility = Contract.facilityOfResult(s.result)
				if facility ~= nil and not Contract.traversalOk(facility.par, TUNING) then
					visible += 1
				end
			end
			print(
				`        [measured] D-2 visibility: n = {n}: {visible} of 1000 seeds return a facility that violates INV_traversal`
			)
			assert(
				visible > 0,
				`n = {n}: the sweep cannot see D-2 - no seed's first facility violates INV_traversal`
			)
		end
	end,

	["D-1's shape: a generator whose par sums the walks is rejected by AC-5's sweep (facility.par is not the test's §6.3) and rejects more first attempts than the reference (measured)"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local message = refuses(function()
				Contract.assertSweepValid(Stubs.sumWalks, n)
			end, `the summed-walks generator must fail AC-5 at n = {n}`)
			names(message, "AC-5", "the summed-walks generator fails")
			names(message, "par:", "the summed-walks generator fails")
			local reference = Contract.acceptance(Stubs.reference, n)
			local summed = Contract.acceptance(Stubs.sumWalks, n)
			print(
				`        [measured] D-1 shape: n = {n}: first attempts accepted {summed.firstAttempt} (summed) vs {reference.firstAttempt} (reference); max attempt {summed.maxAttempt} vs {reference.maxAttempt}`
			)
			assert(
				summed.firstAttempt < reference.firstAttempt,
				`n = {n}: summing the walks did not lower first-attempt acceptance ({summed.firstAttempt} vs {reference.firstAttempt})`
			)
		end
	end,

	["AC-4 / AC-5 control: a generator that returns its first attempt whether or not it passed is rejected by AC-5's sweep and by AC-2's recomposition, and ignores the override so AC-4's exhaustion check refuses it"] = function()
		local message = refuses(function()
			Contract.assertSweepValid(Stubs.returnsRejected, 4)
		end, "the returns-rejected generator must fail AC-5")
		names(message, "AC-5", "the returns-rejected generator fails")
		local message2 = refuses(function()
			Contract.assertRecomposition(Stubs.returnsRejected, 4)
		end, "the returns-rejected generator must fail AC-2")
		names(message2, "AC-2", "the returns-rejected generator fails")
		local message3 = refuses(function()
			Contract.assertExhausts(Stubs.returnsRejected, 1, 4, "refused")
		end, "the returns-rejected generator must fail AC-4")
		names(message3, "AC-4", "the returns-rejected generator fails")
		names(message3, "failed", "the returns-rejected generator fails")
	end,

	--[[ ================================================================
	     The checks' own needles and shape clauses.
	     ================================================================ ]]

	["needles: isTraversal accepts only strings starting `INV_traversal:par ` with the space, and headOf reads only a leading `<INV>:<token> `"] = function()
		assert(
			Contract.isTraversal("INV_traversal:par 300 × 1.5 > round_seconds 420"),
			"the real head"
		)
		assert(not Contract.isTraversal("INV_traversal:par"), "no trailing space")
		assert(not Contract.isTraversal("INV_traversal:parx "), "a longer token")
		assert(not Contract.isTraversal(" INV_traversal:par x"), "a leading space")
		assert(not Contract.isTraversal("failed INV_traversal:par x"), "embedded")
		assert(not Contract.isTraversal(nil), "nil")
		assert(Contract.headOf("INV_finale:rooms x") == "INV_finale:rooms", "a real head")
		assert(Contract.headOf("INV_finale:rooms") == nil, "no space")
		assert(Contract.headOf("x INV_finale:rooms y") == nil, "not leading")
	end,

	["shape: resultShapeProblem refuses a result carrying both facility and failures, neither, or an unknown kind; facilityViolations refuses an extra key, a wrong spawnRoom and a wrong par on an otherwise valid facility"] = function()
		assert(
			Contract.resultShapeProblem({ kind = "facility", facility = {}, failures = {} }) ~= nil,
			"both"
		)
		assert(
			Contract.resultShapeProblem({ kind = "facility" }) ~= nil,
			"facility without facility"
		)
		assert(Contract.resultShapeProblem({ kind = "failed" }) ~= nil, "failed without failures")
		assert(Contract.resultShapeProblem({ kind = "other" }) ~= nil, "unknown kind")
		assert(
			Contract.resultShapeProblem({ kind = "failed", failures = {} }) == nil,
			"a failed result"
		)

		local ring = Contract.ringFor(1, 4)
		local expected = Contract.expectedFor(1, 4, TUNING)
		local good = Contract.facilityOf(expected.accepted :: Contract.Attempt)
		assert(
			#Contract.facilityViolations(good, ring, TUNING) == 0,
			"the reference facility is valid"
		)

		local extra: any = Deep.copy(good)
		extra.seed = 1
		local v1 = Contract.facilityViolations(extra, ring, TUNING)
		assert(
			#v1 == 1 and string.find(v1[1], "AC-6 shape", 1, true) ~= nil,
			`extra key: {Deep.show(v1)}`
		)

		local spawn: any = Deep.copy(good)
		spawn.spawnRoom = spawn.spawnRoom % #spawn.layout.rooms + 1
		local v2 = Contract.facilityViolations(spawn, ring, TUNING)
		assert(
			#v2 == 1 and string.find(v2[1], "AC-6 spawnRoom", 1, true) ~= nil,
			`spawnRoom: {Deep.show(v2)}`
		)

		local par: any = Deep.copy(good)
		par.par = par.par + 1
		local v3 = Contract.facilityViolations(par, ring, TUNING)
		assert(#v3 == 1 and string.find(v3[1], "AC-5 par:", 1, true) ~= nil, `par: {Deep.show(v3)}`)
	end,
}
