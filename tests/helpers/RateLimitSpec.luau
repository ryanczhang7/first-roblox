--!strict
--[[
	NET-003's provenance reader: the `1.5` the rate suite declares on its test
	remote is `tuning.md` §3's `signal_rate_limit_seconds`, marked DERIVED, and
	this module reads that constant out of the document's table so the suite's
	literal is anchored to the document rather than to somebody's memory.
	`tests/net/rate_limit_provenance_test.luau` applies it to the tree and
	drives it with fixtures that must fail.

	WHY `TuningSpec.parse` IS NOT REUSED: its scope is `tuning.md` §1 and §5
	only, by the same `SECTION_TABLE` filter that keeps `src/shared/Tuning.luau`
	out of §3 (`Tuning.luau:14`, `TuningSpec.luau:420-438`). A §3 constant added
	to `Tuning` would red `tuning_spec_test` and `tuning_controls_test`, which
	are ROUND-002's and frozen. So this is a small local reader over the whole
	document, and the story's Contract says so.

	HOW A ROW IS LOCATED. A markdown table row whose FIRST cell, trimmed, is
	exactly the constant's name in backticks. The first cell and nothing
	else: the name also appears in prose, in the Context of stories, and could
	appear in another row's rationale cell, and none of those is the row
	that fixes the value. The value is the SECOND cell, converted with
	`tonumber` after trimming, so `1.5 s` or `**1.5**` is "not a number"
	rather than a silent 1.5.

	WHAT THIS CANNOT SEE, stated so the next reader does not assume otherwise:
	it reads the table row as it is written today - a pipe-delimited row with
	the name in the first cell in backticks and a bare number in the second.
	A row whose name is not in backticks, a value written as `1.5 s`, a
	constant restated in prose, or a table whose columns are reordered are
	all invisible to it. That is why `violations` carries three vacuity
	assertions and the first is "exactly one row": an extraction that matches
	nothing compares nothing, and it must fail loudly rather than pass.
]]

local fs = require("@lune/fs")

local RateLimitSpec = {}

RateLimitSpec.SPEC_PATH = "docs/wiki/game/tuning.md"
RateLimitSpec.NAME = "signal_rate_limit_seconds"

-- One table row naming the constant: where it is, which `## N` section the
-- row sits under (nil above the first heading), and the raw value cell.
export type Row = { line: number, section: number?, valueCell: string }

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

--[[
	Every table row in `text` whose first cell is `` `name` `` exactly, with
	the section it sits under. Duplicates are kept, so two rows are visible to
	`violations`.
]]
function RateLimitSpec.rowsNaming(text: string, name: string): { Row }
	local wanted = "`" .. name .. "`"
	local out: { Row } = {}
	local section: number? = nil
	for lineNumber, line in string.split(text, "\n") do
		local heading = string.match(line, "^##%s+(%d+)%.")
		if heading ~= nil then
			section = tonumber(heading)
		end
		local row = cells(line)
		if row[1] == wanted then
			table.insert(out, { line = lineNumber, section = section, valueCell = row[2] or "" })
		end
	end
	return out
end

--[[
	Every way `rows` fails to fix `name` at `expected`, accumulated. The
	three vacuity assertions the Contract lists, in order: exactly one row
	(zero is the failure mode, two is a document that disagrees with itself);
	the value cell yields a number, asserted BEFORE it is compared; and that
	number equals what the suite declares.
]]
function RateLimitSpec.violations(rows: { Row }, name: string, expected: number): { string }
	local out: { string } = {}
	local path = RateLimitSpec.SPEC_PATH
	if #rows == 0 then
		table.insert(
			out,
			`{path}: no table row has \`{name}\` in its first cell - the extraction matched nothing, `
				.. `and a value compared against nothing would pass`
		)
		return out
	end
	if #rows ~= 1 then
		local lines: { string } = {}
		for _, row in rows do
			table.insert(lines, tostring(row.line))
		end
		table.insert(
			out,
			`{path}: {#rows} table rows name \`{name}\` (lines {table.concat(lines, ", ")}); expected `
				.. `exactly one`
		)
	end
	for _, row in rows do
		local where = `{path}:{row.line}` .. (if row.section ~= nil then ` §{row.section}` else "")
		local value = tonumber(row.valueCell)
		if value == nil then
			table.insert(
				out,
				`{where}: the value cell for \`{name}\` is "{row.valueCell}", which is not a number`
			)
		elseif value ~= expected then
			table.insert(
				out,
				`{where}: \`{name}\` is {value} in the document; the suite declares {expected} - `
					.. `the document is the oracle and the suite's literal must follow it`
			)
		end
	end
	return out
end

function RateLimitSpec.read(): string
	return fs.readFile(RateLimitSpec.SPEC_PATH)
end

function RateLimitSpec.describe(violations: { string }): string
	if #violations == 0 then
		return "(the document and the suite agree)"
	end
	return table.concat(violations, "\n")
end

return RateLimitSpec
