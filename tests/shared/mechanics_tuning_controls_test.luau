--!strict
--[[
	The negative controls for TUNE-001 AC-1 to AC-5.

	Each criterion names its control as a mutation of the module or the document:

		AC-1  a document row `foo_seconds | 5 s` must fail, naming foo_seconds;
		      a RULE_ROWS name given a number must fail, naming it
		AC-2  dial_settings = 5 must fail, naming 4 and 5; an extra key
		      vocabulary_size must fail, naming it; a module missing
		      ping_display_seconds must fail, naming it
		AC-3  a section that yields zero rows must fail rather than compare nothing
		AC-4  procedure_length 9 must fail the per_operation_seconds relation
		AC-5  an unfrozen module, or one frozen only at the root, must fail

	In RED `src/ReplicatedStorage/Shared/MechanicsTuning.luau` does not exist, so no mutation of it
	can be made and `mechanics_tuning_spec_test.luau` runs no assertion. This
	file requires NO production code - not even `Tuning.luau`; AC-4's §1/§5
	operands come from `TuningFakes.correct()`, a test helper - so that the SAME
	check objects the guard uses are observed rejecting documents and modules
	whose defects are known, during RED rather than promised for GREEN.
	ROUND-002's `tuning_controls_test.luau` established the shape.

	Every control asserts BOTH directions where a trap exists: the wrong module
	passes the check that does not catch it, and fails the one that does. Only
	the second half is the control; the first is what proves the fake is
	plausible rather than merely broken.

	NO NUMBER FROM THE DOCUMENT IS TYPED HERE. The "4" of AC-2's control is read
	from the parsed `dial_settings` row; the "45" of AC-4's is read from the
	Tuning-shaped fake. The wrong numbers (5, 9, 16) are the controls' own.
]]

local MechanicsTuningFakes = require("../helpers/MechanicsTuningFakes")
local MechanicsTuningSpec = require("../helpers/MechanicsTuningSpec")
local TuningFakes = require("../helpers/TuningFakes")

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

local function saysNone(message: string, needles: { string }, what: string)
	for _, needle in needles do
		assert(
			string.find(message, needle, 1, true) == nil,
			`{what}: the failure wrongly mentions "{needle}".\n  message: {message}`
		)
	end
end

local function names(findings: { MechanicsTuningSpec.Finding }): { string }
	local out: { string } = {}
	for _, finding in findings do
		table.insert(out, finding.name)
	end
	table.sort(out)
	return out
end

local function realRows(): { MechanicsTuningSpec.Row }
	return MechanicsTuningFakes.spec().rows
end

--[[
	A mini specification for the PARSER controls. Names are deliberately not the
	real ones, except where a control is about a RULE_ROWS name. It exercises:
	a table before any section, §1 (out of scope), a `###` sub-table inside §2,
	an INV_ row, a struck-through row, a reference, booleans, §5 (out of scope).
]]
local FIXTURE = [[
# Tuning constants

| Reader | Reads |
|---|---|
| `tests/helpers/X.luau` | not in any section |

## 1. Session and lobby

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `alpha_seconds` | 10 | taste | section 1 is not this guard's |

## 2. The instance

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `beta_count` | 7 | **placeholder** | a number |
| `beta_ratio` | 0.25 | **placeholder** | a decimal |
| `beta_flag` | false | **derived** | a boolean |
| `beta_alias` | = `beta_count` | **derived** | a reference |
| `spawn_room` | the room of least eccentricity | **placeholder** | a rule row |

### The layout

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `gamma_studs` | 64 | **placeholder** | a sub-table row belongs to §2 |

### Generator invariants

| Invariant | Statement |
|---|---|
| `INV_something` | an invariant row is not a constant |

## 3. The channel

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `delta_count` | 12 | **derived** | a number in §3 |
| `delta_on` | true | **derived** | a boolean in §3 |

## 4. Actuation and instability

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `epsilon_max` | 5 | **placeholder** | a number in §4 |

### What the HUD shows

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `epsilon_shown` | true | **derived** | a sub-table row belongs to §4 |

## 5. Round timing

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `zeta_seconds` | 420 | taste | section 5 is not this guard's |

## 9. Superseded

| Constant (superseded) | Old value |
|---|---|
| ~~`eta_size`~~ | 16 |
]]

