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

	A `ring` here is anything with four plain field functions, called with a dot
	exactly as the story's Contract writes them:

	    ring.assign(players, rng)          -> Assignment
	    ring.lensOf(assignment, p)         -> KeyClass
	    ring.supplierOf(assignment, p)     -> PlayerId   (σ⁻¹(p), the predecessor)
	    ring.dependentOf(assignment, p)    -> PlayerId   (σ(p),   the successor)

	and an `Assignment` is `{ players, sigma, keyClass }` with `players` in seat
	order, `sigma[p]` = σ(p) and `keyClass[p]` = k(p).

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

--[[ AC-4, the key half: `keyClass` is exactly the integers 1..n, one per seated player. ]]
function RingContract.keyClassesAreOneToNEachOnce(ring: Ring)
	local violations: { string } = {}

	for _, n in RingContract.COUNTS do
		local players = RingContract.seated(n)
		for _, seed in KEY_SEEDS do
			local assignment = ring.assign(players, RingContract.rngFor(seed))
			local problems: { string } = {}
			local held: { number } = {}

			for _, p in players do
				local k = assignment.keyClass[p]
				if typeof(k) ~= "number" or k ~= math.floor(k) then
					table.insert(problems, `k({p}) = {Deep.show(k)}, not an integer`)
				else
					table.insert(held, k)
				end
			end
			for key in pairs(assignment.keyClass) do
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

	    lensOf(p)                  == k(σ(p))
	    dependentOf(p)             == σ(p)
	    supplierOf(dependentOf(p)) == p      and      σ(supplierOf(p)) == p

	The lens message names the supplier's key class as well as the dependent's,
	so that the failure for a backwards implementation reads as "the lens is
	reading the supplier" rather than as a mystery number.
]]
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
				local dependentKey = if dependent ~= nil
					then assignment.keyClass[dependent]
					else nil
				local supplierKey = if supplier ~= nil then assignment.keyClass[supplier] else nil

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

	assert(
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

return RingContract
