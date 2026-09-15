--!strict
--[[
	ROUND-001 AC-5 and AC-6: the tree-scanning guard.

	AC-5 - no source module other than `src/shared/Clock.luau` references a real
	time source, and none other than `src/shared/Rng.luau` references a real
	random source.
	AC-6 - the file list comes from `scripts/classify.sh`, not from a private
	glob, and an uncommitted source file is in it.

	The scanning itself lives in `tests/helpers/SourceScan.luau`; this file is the
	assertions. Two of them are the negative controls the story's `## Notes` calls
	the point of the guard: a scan over a list built wrongly passes over
	everything, so the suite proves the scan FINDS the probe before it is allowed
	to mean anything by the scan finding nothing.
]]

local fs = require("@lune/fs")
local SourceScan = require("../helpers/SourceScan")

local PROBE = "src/shared/__probe_clock_leak.luau"
local CLOCK = "src/shared/Clock.luau"
local RNG = "src/shared/Rng.luau"

-- AC-6's fixture. Written, listed, removed, all inside the one test that needs
-- it - `tdd-cycle` warns that a probe writer and a tree scanner in the same
-- suite race, and the answer is that nothing else in this repository enumerates
-- the tree while this file exists. It is valid strict Luau with no violations in
-- it, so that a run killed between the write and the remove leaves a tree the
-- lint, typecheck and build gates still pass over.
local FIXTURE = "src/shared/__ac6_uncommitted_fixture.luau"
local FIXTURE_SOURCE = table.concat({
	"--!strict",
	"-- Transient fixture for ROUND-001 AC-6. Written and removed by",
	"-- tests/shared/source_guard_test.luau. If you are reading this in a",
	"-- checkout, a test run died midway and this file is safe to delete.",
	"return {}",
	"",
}, "\n")

local function concatLists(a: { string }, b: { string }): { string }
	local out: { string } = table.clone(a)
	for _, item in b do
		table.insert(out, item)
	end
	return out
end

