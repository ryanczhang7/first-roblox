--!strict
--[[
	TUNE-001's criteria, written once, as checks over a MODULE-SHAPED TABLE.

	`tests/shared/mechanics_tuning_spec_test.luau` applies them to
	`src/ReplicatedStorage/Shared/MechanicsTuning.luau`, which is the story.
	`tests/shared/mechanics_tuning_controls_test.luau` applies the same objects
	to deliberately wrong fixtures and fake tables, and requires NO production
	code, so every control here RUNS during RED while the module does not exist.
	ROUND-002's `TuningSpec.luau` established the shape; this file is its sibling
	for `tuning.md` §2, §3 and §4 - a sibling, NOT an extension. `TuningSpec.parse`
	is scoped to §1 and §5 by its own `SECTION_TABLE` and reads only numbers;
	`RateLimitSpec` locates two named rows anywhere. Neither reads a boolean, a
	reference or a rule row, and widening either would change what ROUND-002's
	and NET-003's frozen tests mean.

	THE ORACLE. `docs/wiki/game/tuning.md` declares itself the specification, so
	the guard PARSES it rather than carrying a copy of the numbers. Unlike
	`TuningSpec` there is no frozen `ACCEPTANCE` list here: TUNE-001's criteria
	name no value (AC-2 and AC-4 are "settled" - read out, never restated), so
	the document is the one oracle and this file holds no number from it.

	THE FOUR KINDS (AC-1). Every row of §2-§4 whose first cell, trimmed, is
	exactly one backticked name - and whose name does not start with `INV_` - is
	exactly one of:

	  number     the value cell is a bare decimal          -> module value
	  boolean    the value cell is `true` or `false`       -> module value
	  reference  the value cell is exactly `= \`other\``   -> module value equal
	                                                          to the module's
	                                                          value for `other`
	  rule       the name is in RULE_ROWS                  -> absent from module

	A row that is none of these is REPORTED in `Parsed.problems`, never skipped,
	for the reason the per-section row floor exists: a parser that silently
	matches nothing compares nothing and passes. So is a RULE_ROWS name whose
	value cell classifies as a number, boolean or reference - "exactly one kind"
	is asserted in both directions.

	WHAT THIS CANNOT SEE. A constant stated in prose, a value with a unit, a name
	outside backticks. The document's own preface ("tests read this file") keeps
	§2-§4's value cells to the four shapes above, and this parser is what makes
	that rule enforceable.
]]

local Contract = require("./Contract")
local fs = require("./GatedFs")

local MechanicsTuningSpec = {}

MechanicsTuningSpec.SPEC_PATH = "docs/wiki/game/tuning.md"

-- The three sections in scope and the module table each maps onto. Sub-tables
-- under `###` headings belong to their `##` section: only a `## N.` line
-- changes the current section.
local SECTION_TABLE: { [number]: string } = {
	[2] = "instance",
	[3] = "channel",
	[4] = "actuation",
}
MechanicsTuningSpec.SECTION_TABLE = SECTION_TABLE

MechanicsTuningSpec.TABLE_NAMES = { "instance", "channel", "actuation" }
MechanicsTuningSpec.SECTIONS = { 2, 3, 4 }

local TABLE_SECTION: { [string]: number } = {}
for section, tableName in SECTION_TABLE do
	TABLE_SECTION[tableName] = section
end
MechanicsTuningSpec.TABLE_SECTION = TABLE_SECTION

--[[
	Rows that are rules, not module constants. The ONLY list in this file, and it
	is a list of names, not of values: a name here whose value cell turns out to
	be a number or a boolean is a parse problem (AC-1), so the list cannot
	quietly absorb a constant.
]]
MechanicsTuningSpec.RULE_ROWS = {
	-- §2
	"key_classes",
	"actuators_per_class",
	"spawn_room",
	-- §3
	"channel_limiter_consumed_by",
	"ping_budget_per_player",
	-- §4
	"blackout_selection",
	"hud_round_clock_form",
}

local RULE_SET: { [string]: boolean } = {}
for _, name in MechanicsTuningSpec.RULE_ROWS do
	RULE_SET[name] = true
end

export type Kind = "number" | "boolean" | "reference" | "rule"

export type Row = {
	name: string,
	kind: Kind,
	-- number and boolean rows only.
	value: (number | boolean)?,
	-- reference rows only: the referent's name.
	ref: string?,
	section: number,
	tableName: string,
	line: number,
}

