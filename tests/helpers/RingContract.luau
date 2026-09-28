--!strict
--[[
	SEAT-001 AC-1 through AC-7 written once, as checks over a RING MODULE rather
	than over `src/server/seats/Ring.luau` by name - the same arrangement as
	`PhaseMachineContract.luau` and `RoundEndingContract.luau`, and for the same
	reason.

	`tests/server/ring_test.luau` applies these to the real module.
	`tests/server/ring_controls_test.luau` applies them to the deliberately wrong
	generators in `RingStubs.luau`, so that in RED - where the production module
	does not exist, the real file fails at `require`, and not one assertion in it
	has executed - every check here has still been EXECUTED and observed to
	reject the implementation it exists to catch.

	A `ring` here is anything with six plain field functions, called with a dot
	exactly as the stories' Contracts write them:

	    ring.assign(players, rng)          -> Assignment
	    ring.lensOf(assignment, p)         -> KeyClass    (assignment.lens[p], PO-1)
	    ring.supplierOf(assignment, p)     -> PlayerId    (σ⁻¹(p), the predecessor)
	    ring.dependentOf(assignment, p)    -> PlayerId    (σ(p),   the successor)
	    ring.withdraw(assignment, q)       -> Assignment  (SEAT-003)
	    ring.rejoin(assignment, absence, now) -> Assignment?  (SEAT-003)

	and an `Assignment` is `{ players, sigma, keyClasses, lens }` with `players`
	in seat order, `sigma[p]` = σ(p), `keyClasses[p]` = the LIST of classes p
	holds (one at deal time; SEAT-003's transfer makes it two) and `lens[p]` =
	λ(p), stored at deal time and never recomputed. SEAT-003 replaced the
	singular `keyClass` map; the checks from SEAT-001 below read the new shape
	and assert the same properties they always did.

	SEAT-003's checks are the second half of this file. They build every
	withdrawal from a ring `assign` dealt, so a ring whose `assign` is wrong
	fails SEAT-001's checks first and SEAT-003's say nothing new.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1, AC-2, AC-4, AC-6 and AC-7 are
	SETTLED by `roles.md` §2 and §6 and `tuning.md` §1, and the checks below read
	those properties out - no fixed point, one orbit, `λ(p) = k(σ(p))`, minimum 3,
	input untouched. Nothing here invents a seating scheme: how the cycle is
	built, which player gets which key class, and what the error at `n < 3` says
	are all the implementer's. AC-5 is the one oracle-free criterion, and its
	10,000-seed sample and 8-25% band are copied from the Contract verbatim:
	they are NOT tuned here and must not be tuned in GREEN (`rules.md`, "do not
	widen a tolerance").

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")
local Rng = require("../../src/shared/Rng")

local RingContract = {}

export type Ring = any
export type Assignment = any

--[[
	Seat names that are neither sorted nor numbered. AC-7 says the seat order in
	the result matches the INPUT order, and an implementation that sorted its
	players would pass that against `{ "p1", "p2", "p3", "p4" }` and fail it
	against these.
]]
local NAMES = { "kim", "zed", "amy", "bob", "eve", "raj" }

function RingContract.seated(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = NAMES[i]
	end
	return out
end

-- Every `n` a criterion says "for every n" over: `min_players_to_continue` (3)
-- up to `players_max` (6), both settled in `tuning.md` §1.
RingContract.COUNTS = { 3, 4, 5, 6 }

--[[
	THE SEED SAMPLE FOR THE PER-SEED STRUCTURAL CHECKS, and why it is 64.

	AC-2's control is a plain derangement generator, and at `n = 4` a plain
	derangement is a single cycle 6 times in 9. A check over ONE seed therefore
	lets that control through two times in three, and the story says so. Over 64
	independent seeds the control passes only if all 64 land on a cycle:
	(2/3)^64 ≈ 5e-12, so a plain derangement generator cannot pass by luck. At
	`n = 5` (24 cycles of 44 derangements) and `n = 6` (120 of 265) the odds per
	seed are worse for the control, and at `n = 3` both derangements are cycles,
	so `n = 3` is where AC-2 cannot discriminate and AC-1 does the work.

	The seeds are fixed rather than drawn, because a check that fails must fail
	the same way twice.
]]
local SEED_COUNT = 64
local SEEDS: { number } = {}
for i = 1, SEED_COUNT do
	SEEDS[i] = 1000 + i
end
RingContract.SEEDS = SEEDS

-- The rng every check hands to `assign`: the real one from ROUND-001, from a
-- fresh seed each call, so that reproducibility is a claim about the seed and
-- not about a stream two calls happen to share.
function RingContract.rngFor(seed: number): Rng.Rng
	return Rng.fromSeed(seed)
end

local function isSeated(players: { string }, id: any): boolean
	for _, p in players do
		if p == id then
			return true
		end
	end
	return false
end

--[[
	A ring rendered as one string in SEAT order, `kim>zed,zed>amy,...`, so that
	two rings can be tallied and compared as keys. Non-cyclic σ render just as
	well, which is what lets AC-5's tally count "something that is not one of
	the six" without a special case.
]]
function RingContract.ringKey(assignment: Assignment): string
	local parts: { string } = {}
	for _, p in assignment.players do
		table.insert(parts, `{p}>{tostring(assignment.sigma[p])}`)
	end
	return table.concat(parts, ",")
end

-- The orbit of `start` under σ, up to `limit` steps, as a list of names. Bounded
-- so that a σ that is not even a function (nil somewhere) cannot spin forever.
local function orbit(sigma: { [string]: string }, start: string, limit: number): { string }
	local visited: { string } = { start }
	local at = start
	for _ = 1, limit do
		local nextAt = sigma[at]
		if nextAt == nil or nextAt == start then
			break
		end
		table.insert(visited, nextAt)
		at = nextAt
	end
	return visited
end

local function render(list: { string }): string
	return table.concat(list, " → ")
end

local function firstFew(list: { string }, count: number): string
	local shown: { string } = {}
	for i = 1, math.min(count, #list) do
		shown[i] = list[i]
	end
	local more = #list - #shown
	return table.concat(shown, "\n") .. (if more > 0 then `\n  ... and {more} more` else "")
end

--[[
	`error(message, 2)` rather than `assert`. MEASURED (SEAT-002): under Lune
	`assert(false, message)` truncates the message to 512 characters after the
	location prefix and `error(message)` does not. AC-6's degenerate-ring
	rendering grew past that cut when SEAT-003 widened the Assignment, and a
	control whose needle lies beyond the cut can never match. Level 2
	attributes the failure to the test that called the check.
]]
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

--[[ AC-1. σ is a permutation of exactly the seated players with no fixed point. ]]
function RingContract.sigmaIsAFixedPointFreePermutation(ring: Ring)
	local violations: { string } = {}
	local total = 0

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		for _, seed in SEEDS do
			total += 1
			local assignment = ring.assign(players, RingContract.rngFor(seed))
			local problems: { string } = {}
			local seen: { [string]: boolean } = {}

			for _, p in players do
				local q = assignment.sigma[p]
				if q == nil then
					table.insert(problems, `σ({p}) is nil`)
				elseif not isSeated(players, q) then
					table.insert(problems, `σ({p}) = {tostring(q)}, who is not seated`)
				elseif q == p then
					table.insert(problems, `σ({p}) = {p}, a fixed point`)
				elseif seen[q] then
					table.insert(problems, `σ maps two players to {q}`)
				else
					seen[q] = true
				end
			end
			for key in pairs(assignment.sigma) do
				if not isSeated(players, key) then
					table.insert(problems, `σ has an entry for {tostring(key)}, who is not seated`)
				end
			end

			if #problems > 0 then
				table.insert(
					violations,
					`  n = {n}, seed {seed}: {table.concat(problems, "; ")} `
						.. `(σ = {RingContract.ringKey(assignment)})`
				)
			end
		end
	end

	assert(
		#violations == 0,
		`AC-1: σ is not a fixed-point-free permutation of the seated players in `
			.. `{#violations} of {total} (n, seed) cases:\n{firstFew(violations, 8)}`
	)
end

--[[
	AC-2. The orbit of a player under σ visits all n before returning.

	The per-n breakdown is in the message on purpose: the story's control is
	specified AT n = 4, and the number of seeds on which it produced two 2-cycles
	is the measurement the handoff records.
]]
function RingContract.sigmaIsASingleCycle(ring: Ring)
	local violations: { string } = {}
	local perCount: { string } = {}
	local total = 0

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		local failedHere = 0
		for _, seed in SEEDS do
			total += 1
			local assignment = ring.assign(players, RingContract.rngFor(seed))
			local visited = orbit(assignment.sigma, players[1], n + 1)
			if #visited ~= n then
				failedHere += 1
				table.insert(
					violations,
					`  n = {n}, seed {seed}: the orbit of {players[1]} is {render(visited)} `
						.. `(length {#visited} of {n}); σ = {RingContract.ringKey(assignment)}`
				)
			end
		end
		table.insert(perCount, `n = {n}: {failedHere} of {SEED_COUNT} seeds`)
	end

	assert(
		#violations == 0,
		`AC-2: σ is not a single n-cycle in {#violations} of {total} (n, seed) cases `
			.. `[{table.concat(perCount, "; ")}]. Two disjoint cycles are two independent `
			.. `games sharing a map (roles.md §2):\n{firstFew(violations, 8)}`
	)
end

--[[ AC-3, first half: same seed, same seated list, identical Assignment. ]]
function RingContract.sameSeedSameAssignment(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		for _, seed in { 1, 42, 20260916 } do
			local first = ring.assign(players, RingContract.rngFor(seed))
			local second = ring.assign(players, RingContract.rngFor(seed))
			local difference = Deep.diff(first, second)
			if difference ~= "" then
				table.insert(violations, `  n = {n}, seed {seed}:\n{difference}`)
			end
		end
	end

	assert(
		#violations == 0,
		`AC-3: the same seed and seated list produced two different assignments in `
			.. `{#violations} case(s):\n{firstFew(violations, 4)}`
	)
end

-- The seeds AC-3's second half samples: a small spread, fixed, at every n.
local DIVERGENCE_SEEDS = { 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597 }

--[[
	AC-3, second half: across a sample of seeds at least two different rings
	appear. This is the half a seed-ignoring generator fails, and it is the only
	half most reproducibility tests bother with the inverse of.
]]
function RingContract.differentSeedsProduceDifferentRings(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		local distinct: { [string]: boolean } = {}
		local count = 0
		for _, seed in DIVERGENCE_SEEDS do
			local key = RingContract.ringKey(ring.assign(players, RingContract.rngFor(seed)))
			if not distinct[key] then
				distinct[key] = true
				count += 1
			end
		end
		if count < 2 then
			local only = next(distinct)
			table.insert(
				violations,
				`  n = {n}: {#DIVERGENCE_SEEDS} seeds produced {count} distinct ring(s): `
					.. tostring(only)
			)
		end
	end

	assert(
		#violations == 0,
		`AC-3: different seeds did not produce different rings, so the seed is not being `
			.. `used, at {#violations} value(s) of n:\n{firstFew(violations, 4)}`
	)
end

-- A smaller seed sample for the AC-4 checks: they are per-player and per-seed,
-- and the direction of σ does not vary with the seed.
local KEY_SEEDS = { 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008 }

--[[
	AC-4, the key half: at deal time every seated player holds exactly ONE key
	class - `keyClasses[p]` is a one-element list - and the classes held are
	exactly the integers 1..n, each once. The list shape is SEAT-003's; the
	property is SEAT-001's, unchanged.
]]
function RingContract.keyClassesAreOneToNEachOnce(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		for _, seed in KEY_SEEDS do
			local assignment = ring.assign(players, RingContract.rngFor(seed))
			local problems: { string } = {}
			local held: { number } = {}

			local classes = assignment.keyClasses
			if typeof(classes) ~= "table" then
				table.insert(problems, `assignment.keyClasses is {typeof(classes)}, not a table`)
				classes = {}
			end
			for _, p in players do
				local list = classes[p]
				if typeof(list) ~= "table" then
					table.insert(problems, `keyClasses[{p}] = {Deep.show(list)}, not a list`)
				elseif #list ~= 1 then
					table.insert(
						problems,
						`keyClasses[{p}] = {Deep.show(list)} holds {#list} class(es); a dealt ring `
							.. `gives every player exactly one`
					)
				else
					local k = list[1]
					if typeof(k) ~= "number" or k ~= math.floor(k) then
						table.insert(problems, `k({p}) = {Deep.show(k)}, not an integer`)
					else
						table.insert(held, k)
					end
				end
			end
			for key in pairs(classes) do
				if not isSeated(players, key) then
					table.insert(problems, `a key class for {tostring(key)}, who is not seated`)
				end
			end

			table.sort(held)
			local expected: { number } = {}
			for i = 1, n do
				expected[i] = i
			end
			if #problems == 0 and not Deep.equal(held, expected) then
				table.insert(
					problems,
					`the key classes held are {Deep.show(held)}, wanted {Deep.show(expected)}`
				)
			end

			if #problems > 0 then
				table.insert(violations, `  n = {n}, seed {seed}: {table.concat(problems, "; ")}`)
			end
		end
	end

	assert(
		#violations == 0,
		`AC-4: the key classes are not the integers 1..n each used once, in {#violations} `
			.. `case(s):\n{firstFew(violations, 8)}`
	)
end

--[[
	AC-4, the direction half, and THE assertion the Contract warns about.

	`λ(p) = k(σ(p))`: the lens reads the DEPENDENT's key class - the successor,
	the one player whose actuators only `p` can see - and never the supplier's.
	Getting this backwards produces a game that still works and is wrong in a way
	no structural test catches, so all three relations are asserted per player:

	    lens[p] == lensOf(p)       == k(σ(p))     (stored at deal time, PO-1)
	    dependentOf(p)             == σ(p)
	    supplierOf(dependentOf(p)) == p      and      σ(supplierOf(p)) == p

	The lens message names the supplier's key class as well as the dependent's,
	so that the failure for a backwards implementation reads as "the lens is
	reading the supplier" rather than as a mystery number. `k(q)` at deal time
	is the one class in `keyClasses[q]`.
]]
local function dealtClass(assignment: Assignment, playerId: any): any
	if playerId == nil or typeof(assignment.keyClasses) ~= "table" then
		return nil
	end
	local held = assignment.keyClasses[playerId]
	return if typeof(held) == "table" then held[1] else nil
end

function RingContract.lensIsTheDependentsKeyClass(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		for _, seed in KEY_SEEDS do
			local assignment = ring.assign(players, RingContract.rngFor(seed))
			local problems: { string } = {}

			local inverse: { [string]: string } = {}
			for _, p in players do
				local q = assignment.sigma[p]
				if typeof(q) == "string" then
					inverse[q] = p
				end
			end

			for _, p in players do
				local dependent = assignment.sigma[p]
				local supplier = inverse[p]
				local lens = ring.lensOf(assignment, p)
				local stored = if typeof(assignment.lens) == "table"
					then assignment.lens[p]
					else nil
				local dependentKey = dealtClass(assignment, dependent)
				local supplierKey = dealtClass(assignment, supplier)

				if lens ~= dependentKey then
					table.insert(
						problems,
						`λ({p}) = {Deep.show(lens)}, but k(σ({p})) = k({tostring(dependent)}) = `
							.. `{Deep.show(dependentKey)} - the lens must read the DEPENDENT's key `
							.. `class; the supplier {tostring(supplier)} holds {Deep.show(
								supplierKey
							)}`
					)
				end
				if stored ~= dependentKey then
					table.insert(
						problems,
						`lens[{p}] = {Deep.show(stored)} is stored on the assignment, but k(σ({p})) = `
							.. `{Deep.show(dependentKey)} - the lens is dealt as k(σ(p)) and STORED (PO-1)`
					)
				end
				if lens ~= stored then
					table.insert(
						problems,
						`lensOf({p}) = {Deep.show(lens)} but lens[{p}] = {Deep.show(stored)} - lensOf `
							.. `reads the stored field`
					)
				end

				local reportedDependent = ring.dependentOf(assignment, p)
				if reportedDependent ~= dependent then
					table.insert(
						problems,
						`dependentOf({p}) = {Deep.show(reportedDependent)}, but σ({p}) = `
							.. `{Deep.show(dependent)} - dependentOf is σ, the ring-successor`
					)
				end

				local reportedSupplier = ring.supplierOf(assignment, p)
				if reportedSupplier ~= supplier then
					table.insert(
						problems,
						`supplierOf({p}) = {Deep.show(reportedSupplier)}, but σ⁻¹({p}) = `
							.. `{Deep.show(supplier)} - supplierOf is σ⁻¹, the ring-predecessor`
					)
				end

				if dependent ~= nil and ring.supplierOf(assignment, dependent) ~= p then
					table.insert(
						problems,
						`supplierOf(dependentOf({p})) = `
							.. `{Deep.show(ring.supplierOf(assignment, dependent))}, not {p}`
					)
				end
			end

			if #problems > 0 then
				table.insert(
					violations,
					`  n = {n}, seed {seed} (σ = {RingContract.ringKey(assignment)}):\n    `
						.. table.concat(problems, "\n    ")
				)
			end
		end
	end

	assert(
		#violations == 0,
		`AC-4: λ(p) = k(σ(p)) does not hold, or supplierOf/dependentOf do not read σ⁻¹/σ, `
			.. `in {#violations} case(s):\n{firstFew(violations, 4)}`
	)
end

--[[
	AC-5. The numbers are the Contract's, verbatim, and are exported so the
	story's handoff and the controls quote the same constants the check uses.

	  SAMPLE      10,000 seeds at n = 4
	  LOW_SHARE   0.08   - fewer than 8% of the sample on any one ring fails
	  HIGH_SHARE  0.25   - more than 25% on any one ring fails

	Uniform over six rings is 16.7%. The band is roughly ±50% of uniform: wide
	enough that sampling noise at 10,000 cannot fire it (the standard deviation
	of a 1/6 share over 10,000 draws is 0.37 percentage points, so 8% is more
	than 23σ below uniform), tight enough that a generator biased toward one ring
	will. It is not tuned here, and "the real module fails it" is a finding to
	report, not a reason to move it.
]]
RingContract.SAMPLE = 10000
RingContract.LOW_SHARE = 0.08
RingContract.HIGH_SHARE = 0.25

-- The six cyclic derangements of the four seated players, as ring keys. Built
-- rather than written down: every ordering (a, b, c) of the three players who
-- are not first gives the cycle first → a → b → c → first, and there are 3! of
-- them.
function RingContract.cyclicRingsOfFour(): { string }
	local players = RingContract.seated(4)
	local first = players[1]
	local rest = { players[2], players[3], players[4] }
	local keys: { string } = {}

	for _, a in rest do
		for _, b in rest do
			for _, c in rest do
				if a ~= b and b ~= c and a ~= c then
					local sigma = { [first] = a, [a] = b, [b] = c, [c] = first }
					table.insert(keys, RingContract.ringKey({ players = players, sigma = sigma }))
				end
			end
		end
	end

	table.sort(keys)
	return keys
end

-- The tally itself, separate from the assertion so that the handoff can report
-- the measured shares of a control without going through a failure message.
function RingContract.tallyRingsOfFour(ring: Ring): { [string]: number }
	local players = RingContract.seated(4)
	local tally: { [string]: number } = {}
	for seed = 1, RingContract.SAMPLE do
		local key = RingContract.ringKey(ring.assign(players, RingContract.rngFor(seed)))
		tally[key] = (tally[key] or 0) + 1
	end
	return tally
end

local function percent(count: number): string
	return string.format("%.1f%%", 100 * count / RingContract.SAMPLE)
end

function RingContract.ringsOfFourAreUniformlyDistributed(ring: Ring)
	local tally = RingContract.tallyRingsOfFour(ring)
	local cyclic = RingContract.cyclicRingsOfFour()

	local lines: { string } = {}
	local absent = 0
	local outOfBand = 0
	local cyclicTotal = 0

	for _, key in cyclic do
		local count = tally[key] or 0
		cyclicTotal += count
		local share = count / RingContract.SAMPLE
		local verdict = ""
		if count == 0 then
			absent += 1
			verdict = "  <- ABSENT"
		elseif share < RingContract.LOW_SHARE then
			outOfBand += 1
			verdict = `  <- below {percent(RingContract.LOW_SHARE * RingContract.SAMPLE)}`
		elseif share > RingContract.HIGH_SHARE then
			outOfBand += 1
			verdict = `  <- above {percent(RingContract.HIGH_SHARE * RingContract.SAMPLE)}`
		end
		table.insert(lines, `  {key} = {count} ({percent(count)}){verdict}`)
	end

	local other = RingContract.SAMPLE - cyclicTotal
	if other > 0 then
		table.insert(lines, `  not a single cycle at all: {other} ({percent(other)})`)
	end

	assert(
		absent == 0 and outOfBand == 0,
		`AC-5: over {RingContract.SAMPLE} seeds at n = 4, {absent} of the 6 cyclic derangements `
			.. `never appeared and {outOfBand} fell outside the `
			.. `{percent(RingContract.LOW_SHARE * RingContract.SAMPLE)}-`
			.. `{percent(RingContract.HIGH_SHARE * RingContract.SAMPLE)} band (uniform is 16.7%). `
			.. `roles.md §2: the ring's shape is itself variance:\n`
			.. table.concat(lines, "\n")
	)
end

--[[
	AC-6. Fewer than 3 seated fails, and the observable behaviour pinned here
	is: `assign` RAISES. Chosen over returning nil or a sentinel because the
	Contract's signature returns an `Assignment` and nothing else, because
	`Rng.nextInteger` in the same codebase raises on an empty range for the same
	reason ("returning nil would move the failure somewhere else"), and because
	a degenerate ring is the failure mode - a swap at n = 2, a fixed point at
	n = 1 - and every one of those is a table that LOOKS like an Assignment.

	The message text is not constrained. Exactly 3 is the boundary and must
	succeed: a 3-cycle is still a ring (tuning.md §1).
]]
function RingContract.fewerThanThreeSeatedRaises(ring: Ring)
	local violations: { string } = {}

	for _, n in { 0, 1, 2 } do
		local ok, result = pcall(ring.assign, RingContract.seated(n), RingContract.rngFor(7))
		if ok then
			table.insert(
				violations,
				`  n = {n}: assign returned {Deep.show(result)} instead of raising`
			)
		end
	end

	local ok, result = pcall(ring.assign, RingContract.seated(3), RingContract.rngFor(7))
	if not ok then
		table.insert(
			violations,
			`  n = 3: assign raised "{tostring(result)}", but three is a ring `
				.. `(min_players_to_continue, tuning.md §1)`
		)
	end

	check(
		#violations == 0,
		`AC-6: fewer than 3 seated must raise rather than return a degenerate ring, and `
			.. `exactly 3 must not:\n{firstFew(violations, 4)}`
	)
end

--[[
	AC-7. A deep snapshot of the input before the call, deep-compared against the
	input after it - never an identity check - and the result's seat order
	compared against the SNAPSHOT rather than the live list, so an implementation
	that shuffles its input in place and hands the same table back fails both
	halves rather than passing the second by aliasing.
]]
function RingContract.inputIsNotMutatedAndSeatOrderIsKept(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		local snapshot = Deep.copy(players)

		local assignment = ring.assign(players, RingContract.rngFor(31337))

		local mutated = Deep.diff(snapshot, players)
		if mutated ~= "" then
			table.insert(violations, `  n = {n}: the input list was mutated:\n{mutated}`)
		end
		local reordered = Deep.diff(snapshot, assignment.players)
		if reordered ~= "" then
			table.insert(
				violations,
				`  n = {n}: assignment.players is {Deep.show(assignment.players)}, wanted the `
					.. `input order {Deep.show(snapshot)}:\n{reordered}`
			)
		end
	end

	assert(
		#violations == 0,
		`AC-7: the input list must come back untouched and the result must keep its seat `
			.. `order, violated at {#violations} value(s) of n:\n{firstFew(violations, 8)}`
	)
end

--[[
	Contract pin: `assign` draws from `rng:derive("seats")`, its own sub-stream.

	Observable from outside as: draws taken from the PARENT rng before the call
	do not change the ring. ROUND-001's `derive` mixes a fresh identity from the
	parent's seed and label and touches no state the parent can see, so an
	implementation that derives is immune to how much the caller has already
	drawn, and one that shuffles with the parent directly is not. This is what
	lets the M3 instance generator draw from `derive("instance")` later without
	shifting a single seat. The LABEL is not pinned.
]]
function RingContract.assignDrawsFromItsOwnSubStream(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		local fresh = ring.assign(players, RingContract.rngFor(2024))

		local consumed = RingContract.rngFor(2024)
		for _ = 1, 5 do
			consumed:nextNumber()
		end
		local afterDraws = ring.assign(players, consumed)

		local difference = Deep.diff(fresh, afterDraws)
		if difference ~= "" then
			table.insert(
				violations,
				`  n = {n}: five draws from the parent rng changed the assignment:\n{difference}`
			)
		end
	end

	assert(
		#violations == 0,
		`Contract: assign must draw from its own derived sub-stream, so that draws taken from `
			.. `the parent rng beforehand do not move the seats, violated at {#violations} `
			.. `value(s) of n:\n{firstFew(violations, 4)}`
	)
end

--[[ ======================================================================
	SEAT-003: a disconnect transfers the key class to the supplier and closes
	the ring; a rejoin inside the grace window restores the seat.

	THE ORACLE PARTITION. AC-1, AC-3, AC-4, AC-5 and AC-6 are SETTLED by
	`roles.md` §6 and `mechanics.md` §8: the leaver's key class goes to the
	SUPPLIER σ⁻¹(q) - the ring-predecessor, the one player who could already
	see those required values - the leaver's lens is LOST, the supplier can now
	act on one of their own lens's pairings (the round gets easier, on purpose),
	and a rejoin inside `disconnect_grace_seconds` restores the seat while one
	at or after it does not. Nothing here improves that repair. AC-2 and AC-7
	are mechanical, and AC-7's control - suppliers computed against the ring as
	DEALT rather than as it stands - is the one a single-withdrawal suite cannot
	see. AC-8 pins a boundary of responsibility: a ring module produces a
	well-formed 2-ring and does not decide the round's fate.

	THE GRACE WINDOW IS READ FROM `Tuning.round.disconnect_grace_seconds` (PO-2)
	and never written here. It is a placeholder in `tuning.md` §5; the tests
	must move with it.

	The final assertion of every SEAT-003 check goes through `check` (above)
	rather than `assert`, for the truncation reason given there.
====================================================================== ]]

local Tuning = require("../../src/shared/Tuning")

RingContract.GRACE_SECONDS = Tuning.round.disconnect_grace_seconds

-- The strangers the raise pin asks about: a name never seated, a seated name
-- in the wrong case, and nil. Each is a record so that the nil survives a list.
local STRANGERS: { { id: any } } = { { id = "sam" }, { id = "KIM" }, { id = nil } }

-- Three departure times, so that the boundary arithmetic is not a property of
-- t = 0: zero, a fraction, and a large clock reading.
local LEFT_AT = { 0, 12.5, 1000000 }

local function listOf(value: any): { number }
	return if typeof(value) == "table" then value else {}
end

local function contains(list: { any }, wanted: any): boolean
	for _, item in list do
		if item == wanted then
			return true
		end
	end
	return false
end

-- σ⁻¹ read off an assignment's own σ by a scan over its seated players -
-- the ORACLE, deliberately not `ring.supplierOf`.
local function inverseOf(assignment: Assignment): { [string]: string }
	local inverse: { [string]: string } = {}
	for _, p in assignment.players do
		local q = assignment.sigma[p]
		if typeof(q) == "string" then
			inverse[q] = p
		end
	end
	return inverse
end

-- Every seated player holding `class`, in seat order, plus every UNSEATED key
-- of `keyClasses` holding it - a stray entry is a holder nobody can see.
local function holdersOf(assignment: Assignment, class: number): ({ string }, { string })
	local seated: { string } = {}
	local stray: { string } = {}
	local classes = if typeof(assignment.keyClasses) == "table" then assignment.keyClasses else {}
	for _, p in assignment.players do
		if contains(listOf(classes[p]), class) then
			table.insert(seated, p)
		end
	end
	for key, held in pairs(classes) do
		if not isSeated(assignment.players, key) and contains(listOf(held), class) then
			table.insert(stray, tostring(key))
		end
	end
	return seated, stray
end

local function without(list: { string }, removed: string): { string }
	local out: { string } = {}
	for _, item in list do
		if item ~= removed then
			table.insert(out, item)
		end
	end
	return out
end

--[[
	The two SEAT-003 exports, fetched by name so that a ring missing one fails
	with a message naming it rather than "attempt to call a nil value" three
	frames down. In RED that IS the failure, and it should read like one.
]]
local function exportOf(ring: Ring, name: string): any
	local export = ring[name]
	check(
		typeof(export) == "function",
		`Ring.{name} is {typeof(export)} - SEAT-003 exports withdraw(assignment, playerId) and `
			.. `rejoin(assignment, absence, now) as plain field functions`
	)
	return export
end

-- One withdrawal case: a ring dealt fresh for the leaver, and the result.
type Withdrawal = { n: number, seed: number, leaver: string, before: Assignment, after: Assignment }

--[[
	Every (n, seed, leaver) case over the given counts: a FRESH ring per leaver,
	so that a withdraw that mutates its argument corrupts only its own case and
	the non-mutation pin reports it rather than every later case.
]]
local function withdrawals(ring: Ring, counts: { number }): { Withdrawal }
	local cases: { Withdrawal } = {}
	for _, n in counts do
		local players = RingContract.seated(n)
		for _, seed in KEY_SEEDS do
			for _, leaver in players do
				local before = ring.assign(players, RingContract.rngFor(seed))
				local after = exportOf(ring, "withdraw")(before, leaver)
				table.insert(
					cases,
					{ n = n, seed = seed, leaver = leaver, before = before, after = after }
				)
			end
		end
	end
	return cases
end

local function label(case: Withdrawal): string
	return `n = {case.n}, seed {case.seed}, {case.leaver} leaves (σ = {RingContract.ringKey(
		case.before
	)})`
end

local function absenceFor(case: Withdrawal, leftAt: number): any
	return {
		playerId = case.leaver,
		leftAt = leftAt,
		graceSeconds = RingContract.GRACE_SECONDS,
		snapshot = case.before,
	}
end

--[[
	AC-1. The leaver's key class is held by σ⁻¹(q) - the SUPPLIER - and by
	nobody else. THE DIRECTION IS THE WHOLE CRITERION: the supplier is the one
	player who could already see the values those actuators need. Transfer to
	the dependent σ(q) and every structural property still holds while the
	instance becomes unsolvable, so when the holder is the dependent the
	message says so by name.
]]
function RingContract.withdrawTransfersTheKeyClassToTheSupplier(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })

	for _, case in cases do
		local inverse = inverseOf(case.before)
		local supplier = inverse[case.leaver]
		local dependent = case.before.sigma[case.leaver]
		local problems: { string } = {}

		for _, class in listOf(case.before.keyClasses[case.leaver]) do
			local seated, stray = holdersOf(case.after, class)
			local holders = table.clone(seated)
			for _, key in stray do
				table.insert(holders, `{key} (not seated)`)
			end
			if not (#seated == 1 and seated[1] == supplier and #stray == 0) then
				local held = if #holders == 0 then "nobody" else table.concat(holders, ", ")
				local why = ""
				if contains(seated, dependent) then
					why = ` - {dependent} is σ({case.leaver}), the DEPENDENT; the supplier `
						.. `σ⁻¹({case.leaver}) = {supplier} is the player who could already see `
						.. `those required values (roles.md §6)`
				end
				table.insert(
					problems,
					`k({case.leaver}) = {class} is held by {held}, wanted the supplier {supplier} `
						.. `alone{why}`
				)
			end
		end
		if
			typeof(case.after.keyClasses) == "table"
			and case.after.keyClasses[case.leaver] ~= nil
		then
			table.insert(
				problems,
				`{case.leaver} still has a key-class entry after leaving: `
					.. Deep.show(case.after.keyClasses[case.leaver])
			)
		end

		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	check(
		#violations == 0,
		`AC-1: the leaver's key class did not go to the supplier σ⁻¹(q) and nobody else, in `
			.. `{#violations} of {#cases} (seed, leaver) cases at n = 4:\n{firstFew(violations, 6)}`
	)
end

--[[
	THE NAIVE TEST, for AC-1's control: "somebody holds the class". Every class
	1..n appears in SOME list after the withdrawal. This is the test a
	transfer-to-the-dependent implementation passes, and it is here so that
	`ring_controls_test.luau` can show that control PASSING it and FAILING AC-1
	in the same breath. A control that fails both proves nothing about AC-1.
]]
function RingContract.naiveEveryClassIsHeldBySomebody(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })

	for _, case in cases do
		local missing: { number } = {}
		for class = 1, case.n do
			local seated, stray = holdersOf(case.after, class)
			if #seated + #stray == 0 then
				table.insert(missing, class)
			end
		end
		if #missing > 0 then
			table.insert(violations, `  {label(case)}: nobody holds {Deep.show(missing)}`)
		end
	end

	check(
		#violations == 0,
		`naive: a key class is held by nobody after the withdrawal in {#violations} of {#cases} `
			.. `cases:\n{firstFew(violations, 6)}`
	)
end

--[[
	AC-2. After the withdrawal σ is a single cycle over exactly the remaining
	n − 1 players with no fixed point, and the relative order of the remaining
	players is unchanged - in `players` (the seat order minus q) and in σ (the
	orbit walked from any remaining player is the original orbit minus q).
]]
function RingContract.withdrawnRingIsOneCycleInTheOriginalOrder(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4, 5, 6 })

	for _, case in cases do
		local remaining = without(case.before.players, case.leaver)
		local problems: { string } = {}

		local seats = Deep.diff(remaining, case.after.players)
		if seats ~= "" then
			table.insert(
				problems,
				`players is {Deep.show(case.after.players)}, wanted the seat order minus the `
					.. `leaver {Deep.show(remaining)}`
			)
		end

		local sigma = if typeof(case.after.sigma) == "table" then case.after.sigma else {}
		local seen: { [string]: boolean } = {}
		for _, p in remaining do
			local q = sigma[p]
			if q == nil then
				table.insert(problems, `σ({p}) is nil`)
			elseif not isSeated(remaining, q) then
				table.insert(
					problems,
					`σ({p}) = {tostring(q)}, who is not seated after the withdrawal`
				)
			elseif q == p then
				table.insert(problems, `σ({p}) = {p}, a fixed point`)
			elseif seen[q] then
				table.insert(problems, `σ maps two players to {q}`)
			else
				seen[q] = true
			end
		end
		for key in pairs(sigma) do
			if not isSeated(remaining, key) then
				table.insert(problems, `σ has an entry for {tostring(key)}, who is not seated`)
			end
		end

		local expectedOrbit =
			without(orbit(case.before.sigma, remaining[1], case.n + 1), case.leaver)
		local actualOrbit = orbit(sigma, remaining[1], case.n)
		if not Deep.equal(expectedOrbit, actualOrbit) then
			table.insert(
				problems,
				`the orbit of {remaining[1]} is {render(actualOrbit)}, wanted the original orbit `
					.. `minus the leaver {render(expectedOrbit)}`
			)
		end

		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	check(
		#violations == 0,
		`AC-2: the withdrawn ring is not a single (n − 1)-cycle in the original order in `
			.. `{#violations} of {#cases} (n, seed, leaver) cases:\n{firstFew(violations, 6)}`
	)
end

--[[
	AC-3. The supplier holds TWO key classes, and exactly one player in the ring
	can now act on a class their own lens covers - that supplier.

	THIS IS A DELIBERATELY DEGRADED INVARIANT. SEAT-001's derangement property
	("nobody can act on what they can see") is broken for exactly one player
	after a withdrawal, on purpose: `roles.md` §6 says the supplier "can act on
	one of their own lens's pairings, so the round gets easier and
	k-essentiality is degraded. That is correct: the group has been harmed
	enough." A ring that "fixes" this - by handing the class elsewhere, or by
	moving the supplier's lens off it - has changed the design, and this check
	is what refuses it.
]]
function RingContract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })

	for _, case in cases do
		local supplier = inverseOf(case.before)[case.leaver]
		local classes = if typeof(case.after.keyClasses) == "table"
			then case.after.keyClasses
			else {}
		local lens = if typeof(case.after.lens) == "table" then case.after.lens else {}
		local problems: { string } = {}

		if supplier == nil then
			table.insert(
				violations,
				`  {label(case)}: σ⁻¹({case.leaver}) cannot be found in the ring as passed - was `
					.. `the argument mutated by the withdrawal?`
			)
			continue
		end

		local held = listOf(classes[supplier])
		if #held ~= 2 then
			table.insert(
				problems,
				`the supplier {supplier} holds {#held} class(es) {Deep.show(held)}, wanted two`
			)
		end

		local actors: { string } = {}
		for _, p in case.after.players do
			if contains(listOf(classes[p]), lens[p]) then
				table.insert(
					actors,
					`{p} (lens {tostring(lens[p])} in {Deep.show(listOf(classes[p]))})`
				)
			end
		end
		if not (#actors == 1 and string.sub(actors[1], 1, #supplier + 1) == supplier .. " ") then
			table.insert(
				problems,
				`{#actors} player(s) can act on a class their own lens covers [{table.concat(
					actors,
					", "
				)}], wanted exactly one - the supplier {supplier}, whose lens still reads `
					.. `k({case.leaver}) and who now holds it. This degradation is DELIBERATE `
					.. `(roles.md §6)`
			)
		end

		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	check(
		#violations == 0,
		`AC-3: the supplier does not hold two classes, or the number of players who can act on `
			.. `their own lens is not exactly one, in {#violations} of {#cases} cases at n = 4:\n`
			.. firstFew(violations, 6)
	)
end

--[[
	AC-4. The leaver's lens is LOST: no remaining player has acquired it, the
	leaver has no lens entry, every other lens is untouched, and `lensOf` reads
	the stored lens rather than recomputing k(σ(p)) - which, after `σ(s) = d`,
	would hand the supplier exactly the lens that was lost (PO-1).
]]
function RingContract.leaversLensIsLost(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4, 5 })

	for _, case in cases do
		local lost = case.before.lens[case.leaver]
		local lens = if typeof(case.after.lens) == "table" then case.after.lens else {}
		local problems: { string } = {}

		if lens[case.leaver] ~= nil then
			table.insert(
				problems,
				`{case.leaver} still has a lens entry: {tostring(lens[case.leaver])}`
			)
		end
		for _, p in case.after.players do
			if lens[p] == lost then
				table.insert(
					problems,
					`λ({p}) = {tostring(lost)}, the LEAVER's lens - it is lost, not handed on `
						.. `(roles.md §6)`
				)
			elseif lens[p] ~= case.before.lens[p] then
				table.insert(
					problems,
					`λ({p}) changed from {tostring(case.before.lens[p])} to {tostring(lens[p])}`
				)
			end
			local read = ring.lensOf(case.after, p)
			if read ~= case.before.lens[p] then
				table.insert(
					problems,
					`lensOf({p}) = {tostring(read)}, but λ({p}) = {tostring(case.before.lens[p])} - `
						.. `lensOf must read the stored lens, not recompute k(σ(p)) (PO-1)`
				)
			end
		end
		for key in pairs(lens) do
			if not isSeated(case.after.players, key) then
				table.insert(problems, `a lens entry for {tostring(key)}, who is not seated`)
			end
		end

		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	check(
		#violations == 0,
		`AC-4: the leaver's lens was not lost, or another lens moved, in {#violations} of `
			.. `{#cases} (n, seed, leaver) cases:\n{firstFew(violations, 6)}`
	)
end

--[[
	AC-5. A rejoin at t + grace − 0.1 restores the original seat, key classes and
	lens: the result deep-equals the pre-withdrawal assignment. And at t itself,
	an instant later, the same.
]]
function RingContract.rejoinInsideTheGraceWindowRestoresTheSeat(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })
	local grace = RingContract.GRACE_SECONDS
	local total = 0

	for _, case in cases do
		for _, leftAt in LEFT_AT do
			for _, offset in { grace - 0.1, 0 } do
				total += 1
				local now = leftAt + offset
				local restored = exportOf(ring, "rejoin")(case.after, absenceFor(case, leftAt), now)
				if restored == nil then
					table.insert(
						violations,
						`  {label(case)}, left at {leftAt}, rejoins at {now} (grace {grace}): `
							.. `rejoin returned nil; {case.leaver} is inside the window and must get `
							.. `their seat back`
					)
				else
					local diff = Deep.diff(case.before, restored)
					if diff ~= "" then
						table.insert(
							violations,
							`  {label(case)}, left at {leftAt}, rejoins at {now}: the restored ring is `
								.. `not the pre-withdrawal one:\n    {(string.gsub(
									diff,
									"\n",
									"\n    "
								))}`
						)
					end
				end
			end
		end
	end

	check(
		#violations == 0,
		`AC-5: a rejoin inside disconnect_grace_seconds ({grace}) did not restore the `
			.. `pre-withdrawal ring in {#violations} of {total} cases:\n{firstFew(violations, 4)}`
	)
end

--[[
	AC-6. A rejoin at EXACTLY t + grace is too late: nil, the ring the caller
	holds stays at n − 1, the rejoiner is not seated. `now - leftAt >=
	graceSeconds` → too late, inclusive, the phase machine's boundary
	convention. Later than that is too late as well.
]]
function RingContract.rejoinAtOrAfterTheGraceBoundaryIsRefused(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })
	local grace = RingContract.GRACE_SECONDS
	local total = 0

	for _, case in cases do
		for _, leftAt in LEFT_AT do
			for _, entry in
				{
					{ offset = grace, name = "exactly t + disconnect_grace_seconds" },
					{ offset = grace + 1, name = "t + grace + 1" },
					{ offset = grace * 10, name = "t + 10 × grace" },
				}
			do
				total += 1
				local now = leftAt + entry.offset
				local held = Deep.copy(case.after)
				local result = exportOf(ring, "rejoin")(case.after, absenceFor(case, leftAt), now)
				local problems: { string } = {}
				if result ~= nil then
					table.insert(
						problems,
						`rejoin at {entry.name} ({now}, left at {leftAt}) returned an assignment with `
							.. `{#result.players} seated instead of nil - the comparison is `
							.. `now - leftAt >= graceSeconds, too late INCLUSIVE`
					)
				end
				if isSeated(case.after.players, case.leaver) then
					table.insert(problems, `{case.leaver} is seated in the ring the caller holds`)
				end
				if #case.after.players ~= case.n - 1 then
					table.insert(
						problems,
						`the ring the caller holds has {#case.after.players} seated, not {case.n - 1}`
					)
				end
				local diff = Deep.diff(held, case.after)
				if diff ~= "" then
					table.insert(
						problems,
						`the refused rejoin changed the assignment it was passed:\n    {diff}`
					)
				end
				if #problems > 0 then
					table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
				end
			end
		end
	end

	check(
		#violations == 0,
		`AC-6: a rejoin at or after t + disconnect_grace_seconds ({grace}) was not refused, or `
			.. `the seat came back, in {#violations} of {total} cases:\n{firstFew(violations, 4)}`
	)
end

--[[
	AC-7. Two players leave a 5-ring in succession. The result is a single
	3-cycle in the original order, every class 1..5 is held by exactly one
	seated player, and each transfer went to the supplier IN THE RING AS IT
	STOOD at that withdrawal.

	THE SECOND LEAVER IS CHOSEN SO THAT THE CONTROL IS NOT VACUOUS: when q2 is
	q1's DEPENDENT, q2's original supplier is q1 - who has left - and q2's
	current supplier is q1's old supplier s1. An implementation reading σ⁻¹ off
	the ring as dealt sends q2's class to a player who is not seated. When q2 is
	q1's SUPPLIER, the two rings agree on q2's supplier and the same
	implementation is correct; both orders are exercised, and the failure count
	in the message says how many cases discriminate.
]]
function RingContract.twoWithdrawalsEachTransferToTheSupplierAtTheTime(ring: Ring)
	local violations: { string } = {}
	local total = 0
	local players = RingContract.seated(5)

	for _, seed in KEY_SEEDS do
		for _, first in players do
			local original = ring.assign(players, RingContract.rngFor(seed))
			local inverse = inverseOf(original)
			for _, second in { original.sigma[first], inverse[first] } do
				total += 1
				local before = ring.assign(players, RingContract.rngFor(seed))
				local dealt = Deep.copy(before)
				local s1 = inverseOf(dealt)[first]
				local once = exportOf(ring, "withdraw")(before, first)
				local s2 = inverseOf(once)[second]
				if s2 == nil then
					table.insert(
						violations,
						`  seed {seed}: {first} leaves, then {second}: σ⁻¹({second}) cannot be found `
							.. `after the first withdrawal (players = {Deep.show(once.players)})`
					)
					continue
				end
				-- The oracle is captured BEFORE the call it judges: the ring as
				-- dealt, and what the second leaver holds going into their
				-- withdrawal. A withdraw that mutates in place would otherwise
				-- rewrite both before they are read.
				before = dealt
				local heldBySecond = Deep.copy(listOf(once.keyClasses[second]))
				local twice = exportOf(ring, "withdraw")(once, second)
				local problems: { string } = {}

				-- Expected holders: q1's classes went to s1, and then wherever
				-- s1's went if s1 was the second to leave; q2's went to s2.
				local expected: { [number]: string } = {}
				for _, p in players do
					for _, class in listOf(before.keyClasses[p]) do
						expected[class] = p
					end
				end
				for _, class in listOf(before.keyClasses[first]) do
					expected[class] = s1
				end
				for _, class in heldBySecond do
					expected[class] = s2
				end

				for class = 1, 5 do
					local seated, stray = holdersOf(twice, class)
					if not (#seated == 1 and seated[1] == expected[class] and #stray == 0) then
						local holders = table.clone(seated)
						for _, key in stray do
							table.insert(holders, `{key} (not seated)`)
						end
						table.insert(
							problems,
							`class {class} is held by {if #holders == 0
								then "nobody"
								else table.concat(holders, ", ")}, wanted {expected[class]} alone`
						)
					end
				end

				local remaining = without(without(before.players, first), second)
				if not Deep.equal(remaining, twice.players) then
					table.insert(
						problems,
						`players is {Deep.show(twice.players)}, wanted {Deep.show(remaining)}`
					)
				end
				local expectedOrbit =
					without(without(orbit(before.sigma, remaining[1], 6), first), second)
				local actualOrbit = orbit(
					if typeof(twice.sigma) == "table" then twice.sigma else {},
					remaining[1],
					5
				)
				if #actualOrbit ~= 3 or not Deep.equal(expectedOrbit, actualOrbit) then
					table.insert(
						problems,
						`the orbit of {remaining[1]} is {render(actualOrbit)}, wanted the 3-cycle `
							.. render(expectedOrbit)
					)
				end

				if #problems > 0 then
					local relation = if second == original.sigma[first]
						then "dependent"
						else "supplier"
					table.insert(
						violations,
						`  seed {seed} (σ = {RingContract.ringKey(before)}): {first} leaves, then their `
							.. `{relation} {second} leaves: {table.concat(problems, "; ")}`
					)
				end
			end
		end
	end

	check(
		#violations == 0,
		`AC-7: after two withdrawals from a 5-ring the classes are not each held by the supplier `
			.. `at the time, or the ring is not a 3-cycle, in {#violations} of {total} cases:\n`
			.. firstFew(violations, 6)
	)
end

--[[
	AC-8. A withdrawal from a 3-ring does not raise, produces a well-formed
	2-player result - a single 2-cycle, no fixed point, all three classes held
	by the two remaining, their lenses intact - and DECIDES NOTHING: the result
	is an Assignment with exactly the Contract's four fields. Ending the round
	is ROUND-005's, on the phase machine's quorum rule; a ring module that also
	ended rounds would be a second place to disagree about when a round ended.
]]
RingContract.ASSIGNMENT_FIELDS = { "players", "sigma", "keyClasses", "lens" }

local function extraFields(assignment: any): { string }
	local extra: { string } = {}
	for key in pairs(assignment) do
		if not contains(RingContract.ASSIGNMENT_FIELDS, key) then
			table.insert(extra, tostring(key))
		end
	end
	table.sort(extra)
	return extra
end

function RingContract.withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing(ring: Ring)
	local violations: { string } = {}
	local players = RingContract.seated(3)
	local total = 0

	for _, seed in KEY_SEEDS do
		for _, leaver in players do
			total += 1
			local before = ring.assign(players, RingContract.rngFor(seed))
			local ok, result = pcall(exportOf(ring, "withdraw"), before, leaver)
			if not ok then
				table.insert(
					violations,
					`  seed {seed}, {leaver} leaves: withdraw raised "{tostring(result)}" - the ring `
						.. `module does not decide the round's fate (ROUND-005 owns quorum)`
				)
				continue
			end
			local problems: { string } = {}
			if typeof(result) ~= "table" then
				table.insert(problems, `withdraw returned {typeof(result)}`)
			else
				local extra = extraFields(result)
				if #extra > 0 then
					table.insert(
						problems,
						`the result carries {table.concat(extra, ", ")} - an Assignment is exactly `
							.. `{table.concat(RingContract.ASSIGNMENT_FIELDS, ", ")}; the round's fate is `
							.. `not this module's to decide`
					)
				end
				local remaining = without(players, leaver)
				local a, b = remaining[1], remaining[2]
				if not Deep.equal(remaining, result.players) then
					table.insert(
						problems,
						`players is {Deep.show(result.players)}, wanted {Deep.show(remaining)}`
					)
				end
				local sigma = if typeof(result.sigma) == "table" then result.sigma else {}
				local wantedSigma = { [a] = b, [b] = a }
				if not Deep.equal(wantedSigma, sigma) then
					table.insert(
						problems,
						`σ is {Deep.show(sigma)}, wanted the 2-cycle {Deep.show(wantedSigma)}`
					)
				end
				local held: { number } = {}
				for _, p in remaining do
					for _, class in listOf((result.keyClasses or {})[p]) do
						table.insert(held, class)
					end
				end
				table.sort(held)
				if not Deep.equal({ 1, 2, 3 }, held) then
					table.insert(
						problems,
						`the two remaining players hold {Deep.show(held)}, wanted all three classes once each`
					)
				end
				local wantedLens = { [a] = before.lens[a], [b] = before.lens[b] }
				if not Deep.equal(wantedLens, result.lens) then
					table.insert(
						problems,
						`lens is {Deep.show(result.lens)}, wanted {Deep.show(wantedLens)}`
					)
				end
			end
			if #problems > 0 then
				table.insert(
					violations,
					`  seed {seed}, {leaver} leaves: {table.concat(problems, "; ")}`
				)
			end
		end
	end

	check(
		#violations == 0,
		`AC-8: a withdrawal from a 3-ring did not produce a well-formed 2-ring and nothing else `
			.. `in {#violations} of {total} cases:\n{firstFew(violations, 6)}`
	)
end

--[[
	Contract pin (PO-3): `withdraw` never mutates its argument, and the result
	is fresh AT EVERY LEVEL - not the argument, and sharing none of its tables.
	The caller keeps the argument as `Absence.snapshot`; a result whose lists
	are the argument's own would let the NEXT withdrawal's append rewrite the
	snapshot in place, which is the same defect one step later.
]]
function RingContract.withdrawDoesNotMutateOrAliasItsArgument(ring: Ring)
	local violations: { string } = {}
	local players = RingContract.seated(4)
	local total = 0

	for _, seed in KEY_SEEDS do
		for _, leaver in players do
			total += 1
			local before = ring.assign(players, RingContract.rngFor(seed))
			local snapshot = Deep.copy(before)
			local after = exportOf(ring, "withdraw")(before, leaver)
			local problems: { string } = {}

			local diff = Deep.diff(snapshot, before)
			if diff ~= "" then
				table.insert(
					problems,
					`the argument was mutated:\n    {(string.gsub(diff, "\n", "\n    "))}`
				)
			end
			if after == before then
				table.insert(problems, "withdraw returned its argument rather than a fresh table")
			elseif typeof(after) == "table" then
				for _, field in RingContract.ASSIGNMENT_FIELDS do
					if after[field] ~= nil and after[field] == before[field] then
						table.insert(problems, `result.{field} IS the argument's own {field} table`)
					end
				end
				if typeof(after.keyClasses) == "table" and typeof(before.keyClasses) == "table" then
					for p, held in pairs(after.keyClasses) do
						if held == before.keyClasses[p] then
							table.insert(
								problems,
								`result.keyClasses[{tostring(p)}] IS the argument's own list (shared, so a `
									.. `later transfer appended in place would rewrite the snapshot)`
							)
						end
					end
				end
			end

			if #problems > 0 then
				table.insert(
					violations,
					`  seed {seed}, {leaver} leaves: {table.concat(problems, "; ")}`
				)
			end
		end
	end

	check(
		#violations == 0,
		`Contract: withdraw must return a fresh table and leave its argument untouched (PO-3), `
			.. `violated in {#violations} of {total} cases:\n{firstFew(violations, 4)}`
	)
end

local function splitLocation(message: string): (string, string)
	local location, rest = string.match(message, "^(.-):%d+: (.*)$")
	if location == nil then
		return "", message
	end
	return location :: string, rest :: string
end

--[[
	Contract pin: withdrawing a player who is not seated RAISES, as
	`Ring.supplierOf` does, at level 2 - attributed to the caller, and naming
	the player. Returning a copy or the argument would move the failure
	somewhere later and harder to read. And the positive half: every seated
	player can be withdrawn.
]]
function RingContract.withdrawOfAnUnseatedPlayerRaises(ring: Ring)
	local violations: { string } = {}
	local assignment = ring.assign(RingContract.seated(4), RingContract.rngFor(KEY_SEEDS[1]))

	for _, entry in STRANGERS do
		local stranger = entry.id
		local shown = if stranger == nil then "nil" else Deep.show(stranger)
		local ok, result = pcall(exportOf(ring, "withdraw"), assignment, stranger)
		if ok then
			table.insert(
				violations,
				`  withdraw(assignment, {shown}) returned {Deep.show(result)} instead of raising`
			)
		else
			local message = tostring(result)
			local location, rest = splitLocation(message)
			local problems: { string } = {}
			if stranger ~= nil and string.find(rest, tostring(stranger), 1, true) == nil then
				table.insert(problems, `does not name the player ({tostring(stranger)})`)
			end
			if string.find(location, "[/\\]Ring$") ~= nil then
				table.insert(
					problems,
					"is attributed to Ring.luau itself rather than to its caller (level 2)"
				)
			end
			if #problems > 0 then
				table.insert(
					violations,
					`  withdraw(assignment, {shown}) raised, but the error {table.concat(
						problems,
						"; "
					)}:\n    {message}`
				)
			end
		end
	end

	for _, p in assignment.players do
		local ok, result = pcall(exportOf(ring, "withdraw"), assignment, p)
		if not ok then
			table.insert(
				violations,
				`  withdraw(assignment, "{p}") raised for a SEATED player: {tostring(result)}`
			)
		end
	end

	check(
		#violations == 0,
		`Contract: withdrawing an unseated player must raise, and a seated one must not, violated `
			.. `in {#violations} case(s):\n{table.concat(violations, "\n")}`
	)
end

--[[
	Contract pin (PO-4): `rejoin` never mutates the assignment or the absence it
	is passed, inside the window or at the boundary, and what it returns is a
	DEEP COPY of the snapshot - not the snapshot itself, sharing none of its
	tables - so that the driver holding the absence cannot be reached through
	the ring it hands out.
]]
function RingContract.rejoinDoesNotMutateOrAliasItsArguments(ring: Ring)
	local violations: { string } = {}
	local cases = withdrawals(ring, { 4 })
	local grace = RingContract.GRACE_SECONDS
	local total = 0

	for _, case in cases do
		for _, offset in { grace - 0.1, grace } do
			total += 1
			local leftAt = LEFT_AT[2]
			local absence = absenceFor(case, leftAt)
			local heldAssignment = Deep.copy(case.after)
			local heldAbsence = Deep.copy(absence)
			local restored = exportOf(ring, "rejoin")(case.after, absence, leftAt + offset)
			local problems: { string } = {}

			local diff = Deep.diff(heldAssignment, case.after)
			if diff ~= "" then
				table.insert(
					problems,
					`the assignment was mutated:\n    {(string.gsub(diff, "\n", "\n    "))}`
				)
			end
			diff = Deep.diff(heldAbsence, absence)
			if diff ~= "" then
				table.insert(
					problems,
					`the absence was mutated:\n    {(string.gsub(diff, "\n", "\n    "))}`
				)
			end
			if restored ~= nil then
				if restored == absence.snapshot then
					table.insert(
						problems,
						"rejoin returned absence.snapshot itself rather than a deep copy"
					)
				elseif restored == case.after then
					table.insert(problems, "rejoin returned the assignment it was passed")
				elseif typeof(restored) == "table" then
					for _, field in RingContract.ASSIGNMENT_FIELDS do
						if
							restored[field] ~= nil
							and restored[field] == absence.snapshot[field]
						then
							table.insert(
								problems,
								`restored.{field} IS the snapshot's own {field} table`
							)
						end
					end
					if typeof(restored.keyClasses) == "table" then
						for p, held in pairs(restored.keyClasses) do
							if held == absence.snapshot.keyClasses[p] then
								table.insert(
									problems,
									`restored.keyClasses[{tostring(p)}] IS the snapshot's own list`
								)
							end
						end
					end
				end
			end

			if #problems > 0 then
				table.insert(
					violations,
					`  {label(case)}, rejoin at t + {offset}: {table.concat(problems, "; ")}`
				)
			end
		end
	end

	check(
		#violations == 0,
		`Contract: rejoin must not mutate its arguments and must return a deep copy of the `
			.. `snapshot (PO-4), violated in {#violations} of {total} cases:\n{firstFew(
				violations,
				4
			)}`
	)
end

--[[
	Contract pin: the supplier's list is their OWN classes first, then ALL of
	the leaver's, in order. Pinned through two withdrawals so that "all" means
	something: after q1 leaves, s1 holds {k(s1), k(q1)}; when s1 then leaves,
	s0 holds {k(s0), k(s1), k(q1)}.
]]
function RingContract.supplierListIsOwnClassesThenTheLeaversInOrder(ring: Ring)
	local violations: { string } = {}
	local players = RingContract.seated(5)
	local total = 0

	for _, seed in KEY_SEEDS do
		for _, first in players do
			total += 1
			local before = ring.assign(players, RingContract.rngFor(seed))
			local dealt = Deep.copy(before)
			local s1 = inverseOf(dealt)[first]
			local once = exportOf(ring, "withdraw")(before, first)
			local s0 = inverseOf(once)[s1]
			if s0 == nil then
				table.insert(
					violations,
					`  seed {seed}, {first} then {s1} leave: σ⁻¹({s1}) cannot be found after the first `
						.. `withdrawal (players = {Deep.show(once.players)})`
				)
				continue
			end
			local twice = exportOf(ring, "withdraw")(once, s1)
			local problems: { string } = {}

			-- Expected lists are read off the ring AS DEALT, snapshotted before the
			-- first withdrawal, so that a mutating withdraw cannot rewrite the oracle.
			before = dealt
			local wantedOnce = { before.keyClasses[s1][1], before.keyClasses[first][1] }
			local gotOnce = listOf((once.keyClasses or {})[s1])
			if not Deep.equal(wantedOnce, gotOnce) then
				table.insert(
					problems,
					`after {first} leaves, keyClasses[{s1}] = {Deep.show(gotOnce)}, wanted own then the `
						.. `leaver's: {Deep.show(wantedOnce)}`
				)
			end
			local wantedTwice = { before.keyClasses[s0][1], wantedOnce[1], wantedOnce[2] }
			local gotTwice = listOf((twice.keyClasses or {})[s0])
			if not Deep.equal(wantedTwice, gotTwice) then
				table.insert(
					problems,
					`after {s1} leaves too, keyClasses[{s0}] = {Deep.show(gotTwice)}, wanted own then all `
						.. `of the leaver's in order: {Deep.show(wantedTwice)}`
				)
			end

			if #problems > 0 then
				table.insert(
					violations,
					`  seed {seed}, {first} then {s1} leave: {table.concat(problems, "; ")}`
				)
			end
		end
	end

	check(
		#violations == 0,
		`Contract: the supplier's list must be their own classes followed by all of the leaver's, `
			.. `in order, violated in {#violations} of {total} cases:\n{firstFew(violations, 4)}`
	)
end

return RingContract
