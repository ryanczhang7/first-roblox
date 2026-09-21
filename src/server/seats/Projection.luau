--!strict
--[[
	SEAT-002: what a client is allowed to know about the seating ring.

	THE PROJECTION IS AN ALLOWLIST, BUILT FIELD BY FIELD (`architecture.md` §4,
	D8). It is never a copy of the `Assignment` with the private parts removed,
	and the reason is that the two failure modes are not symmetric:

	  * a denylist that forgets a field leaks the round, silently, to any
	    exploiter who bothers to read what was replicated to them;
	  * an allowlist that forgets a field produces a visibly missing feature
	    within a minute of anyone playing.

	`roles.md` §6: "a client that can read another player's lens is not cheating
	at a scoreboard, it has deleted the game." A Roblox client is fully hostile
	and can read every value replicated to it, so "the UI does not show it" is
	worth nothing. The only mechanism that works is never sending it, and the
	only way to never send it is to name what IS sent.

	WHAT `p` IS TOLD, and why each field is safe (`roles.md` §3):

	  playerId     who this view is for.
	  keyClass     `k(p)`, p's own key class. Public: `roles.md` §3 puts actuator
	               key classes in the column "shared with anyone in the room".
	  lensClass    `λ(p) = k(σ(p))`, the class p's lens reads. Safe because p
	               sees those values anyway by pointing their light at the panels
	               (`mechanics.md` §2). It says nothing about what ANYONE ELSE
	               can see, which is the ignorance the game is made of
	               (`mechanics.md` §4.5).
	  supplierId   who tells p what p's actuators need.
	  dependentId  who p must tell. Both neighbours are necessary: `roles.md` §3
	               makes "get your dependent right" and "get yourself told" the
	               player's local obligations, and neither is actionable without
	               a name.
	  seatOrder    who is in the round. Public by construction.

	WHAT IS NEVER SENT: `σ` in any form, and anyone else's key class. `σ` is the
	whole puzzle - a client holding it can compute every lens in the room - and
	that includes σ written out as an ORDER, which is why `seatOrder` is the SEAT
	order and not the ring walked from p.

	WHAT M3 ADDS, and where: `pairings` (this player's lens contents) and
	`fragments` (this player's order fragments), both per-player secrets, both
	added to the list below BY NAME. Nothing else about this module changes -
	that is the whole reason this is built now, while the only secret is σ.

	THE RING RELATIONS COME FROM `Ring`, never from a private σ⁻¹ here. `Ring`'s
	own header says direction is the one error the ring's structure cannot catch:
	a backwards ring still has no fixed point and still has one orbit. A second
	implementation of σ⁻¹ in this file would be a second answer to that question,
	free to disagree with the first and impossible to test apart from it.
]]

local Ring = require("./Ring")

local Projection = {}

--[[
	THE ALLOWLIST IS THE TYPE. Every field here is written into the result by an
	explicit assignment in `forPlayer`; there is no path from an `Assignment` to
	a `PublicSeatView` that does not pass through one.
]]
export type PublicSeatView = {
	playerId: Ring.PlayerId,
	keyClass: Ring.KeyClass, -- k(p): this player's own class
	lensClass: Ring.KeyClass, -- λ(p) = k(σ(p)): the class this player's lens reads
	supplierId: Ring.PlayerId, -- σ⁻¹(p): who tells me
	dependentId: Ring.PlayerId, -- σ(p): who I tell
	seatOrder: { Ring.PlayerId }, -- public: who is in the round, in SEAT order
}

--[[
	Is `playerId` seated in this assignment?

	A scan over `players` rather than a lookup in `keyClass`, for the same reason
	`Ring.supplierOf` scans it: `players` is the seated list, and a stray key in
	one of the maps must not be able to become a player. Written as a loop rather
	than `table.find` so that a `nil` id - which is one of the strangers AC-5
	asks about - is answered rather than raising somebody else's argument error.
]]
local function isSeated(assignment: Ring.Assignment, playerId: Ring.PlayerId): boolean
	for _, candidate in assignment.players do
		if candidate == playerId then
			return true
		end
	end
	return false
end

--[[
	`p`'s view, and nothing else.

	THE REFUSAL IS THIS MODULE'S OWN, AND IT COMES FIRST (SEAT-002 PO-3).
	`Ring.supplierOf` also raises for an unseated player, so a `forPlayer` that
	simply fell through to it would still fail for a stranger - but the message
	would name the wrong module and the refusal would be a side effect of a
	helper rather than a decision this function made. An empty or partial view is
	worse than either: it is indistinguishable from a legitimate view of a player
	with nothing, so a spectator quietly receiving one is a bug that hides.

	Level 2 attributes the error to the caller, which is the code that asked for
	a stranger's view.

	`seatOrder` IS BUILT BY AN EXPLICIT LOOP (SEAT-002 PO-2), never by a
	table-copy helper. Handing out `assignment.players` itself would let a
	consumer mutate a ring that was already dealt - `Ring.assign` clones the
	caller's list precisely to prevent that - and cloning it here would be
	behaviourally identical but unguardable: AC-4's structural guard is a FLAT
	ban on copy helpers anywhere in this file, with no argument analysis, and it
	is worth having only because this module has no legitimate use for one. A
	guard that must parse a call's arguments to decide whether that call is
	allowed fails open on the first argument it cannot parse.

	The loop appends rather than assigning by index, which is not a style
	preference: selene's `manual_table_clone` fires on the indexed form and its
	suggested fix is `table.clone(players)` - the one construct AC-4 exists to
	forbid (SEAT-002 PO-7). Following the linter's advice here writes the leak.
]]
function Projection.forPlayer(assignment: Ring.Assignment, playerId: Ring.PlayerId): PublicSeatView
	if not isSeated(assignment, playerId) then
		error(`Projection.forPlayer: {tostring(playerId)} is not seated in this assignment`, 2)
	end

	local seatOrder: { Ring.PlayerId } = {}
	for _, seated in assignment.players do
		table.insert(seatOrder, seated)
	end

	return {
		playerId = playerId,
		keyClass = assignment.keyClass[playerId],
		lensClass = Ring.lensOf(assignment, playerId),
		supplierId = Ring.supplierOf(assignment, playerId),
		dependentId = Ring.dependentOf(assignment, playerId),
		seatOrder = seatOrder,
	}
end

return Projection
