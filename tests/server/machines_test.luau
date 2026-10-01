--!strict
--[[
	GEN-002: machines are placed with tags distinct within each key class and
	a required setting each. AC-1 through AC-6, applied to the real
	`src/server/facility/Machines.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `layout_test.luau` does. In RED it does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering six criteria. Per-criterion failures say which
	behaviours are missing, which is what GREEN needs. It is not a skip: every
	test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS, STATISTICS AND FIXTURES LIVE IN `tests/helpers/PlacementContract.luau`
	and are exercised against deliberately wrong generators in
	`tests/server/machines_controls_test.luau`. That file is where each
	statistic is OBSERVED to reject its control and accept a reference - which
	matters in RED, because the pcall above means not one assertion in THIS
	file executes until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`):
	  * AC-1, AC-2, AC-3, AC-5's formula and every `check` token are settled:
	    the sweeps re-derive each invariant with the helper's own checker
	    before asking `check`; the fixtures are hand-built on a hand-built
	    layout with hand-written expected tokens; positions are the Contract's
	    formula over `room_pitch_studs`.
	  * AC-4's frequency, AC-5's spacing and AC-6's coverage are oracle-free
	    statistics with negative controls; their sample sizes and bands are the
	    Lead PO's, verbatim, and are not to be moved in GREEN.

	WHAT THIS FILE DOES NOT PIN: which classes a given seed gives the extra
	step (the Contract forbids it), how machines are spread over rooms beyond
	INV_room_capacity, the text after a `check` head, and how many draws each
	sub-stream takes.
]]

local Contract = require("../helpers/PlacementContract")
local Deep = require("../helpers/Deep")

local TUNING = Contract.TUNING

local loaded, loadResult = pcall(require, "../../src/server/facility/Machines")

