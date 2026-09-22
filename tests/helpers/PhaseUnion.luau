--!strict
--[[
	NET-002 AC-7: the two `Phase` unions - `src/net/Remotes.luau` re-declares
	the one `src/server/round/PhaseMachine.luau` exports, because
	`architecture.md` section 1 forbids `net` -> `server` and `.luaurc` has no
	alias that would spell the require - must name exactly the same phases.
	This module reads a union out of a module's text and compares two of them
	as SETS; `tests/net/phase_union_guard_test.luau` applies it to the tree
	and drives it with fixtures that must fail.

	WHY THIS IS TEXTUAL, and why that is the right instrument rather than a
	weaker one: the typecheck gate cannot see the drift. Nothing constructs a
	`GuardContext`, nothing in `src/net/` requires `PhaseMachine`, nothing in
	`src/server/` requires `Wrapper`, so no expression exists in which one
	`Phase` flows into the other, and `luau-lsp` exiting 0 is the absence of a
	complaint. The story's Contract measured that on 2026-09-21 and RED
	re-measured it (the greps are in `## Handoff`). Until the M3 driver makes
	the two types meet, a textual guard is the only thing that can say they
	agree.

	HOW THE DECLARATION IS LOCATED versus HOW THE NAMES ARE READ. The line is
	found in `SourceScan.codeOnly` output - comments and string literals
	blanked, newlines kept - so `export type Phase =` inside a doc comment is
	not a second declaration. But `codeOnly` blanks the CONTENTS of string
	literals too, so the phase names cannot be read from it; they are read
	from the raw line at the same number, up to a `--` that stands outside a
	string. A union that wraps across lines is followed while a line ends
	with `|` or the next begins with one, which is how stylua wraps a long
	union.

	WHAT THIS CANNOT SEE, stated so the next reader does not assume otherwise:
	a union built by string concatenation, one assembled from other type
	aliases (`type Phase = Early | Late`), one whose members are single-quoted,
	or one declared under a different name. It catches the way the type is
	actually written today - `export type Phase = "Lobby" | ... | "Post"` -
	and the three vacuity assertions in `violations` are what make a pattern
	that stops matching a loud failure rather than a quiet pass.
]]

local SourceScan = require("./SourceScan")

local PhaseUnion = {}

export type Declaration = { line: number, phases: { string } }

-- One side of the comparison: where it came from, how many declarations were
-- found there (exactly one is the only acceptable answer), and the names.
export type Side = { path: string, declarations: number, phases: { string } }

-- The five phases `PhaseMachine.luau` produces today. A union that lacks one
-- of these has drifted or has not been read; a union that adds one has drifted.
PhaseUnion.KNOWN = { "Lobby", "Assignment", "Round", "Resolution", "Post" }

local DECLARATION = "^%s*export%s+type%s+Phase%s*="

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") :: string
end

--[[
	`raw` up to the first `--` that stands outside a double-quoted string, so a
	trailing comment on the declaration line contributes no phase. Quotes
	inside a phase name are not a case this handles; a phase name is an
	identifier.
]]
local function beforeLineComment(raw: string): string
	local i = 1
	local n = #raw
	local inString = false
	while i <= n do
		local ch = string.sub(raw, i, i)
		if inString then
			if ch == '"' then
				inString = false
			end
		elseif ch == '"' then
			inString = true
		elseif ch == "-" and string.sub(raw, i, i + 1) == "--" then
			return string.sub(raw, 1, i - 1)
		end
		i += 1
	end
	return raw
end

--[[
	Every `export type Phase = ...` that stands as CODE in `text`, with the
	double-quoted literals of its union in declaration order. Duplicates are
	kept, so a union naming a phase twice is visible to `violations`.
]]
function PhaseUnion.declarationsIn(text: string): { Declaration }
	local code = string.split(SourceScan.codeOnly(text), "\n")
	local raw = string.split(text, "\n")
	local out: { Declaration } = {}

	local i = 1
	while i <= #code do
		if string.match(code[i], DECLARATION) == nil then
			i += 1
			continue
		end

		local phases: { string } = {}
		local j = i
		while true do
			local here = trim(beforeLineComment(raw[j]))
			for name in string.gmatch(here, '"([^"]*)"') do
				table.insert(phases, name)
			end
			local following = if j < #raw then trim(beforeLineComment(raw[j + 1])) else ""
			local continues = string.sub(here, -1) == "|" or string.sub(following, 1, 1) == "|"
			if continues and j < #raw then
				j += 1
			else
				break
			end
		end
		table.insert(out, { line = i, phases = phases })
		i = j + 1
	end

	return out
end

-- The union in `text`, attributed to `path`, as one side of a comparison.
function PhaseUnion.read(path: string, text: string): Side
	local declarations = PhaseUnion.declarationsIn(text)
	local phases: { string } = {}
	for _, declaration in declarations do
		for _, name in declaration.phases do
			table.insert(phases, name)
		end
	end
	return { path = path, declarations = #declarations, phases = phases }
end

local function toSet(list: { string }): { [string]: number }
	local set: { [string]: number } = {}
	for _, item in list do
		set[item] = (set[item] or 0) + 1
	end
	return set
end

--[[
	Every way `a` and `b` fail to be one union spelled twice, accumulated so
	the guard reports all of them at once. The first three per side are the
	vacuity assertions the criterion demands - exactly one declaration, a
	non-empty set, every known phase present - and they come first because
	a side that fails them has not been READ, and a set comparison over it
	would be comparing nothing to nothing. The last two name the differing
	phase and the side that has it, per phase.
]]
function PhaseUnion.violations(a: Side, b: Side): { string }
	local out: { string } = {}

	for _, side in { a, b } do
		if side.declarations ~= 1 then
			table.insert(
				out,
				`{side.path}: found {side.declarations} 'export type Phase =' declaration(s) standing as `
					.. `code; expected exactly one`
			)
		end
		if #side.phases == 0 then
			table.insert(
				out,
				`{side.path}: the Phase union names no phases - the extraction matched nothing, and an `
					.. `empty set compared to an empty set would pass`
			)
		end
		local set = toSet(side.phases)
		for _, known in PhaseUnion.KNOWN do
			if set[known] == nil then
				table.insert(out, `{side.path}: the Phase union lacks the known phase "{known}"`)
			end
		end
		for name, count in set do
			if count > 1 then
				table.insert(out, `{side.path}: the Phase union names "{name}" {count} times`)
			end
		end
	end

	local setA, setB = toSet(a.phases), toSet(b.phases)
	for _, name in a.phases do
		if setB[name] == nil then
			table.insert(out, `{a.path} names the phase "{name}", which {b.path} does not`)
			setB[name] = 0
		end
	end
	for _, name in b.phases do
		if setA[name] == nil then
			table.insert(out, `{b.path} names the phase "{name}", which {a.path} does not`)
			setA[name] = 0
		end
	end

	return out
end

function PhaseUnion.describe(violations: { string }): string
	if #violations == 0 then
		return "(the two Phase unions agree)"
	end
	return table.concat(violations, "\n")
end

return PhaseUnion