return {
	--[[ AC-5 ]]

	["AC-5: no source module outside the Clock adapter reads a real time source"] = function()
		local sources = SourceScan.sourceFiles()
		local findings = SourceScan.ofKind(SourceScan.scan(sources), "time")
		assert(
			#findings == 0,
			`{#findings} time-source reference(s) outside {CLOCK}, over {#sources} scanned file(s):\n`
				.. SourceScan.describe(findings)
		)
	end,

	["AC-5: no source module outside the Rng adapter reads a real random source"] = function()
		local sources = SourceScan.sourceFiles()
		local findings = SourceScan.ofKind(SourceScan.scan(sources), "random")
		assert(
			#findings == 0,
			`{#findings} random-source reference(s) outside {RNG}, over {#sources} scanned file(s):\n`
				.. SourceScan.describe(findings)
		)
	end,

	-- The size assertion the story's oracle partition demands: a guard over zero
	-- files passes. Naming the two modules this story adds is a stronger form of
	-- it than a count, because it cannot be satisfied by any four files.
	["AC-5: the scanned set is the real source tree, including this story's two adapters"] = function()
		local sources = SourceScan.sourceFiles()
		assert(#sources >= 4, `the guard scanned {#sources} file(s); a guard over nothing passes`)
		assert(
			SourceScan.contains(sources, CLOCK),
			`{CLOCK} is not in the scanned set: {table.concat(sources, ", ")}`
		)
		assert(
			SourceScan.contains(sources, RNG),
			`{RNG} is not in the scanned set: {table.concat(sources, ", ")}`
		)
	end,

	--[[ AC-5, the negative control. This is the assertion that gives the two
	     above their meaning. ]]

	["AC-5 control: the probe module's os.clock call is found and named in the failure"] = function()
		local probes = SourceScan.nonSourceFilesUnderSrc()
		assert(
			SourceScan.contains(probes, PROBE),
			`{PROBE} is missing, or the harness no longer classifies it as a test; `
				.. `without it AC-5 has no negative control. classify.sh --list test src said: `
				.. `{table.concat(probes, ", ")}`
		)

		-- Deliberately the WRONG list: source plus the probes the normal
		-- assertion excludes. Anything other than a hit here means the scanner,
		-- not the tree, is what is clean.
		local findings = SourceScan.scan(concatLists(SourceScan.sourceFiles(), probes))
		assert(#findings > 0, `the scanner found nothing in {PROBE}, which calls os.clock()`)

		local named = false
		for _, finding in findings do
			if finding.path == PROBE and finding.symbol == "os.clock" then
				named = true
			end
		end
		assert(
			named,
			`the failure does not name {PROBE} against os.clock; it said:\n`
				.. SourceScan.describe(findings)
		)
		assert(
			string.find(SourceScan.describe(findings), PROBE, 1, true) ~= nil,
			"the rendered failure message does not contain the offending path"
		)
	end,

	--[[ AC-6 ]]

	["AC-6: a source file created and not yet committed is in the scanned set"] = function()
		assert(
			not fs.isFile(FIXTURE),
			`{FIXTURE} already exists - a previous run died before removing it`
		)

		-- The refresh either side of the fixture is mandatory, not tidiness. The
		-- first makes the listing below a real one rather than a cached answer
		-- from before the file existed; the second stops every later test in the
		-- run scanning a path that has just been deleted.
		fs.writeFile(FIXTURE, FIXTURE_SOURCE)
		SourceScan.refresh()
		local listed, result = pcall(SourceScan.sourceFiles)
		local removed, removeError = pcall(fs.removeFile, FIXTURE)
		SourceScan.refresh()

		assert(removed, `could not remove {FIXTURE}: {tostring(removeError)}`)
		assert(not fs.isFile(FIXTURE), `{FIXTURE} survived removal`)
		assert(listed, `listing the source tree failed: {tostring(result)}`)

		local sources = result :: { string }
		assert(
			SourceScan.contains(sources, FIXTURE),
			`{FIXTURE} was written and not committed, and the guard did not see it. `
				.. `A list built from the git index, or from a glob over committed files, `
				.. `fails exactly here. The guard saw: {table.concat(sources, ", ")}`
		)
	end,

	["AC-6: the scanned set excludes probe artifacts and still contains real modules"] = function()
		local sources = SourceScan.sourceFiles()
		assert(
			not SourceScan.contains(sources, PROBE),
			`{PROBE} is in the scanned set; AC-5 is asserting a real property over a file `
				.. `written to violate it`
		)

		-- The other half. An exclusion that is too broad is the same defect
		-- reversed, and it also passes AC-5 forever.
		local modules = 0
		for _, path in sources do
			if string.match(path, "%.luau$") ~= nil then
				modules += 1
			end
		end
		assert(modules >= 1, "the scanned set contains no .luau module at all")
	end,

	--[[ The scanner's own discrimination. Every one of these is a case where a
	     line-grep guard gives the wrong answer, and each wrong answer ends the
	     same way: somebody deletes the guard. ]]

	["the guard does not fire on a symbol named in a comment"] = function()
		local text = table.concat({
			"--!strict",
			"--[[ nothing here may call os.clock, tick or math.random ]]",
			"-- not even task.wait or Random.new",
			"return {}",
		}, "\n")
		local findings = SourceScan.findingsIn("src/shared/Doc.luau", text)
		assert(#findings == 0, `comments produced findings:\n` .. SourceScan.describe(findings))
	end,

	["the guard does not fire on a symbol named in a string literal"] = function()
		local text = table.concat({
			'local message = "use Clock.now() instead of os.clock()"',
			"local other = 'math.random is banned'",
			"return message .. other",
		}, "\n")
		local findings = SourceScan.findingsIn("src/shared/Message.luau", text)
		assert(
			#findings == 0,
			`string literals produced findings:\n` .. SourceScan.describe(findings)
		)
	end,

	["the guard fires on a real call, and reports its line"] = function()
		local text = table.concat({
			"--!strict",
			"local started = os.clock()",
			"return started",
		}, "\n")
		local findings = SourceScan.findingsIn("src/shared/Leaky.luau", text)
		assert(#findings == 1, `expected 1 finding, got {#findings}`)
		assert(findings[1].symbol == "os.clock", `expected os.clock, got {findings[1].symbol}`)
		assert(findings[1].line == 2, `expected line 2, got {findings[1].line}`)
	end,

	["the guard fires on a call written inside a string interpolation"] = function()
		local text = "print(`elapsed {os.clock()}s`)"
		local findings = SourceScan.findingsIn("src/shared/Interp.luau", text)
		assert(
			#findings == 1,
			`interpolation holes are code; expected 1 finding, got {#findings}:\n`
				.. SourceScan.describe(findings)
		)
	end,

	["the guard does not fire on identifiers that merely contain a symbol"] = function()
		local text = table.concat({
			"local ticket = 1",
			"local ticking = true",
			"local self = { tick = 2 }",
			"return ticket + self.tick + (if ticking then 0 else 1)",
		}, "\n")
		local findings = SourceScan.findingsIn("src/shared/Words.luau", text)
		assert(#findings == 0, `word boundaries are wrong:\n` .. SourceScan.describe(findings))
	end,

	-- The other half of the rule above. Skipping a field DEFINITION must not turn
	-- into skipping every mention that is not a call: `local now = tick` hands
	-- the global to a caller just as effectively as calling it.
	["the guard fires on a symbol that is read without being called"] = function()
		local text = table.concat({
			"local grab = tick",
			"local ready = os.clock ~= nil",
			"return grab, ready",
		}, "\n")
		local findings = SourceScan.findingsIn("src/shared/Held.luau", text)
		assert(
			#findings == 2,
			`expected 2 findings, got {#findings}:\n` .. SourceScan.describe(findings)
		)
	end,

	["the guard fires on a bare tick() call"] = function()
		local findings = SourceScan.findingsIn("src/shared/Bare.luau", "return tick()")
		assert(#findings == 1, `expected 1 finding, got {#findings}`)
		assert(findings[1].symbol == "tick", `expected tick, got {findings[1].symbol}`)
	end,

	["the guard counts math.randomseed once, as itself"] = function()
		local findings = SourceScan.findingsIn("src/shared/Seeded.luau", "math.randomseed(1)")
		assert(
			#findings == 1,
			`expected 1 finding, got {#findings}:\n` .. SourceScan.describe(findings)
		)
		assert(
			findings[1].symbol == "math.randomseed",
			`expected math.randomseed, got {findings[1].symbol}`
		)
	end,

	["each adapter may say its own symbols and not the other's"] = function()
		local clockText = "local a = os.clock()\nlocal b = math.random()\nreturn a + b"
		local clockFindings = SourceScan.findingsIn(CLOCK, clockText)
		assert(
			#clockFindings == 1 and clockFindings[1].symbol == "math.random",
			`{CLOCK} must be allowed os.clock and refused math.random; got:\n`
				.. SourceScan.describe(clockFindings)
		)

		local rngText = "local a = math.random()\nlocal b = tick()\nreturn a + b"
		local rngFindings = SourceScan.findingsIn(RNG, rngText)
		assert(
			#rngFindings == 1 and rngFindings[1].symbol == "tick",
			`{RNG} must be allowed math.random and refused tick; got:\n`
				.. SourceScan.describe(rngFindings)
		)
	end,
}
