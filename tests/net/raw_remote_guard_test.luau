--!strict
--[[
	NET-001 AC-7: the tree-scanning guard behind B4's one enforceable rule -
	"no raw `OnServerEvent:Connect` in `src/server/`", generalised by the
	criterion to: `OnServerEvent`, `OnServerInvoke` and `.OnClientEvent`
	appear in no source module outside `src/net/`.

	THE FILE LIST COMES FROM `scripts/classify.sh`, through
	`tests/helpers/SourceScan.luau`, never from a glob or a directory walk of
	my own - `.claude/harness/rules.md` explains at length why. THE MATCHER IS
	`SourceScan.memberHitsIn`, a sibling of `hitsIn` written for this story:
	`hitsIn` rejects any match preceded by `.` or `:`, so that `self.tick` is
	not the global `tick`, and every one of AC-7's three needles is a member
	access. Measured at PLANNED and again in RED: `hitsIn` scores 0, 0, 0 on
	them. A guard built on it would report green over a tree in which every
	module connects a raw remote - the needle-that-cannot-fail failure in
	`rules.md` - which is why this file's control is not optional and why the
	scanned set's size is asserted too.

	THE CONTROL is `src/server/__probe_raw_remote.luau`, a deliberately
	offending module at the real path. `paths.conf` classifies `__probe_*` as
	`test`, so `classify.sh --list source src` never returns it and the normal
	assertion never sees it; the control scans `source + test` files together
	and requires it to be reported BY NAME.

	WHAT THIS CANNOT SEE, stated so the next reader does not assume otherwise:
	the scan is textual over code with comments and string literals blanked.
	`remote["OnServerEvent"]` and `remote[name]` are invisible to it. It
	catches the way the call is actually written.

	THREE ASSERTIONS HERE ARE RED IN RED for a reason that is not the matcher:
	`src/net/` is empty, so the three Contract modules are not yet in the
	scanned set. That is the right failure - it is the first thing the story
	requires - and it is what makes the scanned-set assertion mean something
	once they exist.
]]

local SourceScan = require("../helpers/SourceScan")

local NEEDLES: { string } = { "OnServerEvent", "OnServerInvoke", ".OnClientEvent" }

local NET_PREFIX = "src/net/"
local PROBE = "src/server/__probe_raw_remote.luau"

-- Modules the scanned set must contain: two that exist today, outside src/net/,
-- so the exemption cannot have emptied the set; and the three this story adds.
local EXISTING: { string } = {
	"src/server/round/PhaseMachine.luau",
	"src/server/seats/Ring.luau",
	"src/shared/Clock.luau",
}
local NET_MODULES: { string } = {
	"src/net/Schema.luau",
	"src/net/Remotes.luau",
	"src/net/Wrapper.luau",
}

