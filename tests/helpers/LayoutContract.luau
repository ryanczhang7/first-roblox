--!strict
--[[
	GEN-001's checks, statistics and fixtures, written once over a LAYOUT MODULE
	rather than over `src/server/facility/Layout.luau` by name - the same
	arrangement as `RingContract.luau`, and for the same reason.

	`tests/server/layout_test.luau` applies these to the real module.
	`tests/server/layout_controls_test.luau` applies them to the deliberately
	wrong generators in `LayoutStubs.luau`, so that in RED - where the module
	does not exist, the real file fails at `require`, and not one assertion in
	it has executed - every statistic here has been EXECUTED and observed to
	reject the generator it exists to catch, and observed to accept a reference
	that is correct.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE.

	  * MECHANICAL. `INV_layout` (`tuning.md` §2) is re-derived INDEPENDENTLY in
	    `violations` below - our own adjacency test, our own BFS - so that the
	    AC-1 sweep does not take `Layout.check`'s word for it. The AC-4 and AC-5
	    fixtures carry distance matrices and spawn rooms WRITTEN BY HAND; nothing
	    in them is computed by the module under test. The controls file checks
	    each hand matrix against this file's BFS, so a slip of the pen in a
	    fixture is caught in RED rather than blamed on GREEN.
	  * SETTLED NUMBERS READ OUT. The 15 spanning trees of the 2 × 3 ladder are
	    listed by hand (`LADDER_TREES`); the controls file proves the list has
	    15 distinct entries, each a spanning tree. The 48 connected 6-sets of
	    the 3 × 3 grid (PO-3) are enumerated by `connectedSubsetCount`.
	  * ORACLE-FREE WITH NEGATIVE CONTROL. `cellSetVariety`, `treeUniformity`
	    and `loopRate` are pure functions of a generator. Their sample sizes and
	    tolerances are the Lead PO's, copied from the criteria verbatim: RED may
	    tighten one from a measured variance and did not need to; GREEN may not
	    move any of them (`rules.md`, "do not widen a tolerance").

	Every constant the grid depends on is READ from `MechanicsTuning`; the only
	numbers hard-coded below are the statistics' own sample sizes and bands, and
	the hand-built fixtures, which are 3 × 3 by construction and say so.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")

local LayoutContract = {}

export type Cell = { column: number, row: number }
export type Room = { id: number, column: number, row: number }
export type Door = { a: number, b: number }
export type Layout = { rooms: { Room }, doors: { Door }, spawnRoom: number }
export type Tuning = typeof(MechanicsTuning)
export type Generate = (rng: Rng.Rng, tuning: Tuning) -> Layout
export type SpanningTree = (rng: Rng.Rng, cells: { Cell }) -> { Door }

-- The shipped tuning. Every sweep below reads `instance.room_count`,
-- `instance.layout_grid_columns`, `instance.layout_grid_rows` and
-- `instance.layout_loop_door_chance` from here, never from a literal.
LayoutContract.TUNING = MechanicsTuning

-- AC-1, AC-2 and AC-5 sweep these seeds. AC-6 sweeps `LOOP_SEEDS` (PO-4).
LayoutContract.SWEEP_SEEDS = 1000
LayoutContract.VARIETY_MIN = 20
LayoutContract.TREE_DRAWS = 150000
LayoutContract.TREE_TOLERANCE = 0.004
LayoutContract.LOOP_SEEDS = 10000
LayoutContract.LOOP_TOLERANCE = 0.03

-- The four clause tokens `check` may report, from the Contract's table.
LayoutContract.TOKENS = { "room_count", "cells", "adjacency", "connected" }

--[[ ------------------------------------------------------------------------
     Graph primitives, independent of the module under test.
     --------------------------------------------------------------------- ]]

function LayoutContract.gridAdjacent(p: Cell, q: Cell): boolean
	return math.abs(p.column - q.column) + math.abs(p.row - q.row) == 1
end

-- Row-major cell index, 1-based: the room id a cell would carry.
function LayoutContract.cellIndex(cell: Cell, columns: number): number
	return (cell.row - 1) * columns + cell.column
end

-- Neighbour lists from a door list, each ascending. `roomCount` rather than
-- `#rooms` so a door naming an unknown room is visible to the caller.
function LayoutContract.neighbourLists(roomCount: number, doors: { Door }): { { number } }
	local lists: { { number } } = {}
	for id = 1, roomCount do
		lists[id] = {}
	end
	for _, door in doors do
		if lists[door.a] ~= nil and lists[door.b] ~= nil then
			table.insert(lists[door.a], door.b)
			table.insert(lists[door.b], door.a)
		end
	end
	for _, list in lists do
		table.sort(list)
	end
	return lists
end

-- Breadth-first distances from `from` over the doors; `math.huge` where
-- unreachable. This is the test's own oracle for AC-1's "connected" and
-- "distance ≥ 2" clauses and for the AC-5 sweep.
function LayoutContract.bfs(roomCount: number, doors: { Door }, from: number): { number }
	local lists = LayoutContract.neighbourLists(roomCount, doors)
	local dist: { number } = {}
	for id = 1, roomCount do
		dist[id] = math.huge
	end
	dist[from] = 0
	local queue = { from }
	local head = 1
	while head <= #queue do
		local u = queue[head]
		head += 1
		for _, v in lists[u] do
			if dist[v] == math.huge then
				dist[v] = dist[u] + 1
				table.insert(queue, v)
			end
		end
	end
	return dist
end

-- Argmin over rooms of the eccentricity, ties to the lowest id (`tuning.md`
-- §2, `spawn_room`). `math.huge` eccentricities compare like any other.
function LayoutContract.spawnRoomOf(roomCount: number, doors: { Door }): number
	local best = 1
	local bestEcc = math.huge
	for id = 1, roomCount do
		local ecc = 0
		for _, d in LayoutContract.bfs(roomCount, doors, id) do
			ecc = math.max(ecc, d)
		end
		if ecc < bestEcc then
			best = id
			bestEcc = ecc
		end
	end
	return best
end

-- Every grid-adjacent pair of occupied cells, as `(a, b)` with `a < b`,
-- sorted. The loop-door denominator counts these.
function LayoutContract.adjacentPairs(rooms: { Room }): { Door }
	local pairs_: { Door } = {}
	for i = 1, #rooms do
		for j = i + 1, #rooms do
			if LayoutContract.gridAdjacent(rooms[i], rooms[j]) then
				local a, b = rooms[i].id, rooms[j].id
				if a > b then
					a, b = b, a
				end
				table.insert(pairs_, { a = a, b = b })
			end
		end
	end
	table.sort(pairs_, function(x: Door, y: Door): boolean
		return if x.a ~= y.a then x.a < y.a else x.b < y.b
	end)
	return pairs_
end

-- "a-b,a-b,..." in the order given. Used as a tree identity for AC-3 and as a
-- readable rendering in failure messages.
function LayoutContract.doorKey(doors: { Door }): string
	local parts: { string } = {}
	for _, door in doors do
		table.insert(parts, `{door.a}-{door.b}`)
	end
	return table.concat(parts, ",")
end

-- The occupied-cell SET, as a canonical string: the (column, row) pairs
-- themselves, sorted, not a translated shape (AC-2).
function LayoutContract.cellSetKey(layout: Layout): string
	local keys: { string } = {}
	for _, room in layout.rooms do
		table.insert(keys, `{room.column},{room.row}`)
	end
	table.sort(keys)
	return table.concat(keys, ";")
end

--[[ ------------------------------------------------------------------------
     INV_layout, re-derived here. AC-1's sweep asserts THESE, and then also
     asserts `Layout.check` returns `{}` - two oracles, so a `check` that
     returns `{}` for everything is caught by the first and a sweep that
     trusts `check` is not the only line of defence.

     Returns one string per violated clause, each starting with the clause's
     token, so the controls file can show which clause each hand-built
     violation trips in OUR checker - which is what makes it a fair control
     for the module's `check`.
     --------------------------------------------------------------------- ]]

function LayoutContract.violations(layout: Layout, tuning: Tuning): { string }
	local out: { string } = {}
	local roomCount = tuning.instance.room_count
	local columns = tuning.instance.layout_grid_columns
	local rows = tuning.instance.layout_grid_rows

	-- room_count: exactly `room_count` rooms, `rooms[i].id == i`.
	if #layout.rooms ~= roomCount then
		table.insert(out, `room_count #rooms is {#layout.rooms}, expected {roomCount}`)
	end
	for i, room in layout.rooms do
		if room.id ~= i then
			table.insert(out, `room_count rooms[{i}].id is {room.id}`)
		end
	end

	-- cells: distinct, inside the grid.
	local seen: { [string]: number } = {}
	for _, room in layout.rooms do
		if
			room.column < 1
			or room.column > columns
			or room.row < 1
			or room.row > rows
			or room.column ~= math.floor(room.column)
			or room.row ~= math.floor(room.row)
		then
			table.insert(
				out,
				`cells room {room.id} at ({room.column}, {room.row}) is outside the {columns} × {rows} grid`
			)
		end
		local key = `{room.column},{room.row}`
		if seen[key] ~= nil then
			table.insert(
				out,
				`cells rooms {seen[key]} and {room.id} share cell ({room.column}, {room.row})`
			)
		else
			seen[key] = room.id
		end
	end

	-- adjacency: every door joins two known, grid-adjacent rooms; a < b; sorted
	-- by (a, b); no pair twice.
	local byId: { [number]: Room } = {}
	for _, room in layout.rooms do
		byId[room.id] = room
	end
	local pairSeen: { [string]: boolean } = {}
	local previous: Door? = nil
	for i, door in layout.doors do
		local ra, rb = byId[door.a], byId[door.b]
		if ra == nil or rb == nil then
			table.insert(out, `adjacency door {i} ({door.a}, {door.b}) names an unknown room`)
		elseif not LayoutContract.gridAdjacent(ra, rb) then
			table.insert(
				out,
				`adjacency door {i} joins rooms {door.a} ({ra.column}, {ra.row}) and {door.b} ({rb.column}, {rb.row}), which are not grid-adjacent`
			)
		end
		if not (door.a < door.b) then
			table.insert(out, `adjacency door {i} ({door.a}, {door.b}) does not have a < b`)
		end
		local key = `{math.min(door.a, door.b)}-{math.max(door.a, door.b)}`
		if pairSeen[key] then
			table.insert(out, `adjacency pair {key} has two doorways`)
		end
		pairSeen[key] = true
		if previous ~= nil then
			local p = previous :: Door
			if p.a > door.a or (p.a == door.a and p.b >= door.b) then
				table.insert(out, `adjacency doors are not sorted by (a, b) at door {i}`)
			end
		end
		previous = door
	end

	-- connected: every room reachable from room 1.
	if #layout.rooms > 0 then
		local dist = LayoutContract.bfs(#layout.rooms, layout.doors, 1)
		local unreachable: { number } = {}
		for id, d in dist do
			if d == math.huge then
				table.insert(unreachable, id)
			end
		end
		if #unreachable > 0 then
			table.insert(
				out,
				`connected rooms {table.concat(unreachable, ", ")} are not reachable from room 1 over doors {LayoutContract.doorKey(
					layout.doors
				)}`
			)
		end
	end

	return out
end

-- The consequences `tuning.md` §2 says a test may also check: degree ≤ 4 and
-- some pair at distance ≥ 2. Asserted on generated layouts, not by `check`.
function LayoutContract.consequenceViolations(layout: Layout): { string }
	local out: { string } = {}
	local n = #layout.rooms
	local lists = LayoutContract.neighbourLists(n, layout.doors)
	for id, list in lists do
		if #list > 4 then
			table.insert(out, `room {id} has degree {#list}`)
		end
	end
	local far = false
	for id = 1, n do
		for _, d in LayoutContract.bfs(n, layout.doors, id) do
			if d ~= math.huge and d >= 2 then
				far = true
			end
		end
	end
	if not far then
		table.insert(out, `no pair of rooms is at least 2 doorways apart`)
	end
	return out
end

-- The clause tokens in a list of `check` strings. A string that does not have
-- the Contract's shape - `INV_layout:<token> ` with a known token - goes in
-- `malformed`, so a needle can never be satisfied by text that merely
-- contains it (`rules.md`, "the needle is part of the assertion").
function LayoutContract.parseTokens(
	strings: { string }
): { tokens: { string }, malformed: { string } }
	local tokens: { string } = {}
	local malformed: { string } = {}
	for _, s in strings do
		local matched = false
		if typeof(s) == "string" then
			for _, token in LayoutContract.TOKENS do
				local prefix = `INV_layout:{token} `
				if string.sub(s, 1, #prefix) == prefix then
					table.insert(tokens, token)
					matched = true
					break
				end
			end
		end
		if not matched then
			table.insert(malformed, tostring(s))
		end
	end
	table.sort(tokens)
	return { tokens = tokens, malformed = malformed }
end

--[[ ------------------------------------------------------------------------
     Statistics. Each takes the generator and returns what it measured; each
     `assert*` turns the measurement into a pass or a raise with the numbers
     in the message. The controls file records those numbers.
     --------------------------------------------------------------------- ]]

-- AC-2, second clause: distinct occupied-cell sets over the sweep.
function LayoutContract.cellSetVariety(generate: Generate, tuning: Tuning, seeds: number): number
	local sets: { [string]: boolean } = {}
	local count = 0
	for seed = 1, seeds do
		local key = LayoutContract.cellSetKey(generate(Rng.fromSeed(seed), tuning))
		if not sets[key] then
			sets[key] = true
			count += 1
		end
	end
	return count
end

function LayoutContract.assertCellSetVariety(generate: Generate, tuning: Tuning)
	local count = LayoutContract.cellSetVariety(generate, tuning, LayoutContract.SWEEP_SEEDS)
	assert(
		count >= LayoutContract.VARIETY_MIN,
		`AC-2: only {count} distinct occupied-cell sets over seeds 1..{LayoutContract.SWEEP_SEEDS}; at least {LayoutContract.VARIETY_MIN} required`
	)
end

--[[
	AC-3's fixed input: the 2 × 3 block of six cells, two rows of three, in
	row-major order so that cell index == the room id the block would carry.

	    1 2 3
	    4 5 6

	Its 7 edges and its 15 spanning trees, WRITTEN BY HAND (story `## Contract`,
	"settled number read out"). A spanning tree of this ladder is 5 of the 7
	edges leaving no 4-cycle intact; the two squares are {1-2,1-4,2-5,4-5} and
	{2-3,2-5,3-6,5-6}. Removing 2 edges from 7 gives 21 subsets; the 6 that
	remove both from {2-3,3-6,5-6} or both from {1-2,1-4,4-5} leave a square,
	so 15 remain. They are listed as the 5 edges kept, each sorted by (a, b).
]]
LayoutContract.LADDER_CELLS = {
	{ column = 1, row = 1 },
	{ column = 2, row = 1 },
	{ column = 3, row = 1 },
	{ column = 1, row = 2 },
	{ column = 2, row = 2 },
	{ column = 3, row = 2 },
} :: { Cell }

LayoutContract.LADDER_EDGES = {
	{ a = 1, b = 2 },
	{ a = 1, b = 4 },
	{ a = 2, b = 3 },
	{ a = 2, b = 5 },
	{ a = 3, b = 6 },
	{ a = 4, b = 5 },
	{ a = 5, b = 6 },
} :: { Door }

local function tree(...: string): { Door }
	local doors: { Door } = {}
	for _, s in { ... } do
		local a, b = string.match(s, "^(%d+)-(%d+)$")
		doors[#doors + 1] = { a = tonumber(a) :: number, b = tonumber(b) :: number }
	end
	return doors
end

LayoutContract.LADDER_TREES = {
	-- removed 1-2, 2-3
	tree("1-4", "2-5", "3-6", "4-5", "5-6"),
	-- removed 1-2, 2-5
	tree("1-4", "2-3", "3-6", "4-5", "5-6"),
	-- removed 1-2, 3-6
	tree("1-4", "2-3", "2-5", "4-5", "5-6"),
	-- removed 1-2, 5-6
	tree("1-4", "2-3", "2-5", "3-6", "4-5"),
	-- removed 2-3, 1-4
	tree("1-2", "2-5", "3-6", "4-5", "5-6"),
	-- removed 2-3, 2-5
	tree("1-2", "1-4", "3-6", "4-5", "5-6"),
	-- removed 2-3, 4-5
	tree("1-2", "1-4", "2-5", "3-6", "5-6"),
	-- removed 1-4, 2-5
	tree("1-2", "2-3", "3-6", "4-5", "5-6"),
	-- removed 1-4, 3-6
	tree("1-2", "2-3", "2-5", "4-5", "5-6"),
	-- removed 1-4, 5-6
	tree("1-2", "2-3", "2-5", "3-6", "4-5"),
	-- removed 2-5, 3-6
	tree("1-2", "1-4", "2-3", "4-5", "5-6"),
	-- removed 2-5, 4-5
	tree("1-2", "1-4", "2-3", "3-6", "5-6"),
	-- removed 2-5, 5-6
	tree("1-2", "1-4", "2-3", "3-6", "4-5"),
	-- removed 3-6, 4-5
	tree("1-2", "1-4", "2-3", "2-5", "5-6"),
	-- removed 4-5, 5-6
	tree("1-2", "1-4", "2-3", "2-5", "3-6"),
} :: { { Door } }

export type TreeStats = {
	draws: number,
	frequencies: { [string]: number }, -- per hand-listed tree key
	min: number,
	max: number,
	minKey: string,
	maxKey: string,
	missing: { string }, -- hand-listed trees never drawn
	unknown: { [string]: number }, -- keys drawn that are not one of the 15 (malformed included)
}

-- Is `doors` a well-formed tree over `n` cells: n - 1 doors, each a < b in
-- 1..n, sorted by (a, b), no repeat, connected? A draw that is not goes to
-- `unknown` under a descriptive key rather than being silently dropped.
local function treeShapeProblem(doors: { Door }, n: number): string?
	if typeof(doors) ~= "table" then
		return `not a table: {typeof(doors)}`
	end
	if #doors ~= n - 1 then
		return `{#doors} doors for {n} cells`
	end
	for i, door in doors do
		if typeof(door) ~= "table" or typeof(door.a) ~= "number" or typeof(door.b) ~= "number" then
			return `door {i} is not a table with numeric a and b: {Deep.show(door)}`
		end
		if door.a < 1 or door.b > n or not (door.a < door.b) then
			return `door {i} ({door.a}, {door.b}) is not a < b within 1..{n}`
		end
		if i > 1 then
			local p = doors[i - 1]
			if p.a > door.a or (p.a == door.a and p.b >= door.b) then
				return `doors not sorted by (a, b) at door {i}: {LayoutContract.doorKey(doors)}`
			end
		end
	end
	for _, d in LayoutContract.bfs(n, doors, 1) do
		if d == math.huge then
			return `not connected: {LayoutContract.doorKey(doors)}`
		end
	end
	return nil
end

-- AC-3: `draws` trees of the ladder, draw i from
-- `Rng.fromSeed(1):derive("tree-" .. i)`, tallied against the 15 hand-listed
-- trees.
--
-- The hot loop is 150,000 draws, so the per-draw work is kept to the draw
-- itself plus a NUMERIC key (each door packed as a * 8 + b, five of them in
-- base 64, exact in a double). A key that is one of the 15 is a well-formed
-- sorted tree by construction and is counted; anything else takes the slow
-- path through `treeShapeProblem` so the failure message can say what it was.
function LayoutContract.treeUniformity(spanningTree: SpanningTree, draws: number): TreeStats
	local n = #LayoutContract.LADDER_CELLS
	local counts: { [number]: number } = {}
	local keyOf: { [number]: string } = {}
	local unknown: { [string]: number } = {}

	local function packed(doors: { Door }): number?
		if typeof(doors) ~= "table" or #doors ~= n - 1 then
			return nil
		end
		local k = 0
		for _, d in doors do
			if typeof(d) ~= "table" or typeof(d.a) ~= "number" or typeof(d.b) ~= "number" then
				return nil
			end
			k = k * 64 + d.a * 8 + d.b
		end
		return k
	end

	for _, t in LayoutContract.LADDER_TREES do
		local k = packed(t) :: number
		counts[k] = 0
		keyOf[k] = LayoutContract.doorKey(t)
	end

	for i = 1, draws do
		local rng = Rng.fromSeed(1):derive("tree-" .. i)
		local cells: { Cell } = {}
		for j, c in LayoutContract.LADDER_CELLS do
			cells[j] = { column = c.column, row = c.row }
		end
		local doors = spanningTree(rng, cells)
		local k = packed(doors)
		if k ~= nil and counts[k] ~= nil then
			counts[k] += 1
		else
			local problem = treeShapeProblem(doors, n)
			local key = if problem ~= nil
				then `malformed: {problem}`
				else LayoutContract.doorKey(doors)
			unknown[key] = (unknown[key] or 0) + 1
		end
	end

	local stats: TreeStats = {
		draws = draws,
		frequencies = {},
		min = math.huge,
		max = -math.huge,
		minKey = "",
		maxKey = "",
		missing = {},
		unknown = unknown,
	}
	for _, t in LayoutContract.LADDER_TREES do
		local k = packed(t) :: number
		local key = keyOf[k]
		local f = counts[k] / draws
		stats.frequencies[key] = f
		if counts[k] == 0 then
			table.insert(stats.missing, key)
		end
		if f < stats.min then
			stats.min, stats.minKey = f, key
		end
		if f > stats.max then
			stats.max, stats.maxKey = f, key
		end
	end
	return stats
end

function LayoutContract.describeTreeStats(stats: TreeStats): string
	local unknownParts: { string } = {}
	for key, count in stats.unknown do
		table.insert(unknownParts, `{key} × {count}`)
	end
	table.sort(unknownParts)
	return `over {stats.draws} draws: min {string.format("%.5f", stats.min)} ({stats.minKey}), max {string.format(
		"%.5f",
		stats.max
	)} ({stats.maxKey}), missing {#stats.missing}, unknown [{table.concat(unknownParts, "; ")}]`
end

function LayoutContract.assertTreeUniform(spanningTree: SpanningTree)
	local stats = LayoutContract.treeUniformity(spanningTree, LayoutContract.TREE_DRAWS)
	local target = 1 / #LayoutContract.LADDER_TREES
	local lo, hi = target - LayoutContract.TREE_TOLERANCE, target + LayoutContract.TREE_TOLERANCE
	local unknownCount = 0
	for _ in stats.unknown do
		unknownCount += 1
	end
	assert(
		unknownCount == 0,
		`AC-3: spanningTree returned {unknownCount} kind(s) of tree that are not among the ladder's 15 spanning trees - {LayoutContract.describeTreeStats(
			stats
		)}`
	)
	assert(
		#stats.missing == 0,
		`AC-3: {#stats.missing} of the 15 spanning trees never appeared ({table.concat(
			stats.missing,
			"; "
		)}) - {LayoutContract.describeTreeStats(stats)}`
	)
	assert(
		stats.min >= lo and stats.max <= hi,
		`AC-3: tree frequencies are not uniform within 1/15 ± {LayoutContract.TREE_TOLERANCE} ([{string.format(
			"%.5f",
			lo
		)}, {string.format("%.5f", hi)}]) - {LayoutContract.describeTreeStats(stats)}`
	)
end

export type LoopStats = { numerator: number, denominator: number, ratio: number }

-- AC-6: Σ(#doors − (room_count − 1)) over Σ(adjacent occupied pairs −
-- (room_count − 1)), over seeds 1..`seeds`.
function LayoutContract.loopRate(generate: Generate, tuning: Tuning, seeds: number): LoopStats
	local treeDoors = tuning.instance.room_count - 1
	local numerator, denominator = 0, 0
	for seed = 1, seeds do
		local layout = generate(Rng.fromSeed(seed), tuning)
		numerator += #layout.doors - treeDoors
		denominator += #LayoutContract.adjacentPairs(layout.rooms) - treeDoors
	end
	return {
		numerator = numerator,
		denominator = denominator,
		ratio = if denominator == 0 then 0 / 0 else numerator / denominator,
	}
end

function LayoutContract.assertLoopRate(generate: Generate, tuning: Tuning)
	local stats = LayoutContract.loopRate(generate, tuning, LayoutContract.LOOP_SEEDS)
	local chance = tuning.instance.layout_loop_door_chance
	local lo, hi = chance - LayoutContract.LOOP_TOLERANCE, chance + LayoutContract.LOOP_TOLERANCE
	assert(
		stats.denominator > 0,
		`AC-6: no non-tree adjacent pairs over seeds 1..{LayoutContract.LOOP_SEEDS}; the loop rate is undefined`
	)
	assert(
		stats.ratio >= lo and stats.ratio <= hi,
		`AC-6: loop-door rate {string.format("%.4f", stats.ratio)} ({stats.numerator} / {stats.denominator}) over seeds 1..{LayoutContract.LOOP_SEEDS} is outside layout_loop_door_chance {chance} ± {LayoutContract.LOOP_TOLERANCE}`
	)
end

--[[ ------------------------------------------------------------------------
     PO-3's settled number, enumerated: connected k-subsets of a columns × rows
     grid. 84 six-subsets of the 3 × 3 grid, 48 connected.
     --------------------------------------------------------------------- ]]
function LayoutContract.connectedSubsetCount(
	columns: number,
	rows: number,
	k: number
): { total: number, connected: number }
	local n = columns * rows
	local total, connected = 0, 0
	for mask = 0, 2 ^ n - 1 do
		local cells: { Room } = {}
		for i = 1, n do
			if bit32.btest(mask, bit32.lshift(1, i - 1)) then
				local column = (i - 1) % columns + 1
				local row = (i - 1) // columns + 1
				table.insert(cells, { id = #cells + 1, column = column, row = row })
			end
		end
		if #cells == k then
			total += 1
			local dist = LayoutContract.bfs(k, LayoutContract.adjacentPairs(cells), 1)
			local ok = true
			for _, d in dist do
				if d == math.huge then
					ok = false
				end
			end
			if ok then
				connected += 1
			end
		end
	end
	return { total = total, connected = connected }
end

--[[ ------------------------------------------------------------------------
     Hand-built fixtures. Every number here was derived BY HAND from the
     drawing; `layout_controls_test.luau` re-derives each matrix with the BFS
     above so that a slip is caught in RED. Rooms are the 2 × 3 block
     (ids row-major, as `LADDER_CELLS`) unless the fixture says otherwise.

     A distance matrix is written as `D[a][b]` for a < b only; `distanceAt`
     folds in symmetry and the zero diagonal, so the fixture holds exactly the
     15 numbers a person wrote down.
     --------------------------------------------------------------------- ]]

export type Fixture = {
	name: string,
	rooms: { Room },
	doors: { Door },
	distances: { [number]: { [number]: number } }, -- a < b
	neighbours: { { number } },
	spawnRoom: number,
	tie: { number }?, -- the rooms sharing the least eccentricity, where it is a tie
}

local function block(): { Room }
	local rooms: { Room } = {}
	for i, cell in LayoutContract.LADDER_CELLS do
		rooms[i] = { id = i, column = cell.column, row = cell.row }
	end
	return rooms
end

--[[
	THE CHAIN. 1-2-3-6-5-4, a snake through the block:

	    1 - 2 - 3
	            |
	    4 - 5 - 6

	Eccentricities 5,4,3,5,4,3: rooms 3 and 6 tie at 3; the spawn room is 3.
	AC-5's "tie that does not include room 1".
]]
local chain: Fixture = {
	name = "chain",
	rooms = block(),
	doors = tree("1-2", "2-3", "3-6", "4-5", "5-6"),
	distances = {
		[1] = { [2] = 1, [3] = 2, [4] = 5, [5] = 4, [6] = 3 },
		[2] = { [3] = 1, [4] = 4, [5] = 3, [6] = 2 },
		[3] = { [4] = 3, [5] = 2, [6] = 1 },
		[4] = { [5] = 1, [6] = 2 },
		[5] = { [6] = 1 },
	},
	neighbours = { { 2 }, { 1, 3 }, { 2, 6 }, { 5 }, { 4, 6 }, { 3, 5 } },
	spawnRoom = 3,
	tie = { 3, 6 },
}

--[[
	THE SQUARE. The left square closed, with 3 and 6 hanging off it:

	    1 - 2 - 3
	    |   |
	    4 - 5 - 6

	Eccentricities 3,2,3,3,2,3: rooms 2 and 5 tie at 2; the spawn room is 2.
	A loop, so a BFS that stops at the first path found and one that walks the
	tree it was handed differ here.
]]
local square: Fixture = {
	name = "square",
	rooms = block(),
	doors = tree("1-2", "1-4", "2-3", "2-5", "4-5", "5-6"),
	distances = {
		[1] = { [2] = 1, [3] = 2, [4] = 1, [5] = 2, [6] = 3 },
		[2] = { [3] = 1, [4] = 2, [5] = 1, [6] = 2 },
		[3] = { [4] = 3, [5] = 2, [6] = 3 },
		[4] = { [5] = 1, [6] = 2 },
		[5] = { [6] = 1 },
	},
	neighbours = { { 2, 4 }, { 1, 3, 5 }, { 2 }, { 1, 5 }, { 2, 4, 6 }, { 5 } },
	spawnRoom = 2,
	tie = { 2, 5 },
}

--[[
	THE CYCLE. The outer ring of the block, 1-2-3-6-5-4-1:

	    1 - 2 - 3
	    |       |
	    4 - 5 - 6

	Every eccentricity is 3, a six-way tie, so the spawn room is 1: the "lowest
	index" clause with room 1 in the tie. Distances are the shorter way round.
]]
local cycle: Fixture = {
	name = "cycle",
	rooms = block(),
	doors = tree("1-2", "1-4", "2-3", "3-6", "4-5", "5-6"),
	distances = {
		[1] = { [2] = 1, [3] = 2, [4] = 1, [5] = 2, [6] = 3 },
		[2] = { [3] = 1, [4] = 2, [5] = 3, [6] = 2 },
		[3] = { [4] = 3, [5] = 2, [6] = 1 },
		[4] = { [5] = 1, [6] = 2 },
		[5] = { [6] = 1 },
	},
	neighbours = { { 2, 4 }, { 1, 3 }, { 2, 6 }, { 1, 5 }, { 4, 6 }, { 3, 5 } },
	spawnRoom = 1,
	tie = { 1, 2, 3, 4, 5, 6 },
}

--[[
	THE PLUS. Five rooms in a cross on the 3 × 3 grid, ids row-major:

	        1
	    2 - 3 - 4
	        5

	The centre, room 3, has eccentricity 1 and every arm 2: a unique spawn room
	that is neither room 1 nor the last. Five rooms, because a fixture for
	`distance` and `spawnRoom` is not passed to `check`.
]]
local plus: Fixture = {
	name = "plus",
	rooms = {
		{ id = 1, column = 2, row = 1 },
		{ id = 2, column = 1, row = 2 },
		{ id = 3, column = 2, row = 2 },
		{ id = 4, column = 3, row = 2 },
		{ id = 5, column = 2, row = 3 },
	},
	doors = tree("1-3", "2-3", "3-4", "3-5"),
	distances = {
		[1] = { [2] = 2, [3] = 1, [4] = 2, [5] = 2 },
		[2] = { [3] = 1, [4] = 2, [5] = 2 },
		[3] = { [4] = 1, [5] = 1 },
		[4] = { [5] = 2 },
	},
	neighbours = { { 3 }, { 3 }, { 1, 2, 4, 5 }, { 3 }, { 3 } },
	spawnRoom = 3,
	tie = nil,
}

--[[
	THE SPLIT. Two rows with no door between them - NOT a valid layout, and
	never handed to `check` here; it is the fixture for "an unreachable pair
	returns math.huge" and for the `connected` control.

	    1 - 2 - 3

	    4 - 5 - 6
]]
local split: Fixture = {
	name = "split",
	rooms = block(),
	doors = tree("1-2", "2-3", "4-5", "5-6"),
	distances = {
		[1] = { [2] = 1, [3] = 2, [4] = math.huge, [5] = math.huge, [6] = math.huge },
		[2] = { [3] = 1, [4] = math.huge, [5] = math.huge, [6] = math.huge },
		[3] = { [4] = math.huge, [5] = math.huge, [6] = math.huge },
		[4] = { [5] = 1, [6] = 2 },
		[5] = { [6] = 1 },
	},
	neighbours = { { 2 }, { 1, 3 }, { 2 }, { 5 }, { 4, 6 }, { 5 } },
	spawnRoom = 1, -- every eccentricity is math.huge; the tie goes to room 1
	tie = { 1, 2, 3, 4, 5, 6 },
}

LayoutContract.FIXTURES = { chain, square, cycle, plus } :: { Fixture }
LayoutContract.SPLIT = split

-- The hand-written distance for any ordered pair, folding in d(a, a) = 0 and
-- symmetry.
function LayoutContract.distanceAt(fixture: Fixture, a: number, b: number): number
	if a == b then
		return 0
	end
	local lo, hi = math.min(a, b), math.max(a, b)
	local d = fixture.distances[lo][hi]
	assert(d ~= nil, `fixture {fixture.name} has no hand-written distance for ({lo}, {hi})`)
	return d
end

-- A fresh Layout value from a fixture, so a test that mutates one cannot leak
-- into the next. `spawnRoom` is the hand-derived value.
function LayoutContract.layoutOf(fixture: Fixture): Layout
	return {
		rooms = Deep.copy(fixture.rooms),
		doors = Deep.copy(fixture.doors),
		spawnRoom = fixture.spawnRoom,
	}
end

--[[
	AC-1's four hand-built violations, on the shipped 3 × 3 grid with
	`room_count` = 6. Each breaks exactly ONE clause so that the token it must
	produce is attributable; the controls file shows our own `violations`
	agrees, clause for clause.

	  * twoRoomsOneCell: room 6 sits on room 4's cell (1, 2), and is joined to
	    room 1 at (1, 1), which IS grid-adjacent to (1, 2) - so only `cells`.
	  * diagonalDoor: the block with a door 1-5, (1, 1) to (2, 2) - only
	    `adjacency`. Connected without it, so `connected` stays quiet.
	  * disconnected: the split, two rows and no rung - only `connected`.
	  * fiveRooms: rooms 1..5 of the block in a tree - only `room_count`.
]]
export type Violation = { name: string, token: string, layout: Layout }

function LayoutContract.violationFixtures(): { Violation }
	local b = block()
	local twoRoomsOneCell = block()
	twoRoomsOneCell[6] = { id = 6, column = 1, row = 2 }
	return {
		{
			name = "two rooms on one cell",
			token = "cells",
			layout = {
				rooms = twoRoomsOneCell,
				doors = tree("1-2", "1-4", "1-6", "2-3", "4-5"),
				spawnRoom = 1,
			},
		},
		{
			name = "a diagonal doorway",
			token = "adjacency",
			layout = {
				rooms = Deep.copy(b),
				doors = tree("1-2", "1-4", "1-5", "2-3", "3-6"),
				spawnRoom = 1,
			},
		},
		{
			name = "a disconnected pair",
			token = "connected",
			layout = LayoutContract.layoutOf(split),
		},
		{
			name = "5 rooms",
			token = "room_count",
			layout = {
				rooms = { b[1], b[2], b[3], b[4], b[5] },
				doors = tree("1-2", "1-4", "2-3", "4-5"),
				spawnRoom = 1,
			},
		},
	}
end

return LayoutContract
