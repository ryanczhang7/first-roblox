--!strict
--[[
	GEN-003: the Procedure is two alternating tracks ending in a finale that
	needs four bodies. AC-1 through AC-7, applied to the real
	`src/server/facility/Steps.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `machines_test.luau` does. In RED it does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering seven criteria. Per-criterion failures say which
	behaviours are missing, which is what GREEN needs. It is not a skip: every
	test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS, STATISTICS AND FIXTURES LIVE IN `tests/helpers/ProcedureContract.luau`
	and are exercised against deliberately wrong draws in
	`tests/server/steps_controls_test.luau`. That file is where each statistic
	is OBSERVED to reject its control and accept a reference - which matters in
	RED, because the pcall above means not one assertion in THIS file executes
	until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`):
	  * AC-1 to AC-5 and every `check` token are settled: the sweeps re-derive
	    each invariant with the helper's own checker over the ACCEPTED
	    candidates (those `check` returns `{}` for), and separately require
	    `check` to agree with that checker head for head on every first draw;
	    the fixtures are hand-built on a hand-built layout and placement with a
	    ring whose σ was read back, and their expected heads are hand-written.
	  * AC-6's acceptance and AC-7's two pools are oracle-free statistics with
	    negative controls; their floor, sample sizes and bands are the Lead
	    PO's, verbatim, and are not to be moved in GREEN. AC-6's floor is also
	    what keeps the "accepted candidates" of AC-1 to AC-4 and AC-7 from being
	    an empty set; each sweep test asserts the set is non-empty as well.

	WHAT THIS FILE DOES NOT PIN: which valid structure a given seed draws (the
	Contract forbids it), how `draw` orders its choices, the text after a
	`check` head, how many draws each sub-stream takes, and what `check`
	reports BEYOND `shape` on a malformed candidate.
]]

local Contract = require("../helpers/ProcedureContract")
local Deep = require("../helpers/Deep")

local TUNING = Contract.TUNING

local loaded, loadResult = pcall(require, "../../src/server/facility/Steps")