local function isUnderNet(path: string): boolean
	return string.sub(path, 1, #NET_PREFIX) == NET_PREFIX
end

local function outsideNet(paths: { string }): { string }
	local out: { string } = {}
	for _, path in paths do
		if not isUnderNet(path) then
			table.insert(out, path)
		end
	end
	return out
end

local function concatLists(a: { string }, b: { string }): { string }
	local out: { string } = table.clone(a)
	for _, item in b do
		table.insert(out, item)
	end
	return out
end

return {
	--[[
		The vacuity guard, and it is not optional: a scan over an empty list
		passes. Naming modules is a stronger form than a count, because no five
		files satisfy it; the floor is there as well so the set cannot be five
		files and nothing else.
	]]
	["AC-7: the scanned set is the real source tree - at least six modules, including three outside src/net/ and this story's three inside it"] = function()
		local sources = SourceScan.sourceFiles()
		assert(#sources >= 6, `the guard scanned {#sources} file(s); a guard over nothing passes`)
		for _, path in EXISTING do
			assert(
				SourceScan.contains(sources, path),
				`{path} is not in the scanned set: {table.concat(sources, ", ")}`
			)
		end
		for _, path in NET_MODULES do
			assert(
				SourceScan.contains(sources, path),
				`{path} is not in the scanned set, so the guard cannot know it is the exempt layer and `
					.. `not a missing one: {table.concat(sources, ", ")}`
			)
		end
		assert(
			not SourceScan.contains(sources, PROBE),
			`{PROBE} is in the scanned set; the normal assertion would be asserting over a file `
				.. `written to violate it`
		)
	end,

	["AC-7: OnServerEvent, OnServerInvoke and .OnClientEvent appear in no source module outside src/net/"] = function()
		local sources = SourceScan.sourceFiles()
		-- The same vacuity check as above, repeated rather than trusted from
		-- there: this is the assertion that can pass while proving nothing.
		local scanned = outsideNet(sources)
		assert(
			#scanned >= 3 and SourceScan.contains(scanned, EXISTING[1]),
			`this assertion would pass over the {#scanned} file(s) outside src/net/ the classifier `
				.. `returned, and {EXISTING[1]} is not among them: {table.concat(scanned, ", ")}`
		)
		local exempt = #sources - #scanned
		assert(
			exempt >= #NET_MODULES,
			`only {exempt} file(s) under src/net/ were exempted; the wrapper layer is the one place `
				.. `these names may appear and it must be in the tree`
		)

		local hits = SourceScan.scanForMembers(scanned, NEEDLES)
		assert(
			#hits == 0,
			`{#hits} raw-remote reference(s) across {#scanned} scanned file(s) outside src/net/. `
				.. `B4: every remote goes through the wrapper in src/net/:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	--[[
		The control the criterion names. Deliberately the WRONG list: source
		plus the probes the normal assertion excludes. Anything other than a hit
		naming the probe means the scanner, not the tree, is what is clean.
	]]
	["AC-7 control: the probe module's OnServerEvent is found through the classifier's list and named in the failure"] = function()
		local probes = SourceScan.nonSourceFilesUnderSrc()
		assert(
			SourceScan.contains(probes, PROBE),
			`{PROBE} is missing, or the harness no longer classifies it as a test; without it AC-7 `
				.. `has no negative control. classify.sh --list test src said: {table.concat(
					probes,
					", "
				)}`
		)

		local hits = SourceScan.scanForMembers(
			concatLists(outsideNet(SourceScan.sourceFiles()), probes),
			NEEDLES
		)
		assert(#hits > 0, `the scanner found nothing in {PROBE}, which connects OnServerEvent`)

		local found: { [string]: boolean } = {}
		for _, hit in hits do
			if hit.path == PROBE then
				found[hit.symbol] = true
			end
		end
		for _, needle in NEEDLES do
			assert(
				found[needle],
				`the probe's {needle} was not reported against {PROBE}; the scanner said:\n`
					.. SourceScan.describeHits(hits)
			)
		end
		assert(
			string.find(SourceScan.describeHits(hits), PROBE, 1, true) ~= nil,
			"the rendered failure message does not contain the offending path"
		)
	end,

	--[[ The matcher's own discrimination, in memory. ]]

	["control: hitsIn scores zero on all three needles, which is why this guard does not use it"] = function()
		local text = table.concat({
			"remote.OnServerEvent:Connect(function(player) end)",
			"remote.OnServerInvoke = function(player) return 1 end",
			"local c = other.OnClientEvent",
		}, "\n")
		local hits = SourceScan.hitsIn("src/server/Sample.luau", text, NEEDLES)
		assert(
			#hits == 0,
			`hitsIn now fires on member accesses ({#hits} hit(s)); ROUND-001's and ROUND-003's guards `
				.. `depend on it not doing so, and this guard's reason for a sibling matcher has changed:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["control: the member matcher fires on a connection, an assignment, a read and a table field, naming the line"] = function()
		local text = table.concat({
			"--!strict",
			"remote.OnServerEvent:Connect(function(player) end)",
			"remote.OnServerInvoke = function(player) return 1 end",
			"local c = other.OnClientEvent",
			"local fake = { OnServerEvent = signal }",
			"print(`{remote.OnServerEvent}`)",
		}, "\n")
		local hits = SourceScan.memberHitsIn("src/server/Leaky.luau", text, NEEDLES)
		local lines: { [string]: { number } } = {}
		for _, hit in hits do
			lines[hit.symbol] = lines[hit.symbol] or {}
			table.insert(lines[hit.symbol], hit.line)
		end
		assert(#hits == 5, `expected 5 hits, got {#hits}:\n` .. SourceScan.describeHits(hits))
		assert(
			lines["OnServerEvent"] ~= nil and #lines["OnServerEvent"] == 3,
			`OnServerEvent should fire on lines 2, 5 and 6:\n` .. SourceScan.describeHits(hits)
		)
		assert(
			lines["OnServerInvoke"] ~= nil and lines["OnServerInvoke"][1] == 3,
			`OnServerInvoke should fire on line 3:\n` .. SourceScan.describeHits(hits)
		)
		assert(
			lines[".OnClientEvent"] ~= nil and lines[".OnClientEvent"][1] == 4,
			`.OnClientEvent should fire on line 4:\n` .. SourceScan.describeHits(hits)
		)
		assert(
			string.find(SourceScan.describeHits(hits), "src/server/Leaky.luau:2", 1, true) ~= nil,
			`the rendered failure does not name the offending path and line:\n`
				.. SourceScan.describeHits(hits)
		)
	end,

	["control: the member matcher does not fire on the needles in comments or string literals"] = function()
		local text = table.concat({
			"--!strict",
			"--[[ No OnServerEvent:Connect outside src/net/; no OnServerInvoke either ]]",
			"-- and nothing reads .OnClientEvent",
			'local rule = "OnServerEvent, OnServerInvoke and .OnClientEvent are banned here"',
			"local other = 'remote.OnServerEvent:Connect'",
			"return rule .. other",
		}, "\n")
		local hits = SourceScan.memberHitsIn("src/server/Doc.luau", text, NEEDLES)
		assert(
			#hits == 0,
			`a doc comment and a string literal produced hits:\n` .. SourceScan.describeHits(hits)
		)
	end,

	["control: the member matcher does not fire on identifiers that merely contain a needle, and .OnClientEvent needs its dot"] = function()
		local text = table.concat({
			"local OnServerEvents = 1",
			"local MyOnServerEvent = 2",
			"local OnServerEventHandler = 3",
			"local OnServerInvoked = 4",
			"local OnClientEvent = 5",
			"return OnServerEvents + MyOnServerEvent + OnServerEventHandler + OnServerInvoked + OnClientEvent",
		}, "\n")
		local hits = SourceScan.memberHitsIn("src/server/Words.luau", text, NEEDLES)
		assert(#hits == 0, `word boundaries are wrong:\n` .. SourceScan.describeHits(hits))
	end,

	["control: the member matcher exempts nothing by itself - a src/net/ path scans like any other, and the guard is what exempts it"] = function()
		local text = "remote.OnServerEvent:Connect(handler)"
		local hits = SourceScan.memberHitsIn("src/net/Wrapper.luau", text, NEEDLES)
		assert(#hits == 1, `expected the matcher to report 1 hit under src/net/, got {#hits}`)
		assert(
			#outsideNet({ "src/net/Wrapper.luau", "src/server/X.luau", "src/network/Y.luau" }) == 2,
			"outsideNet exempts exactly the src/net/ prefix"
		)
	end,
}
