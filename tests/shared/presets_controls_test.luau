--!strict
--[[
	The negative controls for CHAN-002 AC-1 .. AC-5 and P-1, P-3 .. P-5, and
	the proof that each check in `tests/helpers/PresetContract.luau` and each
	vacuity step in `tests/helpers/PresetSpec.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/shared/channel/Presets.luau` does not exist, every test in
	`tests/shared/presets_test.luau` stops at `presets()`, and so not one of
	that file's checks has been observed to accept or refuse anything. This
	file needs only `MechanicsTuning` (TUNE-001, merged), `src/net/Remotes.luau`
	as text (NET-002, merged) and `docs/wiki/game/mechanics.md`, so what is
	asserted here is MEASURED in RED rather than claimed for GREEN. The story's
	handoff carries the table.

	THE REFERENCE is the Contract written out (`PresetStubs.reference`), and
	the baseline control is where the parser is observed reading the REAL
	document into exactly those rows. Each other control is the reference
	with EXACTLY ONE thing changed and pins the set of checks that fire
	EXACTLY - a check that fires on a control it should not is as much a
	finding as one that stays quiet.

	THE DEFERRED VERIFICATIONS' SHAPES ARE HERE AS STUBS. D-1 is
	`wordChanged`, D-2 is `phaseDropped`, D-3 is `terminalPunctuation`. What is
	measured here is that the checks WOULD see them; D-1..D-3 THEMSELVES - the
	same mutations of the real module through scripts/mutate.sh - stay with
	GATES, because the module does not exist in RED.

	THE SETTLED NUMBERS are asserted first and printed: ten rows in the
	document, `preset_count` 10, `ping_kinds` 1, `presets_plus_pings_max` 12.
]]

local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local PhaseUnion = require("../helpers/PhaseUnion")
local PresetContract = require("../helpers/PresetContract")
local PresetSpec = require("../helpers/PresetSpec")
local Stubs = require("../helpers/PresetStubs")
local fs = require("../helpers/GatedFs")

local REMOTES = "src/net/Remotes.luau"

local SPEC = "tableMatchesTheSpec"
local COUNTS = "countsAgreeWithTheTuning"
local FACT = "noWordNamesAFact"
local PUNCT = "noWordEndsInTerminalPunctuation"
local PHASES = "phasesAreNonEmptyAndKnown"
local KEYS = "idsAreIndicesAndKeysArePinned"
local BY_ID = "byIdReturnsTheEntryOrNil"
local FROZEN = "everyTableIsFrozen"

local memo: PresetContract.Context? = nil

local function context(): PresetContract.Context
	if memo == nil then
		memo = {
			rows = PresetSpec.rows(PresetSpec.read()),
			phases = PresetContract.phaseSet(PhaseUnion.read(REMOTES, fs.readFile(REMOTES))),
			tuning = MechanicsTuning,
		}
	end
	return memo :: PresetContract.Context
end

-- The live context with one channel value substituted.
local function contextWith(channel: { [string]: any }): PresetContract.Context
	local base = context()
	local sub = table.clone(MechanicsTuning.channel :: any)
	for key, value in channel do
		sub[key] = value
	end
	return { rows = base.rows, phases = base.phases, tuning = { channel = sub } }
end

local function failingNames(P: any, ctx: PresetContract.Context): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in PresetContract.failures(P, ctx) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

local function lacks(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) == nil,
		`{what}: the message must not contain "{needle}", got:\n{haystack}`
	)
end

-- A table fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(
	label: string,
	P: any,
	ctx: PresetContract.Context,
	expected: { string }
): { [string]: string }
	local names, messages = failingNames(P, ctx)
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {label} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{label} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: PresetContract.Check } = {}
	for _, check in PresetContract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac .. ":", 1, true) == 1,
			`{label}: the failure of {name} does not open with "{ac}:":\n{messages[name]}`
		)
	end
	return messages
end

local function defect(name: Stubs.Defect, expected: { string }): { [string]: string }
	return expectFires(name, Stubs.with(name), context(), expected)
end

-- A §4.2 fixture: the heading, the header rows, and `rows` as table lines.
local function document(rows: { string }, trailer: string?): string
	local lines = {
		"## 4. The channel",
		"",
		"| `not_a_preset` | a row above the heading | Round |",
		"",
		PresetSpec.HEADING,
		"",
		"| Preset | Intent | Phases |",
		"|---|---|---|",
	}
	for _, row in rows do
		table.insert(lines, row)
	end
	table.insert(lines, "")
	table.insert(lines, trailer or "### 4.3 Compliance")
	table.insert(lines, "")
	table.insert(lines, "| `after_the_section` | not a preset | Round |")
	return table.concat(lines, "\n")
