--!strict
--[[
	The negative controls for GEN-002, and the proof that each statistic and
	each fixture in `tests/helpers/PlacementContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `src/server/facility/
	Machines.luau` does not exist, every test in `tests/server/machines_test.luau`
	fails before its assertion runs, and so not one of that file's statistics
	has been observed to accept or reject anything. These controls need only
	`Rng`, `MechanicsTuning` and GEN-001's `Layout`, which are merged, so the
	numbers asserted below are MEASUREMENTS taken in RED rather than claims
	left for GREEN. The story's handoff carries them as a table.

	THREE KINDS OF CONTROL:

	  * The statistics (AC-4 frequency, AC-5 spacing, AC-6 coverage) are each
	    shown to REJECT the generator the criterion names and to ACCEPT the
	    reference. A statistic that rejects everything is indistinguishable
	    from a broken one, and the acceptance half is the one that is easy to
	    leave out.
	  * The hand-built fixtures (the valid placements, the violation
	    placements) are run through this file's own checker. A fixture whose
	    expected token list is wrong fails HERE, in RED, where the fix is a
	    fixture - not in GREEN, where it would read as a defect in `Machines`.
	  * The hand-built fixtures' ASSUMPTIONS about the shipped constants are
	    checked against the constants as read, so a tuning change fails with a
	    message naming the fixture rather than a puzzle in `check`.

	Every control is also held to the checks it SHOULD pass, so that a control
	that fires is attributable to its one defect.
]]

local Contract = require("../helpers/PlacementContract")
local Deep = require("../helpers/Deep")
local Stubs = require("../helpers/PlacementStubs")

local TUNING = Contract.TUNING

local function refuses(check: () -> (), what: string): string
	local ok, err = pcall(check)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

-- Every invariant and the listing rule over a generator, our own oracle only,
-- for every n. `allow` is an invariant prefix whose violations are the
-- control's one intended defect and are not counted.
local function sweepIsValid(generate: Contract.Generate, who: string, allow: string?)
	local problems: { string } = {}
	for _, n in Contract.CLASS_COUNTS do
		local classes = Contract.classesFor(n)
		for seed, placement in Contract.sweep(generate, n, Contract.SWEEP_SEEDS) do
			for _, v in Contract.violations(placement, Contract.layoutFor(seed), classes, TUNING) do
				if allow == nil or string.sub(v, 1, #allow) ~= allow then
					table.insert(problems, `n = {n} seed {seed}: {v}`)
				end
			end
			for _, v in Contract.orderProblems(placement) do
				table.insert(problems, `n = {n} seed {seed}: {v}`)
			end
			if #problems > 10 then
				break
			end
		end
	end
	assert(#problems == 0, `{who} breaks an invariant:\n{table.concat(problems, "\n")}`)
end

return {
	--[[ ================================================================
	     The reference. Everything below is this generator with one defect.
	     ================================================================ ]]

	["baseline: the reference generator satisfies INV_class_machines, INV_room_capacity, INV_tags_distinct_in_class, INV_settings_uniform's shape and the listing rule on every seed 1..1000 at n = 4, 5 and 6"] = function()
		sweepIsValid(Stubs.reference, "the reference generator")
	end,

	["baseline: the reference generator is deterministic, derives exactly counts, rooms, tags and settings, and draws nothing directly"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local classes = Contract.classesFor(n)
			for _, seed in { 1, 2, 77, 1000 } do
				local layout = Contract.layoutFor(seed)
				local a = Stubs.reference(Contract.rngFor(seed), layout, classes, TUNING)
				local b = Stubs.reference(Contract.rngFor(seed), layout, classes, TUNING)
				assert(
					Deep.equal(a, b),
					`n = {n} seed {seed} generated two different placements:\n{Deep.diff(a, b)}`
				)
			end
			local rng, record = Contract.recordingRng(7)
			Stubs.reference(rng, Contract.layoutFor(7), classes, TUNING)
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

	["fixtures: the hand-drawn placements assume the shipped constants - actuator_count machines, room_count rooms, slots within machine_slots_per_room, tag_alphabet_size tags, dial_settings positions, procedure_length steps"] = function()
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
		expect("machines", a.machines, t.actuator_count)
		expect("rooms", a.rooms, t.room_count)
		expect("tags", a.tags, t.tag_alphabet_size)
		expect("dial settings", a.dialSettings, t.dial_settings)
		expect("procedure length", a.procedureLength, t.procedure_length)
		if a.slots > t.machine_slots_per_room then
			table.insert(
				problems,
				`slots: the fixtures use slot {a.slots}; machine_slots_per_room is {t.machine_slots_per_room}`
			)
		end
		-- The smallest fixture room holds 2 machines and the largest 3; the
		-- empty-room control needs room 5 to take 4.
		if t.machines_per_room_min > 2 or t.machines_per_room_max < 4 then
			table.insert(
				problems,
				`room capacity: the fixtures hold 2..3 per room (4 in one control); the tuning allows {t.machines_per_room_min}..{t.machines_per_room_max}`
			)
		end
		assert(
			#problems == 0,
			`the hand-built fixtures no longer match the tuning:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: the valid placements at n = 4, 5 and 6 trip no clause in the test's own checker and are listed in (room, slot) order"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local p = Contract.validPlacement(n)
			local found =
				Contract.violations(p, Contract.FIXTURE_LAYOUT, Contract.classesFor(n), TUNING)
			assert(
				#found == 0,
				`n = {n}: the valid fixture is not valid: {table.concat(found, "; ")}`
			)
			local order = Contract.orderProblems(p)
			assert(
				#order == 0,
				`n = {n}: the valid fixture is mislisted: {table.concat(order, "; ")}`
			)
			assert(
				#p.machines == TUNING.instance.actuator_count,
				`n = {n}: the valid fixture has {#p.machines} machines`
			)
		end
	end,

	["fixtures: each hand-built violation trips exactly its expected head(s) in the test's own checker, and every string has the Contract's shape"] = function()
		local fixtures = Contract.violationFixtures()
		assert(#fixtures >= 15, `only {#fixtures} violation fixtures`)
		local problems: { string } = {}
		local covered: { [string]: boolean } = {}
		for _, v in fixtures do
			local found = Contract.violations(
				v.placement,
				Contract.FIXTURE_LAYOUT,
				Contract.classesFor(v.n),
				TUNING
			)
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
			if not covered[token] then
				table.insert(problems, `no single-head fixture produces {token} alone`)
			end
		end
		assert(
			#problems == 0,
			`the violation fixtures are not attributable:\n{table.concat(problems, "\n")}`
		)
	end,

	["needles: parseTokens accepts only `<INV>:<token> ` heads, so a head inside other text or with the wrong token does not satisfy it"] = function()
		local parsed = Contract.parseTokens({
			"INV_class_machines:count class 1 has 5 machines",
			"INV_class_machines:count",
			"INV_class_machines:counts x",
			"the placement failed INV_class_machines:count ",
			"INV_class_machines: count",
			"INV_room_capacity:slot\tmachine 2",
		})
		assert(
			Deep.equal(parsed.tokens, { "INV_class_machines:count" }),
			`expected exactly one well-formed head, got {Deep.show(parsed.tokens)}`
		)
		assert(
			#parsed.malformed == 5,
			`expected 5 malformed strings, got {#parsed.malformed}: {Deep.show(parsed.malformed)}`
		)
	end,

	--[[ ================================================================
	     AC-4 settings.
	     ================================================================ ]]

	["AC-4 control: a generator that leaves the last machine of each class without a setting has n missing per seed and fails the first clause"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.settingStats(Stubs.lastOfClassUnset, n, Contract.SWEEP_SEEDS)
			assert(
				stats.missing == n * Contract.SWEEP_SEEDS,
				`n = {n}: {stats.missing} missing settings, expected {n * Contract.SWEEP_SEEDS}`
			)
			local message = refuses(function()
				Contract.assertSettingsUniform(Stubs.lastOfClassUnset, n)
			end, `the last-of-class-unset generator must fail AC-4 at n = {n}`)
			names(message, "AC-4", "the last-of-class-unset generator fails")
			names(message, "without a setting", "the last-of-class-unset generator fails")
			print(`        [measured] last-of-class unset: {Contract.describeSettingStats(stats)}`)
		end
		sweepIsValid(
			Stubs.lastOfClassUnset,
			"the last-of-class-unset generator",
			"INV_settings_uniform:"
		)
	end,

	["AC-4 control: a generator that draws settings from 1..dial_settings − 1 puts setting dial_settings at exactly 0 and fails the frequency check"] = function()
		local d = TUNING.instance.dial_settings
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.settingStats(Stubs.settingsOneFewer, n, Contract.SWEEP_SEEDS)
			assert(
				stats.missing == 0,
				`n = {n}: {stats.missing} settings out of range; the defect is frequency, not shape`
			)
			assert(
				stats.counts[d] == 0,
				`n = {n}: setting {d} appeared {stats.counts[d]} times, expected exactly 0`
			)
			assert(
				stats.minValue == d,
				`n = {n}: the rarest setting is {stats.minValue}, expected {d}`
			)
			local message = refuses(function()
				Contract.assertSettingsUniform(Stubs.settingsOneFewer, n)
			end, `the one-fewer generator must fail AC-4 at n = {n}`)
			names(message, "AC-4", "the one-fewer generator fails")
			names(message, "not uniform", "the one-fewer generator fails")
			print(`        [measured] one-fewer settings: {Contract.describeSettingStats(stats)}`)
		end
		sweepIsValid(Stubs.settingsOneFewer, "the one-fewer generator")
	end,

	["AC-4 positive control: the reference generator's pooled setting frequencies lie within 1/dial_settings ± 0.02 at n = 4, 5 and 6 (measured: see the run log)"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local stats = Contract.assertSettingsUniform(Stubs.reference, n)
			assert(
				stats.machines == TUNING.instance.actuator_count * Contract.SWEEP_SEEDS,
				`n = {n}: pooled {stats.machines} settings`
			)
			print(`        [measured] reference settings: {Contract.describeSettingStats(stats)}`)
		end
	end,

	--[[ ================================================================
	     AC-6 extra-step coverage.
	     ================================================================ ]]

	["AC-6 control: a generator that always gives the extra steps to classes 1..k leaves classes k+1..n at 0 and fails, at n = 5 and 6"] = function()
		for _, n in { 5, 6 } do
			local stats = Contract.extraStepCoverage(Stubs.extraToLowest, n, Contract.SWEEP_SEEDS)
			local k = stats.extraPerSeed
			local expectedNever: { number } = {}
			for c = k + 1, n do
				table.insert(expectedNever, c)
			end
			assert(
				Deep.equal(stats.never, expectedNever),
				`n = {n}: classes never given the extra step are {Deep.show(stats.never)}, expected {Deep.show(
					expectedNever
				)}`
			)
			for c = 1, k do
				assert(
					stats.tally[c] == Contract.SWEEP_SEEDS,
					`n = {n}: class {c} got the extra step in {stats.tally[c]} seeds, expected every one`
				)
			end
			local message = refuses(function()
				Contract.assertExtraStepCoverage(Stubs.extraToLowest, n)
			end, `the lowest-classes generator must fail AC-6 at n = {n}`)
			names(message, "AC-6", "the lowest-classes generator fails")
			names(message, "never received the extra step", "the lowest-classes generator fails")
			print(`        [measured] extra to lowest: {Contract.describeExtraSteps(stats)}`)
		end
		sweepIsValid(Stubs.extraToLowest, "the lowest-classes generator")
	end,

	["AC-6 positive control: the reference generator gives every class the extra step in some seeds at n = 5 and 6, and no class at n = 4 where procedure_length mod 4 is 0 (measured: see the run log)"] = function()
		for _, n in { 5, 6 } do
			local stats = Contract.assertExtraStepCoverage(Stubs.reference, n)
			print(`        [measured] reference extra steps: {Contract.describeExtraSteps(stats)}`)
		end
		local four = Contract.extraStepCoverage(Stubs.reference, 4, Contract.SWEEP_SEEDS)
		assert(
			four.extraPerSeed == TUNING.instance.procedure_length % 4,
			`n = 4 extra per seed is {four.extraPerSeed}`
		)
		if four.extraPerSeed == 0 then
			assert(
				four.total == 0,
				`n = 4: {four.total} ceil counts tallied where the split is even`
			)
		end
	end,

	--[[ ================================================================
	     AC-5 positions and spacing.
	     ================================================================ ]]

	["AC-5 geometry: the helper's expected position puts the four slots of a room at ± pitch / 4 from its centre on each axis, y = 0, each pair at least pitch / 2 apart"] = function()
		local pitch = TUNING.instance.room_pitch_studs
		local layout = Contract.FIXTURE_LAYOUT
		for _, room in layout.rooms do
			local cx, cz = (room.column - 1) * pitch, (room.row - 1) * pitch
			local positions: { Contract.Position } = {}
			for slot = 1, 4 do
				local p = Contract.expectedPosition(layout, room.id, slot, TUNING)
				assert(p.y == 0, `room {room.id} slot {slot}: y = {p.y}`)
				assert(
					math.abs(p.x - cx) == pitch / 4 and math.abs(p.z - cz) == pitch / 4,
					`room {room.id} slot {slot}: ({p.x}, {p.z}) is not ± {pitch / 4} from the centre ({cx}, {cz})`
				)
				positions[slot] = p
			end
			-- The Contract's signs: slot 1 (−,−), 2 (+,−), 3 (−,+), 4 (+,+).
			assert(positions[1].x < cx and positions[1].z < cz, "slot 1 is not (−x, −z)")
			assert(positions[2].x > cx and positions[2].z < cz, "slot 2 is not (+x, −z)")
			assert(positions[3].x < cx and positions[3].z > cz, "slot 3 is not (−x, +z)")
			assert(positions[4].x > cx and positions[4].z > cz, "slot 4 is not (+x, +z)")
			for i = 1, 4 do
				for j = i + 1, 4 do
					local d = Contract.horizontalDistance(positions[i], positions[j])
					assert(d >= pitch / 2, `room {room.id}: slots {i} and {j} are only {d} apart`)
				end
			end
		end
	end,

	["AC-5 control: a positionOf that stacks every slot on the room centre puts two machines 0 studs apart and fails"] = function()
		local items = Contract.sweepItems(Stubs.reference)
		local worst = math.huge
		for _, item in items do
			local s =
				Contract.minSpacing(Stubs.positionAtCentre, item.layout, item.placement, TUNING)
			worst = math.min(worst, s.min)
		end
		assert(
			worst == 0,
			`the centre-stacking positionOf's closest pair is {worst} apart, expected exactly 0`
		)
		local message = refuses(function()
			Contract.assertSpacing(Stubs.positionAtCentre, items, TUNING)
		end, "the centre-stacking positionOf must fail AC-5's spacing clause")
		names(message, "AC-5", "the centre-stacking positionOf fails")
		names(message, "studs apart", "the centre-stacking positionOf fails")
	end,

	["AC-5 positive control: the Contract's formula keeps every pair of the reference's machines at least machine_spacing_min_studs apart, and the closest pair is exactly pitch / 2 (measured)"] = function()
		local worst = Contract.assertSpacing(
			Stubs.referencePosition,
			Contract.sweepItems(Stubs.reference),
			TUNING
		)
		local pitch = TUNING.instance.room_pitch_studs
		assert(
			worst.min == pitch / 2,
			`the closest pair under the Contract's formula is {worst.min} apart, expected pitch / 2 = {pitch / 2} ({worst.pair})`
		)
		print(
			`        [measured] reference spacing: min {worst.min} studs over {worst.pairs} pairs ({worst.pair}); floor {TUNING.instance.machine_spacing_min_studs}`
		)
	end,
}
