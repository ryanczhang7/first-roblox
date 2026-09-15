--!strict
--[[
	The negative controls for ROUND-002 AC-4 and AC-5.

	AC-4 and AC-5 each name their control as a mutation of the module:

		AC-4  changing `lobby_seconds` from 60 to 61 must make the guard fail and
		      must name `lobby_seconds`
		AC-5  adding `vote_seconds = 30` must make this fail

	In RED `src/shared/Tuning.luau` does not exist, so neither mutation can be
	made and neither file that requires the module runs a single assertion. This
	file requires NO production code, deliberately, so that the SAME check
	objects the guard uses are observed rejecting modules whose defects are known
	- during RED, rather than promised for GREEN. ROUND-001's
	`rng_controls_test.luau` established the shape.

	Every control asserts BOTH directions where a trap exists: the wrong module
	passes the check that does not catch it, and fails the one that does. Only
	the second half is the control; the first is what proves the fake is
	plausible rather than merely broken.

	The two marked "vacuity control" are the ones the story says matter most. A
	guard that parses zero rows compares them all successfully and passes, so one
	of them drives the comparison with an empty row set and asserts it comes back
	CLEAN - which is the failure mode, made visible - and then asserts that the
	row floor is what catches it. The other parses thirteen rows with the wrong
	names, because §2 of the specification has exactly thirteen constant rows and
	a count-only floor would accept them.
]]

local TuningFakes = require("../helpers/TuningFakes")
local TuningSpec = require("../helpers/TuningSpec")

local function accepts(run: () -> (), what: string)
	local ok, err = pcall(run)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(run: () -> (), what: string): string
	local ok, err = pcall(run)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function saysAll(message: string, needles: { string }, what: string)
	for _, needle in needles do
		assert(
			string.find(message, needle, 1, true) ~= nil,
			`{what}: the failure does not mention "{needle}".\n  message: {message}`
		)
	end
end

-- The rows every module control is compared against come from the REAL
-- specification file, parsed once. That is what makes the baseline below a
-- measurement rather than a tautology.
local realRows = TuningSpec.read().rows

--[[
	A mini specification, used where the control is about the PARSER rather than
	about a module. The names are deliberately not the real ones: a fixture that
	reused them could pass by accident.
]]
local FIXTURE = [[
# Tuning constants

| Constant | Value | Label |
|---|---|---|
| `preamble_seconds` | 1 | taste |

## 1. Session and lobby

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `alpha_seconds` | 10 | taste | a table row before any section is not in a section |

## 2. The instance

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `beta_count` | 7 | **derived** | section 2 is out of scope for ROUND-002 |

### Generator invariants

| Invariant | Statement |
|---|---|
| `INV_something` | a subsection heading must not reopen a numbered section |

## 5. Round timing

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `gamma_seconds_min` / `_max` | 30 / 90 | **derived** | two constants on one row |
]]

local function fixtureWithHeadingBroken(): string
	local broken = string.gsub(FIXTURE, "## 1%. Session and lobby", "## Session and lobby")
	return broken
end

local function fixtureWithUnreadableRow(): string
	return FIXTURE .. "\n| `delta_seconds` | soon | **placeholder** | no number in the value |\n"
end

-- Thirteen parsed constants with the wrong names: what a parser aimed at the
-- wrong section of the real document would produce.
local function fixtureWithFillerRows(count: number): string
	local lines = { "## 1. Session and lobby", "", "| Constant | Value |", "|---|---|" }
	for index = 1, count do
		table.insert(lines, `| \`filler_{index}\` | {index} |`)
	end
	return table.concat(lines, "\n")
end

local function namesIn(rows: { TuningSpec.Row }): { string }
	local out: { string } = {}
	for _, row in rows do
		table.insert(out, `{row.tableName}.{row.name}={row.value}`)
	end
	table.sort(out)
	return out
end

