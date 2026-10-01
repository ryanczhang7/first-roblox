--!strict
--[[
	The negative controls for GEN-003, and the proof that each statistic and
	each fixture in `tests/helpers/ProcedureContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `src/server/facility/
	Steps.luau` does not exist, every test in `tests/server/steps_test.luau`
	fails before its assertion runs, and so not one of that file's statistics
	has been observed to accept or reject anything. These controls need only
	`Rng`, `MechanicsTuning`, `Layout`, `Machines` and `Ring`, which are merged,
	so the numbers asserted below are MEASUREMENTS taken in RED rather than
	claims left for GREEN. The story's handoff carries them as a table.

	THREE KINDS OF CONTROL:

	  * The statistics (AC-6 acceptance, AC-7 pools) are each shown to REJECT
	    the draw the criterion names and to ACCEPT the reference. A statistic
	    that rejects everything is indistinguishable from a broken one, and the
	    acceptance half is the one that is easy to leave out.
	  * The hand-built fixtures (the valid steps, the violation steps) are run
	    through this file's own checker. A fixture whose expected head list is
	    wrong fails HERE, in RED, where the fix is a fixture - not in GREEN,
	    where it would read as a defect in `Steps`.
	  * The hand-built fixtures' ASSUMPTIONS - the shipped constants and the σ
	    the comments state - are checked against the constants and the ring as
	    read, so a drift fails with a message naming the fixture rather than a
	    puzzle in `check`.

	Every control is also held to the checks it SHOULD pass, so that a control
	that fires is attributable to its one defect.
]]

local Contract = require("../helpers/ProcedureContract")
local Deep = require("../helpers/Deep")
local Stubs = require("../helpers/ProcedureStubs")

local TUNING = Contract.TUNING
local check = Contract.violations

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

local function sortedKeys(value: { [any]: any }): { string }
	local keys: { string } = {}
	for key in pairs(value) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

-- Every first draw of a draw, at every n, must be rejected ONLY under the
-- heads in `allowed` (the control's one intended defect); the accepted ones
-- are, by construction, clean in our checker.
local function rejectionsOnly(draw: Contract.Draw, who: string, allowed: { string })
	local allow: { [string]: boolean } = {}
	for _, head in allowed do
		allow[head] = true
	end
	local problems: { string } = {}
	for _, n in Contract.CLASS_COUNTS do
		for _, c in Contract.sweep(draw, check, n) do
			local parsed = Contract.parseTokens(c.report)
			for _, m in parsed.malformed do
				table.insert(problems, `n = {n} seed {c.seed}: malformed {m}`)
			end
			for _, head in parsed.tokens do
				if not allow[head] then
					table.insert(problems, `n = {n} seed {c.seed}: {head}`)
				end
			end
			if #problems > 10 then
				break
			end
		end
	end
	assert(
		#problems == 0,
		`{who} breaks an invariant other than its own defect:\n{table.concat(problems, "\n")}`
	)
end

return {
	--[[ ================================================================
	     The reference. Everything below is this draw with one defect.
	     ================================================================ ]]

	["baseline: the reference draw's first candidates are rejected by nothing but INV_finale, and are accepted at or above the AC-6 floor at n = 4, 5 and 6 (measured: see the run log)"] = function()
		rejectionsOnly(
			Stubs.reference,
			"the reference draw",
			{ "INV_finale:rooms", "INV_finale:ring" }
		)
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.assertAcceptance(Stubs.reference, check, n)
			print(`        [measured] reference acceptance: {Contract.describeAcceptance(stats)}`)
		end
	end,

	["baseline: the reference draw is deterministic, returns exactly { tracks, finale }, derives exactly choose, order and finale once each, and draws nothing directly"] = function()
		for _, n in Contract.CLASS_COUNTS do
			for _, seed in { 1, 2, 77, 1000 } do
				local w = Contract.worldFor(seed, n)
				local a = Stubs.reference(
					Contract.rngFor(seed),
					w.layout,
					w.placement,
					w.assignment,
					TUNING
				)
				local b = Stubs.reference(
					Contract.rngFor(seed),
					w.layout,
					w.placement,
					w.assignment,
					TUNING
				)
				assert(
					Deep.equal(a, b),
					`n = {n} seed {seed} drew two different candidates:\n{Deep.diff(a, b)}`
				)
				assert(
					Deep.equal(sortedKeys(a), { "finale", "tracks" }),
					`the reference's Steps carries {Deep.show(sortedKeys(a))}`
				)
				assert(
					Deep.equal(a.finale, { a.tracks[1][#a.tracks[1]], a.tracks[2][#a.tracks[2]] }),
					`the reference's finale is not the tracks' last steps`
				)
			end
			local w = Contract.worldFor(7, n)
			local rng, record = Contract.recordingRng(7)
			Stubs.reference(rng, w.layout, w.placement, w.assignment, TUNING)
			local labels = table.clone(record.labels)
			table.sort(labels)
			assert(
				Deep.equal(labels, Contract.DERIVE_LABELS),
				`the reference derived {Deep.show(record.labels)}`
			)
			assert(
				record.directDraws == 0,
				`the reference drew {record.directDraws} time(s) directly`
			)
		end
	end,

	--[[ ================================================================
	     The hand-built fixtures.
	     ================================================================ ]]

	["fixtures: the hand-built steps assume the shipped constants - procedure_tracks tracks of steps_per_track, procedure_length steps, paired_room_distance_min - and GEN-002's 16-machine placement"] = function()
		local t = TUNING.instance
		local a = Contract.FIXTURE_ASSUMES
		local problems: { string } = {}
		local function expect(label: string, got: number, want: number)
			if got ~= want then
				table.insert(
					problems,
					`{label}: the fixtures were drawn for {got}, the tuning reads {want}`
				)
			end
		end
		expect("procedure_tracks", a.procedureTracks, t.procedure_tracks)
		expect("steps_per_track", a.stepsPerTrack, t.steps_per_track)
		expect("procedure_length", a.procedureLength, t.procedure_length)
		expect("paired_room_distance_min", a.pairedRoomDistanceMin, t.paired_room_distance_min)
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.fixtureWorld(n)
			if #w.placement.machines ~= 16 then
				table.insert(
					problems,
					`n = {n}: the placement fixture has {#w.placement.machines} machines, the steps were drawn for 16`
				)
			end
		end
		assert(
			#problems == 0,
			`the hand-built fixtures no longer match the tuning:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: the ring at FIXTURE_RING_SEED has exactly the σ the fixtures were derived from (read back, stated in FIXTURE_SIGMA), with key class i at seat i"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.fixtureWorld(n)
			assert(
				Deep.equal(w.assignment.sigma, Contract.FIXTURE_SIGMA[n]),
				`n = {n}: Ring.assign at seed {Contract.FIXTURE_RING_SEED} gives σ = {Deep.show(
					w.assignment.sigma
				)}, the fixtures assume {Deep.show(Contract.FIXTURE_SIGMA[n])}`
			)
			for i, p in w.assignment.players do
				assert(
					Deep.equal(w.assignment.keyClasses[p], { i }),
					`n = {n}: {p} holds {Deep.show(w.assignment.keyClasses[p])}, the fixtures assume class {i}`
				)
			end
		end
	end,

	["fixtures: the n = 4 ring's non-adjacent class pairs are exactly {1,2} and {3,4}, as the valid fixture's finale relies on"] = function()
		local w = Contract.fixtureWorld(4)
		local nonAdjacent: { string } = {}
		for a = 1, 4 do
			for b = a + 1, 4 do
				local ha = Contract.holderOf(w.assignment, a) :: string
				local hb = Contract.holderOf(w.assignment, b) :: string
				if not Contract.ringNeighbours(w.assignment, ha, hb) then
					table.insert(nonAdjacent, `{a},{b}`)
				end
			end
		end
		assert(
			Deep.equal(nonAdjacent, { "1,2", "3,4" }),
			`non-adjacent class pairs at n = 4 are {Deep.show(nonAdjacent)}`
		)
	end,

	["fixtures: the valid steps at n = 4, 5 and 6 trip no clause in the test's own checker, and their finale participants are four distinct players"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local w = Contract.fixtureWorld(n)
			local s = Contract.validSteps(n)
			local found = check(s, w.layout, w.placement, w.assignment, TUNING)
			assert(
				#found == 0,
				`n = {n}: the valid fixture is not valid: {table.concat(found, "; ")}`
			)
			local who = Contract.finaleParticipants(s, w.placement, w.assignment)
			local distinct: { [string]: boolean } = {}
			for _, p in who do
				distinct[p :: string] = true
			end
			assert(
				#sortedKeys(distinct) == 4,
				`n = {n}: finale participants {Deep.show(who)} are not four distinct players`
			)
		end
	end,

	["fixtures: each hand-built violation trips exactly its expected head(s) in the test's own checker, every string has the Contract's shape, and every token not listed as inseparable has a sole fixture"] = function()
		local fixtures = Contract.violationFixtures()
		assert(#fixtures >= 15, `only {#fixtures} violation fixtures`)
		local problems: { string } = {}
		local covered: { [string]: boolean } = {}
		for _, v in fixtures do
			local w = Contract.fixtureWorld(v.n)
			local found = check(v.steps, w.layout, w.placement, w.assignment, TUNING)
			local parsed = Contract.parseTokens(found)
			if #parsed.malformed > 0 then
				table.insert(
					problems,
					`{v.name}: our checker emitted malformed {Deep.show(parsed.malformed)}`
				)
			end
			if not Deep.equal(parsed.tokens, v.expect) then
				table.insert(
					problems,
					`{v.name}: our checker reports {Deep.show(parsed.tokens)}, the fixture expects {Deep.show(
						v.expect
					)}: {table.concat(found, " | ")}`
				)
			end
			if #v.expect == 1 then
				covered[v.expect[1]] = true
			end
		end
		for _, token in Contract.TOKENS do
			if not covered[token] and Contract.NO_SOLE_FIXTURE[token] == nil then
				table.insert(problems, `no single-head fixture produces {token} alone`)
			end
			if covered[token] and Contract.NO_SOLE_FIXTURE[token] ~= nil then
				table.insert(problems, `{token} is listed as inseparable but has a sole fixture`)
			end
		end
		assert(
			#problems == 0,
			`the violation fixtures are not attributable:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: the empty Steps is reported under shape by the test's own checker without raising"] = function()
		local w = Contract.fixtureWorld(4)
		local found = check(Contract.emptySteps(), w.layout, w.placement, w.assignment, TUNING)
		local parsed = Contract.parseTokens(found)
		assert(#parsed.malformed == 0, `malformed: {Deep.show(parsed.malformed)}`)
		assert(
			table.find(parsed.tokens, "INV_balanced_steps:shape") ~= nil,
			`the empty Steps reported {Deep.show(parsed.tokens)}, no shape`
		)
	end,

	["needles: parseTokens accepts only `<INV>:<token> ` heads, so a head inside other text or with the wrong token does not satisfy it"] = function()
		local parsed = Contract.parseTokens({
			"INV_finale:ring the holders are neighbours",
			"INV_finale:ring",
			"INV_finale:rings x",
			"the candidate failed INV_finale:ring ",
			"INV_finale: ring",
			"INV_k_essential:turn\tp1",
			"INV_k_essential:read p2",
		})
		assert(
			Deep.equal(parsed.tokens, { "INV_finale:ring", "INV_k_essential:read" }),
			`expected exactly two well-formed heads, got {Deep.show(parsed.tokens)}`
		)
		assert(
			#parsed.malformed == 5,
			`expected 5 malformed strings, got {#parsed.malformed}: {Deep.show(parsed.malformed)}`
		)
	end,

	--[[ ================================================================
	     AC-6 acceptance.
	     ================================================================ ]]

	["AC-6 control: a draw that picks the finale pair blind to ring adjacency and room distance is rejected only under INV_finale, and falls below the 0.25 floor at n = 4 (measured: see the run log)"] = function()
		rejectionsOnly(
			Stubs.finaleBlind,
			"the finale-blind draw",
			{ "INV_finale:rooms", "INV_finale:ring" }
		)
		local stats = Contract.acceptance(Stubs.finaleBlind, check, 4)
		print(`        [measured] finale-blind acceptance: {Contract.describeAcceptance(stats)}`)
		assert(
			stats.rate < Contract.ACCEPTANCE_FLOOR,
			`the finale-blind draw is accepted at {string.format("%.4f", stats.rate)} at n = 4, not below the floor {Contract.ACCEPTANCE_FLOOR} - STOP and report this number rather than tuning the stub`
		)
		local message = refuses(function()
			Contract.assertAcceptance(Stubs.finaleBlind, check, 4)
		end, "the finale-blind draw must fail AC-6 at n = 4")
		names(message, "AC-6", "the finale-blind draw fails")
		names(message, "below the floor", "the finale-blind draw fails")
		for _, n in { 5, 6 } do
			local other = Contract.acceptance(Stubs.finaleBlind, check, n)
			print(
				`        [measured] finale-blind acceptance: {Contract.describeAcceptance(other)}`
			)
		end
	end,

	--[[ ================================================================
	     AC-7 setting pools.
	     ================================================================ ]]

	["AC-7 control: a draw that prefers requiredSetting 1 when choosing steps fails the step pool or the decoy pool at n = 4, 5 and 6, with setting 1 over-represented among steps (measured: see the run log)"] = function()
		rejectionsOnly(
			Stubs.preferLowSetting,
			"the prefer-low draw",
			{ "INV_finale:rooms", "INV_finale:ring" }
		)
		local d = TUNING.instance.dial_settings
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.settingPools(Stubs.preferLowSetting, check, n)
			print(`        [measured] prefer-low pools: {Contract.describePools(stats)}`)
			assert(
				not stats.capped,
				`n = {n}: the prefer-low draw hit the seed cap; the defect is bias, not acceptance`
			)
			assert(
				stats.step.maxValue == 1 and stats.step.max > 1 / d + Contract.SETTING_TOLERANCE,
				`n = {n}: setting 1 is at {string.format("%.4f", stats.step.frequencies[1])} among steps, expected well above {1 / d + Contract.SETTING_TOLERANCE}`
			)
			assert(
				stats.decoy.minValue == 1 and stats.decoy.min < 1 / d - Contract.SETTING_TOLERANCE,
				`n = {n}: setting 1 is at {string.format("%.4f", stats.decoy.frequencies[1])} among decoys, expected well below {1 / d - Contract.SETTING_TOLERANCE}`
			)
			local message = refuses(function()
				Contract.assertSettingPools(Stubs.preferLowSetting, check, n)
			end, `the prefer-low draw must fail AC-7 at n = {n}`)
			names(message, "AC-7", "the prefer-low draw fails")
			names(message, "not uniform", "the prefer-low draw fails")
		end
	end,

	["AC-7 control: a draw that never produces a valid candidate reaches the seed cap with empty pools and fails naming the cap (n = 4)"] = function()
		local stats = Contract.settingPools(Stubs.neverValid, check, 4)
		assert(stats.capped, "the never-valid draw did not hit the cap")
		assert(
			stats.seedsUsed == Contract.POOL_SEED_CAP and stats.accepted == 0,
			`the never-valid draw used {stats.seedsUsed} seeds and had {stats.accepted} accepted`
		)
		local message = refuses(function()
			Contract.assertSettingPools(Stubs.neverValid, check, 4)
		end, "the never-valid draw must fail AC-7's cap clause")
		names(message, "AC-7", "the never-valid draw fails")
		names(message, "seed cap", "the never-valid draw fails")
	end,

	["AC-7 positive control: the reference draw's step and decoy pools each hold at least 16,000 settings within the cap and lie within 1/dial_settings ± 0.02 at n = 4, 5 and 6 (measured: see the run log)"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.assertSettingPools(Stubs.reference, check, n)
			print(`        [measured] reference pools: {Contract.describePools(stats)}`)
			assert(
				stats.step.count >= Contract.POOL_MIN and stats.decoy.count >= Contract.POOL_MIN,
				`n = {n}: pools hold {stats.step.count} and {stats.decoy.count}`
			)
		end
	end,
}
