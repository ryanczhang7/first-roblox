--!strict
--[[
	The negative controls for GEN-001, and the proof that each statistic and
	each fixture in `tests/helpers/LayoutContract.luau` means what it says.

	NOTHING HERE REQUIRES PRODUCTION CODE. In RED `src/server/facility/
	Layout.luau` does not exist, every test in `tests/server/layout_test.luau`
	fails before its assertion runs, and so not one of that file's statistics
	has been observed to accept or reject anything. These controls need only
	`Rng` and `MechanicsTuning`, which are merged, so the numbers asserted below
	are MEASUREMENTS taken in RED rather than claims left for GREEN. The story's
	handoff carries them as a table.

	THREE KINDS OF CONTROL:

	  * The statistics (AC-2 variety, AC-3 uniformity, AC-6 loop rate) are each
	    shown to REJECT the generator the criterion names and to ACCEPT the
	    reference. A statistic that rejects everything is indistinguishable from
	    a broken one, and the acceptance half is the one that is easy to leave
	    out.
	  * The settled numbers (15 ladder trees, 48 connected 6-sets) are read out
	    of the fixtures and checked for what the Contract says of them.
	  * The hand-built fixtures (AC-1's violations, AC-4's matrices, AC-5's
	    spawn rooms) are re-derived with this file's own BFS. A fixture whose
	    hand-written number is wrong fails HERE, in RED, where the fix is a
	    fixture - not in GREEN, where it would read as a defect in `Layout`.

	Every control is also held to the checks it SHOULD pass, so that a control
	that fires is attributable to its one defect.
]]

local Contract = require("../helpers/LayoutContract")
local Deep = require("../helpers/Deep")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local Stubs = require("../helpers/LayoutStubs")

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

local function fmt(x: number): string
	return string.format("%.5f", x)
end

