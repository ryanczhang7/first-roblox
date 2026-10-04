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
	  keyClasses   p's own key classes - one when dealt, two for a supplier who
	               inherited a leaver's (SEAT-003). Public: `roles.md` §3 puts
	               actuator key classes in the column "shared with anyone in the
	               room". p's OWN list, never anyone else's, never the list itself.
	  lensClass    `λ(p)`, the class p's lens reads, as `Ring` stores it (dealt as
	               `k(σ(p))`, never recomputed). Safe because p
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

	WHAT M3 ADDS, and where: not wider fields on this view but views of their
	own beside it (`architecture.md` D16), each an allowlist built BY NAME.
	`lensFor` (VIEW-001) is this player's lens view - the required settings p's
	lens may read from where p stands (D14). `turnCuesFor` (VIEW-002) is p's
	turn cues - which of p's own machines is live and which is next.
	`PublicSeatView` does not change - that is the whole reason it was built
	while the only secret was σ.

	WHAT `p`'s LENS VIEW HOLDS, and why each field is safe (`roles.md` §6:
	"only for the machine they are reading"):

	  readings     one entry per machine p is reading NOW: of p's lens class
	               (`Ring.lensOf`), within `lens_read_range_studs` horizontally
	               of p's accepted position, in a lit room, not committed, and
	               in line of sight. Ascending by machine id, built fresh.
	  machineId    which machine. Public: every machine is in the layout.
	  setting      its required setting. The secret itself, and safe only
	               because every clause above is the server's: a client holding
	               it was able to read it by standing there with its light up.

	WHAT IS NEVER SENT on the lens view: any machine outside those five clauses,
	and no room, class, tag or player - the client has those from public state,
	and each would be a second copy of a fact to keep consistent. Light
	DIRECTION is not a clause here: it is presentation (D14, `components.md`
	C-01, C-02), drawn by the client over readings the server already allowed.

	WHAT `p`'s TURN CUES HOLD, and why each field is safe (`mechanics.md` §3.2,
	G12):

	  live         p's machines that `Procedure.isLive` says are live now - one
	               per track at most. Safe because p would find out by turning
	               it: a live step is the one the facility accepts.
	  next         p's uncommitted, not-live step machines whose position among
	               their track's uncommitted steps is at most
	               `turn_cue_lookahead`. Safe because the window is a design
	               constant: it tells p to get ready, not where p stands.
	               Both lists are machine ids only, ascending, built fresh.

	WHAT IS NEVER SENT on the turn cues: no step index, no track, no position,
	no order, and nobody else's cues (`roles.md` §6). Nobody sees the whole
	order - anti-quarterback device 4 (`loop.md` §1.7) - and ascending ids
	rather than track order keep even the shape of the lists from saying it.
	The arrow and its tag are the client's, from public facility data.

	THE RING RELATIONS COME FROM `Ring`, never from a private σ⁻¹ here. `Ring`'s
	own header says direction is the one error the ring's structure cannot catch:
	a backwards ring still has no fixed point and still has one orbit. A second
	implementation of σ⁻¹ in this file would be a second answer to that question,
	free to disagree with the first and impossible to test apart from it.
]]

local Machines = require("../facility/Machines")
local Procedure = require("../procedure/Procedure")
local Ring = require("./Ring")

local Projection = {}

--[[
	THE ALLOWLIST IS THE TYPE. Every field here is written into the result by an
	explicit assignment in `forPlayer`; there is no path from an `Assignment` to
	a `PublicSeatView` that does not pass through one.
]]
export type PublicSeatView = {
	playerId: Ring.PlayerId,
	keyClasses: { Ring.KeyClass }, -- this player's own classes, a fresh list
	lensClass: Ring.KeyClass, -- λ(p): the class this player's lens reads
	supplierId: Ring.PlayerId, -- σ⁻¹(p): who tells me
	dependentId: Ring.PlayerId, -- σ(p): who I tell
	seatOrder: { Ring.PlayerId }, -- public: who is in the round, in SEAT order
}

--[[
	Is `playerId` seated in this assignment?

	A scan over `players` rather than a lookup in `keyClasses`, for the same reason
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

	`keyClasses` IS BUILT THE SAME WAY, for the same reasons (SEAT-003). Handing
	out `assignment.keyClasses[playerId]` would give a client-bound view a
	handle on the dealt ring's own list.
]]
function Projection.forPlayer(assignment: Ring.Assignment, playerId: Ring.PlayerId): PublicSeatView
	if not isSeated(assignment, playerId) then
		error(`Projection.forPlayer: {tostring(playerId)} is not seated in this assignment`, 2)
	end

	local seatOrder: { Ring.PlayerId } = {}
	for _, seated in assignment.players do
		table.insert(seatOrder, seated)
	end

	local keyClasses: { Ring.KeyClass } = {}
	for _, class in assignment.keyClasses[playerId] do
		table.insert(keyClasses, class)
	end

	return {
		playerId = playerId,
		keyClasses = keyClasses,
		lensClass = Ring.lensOf(assignment, playerId),
		supplierId = Ring.supplierOf(assignment, playerId),
		dependentId = Ring.dependentOf(assignment, playerId),
		seatOrder = seatOrder,
	}
