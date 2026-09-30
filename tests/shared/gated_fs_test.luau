--!strict
--[[
	HARNESS-022 AC-4 to AC-7: a test that reads a file outside the gate hash
	fails, naming it.

	AC-4 - a read inside the hash is an ordinary read: byte-equal to the raw one.
	AC-5 - a read outside it raises before reading, and the first line of the
	       error is exactly `read outside the gate hash: <path>`.
	AC-6 - a file that appears during the run is judged (re-asked), not refused
	       from a stale cache - and one that appears and is NOT gated is still
	       refused, so the re-ask judges rather than allows.
	AC-7 - the helper is the only way in: no test file but GatedFs.luau holds a
	       string literal whose whole content is `@lune/fs`, in code.

	The gated set is asked of `scripts/classify.sh --gated`, so every case that
	reads through the helper is red until that mode exists (the story's
	Contract, "RED's expected failure"). Assertion messages carry the raw error
	so that the red names `--gated`, which is how the handoff shows the red is
	the expected one and not a migration bug.

	Every needle is by value: `==` on a whole line, never `string.find` for the
	message under test. The two `string.find`s here are negative (`os error`
	must be ABSENT; `rawReadFile` must be absent from other files).
]]

local GatedFs = require("../helpers/GatedFs")
local SourceScan = require("../helpers/SourceScan")

-- Spelled in two pieces, because this file is in the scanned set and a whole
-- literal `@lune/fs` here would be the guard's first offender. The five
-- in-memory cases below hold the needle inside longer literals, which the
-- whole-literal rule does not count - measured: the rule over this file's own
-- text flags nothing once NEEDLE is split.
local NEEDLE = "@lune/" .. "fs"
local SELF = "tests/shared/gated_fs_test.luau"
local EXEMPT = "tests/helpers/GatedFs.luau"

-- The shipped project.conf covers these two docs (HARNESS-021); Scaffold is
-- source. Nothing here chooses them: they are the story's measured readers.
local INSIDE = {
	"docs/wiki/game/tuning.md",
	"docs/wiki/stack.md",
	"src/shared/Scaffold.luau",
}

-- Mentioned in test comments and read by nothing (the HARNESS-021 control), a
-- game doc no covers line names, and a harness prompt HARNESS-021 AC-3 keeps
-- out of the hash.
local OUTSIDE = {
	"docs/wiki/architecture.md",
	"docs/wiki/game/loop.md",
	".claude/commands/advance-story.md",
}

local LATE_GATED = "tests/helpers/__probe_gated_late.luau"
local LATE_GATED_SOURCE = table.concat({
	"--!strict",
	"-- Transient probe for HARNESS-022 AC-6. Written and removed by",
	"-- tests/shared/gated_fs_test.luau. Safe to delete if a run died midway.",
	"return {}",
	"",
}, "\n")

local LATE_UNGATED = "docs/wiki/__probe_gated_late.md"
local LATE_UNGATED_SOURCE = "# Transient probe for HARNESS-022 AC-6 (control). Safe to delete.\n"

local function firstLine(message: string): string
	return string.split(message, "\n")[1]
end

