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

	["Contract: assign returns an Assignment carrying players, sigma, keyClasses and lens, and nothing the Contract does not name"] = function()
		local players = Contract.seated(4)
		local assignment = Ring().assign(players, Contract.rngFor(1))

		assert(typeof(assignment) == "table", `assign returned {typeof(assignment)}`)
		for _, field in Contract.ASSIGNMENT_FIELDS do
			assert(
				typeof(assignment[field]) == "table",
				`assignment.{field} is {typeof(assignment[field])}: {Deep.show(assignment[field])}`
			)
		end
		-- SEAT-003: the singular map is GONE, not kept beside the list.
		assert(
			assignment.keyClass == nil,
			`assignment.keyClass is still present: {Deep.show(assignment.keyClass)} - SEAT-003 `
				.. `replaced it with keyClasses (a list per player) and lens`
		)

		local extra: { string } = {}
		for key in pairs(assignment) do
			if not table.find(Contract.ASSIGNMENT_FIELDS, key) then
				table.insert(extra, tostring(key))
			end
		end
		assert(
			#extra == 0,
			`assignment carries fields the Contract does not name: {table.concat(extra, ", ")}. `
				.. `Lens CONTENTS are M3 and out of scope; SEAT-002 replicates this shape as is`
		)
	end,

	["Contract: Ring exports withdraw and rejoin as plain field functions (SEAT-003)"] = function()
		local ring = Ring()
		local missing: { string } = {}
		for _, name in { "withdraw", "rejoin" } do
			if typeof(ring[name]) ~= "function" then
				table.insert(missing, `Ring.{name} is {typeof(ring[name])}`)
			end
		end
		assert(
			#missing == 0,
			`SEAT-003's two exports are not both functions: {table.concat(missing, ", ")}`
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

	--[[ ==================================================================
	     SEAT-003. Withdraw and rejoin. The checks are in RingContract's second
	     half and each is observed to fire in ring_controls_test.luau against a
	     one-defect stub - which matters here twice over: in RED the real
	     module has neither function, so every test below fails before its
	     assertion runs, and the first three checks are the ones whose wrong
	     answer is structurally invisible.
	================================================================== ]]

	["SEAT-003 AC-1: after q leaves a 4-ring, q's key class is held by the supplier σ⁻¹(q) and by nobody else - never the dependent"] = function()
		Contract.withdrawTransfersTheKeyClassToTheSupplier(Ring())
	end,

	["SEAT-003 AC-2: the withdrawn ring is a single (n − 1)-cycle with no fixed point and the remaining players keep their relative order, in players and in σ"] = function()
		Contract.withdrawnRingIsOneCycleInTheOriginalOrder(Ring())
	end,

	["SEAT-003 AC-3: the supplier holds two key classes and is the only player who can act on a class their own lens covers (deliberately degraded, roles.md §6)"] = function()
		Contract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens(Ring())
	end,

	["SEAT-003 AC-4: the leaver's lens is lost - no remaining player acquires it, every other lens is untouched, and lensOf reads the stored lens"] = function()
		Contract.leaversLensIsLost(Ring())
	end,

	["SEAT-003 AC-5: a rejoin at t + disconnect_grace_seconds − 0.1 restores the pre-withdrawal ring exactly"] = function()
		Contract.rejoinInsideTheGraceWindowRestoresTheSeat(Ring())
	end,

	["SEAT-003 AC-6: a rejoin at exactly t + disconnect_grace_seconds returns nil, the ring stays at n − 1 and the rejoiner is not seated"] = function()
		Contract.rejoinAtOrAfterTheGraceBoundaryIsRefused(Ring())
	end,

	["SEAT-003 AC-7: two withdrawals from a 5-ring leave a single 3-cycle, every class held once, each transfer to the supplier in the ring as it stood at the time"] = function()
		Contract.twoWithdrawalsEachTransferToTheSupplierAtTheTime(Ring())
	end,

	["SEAT-003 AC-8: a withdrawal from a 3-ring does not raise, yields a well-formed 2-ring, and carries exactly the four Assignment fields - the round's fate is not decided here"] = function()
		Contract.withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing(Ring())
	end,

	["SEAT-003 naive: every key class is held by somebody after a withdrawal - the test the dependent-transfer control passes"] = function()
		Contract.naiveEveryClassIsHeldBySomebody(Ring())
	end,

	["SEAT-003 Contract: withdraw returns a fresh table at every level and never mutates its argument (PO-3)"] = function()
		Contract.withdrawDoesNotMutateOrAliasItsArgument(Ring())
	end,

	["SEAT-003 Contract: withdrawing an unseated player raises, naming the player and blaming the caller; a seated one does not"] = function()
		Contract.withdrawOfAnUnseatedPlayerRaises(Ring())
	end,

	["SEAT-003 Contract: rejoin never mutates its arguments and returns a deep copy of the snapshot (PO-4)"] = function()
		Contract.rejoinDoesNotMutateOrAliasItsArguments(Ring())
	end,

	["SEAT-003 Contract: the supplier's list is their own classes first, then all of the leaver's in order, through two withdrawals"] = function()
		Contract.supplierListIsOwnClassesThenTheLeaversInOrder(Ring())
	end,
}
