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
		-- The MEASURED degenerate rings, verbatim.
		names(
			message,
			'n = 2: assign returned { keyClass = { kim = 1, zed = 2 }, players = { 1 = "kim", '
				.. '2 = "zed" }, sigma = { kim = "zed", zed = "kim" } } instead of raising',
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
}
