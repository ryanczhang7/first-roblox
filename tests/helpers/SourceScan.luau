--!strict
--[[
	The source guard behind ROUND-001 AC-5 and AC-6.

	AC-5 says no module other than `src/shared/Clock.luau` may reference a real
	time source, and no module other than `src/shared/Rng.luau` may reference a
	real random source. AC-6 says the file list this scan runs over comes from
	`scripts/classify.sh`, never from a private glob, regex or directory walk.

	Both halves live here so there is exactly ONE answer in this repository to
	"which files are source modules", and it is the harness's answer - the same
	one `.claude/hooks/phase-guard.sh` uses. `.claude/harness/rules.md` says why:
	four private copies of that question in one project drifted apart and spent
	six stories returning deliberately-offending probe artifacts as production
	source, asserting real properties over files written to violate a rule.

	So: no `fs.readDir` walk, no `*.luau` glob, no path regex. `--list source src`
	is asked once per call and every path it returns is scanned, whatever its
	extension - a private filter here would be the same defect in a smaller box.

	WHAT THIS CANNOT SEE, stated so the next reader does not assume otherwise:
	the scan is textual, over code with comments and string literals blanked out.
	`os["clock"]()` and `getfenv().os.clock()` are invisible to it. It catches the
	way the call is actually written, which is the failure this story is about.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SourceScan = {}

export type Rule = {
	symbol: string,
	owner: string,
	kind: string,
}

export type Finding = {
	path: string,
	line: number,
	symbol: string,
	owner: string,
	kind: string,
}

-- AC-5's two lists, verbatim. `owner` is the one module allowed to say it.
local RULES: { Rule } = {
	{ symbol = "os.clock", owner = "src/shared/Clock.luau", kind = "time" },
	{ symbol = "os.time", owner = "src/shared/Clock.luau", kind = "time" },
	{ symbol = "tick", owner = "src/shared/Clock.luau", kind = "time" },
	{ symbol = "DateTime.now", owner = "src/shared/Clock.luau", kind = "time" },
	{ symbol = "task.wait", owner = "src/shared/Clock.luau", kind = "time" },
	{ symbol = "math.random", owner = "src/shared/Rng.luau", kind = "random" },
	{ symbol = "math.randomseed", owner = "src/shared/Rng.luau", kind = "random" },
	{ symbol = "Random.new", owner = "src/shared/Rng.luau", kind = "random" },
}

SourceScan.RULES = RULES

--[[
	Every path the harness classifies as `category` under `src/`.

	This is the AC-6 requirement in one function: shell out, take what comes
	back, filter nothing. `--list` enumerates through git - tracked files PLUS
	untracked ones git does not ignore - so a module written five minutes ago and
	not yet committed is in the scanned set, which is the half a `git ls-files`
	of my own would have silently dropped.
]]
--[[
	One answer per category per run, cached.

	Not an optimisation for its own sake: every call is a `bash` process, and on
	Windows that is over a second. Eight of them turned a 155 ms unit gate into a
	14 s one, and a slow gate is one somebody eventually stops running.

	The cache is a real hazard and it is named here rather than discovered later:
	a test that CHANGES the tree - AC-6's uncommitted fixture is the only one -
	must call `SourceScan.refresh()` after writing and again after removing.
	Skipping the second call leaves a path in the cache that no longer exists, and
	the next `scan()` dies in `fs.readFile`. The fix is to invalidate, never to
	tolerate the read error: a scanner that swallows a missing file degrades
	toward scanning nothing while still reporting green.
]]
local cache: { [string]: { string } } = {}

function SourceScan.refresh()
	cache = {}
end

function SourceScan.classifierList(category: string): { string }
	local cached = cache[category]
	if cached ~= nil then
		return table.clone(cached)
	end

	local result = process.exec("bash", { "scripts/classify.sh", "--list", category, "src" })
	if not result.ok then
		error(
			`scripts/classify.sh --list {category} src exited {result.code}\n`
				.. `stdout: {result.stdout}\nstderr: {result.stderr}`
		)
	end

	local paths: { string } = {}
	for line in string.gmatch(result.stdout, "[^\r\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if trimmed ~= "" then
			table.insert(paths, trimmed)
		end
	end

	cache[category] = paths
	return table.clone(paths)
end

-- The set AC-5 asserts over. Probe artifacts are absent from it BY
-- CLASSIFICATION (`paths.conf` calls `**/__probe_*.*` a test), never by a name
-- check of mine.
function SourceScan.sourceFiles(): { string }
	return SourceScan.classifierList("source")
end

-- Files under src/ the harness calls tests: today, exactly the AC-5 probe. The
-- guard's own negative control runs over `sourceFiles() + this`, which is the
-- "temporarily include probe files when running the control" the story's
-- Contract asks for.
function SourceScan.nonSourceFilesUnderSrc(): { string }
	return SourceScan.classifierList("test")
end

-- The first character at or after `idx` that is not a space or a tab.
local function nextNonSpace(line: string, idx: number): (string, number)
	local j = idx
	while true do
		local c = string.sub(line, j, j)
		if c == " " or c == "\t" then
			j += 1
		else
			return c, j
		end
	end
end

-- The first character at or before `idx` that is not a space or a tab.
local function prevNonSpace(line: string, idx: number): string
	local j = idx
	while j >= 1 do
		local c = string.sub(line, j, j)
		if c ~= " " and c ~= "\t" then
			return c
		end
		j -= 1
	end
	return ""
end

local function isIdentByte(b: number?): boolean
	if b == nil then
		return false
	end
	local c = b :: number
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
end

-- `[`, k `=`, `[` -> (k, index just past the opener). Otherwise nil.
local function longBracketAt(text: string, p: number): (number?, number)
	if string.sub(text, p, p) ~= "[" then
		return nil, p
	end
	local k = 0
	while string.sub(text, p + 1 + k, p + 1 + k) == "=" do
		k += 1
	end
	if string.sub(text, p + 1 + k, p + 1 + k) == "[" then
		return k, p + k + 2
	end
	return nil, p
end

local function longBracketCloseAt(text: string, p: number, level: number): number?
	if string.sub(text, p, p) ~= "]" then
		return nil
	end
	local k = 0
	while string.sub(text, p + 1 + k, p + 1 + k) == "=" do
		k += 1
	end
	if k == level and string.sub(text, p + 1 + k, p + 1 + k) == "]" then
		return p + level + 2
	end
	return nil
end

--[[
	`text` with every comment and string literal replaced by spaces, newlines
	kept so line numbers still mean something.

	This is not decoration. `src/shared/Scaffold.luau` names `os.clock`, `tick`,
	`task.wait`, `math.random` and `Random.new` in a doc comment explaining that
	nothing may call them, and a line-grep guard fires on that comment - flagging
	the one file in the tree that documents the rule it is enforcing. A guard
	that cannot tell a call from a sentence about calls would be reverted within
	a story, and the way it gets reverted is by deleting the guard.

	Luau string interpolation is handled rather than skipped: the braces in a
	backtick string are CODE, so an `os.clock()` call written inside one is real
	and is reported. Blanking the whole backtick string would leave a hole in the
	guard shaped exactly like this repository's favourite way to write a message.
]]
function SourceScan.codeOnly(text: string): string
	local out: { string } = {}
	local n = #text
	local i = 1
	local mode = "code"
	local quote = ""
	local level = 0
	local braceDepth = 0
	local interpStack: { number } = {}

	local function keep(ch: string)
		table.insert(out, ch)
	end

	local function drop(ch: string)
		table.insert(out, if ch == "\n" then "\n" else " ")
	end

	local function dropRange(from: number, to: number)
		for j = from, to do
			drop(string.sub(text, j, j))
		end
	end

	while i <= n do
		local ch = string.sub(text, i, i)

		if mode == "code" then
			if ch == "-" and string.sub(text, i, i + 1) == "--" then
				local lvl, after = longBracketAt(text, i + 2)
				if lvl ~= nil then
					mode, level = "longComment", lvl :: number
					dropRange(i, after - 1)
					i = after
				else
					mode = "lineComment"
					dropRange(i, i + 1)
					i += 2
				end
			elseif ch == '"' or ch == "'" then
				mode, quote = "short", ch
				drop(ch)
				i += 1
			elseif ch == "`" then
				mode = "interp"
				drop(ch)
				i += 1
			elseif ch == "[" then
				local lvl, after = longBracketAt(text, i)
				if lvl ~= nil then
					mode, level = "longString", lvl :: number
					dropRange(i, after - 1)
					i = after
				else
					keep(ch)
					i += 1
				end
			elseif ch == "{" then
				braceDepth += 1
				keep(ch)
				i += 1
			elseif ch == "}" then
				if braceDepth == 0 and #interpStack > 0 then
					braceDepth = table.remove(interpStack) :: number
					mode = "interp"
					drop(ch)
				else
					if braceDepth > 0 then
						braceDepth -= 1
					end
					keep(ch)
				end
				i += 1
			else
				keep(ch)
				i += 1
			end
		elseif mode == "lineComment" then
			if ch == "\n" then
				mode = "code"
				keep("\n")
			else
				drop(ch)
			end
			i += 1
		elseif mode == "short" then
			if ch == "\\" then
				dropRange(i, i + 1)
				i += 2
			elseif ch == quote then
				mode = "code"
				drop(ch)
				i += 1
			elseif ch == "\n" then
				-- Unterminated literal. Recover rather than swallow the file.
				mode = "code"
				keep("\n")
				i += 1
			else
				drop(ch)
				i += 1
			end
		elseif mode == "interp" then
			if ch == "\\" then
				dropRange(i, i + 1)
				i += 2
			elseif ch == "`" then
				mode = "code"
				drop(ch)
				i += 1
			elseif ch == "{" then
				table.insert(interpStack, braceDepth)
				braceDepth = 0
				mode = "code"
				drop(ch)
				i += 1
			else
				drop(ch)
				i += 1
			end
		else
			local closeAt = longBracketCloseAt(text, i, level)
			if closeAt ~= nil then
				mode = "code"
				dropRange(i, (closeAt :: number) - 1)
				i = closeAt :: number
			else
				drop(ch)
				i += 1
			end
		end
	end

	return table.concat(out)
end

--[[
	Every AC-5 violation in `text`, attributed to `path`.

	`path` decides ownership: the two adapters are allowed to say their own
	symbols and nobody else is. A symbol only counts when it stands alone -
	`ticket` is not `tick`, `self.tick` is a field rather than the global, and
	`math.randomseed` is not a `math.random` hit.
]]
function SourceScan.findingsIn(path: string, text: string): { Finding }
	local findings: { Finding } = {}
	local lines = string.split(SourceScan.codeOnly(text), "\n")

	for lineNumber, line in lines do
		for _, rule in RULES do
			if rule.owner == path then
				continue
			end
			local from = 1
			while true do
				local s, e = string.find(line, rule.symbol, from, true)
				if s == nil then
					break
				end
				local start = s :: number
				local finish = e :: number
				local before = string.sub(line, start - 1, start - 1)
				local leading = prevNonSpace(line, start - 1)
				-- A field access or definition is not a reference to the global.
				-- `self.tick` is somebody's own field; `{ tick = 2 }` is a table
				-- key. Both read as the symbol to a line-grep and neither asks
				-- the process for anything.
				local okBefore = start == 1
					or (not isIdentByte(string.byte(before)) and leading ~= "." and leading ~= ":")
				local trailing, at = nextNonSpace(line, finish + 1)
				local isAssignedTo = trailing == "=" and string.sub(line, at + 1, at + 1) ~= "="
				local okAfter = not isIdentByte(string.byte(line, finish + 1)) and not isAssignedTo
				if okBefore and okAfter then
					table.insert(findings, {
						path = path,
						line = lineNumber,
						symbol = rule.symbol,
						owner = rule.owner,
						kind = rule.kind,
					})
				end
				from = finish + 1
			end
		end
	end

	return findings
end

-- Every violation across `paths`. Violations are accumulated and asserted once
-- by the caller; a guard that asserts per file reports the first offender and
-- hides the rest.
function SourceScan.scan(paths: { string }): { Finding }
	local findings: { Finding } = {}
	for _, path in paths do
		for _, finding in SourceScan.findingsIn(path, fs.readFile(path)) do
			table.insert(findings, finding)
		end
	end
	return findings
end

function SourceScan.ofKind(findings: { Finding }, kind: string): { Finding }
	local out: { Finding } = {}
	for _, finding in findings do
		if finding.kind == kind then
			table.insert(out, finding)
		end
	end
	return out
end

-- The failure message. AC-5's control requires the offending file to be NAMED,
-- so the path leads every line.
function SourceScan.describe(findings: { Finding }): string
	if #findings == 0 then
		return "(no findings)"
	end
	local lines: { string } = {}
	for _, finding in findings do
		table.insert(
			lines,
			`{finding.path}:{finding.line} references {finding.symbol} - only {finding.owner} may`
		)
	end
	return table.concat(lines, "\n")
end

function SourceScan.contains(list: { string }, wanted: string): boolean
	for _, item in list do
		if item == wanted then
			return true
		end
	end
	return false
end

return SourceScan
