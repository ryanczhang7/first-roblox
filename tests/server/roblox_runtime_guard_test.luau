--!strict
--[[
	The second half of ROUND-003 AC-8: "and no Roblox runtime was required at any
	point".

	The lifecycle test in `phase_machine_test.luau` runs under Lune, which has no
	Roblox runtime at all - so "the test passed" is weak evidence for this clause
	and no evidence at all for the module. A machine that reached for
	`RunService` would not even load here, and one that reached for it down a
	branch the lifecycle does not take would load fine and ship. What AC-8 is
	actually about is the MODULE: `src/server/round/**` is pure, and stays pure
	after this story.

	So the assertion is textual, over the story's own source modules, and it pins
	THE SHAPE OF THE CODE rather than the behaviour of one run. That is the
	honest description of what it can do, and it is the right instrument here
	rather than a weaker substitute for a test: the thing it rules out - a
	Roblox-only call on an untaken branch - is by construction not reachable from
	any test this repository can run.

	THE FILE LIST COMES FROM `scripts/classify.sh`, through
	`tests/helpers/SourceScan.luau`, never from a glob or a directory walk of my
	own. `.claude/harness/rules.md` explains at length why: four private copies
	of that question in one project drifted apart and spent six stories asserting
	real properties over files written deliberately to violate a rule. The
	matching is `SourceScan.hitsIn`, the same matcher ROUND-001's AC-5 guard uses,
	for the same reason one level down.

	WHAT THIS CANNOT SEE, stated so the next reader does not assume otherwise:
	the scan is textual over code with comments and string literals blanked out.
	`game["GetService"]` and `getfenv().workspace` are invisible to it. It catches
	the way the call is actually written.
]]

local SourceScan = require("../helpers/SourceScan")

local ROUND = "src/server/round"
local PHASE_MACHINE = "src/server/round/PhaseMachine.luau"
local ROUND_CONFIG = "src/server/round/RoundConfig.luau"

-- The Roblox runtime surface a pure phase machine must not touch. `task.wait`
-- is here as well as in ROUND-001's time rules: it is both a real time source
-- and a Roblox scheduler call, and this guard is about the second.
local ROBLOX: { string } = {
	"game",
	"workspace",
	"Instance.new",
	"RunService",
	"task.wait",
	"script",
}

-- ROUND-001's committed probe, which calls `os.clock()`. Used below to prove the
-- guard's file-reading path finds a real call in a real file.
local CLOCK_PROBE = "src/shared/__probe_clock_leak.luau"

