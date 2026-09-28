--!strict
--[[
	The negative controls for SEAT-001, and the proof that each check in
	`tests/helpers/RingContract.luau` refuses the generator it exists to catch.

	THREE CRITERIA NAME THEIR CONTROL. AC-2: a plain derangement generator
	"passes AC-1 and must fail this at n = 4". AC-3: a seed-ignoring generator
	"passes the first half and must fail the second". AC-5: the constant
	canonical ring "satisfies AC-1, AC-2 and the first half of AC-3, and must
	fail this - scoring 100% on one ring and 0% on five". All three are asserted
	below with the numbers they MEASURED, and so are the controls for the
	mutation the story's `## Notes` asks the orchestrator to run (swapped
	accessors, mutation 3), the sign error the Contract warns about (a lens that
	reads the supplier), and one-defect generators for AC-1, AC-6, AC-7 and the
	Contract's sub-stream pin, which would otherwise have no control at all.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half is
	the one that is easy to leave out and worth the most: a stub that fails EVERY
	check proves only that the checks reject something, and a control that fails
	everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	measured here rather than predicted. The constant and seed-ignoring
	generators both fail AC-3's second half AND AC-5 - the story's `## Notes`
	predicts exactly that for mutation 2. The in-place generator fails AC-3's
	first half, AC-5 and the sub-stream pin as well as AC-7, because the checks
	reuse one seated list across calls and a generator that shuffles it in place
	corrupts every later call; that is a property of the defect, not of the
	checks, and it is recorded in the story's mutation table.

	NOTHING HERE REQUIRES PRODUCTION CODE. In RED `src/server/seats/Ring.luau`
	does not exist, `tests/server/ring_test.luau` fails at `require`, and not one
	assertion in it has executed. These controls need only ROUND-001's `Rng`,
	which is merged, so the numbers below are measurements taken in RED rather
	than claims left for GREEN.

	SEAT-003 ADDS THE SECOND HALF OF THIS FILE: the controls for `withdraw` and
	`rejoin`. The same discipline, the same reason - in SEAT-003's RED the real
	module has neither function, so `ring_test.luau`'s new tests fail before
	their assertion runs - and two of its controls are the ones the story names:
	transfer to the DEPENDENT (mutation 1, which passes the naive "somebody
	holds it" test and must fail AC-1) and suppliers read off the ring AS DEALT
	(mutation 2, which passes every single-withdrawal check and must fail AC-7).
	Every SEAT-003 control is also held to all ten SEAT-001 checks: its defect
	is in the withdrawal, so the ring it deals is correct.
]]

local Contract = require("../helpers/RingContract")
local Stubs = require("../helpers/RingStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local function accepts(check: Check, ring: any, what: string)
	local ok, err = pcall(check, ring)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, ring: any, what: string): string
	local ok, err = pcall(check, ring)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

-- The checks a generator that gets the STRUCTURE right passes: everything
-- except the one it is built to fail. Listed once, used by every control whose
-- single defect leaves the structure intact.
local function passesTheStructuralChecks(ring: any, who: string, except: { [string]: boolean })
	local structural: { Named } = {
		{ label = "AC-1", check = Contract.sigmaIsAFixedPointFreePermutation },
		{ label = "AC-2", check = Contract.sigmaIsASingleCycle },
		{ label = "AC-3 (first half)", check = Contract.sameSeedSameAssignment },
		{ label = "AC-3 (second half)", check = Contract.differentSeedsProduceDifferentRings },
		{ label = "AC-4 (keys)", check = Contract.keyClassesAreOneToNEachOnce },
		{ label = "AC-4 (lens direction)", check = Contract.lensIsTheDependentsKeyClass },
		{ label = "AC-5", check = Contract.ringsOfFourAreUniformlyDistributed },
		{ label = "AC-6", check = Contract.fewerThanThreeSeatedRaises },
		{ label = "AC-7", check = Contract.inputIsNotMutatedAndSeatOrderIsKept },
		{ label = "sub-stream pin", check = Contract.assignDrawsFromItsOwnSubStream },
	}
	for _, entry in structural do
		if not except[entry.label] then
			accepts(entry.check, ring, `{entry.label} on {who}`)
		end
	end
end