-- One refusal, checked whole: raised, first line exact, no os error, and a
-- hint on a second line. The raw control lives in the same case so that a
-- refusal caused by a missing file cannot pass as a refusal by the check.
local function assertRefused(path: string)
	local ok, err = pcall(GatedFs.readFile, path)
	assert(not ok, `GatedFs.readFile({path}) returned instead of raising`)
	local message = tostring(err)
	local expected = `read outside the gate hash: {path}`
	-- The actual first line sits on the same line as the verdict, so that a
	-- FAIL's first line names the cause (in RED: `--gated exited 2`).
	assert(
		firstLine(message) == expected,
		`first line of the error is [{firstLine(message)}], not [{expected}]; the error was:\n{message}`
	)
	assert(
		string.find(message, "os error", 1, true) == nil,
		`the refusal read the file (an os error is in it):\n{message}`
	)
	assert(#string.split(message, "\n") >= 2, `the refusal carries no hint line:\n{message}`)

	-- Control: the same path through the raw module. If this fails the path is
	-- missing and the refusal above proved nothing.
	local rawOk, raw = pcall(GatedFs.rawReadFile, path)
	assert(rawOk, `control: the raw read of {path} failed, so the file is missing: {tostring(raw)}`)
	assert(#(raw :: string) > 0, `control: the raw read of {path} is empty`)
end

local function assertInside(path: string)
	local raw = GatedFs.rawReadFile(path)
	assert(#raw > 0, `{path} is empty on disk; an equality over nothing proves nothing`)
	local got = GatedFs.readFile(path)
	assert(
		got == raw,
		`GatedFs.readFile({path}) differs from the raw read ({#got} vs {#raw} bytes)`
	)
end

-- AC-7's rule, on a text. A literal whose WHOLE content is the needle, in
-- code: `require("@lune/fs")` and `local n = '@lune/fs'` both, a comment and
-- `"@lune/fsx"` neither.
local function holdsRawFsLiteral(text: string): boolean
	for _, literal in SourceScan.stringLiteralsIn(text) do
		if literal == NEEDLE then
			return true
		end
	end
	return false
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local function isProbe(path: string): boolean
	local name = basename(path)
	return string.match(name, "^__probe_") ~= nil or string.match(name, "^__.*_probe%.") ~= nil
end

-- Write, run, remove on every exit path, re-raise.
local function withTransient(path: string, contents: string, body: () -> ())
	assert(
		not GatedFs.isFile(path),
		`{path} already exists - a previous run died before removing it`
	)
	GatedFs.writeFile(path, contents)
	local ok, err = pcall(body)
	local removed, removeError = pcall(GatedFs.removeFile, path)
	assert(removed, `could not remove {path}: {tostring(removeError)}`)
	assert(not GatedFs.isFile(path), `{path} survived removal`)
	if not ok then
		error(err, 0)
	end
end

return {
	--[[ AC-4 ]]

	["AC-4: a covered doc (tuning.md) reads through GatedFs byte-equal to the raw read"] = function()
		assertInside(INSIDE[1])
	end,

	["AC-4: a covered doc (stack.md) reads through GatedFs byte-equal to the raw read"] = function()
		assertInside(INSIDE[2])
	end,

	["AC-4: a source module (Scaffold.luau) reads through GatedFs byte-equal to the raw read"] = function()
		assertInside(INSIDE[3])
	end,

	--[[ AC-5 ]]

	["AC-5: reading docs/wiki/architecture.md (uncovered) raises, first line naming the path"] = function()
		assertRefused(OUTSIDE[1])
	end,

	["AC-5: reading docs/wiki/game/loop.md (uncovered) raises, first line naming the path"] = function()
		assertRefused(OUTSIDE[2])
	end,

	["AC-5: reading .claude/commands/advance-story.md (a harness prompt) raises, first line naming the path"] = function()
		assertRefused(OUTSIDE[3])
	end,

	["AC-5: gated() agrees with readFile - true for the covered doc, false for the uncovered one"] = function()
		assert(GatedFs.gated(INSIDE[1]) == true, `gated({INSIDE[1]}) is false`)
		assert(GatedFs.gated(OUTSIDE[1]) == false, `gated({OUTSIDE[1]}) is true`)
	end,

	["AC-5: a backslash path and a ./ prefix are normalised before the check, and nothing else is"] = function()
		assert(
			GatedFs.gated("docs\\wiki\\game\\tuning.md") == true,
			"backslashes were not normalised"
		)
		assert(GatedFs.gated("./docs/wiki/game/tuning.md") == true, "a leading ./ was not stripped")
		-- Not rewritten, so not in git's enumeration, so refused: the check
		-- fails closed on a form it does not understand.
		assert(GatedFs.gated("docs//wiki/game/tuning.md") == false, "a doubled slash was rewritten")
	end,

	--[[ AC-6 ]]

	["AC-6: a test file written after the first read is judged on the re-ask and reads back"] = function()
		-- Force the whole-tree answer BEFORE the probe exists, so the case
		-- below is the miss-path re-ask and not the first spawn seeing the
		-- file. Do not ask about the probe itself here: a miss is memoised.
		assert(#GatedFs.readFile(INSIDE[3]) > 0, "the warm-up read returned nothing")
		withTransient(LATE_GATED, LATE_GATED_SOURCE, function()
			local ok, got = pcall(GatedFs.readFile, LATE_GATED)
			assert(
				ok,
				`GatedFs.readFile({LATE_GATED}) raised on a file git can see:\n{tostring(got)}`
			)
			assert(
				got == LATE_GATED_SOURCE,
				`the late file read back differently:\n{tostring(got)}`
			)
			assert(
				GatedFs.gated(LATE_GATED) == true,
				"gated() disagrees with the read that just succeeded"
			)
		end)
	end,

	["AC-6 control: a doc written after the first read is still refused - the re-ask judges, it does not allow"] = function()
		assert(#GatedFs.readFile(INSIDE[3]) > 0, "the warm-up read returned nothing")
		withTransient(LATE_UNGATED, LATE_UNGATED_SOURCE, function()
			assertRefused(LATE_UNGATED)
		end)
	end,

	--[[ AC-7, the rule on in-memory sources ]]

	['AC-7: require("@lune/fs") in code is flagged'] = function()
		assert(holdsRawFsLiteral('local fs = require("@lune/fs")\nreturn fs'), "not flagged")
	end,

	["AC-7: a bare '@lune/fs' literal is flagged - the literal is the needle, not the require"] = function()
		assert(holdsRawFsLiteral("local name = '@lune/fs'\nreturn name"), "not flagged")
	end,

	['AC-7: a line comment quoting require("@lune/fs") is not flagged'] = function()
		assert(
			not holdsRawFsLiteral('-- use require("@lune/fs") here\nreturn {}'),
			"a comment was flagged"
		)
	end,

	['AC-7: a block comment quoting require("@lune/fs") is not flagged'] = function()
		assert(
			not holdsRawFsLiteral('--[[ require("@lune/fs") ]]\nreturn {}'),
			"a block comment was flagged"
		)
	end,

	['AC-7: "@lune/fsx" is not flagged - whole-literal equality, not a substring'] = function()
		assert(
			not holdsRawFsLiteral('local x = "@lune/fsx"\nreturn x'),
			"a longer literal was flagged"
		)
	end,

	-- The reader's own edges, so that the five above are not passing on a
	-- reader that returns nothing or everything.
	["AC-7: stringLiteralsIn returns each literal's contents in order, with delimiters and comments out"] = function()
		local text = table.concat({
			'local a = "one" -- "not this"',
			"local b = 'two' --[[ 'nor this' ]]",
			"local c = [[three]]",
			"local d = `four {a} five`",
			"return a .. b .. c .. d",
		}, "\n")
		local got = SourceScan.stringLiteralsIn(text)
		local expected = { "one", "two", "three", "four  five" }
		assert(
			table.concat(got, "|") == table.concat(expected, "|"),
			`expected [{table.concat(expected, "|")}], got [{table.concat(got, "|")}]`
		)
	end,

	["AC-7: adding the reader changed neither codeOnly nor commentsOnly on a text with every literal kind"] = function()
		local text = 'local a = "x" -- c\nlocal b = `y {a}` --[[ d ]]\nlocal c = [[z]]\nreturn a'
		local code = SourceScan.codeOnly(text)
		assert(
			string.find(code, "x", 1, true) == nil and string.find(code, "z", 1, true) == nil,
			"codeOnly kept a literal"
		)
		assert(string.find(code, "-- c", 1, true) == nil, "codeOnly kept a comment")
		assert(string.find(code, "local a =", 1, true) ~= nil, "codeOnly lost code")
		local comments = SourceScan.commentsOnly(text)
		assert(string.find(comments, "-- c", 1, true) ~= nil, "commentsOnly lost a comment")
		-- `--[[ d`, not `--[[ d ]]`: commentsOnly has always blanked the closing
		-- bracket (measured before this story touched walk), and pinning the
		-- reader's arrival means pinning that output as it was.
		assert(string.find(comments, "--[[ d", 1, true) ~= nil, "commentsOnly lost a block comment")
		assert(string.find(comments, "local", 1, true) == nil, "commentsOnly kept code")
	end,

	--[[ AC-7, the real tree ]]

	["AC-7: no test file other than tests/helpers/GatedFs.luau names @lune/fs in code"] = function()
		local files = SourceScan.classifierList("test", "tests")
		assert(
			#files >= 10,
			`classify.sh --list test tests returned {#files} file(s); a guard over nothing passes`
		)
		assert(
			SourceScan.contains(files, SELF),
			`{SELF} is not in the scanned set: {table.concat(files, ", ")}`
		)
		assert(
			SourceScan.contains(files, EXEMPT),
			`{EXEMPT} is not in the scanned set, so the exemption is untested`
		)

		local offenders: { string } = {}
		local rawReaders: { string } = {}
		local scanned = 0
		for _, path in files do
			if path == EXEMPT or isProbe(path) then
				continue
			end
			local text = GatedFs.readFile(path)
			scanned += 1
			if holdsRawFsLiteral(text) then
				table.insert(offenders, path)
			end
			if
				path ~= SELF
				and string.find(SourceScan.codeOnly(text), "rawReadFile", 1, true) ~= nil
			then
				table.insert(rawReaders, path)
			end
		end
		assert(scanned >= 10, `only {scanned} file(s) were scanned`)
		assert(
			#offenders == 0,
			`{#offenders} test file(s) reach @lune/fs directly instead of through GatedFs:\n  `
				.. table.concat(offenders, "\n  ")
		)
		assert(
			#rawReaders == 0,
			`{#rawReaders} test file(s) call GatedFs.rawReadFile, which is for this file's AC-5 control only:\n  `
				.. table.concat(rawReaders, "\n  ")
		)
	end,

	["AC-7 control: a probe-named file is skipped by the guard and a real helper is not"] = function()
		assert(isProbe(LATE_GATED), `{LATE_GATED} is not recognised as a probe`)
		assert(isProbe("tests/helpers/__gated_probe.luau"), "the __*_probe. form is not recognised")
		assert(
			not isProbe("tests/helpers/heat_probe.luau"),
			"a helper merely named probe would be skipped"
		)
		assert(not isProbe(EXEMPT), `{EXEMPT} would be skipped as a probe`)
	end,
}
