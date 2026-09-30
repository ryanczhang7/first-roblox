--!strict
--[[
	ROUND-006 AC-4: the rate-limit provenance guard, re-pointed at the preset
	design (product-brief §0d #19, #23; `tuning.md` §3 third pass).

	Until ROUND-006 this file anchored the rate suite's `1.5` to `tuning.md`
	§3's `signal_rate_limit_seconds` (NET-003 AC-1). Brief §0d #19 superseded
	that constant; `tuning.md` §9 records it struck through. The rate suite's
	1.5 is now a fixture interval (`RateContract.luau`'s header), so this file
	no longer compares against the suite at all - it guards the DOCUMENT:

	  - exactly one live row each for `preset_rate_limit_seconds` and
	    `ping_rate_limit_seconds`, each a bare number, each >= the preset
	    guideline's floor of 10 s (brief §0d #19; #23 for pings). The floor is
	    SETTLED - an oracle, not a number chosen here;
	  - no live row for the superseded `signal_rate_limit_seconds`.

	THE VACUITY STEPS ARE THE POINT. An extraction that matches nothing
	compares nothing and passes, so `violations` first requires EXACTLY ONE
	row, then a numeric value cell, and only then compares. The controls below
	drive each step with an in-memory fixture that must fail. The guards
	themselves are green on arrival (the document already says 10 / 10) and
	are earned in ROUND-006's `## Handoff` by mutating the real document
	through `scripts/mutate.sh` (probes P2, P3).

	WHAT THIS CANNOT SEE: `RateLimitSpec.luau`'s header says.
]]

local Spec = require("../helpers/RateLimitSpec")

local PRESET = "preset_rate_limit_seconds"
local PING = "ping_rate_limit_seconds"

-- A §3-shaped table with the given rows between two unrelated constants. The
-- first filler row mentions every rate name in its rationale cell, so a reader
-- that matched anywhere but the first cell would find them there.
local function fixture(rows: { string }): string
	local lines = {
		"## 3. The channel — pings and presets",
		"",
		"| Constant | Value | Label | Rationale |",
		"|---|---|---|---|",
		"| `preset_count` | 10 | **taste** | not the `preset_rate_limit_seconds` row, nor "
			.. "`ping_rate_limit_seconds`, nor `signal_rate_limit_seconds`. |",
	}
	for _, row in rows do
		table.insert(lines, row)
	end
	table.insert(lines, "| `ping_display_seconds` | 15 | **placeholder** | the attentional axis. |")
	return table.concat(lines, "\n")
end

local PRESET_ROW = "| `preset_rate_limit_seconds` | 10 | **derived** | the guideline. |"
local PING_ROW = "| `ping_rate_limit_seconds` | 10 | **derived** | CA-1, stricter reading. |"
local STRUCK_ROW = "| ~~`signal_rate_limit_seconds`~~ | 1.5 | derived | 1.5 < the guideline's 10 s "
	.. "| `preset_rate_limit_seconds` (10) |"
local LIVE_SUPERSEDED_ROW =
	"| `signal_rate_limit_seconds` | 1.5 | **derived** | two purposes at once. |"

local function violationsOf(text: string, name: string): { string }
	return Spec.violations(Spec.rowsNaming(text, name), name, Spec.FLOOR_SECONDS)
end

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

local function guard(name: string)
	-- The floor is settled (brief §0d #19, #23). Pinned here so that lowering it
	-- is not a quiet way to make a lowered rate pass.
	assert(
		Spec.FLOOR_SECONDS == 10,
		`RateLimitSpec.FLOOR_SECONDS is {Spec.FLOOR_SECONDS}; the preset guideline's floor is 10 `
			.. `(brief §0d #19, #23) and is not the test's to choose`
	)
	local text = Spec.read()
	assert(#text > 0, `{Spec.SPEC_PATH} read as an empty string`)
	local violations = violationsOf(text, name)
	assert(
		#violations == 0,
		`AC-4: {Spec.SPEC_PATH} does not fix \`{name}\` at or above the preset guideline's `
			.. `floor of {Spec.FLOOR_SECONDS}:\n{Spec.describe(violations)}`
	)
end

local function valueRow(value: string): string
	return "| `preset_rate_limit_seconds` | " .. value .. " | **derived** | x. |"
end

return {
	--[[ The guards, against the real document. ]]

	["AC-4: the guard checks both live rate constants and the superseded one, by name"] = function()
		-- Pinned so a constant cannot be dropped from the list to stop it being
		-- checked.
		assert(
			#Spec.NAMES == 2 and Spec.NAMES[1] == PRESET and Spec.NAMES[2] == PING,
			`RateLimitSpec.NAMES is {table.concat(Spec.NAMES, ", ")}; expected {PRESET}, {PING}`
		)
		assert(
			Spec.SUPERSEDED == "signal_rate_limit_seconds",
			`RateLimitSpec.SUPERSEDED is {Spec.SUPERSEDED}; expected signal_rate_limit_seconds`
		)
	end,

	["AC-4: tuning.md fixes preset_rate_limit_seconds in exactly one table row, as a bare number, at or above the preset guideline's 10 s"] = function()
		guard(PRESET)
	end,

	["AC-4: tuning.md fixes ping_rate_limit_seconds in exactly one table row, as a bare number, at or above the preset guideline's 10 s"] = function()
		guard(PING)
	end,

	["AC-4: tuning.md has no live table row for the superseded signal_rate_limit_seconds - the struck-through §9 record is not one"] = function()
		local text = Spec.read()
		-- Non-vacuity: this is the right, non-empty document - a live rate row is
		-- in it - so "no superseded row" is a statement about tuning.md, not about
		-- an empty read.
		assert(
			#Spec.rowsNaming(text, PRESET) >= 1,
			`{Spec.SPEC_PATH} read without a {PRESET} row; the superseded check would be vacuous`
		)
		local violations = Spec.supersededViolations(text)
		assert(
			#violations == 0,
			`AC-4: {Spec.SPEC_PATH} carries a superseded rate constant:\n{Spec.describe(violations)}`
		)
	end,

	--[[ Controls: each vacuity step, the floor and the superseded check, driven to fail. ]]

	["AC-4 control: a document with neither rate row is reported as matching nothing for each name, not passed as comparing nothing"] = function()
		local text = fixture({})
		for _, name in Spec.NAMES do
			assert(#Spec.rowsNaming(text, name) == 0, `expected no {name} row in the fixture`)
			local violations = violationsOf(text, name)
			assert(
				#violations == 1,
				`{name}: expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
			)
			contains(violations[1], "no table row has `" .. name .. "` in its first cell", name)
			contains(violations[1], "the extraction matched nothing", name)
		end
	end,

	["AC-4 control: two rows naming ping_rate_limit_seconds are reported by count and line, even when both are at the floor"] = function()
		local text = fixture({ PING_ROW, PING_ROW })
		assert(#Spec.rowsNaming(text, PING) == 2, "expected 2 ping rows in the fixture")
		local violations = violationsOf(text, PING)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		contains(
			violations[1],
			"2 table rows name `ping_rate_limit_seconds` (lines 6, 7)",
			"duplicate rows"
		)
	end,

	["AC-4 control: a value cell of 10 s (with a unit) is reported as not a number, not silently read as 10"] = function()
		local text = fixture({ valueRow("10 s") })
		local violations = violationsOf(text, PRESET)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		contains(
			violations[1],
			'the value cell for `preset_rate_limit_seconds` is "10 s", which is not a number',
			"non-number value"
		)
		contains(violations[1], "§3", "section")
	end,

	["AC-4 control: ping_rate_limit_seconds at 3, its second-pass value, is reported naming the constant, 3 and the floor of 10"] = function()
		local text =
			fixture({ PRESET_ROW, "| `ping_rate_limit_seconds` | 3 | **placeholder** | was. |" })
		local violations = violationsOf(text, PING)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		contains(
			violations[1],
			"`ping_rate_limit_seconds` is 3 in the document, below the floor of 10",
			"below-floor value"
		)
		contains(violations[1], "preset guideline", "the floor's provenance")
		-- The preset row in the same document is at the floor and must not be
		-- reported with it.
		local presetViolations = violationsOf(text, PRESET)
		assert(
			#presetViolations == 0,
			`the preset row at 10 was reported:\n{Spec.describe(presetViolations)}`
		)
	end,

	["AC-4 control: the floor is inclusive - 10 and 11 pass, 9.5 is reported"] = function()
		local atFloor = violationsOf(fixture({ valueRow("10") }), PRESET)
		assert(#atFloor == 0, `10 is the floor and must pass:\n{Spec.describe(atFloor)}`)
		local above = violationsOf(fixture({ valueRow("11") }), PRESET)
		assert(#above == 0, `11 is above the floor and must pass:\n{Spec.describe(above)}`)
		local below = violationsOf(fixture({ valueRow("9.5") }), PRESET)
		assert(#below == 1, `9.5 is below the floor and must be reported, found {#below}`)
		contains(
			below[1],
			"is 9.5 in the document, below the floor of 10",
			"fractional below-floor"
		)
	end,

	["AC-4 control: a row whose first cell is a longer name containing ping_rate_limit_seconds is not a match"] = function()
		local text = fixture({
			"| `ping_rate_limit_seconds_v2` | 3 | **placeholder** | a different constant. |",
			PING_ROW,
		})
		local rows = Spec.rowsNaming(text, PING)
		assert(#rows == 1, `expected 1 row, found {#rows}`)
		assert(rows[1].line == 7, `expected the row at line 7, found line {rows[1].line}`)
		assert(rows[1].section == 3, `expected section 3, found {tostring(rows[1].section)}`)
		assert(tonumber(rows[1].valueCell) == 10, `expected 10, found "{rows[1].valueCell}"`)
		local violations = violationsOf(text, PING)
		assert(#violations == 0, `expected no violation:\n{Spec.describe(violations)}`)
	end,

	["AC-4 control: a live signal_rate_limit_seconds row is reported as superseded, and the struck-through §9 record is not"] = function()
		local struckOnly = fixture({ PRESET_ROW, PING_ROW, STRUCK_ROW })
		local none = Spec.supersededViolations(struckOnly)
		assert(#none == 0, `the struck-through row was reported as live:\n{Spec.describe(none)}`)

		local live = fixture({ PRESET_ROW, PING_ROW, STRUCK_ROW, LIVE_SUPERSEDED_ROW })
		local violations = Spec.supersededViolations(live)
		assert(
			#violations == 1,
			`expected 1 violation, found {#violations}:\n{Spec.describe(violations)}`
		)
		contains(violations[1], ":9 §3", "the live row's line and section")
		contains(
			violations[1],
			"a live table row has `signal_rate_limit_seconds` in its first cell, but it is a superseded constant",
			"superseded row"
		)
	end,
}
