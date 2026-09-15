--!strict
--[[
	The test runner.

	There is no pytest or vitest for Lune, so this repository owns its runner.
	That is a deliberate trade (docs/wiki/stack.md section 3): eighty lines buys
	an exact output contract, which is what lets `evidence`, `floor` and
	`discovery` in .claude/harness/project.conf read real numbers instead of
	scraping a tool that prints nothing.

	The contract, which BOOT-001's acceptance criteria depend on:

	  1. Walk `tests/` recursively for `*_test.luau` and require each one.
	  2. A FILE THAT FAILS TO LOAD IS A FAILURE, NEVER A SKIP. This is the one
	     line that stops a suite quietly shrinking from 120 tests to 4 while
	     staying green. A `require` in a silent `pcall` that moves on is the bug;
	     a `require` in a `pcall` that COUNTS THE FAILURE is the fix.
	  3. Print a final line `N passed, M failed` with real counts.
	  4. Exit non-zero if M > 0 **or if N == 0**. Zero tests is a failure.
	  5. `--list` does the same walk, prints `N tests` and each name, runs
	     nothing - so `discovery` asks the runner what it can see rather than
	     reading its configuration.

	A test file returns a table of `[name] = function()`. Assertions are plain
	`assert`; there is no assertion library and nothing here needs one.

		return {
			["does the thing"] = function()
				assert(subject.thing() == 1, "expected 1")
			end,
		}
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local TEST_ROOT = "tests"
local TEST_SUFFIX = "_test.luau"

-- `require` resolves relative to THIS file, which lives in lune/, so every
-- repo-relative path discovered below needs one level up.
local REQUIRE_PREFIX = "../"

type Case = { file: string, name: string, run: () -> () }
type LoadFailure = { file: string, err: string }

local function collect(dir: string, out: { string })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif fs.isFile(path) and string.sub(entry, -#TEST_SUFFIX) == TEST_SUFFIX then
			table.insert(out, path)
		end
	end
end

local files: { string } = {}
if fs.isDir(TEST_ROOT) then
	collect(TEST_ROOT, files)
end

local cases: { Case } = {}
local loadFailures: { LoadFailure } = {}

for _, path in files do
	local moduleName = string.sub(path, 1, #path - #".luau")
	local ok, result = pcall(require, REQUIRE_PREFIX .. moduleName)

	if not ok then
		table.insert(loadFailures, { file = path, err = tostring(result) })
	elseif typeof(result) ~= "table" then
		table.insert(loadFailures, {
			file = path,
			err = `expected the module to return a table of tests, got {typeof(result)}`,
		})
	else
		local suite = result :: { [string]: () -> () }
		local names: { string } = {}
		local malformed: string? = nil

		for name, fn in suite do
			if typeof(name) ~= "string" or typeof(fn) ~= "function" then
				malformed = `expected [string] = function, found [{typeof(name)}] = {typeof(fn)}`
				break
			end
			table.insert(names, name)
		end

		if malformed ~= nil then
			table.insert(loadFailures, { file = path, err = malformed :: string })
		elseif #names == 0 then
			-- A file named *_test.luau that declares nothing is how a suite
			-- shrinks without anyone noticing. Treat it as a load failure.
			table.insert(loadFailures, { file = path, err = "declares no tests" })
		else
			table.sort(names)
			for _, name in names do
				table.insert(cases, { file = path, name = name, run = suite[name] })
			end
		end
	end
end

for _, failure in loadFailures do
	stdio.ewrite(`  LOAD FAIL  {failure.file}\n             {failure.err}\n`)
end

local listOnly = false
for _, arg in process.args do
	if arg == "--list" then
		listOnly = true
	end
end

if listOnly then
	print(`{#cases} {if #cases == 1 then "test" else "tests"}`)
	for _, case in cases do
		print(`  {case.file} :: {case.name}`)
	end
	process.exit(if #cases == 0 or #loadFailures > 0 then 1 else 0)
end

local passed = 0
local failed = #loadFailures

for _, case in cases do
	local ok, err = pcall(case.run)
	if ok then
		passed += 1
		print(`  pass  {case.file} :: {case.name}`)
	else
		failed += 1
		print(`  FAIL  {case.file} :: {case.name}`)
		print(`        {tostring(err)}`)
	end
end

print(`{passed} passed, {failed} failed`)

-- Point 4. `passed == 0` is the half that is easy to leave out and impossible to
-- notice: without it, `mv tests tests.probe` reports "0 passed, 0 failed" and
-- exits 0, and the unit gate becomes a no-op that never complains again.
process.exit(if failed > 0 or passed == 0 then 1 else 0)
