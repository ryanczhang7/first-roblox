--!strict
--[[
	The negative controls for SEAT-002, and the proof that each check in
	`tests/helpers/ProjectionContract.luau` refuses the projection it exists to
	catch - plus the controls for AC-4's source guard, which is a matcher over
	text and has to be shown to match.

	TWO CRITERIA NAME THEIR CONTROL. AC-2: a copy-and-remove-sigma projection
	"passes a test that checks for a sigma key and must fail this". AC-3:
	"adding a new private field to Assignment and not to the allowlist must
	leave the projection unchanged", which the same copy fails. PO-6 says both
	halves of the AC-2 control are required: the naive test it PASSES and the
	real one it FAILS. If it failed both, the naive test was not naive enough
	and the control would prove nothing.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something, and a control
	that fails everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	measured here rather than predicted. The lens-from-supplier projection
	(mutation 2 of `## Notes`) fails AC-1 as predicted AND AC-2 AND AC-6,
	because the supplier's key class is a foreign one and both of those checks
	look for it; that is a property of the defect, not of the checks, and it
	is recorded in the story's mutation table.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/seats/Projection.luau` does not exist,
	`tests/server/projection_test.luau` fails at `require`, and not one
	assertion in it has executed. These controls need only SEAT-001's `Ring`,
	which is merged, so the numbers below are measurements taken in RED rather
	than claims left for GREEN.
]]

local Contract = require("../helpers/ProjectionContract")
local Deep = require("../helpers/Deep")
local SourceScan = require("../helpers/SourceScan")
local Stubs = require("../helpers/ProjectionStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local function accepts(check: Check, projection: any, what: string)
	local ok, err = pcall(check, projection)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, projection: any, what: string): string
	local ok, err = pcall(check, projection)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

-- Every check, so a control is held to all of them except the ones it is
-- built to fail.
local function passesTheChecks(projection: any, who: string, except: { [string]: boolean })
	local all: { Named } = {
		{ label = "AC-1", check = Contract.viewIsExactlyTheAllowlist },
		{ label = "AC-2", check = Contract.noForeignKeyClassAppears },
		{ label = "AC-3", check = Contract.privateFieldsAreAllowlistedOrAbsent },
		{ label = "AC-5", check = Contract.unknownPlayerIsRefusedByProjectionItself },
		{ label = "AC-6", check = Contract.pairwiseViewsRevealNothingOfEachOther },
		{ label = "naive", check = Contract.naiveFieldPresence },
	}
	for _, entry in all do
		if not except[entry.label] then
			accepts(entry.check, projection, `{entry.label} on {who}`)
		end
	end
end

-- SEAT-001's module, which legitimately clones: the on-disk control for the
-- AC-4 guard's file-reading path, borrowed rather than written.
local RING = "src/server/seats/Ring.luau"

