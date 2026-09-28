--!strict
--[[
	SEAT-002 AC-1, AC-2, AC-3, AC-5 and AC-6 written once, as checks over a
	PROJECTION rather than over `src/server/seats/Projection.luau` by name - the
	same arrangement as `RingContract.luau`, and for the same reason.

	`tests/server/projection_test.luau` applies these to the real module.
	`tests/server/projection_controls_test.luau` applies them to the deliberately
	wrong projections in `ProjectionStubs.luau`, so that in RED - where the
	production module does not exist, the real file fails at `require`, and not
	one assertion in it has executed - every check here has still been EXECUTED
	and observed to reject the implementation it exists to catch. AC-4 is a
	guard over the source text and lives in the test file, not here.

	A `projection` here is anything with one plain field function, called with
	a dot exactly as the story's Contract writes it:

	    projection.forPlayer(assignment, playerId) -> PublicSeatView

	and the `Assignment` handed in is always one `Ring.assign` dealt - the real
	`src/server/seats/Ring.luau`, merged in SEAT-001 - so the oracle for every
	field is read off the assignment's own `sigma`, `keyClasses` and `lens`
	tables, not through the accessors the module under test is told to use. A
	projection that reimplemented `σ⁻¹` backwards would agree with itself and
	disagree with this.

	SEAT-003 CHANGED THE SHAPE AND THE CASES. `keyClass` (one class per player)
	became `keyClasses` (a LIST per player) and `lens` is stored; the view's
	`keyClass` became `keyClasses`, p's OWN list. And a player can now hold two
	classes - after a withdrawal the supplier does - so the cases below include
	WITHDRAWN rings, dealt by the real `Ring.assign` and closed by the real
	`Ring.withdraw`. "Own" for the leak checks is p's own `keyClasses` entries
	plus `lens[p]`; every class anyone else holds is foreign, INCLUDING a second
	class the supplier holds that p's lens does not read. If the simplest way
	to carry two classes tempts an implementation toward a shared table, this
	is where it shows.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1, AC-5 and AC-6 are SETTLED by
	`roles.md` §3 and §6: a player knows their own key, their own lens, who is
	on either side of them and who is in the round, and NOT what anyone else
	can see. The allowlist below is the Contract's `PublicSeatView`, verbatim.
	AC-2 and AC-3 are mechanical, and their controls are the implementations
	`ProjectionStubs.luau` writes out.

	THE SENTENCE THIS IS FOR (`roles.md` §6): "a client that can read another
	player's lens is not cheating at a scoreboard, it has deleted the game."
	The natural test for a function this small is that it returns the right
	fields. The criterion that matters is that it returns NOTHING ELSE, and
	every check here is written from that side.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Ring = require("../../src/server/seats/Ring")
local RingContract = require("./RingContract")

local ProjectionContract = {}

export type Projection = any
export type Assignment = any
export type View = any

-- The Contract's `PublicSeatView`, every field by name. THE ALLOWLIST IS THE
-- TYPE: a field that is not here must not be in the view, for any player.
ProjectionContract.ALLOWLIST = {
	"playerId",
	"keyClasses",
	"lensClass",
	"supplierId",
	"dependentId",
	"seatOrder",
}

local ALLOWED: { [string]: boolean } = {}
for _, field in ProjectionContract.ALLOWLIST do
	ALLOWED[field] = true
end

-- Every `n` a criterion says "for `n` players" over: `min_players_to_continue`
-- (3) up to `players_max` (6), as SEAT-001 settled them.
ProjectionContract.COUNTS = RingContract.COUNTS

--[[
	Eight fixed seeds per n. The checks below are exact, not statistical - one
	wrong field on one seed is a failure - so the sample exists for one reason:
	the SEAT order and the RING order coincide on some seeds (half of them at
	n = 3), and a `seatOrder` built from the ring rather than the seats is
	invisible on exactly those. Eight seeds at each of four counts leave over a
	hundred cases where the two orders differ, and AC-6 counts them.
]]
local SEEDS: { number } = {}
for i = 1, 8 do
	SEEDS[i] = 2000 + i
end
ProjectionContract.SEEDS = SEEDS

function ProjectionContract.assignmentFor(n: number, seed: number): Assignment
	return Ring.assign(RingContract.seated(n), RingContract.rngFor(seed))
end

--[[
	SEAT-003: a ring of n dealt and then closed after `players[leaverIndex]`
	leaves, through the real `Ring.withdraw`. The supplier now holds two
	classes, which is the only way a view with more than one class exists.
	Both fixtures are reached through the module table (`ProjectionContract.x`)
	rather than a local, so a RED-phase measurement can stand in a candidate
	ring while the real one is missing the function.
]]
function ProjectionContract.withdrawnAssignmentFor(
	n: number,
	seed: number,
	leaverIndex: number
): Assignment
	local dealt = ProjectionContract.assignmentFor(n, seed)
	-- Named, so that the RED failure reads as the missing export it is.
	if typeof(Ring.withdraw) ~= "function" then
		Contract.fail(
			`Ring.withdraw is {typeof(Ring.withdraw)} - the withdrawn fixtures need SEAT-003's `
				.. `Ring.withdraw(assignment, playerId)`
		)
	end
	return Ring.withdraw(dealt, dealt.players[leaverIndex])
end

-- The withdrawn cases: two seeds at each n a withdrawal can leave a ring of
-- (4, 5, 6 → 3, 4, 5 seated), the second-seated player leaving each time.
ProjectionContract.WITHDRAWN_COUNTS = { 4, 5, 6 }
ProjectionContract.WITHDRAWN_SEEDS = { SEEDS[1], SEEDS[2] }
ProjectionContract.WITHDRAWN_LEAVER = 2

-- σ⁻¹(p), read off the assignment's own σ by a scan over the seated players.
-- Deliberately NOT `Ring.supplierOf`: this is the oracle, and an oracle that
-- shares the implementation's accessor cannot see the accessor go wrong.
local function supplierIn(assignment: Assignment, playerId: string): string?
	for _, candidate in assignment.players do
		if assignment.sigma[candidate] == playerId then
			return candidate
		end
	end
	return nil
end

--[[
	`roles.md` §3 read out as a table: what `p` knows. Own key, own lens - which
	IS the dependent's key class, `λ(p) = k(σ(p))`, and is safe to send because
	`p` sees those values anyway by pointing a light at the panels
	(`mechanics.md` §2) - the two neighbours, and the public seat order.
]]
function ProjectionContract.expectedView(assignment: Assignment, playerId: string): View
	return {
		playerId = playerId,
		-- Clones here are the ORACLE's copies, made in a test helper; AC-4's
		-- ban on copy helpers is over `Projection.luau` and nothing else.
		keyClasses = table.clone(assignment.keyClasses[playerId]),
		-- λ(p) is STORED (SEAT-003 PO-1): after a withdrawal k(σ(p)) names the
		-- lost lens for the supplier, so the oracle reads the field.
		lensClass = assignment.lens[playerId],
		supplierId = supplierIn(assignment, playerId),
		dependentId = assignment.sigma[playerId],
		seatOrder = table.clone(assignment.players),
	}
end

-- The classes p may legitimately see as integers: p's own, and the one p's
-- lens reads. Everything anyone else holds is foreign.
local function ownClassesOf(assignment: Assignment, playerId: string): { [number]: string }
	local own: { [number]: string } = {}
	for _, class in assignment.keyClasses[playerId] do
		own[class] = playerId
	end
	own[assignment.lens[playerId]] = `lens of {playerId}`
	return own
end

local function foreignClassesOf(assignment: Assignment, playerId: string): { [number]: string }
	local own = ownClassesOf(assignment, playerId)
	local foreign: { [number]: string } = {}
	for _, q in assignment.players do
		if q ~= playerId then
			for _, class in assignment.keyClasses[q] do
				if own[class] == nil then
					foreign[class] = q
				end
			end
		end
	end
	return foreign
end

--[[
	PO-5: "serialised to a flat set of scalar values" means EVERY nested table,
	every key and every value, recursively. `seatOrder` is a table, so a
	flattener that reads only the top level already misses the one nested
	field the view has - and the M3 fields will be nested too.

	Values and keys come back as separate lists, each leaf with the path it was
	found at, because a failure that says "3 appeared" is not a bug report and
	one that says "keyClass[amy] = 3 at view.keyClass.amy" is. Keys are
	reported separately from values because array indices are integers 1..n -
	the same small integers key classes are - and mixing the two lists would
	make every seat position look like a leaked class.
]]
export type Leaf = { path: string, value: any }

function ProjectionContract.flatten(view: any): ({ Leaf }, { Leaf })
	local values: { Leaf } = {}
	local keys: { Leaf } = {}
	local seen: { [any]: boolean } = {}

	local function walk(value: any, path: string)
		if typeof(value) ~= "table" then
			table.insert(values, { path = path, value = value })
			return
		end
		if seen[value] then
			table.insert(values, { path = path, value = "<cycle>" })
			return
		end
		seen[value] = true
		for key, item in pairs(value :: { [any]: any }) do
			local here = if typeof(key) == "number"
				then `{path}[{key}]`
				else `{path}.{tostring(key)}`
			table.insert(keys, { path = here, value = key })
			walk(item, here)
		end
		seen[value] = nil
	end

	walk(view, "view")
	return values, keys
end

--[[
	Every failure here goes through `Contract.fail`, and every message is built
	only on the path that raises it (HARNESS-011). SEAT-002 measured that
	`assert` cuts these messages and used a private `check` -> `error(message,
	2)` instead, which escaped the cut but still built every message on every
	passing run. See `tests/helpers/Contract.luau`.
]]
local firstFew = Contract.firstFew

local function isInteger(value: any): boolean
	return typeof(value) == "number" and value == math.floor(value :: number)
end

-- Every (n, seed, p) case, with the assignment dealt once per (n, seed) -
-- the dealt rings first, then the withdrawn ones (SEAT-003).
type Case = { n: number, seed: number, assignment: Assignment, playerId: string, left: string? }

local function everyCase(): { Case }
	local cases: { Case } = {}
	for _, n in ProjectionContract.COUNTS do
		for _, seed in SEEDS do
			local assignment = ProjectionContract.assignmentFor(n, seed)
			for _, playerId in assignment.players do
				table.insert(
					cases,
					{ n = n, seed = seed, assignment = assignment, playerId = playerId }
				)
			end
		end
	end
	for _, n in ProjectionContract.WITHDRAWN_COUNTS do
		for _, seed in ProjectionContract.WITHDRAWN_SEEDS do
			local leaver = RingContract.seated(n)[ProjectionContract.WITHDRAWN_LEAVER]
			local assignment = ProjectionContract.withdrawnAssignmentFor(
				n,
				seed,
				ProjectionContract.WITHDRAWN_LEAVER
			)
			for _, playerId in assignment.players do
				table.insert(cases, {
					n = n,
					seed = seed,
					assignment = assignment,
					playerId = playerId,
					left = leaver,
				})
			end
		end
	end
	return cases
end

local function label(case: Case): string
	local suffix = if case.left ~= nil then ` after {case.left} left` else ""
	return `n = {case.n}, seed {case.seed}{suffix}, view of {case.playerId}`
end

--[[
	AC-1. The view is the Contract's `PublicSeatView` for `p` and NOTHING ELSE.

	`Deep.diff` against the expected view is the whole assertion: a missing
	field, a wrong value and an EXTRA field all show up, by name. The one thing
	a structural diff cannot see is aliasing, so the second half is PO-2's pin:
	`seatOrder` is a fresh table, never `assignment.players` itself, because
	`Ring.assign` cloned that list precisely so that nobody outside can reach
	an assignment already dealt.
]]
function ProjectionContract.viewIsExactlyTheAllowlist(projection: Projection)
	local violations: { string } = {}
	local cases = everyCase()

	for _, case in cases do
		local view = projection.forPlayer(case.assignment, case.playerId)
		local diff =
			Deep.diff(ProjectionContract.expectedView(case.assignment, case.playerId), view)
		if diff ~= "" then
			table.insert(violations, `  {label(case)}:\n    {(string.gsub(diff, "\n", "\n    "))}`)
		end
		if typeof(view) == "table" and view.seatOrder == case.assignment.players then
			table.insert(
				violations,
				`  {label(case)}: seatOrder IS the assignment's own players table (aliased, `
					.. `not built by a loop - PO-2)`
			)
		end
		-- SEAT-003: the same pin on the class list. A view handing out
		-- `assignment.keyClasses[p]` itself lets a client reach a list the
		-- server appends to on the next withdrawal.
		if
			typeof(view) == "table"
			and view.keyClasses == case.assignment.keyClasses[case.playerId]
		then
			table.insert(
				violations,
				`  {label(case)}: keyClasses IS the assignment's own list for {case.playerId} `
					.. `(aliased, not built by an append loop - SEAT-003)`
			)
		end
	end

	if #violations > 0 then
		Contract.fail(
			`AC-1: the view is not exactly the allowlist ({table.concat(
				ProjectionContract.ALLOWLIST,
				", "
			)}) `
				.. `for p in {#violations} of {#cases} (n, seed, p) cases:\n{firstFew(violations, 6)}`
		)
	end
end

--[[
	AC-2. Flattened to scalars, the view carries no other player's key class.

	THE DISCRIMINATION, chosen deliberately (PO-5). Key classes are the
	integers 1..n and `p` legitimately holds more than one of them - every
	entry of `keyClasses[p]` and `lensClass = lens[p]` - so "no integer equal
	to anyone else's class" would fail a correct projection on `lensClass`.
	Two checks instead, both over integer-TYPED leaf values only:

	  1. no leaf equals a class held by any other player, unless it is the one
	     class p's lens reads;
	  2. there are EXACTLY #keyClasses[p] + 1 integer-valued leaves in the
	     whole view: p's own list and `lensClass`.

	After a withdrawal (SEAT-003) the supplier's second class is FOREIGN to
	everyone whose lens does not read it, even though the supplier legitimately
	holds it - what p may see is still what p's own lens covers.

	What this cannot catch, stated now: a leak of the DEPENDENT's class under a
	second name, since that value is already legitimately present as
	`lensClass` - AC-1's extra-field check is what sees that. And an integer
	smuggled out as a string ("3") is invisible to (1) and (2) alike; AC-6's
	string-leaf check is what sees that.
]]
function ProjectionContract.noForeignKeyClassAppears(projection: Projection)
	local violations: { string } = {}
	local cases = everyCase()

	for _, case in cases do
		local assignment, p = case.assignment, case.playerId
		local view = projection.forPlayer(assignment, p)
		local values = ProjectionContract.flatten(view)

		local own = ownClassesOf(assignment, p)
		local foreign = foreignClassesOf(assignment, p)
		local allowed = #assignment.keyClasses[p] + 1

		local problems: { string } = {}
		local integers = 0
		local ownSeen: { [number]: boolean } = {}
		for _, leaf in values do
			if isInteger(leaf.value) then
				integers += 1
				local class = leaf.value :: number
				if foreign[class] ~= nil then
					table.insert(problems, `a class of {foreign[class]}'s, {class}, at {leaf.path}`)
				elseif own[class] ~= nil then
					ownSeen[class] = true
				end
			end
		end
		if integers ~= allowed then
			table.insert(
				problems,
				`{integers} integer-valued scalar(s) in the view; {p} holds {allowed - 1} class(es), `
					.. `so the allowlist has exactly {allowed} (keyClasses and lensClass)`
			)
		end
		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	if #violations > 0 then
		Contract.fail(
			`AC-2: another player's key class appears in the flattened view in {#violations} of `
				.. `{#cases} views:\n{firstFew(violations, 6)}`
		)
	end
end

--[[
	AC-3. Every field of the private `Assignment` is either in the allowlist or
	provably absent from the view, for every player - and a NEW private field
	does not change the view at all.

	The first half walks the assignment's own keys, so it is not a list of
	names written here that could go stale: whatever `Assignment` carries,
	each key is either an allowlisted name (today only `keyClasses`, which in
	the view is p's OWN list and must not be the map keyed by player) or must
	be absent - `lens`, the map of everyone's lens, is private by name.

	The second half is the criterion's control, run in every case: a new
	private field shaped the way M3's will be - a per-player table of secrets
	with sentinel values that cannot be mistaken for anything legitimate - is
	added AFTER the first view is taken, and the second view must be
	byte-identical, with no sentinel anywhere in it, at any depth, as a key or
	a value. This is the property that makes M3's additions safe by default: a
	denylist projection fails it the day a field is added, an allowlist never
	does.
]]
local SECRET_INTEGER_BASE = 9000 -- outside 1..6, so no key class can collide

function ProjectionContract.privateFieldsAreAllowlistedOrAbsent(projection: Projection)
	local present: { string } = {}
	local changed: { string } = {}
	local cases = everyCase()

	for _, case in cases do
		local assignment, p = case.assignment, case.playerId
		local view = projection.forPlayer(assignment, p)
		local problems: { string } = {}

		if typeof(view) ~= "table" then
			table.insert(problems, `forPlayer returned {typeof(view)}`)
		else
			for key, private in pairs(assignment :: { [any]: any }) do
				local name = tostring(key)
				if ALLOWED[name] then
					-- The one shared name is `keyClasses`: p's own LIST in the
					-- view, the map of everyone's lists on the assignment. A
					-- string key anywhere in the view's value is the map.
					local carried = view[key]
					local keyedByPlayer = false
					if typeof(carried) == "table" then
						for field in pairs(carried :: { [any]: any }) do
							if typeof(field) == "string" then
								keyedByPlayer = true
							end
						end
					end
					if keyedByPlayer then
						table.insert(
							problems,
							`{name} is in the allowlist as p's OWN list, but the view carries the `
								.. `map keyed by player: {Deep.show(carried)}`
						)
					elseif typeof(carried) == "table" and not Deep.equal(private[p], carried) then
						table.insert(
							problems,
							`{name} is in the allowlist as p's OWN list, but the view carries `
								.. `{Deep.show(carried)} where {p}'s is {Deep.show(private[p])}`
						)
					end
				elseif view[key] ~= nil then
					table.insert(
						problems,
						`private field {name} is present in the view: {Deep.show(view[key])}`
					)
				end
				if typeof(private) == "table" and typeof(view) == "table" then
					for field, item in pairs(view :: { [any]: any }) do
						if item == private then
							table.insert(
								problems,
								`view.{tostring(field)} IS the assignment's own {name} table`
							)
						end
					end
				end
			end
		end

		if #problems > 0 then
			table.insert(present, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	-- The control: add the M3-shaped field and take every view again.
	local before: { [string]: View } = {}
	local pinned: { Case } = {}
	for _, case in cases do
		if case.n == 4 then
			table.insert(pinned, case)
		end
	end
	-- Keyed by the leaver too (SEAT-003): a withdrawn n = 4 case shares its
	-- seed with the dealt one and must not overwrite its snapshot.
	local function keyOf(case: Case): string
		return `{case.seed}/{case.left or "dealt"}/{case.playerId}`
	end
	for _, case in pinned do
		before[keyOf(case)] = Deep.copy(projection.forPlayer(case.assignment, case.playerId))
	end
	local sentinelStrings: { [string]: boolean } = {}
	local sentinelIntegers: { [number]: boolean } = {}
	local touched: { [any]: boolean } = {}
	for _, case in pinned do
		if not touched[case.assignment] then
			touched[case.assignment] = true
			local secrets: { [string]: { any } } = {}
			for i, id in case.assignment.players do
				local word = `SECRET:{id}`
				secrets[id] = { word, SECRET_INTEGER_BASE + i }
				sentinelStrings[word] = true
				sentinelIntegers[SECRET_INTEGER_BASE + i] = true
			end
			case.assignment.pairings = secrets
		end
	end
	for _, case in pinned do
		local after = projection.forPlayer(case.assignment, case.playerId)
		local diff = Deep.diff(before[keyOf(case)], after)
		local problems: { string } = {}
		if diff ~= "" then
			table.insert(
				problems,
				"adding a private field 'pairings' to the Assignment CHANGED the view:\n    "
					.. (string.gsub(diff, "\n", "\n    "))
			)
		end
		local values, keys = ProjectionContract.flatten(after)
		for _, leaf in values do
			if sentinelStrings[leaf.value] or sentinelIntegers[leaf.value] then
				table.insert(problems, `secret {Deep.show(leaf.value)} leaked at {leaf.path}`)
			end
		end
		for _, leaf in keys do
			if leaf.value == "pairings" then
				table.insert(
					problems,
					`the private field's own name appears as a key at {leaf.path}`
				)
			end
		end
		if #problems > 0 then
			table.insert(changed, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end
	if not (#pinned > 0) then
		Contract.fail("the AC-3 control ran over no views; a control over nothing proves nothing")
	end

	if not (#present == 0 and #changed == 0) then
		Contract.fail(
			`AC-3: first half - a private field of the Assignment reaches the view in {#present} of `
				.. `{#cases} views:\n{firstFew(present, 4)}\n`
				.. `AC-3: second half - after a private field is added, the view changes or carries a `
				.. `secret in {#changed} of {#pinned} views at n = 4:\n{firstFew(changed, 4)}`
		)
	end
end

--[[
	AC-5. A player not in the assignment is REFUSED - by the projection itself.

	Three needles, because "it raised" is satisfied by the wrong module (PO-3):
	`Ring.supplierOf` already raises for an unseated player, and a projection
	that reached it would pass a bare `pcall` check for a reason that is not
	its own. So, with the location prefix Lune puts on every error split off:

	  * the message names the module ("Projection") and the player;
	  * the message is not Ring's - it does not begin `Ring.`;
	  * the location is not `Projection.luau` itself: the error is raised at
	    level 2, attributed to the caller who asked for a stranger's view.

	And the positive half, without which a projection that always raises
	passes: every seated player still gets a view.
]]
-- A name never seated, a seated name in the wrong case, and nil. Each is a
-- record so that the nil case survives being put in a list.
local STRANGERS: { { id: any } } = { { id = "sam" }, { id = "KIM" }, { id = nil } }

local function splitLocation(message: string): (string, string)
	local location, rest = string.match(message, "^(.-):%d+: (.*)$")
	if location == nil then
		return "", message
	end
	return location :: string, rest :: string
end

function ProjectionContract.unknownPlayerIsRefusedByProjectionItself(projection: Projection)
	local violations: { string } = {}
	local assignment = ProjectionContract.assignmentFor(4, SEEDS[1])

	for _, entry in STRANGERS do
		local stranger = entry.id
		local shown = if stranger == nil then "nil" else Deep.show(stranger)
		local ok, result = pcall(projection.forPlayer, assignment, stranger)
		if ok then
			table.insert(
				violations,
				`  forPlayer(assignment, {shown}) returned {Deep.show(result)} instead of raising; `
					.. `an empty or partial view for a stranger is a bug that hides`
			)
		else
			local message = tostring(result)
			local location, rest = splitLocation(message)
			local problems: { string } = {}
			if string.find(rest, "Projection", 1, true) == nil then
				table.insert(problems, "does not name the module (Projection)")
			end
			if string.find(rest, tostring(stranger), 1, true) == nil then
				table.insert(problems, `does not name the player ({tostring(stranger)})`)
			end
			if string.find(rest, "^Ring%.") ~= nil then
				table.insert(problems, "is Ring's own refusal, not the projection's (PO-3)")
			end
			if string.find(location, "[/\\]Projection$") ~= nil then
				table.insert(
					problems,
					"is attributed to Projection.luau itself rather than to its caller (level 2, PO-3)"
				)
			end
			if #problems > 0 then
				table.insert(
					violations,
					`  forPlayer(assignment, {shown}) raised, but the error `
						.. `{table.concat(problems, "; ")}:\n    {message}`
				)
			end
		end
	end

	for _, p in assignment.players do
		local ok, result = pcall(projection.forPlayer, assignment, p)
		if not ok then
			table.insert(
				violations,
				`  forPlayer(assignment, "{p}") raised for a SEATED player: {tostring(result)}`
			)
		end
	end

	if #violations > 0 then
		Contract.fail(
			`AC-5: a player not in the assignment is not refused by the projection itself, in `
				.. `{#violations} case(s):\n{table.concat(violations, "\n")}`
		)
	end
end

--[[
	AC-6. For any two distinct players, neither view lets a reader compute the
	other's lens: no class of q's that p's lens does not read, and no `σ` in
	any form.

	"In any form" is the half that needs saying. σ can be sent as the table it
	is, as a nested table under some other name, as strings ("kim>zed"), or as
	an ORDER: the ring order is σ written out as a list, and a `seatOrder`
	built by walking the ring from `p` instead of copying the seats hands
	every client the whole permutation. So, per view:

	  * pairwise: for every q ≠ p, no class in `keyClasses[q]` other than
	    `lens[p]` is an integer leaf anywhere in p's view;
	  * every table below the root is an array - no nested table is keyed by
	    strings, which is what a σ, a keyClasses or a lens map looks like at
	    any depth;
	  * every string leaf is a seated player's id - nothing stringified;
	  * `seatOrder` is not a rotation of the ring order, in every case where
	    the seat order itself is not one - and the number of such cases is
	    asserted, because at n = 3 half the seeds make the two coincide.

	What this cannot catch: the supplier's lens CLASS is `keyClass[p]` by the
	ring's definition (`roles.md` §2: your supplier is the one who can see what
	your actuators need), so `p` can always name it from their own key. That
	is the design, not a leak; the secret M3 adds is the lens CONTENTS.
]]
local function ringOrderFrom(assignment: Assignment, start: string): { string }
	local order: { string } = { start }
	local at = start
	for _ = 1, #assignment.players do
		local nextAt = assignment.sigma[at]
		if nextAt == nil or nextAt == start then
			break
		end
		table.insert(order, nextAt)
		at = nextAt
	end
	return order
end

local function isRotationOf(list: { any }, ring: { string }): boolean
	if #list ~= #ring then
		return false
	end
	for offset = 0, #ring - 1 do
		local same = true
		for i = 1, #ring do
			if list[i] ~= ring[((i - 1 + offset) % #ring) + 1] then
				same = false
				break
			end
		end
		if same then
			return true
		end
	end
	return false
end

function ProjectionContract.pairwiseViewsRevealNothingOfEachOther(projection: Projection)
	local violations: { string } = {}
	local cases = everyCase()
	local discriminating = 0

	for _, case in cases do
		local assignment, p = case.assignment, case.playerId
		local view = projection.forPlayer(assignment, p)
		local values, keys = ProjectionContract.flatten(view)
		local problems: { string } = {}

		local seated: { [any]: boolean } = {}
		for _, id in assignment.players do
			seated[id] = true
		end

		local foreign = foreignClassesOf(assignment, p)
		for _, leaf in values do
			if isInteger(leaf.value) and foreign[leaf.value] ~= nil then
				table.insert(
					problems,
					`a class of {foreign[leaf.value]}'s, {leaf.value}, at {leaf.path}`
				)
			end
		end

		for _, leaf in keys do
			-- A string key one level or more below the root. Root keys are
			-- `view.<field>`; anything deeper has a second dot or a bracket
			-- before its last segment.
			local depth = select(2, string.gsub(leaf.path, "[%.%[]", ""))
			if depth >= 2 and typeof(leaf.value) == "string" then
				table.insert(
					problems,
					`a nested table keyed by "{leaf.value}" at {leaf.path} - σ or keyClass in another shape`
				)
			end
		end

		for _, leaf in values do
			if typeof(leaf.value) == "string" and not seated[leaf.value] then
				table.insert(
					problems,
					`a string that is not a seated player's id at {leaf.path}: "{leaf.value}"`
				)
			end
		end

		local ring = ringOrderFrom(assignment, assignment.players[1])
		if not isRotationOf(assignment.players, ring) then
			discriminating += 1
			if
				typeof(view) == "table"
				and typeof(view.seatOrder) == "table"
				and isRotationOf(view.seatOrder, ring)
			then
				table.insert(
					problems,
					`seatOrder {Deep.show(view.seatOrder)} is the RING order, which is σ written out as a list`
				)
			end
		end

		if #problems > 0 then
			table.insert(violations, `  {label(case)}: {table.concat(problems, "; ")}`)
		end
	end

	if not (discriminating >= 100) then
		Contract.fail(
			`AC-6's ring-order check discriminated in only {discriminating} of {#cases} cases; `
				.. `the seeds need changing, not the check`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-6: a view lets a reader compute another player's lens in {#violations} of {#cases} `
				.. `views ({discriminating} cases where the seat order and the ring order differ):\n`
				.. firstFew(violations, 6)
		)
	end
end

--[[
	THE NAIVE TEST, for PO-6: "the view has no `sigma` key". This is the test a
	denylist projection is written against and passes - it checks for the one
	private field everyone already knows about, and it is satisfied by a copy
	of the assignment with that field removed. It is here so that
	`projection_controls_test.luau` can show the copy-and-remove-sigma control
	PASSING it and FAILING AC-2 in the same breath; a control that fails both
	proves nothing about AC-2.
]]
function ProjectionContract.naiveFieldPresence(projection: Projection)
	local assignment = ProjectionContract.assignmentFor(4, SEEDS[1])
	local violations: { string } = {}
	for _, p in assignment.players do
		local view = projection.forPlayer(assignment, p)
		if typeof(view) ~= "table" then
			table.insert(violations, `view of {p} is {typeof(view)}`)
		elseif view.sigma ~= nil then
			table.insert(violations, `view of {p} has a sigma field: {Deep.show(view.sigma)}`)
		elseif view.keyClasses == nil then
			table.insert(violations, `view of {p} has no keyClasses field`)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`naive: the view carries a sigma key or no keyClasses key:\n{table.concat(
				violations,
				"\n"
			)}`
		)
	end
end

return ProjectionContract