-- Every structural check of AC-1 over a generator, our own oracle only.
local function sweepIsStructurallyValid(generate: Contract.Generate, who: string)
	local problems: { string } = {}
	for seed = 1, Contract.SWEEP_SEEDS do
		local layout = generate(Rng.fromSeed(seed), TUNING)
		for _, v in Contract.violations(layout, TUNING) do
			table.insert(problems, `seed {seed}: {v}`)
		end
		for _, v in Contract.consequenceViolations(layout) do
			table.insert(problems, `seed {seed}: {v}`)
		end
		if #problems > 10 then
			break
		end
	end
	assert(#problems == 0, `{who} breaks INV_layout:\n{table.concat(problems, "\n")}`)
end

return {
	--[[ ================================================================
	     The reference. Everything below is this generator with one defect.
	     ================================================================ ]]

	["baseline: the reference generator (growth + Wilson + loop draw) satisfies INV_layout and its consequences on every seed 1..1000"] = function()
		sweepIsStructurallyValid(Stubs.reference, "the reference generator")
	end,

	["baseline: the reference generator is deterministic in its seed"] = function()
		for _, seed in { 1, 2, 77, 1000 } do
			local a = Stubs.reference(Rng.fromSeed(seed), TUNING)
			local b = Stubs.reference(Rng.fromSeed(seed), TUNING)
			assert(
				Deep.equal(a, b),
				`seed {seed} generated two different layouts:\n{Deep.diff(a, b)}`
			)
		end
	end,

	--[[ ================================================================
	     AC-2 variety.
	     ================================================================ ]]

	["AC-2 control: a generator that always occupies the same six cells scores 1 distinct set and fails"] = function()
		local count = Contract.cellSetVariety(Stubs.constantCells, TUNING, Contract.SWEEP_SEEDS)
		assert(count == 1, `the constant-cells generator scored {count}, expected exactly 1`)
		local message = refuses(function()
			Contract.assertCellSetVariety(Stubs.constantCells, TUNING)
		end, "the constant-cells generator must fail AC-2's variety clause")
		names(message, "AC-2", "the constant-cells generator fails")
		names(message, "only 1 distinct", "the constant-cells generator fails")
		-- Its one defect is the cells; everything else about it is correct.
		sweepIsStructurallyValid(Stubs.constantCells, "the constant-cells generator")
	end,

	["AC-2 positive control: the reference generator produces at least 20 distinct cell sets over seeds 1..1000 (measured: 48, every connected 6-set)"] = function()
		local count = Contract.cellSetVariety(Stubs.reference, TUNING, Contract.SWEEP_SEEDS)
		assert(
			count >= Contract.VARIETY_MIN,
			`the reference generator scored only {count} distinct cell sets`
		)
		assert(
			count <= 48,
			`the reference generator scored {count} distinct cell sets, more than the 48 connected 6-sets that exist`
		)
		Contract.assertCellSetVariety(Stubs.reference, TUNING)
		print(`        [measured] reference variety: {count} distinct cell sets`)
	end,

	["PO-3 read-out: the 3 × 3 grid has 84 six-subsets, 48 of them connected"] = function()
		local columns = TUNING.instance.layout_grid_columns
		local rows = TUNING.instance.layout_grid_rows
		local roomCount = TUNING.instance.room_count
		local counts = Contract.connectedSubsetCount(columns, rows, roomCount)
		assert(
			counts.total == 84,
			`{counts.total} {roomCount}-subsets of the {columns} × {rows} grid, expected 84`
		)
		assert(
			counts.connected == 48,
			`{counts.connected} connected {roomCount}-subsets, expected 48 (PO-3)`
		)
	end,

	--[[ ================================================================
	     AC-3 uniformity over the 15 ladder trees.
	     ================================================================ ]]

	["AC-3 fixture: the hand-listed ladder trees are 15 distinct spanning trees of the 2 × 3 block"] = function()
		local n = #Contract.LADDER_CELLS
		local ladderEdge: { [string]: boolean } = {}
		for _, e in Contract.LADDER_EDGES do
			ladderEdge[`{e.a}-{e.b}`] = true
		end
		assert(
			#Contract.LADDER_EDGES == 7,
			`the ladder has {#Contract.LADDER_EDGES} edges, expected 7`
		)
		assert(
			#Contract.LADDER_TREES == 15,
			`{#Contract.LADDER_TREES} trees are listed, expected 15`
		)
		local seen: { [string]: boolean } = {}
		for i, t in Contract.LADDER_TREES do
			local key = Contract.doorKey(t)
			assert(not seen[key], `tree {i} ({key}) is listed twice`)
			seen[key] = true
			assert(#t == n - 1, `tree {i} ({key}) has {#t} edges, expected {n - 1}`)
			for j, d in t do
				assert(
					ladderEdge[`{d.a}-{d.b}`],
					`tree {i} edge {j} ({d.a}-{d.b}) is not a ladder edge`
				)
				if j > 1 then
					local p = t[j - 1]
					assert(
						p.a < d.a or (p.a == d.a and p.b < d.b),
						`tree {i} ({key}) is not sorted by (a, b)`
					)
				end
			end
			for id, dist in Contract.bfs(n, t, 1) do
				assert(dist ~= math.huge, `tree {i} ({key}) does not reach cell {id}`)
			end
		end
		-- Every edge pair the comment says is removable is, and no other: the
		-- 15 keys above are exactly the 5-subsets of the 7 edges that are trees.
		local treeCount = 0
		for i = 1, 7 do
			for j = i + 1, 7 do
				local kept: { Contract.Door } = {}
				for k, e in Contract.LADDER_EDGES do
					if k ~= i and k ~= j then
						table.insert(kept, e)
					end
				end
				local connected = true
				for _, dist in Contract.bfs(n, kept, 1) do
					if dist == math.huge then
						connected = false
					end
				end
				if connected then
					treeCount += 1
					assert(
						seen[Contract.doorKey(kept)],
						`spanning tree {Contract.doorKey(kept)} is missing from the hand list`
					)
				end
			end
		end
		assert(treeCount == 15, `{treeCount} of the 21 five-edge subsets are trees, expected 15`)
	end,

	["AC-3 control: a breadth-first tree from cell 1 scores 1.0 on one tree and 0 on fourteen, and fails"] = function()
		local stats = Contract.treeUniformity(Stubs.bfsTree, Contract.TREE_DRAWS)
		assert(
			stats.max == 1,
			`the BFS tree's most frequent tree scored {fmt(stats.max)}, expected exactly 1`
		)
		assert(#stats.missing == 14, `the BFS tree left {#stats.missing} trees unseen, expected 14`)
		assert(
			stats.maxKey == "1-2,1-4,2-3,2-5,3-6",
			`the BFS tree from cell 1 is {stats.maxKey}; expected the hand-derived 1-2,1-4,2-3,2-5,3-6`
		)
		local message = refuses(function()
			Contract.assertTreeUniform(Stubs.bfsTree)
		end, "the BFS tree must fail AC-3")
		names(message, "AC-3", "the BFS tree fails")
		names(message, "14 of the 15", "the BFS tree fails")
	end,

	["AC-3 control: random-order Kruskal with the real Rng is not uniform - its rarest tree is below 1/15 - 0.004 - and fails (measured: see handoff)"] = function()
		local stats = Contract.treeUniformity(Stubs.kruskal, Contract.TREE_DRAWS)
		local lo = 1 / 15 - Contract.TREE_TOLERANCE
		local unknownCount = 0
		for _ in stats.unknown do
			unknownCount += 1
		end
		assert(
			unknownCount == 0,
			`Kruskal produced trees outside the 15: {Contract.describeTreeStats(stats)}`
		)
		assert(
			#stats.missing == 0,
			`Kruskal never produced some tree: {Contract.describeTreeStats(stats)}`
		)
		assert(
			stats.min < lo,
			`Kruskal's rarest tree scored {fmt(stats.min)}, which is NOT below {fmt(lo)}: the band no longer discriminates (PO-2 measured 0.059) - {Contract.describeTreeStats(
				stats
			)}`
		)
		local message = refuses(function()
			Contract.assertTreeUniform(Stubs.kruskal)
		end, "random-order Kruskal must fail AC-3")
		names(message, "AC-3", "Kruskal fails")
		names(message, "not uniform", "Kruskal fails")
		-- The handoff's row. Printed so the measurement is in the run log.
		print(`        [measured] Kruskal: {Contract.describeTreeStats(stats)}`)
	end,

	["AC-3 positive control: Wilson's algorithm rooted at cell 1 draws all 15 trees within 1/15 ± 0.004 over 150,000 draws"] = function()
		local stats = Contract.treeUniformity(Stubs.wilson, Contract.TREE_DRAWS)
		Contract.assertTreeUniform(Stubs.wilson)
		print(`        [measured] Wilson: {Contract.describeTreeStats(stats)}`)
	end,

	["AC-3 shape: a malformed draw (an unsorted or short tree) is counted as unknown, not silently dropped"] = function()
		local unsorted = function(rng: Rng.Rng, cells: { Contract.Cell }): { Contract.Door }
			local t = Stubs.wilson(rng, cells)
			t[1], t[2] = t[2], t[1]
			return t
		end
		local stats = Contract.treeUniformity(unsorted, 20)
		local unknownCount = 0
		for _ in stats.unknown do
			unknownCount += 1
		end
		assert(unknownCount > 0, "an unsorted tree was accepted as one of the 15")
		local message = refuses(function()
			Contract.assertTreeUniform(unsorted)
		end, "a sampler returning unsorted doors must fail AC-3")
		names(message, "not among the ladder's 15", "the unsorted sampler fails")

		local short = function(rng: Rng.Rng, cells: { Contract.Cell }): { Contract.Door }
			local t = Stubs.wilson(rng, cells)
			table.remove(t)
			return t
		end
		local shortStats = Contract.treeUniformity(short, 20)
		assert(#shortStats.missing == 15, "a 4-door tree was accepted as one of the 15")
	end,

	--[[ ================================================================
	     AC-6 loop rate.
	     ================================================================ ]]

	["AC-6 control: a generator that never adds a loop door scores 0 and fails"] = function()
		local stats = Contract.loopRate(Stubs.noLoops, TUNING, Contract.LOOP_SEEDS)
		assert(stats.denominator > 0, "no non-tree pairs at all; the statistic is undefined")
		assert(stats.ratio == 0, `the no-loop generator scored {stats.ratio}, expected 0`)
		local message = refuses(function()
			Contract.assertLoopRate(Stubs.noLoops, TUNING)
		end, "the no-loop generator must fail AC-6")
		names(message, "AC-6", "the no-loop generator fails")
		names(message, "0.0000", "the no-loop generator fails")
		sweepIsStructurallyValid(Stubs.noLoops, "the no-loop generator")
	end,

	["AC-6 control: a generator that adds every loop door scores 1 and fails"] = function()
		local stats = Contract.loopRate(Stubs.allLoops, TUNING, Contract.LOOP_SEEDS)
		assert(stats.ratio == 1, `the all-loop generator scored {stats.ratio}, expected 1`)
		local message = refuses(function()
			Contract.assertLoopRate(Stubs.allLoops, TUNING)
		end, "the all-loop generator must fail AC-6")
		names(message, "AC-6", "the all-loop generator fails")
		names(message, "1.0000", "the all-loop generator fails")
		sweepIsStructurallyValid(Stubs.allLoops, "the all-loop generator")
	end,

	["AC-6 positive control: the reference generator's loop rate over seeds 1..10000 lies within 0.25 ± 0.03"] = function()
		local stats = Contract.loopRate(Stubs.reference, TUNING, Contract.LOOP_SEEDS)
		Contract.assertLoopRate(Stubs.reference, TUNING)
		print(
			`        [measured] reference loop rate: {string.format("%.4f", stats.ratio)} = {stats.numerator} / {stats.denominator}`
		)
	end,

	--[[ ================================================================
	     AC-1's violations, through OUR checker: each trips exactly its own
	     clause, so it is a fair control for the module's `check`.
	     ================================================================ ]]

	["AC-1 fixtures: each hand-built violation breaks exactly one INV_layout clause in the test's own checker, and the reference's layouts break none"] = function()
		for _, v in Contract.violationFixtures() do
			local found = Contract.violations(v.layout, TUNING)
			assert(#found > 0, `{v.name}: our checker found nothing wrong`)
			for _, line in found do
				local token = string.match(line, "^([%w_]+) ")
				assert(
					token == v.token,
					`{v.name}: our checker reports clause "{tostring(token)}" as well as "{v.token}": {line}`
				)
			end
		end
		for _, f in Contract.FIXTURES do
			if #f.rooms == TUNING.instance.room_count then
				local found = Contract.violations(Contract.layoutOf(f), TUNING)
				assert(
					#found == 0,
					`fixture {f.name} is not a valid layout: {table.concat(found, "; ")}`
				)
			end
		end
	end,

	["AC-1 needles: parseTokens accepts only `INV_layout:<token> ` prefixes, so a token inside other text does not satisfy it"] = function()
		local parsed = Contract.parseTokens({
			"INV_layout:cells rooms 4 and 6 share cell (1, 2)",
			"INV_layout:connected",
			"INV_layout:connected: rooms 4, 5, 6 unreachable",
			"the layout failed INV_layout:cells ",
			"INV_layout:cellsx ",
			"INV_layout: cells",
		})
		assert(
			Deep.equal(parsed.tokens, { "cells" }),
			`expected exactly one well-formed token, got {Deep.show(parsed.tokens)}`
		)
		assert(
			#parsed.malformed == 5,
			`expected 5 malformed strings, got {#parsed.malformed}: {Deep.show(parsed.malformed)}`
		)
	end,

	--[[ ================================================================
	     AC-4 and AC-5 fixtures: the hand-written numbers against this
	     file's BFS. Agreement here is what lets layout_test.luau treat the
	     fixtures as an oracle.
	     ================================================================ ]]

	["AC-4 fixtures: every hand-written distance matrix agrees with the test's own BFS, and every neighbour list with the doors"] = function()
		local all = table.clone(Contract.FIXTURES)
		table.insert(all, Contract.SPLIT)
		for _, f in all do
			local n = #f.rooms
			for a = 1, n do
				local dist = Contract.bfs(n, f.doors, a)
				for b = 1, n do
					local hand = Contract.distanceAt(f, a, b)
					assert(
						hand == dist[b],
						`fixture {f.name}: hand-written distance({a}, {b}) = {hand}, BFS says {dist[b]}`
					)
				end
			end
			local lists = Contract.neighbourLists(n, f.doors)
			assert(
				Deep.equal(f.neighbours, lists),
				`fixture {f.name}: hand-written neighbours disagree with the doors:\n{Deep.diff(
					f.neighbours,
					lists
				)}`
			)
		end
	end,

	["AC-5 fixtures: every hand-written spawn room is the lowest-id room of least eccentricity, and the tie lists are exact"] = function()
		local all = table.clone(Contract.FIXTURES)
		table.insert(all, Contract.SPLIT)
		for _, f in all do
			local n = #f.rooms
			local ecc: { number } = {}
			local least = math.huge
			for a = 1, n do
				ecc[a] = 0
				for _, d in Contract.bfs(n, f.doors, a) do
					ecc[a] = math.max(ecc[a], d)
				end
				least = math.min(least, ecc[a])
			end
			local tied: { number } = {}
			for a = 1, n do
				if ecc[a] == least then
					table.insert(tied, a)
				end
			end
			assert(
				tied[1] == f.spawnRoom,
				`fixture {f.name}: hand-written spawnRoom {f.spawnRoom}, but the least eccentricity {least} belongs first to room {tied[1]}`
			)
			assert(
				Contract.spawnRoomOf(n, f.doors) == f.spawnRoom,
				`fixture {f.name}: spawnRoomOf disagrees with the hand-written {f.spawnRoom}`
			)
			local expectedTie = f.tie or { f.spawnRoom }
			assert(
				Deep.equal(expectedTie, tied),
				`fixture {f.name}: the tie is {Deep.show(tied)}, the fixture says {Deep.show(
					expectedTie
				)}`
			)
		end
	end,

	["AC-5 control: a spawnRoom that always answers 1 is wrong on the chain, the square and the plus - the fixtures whose tie excludes room 1"] = function()
		local wrong: { string } = {}
		for _, f in Contract.FIXTURES do
			if Stubs.alwaysRoomOne(Contract.layoutOf(f)) ~= f.spawnRoom then
				table.insert(wrong, f.name)
			end
		end
		assert(
			Deep.equal(wrong, { "chain", "square", "plus" }),
			`always-1 is wrong on {Deep.show(wrong)}; expected chain, square and plus`
		)
	end,
}
