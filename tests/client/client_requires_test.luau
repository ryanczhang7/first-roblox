--!strict
--[[
	THEME-001, Contract C-8: client source requires `@game/ReplicatedStorage/Shared/…`
	and its own layer only.

	SLICE-008's `layer_requires_test.luau` already refuses a require that
	leaves its layer by any path other than `@game/ReplicatedStorage/Shared/`
	or `@game/ReplicatedStorage/Net/`. C-8 is narrower for the client: the net
	layer "is not needed until SLICE-002, and this story does not need it".
	This guard pins that narrowing over `src/client/**`, using the same
	`LayerRequires.requiresIn` lexer and the same `classify.sh` file list, so
	a require quoted in a comment is not a require here either.

	THE RULE, per require string in a client module:
	  `./…`, `../…`                          stay in the layer: permitted
	  `@self`, `@self/…`                     permitted
	  `@game/ReplicatedStorage/Shared/…`     permitted (C-8)
	  anything else                          a violation, named

	In RED `src/client/` holds only SLICE-008's probe, which `classify.sh`
	classifies as `test` and `sourceFilesIn` therefore does not return. So the
	vacuity assertion - at least the three modules the Contract names - is red
	until GREEN writes them, and that is the right failure.

	The negative control is in-memory: the rule over a module text that
	requires `@game/ReplicatedStorage/Net/Wrapper` and one that requires
	`@game/ServerScriptService/Server/round/PhaseMachine` names both.
]]

local LayerRequires = require("../helpers/LayerRequires")
local SourceScan = require("../helpers/SourceScan")
local fs = require("../helpers/GatedFs")

local CLIENT = "src/client"
local SHARED_PREFIX = LayerRequires.SHARED_PREFIX

local EXPECTED = {
	"src/client/Theme.luau",
	"src/client/models/ScreenScale.luau",
	"src/client/models/ColourMath.luau",
}

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- The C-8 rule. Nil when permitted, otherwise the reason.
local function reasonFor(target: string): string?
	if startsWith(target, "./") or startsWith(target, "../") then
		return nil
	end
	if target == "@self" or startsWith(target, "@self/") then
		return nil
	end
	if startsWith(target, SHARED_PREFIX) then
		return nil
	end
	return `a client require that leaves its layer must begin {SHARED_PREFIX} (C-8)`
end

local function violationsIn(path: string, text: string): { string }
	local out: { string } = {}
	for _, req in LayerRequires.requiresIn(text) do
		local reason = reasonFor(req.target)
		if reason ~= nil then
			table.insert(out, `{path}:{req.line}: require("{req.target}") - {reason}`)
		end
	end
	return out
end

return {
	["C-8: every module under src/client/ requires only its own layer or @game/ReplicatedStorage/Shared/…, and the three Contract modules are among those scanned"] = function()
		-- Modules only: the directory also holds a `.gitkeep`, which the
		-- classifier returns as source and which has no requires to judge.
		local files: { string } = {}
		for _, path in SourceScan.sourceFilesIn(CLIENT) do
			if string.sub(path, -5) == ".luau" then
				table.insert(files, path)
			end
		end
		local missing: { string } = {}
		for _, path in EXPECTED do
			if not SourceScan.contains(files, path) then
				table.insert(missing, path)
			end
		end
		assert(
			#missing == 0,
			`{#missing} Contract module(s) are not in the scanned set (classify.sh --list source {CLIENT} returned {#files} file(s)):\n  `
				.. table.concat(missing, "\n  ")
		)
		local violations: { string } = {}
		for _, path in files do
			for _, v in violationsIn(path, fs.readFile(path)) do
				table.insert(violations, v)
			end
		end
		assert(
			#violations == 0,
			`{#violations} client require(s) leave the layer other than through Shared, over {#files} file(s):\n  `
				.. table.concat(violations, "\n  ")
		)
	end,

	["C-8 control: the rule names a Net require and a ServerScriptService require in a client module, and permits a relative one and a Shared one"] = function()
		local text = table.concat({
			"--!strict",
			'local Wrapper = require("@game/ReplicatedStorage/Net/Wrapper")',
			'local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")',
			'local Presets = require("@game/ReplicatedStorage/Shared/channel/Presets")',
			'local ColourMath = require("./models/ColourMath")',
			'-- require("@game/ServerScriptService/Server/round/Quoted") in a comment',
			"return { Wrapper, PhaseMachine, Presets, ColourMath }",
		}, "\n")
		local violations = violationsIn("src/client/__in_memory.luau", text)
		assert(
			#violations == 2,
			`expected 2 violations, got {#violations}:\n{table.concat(violations, "\n")}`
		)
		assert(
			string.find(
				violations[1],
				':2: require("@game/ReplicatedStorage/Net/Wrapper")',
				1,
				true
			) ~= nil,
			violations[1]
		)
		assert(
			string.find(
				violations[2],
				':3: require("@game/ServerScriptService/Server/round/PhaseMachine")',
				1,
				true
			) ~= nil,
			violations[2]
		)
	end,
}