return {
	--[[
		The baseline. Every control below is this module with exactly one thing
		changed, so a control that fires is attributable to that one thing.
	]]
	["baseline: a correct module passes every AC-4 and AC-5 check against the real tuning.md"] = function()
		local correct = TuningFakes.correct()
		accepts(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, correct),
				"AC-4 spec -> module"
			)
		end, "a correct module must satisfy AC-4 in the spec -> module direction")
		accepts(function()
			TuningSpec.assertNoFindings(
				TuningSpec.unspecified(realRows, correct),
				"AC-4 module -> spec"
			)
		end, "a correct module must satisfy AC-4 in the module -> spec direction")
		accepts(function()
			TuningSpec.assertNoAbsentConstants(correct)
		end, "a correct module must satisfy AC-5")
		assert(
			TuningSpec.constantCount(correct) == TuningSpec.MIN_CONSTANTS,
			`the baseline exposes {TuningSpec.constantCount(correct)} constants, expected `
				.. `{TuningSpec.MIN_CONSTANTS}`
		)
	end,

	--[[ AC-4 controls. ]]

	["AC-4 control: lobby_seconds 61 fails the guard and the failure names lobby_seconds"] = function()
		local drifted = TuningFakes.with("session", "lobby_seconds", 61)
		accepts(
			function()
				TuningSpec.assertNoAbsentConstants(drifted)
			end,
			"a wrong VALUE must still pass AC-5 - that is what makes AC-4 the guard that catches it"
		)

		local message = refuses(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, drifted),
				"AC-4: tuning.md and src/shared/Tuning.luau disagree"
			)
		end, "a module whose lobby_seconds is 61 must fail AC-4")
		saysAll(message, { "lobby_seconds", "spec 60", "module 61" }, "AC-4's value control")
	end,

	["AC-4 control: a constant absent from the module fails and is named"] = function()
		local missing = TuningFakes.with("session", "season_length_days", nil)
		accepts(
			function()
				TuningSpec.assertNoFindings(
					TuningSpec.unspecified(realRows, missing),
					"AC-4 module -> spec"
				)
			end,
			"a module missing a constant has no UNSPECIFIED constant - that is the other direction"
		)

		local message = refuses(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, missing),
				"AC-4: tuning.md and src/shared/Tuning.luau disagree"
			)
		end, "a module missing season_length_days must fail AC-4")
		saysAll(
			message,
			{ "season_length_days", "absent from the module" },
			"AC-4's missing-constant control"
		)
	end,

	["AC-4 control: a constant the specification does not name fails and is named"] = function()
		local extra = TuningFakes.with("round", "warmup_seconds", 15)
		accepts(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, extra),
				"AC-4 spec -> module"
			)
		end, "an EXTRA constant is invisible to the spec -> module direction - that is the trap")

		local message = refuses(function()
			TuningSpec.assertNoFindings(
				TuningSpec.unspecified(realRows, extra),
				"AC-4: the module carries constants the specification does not name"
			)
		end, "a module carrying warmup_seconds must fail AC-4's other direction")
		saysAll(message, { "warmup_seconds", "Tuning.round" }, "AC-4's extra-constant control")
	end,

	["AC-4 control: a constant that is not a number fails and is named"] = function()
		local stringy = TuningFakes.with("round", "round_seconds", "480")
		local message = refuses(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, stringy),
				"AC-4: tuning.md and src/shared/Tuning.luau disagree"
			)
		end, 'a module whose round_seconds is the string "480" must fail AC-4')
		saysAll(message, { "round_seconds", "spec 480", "string" }, "AC-4's wrong-type control")
	end,

	--[[
		The vacuity controls, and the reason AC-4 has a row floor at all.
	]]
	["AC-4 vacuity control: zero parsed rows compare clean, and the row floor is what fires"] = function()
		local empty: TuningSpec.Parsed = { rows = {}, problems = {} }
		local drifted = TuningFakes.with("session", "lobby_seconds", 61)

		-- The failure mode, demonstrated rather than described: with nothing
		-- parsed, the comparison that catches a 61 catches nothing at all.
		assert(
			#TuningSpec.missingOrMismatched(empty.rows, drifted) == 0,
			"a zero-row comparison reported a finding; this control no longer demonstrates "
				.. "the vacuous pass it exists for"
		)

		local message = refuses(function()
			TuningSpec.assertEnoughRows(empty)
		end, "a guard that parsed zero rows must fail its own row floor")
		saysAll(message, { "parsed 0 constants", "at least 13" }, "AC-4's row floor")
	end,

	["AC-4 vacuity control: thirteen rows with the wrong names pass the count and fail the names"] = function()
		local filler = TuningSpec.parse(fixtureWithFillerRows(TuningSpec.MIN_CONSTANTS))
		assert(
			#filler.rows == TuningSpec.MIN_CONSTANTS,
			`the filler fixture parsed {#filler.rows} rows, expected {TuningSpec.MIN_CONSTANTS}`
		)
		accepts(function()
			TuningSpec.assertEnoughRows(filler)
		end, "thirteen filler rows must satisfy the count - that is why the count is not enough")

		local message = refuses(function()
			TuningSpec.assertExpectedNames(filler)
		end, "thirteen rows naming nothing ROUND-002 names must fail the expected-names check")
		saysAll(
			message,
			{ "lobby_seconds", "round_seconds", "Tuning.session", "Tuning.round" },
			"AC-4's expected-names check"
		)
	end,

	--[[ Parser controls. ]]

	["AC-4 parser: sections 1 and 5 are collected, and nothing else is"] = function()
		local parsed = TuningSpec.parse(FIXTURE)
		assert(#parsed.problems == 0, `the fixture did not parse cleanly: {parsed.problems[1]}`)
		assert(
			table.concat(namesIn(parsed.rows), " ")
				== "round.gamma_seconds_max=90 round.gamma_seconds_min=30 session.alpha_seconds=10",
			`the fixture parsed as: {table.concat(namesIn(parsed.rows), " ")}`
		)
	end,

	["AC-4 parser: a heading that does not match yields no constants from that section"] = function()
		local parsed = TuningSpec.parse(fixtureWithHeadingBroken())
		assert(
			table.concat(namesIn(parsed.rows), " ")
				== "round.gamma_seconds_max=90 round.gamma_seconds_min=30",
			`the broken-heading fixture parsed as: {table.concat(namesIn(parsed.rows), " ")}`
		)
	end,

	["AC-4 parser control: a row whose value cell holds no number is reported, not skipped"] = function()
		local parsed = TuningSpec.parse(fixtureWithUnreadableRow())
		assert(
			#parsed.problems == 1,
			`expected exactly one unread row, got {#parsed.problems}: `
				.. table.concat(parsed.problems, " / ")
		)
		saysAll(parsed.problems[1], { "delta_seconds", "soon" }, "the unread-row report")

		local message = refuses(function()
			TuningSpec.assertNoParseProblems(parsed)
		end, "a specification row the guard could not read must fail the guard")
		saysAll(message, { "delta_seconds" }, "AC-4's unread-row assertion")
	end,

	--[[ AC-5 controls. ]]

	["AC-5 control: vote_seconds = 30 fails and is named"] = function()
		local voting = TuningFakes.with("session", "vote_seconds", 30)
		accepts(function()
			TuningSpec.assertNoFindings(
				TuningSpec.missingOrMismatched(realRows, voting),
				"AC-4 spec -> module"
			)
		end, "vote_seconds does not disturb the spec -> module direction - AC-5 is what catches it")

		local message = refuses(function()
			TuningSpec.assertNoAbsentConstants(voting)
		end, "a module with vote_seconds = 30 must fail AC-5")
		saysAll(message, { "vote_seconds", "there is no vote" }, "AC-5's vote control")
	end,

	["AC-5 control: hidden_faction_ratio fails and is named"] = function()
		local message = refuses(function()
			TuningSpec.assertNoAbsentConstants(
				TuningFakes.with("session", "hidden_faction_ratio", 0.25)
			)
		end, "a module with hidden_faction_ratio must fail AC-5")
		saysAll(message, { "hidden_faction_ratio", "amendment 8" }, "AC-5's hidden-faction control")
	end,

	["AC-5 control: a per-player score, rank, MMR or ladder constant fails and is named"] = function()
		for _, key in { "player_score_weight", "rank_decay_days", "mmr_k_factor", "ladder_tiers" } do
			local message = refuses(function()
				TuningSpec.assertNoAbsentConstants(TuningFakes.with("round", key, 1))
			end, `a module with {key} must fail AC-5`)
			saysAll(message, { key, "amendment 9" }, `AC-5's control for {key}`)
		end
	end,

	["AC-5 control: a forbidden key at the top level of the module is caught too"] = function()
		local fake = TuningFakes.correct()
		fake.vote_deadline_seconds = 20
		local message = refuses(function()
			TuningSpec.assertNoAbsentConstants(fake)
		end, "a forbidden key beside session and round must fail AC-5")
		saysAll(message, { "vote_deadline_seconds", "(Tuning)" }, "AC-5's top-level control")
	end,

	--[[
		The other half of AC-5, and the reason the check counts before it looks:
		"no key matches these rules" is true of a module with no keys.
	]]
	["AC-5 vacuity control: an empty module fails the absence check rather than passing it"] = function()
		local empty = TuningFakes.empty()
		assert(
			#TuningSpec.absenceFindings(empty) == 0,
			"the absence rules found something in an empty module; this control no longer "
				.. "demonstrates the vacuous pass it exists for"
		)

		local message = refuses(function()
			TuningSpec.assertNoAbsentConstants(empty)
		end, "an absence check over an empty module must fail rather than pass vacuously")
		saysAll(
			message,
			{ "exposing 0 constants", "at least 13" },
			"AC-5's non-emptiness assertion"
		)
	end,
}
