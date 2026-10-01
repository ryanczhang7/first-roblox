--!strict
--[[
	The wrong generators GEN-001's negative controls are aimed at, and the one
	reference each statistic must ACCEPT.

	THE CRITERIA NAME THEIR CONTROLS. AC-2: "a generator that always occupies
	the same six cells must fail the second clause, scoring 1". AC-3: "a tree
	built by breadth-first search from cell 1 (one tree, always) must fail,
	scoring about 1.0 for one tree. A random-order Kruskal (shuffle the edges,
	keep each that joins two components) must fail: its rarest tree scores
	about 0.059". AC-6: "a generator that never adds a loop door must fail,
	scoring 0. A generator that adds every loop door must fail, scoring 1". A
	criterion that names an implementation needs an implementation to point at,
	so the generators below really do generate.

	THE POSITIVE CONTROL is `reference`: cell growth, Wilson's algorithm rooted
	at cell 1, one loop draw per non-tree adjacent pair in (a, b) order - the
	Contract's construction. It exists so that each statistic is shown to
	ACCEPT a correct generator in RED: a statistic that rejects everything is
	indistinguishable from a broken one. The one-defect generators are the
	reference with exactly one thing changed - the tree sampler, or the loop
	rule, or the cells - so a control that fires is attributable to that one
	thing.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/server/facility/
	Layout.luau` and not a sketch of one. It has no `check`, no `distance`, no
	`neighbours`, no exported types, and its growth and walk are one of several
	constructions the Contract allows. GREEN writes the module from the story's
	Contract, against the failing tests in `tests/server/layout_test.luau`;
	nothing here is to be copied.

	NOTHING HERE REQUIRES PRODUCTION CODE - `src/shared/Rng.luau` and
	`src/shared/MechanicsTuning.luau` are merged - so these controls are
	EXECUTED in RED, and `tests/server/layout_controls_test.luau` records what
	each one measured.
]]

local LayoutContract = require("./LayoutContract")
local Rng = require("../../src/shared/Rng")

type Cell = LayoutContract.Cell
type Room = LayoutContract.Room
type Door = LayoutContract.Door
type Layout = LayoutContract.Layout
type Tuning = LayoutContract.Tuning

local LayoutStubs = {}

local function sortDoors(doors: { Door }): { Door }
	table.sort(doors, function(x: Door, y: Door): boolean
		return if x.a ~= y.a then x.a < y.a else x.b < y.b
	end)
	return doors
end

local function door(a: number, b: number): Door
	return if a < b then { a = a, b = b } else { a = b, b = a }
end

-- Grid adjacency over a cell list, as ascending neighbour-index lists.
local function cellNeighbours(cells: { Cell }): { { number } }
	local lists: { { number } } = {}
	for i = 1, #cells do
		lists[i] = {}
	end
	for i = 1, #cells do
		for j = i + 1, #cells do
			if LayoutContract.gridAdjacent(cells[i], cells[j]) then
				table.insert(lists[i], j)
				table.insert(lists[j], i)
			end
		end
	end
	return lists
end

--[[ ------------------------------------------------------------------------
     Tree samplers. Each is `(rng, cells) -> { Door }`, door ids indexing
     `cells`, a < b, sorted - the Contract's `spanningTree` shape.
     --------------------------------------------------------------------- ]]

--[[
	Wilson's algorithm, rooted at cell 1: for each cell not yet in the tree, in
	index order, walk at random (uniform over grid neighbours) until the tree is
	hit, erase the loops by keeping only the LAST successor recorded for each
	cell, and add the loop-erased path. Uniform over spanning trees.
]]
function LayoutStubs.wilson(rng: Rng.Rng, cells: { Cell }): { Door }
	local n = #cells
	local lists = cellNeighbours(cells)
	local inTree: { boolean } = {}
	local next_: { number } = {}
	local doors: { Door } = {}
	if n == 0 then
		return doors
	end
	inTree[1] = true
	for start = 2, n do
		if not inTree[start] then
			local u = start
			while not inTree[u] do
				local nb = lists[u]
				next_[u] = nb[rng:nextInteger(1, #nb)]
				u = next_[u]
			end
			u = start
			while not inTree[u] do
				inTree[u] = true
				table.insert(doors, door(u, next_[u]))
				u = next_[u]
			end
		end
	end
	return sortDoors(doors)
end

-- AC-3's first control: breadth-first search from cell 1. One tree, always;
-- the rng is never consulted.
function LayoutStubs.bfsTree(_rng: Rng.Rng, cells: { Cell }): { Door }
	local lists = cellNeighbours(cells)
	local seen: { boolean } = { true }
	local queue = { 1 }
	local head = 1
	local doors: { Door } = {}
	while head <= #queue do
		local u = queue[head]
		head += 1
		for _, v in lists[u] do
			if not seen[v] then
				seen[v] = true
				table.insert(doors, door(u, v))
				table.insert(queue, v)
			end
		end
	end
	return sortDoors(doors)
end

-- AC-3's second control: random-order Kruskal. Shuffle the edges with the
-- rng, keep each one that joins two components (union-find). NOT uniform over
-- spanning trees, by a margin AC-3's band is sized to see (PO-2).
function LayoutStubs.kruskal(rng: Rng.Rng, cells: { Cell }): { Door }
	local edges: { Door } = {}
	for i = 1, #cells do
		for j = i + 1, #cells do
			if LayoutContract.gridAdjacent(cells[i], cells[j]) then
				table.insert(edges, { a = i, b = j })
			end
		end
	end
	local parent: { number } = {}
	for i = 1, #cells do
		parent[i] = i
	end
	local function find(x: number): number
		while parent[x] ~= x do
			parent[x] = parent[parent[x]]
			x = parent[x]
		end
		return x
	end
	local doors: { Door } = {}
	for _, e in rng:shuffle(edges) do
		local ra, rb = find(e.a), find(e.b)
		if ra ~= rb then
			parent[ra] = rb
			table.insert(doors, { a = e.a, b = e.b })
		end
	end
	return sortDoors(doors)
end

--[[ ------------------------------------------------------------------------
     Generators. `(rng, tuning) -> Layout`, the Contract's `generate` shape.
     --------------------------------------------------------------------- ]]

-- The Contract's cell growth: a uniform start cell, then a uniform free cell
-- adjacent to the occupied set, until `room_count`. Returns rooms in
-- row-major id order.
local function growCells(rng: Rng.Rng, tuning: Tuning): { Room }
	local columns = tuning.instance.layout_grid_columns
	local rows = tuning.instance.layout_grid_rows
	local roomCount = tuning.instance.room_count
	local occupied: { [number]: boolean } = {} -- by row-major index
	local chosen: { Cell } = {}

	local function cellAt(index: number): Cell
		return { column = (index - 1) % columns + 1, row = (index - 1) // columns + 1 }
	end

	local first = rng:nextInteger(1, columns * rows)
	occupied[first] = true
	table.insert(chosen, cellAt(first))
	while #chosen < roomCount do
		local frontier: { number } = {}
		for index = 1, columns * rows do
			if not occupied[index] then
				local c = cellAt(index)
				for _, o in chosen do
					if LayoutContract.gridAdjacent(c, o) then
						table.insert(frontier, index)
						break
					end
				end
			end
		end
		local pick = frontier[rng:nextInteger(1, #frontier)]
		occupied[pick] = true
		table.insert(chosen, cellAt(pick))
	end

	table.sort(chosen, function(p: Cell, q: Cell): boolean
		return LayoutContract.cellIndex(p, columns) < LayoutContract.cellIndex(q, columns)
	end)
	local rooms: { Room } = {}
	for i, c in chosen do
		rooms[i] = { id = i, column = c.column, row = c.row }
	end
	return rooms
end

export type LoopRule = "draw" | "none" | "all"

--[[
	A generator from a tree sampler and a loop rule:

	    "draw"  one `loops:nextNumber() < layout_loop_door_chance` per non-tree
	            adjacent pair, in (a, b) order  (the Contract; the reference)
	    "none"  never a loop door                 (AC-6's control, scores 0)
	    "all"   every loop door                   (AC-6's control, scores 1)
]]
function LayoutStubs.generatorWith(
	treeOf: LayoutContract.SpanningTree,
	rule: LoopRule,
	cellsOf: ((rng: Rng.Rng, tuning: Tuning) -> { Room })?
): LayoutContract.Generate
	return function(rng: Rng.Rng, tuning: Tuning): Layout
		local cellsRng = rng:derive("cells")
		local treeRng = rng:derive("tree")
		local loops = rng:derive("loops")

		local rooms = (cellsOf or growCells)(cellsRng, tuning)
		local cells: { Cell } = {}
		for i, room in rooms do
			cells[i] = { column = room.column, row = room.row }
		end
		local doors = treeOf(treeRng, cells)

		local isTree: { [string]: boolean } = {}
		for _, d in doors do
			isTree[`{d.a}-{d.b}`] = true
		end
		for _, pair in LayoutContract.adjacentPairs(rooms) do
			if not isTree[`{pair.a}-{pair.b}`] then
				local keep = if rule == "draw"
					then loops:nextNumber() < tuning.instance.layout_loop_door_chance
					elseif rule == "all" then true
					else false
				if keep then
					table.insert(doors, { a = pair.a, b = pair.b })
				end
			end
		end
		sortDoors(doors)

		return {
			rooms = rooms,
			doors = doors,
			spawnRoom = LayoutContract.spawnRoomOf(#rooms, doors),
		}
	end
end

-- The positive control.
LayoutStubs.reference = LayoutStubs.generatorWith(LayoutStubs.wilson, "draw")

-- AC-6's controls.
LayoutStubs.noLoops = LayoutStubs.generatorWith(LayoutStubs.wilson, "none")
LayoutStubs.allLoops = LayoutStubs.generatorWith(LayoutStubs.wilson, "all")

-- AC-2's control: always the 2 × 3 block, whatever the seed. The tree and
-- the loops still vary, so every structural check passes.
LayoutStubs.constantCells = LayoutStubs.generatorWith(
	LayoutStubs.wilson,
	"draw",
	function(_rng, _tuning)
		local rooms: { Room } = {}
		for i, cell in LayoutContract.LADDER_CELLS do
			rooms[i] = { id = i, column = cell.column, row = cell.row }
		end
		return rooms
	end
)

-- AC-5's control: a `spawnRoom` that always answers 1. Right on every fixture
-- whose tie includes room 1, wrong on the chain, the square and the plus.
function LayoutStubs.alwaysRoomOne(_layout: Layout): number
	return 1
end

return LayoutStubs