export type Parsed = { rows: { Row }, problems: { string } }

export type Finding = { name: string, message: string }

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$")) :: string
end

-- The cells of a markdown table row, trimmed. Only cells 1 and 2 are ever read.
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

MechanicsTuningSpec.sortedKeys = sortedKeys

--[[
	Classify one value cell. Returns the kind the CELL has on its own (never
	"rule" - that is a property of the name), or nil when the cell is none of
	number, boolean or reference.
]]
local function classifyCell(cell: string): (Kind?, (number | boolean)?, string?)
	if string.match(cell, "^%-?%d+%.?%d*$") ~= nil then
		local number = tonumber(cell)
		if number ~= nil then
			return "number", number, nil
		end
	end
	if cell == "true" then
		return "boolean", true, nil
	end
	if cell == "false" then
		return "boolean", false, nil
	end
	local ref = string.match(cell, "^=%s*`([%w_]+)`$")
	if ref ~= nil then
		return "reference", nil, ref
	end
	return nil, nil, nil
end

MechanicsTuningSpec.classifyCell = classifyCell

--[[
	Every row of §2, §3 and §4 whose first cell is a bare backticked name, with
	its kind. A `## <n>.` line opens a section; a `### ...` line does not, so
	"The layout" and the HUD sub-table stay in §2 and §4, and a numbered section
	outside `SECTION_TABLE` (§5 onwards, §1) collects nothing.
]]
function MechanicsTuningSpec.parse(text: string): Parsed
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

		local name = string.match(cell[1], "^`([%w_]+)`$")
		if name == nil or string.sub(name, 1, 4) == "INV_" then
			continue
		end

		local where = `{MechanicsTuningSpec.SPEC_PATH}:{lineNumber} §{section}`
		local cellKind, value, ref = classifyCell(cell[2])

		if RULE_SET[name] then
			if cellKind ~= nil then
				table.insert(
					problems,
					`{where}: "{name}" is in RULE_ROWS but its value cell "{cell[2]}" is a `
						.. `{cellKind} - a rule row cannot also be a constant`
				)
				continue
			end
			table.insert(rows, {
				name = name,
				kind = "rule",
				section = section,
				tableName = tableName,
				line = lineNumber,
			})
			continue
		end

		if cellKind == nil then
			table.insert(
				problems,
				`{where}: "{name}" = "{cell[2]}" is none of number, boolean, reference `
					.. `(= \`name\`) or a RULE_ROWS name`
			)
			continue
		end

		table.insert(rows, {
			name = name,
			kind = cellKind :: Kind,
			value = value,
			ref = ref,
			section = section,
			tableName = tableName,
			line = lineNumber,
		})
	end

	return { rows = rows, problems = problems }
end

function MechanicsTuningSpec.read(): Parsed
	return MechanicsTuningSpec.parse(fs.readFile(MechanicsTuningSpec.SPEC_PATH))
end

function MechanicsTuningSpec.byTable(rows: { Row }): { [string]: { [string]: Row } }
	local out: { [string]: { [string]: Row } } = {}
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
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

-- Rows by name across every section, for resolving a reference's referent.
function MechanicsTuningSpec.byName(rows: { Row }): { [string]: Row }
	local out: { [string]: Row } = {}
	for _, row in rows do
		out[row.name] = row
	end
	return out
end

-- How many rows of each kind each section yielded. The counts the handoff
-- records, and what the per-section floor reads.
function MechanicsTuningSpec.countBySection(parsed: Parsed): { [number]: { [string]: number } }
	local out: { [number]: { [string]: number } } = {}
	for _, section in MechanicsTuningSpec.SECTIONS do
		out[section] = { number = 0, boolean = 0, reference = 0, rule = 0, total = 0 }
	end
	for _, row in parsed.rows do
		local bucket = out[row.section]
		if bucket ~= nil then
			bucket[row.kind] += 1
			bucket.total += 1
		end
	end
	return out
end

--[[ AC-1: every backticked row classified as exactly one kind. ]]
function MechanicsTuningSpec.assertNoParseProblems(parsed: Parsed)
	if #parsed.problems ~= 0 then
		Contract.fail(
			`AC-1: {#parsed.problems} row(s) of {MechanicsTuningSpec.SPEC_PATH} §2-§4 fit none of the `
				.. `four kinds. A row the guard cannot classify is a constant it is not checking:\n  `
				.. table.concat(parsed.problems, "\n  ")
		)
	end
end

