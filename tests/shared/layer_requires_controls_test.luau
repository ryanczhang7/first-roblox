--!strict
--[[
	The negative and positive controls for SLICE-008 AC-1 and AC-3, on
	in-memory modules.

	`layer_requires_test.luau` asserts zero violations over the real tree. A
	rule that permits everything satisfies that forever, and a rule that
	refuses everything is deleted within a story - so this file is where the
	rule is shown to discriminate, one case per clause of `## Contract` C-4,
	in both directions: the crossings the story permits PASS, and each
	crossing it forbids is refused with a message naming the file and the
	require.

	Every module here is text, written as a string literal, so that the
	require inside it is data to the lexer and not a require of this file.
	Nothing here needs production code, which is why these run in RED while
	the sibling guard fails for want of the moved tree.
]]

local LayerRequires = require("../helpers/LayerRequires")

local function module(lines: { string }): string
	return table.concat(lines, "\n")
end

local function violationsFor(path: string, lines: { string }): { LayerRequires.Violation }
	return LayerRequires.violationsIn(path, module(lines))
end

local function assertClean(path: string, lines: { string }, what: string)
	local violations = violationsFor(path, lines)
	assert(
		#violations == 0,
		`{what}: expected no violations from {path}, got {#violations}:\n`
			.. LayerRequires.describe(violations)
	)
end

-- One violation, naming exactly `target`, and the rendered message carries
-- both the path and the require - AC-3's two halves of "names the file and
-- the require".
local function assertRefused(path: string, lines: { string }, target: string, what: string)
	local violations = violationsFor(path, lines)
	assert(
		#violations == 1,
		`{what}: expected exactly 1 violation from {path}, got {#violations}:\n`
			.. LayerRequires.describe(violations)
	)
	assert(
		violations[1].target == target,
		`{what}: expected the refusal to name "{target}", it named "{violations[1].target}"`
	)
	assert(violations[1].path == path, `{what}: the refusal names {violations[1].path}, not {path}`)
	local message = LayerRequires.describe(violations)
	assert(
		string.find(message, path, 1, true) ~= nil,
		`{what}: the rendered refusal does not name the file:\n{message}`
	)
	assert(
		string.find(message, target, 1, true) ~= nil,
		`{what}: the rendered refusal does not name the require:\n{message}`
	)
end

local SERVER = "src/server/facility/Layout.luau"
local CLIENT = "src/client/Hud.luau"
local SHARED = "src/ReplicatedStorage/Shared/Rng.luau"
local NET = "src/ReplicatedStorage/Net/Wrapper.luau"

