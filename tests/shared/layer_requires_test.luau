--!strict
--[[
	SLICE-008 AC-1, AC-2 and AC-3: the shared layers live under the DataModel
	path, `.luaurc` aliases `@game` and nothing else, and a string require that
	leaves its layer begins `@game/ReplicatedStorage/`.

	AC-1 - over every source and test module, no string require begins
	`@shared` or `@net`, and `src/shared` and `src/net` no longer exist.
	AC-2 - `.luaurc` declares exactly one alias, `game` -> `src`.
	AC-3 - a string require in `src/` that leaves its own layer begins
	`@game/ReplicatedStorage/`; the refusal names the file and the require.

	The file lists come from `scripts/classify.sh` through
	`tests/helpers/SourceScan.luau`, never from a walk of my own, and every
	file is read through `tests/helpers/GatedFs.luau` so that a file this
	guard's verdict depends on is in the gate tree hash. The rule itself is
	`tests/helpers/LayerRequires.luau`; `layer_requires_controls_test.luau`
	applies it to in-memory modules written to break it, so that "zero
	violations" here is a statement about the tree and not about the rule.

	In RED, before GREEN moves the directories: AC-1 fails because 32
	requires still begin `@shared` and `src/shared` still exists; AC-2 fails
	because `.luaurc` still aliases `shared`; AC-3 fails because every one of
	those `@shared` requires is an `@…` the rule does not permit. The
	vacuity assertions fail because the moved modules are not yet at their
	paths. That is the right failure for a move that has not happened.
]]

local fs = require("../helpers/GatedFs")
local LayerRequires = require("../helpers/LayerRequires")
local SourceScan = require("../helpers/SourceScan")
local serde = require("@lune/serde")

local PROBE = "src/client/__probe_cross_layer.luau"
local PROBE_REQUIRE = "@game/ServerScriptService/Server/round/PhaseMachine"

-- The two moved layers, one module from each, so that "zero violations" is a
-- claim about a tree that contains them.
local MOVED_SHARED = "src/ReplicatedStorage/Shared/Clock.luau"
local MOVED_NET = "src/ReplicatedStorage/Net/Wrapper.luau"
-- A module that crosses into shared, so the scan has a crossing to judge.
local CROSSING = "src/server/round/RoundView.luau"

local function concatLists(a: { string }, b: { string }): { string }
	local out: { string } = table.clone(a)
	for _, item in b do
		table.insert(out, item)
	end
	return out
end

-- Every file the harness classifies as `test` under the two test roots.
local function testFiles(): { string }
	return concatLists(
		SourceScan.classifierList("test", "tests"),
		SourceScan.classifierList("test", "lune")
	)
end

