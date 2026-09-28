--!strict
--[[
	The wrong seat generators SEAT-001's controls are aimed at, the wrong
	withdrawals and rejoins SEAT-003's controls are aimed at, and the one
	baseline each of them is a single defect away from.

	THREE SEAT-001 CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-2: "a
	generator that produces a random derangement without the cycle constraint
	passes AC-1 and must fail this at n = 4". AC-3: "a generator that ignores
	its seed passes the first half and must fail the second". AC-5: "a generator
	that always returns the canonical cycle p1 → p2 → p3 → p4 → p1 satisfies
	AC-1, AC-2 and the first half of AC-3, and must fail this - scoring 100% on
	one ring and 0% on five". A criterion that names an implementation needs an
	implementation to point at, so the generators below really do deal seats.

	TWO SEAT-003 CRITERIA NAME THEIRS. AC-1: "an implementation transferring to
	σ(q), the dependent, must fail this. It passes every test that only asserts
	'somebody has the class'". AC-7: "an implementation computing suppliers
	against the ORIGINAL ring passes the single-withdrawal cases and must fail
	this". The rest are the mutations the story's `## Notes` asks the
	orchestrator to run at acceptance and the one-defect implementations the
	remaining criteria and the Contract's pins would otherwise have no control
	for - including BOTH places PO-1's trap can live: the stored `lens` field
	recomputed as k(σ(p)) after the ring closes, and a `lensOf` that computes
	k(σ(p)) instead of reading the field.

	It is a FACTORY over a table of defects, as `RoundEndingStubs.luau` is, so
	that `defects` is empty for the baseline and has exactly ONE field set for
	every control: a control that fires is then attributable to that one field.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/server/seats/Ring.luau`
	and not a sketch of one. The baseline is the Contract's construction only as
	far as the checks can see - it has no types beyond `any`, its key-class
	choice (seat index) is one of several the Contract allows, and its error
	messages are whatever fell out. GREEN writes the module from the story's
	Contract, against the failing tests in `tests/server/ring_test.luau`;
	nothing here is to be copied.

	NOTHING HERE REQUIRES PRODUCTION CODE - `src/shared/Rng.luau` is ROUND-001's,
	merged and frozen, and `Deep` is a test helper - so these controls are
	EXECUTED in RED, and `tests/server/ring_controls_test.luau` records what
	each one actually did.
]]

local Deep = require("./Deep")
local Rng = require("../../src/shared/Rng")

local RingStubs = {}

--[[
	One field per control, each a single edit to the generator below.

	SEAT-001 (assign and the accessors):

	  * `plainDerangement` - rejection-sample a derangement with no cycle
	                         constraint (AC-2's control; mutation 1 of `## Notes`)
	  * `constantCanonical` - always players[1] → players[2] → ... → players[1],
	                         ignoring the rng (AC-5's control; mutation 2)
	  * `ignoreSeed`        - deal from a fixed internal seed rather than the rng
	                         handed in (AC-3's control)
	  * `swapAccessors`     - supplierOf and dependentOf exchanged (AC-4;
	                         mutation 3)
	  * `lensFromSupplier`  - the lens is dealt as the supplier's key class, the
	                         sign error the Contract warns about (AC-4)
	  * `anyPermutation`    - σ is a plain shuffle, fixed points allowed (AC-1)
	  * `allowDegenerate`   - no minimum count: a swap at 2, a fixed point at 1
	                         (AC-6)
	  * `mutateInput`       - shuffle the caller's list in place and hand it
	                         back as the seat order (AC-7)
	  * `drawFromParent`    - shuffle with the parent rng instead of
	                         rng:derive("seats") (the Contract's sub-stream pin)

	SEAT-003 (withdraw, rejoin, and the stored lens):

	  * `lensOfDerives`         - lensOf computes k(σ(p)) instead of reading the
	                              stored `lens` (PO-1's trap, in the accessor)
	  * `transferToDependent`   - the leaver's classes go to σ(q), the dependent
	                              (AC-1's control; mutation 1 of `## Notes`)
	  * `dropLeaversClasses`    - the leaver's classes go to nobody (the control
	                              for the naive "somebody holds it" check)
	  * `supplierFromOriginal`  - the receiver is σ⁻¹(q) in the ring AS DEALT,
	                              not as passed (AC-7's control; mutation 2)
	  * `deriveLensAfterClose`  - every lens recomputed as k(σ(p)) after the
	                              ring closes (PO-1's trap, in the field; AC-4)
	  * `sortRemainingSeats`    - the remaining players re-seated alphabetically
	                              (AC-2, the seat-order half)
	  * `closeOneStepTooFar`    - σ(s) = σ(d) instead of d: the ring closes past
	                              the dependent (AC-2, the σ half)
	  * `mutateArgument`        - withdraw edits the assignment in place and
	                              returns it (PO-3)
	  * `shareSubTables`        - a fresh top-level table whose untouched lists
	                              are the argument's own (PO-3, aliasing)
	  * `leaverClassesFirst`    - the supplier's list is the leaver's classes
	                              followed by their own (the list-order pin)
	  * `ignoreUnseated`        - withdraw of a stranger returns a copy instead
	                              of raising (the Contract's raise pin)
	  * `graceExclusive`        - `now - leftAt > graceSeconds` instead of `>=`
	                              (AC-6's control; mutation 3)
	  * `rejoinAlwaysNil`       - rejoin never restores (AC-5)
	  * `rejoinReturnsSnapshot` - rejoin hands back absence.snapshot itself
	                              rather than a deep copy (PO-4, aliasing)
	  * `rejoinMutatesArgument` - rejoin re-seats the player into the
	                              assignment it was passed (PO-4)
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

	lensOfDerives: boolean?,
	transferToDependent: boolean?,
	dropLeaversClasses: boolean?,
	supplierFromOriginal: boolean?,
	deriveLensAfterClose: boolean?,
	sortRemainingSeats: boolean?,
	closeOneStepTooFar: boolean?,
	mutateArgument: boolean?,
	shareSubTables: boolean?,
	leaverClassesFirst: boolean?,
	ignoreUnseated: boolean?,
	graceExclusive: boolean?,
	rejoinAlwaysNil: boolean?,
	rejoinReturnsSnapshot: boolean?,
	rejoinMutatesArgument: boolean?,
}

local FIXED_SEED = 777

-- σ⁻¹(p) read off a σ table, for the accessors and the transfer.
local function inverseIn(sigma: { [string]: string }, playerId: string): string?
	for p, q in pairs(sigma) do
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

local function isSeated(players: { string }, id: any): boolean
	for _, p in players do
		if p == id then
			return true
		end
	end
	return false
end

-- Replace the contents of `target` with the contents of `source`, in place.
-- The mutating defects use it so that the argument's own tables change.
local function overwrite(target: { [any]: any }, source: { [any]: any })
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(source) do
		target[key] = value
	end
end

function RingStubs.make(defects: Defects): any
	local ring = {}

	--[[
		The σ each assignment was DEALT with, keyed by the assignment table, so
		that the `supplierFromOriginal` defect has an "original ring" to consult.
		A withdrawal's result inherits its argument's origin, which is exactly
		the bug: after two withdrawals the second leaver's original supplier may
		no longer be seated. Weak keys, so the side table holds nothing alive.
	]]
	local origins: { [any]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any

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

		-- One class per player, by seat index, as a one-element list.
		local keyClasses: { [string]: { number } } = {}
		for i, p in resultPlayers do
			keyClasses[p] = { i }
		end

		-- λ(p) = k(σ(p)), STORED at deal time (PO-1). The sign-error defect
		-- deals it from the supplier instead.
		local lens: { [string]: number } = {}
		for _, p in resultPlayers do
			local reads = if defects.lensFromSupplier then inverseIn(sigma, p) else sigma[p]
			if reads ~= nil and keyClasses[reads] ~= nil then
				lens[p] = keyClasses[reads][1]
			end
		end

		local assignment =
			{ players = resultPlayers, sigma = sigma, keyClasses = keyClasses, lens = lens }
		origins[assignment] = sigma
		return assignment
	end

	ring.lensOf = function(assignment: any, playerId: string): number?
		if defects.lensOfDerives then
			local dependent = assignment.sigma[playerId]
			local held = if dependent ~= nil then assignment.keyClasses[dependent] else nil
			return if held ~= nil then held[1] else nil
		end
		return assignment.lens[playerId]
	end

	ring.dependentOf = function(assignment: any, playerId: string): string?
		return if defects.swapAccessors
			then inverseIn(assignment.sigma, playerId)
			else assignment.sigma[playerId]
	end

	ring.supplierOf = function(assignment: any, playerId: string): string?
		return if defects.swapAccessors
			then assignment.sigma[playerId]
			else inverseIn(assignment.sigma, playerId)
	end

	--[[
		The withdrawal, per the Contract: `s = σ⁻¹(q)`, `d = σ(q)`, q leaves the
		seats, `σ(s) = d`, s's list becomes own-then-q's, q's lens entry goes.
	]]
	ring.withdraw = function(assignment: any, leaver: any): any
		if not isSeated(assignment.players, leaver) then
			if defects.ignoreUnseated then
				return Deep.copy(assignment)
			end
			error(`RingStubs.withdraw: {tostring(leaver)} is not seated in this assignment`, 2)
		end

		local supplier = inverseIn(assignment.sigma, leaver) :: string
		local dependent = assignment.sigma[leaver] :: string

		-- THE RECEIVER. The Contract's answer is the supplier in the ring AS
		-- PASSED. The two named controls differ here and nowhere else.
		local receiver: string
		if defects.transferToDependent then
			receiver = dependent
		elseif defects.supplierFromOriginal then
			local original = origins[assignment] or assignment.sigma
			receiver = inverseIn(original, leaver) :: string
		else
			receiver = supplier
		end

		local players: { string } = {}
		for _, p in assignment.players do
			if p ~= leaver then
				table.insert(players, p)
			end
		end
		if defects.sortRemainingSeats then
			table.sort(players)
		end

		local sigma: { [string]: string } = {}
		for p, q in pairs(assignment.sigma) do
			if p ~= leaver then
				sigma[p] = q
			end
		end
		sigma[supplier] = if defects.closeOneStepTooFar
			then assignment.sigma[dependent]
			else dependent

		local keyClasses: { [string]: { number } } = {}
		for p, held in pairs(assignment.keyClasses) do
			if p ~= leaver then
				keyClasses[p] = if defects.shareSubTables then held else table.clone(held)
			end
		end
		if not defects.dropLeaversClasses then
			local own = keyClasses[receiver] or {}
			local merged: { number } = {}
			local first = if defects.leaverClassesFirst then assignment.keyClasses[leaver] else own
			local second = if defects.leaverClassesFirst then own else assignment.keyClasses[leaver]
			for _, class in first do
				table.insert(merged, class)
			end
			for _, class in second do
				table.insert(merged, class)
			end
			keyClasses[receiver] = merged
		end

		local lens: { [string]: number } = {}
		for p, class in pairs(assignment.lens) do
			if p ~= leaver then
				lens[p] = class
			end
		end
		if defects.deriveLensAfterClose then
			for _, p in players do
				local held = keyClasses[sigma[p]]
				lens[p] = if held ~= nil then held[1] else nil
			end
		end

		if defects.mutateArgument then
			overwrite(assignment.players, players)
			overwrite(assignment.sigma, sigma)
			overwrite(assignment.keyClasses, keyClasses)
			overwrite(assignment.lens, lens)
			return assignment
		end

		local result = { players = players, sigma = sigma, keyClasses = keyClasses, lens = lens }
		origins[result] = origins[assignment] or assignment.sigma
		return result
	end

	ring.rejoin = function(assignment: any, absence: any, now: number): any
		local elapsed = now - absence.leftAt
		local late = if defects.graceExclusive
			then elapsed > absence.graceSeconds
			else elapsed >= absence.graceSeconds
		if late or defects.rejoinAlwaysNil then
			return nil
		end
		if defects.rejoinReturnsSnapshot then
			return absence.snapshot
		end
		if defects.rejoinMutatesArgument then
			overwrite(assignment.players, absence.snapshot.players)
			overwrite(assignment.sigma, absence.snapshot.sigma)
			overwrite(assignment.keyClasses, Deep.copy(absence.snapshot.keyClasses))
			overwrite(assignment.lens, absence.snapshot.lens)
			return assignment
		end
		local restored = Deep.copy(absence.snapshot)
		origins[restored] = origins[absence.snapshot] or absence.snapshot.sigma
		return restored
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

RingStubs.lensOfDerives = RingStubs.make({ lensOfDerives = true })
RingStubs.transferToDependent = RingStubs.make({ transferToDependent = true })
RingStubs.dropLeaversClasses = RingStubs.make({ dropLeaversClasses = true })
RingStubs.supplierFromOriginal = RingStubs.make({ supplierFromOriginal = true })
RingStubs.deriveLensAfterClose = RingStubs.make({ deriveLensAfterClose = true })
RingStubs.sortRemainingSeats = RingStubs.make({ sortRemainingSeats = true })
RingStubs.closeOneStepTooFar = RingStubs.make({ closeOneStepTooFar = true })
RingStubs.mutateArgument = RingStubs.make({ mutateArgument = true })
RingStubs.shareSubTables = RingStubs.make({ shareSubTables = true })
RingStubs.leaverClassesFirst = RingStubs.make({ leaverClassesFirst = true })
RingStubs.ignoreUnseated = RingStubs.make({ ignoreUnseated = true })
RingStubs.graceExclusive = RingStubs.make({ graceExclusive = true })
RingStubs.rejoinAlwaysNil = RingStubs.make({ rejoinAlwaysNil = true })
RingStubs.rejoinReturnsSnapshot = RingStubs.make({ rejoinReturnsSnapshot = true })
RingStubs.rejoinMutatesArgument = RingStubs.make({ rejoinMutatesArgument = true })

return RingStubs
