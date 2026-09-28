--!strict
--[[
	The seating ring, per SEAT-001 and `docs/wiki/game/roles.md` sections 2 and 6:
	a seeded CYCLIC DERANGEMENT of the seated players, dealt as a pure function of
	`(players, rng)`.

	Each player `p` holds a KEY `k(p)` - the class of actuators only `p` may
	operate - and a LENS `λ(p) = k(σ(p))` - the class whose required values only
	`p` can read. `σ` is the whole mechanism, and three properties of it are what
	make the co-operative design work at all:

	  * `σ` HAS NO FIXED POINT. `σ(p) ≠ p`, so nobody can read the values for
	    their own actuators and nobody can act alone.

	  * `σ` IS A SINGLE n-CYCLE, never two shorter ones. A derangement of four
	    players could be two disjoint swaps, and that is two independent
	    two-player games sharing a map rather than one ring of four
	    (`roles.md` section 2). The construction below cannot produce one: linking
	    a shuffled order end to end is a single cycle by shape, not by test.

	  * THE RING'S SHAPE IS ITSELF VARIANCE. All six cyclic derangements of four
	    players are equally likely, so "you do not develop a fixed relationship
	    with one person" (`roles.md` section 2). A generator that always returned
	    the same ring would satisfy every structural property above and quietly
	    remove that, which is why SEAT-001's AC-5 tallies 10,000 seeds.

	THE DIRECTION IS THE THING TO GET RIGHT, and it is the one error the structure
	cannot catch: a backwards ring still has no fixed point, still has one orbit,
	and still gives every player someone to talk to.

	    σ(p)    is p's DEPENDENT - the ring-SUCCESSOR, the one player whose
	            actuators only `p` can see. `p` sends facts TO σ(p).
	    σ⁻¹(p)  is p's SUPPLIER  - the ring-PREDECESSOR, the one player who can
	            see what `p`'s actuators need. `p` receives facts FROM σ⁻¹(p).

	Four players read `P1 → P2 → P3 → P4 → P1`. SEAT-003's key transfer depends on
	this: a leaver's key goes to their SUPPLIER, the player who could already see
	those values.

	WHY `rng:derive("seats")` AND NOT THE RNG ITSELF. `Rng.derive` mixes a fresh
	stream identity from the parent's identity and the label and leaves the
	parent's state untouched (`ROUND-001`), so the seats depend on the round seed
	and on nothing else the caller has drawn. That is what lets M3's instance
	generator draw from `derive("instance")` later without shifting a single seat,
	and it is observable from outside: draws taken from the parent before `assign`
	do not move the ring.

	THE LENS IS STORED, NOT DERIVED (SEAT-003 PO-1). It is DEALT as `k(σ(p))`
	and never recomputed. After a withdrawal closes the ring, `σ(s)` for the
	supplier `s` is the leaver's dependent, so recomputing would hand `s` the
	leaver's lens - exactly what `roles.md` section 6 says is lost.

	WHAT THIS MODULE DOES NOT KNOW. Lens CONTENTS - the `(tag → required value)`
	pairings a lens actually shows - come from the M3 instance generator, so an
	`Assignment` carries `players`, `sigma`, `keyClasses` and `lens` and nothing
	else. It needs no Roblox runtime either: no `Instance`, no service, no clock -
	`rejoin` is handed `now` - nothing but arithmetic over tables.
]]

local Rng = require("@shared/Rng")
local Tuning = require("@shared/Tuning")

local Ring = {}

export type PlayerId = string
export type KeyClass = number -- 1..n, one per seated player

export type Assignment = {
	players: { PlayerId }, -- seat order, as seated
	sigma: { [PlayerId]: PlayerId }, -- σ: p -> p's dependent, the ring-successor
	-- A list, because a supplier inherits a leaver's class (SEAT-003) and one
	-- field says which classes a player may operate, not two.
	keyClasses: { [PlayerId]: { KeyClass } },
	lens: { [PlayerId]: KeyClass }, -- λ(p), dealt as k(σ(p)) and never recomputed
}

-- What the driver keeps while a player is away: the ring as it stood before
-- the withdrawal, so a rejoin inside the window can put it back exactly.
export type Absence = {
	playerId: PlayerId,
	leftAt: number,
	graceSeconds: number,
	snapshot: Assignment,
}

-- The sub-stream label. Any label isolates the seats from the parent's draws;
-- this one is the Contract's, and naming it once keeps a future
-- `derive("instance")` from colliding with it by accident.
local SEATS_LABEL = "seats"

