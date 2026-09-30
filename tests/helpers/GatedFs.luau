--!strict
--[[
	HARNESS-022: the one way a test reaches the filesystem.

	Every file a unit test reads must be in the gate tree hash, or an edit to
	that file after a gate run changes what `unit` reports while the recorded
	stamp still matches (HARNESS-021's bug, generalised). The hash is defined
	once, by `gated_stdin` in `.claude/hooks/lib.sh`, and this module ASKS it
	(`bash scripts/classify.sh --gated`) rather than re-deriving it - the same
	argument `SourceScan.classifierList` makes about "which files are source".

	`readFile` is the checked member: a path outside the hash raises, naming
	the path, BEFORE any read happens. The other members the tests use today
	(`writeFile`, `isFile`, `isDir`, `readDir`, `removeFile`) pass straight
	through. `@lune/fs` itself is frozen, so this is a new table with the same
	member names, not a patched module - and a guard in
	`tests/shared/gated_fs_test.luau` (AC-7) keeps every other file under
	`tests/` off the raw module.

	Lazy, and cached: nothing is spawned at require time, so
	`lune run test -- --list` stays spawn-free. The first check runs
	`classify.sh --gated` once for the whole tree. A miss is re-asked once for
	that one path, because a file written during the run (an untracked probe)
	is judged by git at that moment, not at the first spawn; hits and misses
	are then memoised per path. Fails CLOSED: a classify.sh that exits non-zero
	is an error carrying its exit code, stdout and stderr, never "allowed".

	`rawReadFile` is the unchecked read, and it exists for one caller: AC-5's
	control in gated_fs_test.luau, which shows the refusal comes from the check
	and not from a missing file. The AC-7 guard cannot see a call to it - it
	looks for the `@lune/fs` literal - so that same test file pins that no
	other test file calls it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local GatedFs = {}

-- nil until the first check; then the whole-tree answer.
local gatedSet: { [string]: boolean }? = nil
-- per-path verdicts, hits and misses alike, after the whole-tree answer.
local memo: { [string]: boolean } = {}

local HINT =
	'add "covers | unit | <path>" to .claude/harness/project.conf if a gate really reads it'

-- `\` to `/` and a leading `./` stripped. Nothing else: an absolute path is
-- not rewritten, fails the check, and says so.
local function normalise(path: string): string
	local slashed = (string.gsub(path, "\\", "/"))
	if string.sub(slashed, 1, 2) == "./" then
		return string.sub(slashed, 3)
	end
	return slashed
end

-- One `classify.sh --gated [PATHSPEC...]` call, parsed into a set. The error
-- shape is `SourceScan.classifierList`'s, so a broken classifier reads the
-- same from either helper.
local function ask(pathspecs: { string }): { [string]: boolean }
	local argv = { "scripts/classify.sh", "--gated" }
	for _, spec in pathspecs do
		table.insert(argv, spec)
	end
	local result = process.exec("bash", argv)
	if not result.ok then
		error(
			`scripts/classify.sh --gated {table.concat(pathspecs, " ")} exited {result.code}\n`
				.. `stdout: {result.stdout}\nstderr: {result.stderr}`
		)
	end

	local set: { [string]: boolean } = {}
	for line in string.gmatch(result.stdout, "[^\r\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if trimmed ~= "" then
			set[trimmed] = true
		end
	end
	return set
end

-- Is `path` in the gate tree hash? Exposed for AC-5 and AC-6.
function GatedFs.gated(path: string): boolean
	local key = normalise(path)
	local known = memo[key]
	if known ~= nil then
		return known
	end

	if gatedSet == nil then
		gatedSet = ask({})
	end
	local set = gatedSet :: { [string]: boolean }

	local hit = set[key] == true
	if not hit then
		-- The file may have appeared since the whole-tree answer. Ask git
		-- about this one path, once, and remember the answer either way.
		hit = ask({ key })[key] == true
	end
	memo[key] = hit
	return hit
end

-- The checked read. The refusal is raised at level 0 so that its first line is
-- exactly `read outside the gate hash: <path>` with no `file:line:` prefix.
function GatedFs.readFile(path: string): string
	if not GatedFs.gated(path) then
		error("read outside the gate hash: " .. path .. "\n" .. HINT, 0)
	end
	return fs.readFile(path)
end

-- The unchecked read. For gated_fs_test.luau's AC-5 control only; see above.
function GatedFs.rawReadFile(path: string): string
	return fs.readFile(path)
end

function GatedFs.writeFile(path: string, contents: string)
	fs.writeFile(path, contents)
end

function GatedFs.isFile(path: string): boolean
	return fs.isFile(path)
end

function GatedFs.isDir(path: string): boolean
	return fs.isDir(path)
end

function GatedFs.readDir(path: string): { string }
	return fs.readDir(path)
end

function GatedFs.removeFile(path: string)
	fs.removeFile(path)
end

return GatedFs
