--!strict
--[[
	ROUND-001 AC-2, AC-3, AC-4 and the `src/shared/Rng.luau` Contract.

	The criteria themselves live in `tests/helpers/RngContract.luau`, applied here
	to `Rng.fromSeed` and applied in `tests/shared/rng_controls_test.luau` to
	implementations that are wrong on purpose. That split is the story's own
	instruction: AC-2 and AC-3 each name an implementation that passes a naive
	test, so the same assertion has to be seen rejecting it.

	Nothing here pins a particular number stream. There are no golden values, no
	named generator and no distribution claim - "reproducibility and independence
	are the requirements; unpredictability is not", per `## Out of scope`. How
	`Rng` produces its numbers is the implementer's choice.

	Loaded through a `pcall` for the reason `clock_test.luau` gives: in RED this
	module does not exist, and one LOAD FAIL covering three criteria is worse
	evidence than three failures naming them.
]]

local RngContract = require("../helpers/RngContract")

local loaded, loadResult = pcall(require, "../../src/shared/Rng")

local function Rng(): any
	assert(loaded, `src/shared/Rng.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local function fromSeed(seed: number): any
	return Rng().fromSeed(seed)
end

return {
	--[[ AC-2 ]]

	["AC-2: two Rngs from the same seed produce identical sequences"] = function()
		RngContract.sameSeedReproduces(fromSeed)
	end,

	["AC-2: two Rngs from different seeds produce different sequences"] = function()
		RngContract.differentSeedsDiverge(fromSeed)
	end,

	--[[ AC-3 ]]

	["AC-3: the same derive label on two same-seeded parents gives the same sub-stream"] = function()
		RngContract.sameLabelSameSubStream(fromSeed)
	end,

	["AC-3: draining one derived sub-stream does not change another"] = function()
		RngContract.deriveIsIndependent(fromSeed)
	end,

	["Contract: derive is deterministic in the label, not only in the parent seed"] = function()
		RngContract.differentLabelsDiffer(fromSeed)
	end,

	["Contract: a derived sub-stream is itself an Rng that can derive again"] = function()
		local child = fromSeed(5):derive("seats")
		assert(
			typeof(child.nextInteger) == "function",
			`child.nextInteger is {typeof(child.nextInteger)}`
		)
		assert(
			typeof(child.nextNumber) == "function",
			`child.nextNumber is {typeof(child.nextNumber)}`
		)
		assert(typeof(child.shuffle) == "function", `child.shuffle is {typeof(child.shuffle)}`)
		assert(typeof(child.derive) == "function", `child.derive is {typeof(child.derive)}`)

		local left = RngContract.sequence(fromSeed(5):derive("seats"):derive("inner"))
		local right = RngContract.sequence(fromSeed(5):derive("seats"):derive("inner"))
		assert(
			RngContract.firstDifference(left, right) == nil,
			"a grandchild sub-stream is not reproducible from the same parent seed and labels"
		)
	end,

	--[[ AC-4 ]]

	["AC-4: shuffle returns a permutation of its input"] = function()
		RngContract.shuffleIsAPermutation(fromSeed)
	end,

	["AC-4: shuffle does not mutate the list it was given"] = function()
		RngContract.shuffleDoesNotMutateItsInput(fromSeed)
	end,

	["AC-4: shuffle handles an empty list and a single-item list"] = function()
		RngContract.shuffleHandlesEmptyAndSingleton(fromSeed)
	end,

	["AC-4: shuffle does not return the input order for every seed"] = function()
		RngContract.shuffleActuallyPermutes(fromSeed)
	end,

	--[[ Contract semantics of the numbers themselves. ]]

	["Contract: nextInteger is inclusive at both ends"] = function()
		local rng = fromSeed(11)
		local low, high = false, false
		for _ = 1, 200 do
			local value = rng:nextInteger(1, 2)
			assert(value == 1 or value == 2, `nextInteger(1, 2) returned {value}`)
			if value == 1 then
				low = true
			else
				high = true
			end
		end
		assert(low, "nextInteger(1, 2) never returned 1 in 200 draws")
		assert(high, "nextInteger(1, 2) never returned 2 in 200 draws; max looks exclusive")
	end,

	["Contract: nextInteger stays inside a wide range and accepts a negative one"] = function()
		local rng = fromSeed(12)
		for _ = 1, 200 do
			local value = rng:nextInteger(-5, 5)
			assert(value >= -5 and value <= 5, `nextInteger(-5, 5) returned {value}`)
			assert(value == math.floor(value), `nextInteger returned the non-integer {value}`)
		end
	end,

	["Contract: nextInteger with min equal to max returns that value"] = function()
		local rng = fromSeed(13)
		assert(rng:nextInteger(7, 7) == 7, "nextInteger(7, 7) did not return 7")
	end,

	["Contract: nextInteger with min greater than max is an error"] = function()
		local rng = fromSeed(14)
		local ok = pcall(function()
			rng:nextInteger(5, 1)
		end)
		assert(
			ok == false,
			"nextInteger(5, 1) was accepted; the Contract calls an empty range an error"
		)
	end,

	["Contract: nextNumber is in [0, 1)"] = function()
		local rng = fromSeed(15)
		for _ = 1, 200 do
			local value = rng:nextNumber()
			assert(typeof(value) == "number", `nextNumber returned {typeof(value)}`)
			assert(value >= 0 and value < 1, `nextNumber returned {value}, outside [0, 1)`)
		end
	end,

	["Contract: fromSeed is exported and returns the whole Rng interface"] = function()
		local module = Rng()
		assert(
			typeof(module.fromSeed) == "function",
			`Rng.fromSeed is {typeof(module.fromSeed)}, wanted a function`
		)

		local rng = module.fromSeed(1)
		for _, name in { "nextInteger", "nextNumber", "shuffle", "derive" } do
			assert(typeof(rng[name]) == "function", `Rng.{name} is {typeof(rng[name])}`)
		end
	end,
}