end

local function rowLines(): { string }
	local out: { string } = {}
	for _, row in Stubs.ROWS do
		table.insert(out, `| \`{row.word}\` | intent | {table.concat(row.phases, ", ")} |`)
	end
	return out
end

return {
	--[[ ================================================================
	     The settled numbers, read out.
	     ================================================================ ]]

	["settled: mechanics.md §4.2 reads as exactly ten rows, PresetSpec.EXPECTED_ROWS is ten, and MechanicsTuning says preset_count 10, ping_kinds 1, presets_plus_pings_max 12"] = function()
		local rows = context().rows
		local channel = MechanicsTuning.channel
		assert(#rows == 10, `the document reads as {#rows} rows, expected 10`)
		assert(PresetSpec.EXPECTED_ROWS == 10, `EXPECTED_ROWS is {PresetSpec.EXPECTED_ROWS}`)
		assert(
			#rows == channel.preset_count,
			`the document has {#rows} rows, preset_count is {channel.preset_count}`
		)
		assert(channel.ping_kinds == 1, `ping_kinds is {channel.ping_kinds}, expected 1`)
		assert(
			channel.presets_plus_pings_max == 12,
			`presets_plus_pings_max is {channel.presets_plus_pings_max}, expected 12`
		)
		print(
			`        [measured] rows = {#rows}, preset_count = {channel.preset_count}, ping_kinds = {channel.ping_kinds}, max = {channel.presets_plus_pings_max}`
		)
	end,

	["P-1: the Phase set is read out of src/net/Remotes.luau, is non-empty, and equals PhaseUnion.KNOWN as a set; a side with no declaration, and a side with a sixth phase, are each refused"] = function()
		local set = context().phases
		local names: { string } = {}
		for name in set do
			table.insert(names, name)
		end
		table.sort(names)
		local known = table.clone(PhaseUnion.KNOWN)
		table.sort(known)
		assert(Deep.equal(known, names), `read {Deep.show(names)}, KNOWN is {Deep.show(known)}`)
		print(`        [measured] Phase set read from Remotes.luau: {Deep.show(names)}`)

		local okNone, errNone =
			pcall(PresetContract.phaseSet, { path = "x.luau", declarations = 0, phases = {} })
		assert(not okNone, "a side with no declaration was accepted")
		contains(
			tostring(errNone),
			"found 0 'export type Phase =' declaration(s)",
			"no declaration"
		)
		contains(tostring(errNone), "matched nothing", "no declaration")

		local six = table.clone(PhaseUnion.KNOWN)
		table.insert(six, "Intermission")
		local okSix, errSix =
			pcall(PresetContract.phaseSet, { path = "x.luau", declarations = 1, phases = six })
		assert(not okSix, "a sixth phase was accepted")
		contains(tostring(errSix), 'names "Intermission", which PhaseUnion.KNOWN does not', "sixth")
	end,

	--[[ ================================================================
	     The reader (P-2) against fixtures that are wrong on purpose.
	     ================================================================ ]]

	["P-2 control: a document without the §4.2 heading yields zero rows, and vacuity fails with 'matched nothing' rather than comparing nothing"] = function()
		local text = string.gsub(document(rowLines()), PresetSpec.HEADING, "### 4.2 The wheel")
		local rows = PresetSpec.rows(text)
		assert(#rows == 0, `read {#rows} rows from a document with no §4.2 heading`)
		local v = PresetSpec.vacuity(rows, PresetSpec.EXPECTED_ROWS)
		assert(#v == 1, `expected one vacuity violation, got {#v}:\n{PresetSpec.describe(v)}`)
		contains(v[1], "the extraction matched nothing", "zero rows")
	end,

	["P-2 control: nine rows fail vacuity naming the count and the words; the header row, the separator row, a row above the heading and a row after the next heading are not read"] = function()
		local lines = rowLines()
		table.remove(lines, 4) -- Help
		local rows = PresetSpec.rows(document(lines))
		assert(#rows == 9, `read {#rows} rows, expected 9`)
		for _, row in rows do
			assert(row.word ~= "not_a_preset" and row.word ~= "after_the_section", row.word)
			assert(row.word ~= "Preset" and row.word ~= "---", row.word)
		end
		local v = PresetSpec.vacuity(rows, PresetSpec.EXPECTED_ROWS)
		assert(#v == 1, `expected one vacuity violation, got {#v}:\n{PresetSpec.describe(v)}`)
		contains(v[1], "9 preset row(s)", "the count")
		contains(v[1], "expected exactly 10", "the expectation")
		contains(v[1], '"Ready", "Wait", "Go", "On my way"', "the words, Help gone")
	end,

	["P-2 control: a row with an empty phases cell and a row with empty backticks each fail vacuity, naming the row"] = function()
		local lines = rowLines()
		lines[2] = "| `Wait` | hold |  |"
		lines[3] = "| `` | act now | Round |"
		local rows = PresetSpec.rows(document(lines))
		assert(#rows == 10, `read {#rows} rows, expected 10`)
		local v = PresetSpec.vacuity(rows, PresetSpec.EXPECTED_ROWS)
		assert(#v == 2, `expected two vacuity violations, got {#v}:\n{PresetSpec.describe(v)}`)
		contains(
			PresetSpec.describe(v),
			'the preset "Wait" has no phases in its third cell',
			"Wait"
		)
		contains(PresetSpec.describe(v), "a preset row has an empty word", "empty word")
	end,

	["P-2 control: the section also ends at a `## 5` heading, so a §5 table is not read as presets when §4.3 is absent"] = function()
		local rows = PresetSpec.rows(document(rowLines(), "## 5. Something else"))
		assert(#rows == 10, `read {#rows} rows, expected 10`)
		assert(rows[10].word == "Well played", `last row is "{rows[10].word}"`)
	end,

	["P-2: the reader keeps a word's case and inner spaces, splits the third cell on commas with trimming, and records the line number"] = function()
		local rows = PresetSpec.rows(document({ "|  `On  my way`  |  x  |  Round ,Lobby,  |" }))
		assert(#rows == 1, `read {#rows} rows`)
		assert(rows[1].word == "On  my way", `word is "{rows[1].word}"`)
		assert(Deep.equal({ "Round", "Lobby" }, rows[1].phases), Deep.show(rows[1].phases))
		assert(rows[1].line == 9, `line is {rows[1].line}, expected 9`)
	end,

	--[[ ================================================================
	     The reference, and the shape of RED.
	     ================================================================ ]]

	["baseline: the reference table - the Contract written out - passes every check against the real mechanics.md §4.2, the real Remotes.luau Phase set and the real MechanicsTuning"] = function()
		local names, messages = failingNames(Stubs.reference, context())
		if #names > 0 then
			local shown: { string } = {}
			for _, name in names do
				table.insert(shown, `{name}: {messages[name]}`)
			end
			error(
				`the reference fails {#names} check(s), so the check, the reader or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#PresetContract.CHECKS} checks`)
	end,

	["baseline: a module without ALL fails every check at need(), naming the missing export - the shape of RED against the real module"] = function()
		local names, messages = failingNames({}, context())
		assert(
			#names == #PresetContract.CHECKS,
			`{#names} of {#PresetContract.CHECKS} checks fired on an empty module`
		)
		for _, name in names do
			contains(messages[name], "Presets.ALL is nil, expected a list of presets", name)
		end
	end,

	--[[ ================================================================
	     AC-1 (settled): the controls the story names, and the neighbours.
	     ================================================================ ]]

	["control (AC-1, required; D-1's shape): one word changed, Go -> 'Go now', fails exactly AC-1, naming both words at row 3"] = function()
		local messages = defect("wordChanged", { SPEC })
		contains(
			messages[SPEC],
			'row 3: the module\'s word is "Go now", mechanics.md §4.2 says "Go"',
			"row 3"
		)
	end,

	["control (AC-1): a preset removed (Help) fails AC-1 naming Help as missing from the module, AC-2 on the count, and P-3 on the shifted keys"] = function()
		local messages = defect("rowRemoved", { SPEC, COUNTS, KEYS })
		contains(
			messages[SPEC],
			"Presets.ALL has 9 preset(s), mechanics.md §4.2 has 10",
			"the count"
		)
		contains(messages[SPEC], 'missing from the module: "Help"', "Help")
		contains(messages[COUNTS], "#Presets.ALL is 9, tuning channel.preset_count is 10", "AC-2")
	end,

	["control (AC-1): a preset added (Okay) fails AC-1 naming Okay as not in the document, AC-2 on the count, and P-3 on the eleventh key"] = function()
		local messages = defect("rowAdded", { SPEC, COUNTS, KEYS })
		contains(messages[SPEC], 'not in the document: "Okay"', "Okay")
		contains(messages[KEYS], "#Presets.ALL is 11, the Contract pins 10 keys", "P-3")
	end,

	["control (AC-1): two presets swapped (Wait, Go) fail exactly AC-1, at rows 2 and 3 naming both - the keys stay in Contract order, so P-3 is quiet and only the document catches a reorder"] = function()
		-- The stub keeps the keys in Contract order, so P-3 (key by POSITION) is
		-- satisfied and only the document catches the reorder. Measured in RED.
		local messages = defect("rowsSwapped", { SPEC })
		contains(
			messages[SPEC],
			'row 2: the module\'s word is "Go", mechanics.md §4.2 says "Wait"',
			"row 2"
		)
		contains(
			messages[SPEC],
			'row 3: the module\'s word is "Wait", mechanics.md §4.2 says "Go"',
			"row 3"
		)
	end,

	["control (AC-1; D-2's shape): Well played with no phases fails AC-1 naming Well played and AC-5 on the empty list"] = function()
		local messages = defect("phaseDropped", { SPEC, PHASES })
		contains(
			messages[SPEC],
			'row 10 "Well played": the module\'s phases are {  }',
			"the module side"
		)
		contains(
			messages[SPEC],
			`mechanics.md §4.2 says {Deep.show({ "Post" })}`,
			"the document side"
		)
		contains(messages[PHASES], 'row 10 "Well played": the phase list is empty', "AC-5")
	end,

	["control (AC-1): a phase changed to another legal one (Wait: Round -> Lobby) fails exactly AC-1 - AC-5 is satisfied, so only the document catches it"] = function()
		local messages = defect("phaseChanged", { SPEC })
		contains(
			messages[SPEC],
			`row 2 "Wait": the module's phases are {Deep.show({ "Lobby" })}`,
			"the module side"
		)
		contains(messages[SPEC], `says {Deep.show({ "Round" })}`, "the document side")
	end,

	["control (AC-1): a parser that matches no rows fails AC-1 with 'matched nothing' and compares nothing - the reference is not reported as wrong"] = function()
		local empty = { rows = {}, phases = context().phases, tuning = MechanicsTuning }
		local messages = expectFires("emptyRows", Stubs.reference, empty, { SPEC })
		contains(messages[SPEC], "the extraction matched nothing", "vacuity")
		contains(messages[SPEC], "(nothing was compared)", "nothing compared")
		lacks(messages[SPEC], "Presets.ALL has", "the comparison must not have run")
	end,

	--[[ ================================================================
	     AC-2 (settled).
	     ================================================================ ]]

	["control (AC-2): a substituted tuning with ping_kinds 3 fails exactly AC-2 on the C1 clause (10 + 3 = 13 > 12), not on the count"] = function()
		local messages =
			expectFires("pingKinds3", Stubs.reference, contextWith({ ping_kinds = 3 }), { COUNTS })
		contains(
			messages[COUNTS],
			"C1: preset_count + ping_kinds = 10 + 3 = 13, above presets_plus_pings_max = 12",
			"C1"
		)
		lacks(messages[COUNTS], "#Presets.ALL is", "the count clause must not fire")
	end,

	["control (AC-2): a substituted tuning with preset_count 11 fails exactly AC-2 on the count clause (10 != 11), and on C1 (11 + 1 = 12 is allowed, so not on C1)"] = function()
		local messages = expectFires(
			"presetCount11",
			Stubs.reference,
			contextWith({ preset_count = 11 }),
			{ COUNTS }
		)
		contains(
			messages[COUNTS],
			"#Presets.ALL is 10, tuning channel.preset_count is 11",
			"the count"
		)
		lacks(messages[COUNTS], "C1:", "11 + 1 = 12 is within the ceiling")
	end,

	--[[ ================================================================
	     AC-3 (invented oracle): the hand-built bad table, and the denylist.
	     ================================================================ ]]

	["control (AC-3, required): the hand-built table Red, Two, First, Left, Yes, Hello fails AC-3 naming each word and its category - and AC-1, AC-2 and P-3, since it is not the wheel"] = function()
		local messages =
			expectFires("factTable", Stubs.factTable, context(), { SPEC, COUNTS, FACT, KEYS })
		contains(messages[FACT], "6 violation(s)", "six")
		contains(messages[FACT], 'row 1 "Red": the token "red" is a colour word', "Red")
		contains(messages[FACT], 'row 2 "Two": the token "two" is a number word', "Two")
		contains(messages[FACT], 'row 3 "First": the token "first" is a ordinal word', "First")
		contains(messages[FACT], 'row 4 "Left": the token "left" is a direction word', "Left")
		contains(messages[FACT], 'row 5 "Yes": the token "yes" is a polarity word', "Yes")
		contains(messages[FACT], 'row 6 "Hello": the token "hello" is a greeting word', "Hello")
	end,

	["control (AC-3): the check is on whole tokens of a multi-word preset - 'Go left now' fails naming 'left' only, and a shape, a digit and a sequence word are each caught"] = function()
		local table_ = Stubs.build({
			{ word = "Go left now", phases = { "Round" } },
			{ word = "Make a Circle", phases = { "Round" } },
			{ word = "Press 2", phases = { "Round" } },
			{ word = "You next", phases = { "Round" } },
		})
		local messages = expectFires("multiWord", table_, context(), { SPEC, COUNTS, FACT, KEYS })
		contains(messages[FACT], "4 violation(s)", "four")
		contains(
			messages[FACT],
			'row 1 "Go left now": the token "left" is a direction word',
			"left"
		)
		lacks(messages[FACT], '"go"', "go is not a fact word")
		contains(messages[FACT], 'the token "circle" is a shape word', "circle")
		contains(messages[FACT], 'the token "2" is a digit word', "2")
		contains(messages[FACT], 'the token "next" is a sequence word', "next")
	end,

	["AC-3: the denylist contains no token of any shipped word read from mechanics.md §4.2 (ready, wait, go, help, on, my, way, follow, me, got, it, thanks, nice, one, well, played) - 'one' deliberately excluded (T12) - while 'two' and every category are present"] = function()
		local offending: { string } = {}
		local tokens: { string } = {}
		for _, row in context().rows do
			for _, token in PresetContract.tokens(row.word) do
				table.insert(tokens, token)
				local category = PresetContract.deniedAs(token)
				if category ~= nil then
					table.insert(offending, `"{token}" ({category}, from "{row.word}")`)
				end
			end
		end
		assert(#tokens == 16, `the ten words split into {#tokens} tokens, expected 16`)
		assert(
			#offending == 0,
			`the denylist contains shipped tokens: {table.concat(offending, ", ")} - the shipped wheel `
				.. "would fail AC-3, and exempting it would make the check fail open"
		)
		assert(
			PresetContract.deniedAs("one") == nil,
			"'one' is in the denylist; mechanics.md §4.2 chose Nice one (T12)"
		)
		assert(PresetContract.deniedAs("two") == "number", "'two' is not a number word")
		for _, category in
			{
				"colour",
				"shape",
				"number",
				"digit",
				"ordinal",
				"sequence",
				"direction",
				"polarity",
				"greeting",
			}
		do
			local words = (PresetContract.DENYLIST :: { [string]: { string } })[category]
			assert(words ~= nil and #words > 0, `the denylist has no {category} words`)
		end
		print(`        [measured] shipped tokens: {Deep.show(tokens)}`)
	end,

	--[[ ================================================================
	     AC-4 (mechanical; D-3's shape).
	     ================================================================ ]]

	["control (AC-4, required; D-3's shape): 'Help!' fails AC-4 naming it and '!', and AC-1 since the word changed"] = function()
		local messages = defect("terminalPunctuation", { SPEC, PUNCT })
		contains(messages[PUNCT], 'row 4 "Help!": ends in "!", terminal punctuation (C6)', "Help!")
	end,

	["control (AC-4): a word ending in '.', one in '?', and one with punctuation inside but not at the end - only the first two are named"] = function()
		local table_ = Stubs.build({
			{ word = "Wait.", phases = { "Round" } },
			{ word = "Ready?", phases = { "Round" } },
			{ word = "Go, now", phases = { "Round" } },
		})
		local messages =
			expectFires("punctuation", table_, context(), { SPEC, COUNTS, PUNCT, KEYS })
		contains(messages[PUNCT], "2 violation(s)", "two")
		contains(messages[PUNCT], 'row 1 "Wait.": ends in "."', "full stop")
		contains(messages[PUNCT], 'row 2 "Ready?": ends in "?"', "question mark")
		lacks(messages[PUNCT], "Go, now", "inner punctuation is not terminal")
	end,

	--[[ ================================================================
	     AC-5 (mechanical).
	     ================================================================ ]]

	["control (AC-5): a phase outside the extracted set (Intermission) fails AC-5 naming it and listing the five known phases, and AC-1 since the document disagrees"] = function()
		local messages = defect("unknownPhase", { SPEC, PHASES })
		contains(
			messages[PHASES],
			'row 2 "Wait": the phase "Intermission" is not one Remotes.Phase declares',
			"Intermission"
		)
		contains(messages[PHASES], "(Assignment, Lobby, Post, Resolution, Round)", "the known five")
	end,

	["control (AC-5): an empty Phase set is refused by the check itself before any membership is judged"] = function()
		local empty = { rows = context().rows, phases = {}, tuning = MechanicsTuning }
		local messages = expectFires("emptyPhaseSet", Stubs.reference, empty, { PHASES })
		contains(
			messages[PHASES],
			"the Phase set read out of src/net/Remotes.luau is empty",
			"empty set"
		)
	end,

	--[[ ================================================================
	     P-3: id, key, fields.
	     ================================================================ ]]

	["control (P-3): ids 0..9 fail exactly P-3, naming the position each id should be"] = function()
		local messages = defect("idOffByOne", { KEYS })
		contains(messages[KEYS], "10 violation(s)", "every row")
		contains(
			messages[KEYS],
			'row 1 "Ready": id is 0, expected 1 (1-based position in ALL)',
			"row 1"
		)
	end,

	["control (P-3): one key changed (go -> go_now) fails exactly P-3, naming the pinned key"] = function()
		local messages = defect("keyChanged", { KEYS })
		contains(messages[KEYS], "1 violation(s)", "one")
		contains(messages[KEYS], 'row 3 "Go": key is "go_now", the Contract pins "go"', "row 3")
	end,

	["control (P-3): an icon field on every preset fails exactly P-3, naming the extra field"] = function()
		local messages = defect("iconField", { KEYS })
		contains(
			messages[KEYS],
			`fields are {Deep.show({ "icon", "id", "key", "phases", "word" })}, expected exactly {Deep.show(
				PresetContract.FIELDS
			)}`,
			"icon"
		)
		contains(messages[KEYS], "no icon field", "the Contract's reason")
	end,

	--[[ ================================================================
	     P-4: byId.
	     ================================================================ ]]

	["control (P-4): a byId that floors and coerces (1.5 -> ALL[1], '1' -> ALL[1]) fails exactly P-4, naming both"] = function()
		local messages = defect("byIdLenient", { BY_ID })
		contains(messages[BY_ID], "2 violation(s)", "two")
		contains(messages[BY_ID], "byId(1.5) returned", "1.5")
		contains(messages[BY_ID], 'byId("1") returned', "a string")
		lacks(messages[BY_ID], "byId(0) returned", "0 is nil under floor too")
	end,

	["control (P-4): a byId that returns a copy fails exactly P-4 on every id, naming the aliasing"] = function()
		local messages = defect("byIdReturnsCopy", { BY_ID })
		contains(messages[BY_ID], "10 violation(s)", "every id")
		contains(messages[BY_ID], 'expected the same table as ALL[1] ("Ready")', "same table")
	end,

	--[[ ================================================================
	     P-5: frozen.
	     ================================================================ ]]

	["control (P-5): an unfrozen ALL, an unfrozen preset and an unfrozen phases list each fail exactly P-5, naming what is not frozen"] = function()
		local all = defect("unfrozenAll", { FROZEN })
		contains(all[FROZEN], "Presets.ALL is not frozen", "ALL")
		local preset = defect("unfrozenPreset", { FROZEN })
		contains(preset[FROZEN], "10 violation(s)", "every preset")
		contains(preset[FROZEN], 'row 1 "Ready": the preset table is not frozen', "preset")
		local phases = defect("unfrozenPhases", { FROZEN })
		contains(phases[FROZEN], 'row 1 "Ready": the phases list is not frozen', "phases")
	end,
}
