--!strict
--[[
	ROUND-002's criteria, written once, as checks over a MODULE-SHAPED TABLE.

	`tests/shared/tuning_test.luau` and `tests/shared/tuning_spec_test.luau` apply
	them to `src/shared/Tuning.luau`, which is the story.
	`tests/shared/tuning_controls_test.luau` applies the same objects to the
	deliberately wrong tables in `tests/helpers/TuningFakes.luau`, which is what
	makes the word "control" mean something here: in RED the module does not
	exist, the files that require it die at `require`, and not one assertion in
	them has run. ROUND-001 established that split; this file continues it.

	THE ORACLE. `docs/wiki/game/tuning.md` opens by declaring itself the
	specification and the module source, so the guard PARSES it rather than
	carrying a second copy of the numbers. The alternative - a list of values in
	the test - is a third place for the two documents to disagree.

	ONE exception, and it is deliberate: `ACCEPTANCE` below is ROUND-002's AC-1
	and AC-2 lists, which are FROZEN once the story leaves PLANNED. It is not a
	convenience copy of the spec; it is the third point of a triangle. The module
	is checked against it (AC-1, AC-2), the specification file is checked against
	it (AC-4's drift check), and the module is checked against the specification
	file directly (AC-4). If `tuning.md` is edited to a different value, the
	module and the spec still agree and only the frozen criteria disagree - which
	is exactly the moment somebody should be asked, per `rules.md`. Changing a
	number in `ACCEPTANCE` therefore requires an `## Amendments` entry in
	ROUND-002.

	WHAT THIS CANNOT SEE. The parse is textual and reads only the first two cells
	of a markdown table row in sections 1 and 5. A constant stated in prose, in a
	nested list, or in a section this story does not cover is invisible to it -
	and a row it cannot read is REPORTED (`Parsed.problems`), never skipped, for
	the reason the row floor exists: a parser that silently matches nothing
	compares nothing and passes.
]]

local fs = require("@lune/fs")

local TuningSpec = {}

TuningSpec.SPEC_PATH = "docs/wiki/game/tuning.md"

--[[
	The two sections in scope, and the module table each maps onto.

	§2, §3, §4 and §6 are M3 (`## Out of scope`). A row in them is not a defect
	here, it is simply not this story's, so the parser collects nothing from them.
]]
local SECTION_TABLE: { [number]: string } = { [1] = "session", [5] = "round" }
TuningSpec.SECTION_TABLE = SECTION_TABLE

--[[
	AC-4's floor. Six constants in §1 and seven in §5.

	This is the assertion the whole guard rests on. A markdown-table parser that
	matches nothing parses zero rows, compares all zero of them successfully and
	reports green - so the guard has to say how much it parsed. Note the near
	miss that makes the count alone insufficient: §2 has exactly 13 constant rows
	of its own, so a parser pointed at the wrong section would satisfy this floor
	and nothing else. `assertExpectedNames` is the other half.
]]
TuningSpec.MIN_CONSTANTS = 13

-- ROUND-002 AC-1 and AC-2, verbatim. Frozen; see the header.
local ACCEPTANCE: { [string]: { [string]: number } } = {
	session = {
		players_min = 4,
		players_max = 6,
		min_players_to_continue = 3,
		lobby_seconds = 60,
		post_round_seconds = 45,
		season_length_days = 28,
	},
	round = {
		round_seconds = 480,
		round_seconds_min = 360,
		round_seconds_max = 600,
		per_operation_seconds = 45,
		traversal_reserve_seconds = 120,
		first_round_within_seconds = 480,
		disconnect_grace_seconds = 30,
	},
}
TuningSpec.ACCEPTANCE = ACCEPTANCE

TuningSpec.TABLE_NAMES = { "session", "round" }

export type Row = {
	name: string,
	value: number,
	section: number,
	tableName: string,
	line: number,
}

export type Parsed = { rows: { Row }, problems: { string } }

export type Finding = { name: string, message: string }

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$")) :: string
end

-- The cells of a markdown table row, trimmed. Only cells 1 and 2 are ever read,
-- so a stray pipe in the rationale column costs nothing.
local function cells(line: string): { string }
	local parts = string.split(line, "|")
	local out: { string } = {}
	for index = 2, #parts do
		table.insert(out, trim(parts[index]))
	end
	if #out > 0 and out[#out] == "" then
		table.remove(out)
	end
	return out
end

local function sortedKeys(source: any): { string }
	local keys: { string } = {}
	for key in source do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

TuningSpec.sortedKeys = sortedKeys

--[[
	`tuning.md` §5 writes two constants on one row:

		| `round_seconds_min` / `_max` | 360 / 600 | ...

	A name beginning with an underscore is a suffix shorthand, completed by
	replacing the previous name's own trailing segment. The alternatives were to
	special-case that one row by name - stale the first time §5 gains another
	pair - or to edit the specification, which is the Game Designer's file and
	explicitly not this story's to change.
]]
local function expand(raw: string, previous: string?): (string?, string?)
	if string.sub(raw, 1, 1) ~= "_" then
		return raw, nil
	end
	if previous == nil then
		return nil, `"{raw}" is a suffix shorthand with no preceding name on the row`
	end
	local stem = string.match(previous :: string, "^(.*)_%w+$")
	if stem == nil then
		return nil, `"{raw}" cannot be expanded from "{previous}"`
	end
	return (stem :: string) .. raw, nil
end

TuningSpec.expand = expand

--[[
	Every constant named in §1 and §5, with the value the specification gives.

	A `## <n>.` line opens a section; a `### ...` line does not, so §2's
	"Generator invariants" subsection cannot silently reopen a target section.
	Rows whose first cell carries no backticked name are the header and separator
	rows and are skipped; a row that DOES name a constant but whose value cell
	does not yield one number per name is recorded in `problems`.
]]
function TuningSpec.parse(text: string): Parsed
	local rows: { Row } = {}
	local problems: { string } = {}
	local section = 0
	local lineNumber = 0

	for _, rawLine in string.split(text, "\n") do
		lineNumber += 1
		local line = trim(rawLine)

		local heading = string.match(line, "^##%s+(%d+)%.")
		if heading ~= nil then
			section = tonumber(heading) :: number
			continue
		end

		local tableName = SECTION_TABLE[section]
		if tableName == nil or string.sub(line, 1, 1) ~= "|" then
			continue
		end

		local cell = cells(line)
		if #cell < 2 then
			continue
		end

		local names: { string } = {}
		for name in string.gmatch(cell[1], "`([^`]+)`") do
			table.insert(names, name)
		end
		if #names == 0 then
			continue
		end

		local values: { number } = {}
		for literal in string.gmatch(cell[2], "%-?%d+%.?%d*") do
			local number = tonumber(literal)
			if number ~= nil then
				table.insert(values, number :: number)
			end
		end

		if #values ~= #names then
			table.insert(
				problems,
				`{TuningSpec.SPEC_PATH}:{lineNumber} §{section}: {#names} name(s) but {#values} `
					.. `value(s) - "{cell[1]}" = "{cell[2]}"`
			)
			continue
		end

		local previous: string? = nil
		for index, raw in names do
			local name, why = expand(raw, previous)
			if name == nil then
				table.insert(problems, `{TuningSpec.SPEC_PATH}:{lineNumber} §{section}: {why}`)
				previous = raw
			else
				table.insert(rows, {
					name = name :: string,
					value = values[index],
					section = section,
					tableName = tableName,
					line = lineNumber,
				})
				previous = name
			end
		end
	end

	return { rows = rows, problems = problems }
end

function TuningSpec.read(): Parsed
	return TuningSpec.parse(fs.readFile(TuningSpec.SPEC_PATH))
end

-- The raw text of one `## <n>.` section, used by the AC-5 anchor check on §7.
function TuningSpec.section(text: string, wanted: number): string
	local out: { string } = {}
	local inside = false
	for _, rawLine in string.split(text, "\n") do
		local heading = string.match(trim(rawLine), "^##%s+(%d+)%.")
		if heading ~= nil then
			inside = tonumber(heading) == wanted
		elseif inside then
			table.insert(out, rawLine)
		end
	end
	return table.concat(out, "\n")
end

function TuningSpec.byTable(rows: { Row }): { [string]: { [string]: Row } }
	local out: { [string]: { [string]: Row } } = {}
	for _, tableName in TuningSpec.TABLE_NAMES do
		out[tableName] = {}
	end
	for _, row in rows do
		local bucket = out[row.tableName]
		if bucket == nil then
			bucket = {}
			out[row.tableName] = bucket
		end
		(bucket :: { [string]: Row })[row.name] = row
	end
	return out
end

--[[ AC-4's anti-vacuity half, first direction: how much was parsed. ]]
function TuningSpec.assertEnoughRows(parsed: Parsed)
	assert(
		#parsed.rows >= TuningSpec.MIN_CONSTANTS,
		`AC-4: the guard parsed {#parsed.rows} constants from {TuningSpec.SPEC_PATH} §1 and §5, `
			.. `expected at least {TuningSpec.MIN_CONSTANTS}. A parser that matches nothing `
			.. `compares nothing and passes.`
	)
end

--[[
	AC-4's anti-vacuity half, second direction: WHICH constants were parsed.

	The count alone is satisfiable by parsing the wrong section - §2 has 13
	constant rows - so the guard also insists the constants it found include
	every one ROUND-002's frozen criteria name.
]]
function TuningSpec.assertExpectedNames(parsed: Parsed)
	local found = TuningSpec.byTable(parsed.rows)
	local missing: { string } = {}
	for _, tableName in TuningSpec.TABLE_NAMES do
		for _, name in sortedKeys(ACCEPTANCE[tableName]) do
			local bucket = found[tableName]
			if bucket == nil or bucket[name] == nil then
				table.insert(missing, `{name} (expected in the rows for Tuning.{tableName})`)
			end
		end
	end
	assert(
		#missing == 0,
		`AC-4: the guard parsed {#parsed.rows} constants from {TuningSpec.SPEC_PATH} but not `
			.. `these:\n  `
			.. table.concat(missing, "\n  ")
	)
end

function TuningSpec.assertNoParseProblems(parsed: Parsed)
	assert(
		#parsed.problems == 0,
		`AC-4: the guard could not read {#parsed.problems} row(s) of {TuningSpec.SPEC_PATH}. `
			.. `A row it cannot read is a constant it is not checking:\n  `
			.. table.concat(parsed.problems, "\n  ")
	)
end

--[[
	The specification against ROUND-002's frozen AC-1 and AC-2 values.

	Red here means `tuning.md` moved under a story whose criteria are frozen. It
	is not a test failure to be fixed by editing either side; it is the
	conversation `rules.md` says to have.
]]
function TuningSpec.specDriftFindings(parsed: Parsed): { Finding }
	local found = TuningSpec.byTable(parsed.rows)
	local findings: { Finding } = {}
	for _, tableName in TuningSpec.TABLE_NAMES do
		for _, name in sortedKeys(ACCEPTANCE[tableName]) do
			local expected = ACCEPTANCE[tableName][name]
			local bucket = found[tableName]
			local row = if bucket ~= nil then bucket[name] else nil
			if row == nil then
				table.insert(findings, {
					name = name,
					message = `{name}: ROUND-002 freezes it at {expected}, `
						.. `{TuningSpec.SPEC_PATH} no longer names it`,
				})
			elseif (row :: Row).value ~= expected then
				table.insert(findings, {
					name = name,
					message = `{name}: ROUND-002 freezes it at {expected}, {TuningSpec.SPEC_PATH}:`
						.. `{(row :: Row).line} now says {(row :: Row).value}`,
				})
			end
		end
	end
	return findings
end

local function tablesOf(module: any): (any, { Finding })
	local findings: { Finding } = {}
	if typeof(module) ~= "table" then
		table.insert(findings, {
			name = "Tuning",
			message = `Tuning is {typeof(module)}, expected a table`,
		})
		return nil, findings
	end
	local out: { [string]: any } = {}
	for _, tableName in TuningSpec.TABLE_NAMES do
		local sub = (module :: any)[tableName]
		if typeof(sub) ~= "table" then
			table.insert(findings, {
				name = tableName,
				message = `Tuning.{tableName} is {typeof(sub)}, expected a table`,
			})
		else
			out[tableName] = sub
		end
	end
	return out, findings
end

--[[
	AC-4, first direction: every constant the specification names is in the
	module, with a matching value. Reported BY NAME - "Tuning mismatch" is a
	failure nobody can act on.
]]
function TuningSpec.missingOrMismatched(rows: { Row }, module: any): { Finding }
	local tables, findings = tablesOf(module)
	if tables == nil then
		return findings
	end
	local ordered = table.clone(rows)
	table.sort(ordered, function(a: Row, b: Row): boolean
		if a.tableName ~= b.tableName then
			return a.tableName < b.tableName
		end
		return a.name < b.name
	end)
	for _, row in ordered do
		local sub = (tables :: any)[row.tableName]
		if sub ~= nil then
			local actual = sub[row.name]
			local where = `{TuningSpec.SPEC_PATH} §{row.section} -> Tuning.{row.tableName}`
			if actual == nil then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): spec {row.value}, absent from the module`,
				})
			elseif typeof(actual) ~= "number" then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): spec {row.value}, module {typeof(actual)}`,
				})
			elseif actual ~= row.value then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): spec {row.value}, module {actual}`,
				})
			end
		end
	end
	return findings
end

--[[ AC-4, second direction: a constant in the module that the spec does not name. ]]
function TuningSpec.unspecified(rows: { Row }, module: any): { Finding }
	local tables, findings = tablesOf(module)
	if tables == nil then
		return findings
	end
	local found = TuningSpec.byTable(rows)
	for _, tableName in TuningSpec.TABLE_NAMES do
		local sub = (tables :: any)[tableName]
		if sub ~= nil then
			for _, key in sortedKeys(sub) do
				local bucket = found[tableName]
				if bucket == nil or bucket[key] == nil then
					table.insert(findings, {
						name = key,
						message = `{key} (Tuning.{tableName}): in the module, named nowhere in `
							.. `{TuningSpec.SPEC_PATH} §1 or §5`,
					})
				end
			end
		end
	end
	return findings
end

function TuningSpec.describe(findings: { Finding }): string
	if #findings == 0 then
		return "(no findings)"
	end
	local lines: { string } = {}
	for _, finding in findings do
		table.insert(lines, finding.message)
	end
	return table.concat(lines, "\n  ")
end

function TuningSpec.assertNoFindings(findings: { Finding }, what: string)
	assert(#findings == 0, `{what}:\n  ` .. TuningSpec.describe(findings))
end

--[[
	AC-5. `tuning.md` §7 records these absences as decisions rather than
	omissions, so the module must not reintroduce one.
]]
local ABSENT_RULES: { { matches: (string) -> boolean, why: string } } = {
	{
		matches = function(key: string): boolean
			return key == "hidden_faction_ratio"
		end,
		why = "tuning.md §7: amendment 8, there is no hidden faction",
	},
	{
		matches = function(key: string): boolean
			return string.sub(key, 1, 5) == "vote_"
		end,
		why = "tuning.md §7: there is no vote - resolution is the Procedure completing or not",
	},
	{
		matches = function(key: string): boolean
			local lower = string.lower(key)
			for _, word in { "score", "rank", "mmr", "ladder" } do
				if string.find(lower, word, 1, true) ~= nil then
					return true
				end
			end
			return false
		end,
		why = "tuning.md §7: amendment 9, no per-player score, rank, MMR or ladder constant",
	},
}
TuningSpec.ABSENT_RULES = ABSENT_RULES

function TuningSpec.absenceFindings(module: any): { Finding }
	local findings: { Finding } = {}
	if typeof(module) ~= "table" then
		return { { name = "Tuning", message = `Tuning is {typeof(module)}, expected a table` } }
	end

	local scopes: { { where: string, keys: { string } } } = {
		{ where = "Tuning", keys = sortedKeys(module) },
	}
	for _, tableName in TuningSpec.TABLE_NAMES do
		local sub = (module :: any)[tableName]
		if typeof(sub) == "table" then
			table.insert(scopes, { where = `Tuning.{tableName}`, keys = sortedKeys(sub) })
		end
	end

	for _, scope in scopes do
		for _, key in scope.keys do
			for _, rule in ABSENT_RULES do
				if rule.matches(key) then
					table.insert(findings, {
						name = key,
						message = `{key} ({scope.where}) is deliberately absent - {rule.why}`,
					})
				end
			end
		end
	end
	return findings
end

-- How many constants the module actually exposes. An absence assertion over an
-- empty module passes and proves nothing, so AC-5's check counts first.
function TuningSpec.constantCount(module: any): number
	if typeof(module) ~= "table" then
		return 0
	end
	local total = 0
	for _, tableName in TuningSpec.TABLE_NAMES do
		local sub = (module :: any)[tableName]
		if typeof(sub) == "table" then
			total += #sortedKeys(sub)
		end
	end
	return total
end

function TuningSpec.assertNoAbsentConstants(module: any)
	local count = TuningSpec.constantCount(module)
	assert(
		count >= TuningSpec.MIN_CONSTANTS,
		`AC-5: the absence check ran over a module exposing {count} constants, expected at least `
			.. `{TuningSpec.MIN_CONSTANTS}. "No key matches" is true of an empty table.`
	)
	TuningSpec.assertNoFindings(
		TuningSpec.absenceFindings(module),
		"AC-5: the module names a constant tuning.md §7 records as deliberately absent"
	)
end

return TuningSpec