-- SEAT-003's checks, by the label the story uses. A withdrawal control is held
-- to every one of these AND every SEAT-001 check, except the ones it is built
-- to fail.
local WITHDRAWAL_CHECKS: { Named } = {
	{ label = "AC-1", check = Contract.withdrawTransfersTheKeyClassToTheSupplier },
	{ label = "naive", check = Contract.naiveEveryClassIsHeldBySomebody },
	{ label = "AC-2", check = Contract.withdrawnRingIsOneCycleInTheOriginalOrder },
	{ label = "AC-3", check = Contract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens },
	{ label = "AC-4", check = Contract.leaversLensIsLost },
	{ label = "AC-5", check = Contract.rejoinInsideTheGraceWindowRestoresTheSeat },
	{ label = "AC-6", check = Contract.rejoinAtOrAfterTheGraceBoundaryIsRefused },
	{ label = "AC-7", check = Contract.twoWithdrawalsEachTransferToTheSupplierAtTheTime },
	{
		label = "AC-8",
		check = Contract.withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing,
	},
	{ label = "no-mutation", check = Contract.withdrawDoesNotMutateOrAliasItsArgument },
	{ label = "raise", check = Contract.withdrawOfAnUnseatedPlayerRaises },
	{ label = "rejoin no-mutation", check = Contract.rejoinDoesNotMutateOrAliasItsArguments },
	{ label = "list order", check = Contract.supplierListIsOwnClassesThenTheLeaversInOrder },
}

local function passesTheWithdrawalChecks(ring: any, who: string, except: { [string]: boolean })
	passesTheStructuralChecks(ring, who, {})
	for _, entry in WITHDRAWAL_CHECKS do
		if not except[entry.label] then
			accepts(entry.check, ring, `SEAT-003 {entry.label} on {who}`)
		end
	end
end