--[[
	The minimum seated count, READ from ROUND-002's module rather than written
	here. `min_players_to_continue` is 3 because "below 3 there is no derangement
	worth the name" (`tuning.md` section 1, derived): at n = 2 the only
	derangement is a swap - two players each seeing the other's values - which is
	not a ring. A literal 3 in this file would be a second place for that
	constant to live, and `RoundConfig.luau` declines the same temptation for the
	same reason. It is read at load, not injected, because `assign`'s signature
	takes `(players, rng)` and nothing else.
]]
local MINIMUM_SEATED = Tuning.session.min_players_to_continue

--[[
	Deal the ring.

	The construction is shuffle-then-link: put the players in a random order and
	map each to the next, wrapping the last back to the first. Every single cycle
	is produced by exactly `(n-1)!` of the `n!` orderings, so an unbiased shuffle
	makes every cyclic derangement equally likely - which is what AC-5's
	distribution rests on. `Rng:shuffle` is a textbook Fisher-Yates and returns a
	new list, so the caller's `players` is never touched.

	It RAISES below the minimum rather than returning something. Every degenerate
	result - a swap at n = 2, a fixed point at n = 1, an empty ring at n = 0 - is
	a table that LOOKS like an `Assignment`, so returning one would move the
	failure somewhere later and harder to read. `Rng.nextInteger` refuses an empty
	range in the same codebase for the same reason. Level 2 attributes the error
	to the caller, which is the code that chose to seat too few.
]]
function Ring.assign(players: { PlayerId }, rng: Rng.Rng): Assignment
	if #players < MINIMUM_SEATED then
		error(
			`Ring.assign: {#players} seated player(s), but a ring needs at least `
				.. `{MINIMUM_SEATED} (min_players_to_continue)`,
			2
		)
	end

	local order = rng:derive(SEATS_LABEL):shuffle(players)

	local sigma: { [PlayerId]: PlayerId } = {}
	for i, p in order do
		-- The wrap is what makes this one cycle rather than a chain: the last
		-- player in the shuffled order points back at the first.
		sigma[p] = order[(i % #order) + 1]
	end

	--[[
		Key classes follow the SEAT order, not the ring order, and the choice is
		deliberate rather than arbitrary. `tuning.md` section 2 specifies only
		"one class per player", so any bijection onto 1..n satisfies AC-4; dealing
		them by seat keeps the rng's single decision the RING and nothing else, so
		a player's own key class says nothing about where they sit in it.
	]]
	local keyClasses: { [PlayerId]: { KeyClass } } = {}
	for i, p in players do
		keyClasses[p] = { i }
	end

	-- `λ(p) = k(σ(p))`: the lens reads the DEPENDENT's key class - the values
	-- `p` can see are the ones `p`'s successor needs - and never the supplier's.
	-- Dealt once, here, while every player still holds exactly one class.
	local lens: { [PlayerId]: KeyClass } = {}
	for _, p in players do
		lens[p] = keyClasses[sigma[p]][1]
	end

	return {
		-- A clone, so that a later caller mutating its own seat list cannot
		-- reach inside an assignment that was already dealt.
		players = table.clone(players),
		sigma = sigma,
		keyClasses = keyClasses,
		lens = lens,
	}
end

-- The stored lens. Not `k(σ(p))`: after a withdrawal that formula names the
-- leaver's lost lens for the supplier (PO-1).
function Ring.lensOf(assignment: Assignment, playerId: PlayerId): KeyClass
	return assignment.lens[playerId]
end

-- `σ(p)`: the ring-successor, the player `p` sends facts to.
function Ring.dependentOf(assignment: Assignment, playerId: PlayerId): PlayerId
	return assignment.sigma[playerId]
end

--[[
	`σ⁻¹(p)`: the ring-predecessor, the player `p` receives facts from.

	Searched rather than stored, because a second table on the `Assignment` would
	be a second copy of σ that could disagree with the first - and the Contract
	names four fields. The scan is over `players` (bounded by the seated count,
	at most 6) rather than over `sigma`, so the answer does not depend on hash
	order and a stray key in σ cannot become one.
]]
function Ring.supplierOf(assignment: Assignment, playerId: PlayerId): PlayerId
	for _, candidate in assignment.players do
		if assignment.sigma[candidate] == playerId then
			return candidate
		end
	end

	-- Unreachable for an assignment this module dealt: σ is onto the seated
	-- players, so every seated player has a predecessor. Raising says the
	-- argument was not seated, rather than handing back a nil that would be
	-- mistaken for a player somewhere downstream.
	error(`Ring.supplierOf: {tostring(playerId)} has no supplier - is that player seated?`, 2)
end

--[[
	A copy of `assignment` that shares no table with it, leaving out `omit`.

	Fresh at EVERY level, the lists of untouched players included: a result
	that reused an argument's list would let the next withdrawal's append
	rewrite `Absence.snapshot` in place, which is PO-3's defect one step later.
	Every map is walked through `players`, as `supplierOf` walks it, so a stray
	key cannot be carried across, and every list is appended to rather than
	cloned: this file's single `table.clone` is SEAT-001's, and SEAT-002's
	on-disk guard control counts it.
]]
local function copyWithout(assignment: Assignment, omit: PlayerId?): Assignment
	local players: { PlayerId } = {}
	local sigma: { [PlayerId]: PlayerId } = {}
	local keyClasses: { [PlayerId]: { KeyClass } } = {}
	local lens: { [PlayerId]: KeyClass } = {}

	for _, p in assignment.players do
		if p ~= omit then
			table.insert(players, p)
			sigma[p] = assignment.sigma[p]
			lens[p] = assignment.lens[p]
			local classes: { KeyClass } = {}
			for _, class in assignment.keyClasses[p] do
				table.insert(classes, class)
			end
			keyClasses[p] = classes
		end
	end

	return { players = players, sigma = sigma, keyClasses = keyClasses, lens = lens }
end

--[[
	`q` leaves: the ring closes around them and their key goes to their SUPPLIER
	(`roles.md` section 6).

	The supplier `s = σ⁻¹(q)` is the one player who could already see the
	values `q`'s actuators need, so handing them `q`'s class keeps the instance
	solvable. The dependent `σ(q)` is the natural wrong answer and the structure
	cannot tell: the ring closes the same way either way. Both are read from the
	ring AS PASSED, never from any earlier one - after a first withdrawal the
	suppliers have moved (AC-7).

	What this deliberately does NOT repair:

	  * `q`'s LENS IS LOST. Its entry is removed and nobody's lens is
	    recomputed, so `s` keeps `k(q)` - a class `s` now holds. `s` is the one
	    player who can act on what their own lens shows: the derangement is
	    broken for exactly one player, on purpose (AC-3). A dropout should hurt.
	  * The round's fate. A 3 → 2 withdrawal still returns a well-formed ring;
	    quorum is ROUND-005's decision, in one place (AC-8).

	PURE (PO-3): the caller keeps the argument as `Absence.snapshot`, so it is
	never written to. The supplier is found by its own scan rather than through
	`supplierOf`, so an unseated `q` is blamed on THIS function's caller.
]]
function Ring.withdraw(assignment: Assignment, playerId: PlayerId): Assignment
	local supplier: PlayerId? = nil
	for _, candidate in assignment.players do
		if assignment.sigma[candidate] == playerId then
			supplier = candidate
			break
		end
	end
	if supplier == nil then
		error(`Ring.withdraw: {tostring(playerId)} is not seated in this assignment`, 2)
	end

	local result = copyWithout(assignment, playerId)
	result.sigma[supplier] = assignment.sigma[playerId]
	-- The supplier's own classes first, then all of the leaver's, in order.
	for _, class in assignment.keyClasses[playerId] do
		table.insert(result.keyClasses[supplier], class)
	end
	return result
end

--[[
	A rejoin: the original seat back, or nothing.

	Too late is INCLUSIVE - `now - leftAt >= graceSeconds` - matching the phase
	machine's boundary convention; after it "the seat is gone and the player
	spectates until the next round" (`roles.md` section 6). Inside the window
	the answer is the pre-withdrawal ring (PO-4), as a deep copy so the driver
	that owns the `Absence` is not reachable through the ring it hands out.

	`now` is passed in; nothing here reads a clock. The current ring is not
	consulted: composing a rejoin with a second, intervening withdrawal is out
	of this story's scope, and the parameter is kept so that decision has a
	place to land without changing the signature.
]]
function Ring.rejoin(_assignment: Assignment, absence: Absence, now: number): Assignment?
	if now - absence.leftAt >= absence.graceSeconds then
		return nil
	end
	return copyWithout(absence.snapshot, nil)
end

return Ring
