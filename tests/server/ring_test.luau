--!strict
--[[
	SEAT-001: seats are dealt as a seeded single-cycle derangement. AC-1 through
	AC-7, applied to the real `src/server/seats/Ring.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test. In RED it does not exist, and a bare top-level `require` would
	make this whole file a single LOAD FAIL - one line of red covering seven
	criteria. Per-criterion failures say which behaviours are missing, which is
	what GREEN needs. It is not a skip: every test below still FAILS, loudly,
	naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/RingContract.luau` and are exercised against
	deliberately wrong generators in `tests/server/ring_controls_test.luau`. That
	file is where each check is OBSERVED to fire - which matters in RED, because
	the pcall above means not one assertion in THIS file executes until GREEN
	writes the module. This file is where the same checks are applied to the
	real one.

	THE ORACLE PARTITION. AC-1, AC-2, AC-4, AC-6 and AC-7 are settled by
	`roles.md` §2 and §6 and `tuning.md` §1; the checks read those properties out.
	AC-3 is mechanical. AC-5 is the one oracle-free criterion and its 10,000-seed
	sample and 8-25% band are the Contract's, verbatim - not chosen here, not to
	be moved in GREEN.

	THE ONE GENERATOR EVERY STRUCTURAL CHECK IS BLIND TO is a constant: always the
	same ring, for every seed. It has no fixed point, one orbit, keys 1..n, a
	correct lens, an untouched input, and it reproduces from its seed perfectly.
	AC-5 is the only thing between this story and that generator, and the
	`Rng` handed in is the only source of variance, so the rng is the real one
	from ROUND-001, seeded fresh per call.
]]

local Contract = require("../helpers/RingContract")
local Deep = require("../helpers/Deep")

local loaded, loadResult = pcall(require, "../../src/server/seats/Ring")

local function Ring(): any
	assert(loaded, `src/server/seats/Ring.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Ring exports assign, lensOf, supplierOf and dependentOf as plain field functions"] = function()
		local ring = Ring()
		local missing: { string } = {}
		for _, name in { "assign", "lensOf", "supplierOf", "dependentOf" } do
			if typeof(ring[name]) ~= "function" then
				table.insert(missing, `Ring.{name} is {typeof(ring[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's four exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract: assign returns an Assignment carrying players, sigma and keyClass, and nothing the Contract does not name"] = function()
		local players = Contract.seated(4)
		local assignment = Ring().assign(players, Contract.rngFor(1))

		assert(typeof(assignment) == "table", `assign returned {typeof(assignment)}`)
		assert(
			typeof(assignment.players) == "table",
			`assignment.players is {typeof(assignment.players)}: {Deep.show(assignment.players)}`
		)
		assert(
			typeof(assignment.sigma) == "table",
			`assignment.sigma is {typeof(assignment.sigma)}: {Deep.show(assignment.sigma)}`
		)
		assert(
			typeof(assignment.keyClass) == "table",
			`assignment.keyClass is {typeof(assignment.keyClass)}: `
				.. Deep.show(assignment.keyClass)
		)

		local extra: { string } = {}
		for key in pairs(assignment) do
			if key ~= "players" and key ~= "sigma" and key ~= "keyClass" then
				table.insert(extra, tostring(key))
			end
		end
		assert(
			#extra == 0,
			`assignment carries fields the Contract does not name: {table.concat(extra, ", ")}. `
				.. `Lens CONTENTS are M3 and out of scope; SEAT-002 replicates this shape as is`
		)
	end,

	["Contract: assign draws from its own sub-stream - draws taken from the parent rng beforehand do not move the seats"] = function()
		Contract.assignDrawsFromItsOwnSubStream(Ring())
	end,

	--[[ AC-1 ]]

	["AC-1: σ is a permutation of exactly the seated players with no fixed point, for every n in 3..6"] = function()
		Contract.sigmaIsAFixedPointFreePermutation(Ring())
	end,

	--[[ AC-2. 64 seeds per n - see RingContract for why 64. ]]

	["AC-2: the orbit of a player under σ visits all n players before returning - one cycle, never two, for every n in 3..6"] = function()
		Contract.sigmaIsASingleCycle(Ring())
	end,

	--[[ AC-3 ]]

	["AC-3: the same seed and the same seated list produce an identical assignment"] = function()
		Contract.sameSeedSameAssignment(Ring())
	end,

	["AC-3: different seeds produce at least two different rings over a sample of seeds"] = function()
		Contract.differentSeedsProduceDifferentRings(Ring())
	end,

	--[[ AC-4. The direction of σ is pinned here and nowhere else. ]]

	["AC-4: each player holds exactly one key class and the key classes are the integers 1..n each used once"] = function()
		Contract.keyClassesAreOneToNEachOnce(Ring())
	end,

	["AC-4: λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹"] = function()
		Contract.lensIsTheDependentsKeyClass(Ring())
	end,

	--[[ AC-5. The statistical one. 10,000 seeds at n = 4; all six cyclic
	     derangements present; each between 8% and 25% of the sample. ]]

	["AC-5: over 10,000 seeds at n = 4 all six cyclic derangements appear and none takes more than 25% or less than 8%"] = function()
		Contract.ringsOfFourAreUniformlyDistributed(Ring())
	end,

	--[[ AC-6. The observable chosen: assign RAISES below 3. See RingContract. ]]

	["AC-6: assign raises for 0, 1 or 2 seated players rather than returning a degenerate ring, and succeeds at exactly 3"] = function()
		Contract.fewerThanThreeSeatedRaises(Ring())
	end,

	--[[ AC-7 ]]

	["AC-7: the input list is not mutated and the result keeps the input's seat order, for every n in 3..6"] = function()
		Contract.inputIsNotMutatedAndSeatOrderIsKept(Ring())
	end,
}
