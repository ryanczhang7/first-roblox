--!strict
--[[
	ROUND-001's AC-2, AC-3 and AC-4 written once, as checks over a FACTORY rather
	than over a module.

	`tests/shared/rng_test.luau` applies them to `Rng.fromSeed`, which is the
	story. `tests/shared/rng_controls_test.luau` applies them to the deliberately
	wrong implementations in `Fakes.luau`, which is what makes the story's word
	"control" mean something: each check is observed rejecting an implementation
	that a naive version of the same check would accept.

	A factory is `(seed: number) -> Rng`. Every check errors with a message that
	says which half of which criterion broke; nothing here returns a boolean,
	because a control asserts on the ERROR and a boolean loses the reason.
]]

local RngContract = {}

export type Factory = (number) -> any

-- The call sequence AC-2 means by "the same sequence of nextInteger and shuffle
-- calls". Rendered as strings so a difference reads in the failure message.
local function sequence(rng: any): { string }
	local out: { string } = {}
	for i = 1, 5 do
		table.insert(out, `nextInteger#{i}={rng:nextInteger(1, 100)}`)
	end
	table.insert(out, `nextNumber={rng:nextNumber()}`)
	table.insert(out, `shuffle={table.concat(rng:shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 }), ",")}`)
	table.insert(out, `nextInteger#6={rng:nextInteger(-5, 5)}`)
	return out
end

RngContract.sequence = sequence

