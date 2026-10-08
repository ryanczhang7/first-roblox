--!strict
--[[
	The rate-limit provenance reader, re-pointed by ROUND-006 at the preset
	design (product-brief §0d #19, #23; `tuning.md` §3 third pass).

	HISTORY. NET-003 wrote this to anchor the rate suite's `1.5` to `tuning.md`
	§3's `signal_rate_limit_seconds`. Brief §0d #19 superseded that constant on
	2026-09-30 (`tuning.md` §9): the channel is now presets and pings, each
	limited by `preset_rate_limit_seconds` / `ping_rate_limit_seconds`. From
	ROUND-006 on, the rate suite's 1.5 is a FIXTURE interval with no design
	provenance (see `RateContract.luau`'s header), and this reader guards the
	document instead: both rate rows exist exactly once, each is a bare number,
	each is at least the preset guideline's floor, and the superseded name has
	no live row.

	THE FLOOR IS AN ORACLE, NOT A COPY. `FLOOR_SECONDS` is the published preset
	guideline's "Add a rate-limit (10 seconds per send)", quoted by brief §0d
	#19 and applied to pings by #23. The comparison is `value >= floor`, not
	`value == 10`: equality would be a second copy of the document's number
	with nothing behind it, while the floor fails for the change that matters -
	a rate lowered below compliance.

	WHY `TuningSpec.parse` IS NOT REUSED: its scope is `tuning.md` §1 and §5
	only, by the same `SECTION_TABLE` filter that keeps `src/ReplicatedStorage/Shared/Tuning.luau`
	out of §3. A §3 constant added to `Tuning` would red ROUND-002's module-to-
	spec guard. So this is a small local reader over the whole document.

	HOW A ROW IS LOCATED. A markdown table row whose FIRST cell, trimmed, is
	exactly the constant's name in backticks. The first cell and nothing else:
	the name also appears in prose and in other rows' rationale cells, and none
	of those fixes the value. §9's `~~`signal_rate_limit_seconds`~~` is struck
	through, so its first cell is not the bare backticked name and it is not a
	live row - which is the intended reading. The value is the SECOND cell,
	converted with `tonumber` after trimming, so `10 s` or `**10**` is "not a
	number" rather than a silent 10.

	WHAT THIS CANNOT SEE: a row whose name is not in backticks, a value with a
	unit, a constant restated in prose, or reordered columns. That is why
	`violations` carries three vacuity steps and the first is "exactly one
	row": an extraction that matches nothing compares nothing, and it must fail
	loudly rather than pass.
]]

local fs = require("./GatedFs")

local RateLimitSpec = {}

RateLimitSpec.SPEC_PATH = "docs/wiki/game/tuning.md"

-- The live rate constants of `tuning.md` §3 (third pass).
RateLimitSpec.NAMES = { "preset_rate_limit_seconds", "ping_rate_limit_seconds" }

-- The second-pass constant they replace (§9). It must have no live row.
RateLimitSpec.SUPERSEDED = "signal_rate_limit_seconds"

-- brief §0d #19 quoting the preset guideline ("10 seconds per send"); #23 for pings.
RateLimitSpec.FLOOR_SECONDS = 10

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

local function whereOf(row: Row): string
	return `{RateLimitSpec.SPEC_PATH}:{row.line}`
		.. (if row.section ~= nil then ` §{row.section}` else "")
end

--[[
	Every way `rows` fails to fix `name` at or above `floor`, accumulated. The
	three vacuity steps, in order: exactly one row (zero is the failure mode,
	two is a document that disagrees with itself); the value cell yields a
	number, asserted BEFORE it is compared; and only then `value >= floor`.
]]
function RateLimitSpec.violations(rows: { Row }, name: string, floor: number): { string }
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
		local value = tonumber(row.valueCell)
		if value == nil then
			table.insert(
				out,
				`{whereOf(row)}: the value cell for \`{name}\` is "{row.valueCell}", which is not a number`
			)
		elseif not (value >= floor) then
			table.insert(
				out,
				`{whereOf(row)}: \`{name}\` is {value} in the document, below the floor of {floor} - `
					.. `the preset guideline's "10 seconds per send" (brief §0d #19; #23 for pings) `
					.. `is a compliance requirement, not tuning`
			)
		end
	end
	return out
end

--[[
	Every LIVE table row whose first cell is the bare backticked `SUPERSEDED`
	name. §9's struck-through record (`~~`name`~~`) is not a match.
]]
function RateLimitSpec.supersededViolations(text: string): { string }
	local name = RateLimitSpec.SUPERSEDED
	local replacements = "`" .. table.concat(RateLimitSpec.NAMES, "` and `") .. "`"
	local out: { string } = {}
	for _, row in RateLimitSpec.rowsNaming(text, name) do
		table.insert(
			out,
			`{whereOf(row)}: a live table row has \`{name}\` in its first cell, but it is a superseded `
				.. `constant (brief §0d #19, tuning.md §9) - replaced by {replacements}`
		)
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