return {
	--[[ The layers, read from the path. ]]

	["layerOf places the four layers by path and nothing else"] = function()
		assert(LayerRequires.layerOf(SHARED) == "shared", "shared")
		assert(
			LayerRequires.layerOf("src/ReplicatedStorage/Shared/channel/Presets.luau") == "shared",
			"nested shared"
		)
		assert(LayerRequires.layerOf(NET) == "net", "net")
		assert(LayerRequires.layerOf(SERVER) == "server", "server")
		assert(LayerRequires.layerOf(CLIENT) == "client", "client")
		assert(
			LayerRequires.layerOf("src/shared/Rng.luau") == nil,
			"the OLD shared path is in no layer"
		)
		assert(
			LayerRequires.layerOf("src/net/Wrapper.luau") == nil,
			"the OLD net path is in no layer"
		)
		assert(
			LayerRequires.layerOf("src/Stray.luau") == nil,
			"a file directly under src is in no layer"
		)
		assert(LayerRequires.layerOf("tests/server/x_test.luau") == nil, "a test is in no layer")
	end,

	--[[ Positive controls: what the story permits must PASS. A guard that
	     rejects everything is broken. ]]

	["permits: a server module crossing into shared and net through @game, and staying put with ./ and ../"] = function()
		assertClean(SERVER, {
			"--!strict",
			'local Rng = require("@game/ReplicatedStorage/Shared/Rng")',
			'local Tuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")',
			'local Event = require("@game/ReplicatedStorage/Shared/telemetry/Event")',
			'local Remotes = require("@game/ReplicatedStorage/Net/GameRemotes")',
			'local Steps = require("./Steps")',
			'local Ring = require("../seats/Ring")',
			"return { Rng, Tuning, Event, Remotes, Steps, Ring }",
		}, "C-2's spelling and C-4's same-layer requires")
	end,

	["permits: a client module crossing into shared and net through @game"] = function()
		assertClean(CLIENT, {
			'local Clock = require("@game/ReplicatedStorage/Shared/Clock")',
			'local Remotes = require("@game/ReplicatedStorage/Net/GameRemotes")',
			'local Panel = require("./Panel")',
			"return { Clock, Remotes, Panel }",
		}, "a client reaching shared and net")
	end,

	["permits: net may require shared"] = function()
		assertClean(NET, {
			'local Event = require("@game/ReplicatedStorage/Shared/telemetry/Event")',
			'local Schema = require("./Schema")',
			"return { Event, Schema }",
		}, "net -> shared")
	end,

	["permits: shared requiring inside itself, relatively"] = function()
		assertClean(SHARED, {
			'local Event = require("./telemetry/Event")',
			'local Clock = require("../Shared/Clock")',
			"return { Event, Clock }",
		}, "shared -> shared")
	end,

	["permits: @self"] = function()
		assertClean(SERVER, {
			'local here = require("@self")',
			'local child = require("@self/Child")',
			"return { here, child }",
		}, "@self")
	end,

	["permits: a module with no requires at all"] = function()
		assertClean(SHARED, { "--!strict", "return {}" }, "no requires")
	end,

	--[[ Negative controls, one per forbidden crossing. ]]

	["refuses: a client module requiring @game/ServerScriptService/... (AC-3's named case)"] = function()
		assertRefused(CLIENT, {
			'local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")',
			"return PhaseMachine",
		}, "@game/ServerScriptService/Server/round/PhaseMachine", "client -> server")
	end,

	["refuses: a server module requiring @game/StarterPlayer/..."] = function()
		assertRefused(SERVER, {
			'local Hud = require("@game/StarterPlayer/StarterPlayerScripts/Client/Hud")',
			"return Hud",
		}, "@game/StarterPlayer/StarterPlayerScripts/Client/Hud", "server -> client")
	end,

	["refuses: a server module requiring @game/ServerScriptService/... even though it is its own layer"] = function()
		assertRefused(
			SERVER,
			{
				'local Ring = require("@game/ServerScriptService/Server/seats/Ring")',
				"return Ring",
			},
			"@game/ServerScriptService/Server/seats/Ring",
			"server -> server via @game is not ./ or ../"
		)
	end,

	["refuses: a shared module requiring @game/ReplicatedStorage/Net/..."] = function()
		assertRefused(SHARED, {
			'local Remotes = require("@game/ReplicatedStorage/Net/GameRemotes")',
			"return Remotes",
		}, "@game/ReplicatedStorage/Net/GameRemotes", "shared requires nothing outside itself")
	end,

	["refuses: @shared/X itself"] = function()
		assertRefused(SERVER, {
			'local Rng = require("@shared/Rng")',
			"return Rng",
		}, "@shared/Rng", "the retired alias")
	end,

	["refuses: @net/X itself"] = function()
		assertRefused(CLIENT, {
			'local Remotes = require("@net/GameRemotes")',
			"return Remotes",
		}, "@net/GameRemotes", "the retired alias")
	end,

	["refuses: @game/ReplicatedStorage/<anything but Shared or Net>"] = function()
		assertRefused(SERVER, {
			'local Other = require("@game/ReplicatedStorage/Packages/Promise")',
			"return Other",
		}, "@game/ReplicatedStorage/Packages/Promise", "C-4 names exactly two crossings")
	end,

	["refuses: @game/ReplicatedStorage/SharedX, a prefix that only looks like the crossing"] = function()
		assertRefused(SERVER, {
			'local X = require("@game/ReplicatedStorage/SharedExtras/Thing")',
			"return X",
		}, "@game/ReplicatedStorage/SharedExtras/Thing", "the prefix ends with a slash")
	end,

	-- `@lune/net`, not the filesystem builtin: HARNESS-022's AC-7 guard flags
	-- any test file holding a literal whose whole content names that one, and
	-- the point here is the `@lune/` prefix, not which builtin.
	["refuses: @lune/... from a source module"] = function()
		assertRefused(SERVER, {
			'local net = require("@lune/net")',
			"return net",
		}, "@lune/net", "a Lune builtin does not exist in a place")
	end,

	["refuses: a bare name that is neither relative nor an alias"] = function()
		assertRefused(SERVER, {
			'local Rng = require("Rng")',
			"return Rng",
		}, "Rng", "no reader resolves a bare name the same way")
	end,

	["refuses: a require in a file the rule cannot place, and says so"] = function()
		local violations = violationsFor("src/Stray.luau", {
			'local Rng = require("./Rng")',
			"return Rng",
		})
		assert(#violations == 1, `expected 1 violation, got {#violations}`)
		assert(violations[1].layer == "(none)", `expected layer (none), got {violations[1].layer}`)
		assert(
			string.find(violations[1].reason, "no layer", 1, true) ~= nil,
			`the reason does not say the file is in no layer: {violations[1].reason}`
		)
	end,

	["reports every violation in a file, not only the first"] = function()
		local violations = violationsFor(SERVER, {
			'local A = require("@shared/Rng")',
			'local B = require("./Fine")',
			'local C = require("@game/StarterPlayer/X")',
			"return { A, B, C }",
		})
		assert(
			#violations == 2,
			`expected 2 violations, got {#violations}:\n` .. LayerRequires.describe(violations)
		)
		assert(
			violations[1].line == 1 and violations[2].line == 3,
			"lines 1 and 3 are the offenders"
		)
	end,

	--[[ AC-1's needle. ]]

	["isRetiredAlias matches @shared and @net and not the @game spellings"] = function()
		assert(LayerRequires.isRetiredAlias("@shared/Rng"), "@shared/Rng")
		assert(LayerRequires.isRetiredAlias("@net/GameRemotes"), "@net/GameRemotes")
		assert(LayerRequires.isRetiredAlias("@shared"), "bare @shared")
		assert(
			not LayerRequires.isRetiredAlias("@game/ReplicatedStorage/Shared/Rng"),
			"new shared spelling"
		)
		assert(
			not LayerRequires.isRetiredAlias("@game/ReplicatedStorage/Net/Wrapper"),
			"new net spelling"
		)
		assert(
			not LayerRequires.isRetiredAlias("../../src/ReplicatedStorage/Shared/Rng"),
			"a test's file path"
		)
		assert(not LayerRequires.isRetiredAlias("./Shared"), "a relative path")
	end,

	["retiredAliasesIn reports the @shared require with its file and line"] = function()
		local texts: { [string]: string } = {
			[SERVER] = module({ 'local Rng = require("@shared/Rng")', "return Rng" }),
			[NET] = module({
				'local Event = require("@game/ReplicatedStorage/Shared/telemetry/Event")',
				"return Event",
			}),
		}
		local hits = LayerRequires.retiredAliasesIn({ SERVER, NET }, function(path: string): string
			return texts[path]
		end)
		assert(#hits == 1, `expected 1 hit, got {#hits}:\n` .. LayerRequires.describe(hits))
		assert(
			hits[1].path == SERVER and hits[1].line == 1 and hits[1].target == "@shared/Rng",
			"names the offender"
		)
	end,

	--[[ The scanner's own discrimination. ]]

	["the scanner does not fire on a require spelled in a comment"] = function()
		assertClean(SERVER, {
			"--!strict",
			'-- every require("@shared/Rng") becomes require("@game/ReplicatedStorage/Shared/Rng")',
			"--[[ and never require('@game/ServerScriptService/Server/x') ]]",
			"return {}",
		}, "comments")
	end,

	["the scanner does not fire on a require spelled inside a string literal"] = function()
		assertClean(SERVER, {
			'local message = \'use require("@game/ReplicatedStorage/Shared/Rng") not require("@shared/Rng")\'',
			"return message",
		}, "string literals")
	end,

	["the scanner does not fire on an identifier that merely contains require"] = function()
		assertClean(SERVER, {
			'local requireAll = { "@shared/Rng" }',
			'local prerequire = function() return "@net/X" end',
			'local t = { require = "@shared/Rng" }',
			"return { requireAll, prerequire, t.require }",
		}, "word boundaries")
	end,

	["the scanner reads a single-quoted and an unparenthesised require"] = function()
		local violations = violationsFor(SERVER, {
			"local A = require('@shared/Rng')",
			'local B = require "@net/X"',
			"return { A, B }",
		})
		assert(
			#violations == 2,
			`expected 2 violations, got {#violations}:\n` .. LayerRequires.describe(violations)
		)
	end,

	["requiresIn reports the line of each require"] = function()
		local requires = LayerRequires.requiresIn(module({
			"--!strict",
			"",
			'local A = require("./A")',
			"local x = 1",
			'local B = require("../B")',
		}))
		assert(#requires == 2, `expected 2 requires, got {#requires}`)
		assert(requires[1].line == 3 and requires[1].target == "./A", "first require")
		assert(requires[2].line == 5 and requires[2].target == "../B", "second require")
	end,
}