--[[
	AC-3: the guard's own liveness. A markdown-table parser that matches nothing
	parses zero rows, compares all zero of them successfully and reports green,
	so every section in scope must have yielded at least one row before any
	comparison is believed.
]]
function MechanicsTuningSpec.assertEverySectionHasRows(parsed: Parsed)
	local counts = MechanicsTuningSpec.countBySection(parsed)
	local empty: { string } = {}
	for _, section in MechanicsTuningSpec.SECTIONS do
		if counts[section].total == 0 then
			table.insert(
				empty,
				`§{section} (-> MechanicsTuning.{SECTION_TABLE[section]}): 0 rows parsed`
			)
		end
	end
	if #empty ~= 0 then
		Contract.fail(
			`AC-3: the guard parsed {#parsed.rows} rows from {MechanicsTuningSpec.SPEC_PATH} but a `
				.. `section in scope yielded none. A parser that matches nothing compares nothing `
				.. `and passes:\n  `
				.. table.concat(empty, "\n  ")
		)
	end
end

local function tablesOf(module: any): (any, { Finding })
	local findings: { Finding } = {}
	if typeof(module) ~= "table" then
		table.insert(findings, {
			name = "MechanicsTuning",
			message = `MechanicsTuning is {typeof(module)}, expected a table`,
		})
		return nil, findings
	end
	local out: { [string]: any } = {}
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		local sub = (module :: any)[tableName]
		if typeof(sub) ~= "table" then
			table.insert(findings, {
				name = tableName,
				message = `MechanicsTuning.{tableName} is {typeof(sub)}, expected a table`,
			})
		else
			out[tableName] = sub
		end
	end
	return out, findings
end

-- The module's value for `name`, searched across its three tables, with the
-- table it was found in. A referent may live in a different section from the
-- row that references it (§3's `ping_range_studs` -> §2's `lens_read_range_studs`).
local function lookup(tables: any, name: string): (any, string?)
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		local sub = tables[tableName]
		if sub ~= nil and sub[name] ~= nil then
			return sub[name], tableName
		end
	end
	return nil, nil
end

local function sortRows(rows: { Row }): { Row }
	local ordered = table.clone(rows)
	table.sort(ordered, function(a: Row, b: Row): boolean
		if a.tableName ~= b.tableName then
			return a.tableName < b.tableName
		end
		return a.name < b.name
	end)
	return ordered
end

--[[
	AC-2, spec -> module. Number and boolean rows: present under the section's
	table with an equal value of the same type. Reference rows: present, and
	equal to the module's own value for the referent. Rule rows: ABSENT.
	Reported BY NAME, with both values - "mismatch" is a failure nobody can act on.
]]
function MechanicsTuningSpec.missingOrMismatched(rows: { Row }, module: any): { Finding }
	local tables, findings = tablesOf(module)
	if tables == nil then
		return findings
	end
	for _, row in sortRows(rows) do
		local sub = (tables :: any)[row.tableName]
		if sub == nil then
			continue
		end
		local actual = sub[row.name]
		local where = `{MechanicsTuningSpec.SPEC_PATH}:{row.line} §{row.section} -> `
			.. `MechanicsTuning.{row.tableName}`

		if row.kind == "rule" then
			if actual ~= nil then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): a rule row, not a constant, but the module `
						.. `carries it as {tostring(actual)}`,
				})
			end
		elseif actual == nil then
			local spec = if row.kind == "reference"
				then `= \`{row.ref :: string}\``
				else tostring(row.value)
			table.insert(findings, {
				name = row.name,
				message = `{row.name} ({where}): spec {spec}, absent from the module`,
			})
		elseif row.kind == "reference" then
			local ref = row.ref :: string
			local referent, refTable = lookup(tables, ref)
			if referent == nil then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): spec = \`{ref}\`, but the module has no `
						.. `\`{ref}\` under instance, channel or actuation`,
				})
			elseif actual ~= referent then
				table.insert(findings, {
					name = row.name,
					message = `{row.name} ({where}): spec = \`{ref}\`, module {tostring(actual)} `
						.. `but MechanicsTuning.{refTable :: string}.{ref} is {tostring(referent)}`,
				})
			end
		elseif typeof(actual) ~= row.kind then
			table.insert(findings, {
				name = row.name,
				message = `{row.name} ({where}): spec {tostring(row.value)} ({row.kind}), module `
					.. `{tostring(actual)} ({typeof(actual)})`,
			})
		elseif actual ~= row.value then
			table.insert(findings, {
				name = row.name,
				message = `{row.name} ({where}): spec {tostring(row.value)}, module {tostring(
					actual
				)}`,
			})
		end
	end
	return findings
