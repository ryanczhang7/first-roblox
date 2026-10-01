--!strict
--[[
	GEN-001: a seeded facility layout is a connected graph of rooms with known
	distances. AC-1 through AC-6, applied to the real
	`src/server/facility/Layout.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `ring_test.luau` does. In RED it does not exist, and a bare
	top-level `require` would make this whole file a single LOAD FAIL - one
	line of red covering six criteria. Per-criterion failures say which
	behaviours are missing, which is what GREEN needs. It is not a skip: every
	test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS, STATISTICS AND FIXTURES LIVE IN `tests/helpers/LayoutContract.luau`
	and are exercised against deliberately wrong generators in
	`tests/server/layout_controls_test.luau`. That file is where each statistic
	is OBSERVED to reject its control and accept a reference - which matters in
	RED, because the pcall above means not one assertion in THIS file executes
	until GREEN writes the module. This file is where the same checks are
	applied to the real one.

	THE ORACLE PARTITION (story `## Contract`):
	  * AC-1, AC-2's first clause, AC-4, AC-5 and the `check` tokens are
	    mechanical. The sweep re-derives `INV_layout` with the helper's own
	    adjacency and BFS before asking `check`; the fixtures carry hand-written
	    matrices and spawn rooms.
	  * AC-3's 15 trees are a hand-written list; the 48 connected 6-sets are an
	    enumeration in the controls file.
	  * AC-2's variety, AC-3's uniformity and AC-6's loop rate are oracle-free
	    statistics with negative controls; their sample sizes and bands are the
	    Lead PO's, verbatim, and are not to be moved in GREEN.

	WHAT THIS FILE DOES NOT PIN: which cells a given seed produces (the Contract
	forbids it), the text after a `check` token, the error message for an
	out-of-range id, and how `generate` grows cells or walks the tree beyond
	the three derive labels it may use.
]]

local Contract = require("../helpers/LayoutContract")
local Deep = require("../helpers/Deep")
local Rng = require("../../src/shared/Rng")

local TUNING = Contract.TUNING

local loaded, loadResult = pcall(require, "../../src/server/facility/Layout")

