--!strict
--[[
	SEAT-002: a replicated seat view contains nothing of anyone else's. AC-1
	through AC-6, applied to the real `src/server/seats/Projection.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test. In RED it does not exist, and a bare top-level `require` would
	make this whole file a single LOAD FAIL - one line of red covering six
	criteria. Per-criterion failures say which behaviours are missing, which is
	what GREEN needs. It is not a skip: every test below still FAILS, loudly,
	naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/ProjectionContract.luau` and are
	exercised against deliberately wrong projections in
	`tests/server/projection_controls_test.luau`. That file is where each check
	is OBSERVED to fire - which matters in RED, because the pcall above means
	not one assertion in THIS file executes until GREEN writes the module.

	AC-4 IS THE EXCEPTION: it is a guard over the SOURCE TEXT of the module,
	not over its behaviour, and it lives here rather than in the contract
	helper because it names one file. It pins the SHAPE of the code - no copy
	helper anywhere in `Projection.luau` - which is the right instrument rather
	than a weaker substitute for a test: AC-2 and AC-3 can both be satisfied
	today by a copy that happens to be correct today, and the leak that copy
	will carry arrives with a field M3 has not written yet, which no test this
	repository can run today can reach. `tdd-cycle`, "grep for the shape".

	THE SENTENCE THIS FILE IS FOR (`roles.md` §6): "a client that can read
	another player's lens is not cheating at a scoreboard, it has deleted the
	game." Roblox clients are hostile and read whatever is replicated to them.
	The only mechanism that works is never sending it, and the only way to
	never send it is to build the view up by name rather than filter the
	assignment down.
]]

local Contract = require("../helpers/ProjectionContract")
local SourceScan = require("../helpers/SourceScan")

local loaded, loadResult = pcall(require, "../../src/server/seats/Projection")

