--!strict
--[[
	NET-003, AC-1's provenance: the `1.5` the rate suite declares on its test
	remote (`RateContract.MIN_INTERVAL_SECONDS`) is `tuning.md` §3's
	`signal_rate_limit_seconds`, marked DERIVED. AC-1 calls it settled - read
	it out, do not tune it - and this file is what makes "read it out" a fact
	rather than a comment: the document's table row is read, and the suite's
	literal must equal it.

	THE READER IS `tests/helpers/RateLimitSpec.luau`, and it is textual and
	local for a reason the story's Contract measured: `TuningSpec.parse`
	collects §1 and §5 only, by the same filter that keeps
	`src/shared/Tuning.luau` out of §3, and a §3 constant added to `Tuning`
	reds two frozen ROUND-002 suites. So 1.5 reaches the wrapper through the
	remote's declaration and reaches this file through the document - never
	through `Tuning`.

	THE VACUITY ASSERTIONS ARE THE POINT. An extraction that matches nothing
	compares nothing and passes, so the guard's first requirement is EXACTLY
	ONE row, the second that the value cell yields a number before it is
	compared, and only the third that the number equals the literal. The
	controls below drive each with an in-memory fixture that must fail, and
	the guard itself - green on arrival, because the document and the suite
	agree today - is earned in the story's `## Regressions` by mutating the
	real document through `scripts/mutate.sh` and watching this file go red.

	WHAT THIS CANNOT SEE: `RateLimitSpec.luau`'s header says. It reads the
	table row as it is written today.
]]

local RateContract = require("../helpers/RateContract")
local Spec = require("../helpers/RateLimitSpec")

local NAME = Spec.NAME
local EXPECTED = RateContract.MIN_INTERVAL_SECONDS

-- A three-row table in the document's shape, with the constant's row as given.
local function fixture(rows: { string }): string
	local lines = {
		"## 3. The signal channel",
		"",
		"| Constant | Value | Label | Rationale |",
		"|---|---|---|---|",
		"| `signal_budget_per_player` | 12 | **placeholder** | the most uncertain number; not the "
			.. "`signal_rate_limit_seconds` row. |",
	}
	for _, row in rows do
		table.insert(lines, row)
	end
	table.insert(
		lines,
		"| `signal_display_seconds` | 6 | **placeholder** | the attentional axis. |"
	)
	return table.concat(lines, "\n")
end

local REAL_ROW = "| `signal_rate_limit_seconds` | 1.5 | **derived** | two purposes at once. |"

local function violationsOf(text: string): { string }
	return Spec.violations(Spec.rowsNaming(text, NAME), NAME, EXPECTED)
end

return {
	--[[ The guard. ]]

	["AC-1 provenance: docs/wiki/game/tuning.md names signal_rate_limit_seconds in exactly one table row, its value cell is a number, and that number equals the 1.5 the rate suite declares"] = function()
		local text = Spec.read()
		assert(#text > 0, `{Spec.SPEC_PATH} read as an empty string`)
		local rows = Spec.rowsNaming(text, NAME)
		assert(
			#rows == 1,
			`{Spec.SPEC_PATH}: expected exactly one table row naming \`{NAME}\`, found {#rows} - the `
				.. `extraction must match before it can compare`
		)
		local value = tonumber(rows[1].valueCell)
		assert(
			typeof(value) == "number",
			`{Spec.SPEC_PATH}:{rows[1].line}: the value cell "{rows[1].valueCell}" is not a number`
		)
		local violations = Spec.violations(rows, NAME, EXPECTED)
		assert(
			#violations == 0,
			`the suite's {NAME} = {EXPECTED} does not match the document, which is the oracle (AC-1 `
				.. `calls it settled: read out, never tuned):\n{Spec.describe(violations)}`
		)
	end,

	--[[ Controls: each vacuity assertion, and the comparison, driven to fail. ]]

	["provenance control: a document in which the name appears only in prose and in another row's rationale has no row - the extraction matches nothing and says so, rather than comparing nothing"] = function()
		local text = fixture({})
		local rows = Spec.rowsNaming(text, NAME)
		assert(#rows == 0, `expected no rows, found {#rows}`)
		local violations = violationsOf(text)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		assert(
			string.find(violations[1], "the extraction matched nothing", 1, true) ~= nil,
			`the vacuity failure is not named:\n{violations[1]}`
		)
		assert(
			string.find(
				violations[1],
				"no table row has `signal_rate_limit_seconds` in its first cell",
				1,
				true
			) ~= nil,
			`the missing row is not named:\n{violations[1]}`
		)
	end,

	["provenance control: two rows naming the constant are reported by count and line, even when both carry the right value"] = function()
		local text = fixture({ REAL_ROW, REAL_ROW })
		local rows = Spec.rowsNaming(text, NAME)
		assert(#rows == 2, `expected 2 rows, found {#rows}`)
		local violations = violationsOf(text)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		assert(
			string.find(
				violations[1],
				"2 table rows name `signal_rate_limit_seconds` (lines 6, 7)",
				1,
				true
			) ~= nil,
			`the duplicate rows are not named by line:\n{violations[1]}`
		)
	end,

	["provenance control: a value cell that is not a bare number - `1.5 s` - is reported as not a number, not silently read as 1.5"] = function()
		local text =
			fixture({ "| `signal_rate_limit_seconds` | 1.5 s | **derived** | with a unit. |" })
		local violations = violationsOf(text)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		assert(
			string.find(
				violations[1],
				'the value cell for `signal_rate_limit_seconds` is "1.5 s", which is not a number',
				1,
				true
			) ~= nil,
			`the non-number is not named:\n{violations[1]}`
		)
		assert(
			string.find(violations[1], "§3", 1, true) ~= nil,
			`the section is not reported:\n{violations[1]}`
		)
	end,

	["provenance control: a document value of 2 is reported against the suite's 1.5, naming both numbers and the document as the oracle"] = function()
		local text = fixture({ "| `signal_rate_limit_seconds` | 2 | **derived** | retuned. |" })
		local violations = violationsOf(text)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		assert(
			string.find(
				violations[1],
				"`signal_rate_limit_seconds` is 2 in the document; the suite declares 1.5",
				1,
				true
			) ~= nil,
			`the mismatch is not named:\n{violations[1]}`
		)
	end,

	["provenance control: the real row shape yields the value 1.5 and no violation, and a row whose first cell is a longer name containing this one is not a match"] = function()
		local text = fixture({
			"| `signal_rate_limit_seconds_v2` | 9 | **placeholder** | a different constant. |",
			REAL_ROW,
		})
		local rows = Spec.rowsNaming(text, NAME)
		assert(#rows == 1, `expected 1 row, found {#rows}`)
		assert(rows[1].line == 7, `expected the row at line 7, found line {rows[1].line}`)
		assert(rows[1].section == 3, `expected section 3, found {rows[1].section}`)
		assert(tonumber(rows[1].valueCell) == 1.5, `expected 1.5, found "{rows[1].valueCell}"`)
		local violations = violationsOf(text)
		assert(#violations == 0, `expected no violation:\n{Spec.describe(violations)}`)
	end,
}
