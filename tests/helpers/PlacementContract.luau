--!strict
--[[
	GEN-002's checks, statistics and fixtures, written once over a MACHINES
	MODULE rather than over `src/server/facility/Machines.luau` by name - the
	`LayoutContract` arrangement, for the same reason.

	`tests/server/machines_test.luau` applies these to the real module.
	`tests/server/machines_controls_test.luau` applies them to the deliberately
	wrong generators in `PlacementStubs.luau`, so that in RED - where the module
	does not exist, the real file fails at `require`, and not one assertion in
	it has executed - every statistic here has been EXECUTED and observed to
	reject the generator it exists to catch, and to accept a reference that is
	correct.

	NOT `MachineStubs.luau` / `MachineContract.luau`: `tests/helpers/
	MachineStubs.luau` already exists and holds ROUND-003's PHASE-MACHINE stubs.
	These two files are about machine PLACEMENT and are named for it.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE.

	  * SETTLED, EXACT PINNING. `INV_class_machines`, `INV_room_capacity`,
	    `INV_tags_distinct_in_class` and the shape half of `INV_settings_uniform`
	    (`tuning.md` §2) are re-derived INDEPENDENTLY in `violations` below, so
	    the sweeps do not take `Machines.check`'s word for it. The fixtures are
	    hand-built placements on a hand-built `Layout` value, with their expected
	    tokens written by hand; the controls file shows each trips exactly its
	    own clause in THIS checker, so a slip in a fixture fails in RED rather
	    than being blamed on GREEN. `positionOf`'s expected value is the
	    Contract's formula written out here over `room_pitch_studs`.
	  * ORACLE-FREE WITH NEGATIVE CONTROL. `settingStats` (AC-4) and
	    `extraStepCoverage` (AC-6) are pure functions of a generator; the
	    spacing minimum (AC-5) is a pure function of a `positionOf`. Their sample
	    sizes and bands are the Lead PO's, copied from the criteria verbatim: RED
	    may tighten one from a measured variance and did not need to; GREEN may
	    not move any of them (`rules.md`, "do not widen a tolerance").

	Every constant is READ from `MechanicsTuning.instance`; nothing below writes
	16, 8, 4 or 64 where a constant is meant. The only literals are the
	statistics' own sample sizes and bands, and the hand-built fixtures, which
	say which shipped values they were drawn for and are checked against them.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local Layout = require("../../src/server/facility/Layout")
local LayoutContract = require("./LayoutContract")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Rng = require("../../src/shared/Rng")

local PlacementContract = {}

export type Machine = {
	id: number,
	room: number,
	slot: number,
	keyClass: number,
	tag: number,
	requiredSetting: number,
}
export type Placement = { machines: { Machine }, stepsPerClass: { [number]: number } }
export type Layout = LayoutContract.Layout
export type Tuning = typeof(MechanicsTuning)
export type Position = { x: number, y: number, z: number }
export type Generate = (
	rng: Rng.Rng,
	layout: Layout,
	classes: { number },
	tuning: Tuning
) -> Placement
export type PositionOf = (layout: Layout, machine: Machine, tuning: Tuning) -> Position

-- The shipped tuning. Every check below reads `instance.procedure_length`,
-- `actuator_redundancy`, `actuator_count`, `tag_alphabet_size`,
-- `dial_settings`, `machine_slots_per_room`, `machines_per_room_min`,
-- `machines_per_room_max`, `room_pitch_studs` and `machine_spacing_min_studs`
-- from here, never from a literal.
PlacementContract.TUNING = MechanicsTuning

-- AC-1 to AC-6 sweep seeds 1..SWEEP_SEEDS at each n in CLASS_COUNTS.
PlacementContract.SWEEP_SEEDS = 1000
PlacementContract.CLASS_COUNTS = { 4, 5, 6 }
-- AC-4's band around 1/dial_settings. The Lead PO's; ~6 SE at 16,000 settings.
PlacementContract.SETTING_TOLERANCE = 0.02

-- The six `prefix:token` strings `check` may report, from the Contract's table.
PlacementContract.TOKENS = {
	"INV_class_machines:steps",
	"INV_class_machines:count",
	"INV_room_capacity:count",
	"INV_room_capacity:slot",
	"INV_tags_distinct_in_class:tag",
	"INV_settings_uniform:setting",
}

-- The four labels `generate` derives from the rng it is handed, sorted.
PlacementContract.DERIVE_LABELS = { "counts", "rooms", "settings", "tags" }

--[[ ------------------------------------------------------------------------
     Sweep inputs. `GEN-004` will hand this module the attempt's `"machines"`
     sub-stream and the layout built from the attempt's `"layout"` sub-stream;
     the sweep does the same from `Rng.fromSeed(seed)`. Layouts are the REAL
     `Layout.generate` (merged in GEN-001) and are cached per seed, so both
     test files and all three n share one table.
     --------------------------------------------------------------------- ]]

local layoutCache: { [number]: Layout } = {}

function PlacementContract.layoutFor(seed: number): Layout
	local cached = layoutCache[seed]
	if cached == nil then
		cached = Layout.generate(Rng.fromSeed(seed):derive("layout"), MechanicsTuning)
		layoutCache[seed] = cached
	end
	return cached
end

function PlacementContract.rngFor(seed: number): Rng.Rng
	return Rng.fromSeed(seed):derive("machines")
end

-- The key classes in play at n: `1..n` (`Ring.Assignment.keyClasses`).
function PlacementContract.classesFor(n: number): { number }
	local classes: { number } = {}
	for c = 1, n do
		classes[c] = c
	end
	return classes
end

-- Seeds 1..`seeds` at one n, through a generator. The full sweep
-- (`seeds == SWEEP_SEEDS`) is memoised per (generator, n), because every
-- statistic and every control re-walks the same seeds: without the memo the
-- controls file alone ran about forty sweeps. Placements in the cache are
-- shared, so no caller may mutate one; the purity tests snapshot first.
local sweepCache: { [Generate]: { [number]: { Placement } } } = {}

function PlacementContract.sweep(generate: Generate, n: number, seeds: number): { Placement }
	local full = seeds == PlacementContract.SWEEP_SEEDS
	if full then
		local forGenerator = sweepCache[generate]
		if forGenerator ~= nil and forGenerator[n] ~= nil then
			return forGenerator[n]
		end
	end
	local out: { Placement } = {}
	local classes = PlacementContract.classesFor(n)
	for seed = 1, seeds do
		out[seed] = generate(
			PlacementContract.rngFor(seed),
			PlacementContract.layoutFor(seed),
			classes,
			MechanicsTuning
		)
	end
	if full then
		sweepCache[generate] = sweepCache[generate] or {}
		sweepCache[generate][n] = out
	end
	return out
end

export type SweepItem = { layout: Layout, placement: Placement, label: string }

-- Every (layout, placement) of the full sweep at every n, labelled, for the
-- spacing check.
function PlacementContract.sweepItems(generate: Generate): { SweepItem }
	local items: { SweepItem } = {}
	for _, n in PlacementContract.CLASS_COUNTS do
		for seed, placement in PlacementContract.sweep(generate, n, PlacementContract.SWEEP_SEEDS) do
			items[#items + 1] = {
				layout = PlacementContract.layoutFor(seed),
				placement = placement,
				label = `n = {n} seed {seed}`,
			}
		end
	end
	return items
end

-- An Rng that records every label derived from it and counts every draw
-- taken from it DIRECTLY. The Contract says `generate` derives exactly
-- "counts", "rooms", "tags" and "settings" and draws from nothing else.
function PlacementContract.recordingRng(
	seed: number
): (Rng.Rng, { labels: { string }, directDraws: number })
	local real = PlacementContract.rngFor(seed)
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

--[[ ------------------------------------------------------------------------
     The balanced split, derived by hand: floor(L / n) steps per class, with
     L mod n classes carrying one more. AC-1's expectation is THIS arithmetic,
     never `stepsPerClass` read back from the module.
     --------------------------------------------------------------------- ]]

export type Split = { floor: number, ceil: number, ceilCount: number }

function PlacementContract.expectedSplit(n: number, tuning: Tuning): Split
	local length = tuning.instance.procedure_length
	local lower = length // n
	local extra = length % n
	return { floor = lower, ceil = if extra == 0 then lower else lower + 1, ceilCount = extra }
end

local function isInteger(x: any): boolean
	return typeof(x) == "number" and x == math.floor(x)
end

--[[ ------------------------------------------------------------------------
     The invariants, re-derived here. Returns one string per violated clause,
     each starting `<INV>:<token> ` exactly as the Contract's table says
     `check` must, so the controls file can show which clause each hand-built
     violation trips in OUR checker - which is what makes it a fair control
     for the module's `check`.
     --------------------------------------------------------------------- ]]

function PlacementContract.violations(
	placement: Placement,
	layout: Layout,
	classes: { number },
	tuning: Tuning
): { string }
	local out: { string } = {}
	local t = tuning.instance
	local machines = placement.machines
	local steps = placement.stepsPerClass
	local inPlay: { [number]: boolean } = {}
	for _, c in classes do
		inPlay[c] = true
	end

	-- INV_class_machines:steps - key set exactly `classes`, each value floor or
	-- ceil, summing to procedure_length.
	local split = PlacementContract.expectedSplit(#classes, tuning)
	local sum = 0
	for c, s in pairs(steps) do
		if not inPlay[c] then
			table.insert(
				out,
				`INV_class_machines:steps stepsPerClass has key {tostring(c)}, not a class in play`
			)
		end
		if not isInteger(s) or (s ~= split.floor and s ~= split.ceil) then
			table.insert(
				out,
				`INV_class_machines:steps stepsPerClass[{tostring(c)}] is {tostring(s)}, expected {split.floor} or {split.ceil}`
			)
		end
		if typeof(s) == "number" then
			sum += s
		end
	end
	for _, c in classes do
		if steps[c] == nil then
			table.insert(out, `INV_class_machines:steps stepsPerClass has no entry for class {c}`)
		end
	end
	if sum ~= t.procedure_length then
		table.insert(
			out,
			`INV_class_machines:steps stepsPerClass sums to {sum}, expected procedure_length {t.procedure_length}`
		)
	end

	-- INV_class_machines:count - per class actuator_redundancy × steps, every
	-- keyClass in play, total actuator_count.
	local perClass: { [number]: number } = {}
	for _, m in machines do
		if not inPlay[m.keyClass] then
			table.insert(
				out,
				`INV_class_machines:count machine {m.id} has keyClass {tostring(m.keyClass)}, not a class in play`
			)
		end
		perClass[m.keyClass] = (perClass[m.keyClass] or 0) + 1
	end
	for _, c in classes do
		local want = if typeof(steps[c]) == "number" then t.actuator_redundancy * steps[c] else nil
		if (perClass[c] or 0) ~= want then
			table.insert(
				out,
				`INV_class_machines:count class {c} has {perClass[c] or 0} machines, expected actuator_redundancy × steps = {tostring(
					want
				)}`
			)
		end
	end
	if #machines ~= t.actuator_count then
		table.insert(
			out,
			`INV_class_machines:count {#machines} machines in total, expected actuator_count {t.actuator_count}`
		)
	end

	-- INV_room_capacity:slot - slot an integer in 1..machine_slots_per_room,
	-- room a Layout room id, no (room, slot) twice.
	local knownRoom: { [number]: boolean } = {}
	for _, room in layout.rooms do
		knownRoom[room.id] = true
	end
	local perRoom: { [number]: number } = {}
	local slotSeen: { [string]: number } = {}
	for _, m in machines do
		if not knownRoom[m.room] then
			table.insert(
				out,
				`INV_room_capacity:slot machine {m.id} names unknown room {tostring(m.room)}`
			)
		else
			perRoom[m.room] = (perRoom[m.room] or 0) + 1
		end
		if not isInteger(m.slot) or m.slot < 1 or m.slot > t.machine_slots_per_room then
			table.insert(
				out,
				`INV_room_capacity:slot machine {m.id} has slot {tostring(m.slot)}, outside 1..{t.machine_slots_per_room}`
			)
		end
		local key = `{tostring(m.room)}/{tostring(m.slot)}`
		if slotSeen[key] ~= nil then
			table.insert(
				out,
				`INV_room_capacity:slot machines {slotSeen[key]} and {m.id} share room {tostring(
					m.room
				)} slot {tostring(m.slot)}`
			)
		else
			slotSeen[key] = m.id
		end
	end

	-- INV_room_capacity:count - every room within min..max.
	for _, room in layout.rooms do
		local count = perRoom[room.id] or 0
		if count < t.machines_per_room_min or count > t.machines_per_room_max then
			table.insert(
				out,
				`INV_room_capacity:count room {room.id} holds {count} machines, outside {t.machines_per_room_min}..{t.machines_per_room_max}`
			)
		end
	end

	-- INV_tags_distinct_in_class:tag - in 1..tag_alphabet_size, distinct per class.
	local tagSeen: { [string]: number } = {}
	for _, m in machines do
		if not isInteger(m.tag) or m.tag < 1 or m.tag > t.tag_alphabet_size then
			table.insert(
				out,
				`INV_tags_distinct_in_class:tag machine {m.id} has tag {tostring(m.tag)}, outside 1..{t.tag_alphabet_size}`
			)
		end
		local key = `{tostring(m.keyClass)}/{tostring(m.tag)}`
		if tagSeen[key] ~= nil then
			table.insert(
				out,
				`INV_tags_distinct_in_class:tag machines {tagSeen[key]} and {m.id} in class {tostring(
					m.keyClass
				)} both carry tag {tostring(m.tag)}`
			)
		else
			tagSeen[key] = m.id
		end
	end

	-- INV_settings_uniform:setting - present, an integer in 1..dial_settings.
	for _, m in machines do
		local s = (m :: any).requiredSetting
		if not isInteger(s) or s < 1 or s > t.dial_settings then
			table.insert(
				out,
				`INV_settings_uniform:setting machine {m.id} has requiredSetting {tostring(s)}, not an integer in 1..{t.dial_settings}`
			)
		end
	end

	return out
end

-- The Contract's listing rule, asserted on generated placements and never by
-- `check` (the table has no token for it): `machines[i].id == i`, ids in
-- strictly ascending (room, slot) order.
function PlacementContract.orderProblems(placement: Placement): { string }
	local out: { string } = {}
	local machines = placement.machines
	for i, m in machines do
		if m.id ~= i then
			table.insert(out, `machines[{i}].id is {tostring(m.id)}`)
		end
		if i > 1 then
			local p = machines[i - 1]
			if p.room > m.room or (p.room == m.room and p.slot >= m.slot) then
				table.insert(
					out,
					`machines {i - 1} (room {p.room}, slot {p.slot}) and {i} (room {m.room}, slot {m.slot}) are not in ascending (room, slot) order`
				)
			end
		end
	end
	return out
end

-- The violations whose string starts with `prefix` (an invariant name).
function PlacementContract.withPrefix(strings: { string }, prefix: string): { string }
	local out: { string } = {}
	for _, s in strings do
		if string.sub(s, 1, #prefix) == prefix then
			table.insert(out, s)
		end
	end
	return out
end

-- The `prefix:token` heads in a list of `check` strings. A string that does
-- not have the Contract's shape - one of the six heads, then a SPACE - goes
-- in `malformed`, so a needle can never be satisfied by text that merely
-- contains it (`rules.md`, "the needle is part of the assertion"). `tokens`
-- is the sorted list of DISTINCT heads found.
function PlacementContract.parseTokens(
	strings: { string }
): { tokens: { string }, malformed: { string } }
	local found: { [string]: boolean } = {}
	local malformed: { string } = {}
	for _, s in strings do
		local matched = false
		if typeof(s) == "string" then
			for _, token in PlacementContract.TOKENS do
				local head = `{token} `
				if string.sub(s, 1, #head) == head then
					found[token] = true
					matched = true
					break
				end
			end
		end
		if not matched then
			table.insert(malformed, tostring(s))
		end
	end
	local tokens: { string } = {}
	for token in pairs(found) do
		table.insert(tokens, token)
	end
	table.sort(tokens)
	return { tokens = tokens, malformed = malformed }
end

--[[ ------------------------------------------------------------------------
     positionOf, derived by hand (story `## Contract`): centre(room) +
     (sx, 0, sz) × room_pitch_studs / 4, with (sx, sz) = (−1,−1), (+1,−1),
     (−1,+1), (+1,+1) for slots 1..4, and centre(room) =
     ((column − 1) × pitch, 0, (row − 1) × pitch). Horizontal (x, z) distance
     everywhere, because the facility is one storey (`architecture.md` §9.8).
     --------------------------------------------------------------------- ]]

PlacementContract.QUADRANTS = {
	[1] = { sx = -1, sz = -1 },
	[2] = { sx = 1, sz = -1 },
	[3] = { sx = -1, sz = 1 },
	[4] = { sx = 1, sz = 1 },
}

function PlacementContract.roomById(layout: Layout, id: number): LayoutContract.Room
	for _, room in layout.rooms do
		if room.id == id then
			return room
		end
	end
	error(`no room {id} in the layout`)
end

function PlacementContract.expectedPosition(
	layout: Layout,
	room: number,
	slot: number,
	tuning: Tuning
): Position
	local r = PlacementContract.roomById(layout, room)
	local pitch = tuning.instance.room_pitch_studs
	local q = PlacementContract.QUADRANTS[slot]
	assert(q ~= nil, `slot {slot} has no quadrant; the Contract maps slots 1..4`)
	return {
		x = (r.column - 1) * pitch + q.sx * pitch / 4,
		y = 0,
		z = (r.row - 1) * pitch + q.sz * pitch / 4,
	}
end

function PlacementContract.horizontalDistance(a: Position, b: Position): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

export type SpacingStats = { min: number, pair: string, pairs: number }

-- The least horizontal distance between any two machines of one placement,
-- through `positionOf`.
function PlacementContract.minSpacing(
	positionOf: PositionOf,
	layout: Layout,
	placement: Placement,
	tuning: Tuning
): SpacingStats
	local positions: { Position } = {}
	for i, m in placement.machines do
		positions[i] = positionOf(layout, m, tuning)
	end
	local best, pair, count = math.huge, "", 0
	for i = 1, #positions do
		for j = i + 1, #positions do
			count += 1
			local d = PlacementContract.horizontalDistance(positions[i], positions[j])
			if d < best then
				local a, b = placement.machines[i], placement.machines[j]
				best = d
				pair =
					`machines {a.id} (room {a.room} slot {a.slot}) and {b.id} (room {b.room} slot {b.slot})`
			end
		end
	end
	return { min = best, pair = pair, pairs = count }
end

-- AC-5's second clause over a list of (layout, placement) pairs: assert once,
-- naming the closest pair.
function PlacementContract.assertSpacing(
	positionOf: PositionOf,
	items: { SweepItem },
	tuning: Tuning
): SpacingStats
	local worst: SpacingStats = { min = math.huge, pair = "", pairs = 0 }
	local where = ""
	for _, item in items do
		local s = PlacementContract.minSpacing(positionOf, item.layout, item.placement, tuning)
		worst.pairs += s.pairs
		if s.min < worst.min then
			worst.min, worst.pair, where = s.min, s.pair, item.label
		end
	end
	local floor = tuning.instance.machine_spacing_min_studs
	assert(
		worst.min >= floor,
		`AC-5: two machines are only {string.format("%.3f", worst.min)} studs apart horizontally ({where}: {worst.pair}); machine_spacing_min_studs is {floor}`
	)
	return worst
end

--[[ ------------------------------------------------------------------------
     Statistics. Each takes the generator and returns what it measured; each
     `assert*` turns the measurement into a pass or a raise with the numbers
     in the message. The controls file records those numbers.
     --------------------------------------------------------------------- ]]

export type SettingStats = {
	n: number,
	machines: number, -- pooled over the sweep
	missing: number, -- requiredSetting nil, not a number, not an integer, or out of range
	missingExamples: { string },
	counts: { [number]: number }, -- per value 1..dial_settings
	frequencies: { [number]: number },
	min: number,
	max: number,
	minValue: number,
	maxValue: number,
}

-- AC-4: settings pooled over every machine of every seed at one n.
function PlacementContract.settingStats(generate: Generate, n: number, seeds: number): SettingStats
	local d = MechanicsTuning.instance.dial_settings
	local counts: { [number]: number } = {}
	for v = 1, d do
		counts[v] = 0
	end
	local total, missing = 0, 0
	local examples: { string } = {}
	for seed, placement in PlacementContract.sweep(generate, n, seeds) do
		for _, m in placement.machines do
			total += 1
			local s = (m :: any).requiredSetting
			if isInteger(s) and s >= 1 and s <= d then
				counts[s] += 1
			else
				missing += 1
				if #examples < 5 then
					table.insert(examples, `seed {seed} machine {m.id}: {tostring(s)}`)
				end
			end
		end
	end
	local stats: SettingStats = {
		n = n,
		machines = total,
		missing = missing,
		missingExamples = examples,
		counts = counts,
		frequencies = {},
		min = math.huge,
		max = -math.huge,
		minValue = 0,
		maxValue = 0,
	}
	for v = 1, d do
		local f = if total == 0 then 0 else counts[v] / total
		stats.frequencies[v] = f
		if f < stats.min then
			stats.min, stats.minValue = f, v
		end
		if f > stats.max then
			stats.max, stats.maxValue = f, v
		end
	end
	return stats
end

function PlacementContract.describeSettingStats(stats: SettingStats): string
	local parts: { string } = {}
	for v = 1, MechanicsTuning.instance.dial_settings do
		table.insert(parts, `{v}: {string.format("%.4f", stats.frequencies[v])}`)
	end
	return `n = {stats.n}, {stats.machines} settings over seeds 1..{PlacementContract.SWEEP_SEEDS}: [{table.concat(
		parts,
		", "
	)}], min {string.format("%.4f", stats.min)} (setting {stats.minValue}), max {string.format(
		"%.4f",
		stats.max
	)} (setting {stats.maxValue}), missing {stats.missing}`
end

function PlacementContract.assertSettingsUniform(generate: Generate, n: number): SettingStats
	local stats = PlacementContract.settingStats(generate, n, PlacementContract.SWEEP_SEEDS)
	local d = MechanicsTuning.instance.dial_settings
	local target = 1 / d
	local lo, hi =
		target - PlacementContract.SETTING_TOLERANCE, target + PlacementContract.SETTING_TOLERANCE
	assert(stats.machines > 0, `AC-4: the sweep at n = {n} produced no machines at all`)
	assert(
		stats.missing == 0,
		`AC-4: {stats.missing} of {stats.machines} machines at n = {n} are without a setting that is an integer in 1..{d} (first: {table.concat(
			stats.missingExamples,
			"; "
		)}) - {PlacementContract.describeSettingStats(stats)}`
	)
	assert(
		stats.min >= lo and stats.max <= hi,
		`AC-4: setting frequencies at n = {n} are not uniform within 1/{d} ± {PlacementContract.SETTING_TOLERANCE} ([{string.format(
			"%.4f",
			lo
		)}, {string.format("%.4f", hi)}]) - {PlacementContract.describeSettingStats(stats)}`
	)
	return stats
end

export type ExtraStepStats = {
	n: number,
	tally: { [number]: number }, -- seeds in which class c carried a ceil step count
	never: { number }, -- classes that never did
	extraPerSeed: number, -- procedure_length mod n, by hand
	total: number, -- Σ tally
}

-- AC-6: which classes received the extra step, over the sweep at one n.
function PlacementContract.extraStepCoverage(
	generate: Generate,
	n: number,
	seeds: number
): ExtraStepStats
	local split = PlacementContract.expectedSplit(n, MechanicsTuning)
	local tally: { [number]: number } = {}
	for c = 1, n do
		tally[c] = 0
	end
	local total = 0
	for _, placement in PlacementContract.sweep(generate, n, seeds) do
		for c = 1, n do
			if split.ceilCount > 0 and placement.stepsPerClass[c] == split.ceil then
				tally[c] += 1
				total += 1
			end
		end
	end
	local never: { number } = {}
	for c = 1, n do
		if tally[c] == 0 then
			table.insert(never, c)
		end
	end
	return { n = n, tally = tally, never = never, extraPerSeed = split.ceilCount, total = total }
end

function PlacementContract.describeExtraSteps(stats: ExtraStepStats): string
	local parts: { string } = {}
	for c = 1, stats.n do
		table.insert(parts, `class {c}: {stats.tally[c]}`)
	end
	return `n = {stats.n}, seeds 1..{PlacementContract.SWEEP_SEEDS}, {stats.extraPerSeed} extra step(s) per seed: [{table.concat(
		parts,
		", "
	)}]`
end

function PlacementContract.assertExtraStepCoverage(generate: Generate, n: number): ExtraStepStats
	local stats = PlacementContract.extraStepCoverage(generate, n, PlacementContract.SWEEP_SEEDS)
	assert(
		stats.total == stats.extraPerSeed * PlacementContract.SWEEP_SEEDS,
		`AC-6: {stats.total} ceil step counts were tallied at n = {n}; the balanced split gives exactly {stats.extraPerSeed} per seed - {PlacementContract.describeExtraSteps(
			stats
		)}`
	)
	assert(
		#stats.never == 0,
		`AC-6: class(es) {table.concat(stats.never, ", ")} never received the extra step at n = {n} over seeds 1..{PlacementContract.SWEEP_SEEDS}; the choice must be drawn, not always the lowest classes - {PlacementContract.describeExtraSteps(
			stats
		)}`
	)
	return stats
end

--[[ ------------------------------------------------------------------------
     Hand-built fixtures.

     THE LAYOUT is GEN-001's "square" fixture: the 2 × 3 block, ids row-major

         1 2 3
         4 5 6

     with doors 1-2 1-4 2-3 2-5 4-5 5-6. Only its rooms matter here. Positions
     are also asserted on GEN-001's five-room "plus", whose rooms are not the
     block, so a `positionOf` that assumes room id == cell index fails.

     THE PLACEMENTS were drawn BY HAND for the shipped constants - 16 machines
     (procedure_length 8 × redundancy 2), 6 rooms, 4 slots, 4 tags, 4 dial
     settings - and the controls file checks those assumptions against the
     read constants, so a tuning change fails there with a message rather
     than here with a puzzle. Sixteen machines in (room, slot) order: rooms
     1..4 hold slots 1..3, rooms 5 and 6 hold slots 1..2. The class of each
     machine is a hand-written list per n giving the balanced sizes
     4,4,4,4 / 4,4,4,2,2 / 4,4,2,2,2,2; a machine's tag is its ordinal within
     its class, so tags are 1..size and distinct; settings are a hand-written
     list in 1..4.
     --------------------------------------------------------------------- ]]

PlacementContract.FIXTURE_LAYOUT = LayoutContract.layoutOf(LayoutContract.FIXTURES[2])
PlacementContract.PLUS_LAYOUT = LayoutContract.layoutOf(LayoutContract.FIXTURES[4])

local FIXTURE_SLOTS: { { number } } = {
	{ 1, 1 },
	{ 1, 2 },
	{ 1, 3 },
	{ 2, 1 },
	{ 2, 2 },
	{ 2, 3 },
	{ 3, 1 },
	{ 3, 2 },
	{ 3, 3 },
	{ 4, 1 },
	{ 4, 2 },
	{ 4, 3 },
	{ 5, 1 },
	{ 5, 2 },
	{ 6, 1 },
	{ 6, 2 },
}

local FIXTURE_CLASSES: { [number]: { number } } = {
	[4] = { 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4 },
	[5] = { 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 1, 2, 3 },
	[6] = { 1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 1, 2, 1, 2 },
}

local FIXTURE_STEPS: { [number]: { number } } = {
	[4] = { 2, 2, 2, 2 },
	[5] = { 2, 2, 2, 1, 1 },
	[6] = { 2, 2, 1, 1, 1, 1 },
}

local FIXTURE_SETTINGS = { 1, 2, 3, 4, 4, 3, 2, 1, 1, 3, 2, 4, 2, 4, 1, 3 }

-- What the hand-drawn fixtures were drawn for. The controls file asserts each
-- against the read constant; the test files never write these numbers.
PlacementContract.FIXTURE_ASSUMES = {
	machines = #FIXTURE_SLOTS,
	rooms = #PlacementContract.FIXTURE_LAYOUT.rooms,
	slots = 3,
	tags = 4,
	dialSettings = 4,
	procedureLength = 8,
}

-- A fresh valid placement for n in 4..6.
function PlacementContract.validPlacement(n: number): Placement
	local classList = FIXTURE_CLASSES[n]
	assert(classList ~= nil, `no hand-built placement for n = {n}`)
	local nextTag: { [number]: number } = {}
	local machines: { Machine } = {}
	for i, rs in FIXTURE_SLOTS do
		local c = classList[i]
		nextTag[c] = (nextTag[c] or 0) + 1
		machines[i] = {
			id = i,
			room = rs[1],
			slot = rs[2],
			keyClass = c,
			tag = nextTag[c],
			requiredSetting = FIXTURE_SETTINGS[i],
		}
	end
	return { machines = machines, stepsPerClass = table.clone(FIXTURE_STEPS[n]) }
end

--[[
	The violation fixtures. Each is a valid placement with the fewest edits
	that trip the clause it is named for, and `expect` is the EXACT sorted list
	of heads `check` must report - written by hand from the Contract's table.
	Where one edit necessarily trips two clauses the list says so: a class of
	five machines cannot carry five distinct tags from a four-shape alphabet,
	so AC-1's own control is `count` AND `tag`.
]]
export type Violation = { name: string, n: number, expect: { string }, placement: Placement }

function PlacementContract.violationFixtures(): { Violation }
	local t = MechanicsTuning.instance
	local out: { Violation } = {}

	local function add(name: string, n: number, expect: { string }, edit: (Placement) -> ())
		local p = PlacementContract.validPlacement(n)
		edit(p)
		table.sort(expect)
		table.insert(out, { name = name, n = n, expect = expect, placement = p })
	end

	add("stepsPerClass carries a key that is not a class in play", 4, {
		"INV_class_machines:steps",
	}, function(p)
		p.stepsPerClass[5] = 0
	end)

	add(
		"stepsPerClass sums to more than procedure_length, so a class also has too few machines",
		4,
		{ "INV_class_machines:steps", "INV_class_machines:count" },
		function(p)
			p.stepsPerClass[4] += 1
		end
	)

	-- AC-1's control: class 1 gets a fifth machine (machine 9 moves over from
	-- class 4). Five machines, four tags: `tag` fires as well, by pigeonhole.
	add("one class has 5 machines (AC-1's control)", 5, {
		"INV_class_machines:count",
		"INV_tags_distinct_in_class:tag",
	}, function(p)
		p.machines[9].keyClass = 1
		p.machines[9].tag = 1
	end)

	-- Machine 9 (class 4, tag 2) moves to class 5 with the next free tag there:
	-- class 5 has three machines and class 4 one, and nothing else is wrong.
	add("one class has a machine too many and another one too few", 5, {
		"INV_class_machines:count",
	}, function(p)
		p.machines[9].keyClass = 5
		p.machines[9].tag = 3
	end)

	add("a machine's keyClass is not a class in play", 4, {
		"INV_class_machines:count",
	}, function(p)
		p.machines[16].keyClass = 5
	end)

	add("the total is one short of actuator_count", 4, {
		"INV_class_machines:count",
	}, function(p)
		table.remove(p.machines)
	end)

	-- Room 6's two machines move to room 5's free slots 3 and 4: room 6 is empty.
	add("an empty room", 4, { "INV_room_capacity:count" }, function(p)
		p.machines[15].room, p.machines[15].slot = 5, 3
		p.machines[16].room, p.machines[16].slot = 5, 4
	end)

	add("two machines in one slot", 4, { "INV_room_capacity:slot" }, function(p)
		p.machines[2].slot = 1
	end)

	add("a slot above machine_slots_per_room", 4, { "INV_room_capacity:slot" }, function(p)
		p.machines[2].slot = t.machine_slots_per_room + 1
	end)

	add("slot 0", 4, { "INV_room_capacity:slot" }, function(p)
		p.machines[2].slot = 0
	end)

	add("a machine in a room the layout does not have", 4, {
		"INV_room_capacity:slot",
	}, function(p)
		p.machines[16].room = #PlacementContract.FIXTURE_LAYOUT.rooms + 1
	end)

	-- Machine 5 is class 1's second machine (tag 2); tagged 3 it collides with
	-- machine 9, class 1's third. AC-3's control.
	add("a class with two machines tagged 3 (AC-3's control)", 4, {
		"INV_tags_distinct_in_class:tag",
	}, function(p)
		p.machines[5].tag = 3
	end)

	add("a tag outside the alphabet", 4, { "INV_tags_distinct_in_class:tag" }, function(p)
		p.machines[5].tag = t.tag_alphabet_size + 1
	end)

	add("a machine without a requiredSetting", 4, { "INV_settings_uniform:setting" }, function(p)
		(p.machines[7] :: any).requiredSetting = nil
	end)

	add("a requiredSetting above dial_settings", 4, { "INV_settings_uniform:setting" }, function(p)
		p.machines[7].requiredSetting = t.dial_settings + 1
	end)

	add("a requiredSetting of 0", 4, { "INV_settings_uniform:setting" }, function(p)
		p.machines[7].requiredSetting = 0
	end)

	add(
		"a requiredSetting that is not an integer",
		4,
		{ "INV_settings_uniform:setting" },
		function(p)
			p.machines[7].requiredSetting = 2.5
		end
	)

	return out
end

-- A deep snapshot, for the purity checks.
function PlacementContract.snapshot(value: any): any
	return Deep.copy(value)
end

return PlacementContract