return {
	--[[ The baseline. Every control below is this projection with exactly one
	     defect set, so a control that fires is attributable to that one thing. ]]

	["baseline: an allowlist projection over the real Ring passes every SEAT-002 check"] = function()
		passesTheChecks(Stubs.correct, "the baseline projection", {})
	end,

	--[[
		AC-2's control, named in the criterion, and THE control of this story:
		`table.clone(assignment)` then `view.sigma = nil`. Mutation 1 of the
		story's `## Notes`.

		BOTH HALVES (PO-6). It PASSES the naive test - no sigma key, a keyClass
		key - which is what makes it the projection that would otherwise ship.
		It FAILS AC-2 in every one of the 144 views, because `keyClass` is the
		table of everyone's classes and a removal-based projection keeps it.

		THE MEASURED NUMBERS. At n = 3, seed 2001, kim's view holds 3 integer
		leaves against an allowlist of exactly 2, and the one foreign class
		(zed's) is found by name at `view.keyClass.zed`. At n = 4, seed 2001,
		the same view holds 4 integers and both foreign classes. It fails AC-1,
		AC-3, AC-5 and AC-6 as well, because the bare copy has none of the
		named fields; the story's mutation 1 - the REAL module's literal
		construction replaced by a clone-and-delete - keeps the named fields
		and is predicted to fail AC-2 and AC-4 only. Same idea, two
		implementations, both red on AC-2, which is the point.
	]]
	["AC-2 control: copy-and-remove-sigma passes the naive sigma-key test and fails AC-2 on all 144 views - 3 integers at n = 3 and 4 at n = 4, where 2 are allowed"] = function()
		local projection = Stubs.copyAndRemoveSigma

		accepts(
			Contract.naiveFieldPresence,
			projection,
			"the copy-and-remove-sigma projection must PASS the naive sigma-key test, or the control "
				.. "proves nothing about AC-2"
		)

		local message = refuses(
			Contract.noForeignKeyClassAppears,
			projection,
			"a projection that copies the assignment and removes sigma must fail AC-2"
		)
		names(message, "AC-2", "the AC-2 control fires")
		names(message, "in 144 of 144 views", "the AC-2 failure counts every view")
		-- The MEASURED leak at n = 3, by name: kim's dependent is amy, so
		-- keyClass[amy] = 3 is kim's legitimate lensClass and zed's is foreign.
		names(
			message,
			"n = 3, seed 2001, view of kim: keyClass[zed] = 2 at view.keyClass.zed; "
				.. "3 integer-valued scalar(s) in the view; the allowlist has exactly two",
			"the AC-2 failure names the foreign class, where it was found, and the integer count"
		)

		-- And at n = 4, measured directly through the same flattener the check
		-- uses, since the check's message shows its first six cases only.
		local assignment = Contract.assignmentFor(4, Contract.SEEDS[1])
		local values = Contract.flatten(projection.forPlayer(assignment, "kim"))
		local integers: { string } = {}
		for _, leaf in values do
			if typeof(leaf.value) == "number" then
				table.insert(integers, `{leaf.path} = {leaf.value}`)
			end
		end
		table.sort(integers)
		assert(
			#integers == 4,
			`at n = 4 the copy carries {#integers} integer leaves, not 4: {table.concat(
				integers,
				", "
			)}`
		)
		assert(
			table.concat(integers, ", ")
				== "view.keyClass.amy = 3, view.keyClass.bob = 4, view.keyClass.kim = 1, view.keyClass.zed = 2",
			`the copy's integer leaves at n = 4 are not everyone's key classes: {table.concat(
				integers,
				", "
			)}`
		)
	end,

	--[[
		AC-3's control, named in the criterion: the same copy, with a new
		private field added to the Assignment. A copy carries it; an allowlist
		cannot. Also the first half: `players` and `sigma` are not in the
		allowlist and a copy has `players`.
	]]
	["AC-3 control: copy-and-remove-sigma carries a private field added after the fact, and carries players by name"] = function()
		local message = refuses(
			Contract.privateFieldsAreAllowlistedOrAbsent,
			Stubs.copyAndRemoveSigma,
			"a projection that copies the assignment must fail AC-3"
		)
		names(message, "AC-3", "the AC-3 control fires")
		names(
			message,
			"first half - a private field of the Assignment reaches the view in 144 of 144 views",
			"the AC-3 failure counts every view in the first half"
		)
		names(
			message,
			"private field players is present in the view",
			"the AC-3 failure names the un-allowlisted field the copy carried"
		)
		names(
			message,
			"second half - after a private field is added, the view changes or carries a secret "
				.. "in 32 of 32 views at n = 4",
			"the AC-3 failure counts every re-checked view in the second half"
		)
		names(
			message,
			"keyClass is in the allowlist as p's OWN value, but the view carries a table for it",
			"the AC-3 failure says keyClass came through as everyone's table"
		)
		names(
			message,
			"adding a private field 'pairings' to the Assignment CHANGED the view",
			"the AC-3 failure says the new private field changed the view"
		)
		names(
			message,
			'secret "SECRET:kim" leaked at view.pairings.kim[1]',
			"the AC-3 failure names a leaked secret and the nested path it was found at"
		)
		names(
			message,
			"secret 9001 leaked at view.pairings.kim[2]",
			"the integer sentinel is found too"
		)
	end,

	--[[
		The other criteria's controls, and the story's remaining two mutations.
	]]

	["mutation 2 control: a lens read from the supplier fails AC-1, and AC-2 and AC-6 with it, because the supplier's class is a foreign one"] = function()
		local projection = Stubs.lensFromSupplier
		passesTheChecks(projection, "the lens-from-supplier projection", {
			["AC-1"] = true,
			["AC-2"] = true,
			["AC-6"] = true,
		})

		local message = refuses(
			Contract.viewIsExactlyTheAllowlist,
			projection,
			"a lens read from the supplier must fail AC-1 on the lensClass VALUE"
		)
		names(message, "AC-1", "the AC-1 check fires on a backwards lens")
		names(message, "in 144 of 144", "AC-1 fires in every view - the lens is wrong for everyone")
		names(message, "value.lensClass: expected", "AC-1 names the field whose value is wrong")

		names(
			refuses(
				Contract.noForeignKeyClassAppears,
				projection,
				"the supplier's class is foreign"
			),
			"in 144 of 144 views",
			"AC-2 fires on a backwards lens in every view"
		)
		names(
			refuses(
				Contract.pairwiseViewsRevealNothingOfEachOther,
				projection,
				"and AC-6 sees it pairwise"
			),
			"AC-6",
			"AC-6 fires on a backwards lens"
		)
	end,

	["mutation 3 control: {} for an unknown player fails AC-5 alone"] = function()
		local projection = Stubs.emptyForUnknown
		passesTheChecks(projection, "the empty-for-unknown projection", { ["AC-5"] = true })

		local message = refuses(
			Contract.unknownPlayerIsRefusedByProjectionItself,
			projection,
			"a projection that returns {} for a stranger must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
		names(message, "in 3 case(s)", "AC-5 counts all three strangers")
		names(
			message,
			'forPlayer(assignment, "sam") returned {  } instead of raising',
			"the AC-5 failure shows the empty view that would otherwise hide"
		)
	end,

	["PO-3 control: a projection with no membership check of its own raises Ring's error for a stranger and fails AC-5 alone"] = function()
		local projection = Stubs.refuseViaRing
		passesTheChecks(projection, "the refuse-via-Ring projection", { ["AC-5"] = true })

		local message = refuses(
			Contract.unknownPlayerIsRefusedByProjectionItself,
			projection,
			"a projection that lets Ring.supplierOf refuse the stranger must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires on Ring's refusal")
		names(
			message,
			"is Ring's own refusal, not the projection's (PO-3)",
			"the AC-5 failure says whose error it was"
		)
		names(
			message,
			"does not name the module (Projection)",
			"the AC-5 failure says the module was not named"
		)
		names(
			message,
			"Ring.supplierOf: sam has no supplier",
			"the AC-5 failure quotes Ring's message"
		)
	end,

	--[[
		PO-2's control. Two checks see it, and both are right to: AC-1 has the
		identity pin on `seatOrder`, and AC-3's first half asks whether any
		table in the view IS one of the assignment's own - `players` is
		private by name and is present by reference. Measured, not predicted.
	]]
	["PO-2 control: handing out the assignment's own players table as seatOrder fails AC-1, and AC-3 by reference"] = function()
		local projection = Stubs.aliasSeatOrder
		passesTheChecks(projection, "the aliased-seatOrder projection", {
			["AC-1"] = true,
			["AC-3"] = true,
		})

		local message = refuses(
			Contract.viewIsExactlyTheAllowlist,
			projection,
			"a seatOrder that IS assignment.players must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 check fires on aliasing")
		names(
			message,
			"seatOrder IS the assignment's own players table (aliased, not built by a loop - PO-2)",
			"the AC-1 failure says the table was aliased"
		)
		names(message, "in 144 of 144", "every view aliases")

		names(
			refuses(
				Contract.privateFieldsAreAllowlistedOrAbsent,
				projection,
				"AC-3 sees it by reference"
			),
			"view.seatOrder IS the assignment's own players table",
			"AC-3 names the aliased table"
		)
	end,

	["AC-6 control: a seatOrder walked along the ring instead of the seats fails AC-6 and AC-1, in every case where the two orders differ"] = function()
		local projection = Stubs.seatOrderFromRing
		passesTheChecks(projection, "the ring-order projection", {
			["AC-1"] = true,
			["AC-6"] = true,
		})

		local message = refuses(
			Contract.pairwiseViewsRevealNothingOfEachOther,
			projection,
			"a seatOrder that is σ written out as a list must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires on the ring order")
		names(
			message,
			"is the RING order, which is σ written out as a list",
			"AC-6 names the leak"
		)
		-- THE MEASURED COUNT: how many of the 144 (n, seed, p) cases have a seat
		-- order that is not a rotation of the ring, so that this check can see
		-- the difference. The rest are the seeds where the two coincide.
		names(
			message,
			"in 123 of 144 views (123 cases where",
			"AC-6 fires in every discriminating case"
		)

		names(
			refuses(Contract.viewIsExactlyTheAllowlist, projection, "and AC-1 sees the wrong order"),
			"AC-1",
			"AC-1 fires on the ring order"
		)
	end,

	["AC-2 control: one extra integer field holding the supplier's key class fails AC-1, AC-2 and AC-6"] = function()
		local projection = Stubs.leakSupplierClass
		passesTheChecks(projection, "the leak-supplier-class projection", {
			["AC-1"] = true,
			["AC-2"] = true,
			["AC-6"] = true,
		})

		local message = refuses(
			Contract.noForeignKeyClassAppears,
			projection,
			"one foreign integer under a new name must fail AC-2"
		)
		names(message, "AC-2", "the AC-2 check fires on one integer")
		names(
			message,
			"3 integer-valued scalar(s) in the view; the allowlist has exactly two",
			"AC-2 counts the third integer"
		)
		names(message, "at view.supplierClass", "AC-2 names where the foreign class was found")

		names(
			refuses(Contract.viewIsExactlyTheAllowlist, projection, "AC-1 sees the extra key"),
			"value.supplierClass: unexpected",
			"AC-1 names the extra field"
		)
		names(
			refuses(
				Contract.pairwiseViewsRevealNothingOfEachOther,
				projection,
				"AC-6 sees it pairwise"
			),
			"at view.supplierClass",
			"AC-6 names where it found the supplier's class"
		)
	end,

	["AC-1 control: supplierId and dependentId exchanged fails AC-1 alone"] = function()
		local projection = Stubs.swapNeighbours
		passesTheChecks(projection, "the swapped-neighbours projection", { ["AC-1"] = true })

		local message = refuses(
			Contract.viewIsExactlyTheAllowlist,
			projection,
			"swapped neighbours must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 check fires on swapped neighbours")
		names(message, "value.supplierId: expected", "AC-1 names supplierId")
		names(message, "value.dependentId: expected", "AC-1 names dependentId")
		names(message, "in 144 of 144", "every view has them swapped")
	end,

	--[[
		The flattener, PO-5: it must reach every depth, and report keys and
		values separately with the path each was found at.
	]]

	["PO-5 control: the flattener reaches a value three tables down and reports keys separately from values"] = function()
		local values, keys = Contract.flatten({ a = { b = { c = 7 } }, d = { "x", "y" } })
		local found: { [string]: any } = {}
		for _, leaf in values do
			found[leaf.path] = leaf.value
		end
		assert(found["view.a.b.c"] == 7, `the nested leaf was not reached: {Deep.show(found)}`)
		assert(
			found["view.d[1]"] == "x" and found["view.d[2]"] == "y",
			`array leaves: {Deep.show(found)}`
		)
		assert(#values == 3, `{#values} value leaves, expected 3: {Deep.show(found)}`)

		local keyPaths: { [string]: any } = {}
		for _, leaf in keys do
			keyPaths[leaf.path] = leaf.value
		end
		assert(keyPaths["view.a.b.c"] == "c", `key leaves: {Deep.show(keyPaths)}`)
		assert(keyPaths["view.d[2]"] == 2, `array index as a key leaf: {Deep.show(keyPaths)}`)
		assert(
			keyPaths["view.a"] == "a" and keyPaths["view.a.b"] == "b",
			`intermediate keys: {Deep.show(keyPaths)}`
		)
		assert(
			#keys == 6,
			`{#keys} key leaves, expected 6 (a, a.b, a.b.c, d, d[1], d[2]): {Deep.show(keyPaths)}`
		)
	end,

	--[[
		AC-4's guard controls. The guard in `projection_test.luau` is
		`SourceScan.hitsIn` over one file with a banned list; these show the
		matcher fires on every banned symbol as code, stays quiet in comments
		and strings and on look-alike identifiers, and finds a real call in a
		real file through the classifier's list.
	]]

	["AC-4 control: the guard fires on every banned copy helper written as code, and names the line"] = function()
		local banned = {
			"table.clone",
			"table.move",
			"table.pack",
			"table.unpack",
			"table.freeze",
			"Deep.copy",
			"pairs",
			"next",
			"setmetatable",
		}
		local text = table.concat({
			"--!strict",
			"local view = table.clone(assignment)",
			"table.move(assignment.players, 1, #assignment.players, 1, view.seatOrder)",
			"local packed = table.pack(table.unpack(assignment.players))",
			"table.freeze(view)",
			"local deep = Deep.copy(assignment)",
			"for k, v in pairs(assignment) do view[k] = v end",
			"local k2, v2 = next(assignment)",
			"setmetatable(view, { __index = assignment })",
			"return view",
		}, "\n")

		local hits = SourceScan.hitsIn("src/server/seats/Leaky.luau", text, banned)
		local found: { [string]: number } = {}
		for _, hit in hits do
			found[hit.symbol] = hit.line
		end
		local missing: { string } = {}
		for _, symbol in banned do
			if found[symbol] == nil then
				table.insert(missing, symbol)
			end
		end
		assert(
			#missing == 0,
			`the guard did not fire on {table.concat(missing, ", ")}. It saw:\n`
				.. SourceScan.describeHits(hits)
		)
		assert(
			found["table.clone"] == 2,
			`table.clone reported on line {found["table.clone"]}, not 2`
		)
		names(
			SourceScan.describeHits(hits),
			"src/server/seats/Leaky.luau:2 references table.clone",
			"the rendered failure names the offending path and line"
		)
	end,

	["AC-4 control: the guard stays quiet on the banned names in comments, strings and look-alike identifiers, and on the explicit loop PO-2 prescribes"] = function()
		local text = table.concat({
			"--!strict",
			"--[[ never table.clone the assignment; Deep.copy and pairs are banned here ]]",
			'local why = "no table.clone, no setmetatable, no next"',
			"local tableclone = 1",
			"local repairs = { next = 2, pairs = 3 }",
			"local seatOrder = {}",
			"for i, id in assignment.players do",
			"\tseatOrder[i] = id",
			"end",
			"return { seatOrder = seatOrder, n = tableclone + repairs.next + repairs.pairs }",
		}, "\n")

		local hits = SourceScan.hitsIn("src/server/seats/Clean.luau", text, {
			"table.clone",
			"Deep.copy",
			"pairs",
			"next",
			"setmetatable",
		})
		assert(
			#hits == 0,
			`a comment, a string, a look-alike or the prescribed loop produced findings:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["AC-4 control: the guard's file-reading path finds Ring.luau's one legitimate table.clone on disk, through the classifier's list"] = function()
		local files = SourceScan.sourceFilesIn("src/server/seats")
		assert(
			SourceScan.contains(files, RING),
			`{RING} is not in the classifier's list for src/server/seats; without it this guard has `
				.. `no on-disk control. classify.sh said: {table.concat(files, ", ")}`
		)

		local hits = SourceScan.scanFor({ RING }, { "table.clone" })
		assert(
			#hits == 1,
			`scanFor read {RING} and found {#hits} table.clone call(s); SEAT-001 wrote exactly one `
				.. `(players = table.clone(players)):\n{SourceScan.describeHits(hits)}`
		)
		assert(
			hits[1].path == RING,
			`the hit names {hits[1].path} rather than the file it was read from`
		)
		-- And this is why PO-4 says "that path only": a guard over the subtree
		-- would fire on Ring.luau against correct code.
	end,
}