end

--[[ AC-2, module -> spec: a key in the module that no row names. ]]
function MechanicsTuningSpec.unspecified(rows: { Row }, module: any): { Finding }
	local tables, findings = tablesOf(module)
	if tables == nil then
		return findings
	end
	local found = MechanicsTuningSpec.byTable(rows)
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		local sub = (tables :: any)[tableName]
		if sub ~= nil then
			for _, key in sortedKeys(sub) do
				local bucket = found[tableName]
				local row = if bucket ~= nil then bucket[key] else nil
				if row == nil or row.kind == "rule" then
					table.insert(findings, {
						name = key,
						message = `{key} (MechanicsTuning.{tableName}): in the module, named by no `
							.. `constant row of {MechanicsTuningSpec.SPEC_PATH} §{TABLE_SECTION[tableName]}`,
					})
				end
			end
		end
	end
	return findings
end

--[[
	AC-4: the derived relations the document states, computed from module values.
	Every operand is READ from `mechanics` (MechanicsTuning-shaped) or `tuning`
	(Tuning-shaped); nothing here carries a number from the document. A missing
	or non-numeric operand is a finding of its own rather than an arithmetic error.
]]
type Relation = {
	name: string,
	statement: string,
	operands: { { string } }, -- { tableName, key } pairs; tableName may be "round"/"session" (Tuning)
	holds: (v: { [string]: number }) -> (boolean, string),
}

local RELATIONS: { Relation } = {
	{
		name = "actuator_count",
		statement = "actuator_count = procedure_length × actuator_redundancy",
		operands = {
			{ "instance", "actuator_count" },
			{ "instance", "procedure_length" },
			{ "instance", "actuator_redundancy" },
		},
		holds = function(v)
			local rhs = v.procedure_length * v.actuator_redundancy
			return v.actuator_count == rhs, `{v.actuator_count} vs {rhs}`
		end,
	},
	{
		name = "steps_per_track",
		statement = "steps_per_track = procedure_length / procedure_tracks",
		operands = {
			{ "instance", "steps_per_track" },
			{ "instance", "procedure_length" },
			{ "instance", "procedure_tracks" },
		},
		holds = function(v)
			local rhs = v.procedure_length / v.procedure_tracks
			return v.steps_per_track == rhs, `{v.steps_per_track} vs {rhs}`
		end,
	},
	{
		name = "machine_spacing_min_studs",
		statement = "machine_spacing_min_studs = 2 × turn_range_studs",
		operands = {
			{ "instance", "machine_spacing_min_studs" },
			{ "instance", "turn_range_studs" },
		},
		holds = function(v)
			local rhs = 2 * v.turn_range_studs
			return v.machine_spacing_min_studs == rhs, `{v.machine_spacing_min_studs} vs {rhs}`
		end,
	},
	{
		name = "machines_per_class_max",
		statement = "machines_per_class_max = ceil(procedure_length / players_min) × actuator_redundancy",
		operands = {
			{ "instance", "machines_per_class_max" },
			{ "instance", "procedure_length" },
			{ "session", "players_min" },
			{ "instance", "actuator_redundancy" },
		},
		holds = function(v)
			local rhs = math.ceil(v.procedure_length / v.players_min) * v.actuator_redundancy
			return v.machines_per_class_max == rhs, `{v.machines_per_class_max} vs {rhs}`
		end,
	},
	{
		name = "per_operation_seconds",
		statement = "Tuning.round.per_operation_seconds = (round_seconds − traversal_reserve_seconds) / procedure_length",
		operands = {
			{ "round", "per_operation_seconds" },
			{ "round", "round_seconds" },
			{ "round", "traversal_reserve_seconds" },
			{ "instance", "procedure_length" },
		},
		holds = function(v)
			local rhs = (v.round_seconds - v.traversal_reserve_seconds) / v.procedure_length
			return v.per_operation_seconds == rhs, `{v.per_operation_seconds} vs {rhs}`
		end,
	},
	{
		name = "presets_plus_pings_max",
		statement = "preset_count + ping_kinds ≤ presets_plus_pings_max",
		operands = {
			{ "channel", "preset_count" },
			{ "channel", "ping_kinds" },
			{ "channel", "presets_plus_pings_max" },
		},
		holds = function(v)
			local lhs = v.preset_count + v.ping_kinds
			return lhs <= v.presets_plus_pings_max, `{lhs} vs {v.presets_plus_pings_max}`
		end,
	},
}
MechanicsTuningSpec.RELATION_COUNT = #RELATIONS

