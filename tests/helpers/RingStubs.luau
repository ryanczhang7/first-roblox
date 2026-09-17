--!strict
--[[
	The wrong seat generators SEAT-001's controls are aimed at, and the one
	baseline each of them is a single defect away from.

	THREE CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-2: "a generator that
	produces a random derangement without the cycle constraint passes AC-1 and
	must fail this at n = 4". AC-3: "a generator that ignores its seed passes the
	first half and must fail the second". AC-5: "a generator that always returns
	the canonical cycle p1 → p2 → p3 → p4 → p1 satisfies AC-1, AC-2 and the first
	half of AC-3, and must fail this - scoring 100% on one ring and 0% on five".
	A criterion that names an implementation needs an implementation to point
	at, so the generators below really do deal seats.

	The rest are the mutations the story's `## Notes` asks the orchestrator to
	run at acceptance (swapped accessors, mutation 3) and the one-defect
	implementations the remaining criteria would otherwise have no control for.

	It is a FACTORY over a table of defects, as `RoundEndingStubs.luau` is, so
	that `defects` is empty for the baseline and has exactly ONE field set for
	every control: a control that fires is then attributable to that one field.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/server/seats/Ring.luau`
	and not a sketch of one. The baseline is the Contract's construction only as
	far as the checks can see - it has no types beyond `any`, its key-class
	choice (seat index) is one of several the Contract allows, and its error
	message at n < 3 is whatever fell out. GREEN writes the module from the
	story's Contract, against the failing tests in `tests/server/ring_test.luau`;
	nothing here is to be copied.

	NOTHING HERE REQUIRES PRODUCTION CODE - `src/shared/Rng.luau` is ROUND-001's,
	merged and frozen - so these controls are EXECUTED in RED, and
	`tests/server/ring_controls_test.luau` records what each one actually did.
]]

local Rng = require("../../src/shared/Rng")

local RingStubs = {}

--[[
	One field per control, each a single edit to the generator below.

	  * `plainDerangement` - rejection-sample a derangement with no cycle
	                         constraint (AC-2's control; mutation 1 of `## Notes`)
	  * `constantCanonical` - always players[1] → players[2] → ... → players[1],
	                         ignoring the rng (AC-5's control; mutation 2)
	  * `ignoreSeed`        - deal from a fixed internal seed rather than the rng
	                         handed in (AC-3's control)
	  * `swapAccessors`     - supplierOf and dependentOf exchanged (AC-4;
	                         mutation 3)
	  * `lensFromSupplier`  - lensOf reads the supplier's key class, the sign
	                         error the Contract warns about (AC-4)
	  * `anyPermutation`    - σ is a plain shuffle, fixed points allowed (AC-1)
	  * `allowDegenerate`   - no minimum count: a swap at 2, a fixed point at 1
	                         (AC-6)
	  * `mutateInput`       - shuffle the caller's list in place and hand it
	                         back as the seat order (AC-7)
	  * `drawFromParent`    - shuffle with the parent rng instead of
	                         rng:derive("seats") (the Contract's sub-stream pin)
]]
export type Defects = {
	plainDerangement: boolean?,
	constantCanonical: boolean?,
	ignoreSeed: boolean?,
	swapAccessors: boolean?,
	lensFromSupplier: boolean?,
	anyPermutation: boolean?,
	allowDegenerate: boolean?,
	mutateInput: boolean?,
	drawFromParent: boolean?,
}

local FIXED_SEED = 777

-- σ⁻¹(p) read off the assignment, for the accessors.
local function inverse(assignment: any, playerId: string): string?
	for p, q in pairs(assignment.sigma) do
		if q == playerId then
			return p
		end
	end
	return nil
end

local function hasFixedPoint(players: { string }, image: { string }): boolean
	for i, p in players do
		if image[i] == p then
			return true
		end
	end
	return false
end

-- An in-place Fisher-Yates over the caller's own table: the AC-7 defect.
local function shuffleInPlace(list: { string }, rng: Rng.Rng)
	for i = #list, 2, -1 do
		local j = rng:nextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function RingStubs.make(defects: Defects): any
	local ring = {}

	ring.assign = function(players: { string }, rng: Rng.Rng): any
		if not defects.allowDegenerate and #players < 3 then
			error(`RingStubs: {#players} seated, a ring needs at least 3`)
		end

		local stream: Rng.Rng
		if defects.ignoreSeed then
			stream = Rng.fromSeed(FIXED_SEED):derive("seats")
		elseif defects.drawFromParent then
			stream = rng
		else
			stream = rng:derive("seats")
		end

		local sigma: { [string]: string } = {}
		local resultPlayers: { string }

		if defects.plainDerangement then
			-- Rejection sampling: a random permutation, redrawn until it has
			-- no fixed point. Every derangement is equally likely, cycles and
			-- pairs of swaps alike.
			local image = stream:shuffle(players)
			while hasFixedPoint(players, image) do
				image = stream:shuffle(players)
			end
			for i, p in players do
				sigma[p] = image[i]
			end
			resultPlayers = table.clone(players)
		elseif defects.anyPermutation then
			local image = stream:shuffle(players)
			for i, p in players do
				sigma[p] = image[i]
			end
			resultPlayers = table.clone(players)
		else
			local order: { string }
			if defects.constantCanonical then
				order = table.clone(players)
			elseif defects.mutateInput then
				shuffleInPlace(players, stream)
				order = players
			else
				order = stream:shuffle(players)
			end
			for i, p in order do
				sigma[p] = order[if i == #order then 1 else i + 1]
			end
			resultPlayers = if defects.mutateInput then players else table.clone(players)
		end

		local keyClass: { [string]: number } = {}
		for i, p in resultPlayers do
			keyClass[p] = i
		end

		return { players = resultPlayers, sigma = sigma, keyClass = keyClass }
	end

	ring.lensOf = function(assignment: any, playerId: string): number?
		local reads = if defects.lensFromSupplier
			then inverse(assignment, playerId)
			else assignment.sigma[playerId]
		return if reads ~= nil then assignment.keyClass[reads] else nil
	end

	ring.dependentOf = function(assignment: any, playerId: string): string?
		return if defects.swapAccessors
			then inverse(assignment, playerId)
			else assignment.sigma[playerId]
	end

	ring.supplierOf = function(assignment: any, playerId: string): string?
		return if defects.swapAccessors
			then assignment.sigma[playerId]
			else inverse(assignment, playerId)
	end

	return ring
end

-- The baseline: no defects. Every control below is this with one field set.
RingStubs.correct = RingStubs.make({})

RingStubs.plainDerangement = RingStubs.make({ plainDerangement = true })
RingStubs.canonical = RingStubs.make({ constantCanonical = true })
RingStubs.seedIgnoring = RingStubs.make({ ignoreSeed = true })
RingStubs.swappedAccessors = RingStubs.make({ swapAccessors = true })
RingStubs.lensFromSupplier = RingStubs.make({ lensFromSupplier = true })
RingStubs.anyPermutation = RingStubs.make({ anyPermutation = true })
RingStubs.degenerate = RingStubs.make({ allowDegenerate = true })
RingStubs.inPlace = RingStubs.make({ mutateInput = true })
RingStubs.parentDrawing = RingStubs.make({ drawFromParent = true })

return RingStubs