local function describeRows(rows: { MechanicsTuningSpec.Row }): string
	local out: { string } = {}
	for _, row in rows do
		local shown = if row.kind == "reference"
			then `\`{row.ref :: string}\``
			elseif row.kind == "rule" then "rule"
			else tostring(row.value)
		table.insert(out, `{row.tableName}.{row.name}:{row.kind}={shown}`)
	end
	table.sort(out)
	return table.concat(out, " ")
end

return {
	--[[
		The baseline. Every control below is this module, or this document, with
		exactly one thing changed, so a control that fires is attributable to it.
	]]
	["baseline: the real tuning.md parses with no problems and a row in every section"] = function()
		local parsed = MechanicsTuningFakes.spec()
		accepts(function()
			MechanicsTuningSpec.assertNoParseProblems(parsed)
		end, "the real document must classify cleanly - every §2-§4 row is one of the four kinds")
		accepts(function()
			MechanicsTuningSpec.assertEverySectionHasRows(parsed)
		end, "the real document must yield rows in §2, §3 and §4")
		local counts = MechanicsTuningSpec.countBySection(parsed)
		for _, section in MechanicsTuningSpec.SECTIONS do
			assert(
				counts[section].number + counts[section].boolean > 0,
				`§{section} yielded no number or boolean row; the module table for it would be empty`
			)
		end
		-- Every RULE_ROWS name is live in the document, so the list is not stale.
		local byName = MechanicsTuningSpec.byName(parsed.rows)
		for _, name in MechanicsTuningSpec.RULE_ROWS do
			assert(
				byName[name] ~= nil and byName[name].kind == "rule",
				`RULE_ROWS names {name}, but tuning.md §2-§4 has no rule row by that name`
			)
		end
	end,

	["baseline: a correct module passes every AC-2 check against the real tuning.md"] = function()
		local correct = MechanicsTuningFakes.correct()
		accepts(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), correct),
				"AC-2 spec -> module"
			)
		end, "a correct module must satisfy AC-2 in the spec -> module direction")
		accepts(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.unspecified(realRows(), correct),
				"AC-2 module -> spec"
			)
		end, "a correct module must satisfy AC-2 in the module -> spec direction")
	end,

	--[[ AC-1 controls: the parser, on fixtures. ]]

	["AC-1 control: a row whose value cell is `5 s` fails, naming foo_seconds"] = function()
		-- Inserted INSIDE §2, after `beta_count`: a row appended at the end of
		-- the fixture would land in §9 and be (correctly) ignored.
		local text = string.gsub(
			FIXTURE,
			"(| `beta_count` | 7 |[^\n]*\n)",
			"%1| `foo_seconds` | 5 s | **placeholder** | a unit in the value cell |\n"
		)
		assert(text ~= FIXTURE, "the fixture no longer carries the beta_count row to insert after")
		local parsed = MechanicsTuningSpec.parse(text)
		assert(
			#parsed.problems == 1,
			`expected exactly one problem, got {#parsed.problems}: `
				.. table.concat(parsed.problems, " / ")
		)
		saysAll(parsed.problems[1], { "foo_seconds", "5 s" }, "the unclassifiable-row report")

		local message = refuses(function()
			MechanicsTuningSpec.assertNoParseProblems(parsed)
		end, "a document with a row that fits no kind must fail AC-1")
		saysAll(message, { "AC-1", "foo_seconds" }, "AC-1's unclassifiable-row control")
	end,

	["AC-1 control: a RULE_ROWS name given a number fails, naming spawn_room"] = function()
		local text = string.gsub(
			FIXTURE,
			"| `spawn_room` | the room of least eccentricity |",
			"| `spawn_room` | 3 |"
		)
		assert(text ~= FIXTURE, "the fixture no longer carries the spawn_room rule row to rewrite")
		local parsed = MechanicsTuningSpec.parse(text)
		assert(
			#parsed.problems == 1,
			`expected exactly one problem, got {#parsed.problems}: `
				.. table.concat(parsed.problems, " / ")
		)
		saysAll(
			parsed.problems[1],
			{ "spawn_room", "RULE_ROWS", "number" },
			"the rule-with-value report"
		)

		local message = refuses(function()
			MechanicsTuningSpec.assertNoParseProblems(parsed)
		end, "a RULE_ROWS name the document gives a number must fail AC-1")
		saysAll(message, { "spawn_room" }, "AC-1's rule-with-value control")

		-- The converse of the converse: a boolean is refused the same way.
		local boolText = string.gsub(
			FIXTURE,
			"| `spawn_room` | the room of least eccentricity |",
			"| `spawn_room` | true |"
		)
		local boolParsed = MechanicsTuningSpec.parse(boolText)
		assert(#boolParsed.problems == 1, "a RULE_ROWS name given a boolean must be one problem")
		saysAll(boolParsed.problems[1], { "spawn_room", "boolean" }, "the rule-with-boolean report")
	end,

	["AC-1 parser: §2-§4 rows are collected with their kinds, sub-tables included; §1, §5, §9, INV_ and struck-through rows are not"] = function()
		local parsed = MechanicsTuningSpec.parse(FIXTURE)
		assert(#parsed.problems == 0, `the fixture did not parse cleanly: {parsed.problems[1]}`)
		local got = describeRows(parsed.rows)
		local want = table.concat({
			"actuation.epsilon_max:number=5",
			"actuation.epsilon_shown:boolean=true",
			"channel.delta_count:number=12",
			"channel.delta_on:boolean=true",
			"instance.beta_alias:reference=`beta_count`",
			"instance.beta_count:number=7",
			"instance.beta_flag:boolean=false",
			"instance.beta_ratio:number=0.25",
			"instance.gamma_studs:number=64",
			"instance.spawn_room:rule=rule",
		}, " ")
		assert(got == want, `the fixture parsed as:\n  {got}\nexpected:\n  {want}`)
	end,

	["AC-1 parser: a value cell is a number only when bare, a reference only when exactly = `name`"] = function()
		local function kindOf(cell: string): string
			local kind = MechanicsTuningSpec.classifyCell(cell)
			return if kind == nil then "none" else kind
		end
		local cases: { { string } } = {
			{ "4", "number" },
			{ "0.25", "number" },
			{ "-1", "number" },
			{ "true", "boolean" },
			{ "false", "boolean" },
			{ "= `other_name`", "reference" },
			{ "=`other_name`", "reference" },
			{ "**4**", "none" },
			{ "4 s", "none" },
			{ "~4", "none" },
			{ "True", "none" },
			{ "= other_name", "none" },
			{ "= `players_min`..`players_max`", "none" },
			{ "`actuator_redundancy` × that class's step count", "none" },
			{ "none", "none" },
			{ "", "none" },
		}
		local wrong: { string } = {}
		for _, case in cases do
			local got = kindOf(case[1])
			if got ~= case[2] then
				table.insert(wrong, `"{case[1]}" classified as {got}, expected {case[2]}`)
			end
		end
		assert(#wrong == 0, "classifyCell:\n  " .. table.concat(wrong, "\n  "))
	end,

	--[[ AC-3 controls: the per-section row floor. ]]

	["AC-3 vacuity control: zero parsed rows compare clean, and the row floor is what fires"] = function()
		local empty: MechanicsTuningSpec.Parsed = { rows = {}, problems = {} }
		local drifted = MechanicsTuningFakes.with("instance", "dial_settings", 5)

		-- The failure mode, demonstrated rather than described: with nothing
		-- parsed, the comparison that catches a 5 catches nothing at all.
		assert(
			#MechanicsTuningSpec.missingOrMismatched(empty.rows, drifted) == 0,
			"a zero-row comparison reported a finding; this control no longer demonstrates "
				.. "the vacuous pass it exists for"
		)

		local message = refuses(function()
			MechanicsTuningSpec.assertEverySectionHasRows(empty)
		end, "a guard that parsed zero rows must fail its own row floor")
		saysAll(
			message,
			{ "AC-3", "parsed 0 rows", "§2 (", "§3 (", "§4 (", "0 rows parsed" },
			"AC-3's row floor"
		)
	end,

	["AC-3 control: a document whose §3 heading no longer matches fails the floor, naming §3 only"] = function()
		local text = string.gsub(FIXTURE, "## 3%. The channel", "## The channel")
		assert(text ~= FIXTURE, "the fixture no longer carries the §3 heading to break")
		local parsed = MechanicsTuningSpec.parse(text)
		assert(
			#parsed.problems == 0,
			`the broken-heading fixture did not parse cleanly: {parsed.problems[1]}`
		)
		-- The §3 rows fall into §2's bucket (a `##` line without a number does
		-- not close the section), so the total is unchanged and only the
		-- per-section floor can see the loss.
		assert(
			#parsed.rows == #MechanicsTuningSpec.parse(FIXTURE).rows,
			"breaking the §3 heading changed the total row count; a count-only floor would see it, "
				.. "and this control exists to show that one does not"
		)

		local message = refuses(function()
			MechanicsTuningSpec.assertEverySectionHasRows(parsed)
		end, "a document whose §3 yields no rows must fail AC-3")
		saysAll(
			message,
			{ "AC-3", "§3 (-> MechanicsTuning.channel): 0 rows parsed" },
			"AC-3's §3 floor"
		)
		saysNone(message, { "§2 (", "§4 (" }, "AC-3's §3 floor")
	end,

	--[[ AC-2 controls: the comparison, on fakes, against the REAL rows. ]]

	["AC-2 control: dial_settings 5 fails the guard, naming the document's value and 5"] = function()
		local row = MechanicsTuningFakes.row("dial_settings")
		assert(
			row.kind == "number",
			`dial_settings is a {row.kind} row; this control expects a number`
		)
		assert(
			row.value ~= 5,
			"the document's dial_settings is 5; this control's wrong value must differ"
		)
		local drifted = MechanicsTuningFakes.with("instance", "dial_settings", 5)

		accepts(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.unspecified(realRows(), drifted),
				"AC-2 module -> spec"
			)
		end, "a wrong VALUE is invisible to the module -> spec direction - that is the trap")

		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), drifted),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a module whose dial_settings is 5 must fail AC-2")
		saysAll(
			message,
			{ "dial_settings", `spec {tostring(row.value)}`, "module 5" },
			"AC-2's value control"
		)
	end,

	["AC-2 control: an extra key vocabulary_size fails and is named"] = function()
		local extra = MechanicsTuningFakes.with("channel", "vocabulary_size", 16)
		accepts(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), extra),
				"AC-2 spec -> module"
			)
		end, "an EXTRA constant is invisible to the spec -> module direction - that is the trap")

		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.unspecified(realRows(), extra),
				"AC-2: the module carries constants the specification does not name"
			)
		end, "a module carrying vocabulary_size must fail AC-2's other direction")
		saysAll(
			message,
			{ "vocabulary_size", "MechanicsTuning.channel", "§3" },
			"AC-2's extra-key control"
		)
	end,

	["AC-2 control: a module missing ping_display_seconds fails and is named"] = function()
		local row = MechanicsTuningFakes.row("ping_display_seconds")
		local missing = MechanicsTuningFakes.with("channel", "ping_display_seconds", nil)
		accepts(
			function()
				MechanicsTuningSpec.assertNoFindings(
					MechanicsTuningSpec.unspecified(realRows(), missing),
					"AC-2 module -> spec"
				)
			end,
			"a module missing a constant has no UNSPECIFIED constant - that is the other direction"
		)

		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), missing),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a module missing ping_display_seconds must fail AC-2")
		saysAll(
			message,
			{ "ping_display_seconds", `spec {tostring(row.value)}`, "absent from the module" },
			"AC-2's missing-key control"
		)
	end,

	["AC-2 control: a reference row that disagrees with its referent fails, naming both"] = function()
		local row = MechanicsTuningFakes.row("ping_range_studs")
		assert(
			row.kind == "reference",
			`ping_range_studs is a {row.kind} row; this control expects a reference`
		)
		local ref = row.ref :: string
		local correct = MechanicsTuningFakes.correct()
		local referentValue = correct.instance[ref]
		assert(
			typeof(referentValue) == "number",
			`the referent {ref} is not a number in the baseline`
		)
		local skewed = MechanicsTuningFakes.with("channel", "ping_range_studs", referentValue + 1)

		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), skewed),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a reference row whose value differs from its referent must fail AC-2")
		saysAll(message, {
			"ping_range_studs",
			`spec = \`{ref}\``,
			`module {referentValue + 1}`,
			`MechanicsTuning.instance.{ref} is {referentValue}`,
		}, "AC-2's reference control")
		saysNone(
			message,
			{ `{ref} (` },
			"AC-2's reference control names the referent, not a defect in it"
		)
	end,

	["AC-2 control: a referent moved alone fails BOTH its own row and every reference to it"] = function()
		local row = MechanicsTuningFakes.row("ping_range_studs")
		local ref = row.ref :: string
		local correct = MechanicsTuningFakes.correct()
		local referentValue = correct.instance[ref]
		-- D-1's shape, on the fake: the referent changes, the reference does not.
		local skewed = MechanicsTuningFakes.with("instance", ref, referentValue + 1)
		local found = names(MechanicsTuningSpec.missingOrMismatched(realRows(), skewed))
		local want = { ref, "ping_range_studs" }
		table.sort(want)
		assert(
			table.concat(found, ",") == table.concat(want, ","),
			`moving {ref} alone produced findings [{table.concat(found, ", ")}], expected `
				.. `[{table.concat(want, ", ")}]`
		)
	end,

	["AC-2 control: a rule row carried by the module as a value fails and is named"] = function()
		local ruled = MechanicsTuningFakes.with("instance", "spawn_room", 1)
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), ruled),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a module carrying spawn_room must fail AC-2 - a rule row is absent from the module")
		saysAll(message, { "spawn_room", "a rule row, not a constant" }, "AC-2's rule-row control")

		local other = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.unspecified(realRows(), ruled),
				"AC-2: the module carries constants the specification does not name"
			)
		end, "a rule row is also unspecified from the module's side")
		saysAll(other, { "spawn_room" }, "AC-2's rule-row control, other direction")
	end,

	["AC-2 control: a boolean row carried as a number fails, naming both types"] = function()
		local row = MechanicsTuningFakes.row("blackout_permanent")
		assert(
			row.kind == "boolean",
			`blackout_permanent is a {row.kind} row; this control expects a boolean`
		)
		local typed = MechanicsTuningFakes.with("actuation", "blackout_permanent", 1)
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), typed),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a boolean row carried as the number 1 must fail AC-2")
		saysAll(
			message,
			{ "blackout_permanent", `spec {tostring(row.value)} (boolean)`, "module 1 (number)" },
			"AC-2's wrong-type control"
		)
	end,

	["AC-2 control: a module without a channel table fails, naming the table"] = function()
		local fake = MechanicsTuningFakes.correct()
		fake.channel = nil
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.missingOrMismatched(realRows(), fake),
				"AC-2: tuning.md §2-§4 and src/ReplicatedStorage/Shared/MechanicsTuning.luau disagree"
			)
		end, "a module with no channel table must fail AC-2")
		saysAll(message, { "MechanicsTuning.channel is nil" }, "AC-2's missing-table control")
	end,

	--[[ AC-4 controls: the relations, on fakes. ]]

	["AC-4 baseline: every relation holds on the document's own values"] = function()
		local findings = MechanicsTuningSpec.relationFindings(
			MechanicsTuningFakes.correct(),
			TuningFakes.correct()
		)
		assert(
			#findings == 0,
			"the document's relations do not hold on the document's values; this is a tuning.md "
				.. "inconsistency for the Game Designer, not a test to edit:\n  "
				.. MechanicsTuningSpec.describe(findings)
		)
		assert(
			MechanicsTuningSpec.RELATION_COUNT == 6,
			`AC-4 lists six relations; the helper carries {MechanicsTuningSpec.RELATION_COUNT}`
		)
	end,

	["AC-4 control: procedure_length 9 fails the per_operation_seconds relation, showing both sides"] = function()
		local tuning = TuningFakes.correct()
		local nine = MechanicsTuningFakes.with("instance", "procedure_length", 9)
		local lhs = tuning.round.per_operation_seconds
		local rhs = (tuning.round.round_seconds - tuning.round.traversal_reserve_seconds) / 9
		assert(
			lhs ~= rhs,
			"with procedure_length 9 the relation still holds; the control has no teeth"
		)

		local findings = MechanicsTuningSpec.relationFindings(nine, tuning)
		local found = names(findings)
		assert(
			table.find(found, "per_operation_seconds") ~= nil,
			`procedure_length 9 did not fail per_operation_seconds; findings: [{table.concat(
				found,
				", "
			)}]`
		)
		-- Relations that do not read procedure_length must be untouched.
		assert(
			table.find(found, "machine_spacing_min_studs") == nil
				and table.find(found, "presets_plus_pings_max") == nil,
			`procedure_length 9 disturbed a relation that does not read it: [{table.concat(
				found,
				", "
			)}]`
		)

		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(findings, "AC-4: a derived relation does not hold")
		end, "a module whose procedure_length is 9 must fail AC-4")
		saysAll(
			message,
			{ "per_operation_seconds", `{lhs} vs {rhs}`, "procedure_length = 9" },
			"AC-4's procedure_length control"
		)
	end,

	["AC-4 control: preset_count raised to the ceiling breaks preset_count + ping_kinds ≤ presets_plus_pings_max"] = function()
		local correct = MechanicsTuningFakes.correct()
		local ceiling = correct.channel.presets_plus_pings_max
		local crowded = MechanicsTuningFakes.with("channel", "preset_count", ceiling)
		local found = names(MechanicsTuningSpec.relationFindings(crowded, TuningFakes.correct()))
		assert(
			table.concat(found, ",") == "presets_plus_pings_max",
			`preset_count at the ceiling produced findings [{table.concat(found, ", ")}], expected `
				.. `exactly presets_plus_pings_max`
		)
	end,

	["AC-4 control: a relation whose operand is missing is a finding, not an arithmetic error"] = function()
		local gutted = MechanicsTuningFakes.with("instance", "procedure_length", nil)
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.relationFindings(gutted, TuningFakes.correct()),
				"AC-4: a derived relation does not hold"
			)
		end, "a module missing procedure_length must fail AC-4 by name")
		saysAll(
			message,
			{ "cannot be computed", "MechanicsTuning.instance.procedure_length is nil" },
			"AC-4's missing-operand control"
		)
	end,

	--[[ AC-5 controls: the freeze check, on fakes. ]]

	["AC-5 control: a module frozen at every level passes, and the same module unfrozen fails everywhere"] = function()
		accepts(function()
			MechanicsTuningSpec.assertNoFindings(
				MechanicsTuningSpec.freezeFindings(MechanicsTuningFakes.frozen()),
				"AC-5"
			)
		end, "a module frozen at the root and in all three tables must satisfy AC-5")

		local open = MechanicsTuningFakes.correct()
		local findings = MechanicsTuningSpec.freezeFindings(open)
		-- Root: three replacements and one addition; each table: every key and one addition.
		local expected = 3 + 1
		for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
			expected += #MechanicsTuningSpec.sortedKeys(open[tableName]) + 1
		end
		assert(
			#findings == expected,
			`an unfrozen module produced {#findings} findings, expected {expected} (one per attempted write)`
		)
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(findings, "AC-5: MechanicsTuning accepted a write")
		end, "an unfrozen module must fail AC-5")
		saysAll(
			message,
			{ "MechanicsTuning.instance = {}", "the write must raise" },
			"AC-5's unfrozen control"
		)
	end,

	["AC-5 control: a module frozen only at the root fails on nested writes and nothing else"] = function()
		local rootOnly = MechanicsTuningFakes.frozenRootOnly()
		local findings = MechanicsTuningSpec.freezeFindings(rootOnly)
		assert(
			#findings > 0,
			"a root-only freeze passed the whole-structure check; the check is vacuous"
		)
		local message = refuses(function()
			MechanicsTuningSpec.assertNoFindings(findings, "AC-5: MechanicsTuning accepted a write")
		end, "a module frozen only at the root must fail AC-5")
		saysAll(message, {
			"MechanicsTuning.instance.",
			"MechanicsTuning.channel.",
			"MechanicsTuning.actuation.",
		}, "AC-5's root-only control")
		saysNone(message, {
			"MechanicsTuning.instance = {}",
			"MechanicsTuning.channel = {}",
			"MechanicsTuning.actuation = {}",
			"__probe_table",
		}, "AC-5's root-only control must not blame the frozen root")
	end,

	["AC-5 control: one unfrozen table among frozen ones is found, and the frozen ones are not blamed"] = function()
		local findings =
			MechanicsTuningSpec.freezeFindings(MechanicsTuningFakes.frozenExcept("channel"))
		assert(#findings > 0, "a module with an unfrozen channel table passed the check")
		for _, finding in findings do
			assert(
				string.find(finding.name, "MechanicsTuning.channel.", 1, true) == 1,
				`a finding blamed something other than the channel table: {finding.message}`
			)
		end
	end,

	["AC-5 control: a __newindex that swallows writes silently fails - the write must RAISE"] = function()
		local fake = MechanicsTuningFakes.correct()
		fake.instance = setmetatable({}, {
			__index = fake.instance,
			__newindex = function() end,
		})
		local findings = MechanicsTuningSpec.freezeFindings(fake)
		local swallowed = 0
		for _, finding in findings do
			if
				string.find(finding.message, "succeeded; the write must raise", 1, true) ~= nil
				and string.find(finding.name, "MechanicsTuning.instance.", 1, true) == 1
			then
				swallowed += 1
			end
		end
		assert(
			swallowed > 0,
			"a silently swallowing __newindex was not reported as a write that succeeded"
		)
	end,
}