local function Projection(): any
	assert(loaded, `src/server/seats/Projection.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local SEATS = "src/server/seats"
local PROJECTION = "src/server/seats/Projection.luau"

--[[
	AC-4's flat ban, per PO-2: no argument analysis, no allowance. Every one
	of these is a way to move a whole table rather than a named field, and
	`Projection.luau` has no legitimate use for any of them once `seatOrder` is
	an explicit loop. `pairs` and `next` are the inline copy (`for k, v in
	pairs(assignment) do view[k] = v end`), which no helper ban would see.
	`setmetatable` is the copy by reference - a view that delegates lookups to
	the assignment. `Deep.copy` is this repository's own deep-copy helper.

	WHAT THE GUARD CANNOT CATCH, stated so nobody assumes otherwise: the scan
	is textual over code with comments and strings blanked, and it matches the
	way a call is written. `table["clone"]`, a local alias made from a table
	lookup, a generalised-iteration copy written `for k, v in assignment do`
	with no `pairs`, and a helper required under another name are all
	invisible to it. The last of those is why the require check below exists;
	the others are why AC-2, AC-3 and AC-6 exist.
]]
local BANNED: { string } = {
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

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Projection exports forPlayer as a plain field function and nothing else the Contract does not name"] = function()
		local projection = Projection()
		assert(
			typeof(projection.forPlayer) == "function",
			`Projection.forPlayer is {typeof(projection.forPlayer)}`
		)
	end,

	--[[ AC-1 ]]

	["AC-1: the view for p is exactly p's own keyClass, own lensClass, supplierId, dependentId, playerId and a fresh seatOrder - and nothing else"] = function()
		Contract.viewIsExactlyTheAllowlist(Projection())
	end,

	--[[ AC-2 ]]

	["AC-2: flattened to scalars at every depth, the view carries exactly two integers and neither is another player's key class"] = function()
		Contract.noForeignKeyClassAppears(Projection())
	end,

	--[[ AC-3 ]]

	["AC-3: every field of the private Assignment is allowlisted or absent, and adding a new private field leaves every view unchanged"] = function()
		Contract.privateFieldsAreAllowlistedOrAbsent(Projection())
	end,

	--[[ AC-4. The source guard. Two tests, the first of which is the vacuity
	     check PO-4 requires: a guard over a file list that does not contain its
	     subject passes over nothing. In RED this is the failure that names the
	     missing module. ]]

	["AC-4: the harness's source list for src/server/seats contains Projection.luau, so the guard has a subject"] = function()
		local files = SourceScan.sourceFilesIn(SEATS)
		assert(
			SourceScan.contains(files, PROJECTION),
			`{PROJECTION} is not in the scanned set; a guard over nothing passes. `
				.. `classify.sh --list source {SEATS} said: {table.concat(files, ", ")}`
		)
	end,

	["AC-4: Projection.luau builds its result field by field - no table.clone, table.move, table.pack, table.unpack, table.freeze, Deep.copy, pairs, next or setmetatable anywhere in it"] = function()
		local files = SourceScan.sourceFilesIn(SEATS)
		-- Repeated here rather than trusted from the test above: a clean scan
		-- over an empty list is the one way this assertion can pass while
		-- proving nothing, and it must not be able to.
		assert(
			SourceScan.contains(files, PROJECTION),
			`this assertion would pass over the {#files} file(s) the classifier returned for `
				.. `{SEATS}, and {PROJECTION} is not among them: {table.concat(files, ", ")}`
		)

		-- THAT PATH ONLY (PO-4). `Ring.luau` clones `players` legitimately, and a
		-- guard over the whole subtree fails on day one against correct code.
		local hits = SourceScan.scanFor({ PROJECTION }, BANNED)
		assert(
			#hits == 0,
			`{#hits} copy-helper reference(s) in {PROJECTION}. The projection is an allowlist `
				.. `built field by field (architecture.md D8); every leak this guard exists to `
				.. `prevent arrives through a copy:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["AC-4: the only module Projection.luau requires is ./Ring, so no copy helper arrives under another name"] = function()
		local files = SourceScan.sourceFilesIn(SEATS)
		assert(
			SourceScan.contains(files, PROJECTION),
			`this assertion would pass over the {#files} file(s) the classifier returned for `
				.. `{SEATS}, and {PROJECTION} is not among them: {table.concat(files, ", ")}`
		)

		local fs = require("@lune/fs")
		local text = fs.readFile(PROJECTION)
		local requires = SourceScan.scanFor({ PROJECTION }, { "require" })
		local ringRequires = select(2, string.gsub(text, 'require%(%s*"%./Ring"%s*%)', ""))
			+ select(2, string.gsub(text, "require%(%s*'%./Ring'%s*%)", ""))
		assert(
			#requires >= 1,
			`{PROJECTION} requires nothing; PO-1 says it reads Ring.PlayerId, Ring.KeyClass and `
				.. `Ring.Assignment through require("./Ring")`
		)
		assert(
			#requires == ringRequires,
			`{PROJECTION} has {#requires} require(s) but {ringRequires} of them are require("./Ring"). `
				.. `The types come from Ring and the ring relations come from Ring; nothing else is `
				.. `needed, and a helper required here is a copy helper the flat ban cannot see:\n`
				.. SourceScan.describeHits(requires)
		)
	end,

	--[[ AC-5 ]]

	["AC-5: a player not in the assignment is refused by Projection itself - the error names the module and the player, is not Ring's, and blames the caller"] = function()
		Contract.unknownPlayerIsRefusedByProjectionItself(Projection())
	end,

	--[[ AC-6 ]]

	["AC-6: for every pair of players, neither view carries the other's key class or σ in any form - as a map, a string, or the ring order"] = function()
		Contract.pairwiseViewsRevealNothingOfEachOther(Projection())
	end,

	--[[ The naive test, applied to the real module too, so that the controls
	     file's "the copy passes this" is a statement about a check the real
	     projection is also held to. ]]

	["naive: the view has no sigma key and has a keyClass key"] = function()
		Contract.naiveFieldPresence(Projection())
	end,
}