local function Layout(): any
	assert(loaded, `src/server/facility/Layout.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- An Rng that records every label derived from it and counts every draw
-- taken from it DIRECTLY. The Contract says `generate` derives exactly
-- "cells", "tree" and "loops" and draws from nothing else.
local function recordingRng(seed: number): (Rng.Rng, { labels: { string }, directDraws: number })
	local real = Rng.fromSeed(seed)
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

-- An Rng whose `derive` raises: the Contract says `spanningTree` consumes
-- the rng it is handed directly and derives nothing.
local function nonDerivingRng(seed: number): Rng.Rng
	local real = Rng.fromSeed(seed)
	local spy = {}
	spy.nextInteger = function(_self, min: number, max: number): number
		return real:nextInteger(min, max)
	end
	spy.nextNumber = function(_self): number
		return real:nextNumber()
	end
	spy.shuffle = function<T>(_self, list: { T }): { T }
		return real:shuffle(list)
	end
	spy.derive = function(_self, label: string): Rng.Rng
		error(
			`spanningTree derived "{label}" from the rng it was handed; the Contract says it consumes that rng directly`
		)
	end
	return (spy :: any) :: Rng.Rng
end

local function generateAll(seeds: number): { Contract.Layout }
	local layouts: { Contract.Layout } = {}
	for seed = 1, seeds do
		layouts[seed] = Layout().generate(Rng.fromSeed(seed), TUNING)
	end
	return layouts
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Layout exports generate, check, distance, neighbours, spawnRoom and spanningTree as plain field functions"] = function()
		local layout = Layout()
		local missing: { string } = {}
		for _, name in
			{ "generate", "check", "distance", "neighbours", "spawnRoom", "spanningTree" }
		do
			if typeof(layout[name]) ~= "function" then
				table.insert(missing, `Layout.{name} is {typeof(layout[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's six exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract: generate returns plain data - exactly the fields rooms, doors and spawnRoom, rooms as { id, column, row }, doors as { a, b }"] = function()
		local layout = Layout().generate(Rng.fromSeed(1), TUNING)
		assert(typeof(layout) == "table", `generate returned {typeof(layout)}`)
		local extra: { string } = {}
		for key in pairs(layout) do
			if key ~= "rooms" and key ~= "doors" and key ~= "spawnRoom" then
				table.insert(extra, tostring(key))
			end
		end
		assert(
			#extra == 0,
			`the Layout value carries fields the Contract does not name: {table.concat(extra, ", ")} - a memo or a cache belongs outside the value, which AC-2 deep-equals`
		)
		assert(typeof(layout.rooms) == "table", `layout.rooms is {typeof(layout.rooms)}`)
		assert(typeof(layout.doors) == "table", `layout.doors is {typeof(layout.doors)}`)
		assert(
			typeof(layout.spawnRoom) == "number",
			`layout.spawnRoom is {typeof(layout.spawnRoom)}`
		)
		for i, room in layout.rooms do
			local keys: { string } = {}
			for key in pairs(room) do
				table.insert(keys, tostring(key))
			end
			table.sort(keys)
			assert(
				Deep.equal(keys, { "column", "id", "row" }),
				`rooms[{i}] has fields {Deep.show(keys)}, expected column, id, row`
			)
		end
		for i, door in layout.doors do
			local keys: { string } = {}
			for key in pairs(door) do
				table.insert(keys, tostring(key))
			end
			table.sort(keys)
			assert(
				Deep.equal(keys, { "a", "b" }),
				`doors[{i}] has fields {Deep.show(keys)}, expected a, b`
			)
		end
	end,

	["Contract: generate derives exactly the labels cells, tree and loops from the rng it is handed, once each, and draws from it directly not at all"] = function()
		local rng, record = recordingRng(7)
		Layout().generate(rng, TUNING)
		local labels = table.clone(record.labels)
		table.sort(labels)
		assert(
			Deep.equal(labels, { "cells", "loops", "tree" }),
			`generate derived {Deep.show(record.labels)}; the Contract names exactly cells, tree and loops`
		)
		assert(
			record.directDraws == 0,
			`generate drew {record.directDraws} time(s) from the parent rng directly`
		)
	end,

	["Contract: spanningTree consumes the rng it is handed directly and derives nothing; 1 cell gives no doors, 2 cells give the door 1-2"] = function()
		local L = Layout()
		local one = L.spanningTree(nonDerivingRng(1), { { column = 2, row = 2 } })
		assert(Deep.equal(one, {}), `one cell: expected no doors, got {Deep.show(one)}`)
		local two =
			L.spanningTree(nonDerivingRng(1), { { column = 1, row = 1 }, { column = 1, row = 2 } })
		assert(
			Deep.equal(two, { { a = 1, b = 2 } }),
			`two cells: expected the single door 1-2, got {Deep.show(two)}`
		)
		local six = L.spanningTree(nonDerivingRng(3), Deep.copy(Contract.LADDER_CELLS))
		assert(#six == 5, `six ladder cells: expected 5 doors, got {#six}: {Deep.show(six)}`)
	end,

	["Contract: generate, check, distance, neighbours and spawnRoom never mutate the layout or the cells they are handed"] = function()
		local L = Layout()
		local layout = L.generate(Rng.fromSeed(11), TUNING)
		local before = Deep.copy(layout)
		L.check(layout, TUNING)
		for a = 1, #layout.rooms do
			L.neighbours(layout, a)
			for b = 1, #layout.rooms do
				L.distance(layout, a, b)
			end
		end
		L.spawnRoom(layout)
		assert(
			Deep.equal(before, layout),
			`a query mutated the layout:\n{Deep.diff(before, layout)}`
		)

		local cells = Deep.copy(Contract.LADDER_CELLS)
		local cellsBefore = Deep.copy(cells)
		L.spanningTree(Rng.fromSeed(2), cells)
		assert(
			Deep.equal(cellsBefore, cells),
			`spanningTree mutated its cells argument:\n{Deep.diff(cellsBefore, cells)}`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: for every seed 1..1000, the generated layout satisfies INV_layout by the test's own adjacency and BFS - room_count rooms on distinct in-grid cells, ids row-major, doors grid-adjacent, a < b, sorted, no repeated pair, connected, degree ≤ 4, some pair ≥ 2 apart"] = function()
		local columns = TUNING.instance.layout_grid_columns
		local problems: { string } = {}
		for seed, layout in generateAll(Contract.SWEEP_SEEDS) do
			for _, v in Contract.violations(layout, TUNING) do
				table.insert(problems, `seed {seed}: {v}`)
			end
			for _, v in Contract.consequenceViolations(layout) do
				table.insert(problems, `seed {seed}: {v}`)
			end
			-- Row-major id order: rooms[i] sits at a strictly greater row-major
			-- cell index than rooms[i - 1].
			for i = 2, #layout.rooms do
				local prev = Contract.cellIndex(layout.rooms[i - 1], columns)
				local here = Contract.cellIndex(layout.rooms[i], columns)
				if not (here > prev) then
					table.insert(
						problems,
						`seed {seed}: rooms {i - 1} and {i} are not in row-major order (cell indices {prev}, {here})`
					)
				end
			end
			if #problems > 20 then
				break
			end
		end
		assert(
			#problems == 0,
			`INV_layout is broken on generated layouts:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-1: for every seed 1..1000, Layout.check returns {} on the generated layout"] = function()
		local L = Layout()
		local problems: { string } = {}
		for seed, layout in generateAll(Contract.SWEEP_SEEDS) do
			local report = L.check(layout, TUNING)
			assert(typeof(report) == "table", `seed {seed}: check returned {typeof(report)}`)
			if #report > 0 then
				table.insert(problems, `seed {seed}: {table.concat(report, " | ")}`)
			end
		end
		assert(
			#problems == 0,
			`Layout.check reports INV_layout violations on its own layouts:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	["AC-1 control: check reports each hand-built violation under its own clause token - cells, adjacency, connected, room_count - as `INV_layout:<token> `, and the 5-room layout under room_count alone"] = function()
		local L = Layout()
		for _, v in Contract.violationFixtures() do
			local report = L.check(v.layout, TUNING)
			assert(typeof(report) == "table", `{v.name}: check returned {typeof(report)}`)
			assert(#report > 0, `{v.name}: check returned an empty list, reporting nothing`)
			local parsed = Contract.parseTokens(report)
			assert(
				#parsed.malformed == 0,
				`{v.name}: check returned strings that do not start with \`INV_layout:<token> \` for a Contract token: {Deep.show(
					parsed.malformed
				)}`
			)
			assert(
				table.find(parsed.tokens, v.token) ~= nil,
				`{v.name}: check reported {Deep.show(parsed.tokens)} but not "{v.token}": {Deep.show(
					report
				)}`
			)
			if v.token == "room_count" then
				assert(
					Deep.equal(parsed.tokens, { "room_count" }),
					`{v.name}: the Contract says this control is otherwise valid and produces room_count and nothing else, got {Deep.show(
						parsed.tokens
					)}: {Deep.show(report)}`
				)
			end
		end
	end,

	["AC-1 control: check returns {} for the hand-built chain, square and cycle layouts"] = function()
		local L = Layout()
		for _, f in Contract.FIXTURES do
			if #f.rooms == TUNING.instance.room_count then
				local report = L.check(Contract.layoutOf(f), TUNING)
				assert(
					Deep.equal(report, {}),
					`fixture {f.name}: check reported {Deep.show(report)}`
				)
			end
		end
	end,

	--[[ AC-2 ]]

	["AC-2: the same seed and tuning generate deep-equal layouts twice"] = function()
		local L = Layout()
		for _, seed in { 1, 2, 500, 1000 } do
			local a = L.generate(Rng.fromSeed(seed), TUNING)
			local b = L.generate(Rng.fromSeed(seed), TUNING)
			assert(
				Deep.equal(a, b),
				`seed {seed} generated two different layouts:\n{Deep.diff(a, b)}`
			)
		end
	end,

	["AC-2: at least 20 distinct occupied-cell sets appear over seeds 1..1000"] = function()
		Contract.assertCellSetVariety(Layout().generate, TUNING)
	end,

	--[[ AC-3 ]]

	['AC-3: over 150,000 draws on the 2 × 3 block (draw i from Rng.fromSeed(1):derive("tree-" .. i)) all 15 spanning trees appear, each within 1/15 ± 0.004'] = function()
		Contract.assertTreeUniform(Layout().spanningTree)
	end,

	--[[ AC-4 ]]

	["AC-4: distance returns the hand-written shortest-path length for every ordered pair of the chain, square, cycle and plus fixtures, 0 on the diagonal and symmetric"] = function()
		local L = Layout()
		local problems: { string } = {}
		for _, f in Contract.FIXTURES do
			local layout = Contract.layoutOf(f)
			local n = #f.rooms
			for a = 1, n do
				for b = 1, n do
					local got = L.distance(layout, a, b)
					local want = Contract.distanceAt(f, a, b)
					if got ~= want then
						table.insert(
							problems,
							`{f.name}: distance({a}, {b}) = {tostring(got)}, expected {want}`
						)
					end
				end
			end
		end
		assert(
			#problems == 0,
			`distances disagree with the hand-written matrices:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-4: distance returns math.huge for an unreachable pair and 0 for a = b on the split fixture"] = function()
		local L = Layout()
		local layout = Contract.layoutOf(Contract.SPLIT)
		assert(
			L.distance(layout, 1, 4) == math.huge,
			`distance(1, 4) on the split is {tostring(L.distance(layout, 1, 4))}, expected math.huge`
		)
		assert(
			L.distance(layout, 6, 2) == math.huge,
			`distance(6, 2) on the split is {tostring(L.distance(layout, 6, 2))}, expected math.huge`
		)
		assert(
			L.distance(layout, 4, 4) == 0,
			`distance(4, 4) on the split is {tostring(L.distance(layout, 4, 4))}, expected 0`
		)
		assert(
			L.distance(layout, 1, 3) == 2,
			`distance(1, 3) on the split is {tostring(L.distance(layout, 1, 3))}, expected 2`
		)
	end,

	["AC-4 (Contract): distance raises for an id outside 1..#rooms - 0, 7 and 2.5 on a six-room layout - and does not raise for 1 and 6"] = function()
		local L = Layout()
		local layout = Contract.layoutOf(Contract.FIXTURES[1])
		for _, bad in { 0, 7, -1, 2.5 } do
			assert(pcall(L.distance, layout, bad, 1) == false, `distance({bad}, 1) did not raise`)
			assert(pcall(L.distance, layout, 1, bad) == false, `distance(1, {bad}) did not raise`)
		end
		assert(pcall(L.distance, layout, 1, 6), "distance(1, 6) raised on a six-room layout")
		assert(pcall(L.distance, layout, 6, 6), "distance(6, 6) raised on a six-room layout")
	end,

	["AC-4: neighbours returns each room's door-neighbours in ascending order on the chain, square, cycle and plus fixtures"] = function()
		local L = Layout()
		local problems: { string } = {}
		for _, f in Contract.FIXTURES do
			local layout = Contract.layoutOf(f)
			for id = 1, #f.rooms do
				local got = L.neighbours(layout, id)
				if not Deep.equal(f.neighbours[id], got) then
					table.insert(
						problems,
						`{f.name}: neighbours({id}) = {Deep.show(got)}, expected {Deep.show(
							f.neighbours[id]
						)}`
					)
				end
			end
		end
		assert(
			#problems == 0,
			`neighbour lists disagree with the hand-written ones:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-4: neighbours is a fresh list each call - mutating the result does not change the next answer"] = function()
		local L = Layout()
		local layout = Contract.layoutOf(Contract.FIXTURES[2])
		local first = L.neighbours(layout, 5)
		table.insert(first, 99)
		local second = L.neighbours(layout, 5)
		assert(
			Deep.equal(second, { 2, 4, 6 }),
			`after mutating a returned list, neighbours(5) = {Deep.show(second)}`
		)
	end,

	--[[ AC-5 ]]

	["AC-5: spawnRoom is the hand-derived room of least eccentricity on each fixture - 3 on the chain (tie 3/6), 2 on the square (tie 2/5), 1 on the cycle (six-way tie), 3 on the plus (unique)"] = function()
		local L = Layout()
		local problems: { string } = {}
		for _, f in Contract.FIXTURES do
			local got = L.spawnRoom(Contract.layoutOf(f))
			if got ~= f.spawnRoom then
				table.insert(
					problems,
					`{f.name}: spawnRoom = {tostring(got)}, expected {f.spawnRoom}`
				)
			end
		end
		assert(
			#problems == 0,
			`spawn rooms disagree with the hand-derived ones:\n{table.concat(problems, "\n")}`
		)
	end,

	["AC-5: across seeds 1..1000, the generated spawnRoom field equals Layout.spawnRoom(layout) and the test's own argmin of eccentricity"] = function()
		local L = Layout()
		local problems: { string } = {}
		for seed, layout in generateAll(Contract.SWEEP_SEEDS) do
			local own = Contract.spawnRoomOf(#layout.rooms, layout.doors)
			local viaModule = L.spawnRoom(layout)
			if layout.spawnRoom ~= viaModule or layout.spawnRoom ~= own then
				table.insert(
					problems,
					`seed {seed}: field {tostring(layout.spawnRoom)}, Layout.spawnRoom {tostring(
						viaModule
					)}, expected {own}`
				)
			end
			if #problems > 20 then
				break
			end
		end
		assert(
			#problems == 0,
			`spawnRoom disagrees on generated layouts:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ AC-6 ]]

	["AC-6: over seeds 1..10000, Σ(#doors − 5) / Σ(adjacent pairs − 5) lies within layout_loop_door_chance ± 0.03"] = function()
		Contract.assertLoopRate(Layout().generate, TUNING)
	end,
}