local function Steps(): any
	assert(loaded, `src/server/facility/Steps.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- The accepted candidates at one n, through the real draw and the real check.
local function acceptedFor(n: number): { Contract.Candidate }
	local S = Steps()
	local list = Contract.accepted(S.draw, S.check, n)
	assert(
		#list > 0,
		`n = {n}: check accepted none of the {Contract.SWEEP_SEEDS} first draws, so there is nothing to sweep`
	)
	return list
end

-- The helper's own violations with the given invariant prefix, over the
-- accepted candidates of every n, as "n = N seed S: ..." lines. Capped so a
-- wholesale failure is a readable report rather than a wall.
local function acceptedViolations(prefix: string): { string }
	local problems: { string } = {}
	for _, n in Contract.CLASS_COUNTS do
		for _, c in acceptedFor(n) do
			local w = c.world
			local found = Contract.withPrefix(
				Contract.violations(c.steps, w.layout, w.placement, w.assignment, TUNING),
				prefix
			)
			for _, v in found do
				table.insert(problems, `n = {n} seed {c.seed}: {v}`)
			end
			if #problems > 20 then
				return problems
			end
		end
	end
	return problems
end

local function sortedKeys(value: { [any]: any }): { string }
	local keys: { string } = {}
	for key in pairs(value) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

-- `check` on a hand-built fixture, parsed into heads.
local function checkFixture(v: Contract.Violation): { tokens: { string }, malformed: { string } }
	local w = Contract.fixtureWorld(v.n)
	return Contract.parseTokens(Steps().check(v.steps, w.layout, w.placement, w.assignment, TUNING))
end

local function fixtureNamed(fragment: string): Contract.Violation
	for _, v in Contract.violationFixtures() do
		if string.find(v.name, fragment, 1, true) ~= nil then
			return v
		end
	end
	error(`no fixture is named "{fragment}"`)
end

local function assertExactHeads(v: Contract.Violation)
	local parsed = checkFixture(v)
	assert(
		#parsed.malformed == 0,
		`{v.name}: check returned strings that do not start with a Contract head and a space: {Deep.show(
			parsed.malformed
		)}`
	)
	assert(
		Deep.equal(parsed.tokens, v.expect),
		`{v.name}: check reported {Deep.show(parsed.tokens)}, expected exactly {Deep.show(v.expect)}`
	)
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Steps exports draw and check as plain field functions"] = function()
		local S = Steps()
		local missing: { string } = {}
		for _, name in { "draw", "check" } do
			if typeof(S[name]) ~= "function" then
				table.insert(missing, `Steps.{name} is {typeof(S[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's two exports are not both functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract: draw returns plain data - exactly the fields tracks and finale, procedure_tracks tracks of steps_per_track numbers, and finale == { tracks[1][last], tracks[2][last] } - at n = 4, 5 and 6"] = function()
		local t = TUNING.instance
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.worldFor(1, n)
			local steps =
				Steps().draw(Contract.rngFor(1), w.layout, w.placement, w.assignment, TUNING)
			assert(typeof(steps) == "table", `n = {n}: draw returned {typeof(steps)}`)
			assert(
				Deep.equal(sortedKeys(steps), { "finale", "tracks" }),
				`n = {n}: the Steps carries fields {Deep.show(sortedKeys(steps))}; the Contract names exactly tracks and finale`
			)
			assert(
				typeof(steps.tracks) == "table" and #steps.tracks == t.procedure_tracks,
				`n = {n}: tracks is {Deep.show(steps.tracks)}, expected {t.procedure_tracks} tracks`
			)
			local lasts: { any } = {}
			for ti, track in steps.tracks do
				assert(
					typeof(track) == "table" and #track == t.steps_per_track,
					`n = {n}: track {ti} is {Deep.show(track)}, expected {t.steps_per_track} steps`
				)
				for i, id in track do
					assert(typeof(id) == "number", `n = {n}: track {ti} step {i} is {typeof(id)}`)
				end
				lasts[ti] = track[#track]
			end
			assert(
				Deep.equal(steps.finale, lasts),
				`n = {n}: finale is {Deep.show(steps.finale)}, expected the tracks' last steps {Deep.show(
					lasts
				)}`
			)
		end
	end,

	["Contract: draw derives exactly the labels choose, order and finale from the rng it is handed, once each, and draws from it directly not at all"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.worldFor(7, n)
			local rng, record = Contract.recordingRng(7)
			Steps().draw(rng, w.layout, w.placement, w.assignment, TUNING)
			local labels = table.clone(record.labels)
			table.sort(labels)
			assert(
				Deep.equal(labels, Contract.DERIVE_LABELS),
				`n = {n}: draw derived {Deep.show(record.labels)}; the Contract names exactly choose, order and finale, once each`
			)
			assert(
				record.directDraws == 0,
				`n = {n}: draw drew {record.directDraws} time(s) from the parent rng directly`
			)
		end
	end,

	["Contract: draw and check never mutate the layout, the placement, the assignment or the steps they are handed"] = function()
		local S = Steps()
		local w = Contract.worldFor(11, 5)
		local layout, placement, assignment = w.layout, w.placement, w.assignment
		local layoutBefore = Contract.snapshot(layout)
		local placementBefore = Contract.snapshot(placement)
		local assignmentBefore = Contract.snapshot(assignment)
		local steps = S.draw(Contract.rngFor(11), layout, placement, assignment, TUNING)
		local stepsBefore = Contract.snapshot(steps)
		S.check(steps, layout, placement, assignment, TUNING)
		for _, v in Contract.violationFixtures() do
			local fw = Contract.fixtureWorld(v.n)
			S.check(v.steps, fw.layout, fw.placement, fw.assignment, TUNING)
		end
		assert(
			Deep.equal(layoutBefore, layout),
			`a call mutated the layout:\n{Deep.diff(layoutBefore, layout)}`
		)
		assert(
			Deep.equal(placementBefore, placement),
			`a call mutated the placement:\n{Deep.diff(placementBefore, placement)}`
		)
		assert(
			Deep.equal(assignmentBefore, assignment),
			`a call mutated the assignment:\n{Deep.diff(assignmentBefore, assignment)}`
		)
		assert(
			Deep.equal(stepsBefore, steps),
			`check mutated the steps:\n{Deep.diff(stepsBefore, steps)}`
		)
	end,

	["Contract: the same rng seed, layout, placement and assignment draw deep-equal Steps twice, at n = 4, 5 and 6"] = function()
		local S = Steps()
		for _, n in Contract.CLASS_COUNTS do
			for _, seed in { 1, 2, 500, 1000 } do
				local w = Contract.worldFor(seed, n)
				local a = S.draw(Contract.rngFor(seed), w.layout, w.placement, w.assignment, TUNING)
				local b = S.draw(Contract.rngFor(seed), w.layout, w.placement, w.assignment, TUNING)
				assert(
					Deep.equal(a, b),
					`n = {n} seed {seed} drew two different Steps:\n{Deep.diff(a, b)}`
				)
			end
		end
	end,

	--[[ AC-6 first, because it is what makes the accepted set of AC-1 to AC-4
	     and AC-7 non-empty. The measured value is printed for ## Notes. ]]

	["AC-6: at n = 4 over seeds 1..1000, at least 0.25 of first draws pass check (measured value printed for GEN-004)"] = function()
		local S = Steps()
		local stats = Contract.assertAcceptance(S.draw, S.check, 4)
		print(`        [measured] Steps acceptance: {Contract.describeAcceptance(stats)}`)
	end,

	["AC-6: at n = 5 over seeds 1..1000, at least 0.25 of first draws pass check (measured value printed for GEN-004)"] = function()
		local S = Steps()
		local stats = Contract.assertAcceptance(S.draw, S.check, 5)
		print(`        [measured] Steps acceptance: {Contract.describeAcceptance(stats)}`)
	end,

	["AC-6: at n = 6 over seeds 1..1000, at least 0.25 of first draws pass check (measured value printed for GEN-004)"] = function()
		local S = Steps()
		local stats = Contract.assertAcceptance(S.draw, S.check, 6)
		print(`        [measured] Steps acceptance: {Contract.describeAcceptance(stats)}`)
	end,

	--[[ AC-1 ]]

	["AC-1: over the accepted candidates at n = 4, 5, 6 and seeds 1..1000, there are procedure_tracks tracks of steps_per_track placement machine ids, no machine twice, each class with exactly stepsPerClass[c] steps and counts at most 1 apart - by the test's own checker"] = function()
		local problems = acceptedViolations("INV_balanced_steps:")
		assert(
			#problems == 0,
			`INV_balanced_steps is broken on candidates check accepted:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	["AC-1: over the accepted candidates, every class in play has at least one step - by the test's own checker"] = function()
		local problems = acceptedViolations("INV_every_class_has_a_step:")
		assert(
			#problems == 0,
			`INV_every_class_has_a_step is broken on candidates check accepted:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	["AC-1/AC-5: on every first draw at n = 4, 5, 6 and seeds 1..1000, check reports exactly the heads the test's own checker derives - so {} means valid and a rejection names the right invariant"] = function()
		local S = Steps()
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			for _, c in Contract.sweep(S.draw, S.check, n) do
				local w = c.world
				assert(
					typeof(c.report) == "table",
					`n = {n} seed {c.seed}: check returned {typeof(c.report)}`
				)
				local theirs = Contract.parseTokens(c.report)
				local ours = Contract.parseTokens(
					Contract.violations(c.steps, w.layout, w.placement, w.assignment, TUNING)
				)
				if #theirs.malformed > 0 then
					table.insert(
						problems,
						`n = {n} seed {c.seed}: malformed {Deep.show(theirs.malformed)}`
					)
				elseif not Deep.equal(theirs.tokens, ours.tokens) then
					table.insert(
						problems,
						`n = {n} seed {c.seed}: check reports {Deep.show(theirs.tokens)}, the test's checker {Deep.show(
							ours.tokens
						)}: {table.concat(c.report, " | ")}`
					)
				end
				if #problems > 20 then
					break
				end
			end
		end
		assert(
			#problems == 0,
			`check disagrees with the test's own checker:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ AC-2 ]]

	["AC-2: over the accepted candidates, no two consecutive steps in a track share a key class - by the test's own checker"] = function()
		local problems = acceptedViolations("INV_track_alternates:")
		assert(
			#problems == 0,
			`INV_track_alternates is broken on candidates check accepted:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	["AC-2 control: check reports exactly INV_track_alternates:adjacent for the hand-built track [c1, c1, c2, c3]"] = function()
		assertExactHeads(fixtureNamed("AC-2's control"))
	end,

	--[[ AC-3 ]]

	["AC-3: over the accepted candidates, the finale machines are in different rooms at least paired_room_distance_min apart, their classes' holders are not ring neighbours, and {turner 1, turner 2, helper 1, helper 2} are four distinct players"] = function()
		local problems = acceptedViolations("INV_finale:")
		for _, n in Contract.CLASS_COUNTS do
			for _, c in acceptedFor(n) do
				local who =
					Contract.finaleParticipants(c.steps, c.world.placement, c.world.assignment)
				local distinct: { [string]: boolean } = {}
				for _, p in who do
					if p ~= nil then
						distinct[p] = true
					end
				end
				if #sortedKeys(distinct) ~= 4 then
					table.insert(
						problems,
						`n = {n} seed {c.seed}: finale participants {Deep.show(who)} are not four distinct players`
					)
				end
				if #problems > 20 then
					break
				end
			end
		end
		assert(
			#problems == 0,
			`INV_finale is broken on candidates check accepted:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-3 controls: check reports exactly INV_finale:rooms for finale machines in adjacent rooms, and exactly INV_finale:ring for finale classes held by ring neighbours"] = function()
		assertExactHeads(fixtureNamed("finale machines in adjacent rooms (AC-3's control)"))
		assertExactHeads(fixtureNamed("finale classes held by ring neighbours (AC-3's control)"))
	end,

	--[[ AC-4 ]]

	["AC-4: over the accepted candidates, for every seated player some step has a machine only they can turn and some step has a machine whose setting only they can read - by the test's own checker"] = function()
		local problems = acceptedViolations("INV_k_essential:")
		assert(
			#problems == 0,
			`INV_k_essential is broken on candidates check accepted:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ AC-5 ]]

	["AC-5 / check tokens: every hand-built violation is reported under exactly its own head(s) - shape, count, missing, adjacent, rooms, ring, turn - as `<INV>:<token> `, one string per violated invariant, and nothing else"] = function()
		local problems: { string } = {}
		for _, v in Contract.violationFixtures() do
			local ok, err = pcall(assertExactHeads, v)
			if not ok then
				table.insert(problems, tostring(err))
			end
		end
		assert(
			#problems == 0,
			`check does not report what the Contract's table says:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-5: check returns {} for the hand-built valid Steps at n = 4, 5 and 6"] = function()
		local S = Steps()
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.fixtureWorld(n)
			local report =
				S.check(Contract.validSteps(n), w.layout, w.placement, w.assignment, TUNING)
			assert(
				Deep.equal(report, {}),
				`n = {n}: check reported {Deep.show(report)} on valid hand-built Steps`
			)
		end
	end,

	["AC-5: check on a Steps with no tracks at all does not raise, reports INV_balanced_steps:shape, and emits no malformed string"] = function()
		local w = Contract.fixtureWorld(4)
		local ok, result =
			pcall(Steps().check, Contract.emptySteps(), w.layout, w.placement, w.assignment, TUNING)
		assert(ok, `check raised on \{ tracks = \{}, finale = \{} }: {tostring(result)}`)
		local parsed = Contract.parseTokens(result)
		assert(#parsed.malformed == 0, `malformed strings: {Deep.show(parsed.malformed)}`)
		assert(
			table.find(parsed.tokens, "INV_balanced_steps:shape") ~= nil,
			`check reported {Deep.show(parsed.tokens)} on the empty Steps; no shape`
		)
	end,

	--[[ AC-7 ]]

	["AC-7: at n = 4, over accepted candidates of seeds 1, 2, 3, ... until both pools hold 16,000 settings (cap 20,000 seeds), each setting's frequency among step machines and among decoys lies within 1/dial_settings ± 0.02"] = function()
		local S = Steps()
		local stats = Contract.assertSettingPools(S.draw, S.check, 4)
		print(`        [measured] Steps pools: {Contract.describePools(stats)}`)
	end,

	["AC-7: at n = 5, over accepted candidates of seeds 1, 2, 3, ... until both pools hold 16,000 settings (cap 20,000 seeds), each setting's frequency among step machines and among decoys lies within 1/dial_settings ± 0.02"] = function()
		local S = Steps()
		local stats = Contract.assertSettingPools(S.draw, S.check, 5)
		print(`        [measured] Steps pools: {Contract.describePools(stats)}`)
	end,

	["AC-7: at n = 6, over accepted candidates of seeds 1, 2, 3, ... until both pools hold 16,000 settings (cap 20,000 seeds), each setting's frequency among step machines and among decoys lies within 1/dial_settings ± 0.02"] = function()
		local S = Steps()
		local stats = Contract.assertSettingPools(S.draw, S.check, 6)
		print(`        [measured] Steps pools: {Contract.describePools(stats)}`)
	end,
}
