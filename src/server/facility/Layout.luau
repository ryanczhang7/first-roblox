--!strict
--[[
	The facility's room graph, per GEN-001 and `docs/wiki/game/mechanics.md` §1
	(G1, G2). `tuning.md` §2 states the structural invariant, `INV_layout`.

	A layout is `room_count` rooms on distinct cells of a
	`layout_grid_columns` x `layout_grid_rows` grid, joined by doorways between
	grid-adjacent rooms only: a uniformly random spanning tree, then each other
	adjacent pair with probability `layout_loop_door_chance`. Everything the
	generator builds downstream reads distances from here.

	PURE. No module state, no Roblox API, and no argument is ever mutated. The
	`Layout` value is plain data - exactly `rooms`, `doors` and `spawnRoom` - so
	two layouts from the same seed deep-equal each other.

	RANDOMNESS. `generate` derives exactly `"cells"`, `"tree"` and `"loops"`
	from the rng it is handed and draws from nothing else. `spanningTree`
	consumes the rng it is handed directly and derives nothing.

	ROOM IDS run `1..room_count` in row-major order of their cells (row first,
	then column), and `rooms[i].id == i`.
]]

local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Rng = require("@game/ReplicatedStorage/Shared/Rng")

export type Cell = { column: number, row: number }
export type Room = { id: number, column: number, row: number }
export type Door = { a: number, b: number }
export type Layout = { rooms: { Room }, doors: { Door }, spawnRoom: number }

type Tuning = MechanicsTuning.MechanicsTuning

local Layout = {}

local function gridAdjacent(x: Cell, y: Cell): boolean
	return math.abs(x.column - y.column) + math.abs(x.row - y.row) == 1
end

local function sortDoors(doors: { Door })
	table.sort(doors, function(x: Door, y: Door): boolean
		if x.a ~= y.a then
			return x.a < y.a
		end
		return x.b < y.b
	end)
end

-- Grid adjacency over a cell list, as ascending neighbour-index lists.
local function cellNeighbours(cells: { Cell }): { { number } }
	local lists: { { number } } = {}
	for i = 1, #cells do
		lists[i] = {}
	end
	for i = 1, #cells do
		for j = i + 1, #cells do
			if gridAdjacent(cells[i], cells[j]) then
				table.insert(lists[i], j)
				table.insert(lists[j], i)
			end
		end
	end
	return lists
end

-- Door adjacency as ascending neighbour lists, built fresh on every call.
local function doorNeighbours(layout: Layout): { { number } }
	local lists: { { number } } = {}
	for i = 1, #layout.rooms do
		lists[i] = {}
	end
	for _, d in layout.doors do
		local la, lb = lists[d.a], lists[d.b]
		if la and lb then
			table.insert(la, d.b)
			table.insert(lb, d.a)
		end
	end
	for _, list in lists do
		table.sort(list)
	end
	return lists
end

-- Breadth-first distances from `source`; unreachable rooms are `math.huge`.
local function distancesFrom(lists: { { number } }, source: number): { number }
	local dist: { number } = {}
	for i = 1, #lists do
		dist[i] = math.huge
	end
	dist[source] = 0
	local queue = { source }
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

local function checkId(layout: Layout, id: number, name: string)
	if type(id) ~= "number" or id ~= math.floor(id) or id < 1 or id > #layout.rooms then
		error(`Layout: {name} {id} is not a room id in 1..{#layout.rooms}`, 3)
	end
end