end

--[[
	THE LENS VIEW'S ALLOWLIST IS ITS TYPE, as `PublicSeatView`'s is (D16). A
	reading carries exactly `machineId` and `setting`; the view carries exactly
	`readings`.
]]
export type LensReading = { machineId: number, setting: number }
export type LensView = { readings: { LensReading } } -- ascending by machineId

--[[
	`p`'s lens view from `position` (VIEW-001).

	Every machine is a candidate, decoys included. The four cheap clauses are
	asked first and `lineOfSight` LAST, at most once per machine: in a real place
	it is a raycast. The class is `Ring.lensOf` - the stored lens, never the
	player's own key, which is the direction error the ring cannot catch. The
	range and the dark check come from `Machines` and `Procedure` rather than a
	second implementation here, and every constant is read from
	`procedure.tuning` (P-1). Range is horizontal and inclusive, as P-4's
	`within` is, with the lens constant.

	Each reading is built literally, field by field; no machine record is ever
	copied, so a field added to `Machine` later cannot ride along.
]]
function Projection.lensFor(
	assignment: Ring.Assignment,
	procedure: Procedure.ProcedureState,
	playerId: Ring.PlayerId,
	position: Procedure.Vec?,
	lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean
): LensView
	local readings: { LensReading } = {}
	if position == nil then
		return { readings = readings }
	end

	local lensClass = Ring.lensOf(assignment, playerId)
	local range = procedure.tuning.instance.lens_read_range_studs
	local layout = procedure.facility.layout

	for _, machine in procedure.facility.placement.machines do
		if
			machine.keyClass == lensClass
			and procedure.committed[machine.id] ~= true
			and not Procedure.isDark(procedure, machine.room)
		then
			local at = Machines.positionOf(layout, machine, procedure.tuning)
			local dx = position.x - at.x
			local dz = position.z - at.z
			if math.sqrt(dx * dx + dz * dz) <= range and lineOfSight(position, at) then
				table.insert(
					readings,
					{ machineId = machine.id, setting = machine.requiredSetting }
				)
			end
		end
	end

	table.sort(readings, function(a: LensReading, b: LensReading): boolean
		return a.machineId < b.machineId
	end)
	return { readings = readings }
end

--[[
	THE TURN CUES' ALLOWLIST IS ITS TYPE (D16): exactly `live` and `next`, each a
	list of machine ids, ascending. The key is spelled `["next"]` because
	SEAT-002's flat ban scans this file for the bare word (VIEW-002 PO-2); the
	key is still `next`.
]]
export type TurnCues = { live: { number }, ["next"]: { number } }

--[[
	`p`'s turn cues (VIEW-002).

	OWNERSHIP IS THE KEY, NOT THE LENS: a step is p's when its machine's class is
	in `assignment.keyClasses[playerId]` - the list, so a class inherited through
	`Ring.withdraw` counts. `Ring.lensOf` is the class p READS, not the one p
	turns, and using it here would be the direction error again (D-1).

	LIVENESS IS `Procedure`'s, never re-derived from position: that is what keeps
	a finale step at position 0 waiting until both tracks' ordinary steps are
	done, and an armed finale machine live (D-3).

	POSITION is the step's index among its track's uncommitted steps, from 0,
	counted from `procedure.committed` on every call and never stored. The
	window is inclusive and read from `procedure.tuning` (P-1). Decoys are in no
	track and so are never walked.
]]
function Projection.turnCuesFor(
	assignment: Ring.Assignment,
	procedure: Procedure.ProcedureState,
	playerId: Ring.PlayerId
): TurnCues
	local owned = assignment.keyClasses[playerId] or {}
	local lookahead = procedure.tuning.instance.turn_cue_lookahead

	local classOf: { [number]: number } = {}
	for _, machine in procedure.facility.placement.machines do
		classOf[machine.id] = machine.keyClass
	end

	local live: { number } = {}
	local upcoming: { number } = {}
	for _, track in procedure.facility.steps.tracks do
		local position = 0
		for _, id in track do
			if procedure.committed[id] ~= true then
				if table.find(owned, classOf[id]) ~= nil then
					if Procedure.isLive(procedure, id) then
						table.insert(live, id)
					elseif position <= lookahead then
						table.insert(upcoming, id)
					end
				end
				position += 1
			end
		end
	end

	table.sort(live)
	table.sort(upcoming)
	return { live = live, next = upcoming }
end

return Projection
