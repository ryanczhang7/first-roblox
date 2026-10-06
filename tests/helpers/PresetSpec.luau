--!strict
--[[
	CHAN-002: the preset-table reader over `docs/wiki/game/mechanics.md` §4.2.

	`mechanics.md` §4.2 IS the preset table (the operator's T12 choice). This
	module reads the rows out of the document, through `GatedFs` (the file is
	in the gate hash: project.conf has `covers | unit | docs/wiki/game/mechanics.md`),
	so that `presets_test.luau` compares `Presets.ALL` to the document rather
	than to a copy of it typed into a test. AC-1 is a SETTLED criterion: the
	words are read out, never restated here.

	HOW A ROW IS LOCATED (story `## Contract` P-2). A `|`-delimited line under
	the heading `### 4.2 The preset wheel`, before the next heading, whose
	FIRST cell (trimmed) is exactly ONE backtick-quoted string. The word is the
	text between the backticks, kept exactly - case and inner spaces. The THIRD
	cell is the phases, split on `,`, each trimmed, empty pieces dropped. Order
	is file order. The header row (`| Preset | ... |`) and the `|---|` row have
	no backticked first cell and are skipped. The section ends at the next
	markdown heading of any level - P-2 says "the next `###`", and `### 4.3` is
	the heading that follows; stopping at `## 5` too would only matter if §4.3
	vanished, and then a table from §5 must not be read as presets.

	VACUITY FIRST, as `RateLimitSpec` does. A parser that matches nothing
	compares nothing and passes forever, so `vacuity` is asserted BEFORE any
	comparison: exactly `EXPECTED_ROWS` rows (P-2: ten), each with a non-empty
	word, each with at least one phase. The controls in
	`tests/shared/presets_controls_test.luau` drive `rows` over fixture texts
	that are wrong on purpose - no heading, nine rows, an empty phases cell -
	and show each step firing.

	WHAT THIS CANNOT SEE: a preset whose first cell is not in backticks, a
	table whose phases are in a column other than the third, or a heading
	renamed away from `### 4.2 The preset wheel`. Each of those yields fewer
	than ten rows, which is what the first vacuity step is for.
]]

local fs = require("./GatedFs")

local PresetSpec = {}

PresetSpec.SPEC_PATH = "docs/wiki/game/mechanics.md"
PresetSpec.HEADING = "### 4.2 The preset wheel"

-- P-2's first vacuity step. The operator chose ten (T12); `tuning.md`'s
-- `preset_count` is the same number and `presets_test.luau` asserts that too.
PresetSpec.EXPECTED_ROWS = 10

-- One preset row: where it is, the word exactly as written, its phases in
-- cell order.
export type Row = { line: number, word: string, phases: { string } }

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") :: string
end

-- The cells of a pipe-delimited row, trimmed, leading and trailing pipe
-- removed. A line that is not a table row yields an empty list.
local function cells(line: string): { string }
	local body = trim(line)
	if string.sub(body, 1, 1) ~= "|" then
		return {}
	end
	body = string.sub(body, 2)
	if string.sub(body, -1) == "|" then
		body = string.sub(body, 1, -2)
	end
	local out: { string } = {}
	for cell in string.gmatch(body .. "|", "([^|]*)|") do
		table.insert(out, trim(cell))
	end
	return out
end

-- The phases cell split on `,`, each trimmed, empty pieces dropped.
local function splitPhases(cell: string?): { string }
	local out: { string } = {}
	if cell == nil then
		return out
	end
	for piece in string.gmatch(cell .. ",", "([^,]*),") do
		local phase = trim(piece)
		if phase ~= "" then
			table.insert(out, phase)
		end
	end
	return out
end

--[[
	Every preset row of `text` under `HEADING`, in file order. Duplicated
	words are kept, so a document naming a preset twice is visible to the
	comparison.
]]
function PresetSpec.rows(text: string): { Row }
	local out: { Row } = {}
	local inSection = false
	for lineNumber, raw in string.split(text, "\n") do
		local line = trim(raw)
		if line == PresetSpec.HEADING then
			inSection = true
			continue
		end
		if inSection and string.match(line, "^#+%s") ~= nil then
			break
		end
		if not inSection then
			continue
		end
		local row = cells(line)
		if row[1] == nil then
			continue
		end
		local word = string.match(row[1], "^`([^`]*)`$")
		if word == nil then
			continue
		end
		table.insert(out, { line = lineNumber, word = word, phases = splitPhases(row[3]) })
	end
	return out
end

--[[
	Every way `rows` fails to be a readable preset table, accumulated: exactly
	`expected` rows (zero is "the extraction matched nothing"), each with a
	non-empty word, each with at least one phase. Asserted before any
	comparison, so an unread document is a loud failure, never a quiet pass.
]]
function PresetSpec.vacuity(rows: { Row }, expected: number): { string }
	local out: { string } = {}
	local path = PresetSpec.SPEC_PATH
	if #rows == 0 then
		table.insert(
			out,
			`{path}: no table row under "{PresetSpec.HEADING}" has a backticked first cell - the `
				.. `extraction matched nothing, and a module compared against nothing would pass`
		)
		return out
	end
	if #rows ~= expected then
		local words: { string } = {}
		for _, row in rows do
			table.insert(words, `"{row.word}"`)
		end
		table.insert(
			out,
			`{path}: {#rows} preset row(s) under "{PresetSpec.HEADING}" ({table.concat(words, ", ")}); `
				.. `expected exactly {expected}`
		)
	end
	for _, row in rows do
		if row.word == "" then
			table.insert(out, `{path}:{row.line}: a preset row has an empty word`)
		end
		if #row.phases == 0 then
			table.insert(
				out,
				`{path}:{row.line}: the preset "{row.word}" has no phases in its third cell`
			)
		end
	end
	return out
end

function PresetSpec.read(): string
	return fs.readFile(PresetSpec.SPEC_PATH)
end

function PresetSpec.describe(violations: { string }): string
	if #violations == 0 then
		return "(the document reads as a preset table)"
	end
	return table.concat(violations, "\n")
end

return PresetSpec