return {
	--[[ AC-1 ]]

	["AC-1: no source or test module requires @shared or @net"] = function()
		local sources = SourceScan.sourceFiles()
		local tests = testFiles()
		assert(#sources >= 4, `scanned {#sources} source file(s); a guard over nothing passes`)
		assert(#tests >= 4, `scanned {#tests} test file(s); a guard over nothing passes`)

		local hits = LayerRequires.retiredAliasesIn(concatLists(sources, tests), fs.readFile)
		assert(
			#hits == 0,
			`{#hits} require(s) still use a retired alias, over {#sources + #tests} file(s):\n`
				.. LayerRequires.describe(hits)
		)
	end,

	["AC-1: src/shared and src/net no longer exist"] = function()
		assert(
			not fs.isDir("src/shared"),
			"src/shared still exists; it moves to src/ReplicatedStorage/Shared"
		)
		assert(
			not fs.isDir("src/net"),
			"src/net still exists; it moves to src/ReplicatedStorage/Net"
		)
		assert(
			not fs.isFile("src/shared/Clock.luau"),
			"src/shared/Clock.luau still exists at the old path"
		)
	end,

	["AC-1: the moved layers are where the DataModel path says, and the scan sees them"] = function()
		local sources = SourceScan.sourceFiles()
		assert(
			SourceScan.contains(sources, MOVED_SHARED),
			`{MOVED_SHARED} is not in the scanned set: {table.concat(sources, ", ")}`
		)
		assert(
			SourceScan.contains(sources, MOVED_NET),
			`{MOVED_NET} is not in the scanned set: {table.concat(sources, ", ")}`
		)
		assert(
			SourceScan.contains(sources, CROSSING),
			`{CROSSING} is not in the scanned set: {table.concat(sources, ", ")}`
		)
	end,

	--[[ AC-2 ]]

	["AC-2: .luaurc declares exactly one alias, game -> src"] = function()
		local text = fs.readFile(".luaurc")
		local parsed = serde.decode("json", text) :: { [string]: any }
		local aliases = parsed.aliases
		assert(typeof(aliases) == "table", `.luaurc has no "aliases" table; it reads:\n{text}`)

		local names: { string } = {}
		for name in pairs(aliases :: { [string]: any }) do
			table.insert(names, name :: string)
		end
		table.sort(names)

		assert(
			#names == 1 and names[1] == "game",
			`.luaurc must alias exactly "game"; it aliases: {table.concat(names, ", ")}`
		)
		assert(
			(aliases :: { [string]: any }).game == "src",
			`.luaurc aliases game -> {tostring((aliases :: { [string]: any }).game)}, not src`
		)
	end,

	--[[ AC-3 ]]

	["AC-3: no source module holds a string require that leaves its layer outside @game/ReplicatedStorage/"] = function()
		local sources = SourceScan.sourceFiles()
		assert(#sources >= 4, `scanned {#sources} source file(s); a guard over nothing passes`)
		assert(
			SourceScan.contains(sources, CROSSING),
			`{CROSSING} is not in the scanned set, so the scan has no crossing to judge`
		)

		local violations = LayerRequires.scan(sources, fs.readFile)
		assert(
			#violations == 0,
			`{#violations} layer-crossing violation(s) over {#sources} source file(s):\n`
				.. LayerRequires.describe(violations)
		)
	end,

	["AC-3: every scanned source module is in a layer the rule knows"] = function()
		local unplaced: { string } = {}
		for _, path in SourceScan.sourceFiles() do
			if LayerRequires.layerOf(path) == nil then
				table.insert(unplaced, path)
			end
		end
		assert(
			#unplaced == 0,
			`{#unplaced} source file(s) are in no layer, so the rule is not checking them:\n`
				.. table.concat(unplaced, "\n")
		)
	end,

	--[[ AC-3, the negative control. This is the assertion that gives the one
	     above its meaning: the same scan, over the same tree plus the probe,
	     must report the probe by file and by require. ]]

	["AC-3 control: the client probe's @game/ServerScriptService require is reported by file and by require"] = function()
		local probes = SourceScan.nonSourceFilesUnderSrc()
		assert(
			SourceScan.contains(probes, PROBE),
			`{PROBE} is missing, or the harness no longer classifies it as a test; `
				.. `without it AC-3 has no negative control. classify.sh --list test src said: `
				.. `{table.concat(probes, ", ")}`
		)

		-- Deliberately the WRONG list: source plus the probes the normal
		-- assertion excludes. Anything other than a hit here means the
		-- scanner, not the tree, is what is clean.
		local violations =
			LayerRequires.scan(concatLists(SourceScan.sourceFiles(), probes), fs.readFile)
		assert(
			#violations > 0,
			`the scanner found nothing in {PROBE}, which requires {PROBE_REQUIRE}`
		)

		local atProbe = 0
		for _, v in violations do
			if v.path == PROBE then
				atProbe += 1
				assert(
					v.target == PROBE_REQUIRE,
					`{PROBE} was reported for "{v.target}", not for {PROBE_REQUIRE}`
				)
				assert(v.layer == "client", `{PROBE} was placed in layer {v.layer}, not client`)
			end
		end
		assert(
			atProbe == 1,
			`{PROBE} must be reported exactly once (its one require); it was reported {atProbe} time(s):\n`
				.. LayerRequires.describe(violations)
		)

		local message = LayerRequires.describe(violations)
		assert(
			string.find(message, PROBE, 1, true) ~= nil,
			"the rendered failure message does not contain the offending path"
		)
		assert(
			string.find(message, PROBE_REQUIRE, 1, true) ~= nil,
			"the rendered failure message does not contain the offending require"
		)
	end,

	["AC-3 control: the probe is not in the source set the guard asserts over"] = function()
		local sources = SourceScan.sourceFiles()
		assert(
			not SourceScan.contains(sources, PROBE),
			`{PROBE} is in the scanned set; AC-3 is asserting a real property over a file `
				.. `written to violate it`
		)
	end,
}