local function Machines(): any
	assert(loaded, `src/server/facility/Machines.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- One sweep per n, shared by every test in this file.
local sweepCache: { [number]: { Contract.Placement } } = {}

local function placementsFor(n: number): { Contract.Placement }
	local cached = sweepCache[n]
	if cached == nil then
		cached = Contract.sweep(Machines().generate, n, Contract.SWEEP_SEEDS)
		sweepCache[n] = cached
	end
	return cached
end

-- The helper's own violations with the given invariant prefix, over every n
-- and seed, as "n = N seed S: ..." lines. Capped so a wholesale failure is a
-- readable report rather than a wall.
local function sweepViolations(prefix: string): { string }
	local problems: { string } = {}
	for _, n in Contract.CLASS_COUNTS do
		local classes = Contract.classesFor(n)
		for seed, placement in placementsFor(n) do
			local found = Contract.withPrefix(
				Contract.violations(placement, Contract.layoutFor(seed), classes, TUNING),
				prefix
			)
			for _, v in found do
				table.insert(problems, `n = {n} seed {seed}: {v}`)
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

local function probeMachine(room: number, slot: number): Contract.Machine
	return { id = 1, room = room, slot = slot, keyClass = 1, tag = 1, requiredSetting = 1 }
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Machines exports generate, check and positionOf as plain field functions"] = function()
		local M = Machines()
		local missing: { string } = {}
		for _, name in { "generate", "check", "positionOf" } do
			if typeof(M[name]) ~= "function" then
				table.insert(missing, `Machines.{name} is {typeof(M[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's three exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract: generate returns plain data - exactly the fields machines and stepsPerClass, each machine exactly { id, room, slot, keyClass, tag, requiredSetting }, all numbers"] = function()
		local placement = Machines().generate(
			Contract.rngFor(1),
			Contract.layoutFor(1),
			Contract.classesFor(4),
			TUNING
		)
		assert(typeof(placement) == "table", `generate returned {typeof(placement)}`)
		assert(
			Deep.equal(sortedKeys(placement), { "machines", "stepsPerClass" }),
			`the Placement carries fields {Deep.show(sortedKeys(placement))}; the Contract names exactly machines and stepsPerClass`
		)
		assert(#placement.machines > 0, "generate returned no machines")
		for i, m in placement.machines do
			assert(
				Deep.equal(
					sortedKeys(m),
					{ "id", "keyClass", "requiredSetting", "room", "slot", "tag" }
				),
				`machines[{i}] has fields {Deep.show(sortedKeys(m))}, expected id, keyClass, requiredSetting, room, slot, tag`
			)
			for _, field in { "id", "room", "slot", "keyClass", "tag", "requiredSetting" } do
				assert(
					typeof(m[field]) == "number",
					`machines[{i}].{field} is {typeof(m[field])}, expected number`
				)
			end
		end
		for c, s in pairs(placement.stepsPerClass) do
			assert(
				typeof(c) == "number" and typeof(s) == "number",
				`stepsPerClass has entry [{tostring(c)}] = {tostring(s)}; expected number keys and values`
			)
		end
	end,

	["Contract: generate derives exactly the labels counts, rooms, tags and settings from the rng it is handed, once each, and draws from it directly not at all"] = function()
		for _, n in Contract.CLASS_COUNTS do
			local rng, record = Contract.recordingRng(7)
			Machines().generate(rng, Contract.layoutFor(7), Contract.classesFor(n), TUNING)
			local labels = table.clone(record.labels)
			table.sort(labels)
			assert(
				Deep.equal(labels, Contract.DERIVE_LABELS),
				`n = {n}: generate derived {Deep.show(record.labels)}; the Contract names exactly counts, rooms, tags and settings`
			)
			assert(
				record.directDraws == 0,
				`n = {n}: generate drew {record.directDraws} time(s) from the parent rng directly`
			)
		end
	end,

	["Contract: generate, check and positionOf never mutate the layout, the classes or the placement they are handed"] = function()
		local M = Machines()
		local layout = Contract.layoutFor(11)
		local classes = Contract.classesFor(5)
		local layoutBefore = Contract.snapshot(layout)
		local classesBefore = Contract.snapshot(classes)
		local placement = M.generate(Contract.rngFor(11), layout, classes, TUNING)
		local placementBefore = Contract.snapshot(placement)
		M.check(placement, layout, classes, TUNING)
		for _, m in placement.machines do
			M.positionOf(layout, m, TUNING)
		end
		assert(
			Deep.equal(layoutBefore, layout),
			`a call mutated the layout:\n{Deep.diff(layoutBefore, layout)}`
		)
		assert(
			Deep.equal(classesBefore, classes),
			`a call mutated the classes list:\n{Deep.diff(classesBefore, classes)}`
		)
		assert(
			Deep.equal(placementBefore, placement),
			`check or positionOf mutated the placement:\n{Deep.diff(placementBefore, placement)}`
		)
	end,

	["Contract: the same rng seed, layout and classes generate deep-equal placements twice, at n = 4, 5 and 6"] = function()
		local M = Machines()
		for _, n in Contract.CLASS_COUNTS do
			local classes = Contract.classesFor(n)
			for _, seed in { 1, 2, 500, 1000 } do
				local layout = Contract.layoutFor(seed)
				local a = M.generate(Contract.rngFor(seed), layout, classes, TUNING)
				local b = M.generate(Contract.rngFor(seed), layout, classes, TUNING)
				assert(
					Deep.equal(a, b),
					`n = {n} seed {seed} generated two different placements:\n{Deep.diff(a, b)}`
				)
			end
		end
	end,

	["Contract: across the sweep, machines[i].id == i and ids run in strictly ascending (room, slot) order"] = function()
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			for seed, placement in placementsFor(n) do
				for _, v in Contract.orderProblems(placement) do
					table.insert(problems, `n = {n} seed {seed}: {v}`)
				end
				if #problems > 20 then
					break
				end
			end
		end
		assert(
			#problems == 0,
			`machines are not listed as the Contract says:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: for n in {4, 5, 6} and seeds 1..1000, stepsPerClass has key set exactly 1..n, each value floor(procedure_length / n) or ceil, summing to procedure_length, and every class has actuator_redundancy × its step count machines, actuator_count in all - by the test's own checker"] = function()
		local problems = sweepViolations("INV_class_machines:")
		assert(
			#problems == 0,
			`INV_class_machines is broken on generated placements:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-1: for n in {4, 5, 6} and seeds 1..1000, Machines.check returns {} on the generated placement"] = function()
		local M = Machines()
		local problems: { string } = {}
		for _, n in Contract.CLASS_COUNTS do
			local classes = Contract.classesFor(n)
			for seed, placement in placementsFor(n) do
				local report = M.check(placement, Contract.layoutFor(seed), classes, TUNING)
				assert(
					typeof(report) == "table",
					`n = {n} seed {seed}: check returned {typeof(report)}`
				)
				if #report > 0 then
					table.insert(problems, `n = {n} seed {seed}: {table.concat(report, " | ")}`)
				end
				if #problems > 20 then
					break
				end
			end
		end
		assert(
			#problems == 0,
			`Machines.check reports violations on its own placements:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-1 control: check reports INV_class_machines:count for a hand-built placement that gives one class 5 machines (and, four tags being too few for five, INV_tags_distinct_in_class:tag)"] = function()
		local M = Machines()
		for _, v in Contract.violationFixtures() do
			if string.find(v.name, "AC-1's control", 1, true) ~= nil then
				local report =
					M.check(v.placement, Contract.FIXTURE_LAYOUT, Contract.classesFor(v.n), TUNING)
				local parsed = Contract.parseTokens(report)
				assert(
					#parsed.malformed == 0,
					`{v.name}: check returned strings that do not start with a Contract head and a space: {Deep.show(
						parsed.malformed
					)}`
				)
				assert(
					Deep.equal(parsed.tokens, v.expect),
					`{v.name}: check reported {Deep.show(parsed.tokens)}, expected exactly {Deep.show(
						v.expect
					)}: {Deep.show(report)}`
				)
				return
			end
		end
		error("no fixture is marked as AC-1's control")
	end,

	["check tokens: every hand-built violation is reported under exactly its own head(s) - steps, count, room count, slot, tag, setting - as `<INV>:<token> `, and nothing else"] = function()
		local M = Machines()
		local problems: { string } = {}
		for _, v in Contract.violationFixtures() do
			local report =
				M.check(v.placement, Contract.FIXTURE_LAYOUT, Contract.classesFor(v.n), TUNING)
			if typeof(report) ~= "table" then
				table.insert(problems, `{v.name}: check returned {typeof(report)}`)
				continue
			end
			local parsed = Contract.parseTokens(report)
			if #parsed.malformed > 0 then
				table.insert(
					problems,
					`{v.name}: malformed strings {Deep.show(parsed.malformed)} (a head, then a space, then text)`
				)
			end
			if not Deep.equal(parsed.tokens, v.expect) then
				table.insert(
					problems,
					`{v.name}: reported {Deep.show(parsed.tokens)}, expected exactly {Deep.show(
						v.expect
					)}: {Deep.show(report)}`
				)
			end
		end
		assert(
			#problems == 0,
			`check does not report what the Contract's table says:\n{table.concat(problems, "\n")}`
		)
	end,

	["check: returns {} for the hand-built valid placements at n = 4, 5 and 6"] = function()
		local M = Machines()
		for _, n in Contract.CLASS_COUNTS do
			local report = M.check(
				Contract.validPlacement(n),
				Contract.FIXTURE_LAYOUT,
				Contract.classesFor(n),
				TUNING
			)
			assert(
				Deep.equal(report, {}),
				`n = {n}: check reported {Deep.show(report)} on a valid hand-built placement`
			)
		end
	end,

	--[[ AC-2 ]]

	["AC-2: for n in {4, 5, 6} and seeds 1..1000, every room holds between machines_per_room_min and machines_per_room_max machines, each in a distinct slot 1..machine_slots_per_room of a layout room - by the test's own checker"] = function()
		local problems = sweepViolations("INV_room_capacity:")
		assert(
			#problems == 0,
			`INV_room_capacity is broken on generated placements:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ AC-3 ]]

	["AC-3: for n in {4, 5, 6} and seeds 1..1000, tags are pairwise distinct within each class and each in 1..tag_alphabet_size - by the test's own checker"] = function()
		local problems = sweepViolations("INV_tags_distinct_in_class:")
		assert(
			#problems == 0,
			`INV_tags_distinct_in_class is broken on generated placements:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	--[[ AC-4 ]]

	["AC-4: at n = 4 over seeds 1..1000, every machine has a requiredSetting that is an integer in 1..dial_settings, and each value's pooled frequency lies within 1/dial_settings ± 0.02"] = function()
		Contract.assertSettingsUniform(Machines().generate, 4)
	end,

	["AC-4: at n = 5 over seeds 1..1000, every machine has a requiredSetting that is an integer in 1..dial_settings, and each value's pooled frequency lies within 1/dial_settings ± 0.02"] = function()
		Contract.assertSettingsUniform(Machines().generate, 5)
	end,

	["AC-4: at n = 6 over seeds 1..1000, every machine has a requiredSetting that is an integer in 1..dial_settings, and each value's pooled frequency lies within 1/dial_settings ± 0.02"] = function()
		Contract.assertSettingsUniform(Machines().generate, 6)
	end,

	--[[ AC-5 ]]

	["AC-5: positionOf returns exactly { x, y, z } = room centre ((column − 1) × pitch, 0, (row − 1) × pitch) plus the slot's quadrant offset ± pitch / 4 on x and z - slot 1 (−,−), 2 (+,−), 3 (−,+), 4 (+,+) - on every room and slot of the square and plus fixtures"] = function()
		local M = Machines()
		local problems: { string } = {}
		for _, item in
			{
				{ name = "square", layout = Contract.FIXTURE_LAYOUT },
				{ name = "plus", layout = Contract.PLUS_LAYOUT },
			}
		do
			for _, room in item.layout.rooms do
				for slot = 1, TUNING.instance.machine_slots_per_room do
					local got = M.positionOf(item.layout, probeMachine(room.id, slot), TUNING)
					local want = Contract.expectedPosition(item.layout, room.id, slot, TUNING)
					if
						typeof(got) ~= "table" or not Deep.equal(sortedKeys(got), { "x", "y", "z" })
					then
						table.insert(
							problems,
							`{item.name} room {room.id} slot {slot}: positionOf returned {Deep.show(
								got
							)}, expected a table with exactly x, y, z`
						)
					elseif not Deep.equal(got, want) then
						table.insert(
							problems,
							`{item.name} room {room.id} at ({room.column}, {room.row}) slot {slot}: positionOf = {Deep.show(
								got
							)}, expected {Deep.show(want)}`
						)
					end
				end
			end
		end
		assert(
			#problems == 0,
			`positions disagree with the Contract's formula:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-5: across every generated placement at n = 4, 5 and 6, any two machines are at least machine_spacing_min_studs apart horizontally through positionOf"] = function()
		local M = Machines()
		Contract.assertSpacing(M.positionOf, Contract.sweepItems(M.generate), TUNING)
	end,

	--[[ AC-6 ]]

	["AC-6: at n = 5 over seeds 1..1000, every class receives the extra step in some seeds, and exactly procedure_length mod 5 classes do per seed"] = function()
		Contract.assertExtraStepCoverage(Machines().generate, 5)
	end,

	["AC-6: at n = 6 over seeds 1..1000, every class receives the extra step in some seeds, and exactly procedure_length mod 6 classes do per seed"] = function()
		Contract.assertExtraStepCoverage(Machines().generate, 6)
	end,
}