return {
	--[[ The baseline. Every control below is this generator with exactly one
	     defect set, so a control that fires is attributable to that one thing. ]]

	["baseline: a seeded single-cycle generator over the real Rng passes every SEAT-001 check"] = function()
		passesTheStructuralChecks(Stubs.correct, "the baseline generator", {})
	end,

	--[[
		AC-2's control, named in the criterion: a random derangement with no
		cycle constraint. It passes AC-1 - every σ it deals has no fixed point -
		and passes AC-5 too, as the story's `## Notes` predicts for mutation 1:
		the six cyclic rings share two thirds of the sample evenly, about 11%
		each, inside the 8-25% band. Only counting the orbit sees it.

		THE MEASURED NUMBER: at n = 4, 22 of the 64 seeds produced two disjoint
		2-cycles (expected 64/3 ≈ 21). A one-seed check would have let this
		generator through on 42 of those 64 seeds.
	]]
	["AC-2 control: a plain derangement generator passes AC-1 and AC-5 and fails AC-2 at n = 4 on 22 of 64 seeds"] = function()
		local ring = Stubs.plainDerangement
		passesTheStructuralChecks(ring, "the plain-derangement generator", { ["AC-2"] = true })

		local message = refuses(
			Contract.sigmaIsASingleCycle,
			ring,
			"a generator that produces a random derangement without the cycle constraint must "
				.. "fail AC-2"
		)
		names(message, "AC-2", "the AC-2 control fires")
		names(
			message,
			"n = 4: 22 of 64 seeds",
			"the AC-2 failure carries the number of n = 4 seeds that were not one cycle"
		)
		names(
			message,
			"n = 3: 0 of 64 seeds",
			"at n = 3 both derangements are cycles, so AC-2 cannot fire there and AC-1 does the work"
		)
		names(
			message,
			"(length 2 of 4)",
			"the AC-2 failure shows an orbit that closed after two players"
		)
	end,

	--[[
		AC-3's control, named in the criterion: a generator that ignores its seed.
		Same seed, same ring - trivially, since every seed gives the same ring -
		so the first half is green. Different seeds, one ring, so the second half
		is red, and so is AC-5, with 100% on the one ring it always deals.
	]]
	["AC-3 control: a seed-ignoring generator passes the same-seed half and fails the different-seeds half, and AC-5"] = function()
		local ring = Stubs.seedIgnoring
		passesTheStructuralChecks(ring, "the seed-ignoring generator", {
			["AC-3 (second half)"] = true,
			["AC-5"] = true,
		})

		local message = refuses(
			Contract.differentSeedsProduceDifferentRings,
			ring,
			"a generator that ignores its seed must fail AC-3's second half"
		)
		names(message, "AC-3", "the AC-3 control fires")
		names(
			message,
			"16 seeds produced 1 distinct ring(s)",
			"the AC-3 failure names the number of distinct rings it counted"
		)

		names(
			refuses(
				Contract.ringsOfFourAreUniformlyDistributed,
				ring,
				"a seed-ignoring generator deals one ring 10,000 times and must fail AC-5"
			),
			"5 of the 6 cyclic derangements never appeared",
			"AC-5 fires on the seed-ignoring generator with five rings absent"
		)
	end,

	--[[
		AC-5's control, named in the criterion, and THE control of this story:
		the canonical ring players[1] → players[2] → ... → players[1], every time.

		It has no fixed point, it is one cycle, it reproduces from its seed, its
		keys are 1..n and its lens reads the dependent, it leaves its input alone
		and it does not care what the parent rng has drawn. Every structural
		check in the story is green for it. AC-5 is the only check that is not,
		and this test is the measurement that AC-5 is doing that job: 100.0% on
		one ring, 0 on five.
	]]
	["AC-5 control: the constant canonical ring passes AC-1, AC-2, AC-4, AC-6, AC-7 and the same-seed half of AC-3, and fails AC-5 at 100% on one ring"] = function()
		local ring = Stubs.canonical
		passesTheStructuralChecks(ring, "the canonical constant generator", {
			["AC-3 (second half)"] = true,
			["AC-5"] = true,
		})

		local message = refuses(
			Contract.ringsOfFourAreUniformlyDistributed,
			ring,
			"a generator that always returns the canonical cycle must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
		names(
			message,
			"5 of the 6 cyclic derangements never appeared",
			"the AC-5 failure counts the five rings the constant generator never dealt"
		)
		-- The MEASURED share: the whole sample on the seat-order ring, and the
		-- seat order here is kim, zed, amy, bob (see RingContract.seated).
		names(
			message,
			"kim>zed,zed>amy,amy>bob,bob>kim = 10000 (100.0%)  <- above 25.0%",
			"the AC-5 failure names the one ring the constant generator dealt and its share"
		)

		-- The second half of AC-3 fires too: mutation 2 of the story's `## Notes`
		-- predicts "AC-5 goes red and AC-3's second half goes red", and this is
		-- the measurement of that prediction.
		names(
			refuses(
				Contract.differentSeedsProduceDifferentRings,
				ring,
				"a constant generator also fails AC-3's different-seeds half"
			),
			"AC-3",
			"AC-3's second half fires on the constant generator"
		)
	end,

	--[[
		AC-4's controls. Mutation 3 of the story's `## Notes`: supplierOf and
		dependentOf exchanged. And the sign error the Contract spends a section
		on: a lens that reads the supplier's key class. Both deal a perfectly
		good ring, so AC-1, AC-2, AC-3, AC-5, AC-6 and AC-7 are green for both;
		only the direction check sees either. The story says that if this check
		stays green under mutation 3, "AC-4 is not actually pinning the
		direction, and SEAT-003 will inherit the error" - so it is measured.
	]]
	["AC-4 control: swapping supplierOf and dependentOf passes every other check and fails the direction half of AC-4"] = function()
		local ring = Stubs.swappedAccessors
		passesTheStructuralChecks(ring, "the swapped-accessors generator", {
			["AC-4 (lens direction)"] = true,
		})

		local message = refuses(
			Contract.lensIsTheDependentsKeyClass,
			ring,
			"a ring whose supplierOf and dependentOf are exchanged must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires on swapped accessors")
		names(
			message,
			"dependentOf is σ, the ring-successor",
			"the AC-4 failure says which way round dependentOf goes"
		)
		names(
			message,
			"supplierOf is σ⁻¹, the ring-predecessor",
			"the AC-4 failure says which way round supplierOf goes"
		)
		-- The MEASURED count: every player in every case, 4 values of n times 8
		-- seeds.
		names(message, "in 32 case(s)", "the AC-4 failure counts every (n, seed) case")
	end,

	["AC-4 control: a lens that reads the supplier's key class passes every other check and fails the direction half of AC-4"] = function()
		local ring = Stubs.lensFromSupplier
		passesTheStructuralChecks(ring, "the lens-from-supplier generator", {
			["AC-4 (lens direction)"] = true,
		})

		local message = refuses(
			Contract.lensIsTheDependentsKeyClass,
			ring,
			"a ring whose lens reads k(σ⁻¹(p)) instead of k(σ(p)) must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires on a backwards lens")
		names(
			message,
			"the lens must read the DEPENDENT's key class",
			"the AC-4 failure names the direction the lens must read"
		)
		names(
			message,
			"λ(kim) = 2, but k(σ(kim)) = k(amy) = 3",
			"the AC-4 failure shows the lens holding the supplier's key, at the first seed"
		)
	end,

	--[[
		AC-1's control: σ is a plain shuffle and fixed points are allowed. It is
		also not a cycle most of the time, and its six cyclic rings each take
		about 4% of the AC-5 sample (six 4-cycles in 24 permutations), so AC-2
		and AC-5 fire as well. Everything that reads the assignment's SHAPE -
		keys, lens, reproducibility, the input - is green.
	]]
	["AC-1 control: a generator that allows fixed points fails AC-1 on 168 of 256 cases, and AC-2 and AC-5 with it"] = function()
		local ring = Stubs.anyPermutation
		passesTheStructuralChecks(ring, "the any-permutation generator", {
			["AC-1"] = true,
			["AC-2"] = true,
			["AC-5"] = true,
		})

		local message = refuses(
			Contract.sigmaIsAFixedPointFreePermutation,
			ring,
			"a generator whose σ may have a fixed point must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 control fires")
		names(message, "a fixed point", "the AC-1 failure names the fixed point it found")
		names(message, "in 168 of 256", "the AC-1 failure counts the cases it measured")

		names(
			refuses(Contract.sigmaIsASingleCycle, ring, "a plain permutation is rarely one cycle"),
			"AC-2",
			"AC-2 fires on the any-permutation generator"
		)
		names(
			refuses(
				Contract.ringsOfFourAreUniformlyDistributed,
				ring,
				"six 4-cycles in 24 permutations puts every cyclic ring near 4%"
			),
			"6 fell outside the 8.0%-25.0% band",
			"AC-5 fires on the any-permutation generator with all six rings below the floor"
		)
	end,

	--[[
		AC-6's control: no minimum. At n = 2 it deals a swap, at n = 1 a fixed
		point, at n = 0 nothing - and every one of those is a table shaped like
		an Assignment, which is why AC-6 pins RAISING rather than any property of
		the result. Every check over n >= 3 is green for it.
	]]
	["AC-6 control: a generator with no minimum count returns a swap at 2 and a fixed point at 1, and fails only AC-6"] = function()
		local ring = Stubs.degenerate
		passesTheStructuralChecks(ring, "the no-minimum generator", { ["AC-6"] = true })

		local message = refuses(
			Contract.fewerThanThreeSeatedRaises,
			ring,
			"a generator that deals a ring to fewer than three players must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
		-- The MEASURED degenerate rings, verbatim, in SEAT-003's shape: a
		-- one-element list per player and a stored lens.
		names(
			message,
			"n = 2: assign returned { keyClasses = { kim = { 1 = 1 }, zed = { 1 = 2 } }, "
				.. 'lens = { kim = 2, zed = 1 }, players = { 1 = "kim", 2 = "zed" }, '
				.. 'sigma = { kim = "zed", zed = "kim" } } instead of raising',
			"the AC-6 failure shows the two-player swap the criterion calls not a ring"
		)
		names(
			message,
			'sigma = { kim = "kim" }',
			"the AC-6 failure shows the one-player fixed point"
		)
	end,

	--[[
		AC-7's control: the caller's list shuffled in place and handed back as
		the seat order. AC-7 fires on both halves. So do AC-3's first half, AC-5
		and the sub-stream pin, because the checks hand the same seated list to
		consecutive calls and this generator scrambles it between them - the
		defect corrupts the fixture, and every check that compares two calls on
		one fixture sees the corruption. That is the measurement, not a defect
		in the checks, and it is why the story's mutation table lists four reds
		for this generator rather than one.
	]]
	["AC-7 control: a generator that shuffles its input in place fails AC-7 on both halves, and corrupts the fixture for AC-3, AC-5 and the sub-stream pin"] = function()
		local ring = Stubs.inPlace
		passesTheStructuralChecks(ring, "the in-place generator", {
			["AC-3 (first half)"] = true,
			["AC-5"] = true,
			["AC-7"] = true,
			["sub-stream pin"] = true,
		})

		local message = refuses(
			Contract.inputIsNotMutatedAndSeatOrderIsKept,
			ring,
			"a generator that mutates the list it was given must fail AC-7"
		)
		names(message, "AC-7", "the AC-7 control fires")
		names(message, "the input list was mutated", "the AC-7 failure names the mutation")
		names(
			message,
			"wanted the input order",
			"the AC-7 failure names the seat-order half as well, compared against the snapshot"
		)

		local alsoFails: { Named } = {
			{ label = "AC-3", check = Contract.sameSeedSameAssignment },
			{ label = "AC-5", check = Contract.ringsOfFourAreUniformlyDistributed },
			{
				label = "Contract: assign must draw",
				check = Contract.assignDrawsFromItsOwnSubStream,
			},
		}
		for _, entry in alsoFails do
			names(
				refuses(
					entry.check,
					ring,
					`the in-place generator corrupts the fixture for {entry.label}`
				),
				entry.label,
				`{entry.label} fires on the in-place generator`
			)
		end
	end,

	--[[
		The sub-stream pin's control: shuffling with the parent rng rather than
		`rng:derive("seats")`. Every criterion is green for it - it is a correct
		generator in every respect the seven criteria name - and only the pin,
		which drains five draws from the parent before calling, sees it. It is
		the generator that would make the M3 instance generator's first draw
		move every seat.
	]]
	["sub-stream control: a generator that draws from the parent rng passes AC-1 through AC-7 and fails only the sub-stream pin"] = function()
		local ring = Stubs.parentDrawing
		passesTheStructuralChecks(ring, "the parent-drawing generator", {
			["sub-stream pin"] = true,
		})

		local message = refuses(
			Contract.assignDrawsFromItsOwnSubStream,
			ring,
			"a generator that shuffles with the parent rng must fail the sub-stream pin"
		)
		names(
			message,
			"five draws from the parent rng changed the assignment",
			"the sub-stream pin's failure says what moved the seats"
		)
	end,

	--[[ ==================================================================
	     SEAT-003. The withdrawal and rejoin controls.
	================================================================== ]]

	["SEAT-003 baseline: the seeded generator with the Contract's withdraw and rejoin passes every SEAT-001 and SEAT-003 check"] = function()
		passesTheWithdrawalChecks(Stubs.correct, "the baseline ring", {})
	end,

	--[[
		AC-1's control, named in the criterion, and THE control of this story:
		the leaver's class goes to σ(q), the DEPENDENT. Mutation 1 of `## Notes`.

		BOTH HALVES. It PASSES the naive "somebody holds it" test, which is what
		makes it the implementation that would otherwise ship; it FAILS AC-1 in
		all 32 cases, and the message names the holder as the dependent and the
		supplier as the one who could already see the values. It also fails
		AC-3 (the supplier holds one class, and NOBODY can act on their own
		lens - the dependent's lens reads σ(d), not q), AC-7 (both classes
		land on the wrong player) and the list-order pin; every check of ring
		shape - AC-2, AC-4, AC-5, AC-6, AC-8 - is green, which is the point:
		the wrong direction is structurally invisible.
	]]
	["SEAT-003 AC-1 control: transferring to the dependent σ(q) passes the naive somebody-holds-it test and every shape check, and fails AC-1 on 32 of 32 naming the dependent"] = function()
		local ring = Stubs.transferToDependent
		passesTheWithdrawalChecks(ring, "the transfer-to-dependent ring", {
			["AC-1"] = true,
			["AC-3"] = true,
			["AC-7"] = true,
			["list order"] = true,
		})
		accepts(
			Contract.naiveEveryClassIsHeldBySomebody,
			ring,
			"the transfer-to-dependent ring must PASS the naive somebody-holds-it test, or the "
				.. "control proves nothing about AC-1"
		)

		local message = refuses(
			Contract.withdrawTransfersTheKeyClassToTheSupplier,
			ring,
			"a withdrawal that hands the class to the dependent must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 control fires")
		names(message, "in 32 of 32 (seed, leaver) cases at n = 4", "AC-1 fires in every case")
		-- MEASURED at the first seed: kim's dependent is amy, kim's supplier is bob.
		names(
			message,
			"k(kim) = 1 is held by amy, wanted the supplier bob alone - amy is σ(kim), the DEPENDENT; "
				.. "the supplier σ⁻¹(kim) = bob is the player who could already see those required "
				.. "values (roles.md §6)",
			"the AC-1 failure names the dependent as the holder and says which way the transfer goes"
		)

		names(
			refuses(
				Contract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens,
				ring,
				"with the class on the dependent, nobody can act on their own lens"
			),
			"0 player(s) can act on a class their own lens covers [], wanted exactly one - the supplier",
			"AC-3 fires on the dependent transfer with zero actors"
		)
		names(
			refuses(
				Contract.twoWithdrawalsEachTransferToTheSupplierAtTheTime,
				ring,
				"and AC-7 sees both transfers land wrong"
			),
			"in 80 of 80 cases",
			"AC-7 fires on the dependent transfer in every case"
		)
	end,

	--[[
		The naive check's own control: the leaver's classes go to nobody. This
		is what shows the naive test can fail at all - a control the dependent
		transfer PASSES is only meaningful if something FAILS it.
	]]
	["SEAT-003 naive control: dropping the leaver's classes fails the naive somebody-holds-it test on 32 of 32, and AC-1, AC-3, AC-7, AC-8 and the list-order pin with it"] = function()
		local ring = Stubs.dropLeaversClasses
		passesTheWithdrawalChecks(ring, "the drop-the-classes ring", {
			["AC-1"] = true,
			["naive"] = true,
			["AC-3"] = true,
			["AC-7"] = true,
			["AC-8"] = true,
			["list order"] = true,
		})

		local message = refuses(
			Contract.naiveEveryClassIsHeldBySomebody,
			ring,
			"a withdrawal that loses the class must fail even the naive test"
		)
		names(message, "naive: a key class is held by nobody", "the naive check fires")
		names(message, "in 32 of 32 cases", "the naive check fires in every case")

		names(
			refuses(Contract.withdrawTransfersTheKeyClassToTheSupplier, ring, "and AC-1 sees it"),
			"k(kim) = 1 is held by nobody, wanted the supplier bob alone",
			"the AC-1 failure says the class is held by nobody"
		)
		names(
			refuses(
				Contract.withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing,
				ring,
				"and AC-8 sees a class missing from the 2-ring"
			),
			"wanted all three classes once each",
			"AC-8 counts the classes the two remaining players hold"
		)
	end,

	--[[
		AC-7's control, named in the criterion: σ⁻¹ read off the ring AS DEALT.
		Mutation 2 of `## Notes`. It passes AC-1 and every other single-
		withdrawal check - the first withdrawal's two rings agree - and fails
		AC-7 in EXACTLY the 40 of 80 cases where the second leaver is the first
		leaver's dependent: their original supplier is the first leaver, who has
		gone, so the class lands on a player who is not seated. The other 40,
		where the second leaver is the supplier, pass, which is what "vacuous
		unless the second leaver is chosen so the suppliers differ" means.
	]]
	["SEAT-003 AC-7 control: suppliers computed against the ring as dealt pass AC-1 and every single-withdrawal check, and fail AC-7 on exactly the 40 of 80 dependent-second cases"] = function()
		local ring = Stubs.supplierFromOriginal
		passesTheWithdrawalChecks(ring, "the supplier-from-original ring", { ["AC-7"] = true })
		accepts(
			Contract.withdrawTransfersTheKeyClassToTheSupplier,
			ring,
			"the supplier-from-original ring must PASS AC-1, or the control proves nothing about AC-7"
		)

		local message = refuses(
			Contract.twoWithdrawalsEachTransferToTheSupplierAtTheTime,
			ring,
			"a withdrawal that reads the supplier off the original ring must fail AC-7"
		)
		names(message, "AC-7", "the AC-7 control fires")
		names(message, "in 40 of 80 cases", "AC-7 fires in exactly the dependent-second half")
		-- MEASURED at the first seed: kim's dependent is bob; bob's original
		-- supplier is kim, who has left.
		names(
			message,
			"kim leaves, then their dependent bob leaves: class 4 is held by kim (not seated), wanted eve alone",
			"the AC-7 failure shows the class landing on the departed original supplier"
		)
	end,

	--[[
		AC-4's control, PO-1's trap in the FIELD: every lens recomputed as
		k(σ(p)) after the ring closes. With σ(s) = d that gives the supplier
		k(d) = λ(q), the lost lens. AC-3 fires too - the supplier's lens no
		longer covers the class they hold, so nobody can act - and AC-8, whose
		2-ring lenses are wrong.
	]]
	["SEAT-003 AC-4 control: a lens recomputed as k(σ(p)) after the ring closes hands the supplier the lost lens and fails AC-4 on 72 of 72, and AC-3 and AC-8 with it"] = function()
		local ring = Stubs.deriveLensAfterClose
		passesTheWithdrawalChecks(ring, "the derive-lens-after-close ring", {
			["AC-3"] = true,
			["AC-4"] = true,
			["AC-8"] = true,
		})

		local message = refuses(
			Contract.leaversLensIsLost,
			ring,
			"a withdrawal that recomputes the lens from σ must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires")
		names(message, "in 72 of 72 (n, seed, leaver) cases", "AC-4 fires in every case")
		-- MEASURED at the first seed: kim leaves; kim's supplier bob now has
		-- σ(bob) = amy, k(amy) = 3 = λ(kim).
		names(
			message,
			"λ(bob) = 3, the LEAVER's lens - it is lost, not handed on (roles.md §6)",
			"the AC-4 failure names the lost lens on the supplier"
		)

		names(
			refuses(
				Contract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens,
				ring,
				"a supplier whose lens moved off their new class cannot act on it"
			),
			"0 player(s) can act on a class their own lens covers",
			"AC-3 fires on the derived lens with zero actors"
		)
	end,

	--[[
		PO-1's trap in the ACCESSOR: `lensOf` computes k(σ(p)) instead of
		reading the field. The field is right, so only the lensOf half of AC-4
		sees it - and it sees it in every case.
	]]
	["SEAT-003 AC-4 control: a lensOf that derives k(σ(p)) instead of reading the stored lens fails AC-4 alone, on the lensOf half"] = function()
		local ring = Stubs.lensOfDerives
		passesTheWithdrawalChecks(ring, "the deriving-lensOf ring", { ["AC-4"] = true })

		local message =
			refuses(Contract.leaversLensIsLost, ring, "a deriving lensOf must fail AC-4")
		names(message, "in 72 of 72", "AC-4 fires in every case on the deriving lensOf")
		names(
			message,
			"lensOf(bob) = 3, but λ(bob) = 1 - lensOf must read the stored lens, not recompute k(σ(p)) (PO-1)",
			"the AC-4 failure names lensOf as the half that is wrong"
		)
	end,

	--[[
		AC-2's controls: the seat order rebuilt sorted, and the ring closed one
		step too far (σ(s) = σ(d), so d has no predecessor and σ(d) has two).
		The second breaks the ring badly enough that a SECOND withdrawal cannot
		find a supplier, so AC-7 fails on it too - through the check's own
		"cannot be found" report, not a crash - and AC-8's 2-ring has a fixed
		point.
	]]
	["SEAT-003 AC-2 control: re-seating the remaining players sorted fails AC-2 on 120 of 120, and AC-7 and AC-8 where the sorted order differs"] = function()
		local ring = Stubs.sortRemainingSeats
		passesTheWithdrawalChecks(ring, "the sorted-seats ring", {
			["AC-2"] = true,
			["AC-7"] = true,
			["AC-8"] = true,
		})

		local message = refuses(
			Contract.withdrawnRingIsOneCycleInTheOriginalOrder,
			ring,
			"a withdrawal that re-sorts the seats must fail AC-2"
		)
		names(message, "AC-2", "the AC-2 control fires")
		names(message, "in 120 of 120 (n, seed, leaver) cases", "AC-2 fires in every case")
		names(
			message,
			'players is { 1 = "amy", 2 = "bob", 3 = "zed" }, wanted the seat order minus the leaver { 1 = "zed", 2 = "amy", 3 = "bob" }',
			"the AC-2 failure shows the sorted order against the seat order"
		)
	end,

	["SEAT-003 AC-2 control: closing the ring one step too far fails AC-2 on 120 of 120 - two players map to one, the orbit is short - and AC-7 and AC-8 with it"] = function()
		local ring = Stubs.closeOneStepTooFar
		passesTheWithdrawalChecks(ring, "the close-too-far ring", {
			["AC-2"] = true,
			["AC-7"] = true,
			["AC-8"] = true,
		})

		local message = refuses(
			Contract.withdrawnRingIsOneCycleInTheOriginalOrder,
			ring,
			"a ring closed past the dependent must fail AC-2"
		)
		names(message, "in 120 of 120", "AC-2 fires in every case")
		names(
			message,
			"σ maps two players to zed",
			"the AC-2 failure says σ is not a permutation"
		)
		names(
			message,
			"the orbit of zed is zed → bob, wanted the original orbit minus the leaver zed → bob → amy",
			"the AC-2 failure shows the short orbit against the expected one"
		)
		names(
			refuses(
				Contract.withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing,
				ring,
				"the 2-ring has a fixed point"
			),
			'σ is { amy = "zed", zed = "zed" }, wanted the 2-cycle { amy = "zed", zed = "amy" }',
			"AC-8 shows the fixed point"
		)
	end,

	--[[
		AC-6's control, mutation 3 of `## Notes`: `>` instead of `>=`. It fails
		AC-6 in EXACTLY the 96 of 288 cases at the boundary - 32 (seed, leaver)
		cases × 3 departure times - and nothing else: AC-5's t + grace − 0.1 is
		inside the window either way.
	]]
	["SEAT-003 AC-6 control: a grace comparison of > instead of >= passes AC-5 and fails AC-6 on exactly the 96 of 288 cases at t + disconnect_grace_seconds"] = function()
		local ring = Stubs.graceExclusive
		passesTheWithdrawalChecks(ring, "the exclusive-grace ring", { ["AC-6"] = true })

		local message = refuses(
			Contract.rejoinAtOrAfterTheGraceBoundaryIsRefused,
			ring,
			"a rejoin that admits the player at exactly t + grace must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
		names(message, "in 96 of 288 cases", "AC-6 fires on exactly the boundary cases")
		names(
			message,
			`rejoin at exactly t + disconnect_grace_seconds ({Contract.GRACE_SECONDS}, left at 0) returned an assignment with 4 seated instead of nil - the comparison is now - leftAt >= graceSeconds, too late INCLUSIVE`,
			"the AC-6 failure names the boundary and the comparison"
		)
	end,

	["SEAT-003 AC-5 control: a rejoin that always returns nil passes AC-6 and fails AC-5 on 192 of 192"] = function()
		local ring = Stubs.rejoinAlwaysNil
		passesTheWithdrawalChecks(ring, "the never-rejoin ring", { ["AC-5"] = true })

		local message = refuses(
			Contract.rejoinInsideTheGraceWindowRestoresTheSeat,
			ring,
			"a rejoin that never restores must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
		names(message, "in 192 of 192 cases", "AC-5 fires in every case")
		names(
			message,
			`rejoins at {Contract.GRACE_SECONDS - 0.1} (grace {Contract.GRACE_SECONDS}): rejoin returned nil; kim is inside the window and must get their seat back`,
			"the AC-5 failure names the time and the player"
		)
	end,

	--[[
		PO-3's controls. Mutating the argument fails the no-mutation pin, and
		because every check deals a fresh ring per leaver it fails ONLY where the
		check reads the argument after the call: AC-3 and the list-order pin
		both look up the supplier in the ring as passed and report that it
		cannot be found. AC-5 PASSES - the snapshot the check holds is the same
		table the withdrawal rewrote, so the "restored" ring equals it - which
		is exactly why PO-3 is pinned separately rather than left to AC-5.
	]]
	["SEAT-003 PO-3 control: a withdraw that edits its argument in place fails the no-mutation pin on 32 of 32, AC-3 and the list-order pin, and PASSES AC-5"] = function()
		local ring = Stubs.mutateArgument
		passesTheWithdrawalChecks(ring, "the in-place withdraw", {
			["no-mutation"] = true,
			["AC-3"] = true,
			["list order"] = true,
		})
		accepts(
			Contract.rejoinInsideTheGraceWindowRestoresTheSeat,
			ring,
			"AC-5 must PASS on the in-place withdraw - the snapshot it compares against was rewritten "
				.. "too - which is why PO-3 has its own pin"
		)

		local message = refuses(
			Contract.withdrawDoesNotMutateOrAliasItsArgument,
			ring,
			"a withdraw that mutates its argument must fail the no-mutation pin"
		)
		names(message, "PO-3", "the no-mutation pin fires")
		names(message, "in 32 of 32 cases", "it fires in every case")
		names(message, "the argument was mutated:", "the failure says the argument changed")
		names(
			message,
			"withdraw returned its argument rather than a fresh table",
			"and that the result is the argument"
		)
		names(
			refuses(
				Contract.supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens,
				ring,
				"AC-3 cannot find the supplier in the rewritten ring"
			),
			"cannot be found in the ring as passed - was the argument mutated by the withdrawal?",
			"AC-3 reports the mutation rather than crashing on it"
		)
	end,

	["SEAT-003 PO-3 control: a withdraw whose untouched lists are the argument's own passes every criterion and fails the no-mutation pin alone, by aliasing"] = function()
		local ring = Stubs.shareSubTables
		passesTheWithdrawalChecks(ring, "the shared-lists withdraw", { ["no-mutation"] = true })

		local message = refuses(
			Contract.withdrawDoesNotMutateOrAliasItsArgument,
			ring,
			"a result sharing the argument's lists must fail the no-mutation pin"
		)
		names(message, "in 32 of 32 cases", "it fires in every case")
		names(
			message,
			"result.keyClasses[zed] IS the argument's own list (shared, so a later transfer appended in place would rewrite the snapshot)",
			"the failure names the shared list and why it matters"
		)
	end,

	["SEAT-003 list-order control: the leaver's classes ahead of the supplier's own passes every criterion and fails the list-order pin alone, on 40 of 40"] = function()
		local ring = Stubs.leaverClassesFirst
		passesTheWithdrawalChecks(ring, "the leaver-first withdraw", { ["list order"] = true })

		local message = refuses(
			Contract.supplierListIsOwnClassesThenTheLeaversInOrder,
			ring,
			"a supplier list with the leaver's classes first must fail the list-order pin"
		)
		names(message, "in 40 of 40 cases", "it fires in every case")
		names(
			message,
			"keyClasses[eve] = { 1 = 1, 2 = 5 }, wanted own then the leaver's: { 1 = 5, 2 = 1 }",
			"the failure shows the reversed list against the expected one"
		)
		names(
			message,
			"keyClasses[zed] = { 1 = 1, 2 = 5, 3 = 2 }, wanted own then all of the leaver's in order: { 1 = 2, 2 = 5, 3 = 1 }",
			"and the three-class list after the second withdrawal"
		)
	end,

	["SEAT-003 raise control: a withdraw that returns a copy for an unseated player passes every criterion and fails the raise pin alone, in 3 cases"] = function()
		local ring = Stubs.ignoreUnseated
		passesTheWithdrawalChecks(ring, "the ignore-unseated withdraw", { ["raise"] = true })

		local message = refuses(
			Contract.withdrawOfAnUnseatedPlayerRaises,
			ring,
			"a withdraw that does not raise for a stranger must fail the raise pin"
		)
		names(message, "in 3 case(s)", "all three strangers are counted")
		names(
			message,
			'withdraw(assignment, "sam") returned {',
			"the failure shows the copy that came back"
		)
		names(message, "withdraw(assignment, nil) returned {", "including for nil")
	end,

	["SEAT-003 PO-4 control: a rejoin that hands back the snapshot itself passes AC-5 and AC-6 and fails the rejoin no-mutation pin on the 32 of 64 inside-the-window cases"] = function()
		local ring = Stubs.rejoinReturnsSnapshot
		passesTheWithdrawalChecks(
			ring,
			"the snapshot-returning rejoin",
			{ ["rejoin no-mutation"] = true }
		)

		local message = refuses(
			Contract.rejoinDoesNotMutateOrAliasItsArguments,
			ring,
			"a rejoin returning absence.snapshot itself must fail the rejoin pin"
		)
		names(message, "PO-4", "the rejoin pin fires")
		names(message, "in 32 of 64 cases", "it fires on exactly the cases where a ring came back")
		names(
			message,
			"rejoin returned absence.snapshot itself rather than a deep copy",
			"the failure names the aliasing"
		)
	end,

	["SEAT-003 PO-4 control: a rejoin that re-seats the player into the assignment it was passed fails the rejoin no-mutation pin on 32 of 64 and nothing else"] = function()
		local ring = Stubs.rejoinMutatesArgument
		passesTheWithdrawalChecks(ring, "the in-place rejoin", { ["rejoin no-mutation"] = true })

		local message = refuses(
			Contract.rejoinDoesNotMutateOrAliasItsArguments,
			ring,
			"a rejoin that mutates the assignment must fail the rejoin pin"
		)
		names(message, "in 32 of 64 cases", "it fires on exactly the inside-the-window cases")
		names(message, "the assignment was mutated:", "the failure says the assignment changed")
	end,
}