local TUNING_TABLES: { [string]: boolean } = { session = true, round = true }

function MechanicsTuningSpec.relationFindings(mechanics: any, tuning: any): { Finding }
	local findings: { Finding } = {}
	for _, relation in RELATIONS do
		local values: { [string]: number } = {}
		local missing: { string } = {}
		for _, operand in relation.operands do
			local tableName, key = operand[1], operand[2]
			local root = if TUNING_TABLES[tableName] then tuning else mechanics
			local rootName = if TUNING_TABLES[tableName] then "Tuning" else "MechanicsTuning"
			local sub = if typeof(root) == "table" then root[tableName] else nil
			local value = if typeof(sub) == "table" then sub[key] else nil
			if typeof(value) ~= "number" then
				table.insert(missing, `{rootName}.{tableName}.{key} is {typeof(value)}`)
			else
				values[key] = value
			end
		end
		if #missing ~= 0 then
			table.insert(findings, {
				name = relation.name,
				message = `{relation.statement}: cannot be computed - `
					.. table.concat(missing, ", "),
			})
			continue
		end
		local ok, detail = relation.holds(values)
		if not ok then
			local shown: { string } = {}
			for _, operand in relation.operands do
				table.insert(shown, `{operand[2]} = {values[operand[2]]}`)
			end
			table.insert(findings, {
				name = relation.name,
				message = `{relation.statement} does not hold: {detail} ({table.concat(shown, ", ")})`,
			})
		end
	end
	return findings
end

--[[
	AC-5: the whole structure is frozen. One attempt per target: the write must
	RAISE and the value must be unchanged afterwards. A `__newindex` that
	swallows the write satisfies "unchanged" while failing "raises"; a plain
	table satisfies neither. Both are findings. The value is put back if the
	write got through, so one unfrozen table does not cascade.

	NOT asserted: what the error says, or whether `table.freeze` or a metatable
	did it. Only that every attempt fails.
]]
local function attempt(target: any, key: string, value: any, what: string, findings: { Finding })
	local before = target[key]
	local ok = pcall(function()
		target[key] = value
	end)
	local after = target[key]
	if after ~= before then
		pcall(function()
			target[key] = before
		end)
	end
	if ok then
		table.insert(findings, { name = what, message = `{what} succeeded; the write must raise` })
	elseif after ~= before then
		table.insert(findings, {
			name = what,
			message = `{what} raised but the value changed from {tostring(before)} to {tostring(
				after
			)}`,
		})
	end
end

function MechanicsTuningSpec.freezeFindings(module: any): { Finding }
	local findings: { Finding } = {}
	if typeof(module) ~= "table" then
		return {
			{
				name = "MechanicsTuning",
				message = `MechanicsTuning is {typeof(module)}, expected a table`,
			},
		}
	end
	-- The root: replace a table, add a table.
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		attempt(module, tableName, {}, `MechanicsTuning.{tableName} = \{}`, findings)
	end
	attempt(module, "__probe_table", {}, "MechanicsTuning.__probe_table = {}", findings)
	-- Each table: overwrite every existing key, add a new one.
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		local sub = module[tableName]
		if typeof(sub) ~= "table" then
			table.insert(findings, {
				name = tableName,
				message = `MechanicsTuning.{tableName} is {typeof(sub)}, expected a table`,
			})
			continue
		end
		for _, key in sortedKeys(sub) do
			attempt(
				sub,
				key,
				"__probe_value",
				`MechanicsTuning.{tableName}.{key} = "__probe_value"`,
				findings
			)
		end
		attempt(sub, "__probe_key", 1, `MechanicsTuning.{tableName}.__probe_key = 1`, findings)
	end
	return findings
end

function MechanicsTuningSpec.describe(findings: { Finding }): string
	if #findings == 0 then
		return "(no findings)"
	end
	local lines: { string } = {}
	for _, finding in findings do
		table.insert(lines, finding.message)
	end
	return table.concat(lines, "\n  ")
end

function MechanicsTuningSpec.assertNoFindings(findings: { Finding }, what: string)
	if #findings ~= 0 then
		Contract.fail(`{what}:\n  ` .. MechanicsTuningSpec.describe(findings))
	end
end

return MechanicsTuningSpec