--[[
	A uniform spanning tree of the cells' grid-adjacency graph, by Wilson's
	algorithm rooted at cell 1: from each cell not yet in the tree, in index
	order, walk uniformly over grid neighbours until the tree is hit, keeping
	only the last exit recorded for each cell (the loop erasure), then add that
	path. Door ids index `cells`; `a < b`; sorted by `(a, b)`.

	Precondition: the cells are distinct and grid-connected.
]]
function Layout.spanningTree(rng: Rng.Rng, cells: { Cell }): { Door }
	local n = #cells
	local doors: { Door } = {}
	if n == 0 then
		return doors
	end
	local lists = cellNeighbours(cells)
	local inTree: { [number]: boolean } = { [1] = true }
	local exit: { [number]: number } = {}
	for start = 2, n do
		local u = start
		while not inTree[u] do
			local nb = lists[u]
			exit[u] = nb[rng:nextInteger(1, #nb)]
			u = exit[u]
		end
		u = start
		while not inTree[u] do
			inTree[u] = true
			local v = exit[u]
			table.insert(doors, if u < v then { a = u, b = v } else { a = v, b = u })
			u = v
		end
	end
	sortDoors(doors)
	return doors
end

-- The occupied cells, grown from a uniform start cell by adding a uniform free
-- cell adjacent to the occupied set, returned in row-major (room id) order.
local function growCells(rng: Rng.Rng, columns: number, rows: number, count: number): { Cell }
	local total = columns * rows
	local function cellAt(index: number): Cell
		return { column = (index - 1) % columns + 1, row = (index - 1) // columns + 1 }
	end
	local occupied: { [number]: boolean } = {}
	occupied[rng:nextInteger(1, total)] = true
	local size = 1
	while size < count do
		local frontier: { number } = {}
		for index = 1, total do
			if not occupied[index] then
				local c = cellAt(index)
				local column, row = c.column, c.row
				if
					(column > 1 and occupied[index - 1])
					or (column < columns and occupied[index + 1])
					or (row > 1 and occupied[index - columns])
					or (row < rows and occupied[index + columns])
				then
					table.insert(frontier, index)
				end
			end
		end
		occupied[frontier[rng:nextInteger(1, #frontier)]] = true
		size += 1
	end
	local cells: { Cell } = {}
	for index = 1, total do
		if occupied[index] then
			table.insert(cells, cellAt(index))
		end
	end
	return cells
end

function Layout.generate(rng: Rng.Rng, tuning: Tuning): Layout
	local t = tuning.instance
	local cellsRng = rng:derive("cells")
	local treeRng = rng:derive("tree")
	local loopsRng = rng:derive("loops")

	local cells = growCells(cellsRng, t.layout_grid_columns, t.layout_grid_rows, t.room_count)
	local rooms: { Room } = {}
	for i, c in cells do
		rooms[i] = { id = i, column = c.column, row = c.row }
	end

	local doors = Layout.spanningTree(treeRng, cells)
	local isTree: { [number]: boolean } = {}
	local n = #cells
	for _, d in doors do
		isTree[(d.a - 1) * n + d.b] = true
	end
	for a = 1, n do
		for b = a + 1, n do
			if gridAdjacent(cells[a], cells[b]) and not isTree[(a - 1) * n + b] then
				if loopsRng:nextNumber() < t.layout_loop_door_chance then
					table.insert(doors, { a = a, b = b })
				end
			end
		end
	end
	sortDoors(doors)

	local layout: Layout = { rooms = rooms, doors = doors, spawnRoom = 0 }
	layout.spawnRoom = Layout.spawnRoom(layout)
	return layout
end

--[[
	`INV_layout`, one string per violated clause, each starting
	`INV_layout:<token> ` with token `room_count`, `cells`, `adjacency` or
	`connected`. A valid layout returns `{}`.
]]
function Layout.check(layout: Layout, tuning: Tuning): { string }
	local t = tuning.instance
	local report: { string } = {}
	local rooms = layout.rooms

	if #rooms ~= t.room_count then
		table.insert(report, `INV_layout:room_count {#rooms} rooms, expected {t.room_count}`)
	else
		for i, room in rooms do
			if room.id ~= i then
				table.insert(report, `INV_layout:room_count rooms[{i}] has id {room.id}`)
				break
			end
		end
	end

	local seen: { [string]: number } = {}
	for i, room in rooms do
		local key = `{room.column},{room.row}`
		if
			room.column < 1
			or room.column > t.layout_grid_columns
			or room.row < 1
			or room.row > t.layout_grid_rows
		then
			table.insert(report, `INV_layout:cells room {i} at ({key}) lies outside the grid`)
			break
		elseif seen[key] then
			table.insert(
				report,
				`INV_layout:cells rooms {seen[key]} and {i} share the cell ({key})`
			)
			break
		end
		seen[key] = i
	end

	local pairs_: { [string]: boolean } = {}
	for _, d in layout.doors do
		local ra, rb = rooms[d.a], rooms[d.b]
		local key = if d.a < d.b then `{d.a}-{d.b}` else `{d.b}-{d.a}`
		if ra == nil or rb == nil then
			table.insert(report, `INV_layout:adjacency door {d.a}-{d.b} names an unknown room`)
			break
		elseif not gridAdjacent(ra, rb) then
			table.insert(
				report,
				`INV_layout:adjacency door {key} joins rooms that are not grid-adjacent`
			)
			break
		elseif pairs_[key] then
			table.insert(report, `INV_layout:adjacency door {key} appears twice`)
			break
		end
		pairs_[key] = true
	end

	if #rooms > 0 then
		local dist = distancesFrom(doorNeighbours(layout), 1)
		for i = 1, #rooms do
			if dist[i] == math.huge then
				table.insert(report, `INV_layout:connected room {i} is not reachable from room 1`)
				break
			end
		end
	end

	return report
end

-- Doorway edges on a shortest path; `math.huge` when unreachable. Raises for
-- an id that is not an integer in `1..#layout.rooms`.
function Layout.distance(layout: Layout, a: number, b: number): number
	checkId(layout, a, "room")
	checkId(layout, b, "room")
	return distancesFrom(doorNeighbours(layout), a)[b]
end

-- The room's door-neighbours, ascending, in a fresh list on every call.
function Layout.neighbours(layout: Layout, id: number): { number }
	checkId(layout, id, "room")
	return doorNeighbours(layout)[id]
end

-- The room of least eccentricity; ties go to the lowest id.
function Layout.spawnRoom(layout: Layout): number
	local lists = doorNeighbours(layout)
	local best, bestEccentricity = 0, math.huge
	for a = 1, #layout.rooms do
		local eccentricity = 0
		for _, d in distancesFrom(lists, a) do
			eccentricity = math.max(eccentricity, d)
		end
		if best == 0 or eccentricity < bestEccentricity then
			best, bestEccentricity = a, eccentricity
		end
	end
	return best
end

return table.freeze(Layout)
