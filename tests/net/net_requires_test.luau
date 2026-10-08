--!strict
--[[
	SLICE-002 AC-7: `.luaurc` still declares exactly one alias, `game` ->
	`src`, and every require of the net layer from `src/server` or
	`src/client` begins `@game/ReplicatedStorage/Net/`.

	WHAT SLICE-008's `tests/shared/layer_requires_test.luau` ALREADY PINS, and
	what it does not. It reads `.luaurc` and asserts the one alias (its AC-2),
	and it refuses any `@…` crossing that is not `@game/ReplicatedStorage/
	Shared/` or `@game/ReplicatedStorage/Net/` (its AC-3). But its rule treats
	every `./` and `../` require as "stays inside the layer" - so a
	`require("../../ReplicatedStorage/Net/Wrapper")` from `src/server/` passes
	it while reaching the net layer by a spelling AC-7 forbids. This file
	pins THAT: a require that reaches the net layer by any spelling must begin
	the exact prefix. The alias assertion is repeated here, through
	`GatedFs`, because the story says AC-7's test reads `.luaurc`; it is one
	assertion and it names the alias it found.

	TODAY NO MODULE UNDER src/server OR src/client REQUIRES THE NET LAYER AT
	ALL (`rg 'Net/' src/server src/client` at RED: nothing) - the driver that
	does is SLICE-004's. So the tree assertion is green on arrival and is
	earned two ways: the in-memory controls below apply the rule to modules
	written to break it, and the story's `## Handoff` records a
	`scripts/mutate.sh` probe that rewrote a real server require to the
	relative spelling and watched this file's tree assertion go red naming
	the file and the require.

	THE FILE LIST COMES FROM `scripts/classify.sh` through `SourceScan`, and
	every file is read through `GatedFs`, never `@lune/fs`.
]]

local fs = require("../helpers/GatedFs")
local LayerRequires = require("../helpers/LayerRequires")
local SourceScan = require("../helpers/SourceScan")
local serde = require("@lune/serde")

local NET_PREFIX = "@game/ReplicatedStorage/Net/"

-- Modules the scanned set must contain, so "zero violations" is a claim
-- about a tree with server and client code in it.
local EXPECTED_IN_SET: { string } = {
	"src/server/round/PhaseMachine.luau",
	"src/server/channel/Pings.luau",
}

type Violation = { path: string, line: number, target: string }

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- Does this require string reach the net layer by ANY spelling? The segment
-- `Net/` after `ReplicatedStorage/` or at the end of a `../` chain, or the
-- retired `@net` alias.
local function reachesNet(target: string): boolean
	if startsWith(target, "@net/") or target == "@net" then
		return true
	end
	if string.find(target, "ReplicatedStorage/Net/", 1, true) ~= nil then
		return true
	end
	-- `../../Net/X`, `../Net/X`, `src/Net/X`: a `Net/` segment reached by a path.
	if string.match(target, "^[%./]*Net/") ~= nil or string.match(target, "/Net/") ~= nil then
		return true
	end
	return false
end

-- The AC-7 rule on one module's text: every require that reaches the net
-- layer must begin the exact prefix.
local function violationsIn(path: string, text: string): { Violation }
	local out: { Violation } = {}
	for _, req in LayerRequires.requiresIn(text) do
		if reachesNet(req.target) and not startsWith(req.target, NET_PREFIX) then
			table.insert(out, { path = path, line = req.line, target = req.target })
		end
	end
	return out
end

local function describe(violations: { Violation }): string
	local lines: { string } = {}
	for _, v in violations do
		table.insert(lines, `{v.path}:{v.line} requires "{v.target}"; it must begin {NET_PREFIX}`)
	end
	return table.concat(lines, "\n")
end

local function serverAndClientFiles(): { string }
	local out: { string } = SourceScan.sourceFilesIn("src/server")
	for _, path in SourceScan.sourceFilesIn("src/client") do
		table.insert(out, path)
	end
	return out