return {
	--[[
		The vacuity guard, and it is not optional. A scan over an empty file list
		passes, and `src/server/round/` does not exist yet - so without this, AC-8's
		textual half would be satisfied by a directory that was never created.
		In RED this is the failure that names the missing modules.
	]]
	["AC-8: the guard scans this story's two round modules"] = function()
		local files = SourceScan.sourceFilesIn(ROUND)
		assert(
			#files >= 2,
			`the guard scanned {#files} file(s) under {ROUND}; a guard over nothing passes. `
				.. `classify.sh --list source {ROUND} said: {table.concat(files, ", ")}`
		)
		assert(
			SourceScan.contains(files, PHASE_MACHINE),
			`{PHASE_MACHINE} is not in the scanned set: {table.concat(files, ", ")}`
		)
		assert(
			SourceScan.contains(files, ROUND_CONFIG),
			`{ROUND_CONFIG} is not in the scanned set: {table.concat(files, ", ")}`
		)
	end,

	["AC-8: no module under src/server/round references a Roblox runtime global"] = function()
		local files = SourceScan.sourceFilesIn(ROUND)
		-- The same vacuity check as the test above, repeated here rather than
		-- trusted from there: a clean scan over an empty list is the one way this
		-- assertion can pass while proving nothing, and it must not be able to.
		assert(
			SourceScan.contains(files, PHASE_MACHINE) and SourceScan.contains(files, ROUND_CONFIG),
			`this assertion would pass over the {#files} file(s) the classifier returned for `
				.. `{ROUND}, and neither of the story's modules is among them: `
				.. `{table.concat(files, ", ")}`
		)

		local hits = SourceScan.scanFor(files, ROBLOX)
		assert(
			#hits == 0,
			`{#hits} Roblox-runtime reference(s) across {#files} scanned file(s). The round `
				.. `phase machine is pure and needs no Roblox runtime at any point:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	--[[
		The controls. Each of these needs no production code, so they run in RED -
		which is the only phase in which the two assertions above cannot both
		mean anything.
	]]

	["control: the guard fires on every Roblox runtime call in the list, and names the line"] = function()
		local text = table.concat({
			"--!strict",
			'local service = game:GetService("RunService")',
			'local part = Instance.new("Part")',
			"part.Parent = workspace",
			"local heartbeat = RunService.Heartbeat",
			"task.wait(1)",
			"return script.Parent",
		}, "\n")

		local hits = SourceScan.hitsIn("src/server/round/Leaky.luau", text, ROBLOX)
		local found: { [string]: boolean } = {}
		for _, hit in hits do
			found[hit.symbol] = true
		end

		local missing: { string } = {}
		for _, symbol in ROBLOX do
			if not found[symbol] then
				table.insert(missing, symbol)
			end
		end

		assert(
			#missing == 0,
			`the guard did not fire on {table.concat(missing, ", ")}. It saw:\n`
				.. SourceScan.describeHits(hits)
		)
		assert(
			string.find(SourceScan.describeHits(hits), "src/server/round/Leaky.luau", 1, true)
				~= nil,
			`the rendered failure does not name the offending path:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["control: the guard does not fire on these symbols in comments or string literals"] = function()
		local text = table.concat({
			"--!strict",
			"--[[ this module touches no game, no workspace and no Instance.new ]]",
			"-- it never calls RunService, task.wait or script",
			'local note = "no game, no workspace, no Instance.new, no RunService here"',
			"return note",
		}, "\n")

		local hits = SourceScan.hitsIn("src/server/round/Doc.luau", text, ROBLOX)
		assert(
			#hits == 0,
			`a doc comment and a string literal produced findings:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["control: the guard does not fire on identifiers or fields that merely contain a symbol"] = function()
		local text = table.concat({
			"local gamepad = 1",
			"local scripted = true",
			"local subworkspace = 2",
			"local self = { script = 3, game = 4 }",
			"return gamepad + subworkspace + self.script + self.game + (if scripted then 0 else 1)",
		}, "\n")

		local hits = SourceScan.hitsIn("src/server/round/Words.luau", text, ROBLOX)
		assert(
			#hits == 0,
			`word boundaries are wrong for the Roblox symbol list:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	--[[
		The file-reading half. Everything above tests the matcher against text
		held in memory; the assertions this guard actually makes read files off
		disk through the classifier's list, and that path has to be shown to find
		something. ROUND-001's committed probe is a real file with a real call in
		it, so it is the negative control this guard can borrow rather than write.
	]]
	["control: the guard's file-reading path finds a real call in a real file on disk"] = function()
		local probes = SourceScan.nonSourceFilesUnderSrc()
		assert(
			SourceScan.contains(probes, CLOCK_PROBE),
			`{CLOCK_PROBE} is missing, or the harness no longer classifies it as a test; `
				.. `without it this guard has no on-disk control. classify.sh --list test src `
				.. `said: {table.concat(probes, ", ")}`
		)

		local hits = SourceScan.scanFor({ CLOCK_PROBE }, { "os.clock" })
		assert(
			#hits > 0,
			`scanFor read {CLOCK_PROBE} and found no os.clock call in it, so a clean scan over `
				.. `src/server/round proves nothing`
		)
		assert(
			hits[1].path == CLOCK_PROBE,
			`the hit names {hits[1].path} rather than the file it was read from`
		)
	end,
}