-- The index of the first difference, or nil when the two agree.
local function firstDifference(a: { string }, b: { string }): number?
	if #a ~= #b then
		return math.min(#a, #b) + 1
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return i
		end
	end
	return nil
end

RngContract.firstDifference = firstDifference

local function render(values: { string }): string
	return table.concat(values, " | ")
end

--[[ AC-2, first half: same seed, same results. ]]
function RngContract.sameSeedReproduces(factory: Factory)
	for _, seed in { 1, 7, 20260915 } do
		local left = sequence(factory(seed))
		local right = sequence(factory(seed))
		local at = firstDifference(left, right)
		assert(
			at == nil,
			`AC-2: two Rngs from seed {seed} diverged at draw {at}\n`
				.. `  a: {render(left)}\n  b: {render(right)}`
		)
	end
end

--[[
	AC-2, second half, and the criterion's whole point: different seeds, different
	results. An Rng that ignores its seed passes the half above and fails here.
]]
function RngContract.differentSeedsDiverge(factory: Factory)
	for _, pair in { { 1, 2 }, { 7, 8 }, { 0, 1 }, { 1234, 5678 } } do
		local left = sequence(factory(pair[1]))
		local right = sequence(factory(pair[2]))
		assert(
			firstDifference(left, right) ~= nil,
			`AC-2: seeds {pair[1]} and {pair[2]} produced the same sequence, so the seed is `
				.. `not being used:\n  {render(left)}`
		)
	end
end

--[[ AC-3, first half: same label on two same-seeded parents, same sub-stream. ]]
function RngContract.sameLabelSameSubStream(factory: Factory)
	for _, label in { "seats", "instance" } do
		local left = sequence(factory(4242):derive(label))
		local right = sequence(factory(4242):derive(label))
		local at = firstDifference(left, right)
		assert(
			at == nil,
			`AC-3: derive("{label}") on two parents seeded 4242 diverged at draw {at}\n`
				.. `  a: {render(left)}\n  b: {render(right)}`
		)
	end
end

--[[
	AC-3, second half: consuming from one sub-stream perturbs no other.

	Both directions. A `derive` that returns the parent fails either way, but an
	implementation that shares state in one direction only - a sub-stream that
	writes back into the parent - is caught only by testing both.
]]
function RngContract.deriveIsIndependent(factory: Factory)
	local function afterDraining(
		drainLabel: string,
		observeLabel: string,
		draws: number
	): { string }
		local parent = factory(31)
		local drained = parent:derive(drainLabel)
		local observed = parent:derive(observeLabel)
		for _ = 1, draws do
			drained:nextInteger(1, 1000)
		end
		return sequence(observed)
	end

	local baselineB = afterDraining("a", "b", 0)
	local drainedB = afterDraining("a", "b", 50)
	local at = firstDifference(baselineB, drainedB)
	assert(
		at == nil,
		`AC-3: 50 draws from derive("a") changed derive("b") at draw {at}\n`
			.. `  untouched: {render(baselineB)}\n  after draining a: {render(drainedB)}`
	)

	local baselineA = afterDraining("b", "a", 0)
	local drainedA = afterDraining("b", "a", 50)
	local back = firstDifference(baselineA, drainedA)
	assert(
		back == nil,
		`AC-3: 50 draws from derive("b") changed derive("a") at draw {back}\n`
			.. `  untouched: {render(baselineA)}\n  after draining b: {render(drainedA)}`
	)
end

--[[
	The Contract's "deterministic in (parent seed, label)", which AC-3's two
	halves do not between them pin: a `derive` that ignores its label gives
	"seats" and "instance" the same numbers, and both halves still pass.
]]
function RngContract.differentLabelsDiffer(factory: Factory)
	local seats = sequence(factory(77):derive("seats"))
	local instance = sequence(factory(77):derive("instance"))
	assert(
		firstDifference(seats, instance) ~= nil,
		`Contract: derive("seats") and derive("instance") from seed 77 are the same stream, `
			.. `so the label is not being used:\n  {render(seats)}`
	)
end

local function countOf(list: { any }): { [any]: number }
	local counts: { [any]: number } = {}
	for _, value in list do
		counts[value] = (counts[value] or 0) + 1
	end
	return counts
end

--[[ AC-4, first half: the result is a permutation - same multiset, same length. ]]
function RngContract.shuffleIsAPermutation(factory: Factory)
	local input = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
	local rng = factory(5) :: any
	local out = rng:shuffle(input)

	assert(#out == #input, `AC-4: shuffle returned {#out} items from {#input}`)

	local wanted = countOf(input)
	local got = countOf(out)
	for value, n in wanted do
		assert(got[value] == n, `AC-4: shuffle produced {got[value] or 0} of "{value}", wanted {n}`)
	end
	for value, n in got do
		assert(wanted[value] == n, `AC-4: shuffle invented {n} of "{tostring(value)}"`)
	end
end

--[[
	AC-4, second half, and the one the story says will not show up until
	SEAT-001: the input list is not mutated. A shuffle that permutes in place
	still returns a permutation.
]]
function RngContract.shuffleDoesNotMutateItsInput(factory: Factory)
	local input = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
	local before = table.concat(input, ",")
	local rng = factory(5) :: any
	local result = rng:shuffle(input)

	assert(
		table.concat(input, ",") == before,
		`AC-4: shuffle mutated its argument: {before} -> {table.concat(input, ",")}`
	)
	assert(
		rawequal(result, input) == false,
		"AC-4: shuffle returned the caller's own table; the Contract says it returns a new list"
	)
end

--[[
	Empty, one, many. A shuffle of nothing is nothing; a shuffle of one is that
	one; neither may error and neither may mutate.
]]
function RngContract.shuffleHandlesEmptyAndSingleton(factory: Factory)
	local rng = factory(9) :: any

	local empty: { string } = {}
	local emptyOut = rng:shuffle(empty)
	assert(#emptyOut == 0, `AC-4: shuffle of an empty list returned {#emptyOut} items`)
	assert(rawequal(emptyOut, empty) == false, "AC-4: shuffle of an empty list returned the input")

	local one = { "only" }
	local oneOut = rng:shuffle(one)
	assert(#oneOut == 1 and oneOut[1] == "only", "AC-4: shuffle of one item changed it")
	assert(#one == 1 and one[1] == "only", "AC-4: shuffle of one item mutated the input")
end

--[[
	Beyond AC-4, and deliberately so: a `shuffle` that copies and returns the copy
	unchanged satisfies every word of AC-4 for ever. Across 20 seeds at least one
	must come back in a different order.

	Not a probabilistic assertion. Once `Rng` is implemented the result is fixed,
	so this either always passes or always fails; there is no flake to chase.
]]
function RngContract.shuffleActuallyPermutes(factory: Factory)
	local input = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
	local before = table.concat(input, ",")
	for seed = 1, 20 do
		local out = table.concat((factory(seed) :: any):shuffle(input), ",")
		if out ~= before then
			return
		end
	end
	error(`AC-4: 20 seeds all returned the input order {before}; this shuffle does not shuffle`)
end

return RngContract