end

return {
	--[[ The alias ]]

	["AC-7: .luaurc, read through GatedFs, declares exactly one alias and it is game -> src"] = function()
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
			`.luaurc must alias exactly "game" and nothing else; it aliases: {table.concat(
				names,
				", "
			)}`
		)
		assert(
			(aliases :: { [string]: any }).game == "src",
			`.luaurc aliases game -> {tostring((aliases :: { [string]: any }).game)}, not src`
		)
	end,

	--[[ The tree ]]

	["AC-7: every require from src/server or src/client that reaches the net layer begins @game/ReplicatedStorage/Net/"] = function()
		local files = serverAndClientFiles()
		assert(
			#files >= 4,
			`scanned {#files} file(s) under src/server and src/client; a guard over nothing passes`
		)
		for _, path in EXPECTED_IN_SET do
			assert(
				SourceScan.contains(files, path),
				`{path} is not in the scanned set: {table.concat(files, ", ")}`
			)
		end
		local violations: { Violation } = {}
		for _, path in files do
			for _, v in violationsIn(path, fs.readFile(path)) do
				table.insert(violations, v)
			end
		end
		assert(
			#violations == 0,
			`{#violations} net-layer require(s) over {#files} file(s) do not begin {NET_PREFIX}:\n`
				.. describe(violations)
		)
	end,

	--[[ The rule's own discrimination, on modules written to break it ]]

	["AC-7 control: the rule reports a relative, an @net and a bare-path spelling of a net require, by file, line and require, and accepts the @game spelling and a Shared require"] = function()
		local text = table.concat({
			"--!strict",
			'local Wrapper = require("../../ReplicatedStorage/Net/Wrapper")',
			'local Remotes = require("@net/Remotes")',
			'local Clock = require("@game/ReplicatedStorage/Shared/Clock")',
			'local Transport = require("@game/ReplicatedStorage/Net/Transport")',
			'local Schema = require("../Net/Schema")',
			'local Limiter = require("src/ReplicatedStorage/Net/RateLimiter")',
			'-- local Old = require("../../ReplicatedStorage/Net/Old") in a comment',
			"return { Wrapper, Remotes, Clock, Transport, Schema, Limiter }",
		}, "\n")
		local violations = violationsIn("src/server/Leaky.luau", text)
		assert(
			#violations == 4,
			`expected 4 violations (lines 2, 3, 6, 7), got {#violations}:\n{describe(violations)}`
		)
		local expected = {
			{ line = 2, target = "../../ReplicatedStorage/Net/Wrapper" },
			{ line = 3, target = "@net/Remotes" },
			{ line = 6, target = "../Net/Schema" },
			{ line = 7, target = "src/ReplicatedStorage/Net/RateLimiter" },
		}
		for i, want in expected do
			local got = violations[i]
			assert(
				got.path == "src/server/Leaky.luau"
					and got.line == want.line
					and got.target == want.target,
				`violation {i} is {got.path}:{got.line} "{got.target}"; expected line {want.line} "{want.target}"`
			)
		end
		local message = describe(violations)
		assert(
			string.find(
				message,
				'src/server/Leaky.luau:2 requires "../../ReplicatedStorage/Net/Wrapper"',
				1,
				true
			) ~= nil,
			`the rendered failure does not name the file, line and require:\n{message}`
		)
	end,

	["AC-7 control: a module whose only crossings are the @game spelling has no violations"] = function()
		local text = table.concat({
			'local Wrapper = require("@game/ReplicatedStorage/Net/Wrapper")',
			'local Clock = require("@game/ReplicatedStorage/Shared/Clock")',
			'local Sibling = require("./Sibling")',
			"return { Wrapper, Clock, Sibling }",
		}, "\n")
		local violations = violationsIn("src/client/Clean.luau", text)
		assert(#violations == 0, `a clean module produced violations:\n{describe(violations)}`)
	end,
}
