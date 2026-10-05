--!strict
--[[
	CHAN-002 AC-1 .. AC-5 and the Contract's P-3 (id, key, shape), P-4 (`byId`)
	and P-5 (frozen), written once as checks over a `Presets` MODULE handed in
	as a parameter - `{ ALL, byId }` - and a `Context` - the §4.2 rows read
	off disk, the Phase set read out of `src/net/Remotes.luau`, and the
	tuning - rather than over `src/shared/channel/Presets.luau` by name.
	`tests/shared/presets_test.luau` applies these to the real module;
	`tests/shared/presets_controls_test.luau` applies them to
	`PresetStubs.luau`'s reference and to tables with EXACTLY ONE defect each,
	so that in RED - where the module does not exist and every check against
	it stops at `need()` - every check here has still been EXECUTED and
	observed to refuse the table it exists to catch.

	THE ORACLE PARTITION (story `## Contract`).
	  SETTLED   AC-1: the words and phases are READ OUT of mechanics.md §4.2
	            (`ctx.rows`, from `PresetSpec`), never restated here.
	            AC-2: the counts are READ OUT of `ctx.tuning.channel`.
	  INVENTED  AC-3: `DENYLIST` below is the oracle this story invents for
	            C2/C8, and its negative control is the hand-built bad table
	            in the controls test.
	  MECHANICAL AC-4 (last character), AC-5 (membership in the extracted
	            Phase set), P-3, P-4, P-5: exact.

	THE DENYLIST DECISION. The check is on WHOLE TOKENS of a preset word,
	lower-cased, and `"one"` is deliberately NOT a number word here:
	mechanics.md §4.2 (T12, operator, 2026-09-30) chose `Nice one`, and "one"
	in it names no quantity. Listing `one` and then exempting the preset would
	make the check fail open for every future preset. `two` .. `twelve` and the
	digits stay, so the control `"Two"` fires. The controls test asserts both
	halves: `one` is not in the list, and no token of a shipped word is.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local PhaseUnion = require("./PhaseUnion")
local PresetSpec = require("./PresetSpec")

local PresetContract = {}

export type Presets = any
export type Context = {
	rows: { PresetSpec.Row }, -- mechanics.md §4.2, read off disk
	phases: { [string]: boolean }, -- the Phase union of src/net/Remotes.luau, read as text
	tuning: any, -- MechanicsTuning, or a substituted tuning
}
export type Check = { name: string, ac: string, run: (Presets, Context) -> () }

-- P-3: the stable ascii ids, in wheel order. Pinned by the Contract, not by
-- mechanics.md, which has no key column.
PresetContract.KEYS = table.freeze({
	"ready",
	"wait",
	"go",
	"help",
	"on_my_way",
	"follow_me",
	"got_it",
	"thanks",
	"nice_one",
	"well_played",
})

-- The exact field set of a Preset (Contract: no icon field).
PresetContract.FIELDS = table.freeze({ "id", "key", "phases", "word" })

--[[
	AC-3's invented oracle: the words that name a fact, by the categories C2
	and C8 list. Whole lower-cased tokens. `one` is absent on purpose (header).
]]
PresetContract.DENYLIST = table.freeze({
	colour = {
		"red",
		"blue",
		"green",
		"yellow",
		"orange",
		"purple",
		"pink",
		"black",
		"white",
		"grey",
		"gray",
		"brown",
		"cyan",
		"magenta",
	},
	shape = {
		"circle",
		"square",
		"triangle",
		"star",
		"cross",
		"diamond",
		"hexagon",
		"heart",
		"arrow",
	},
	-- `one` is NOT here: mechanics.md §4.2 (T12) chose `Nice one`. See header.
	number = {
		"zero",
		"two",
		"three",
		"four",
		"five",
		"six",
		"seven",
		"eight",
		"nine",
		"ten",
		"eleven",
		"twelve",
		"hundred",
		"half",
		"double",
	},
	digit = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" },
	ordinal = {
		"first",
		"second",
		"third",
		"fourth",
		"fifth",
		"sixth",
		"seventh",
		"eighth",
		"ninth",
		"tenth",
		"last",
		"final",
	},
	sequence = { "next", "previous", "before", "after", "then", "again" },
	direction = {
		"left",
		"right",
		"up",
		"down",
		"north",
		"south",
		"east",
		"west",
		"forward",
		"back",
		"backward",
		"above",
		"below",
		"behind",
		"ahead",
	},
	polarity = { "yes", "no", "yeah", "yep", "nope", "nah", "affirmative", "negative" },
	greeting = {
		"hello",
		"hi",
		"hey",
		"hiya",
		"bye",
		"goodbye",
		"welcome",
		"greetings",
		"farewell",
	},
})

-- The denylist flattened: token -> category. Built once.
local denied: { [string]: string } = {}
for category, words in PresetContract.DENYLIST :: { [string]: { string } } do
	for _, word in words do
		denied[word] = category
	end
end

-- Is `token` denied, and under which category? Exposed for the controls.
function PresetContract.deniedAs(token: string): string?
	return denied[string.lower(token)]
end

-- A preset word's lower-cased tokens: maximal runs of letters, digits and
-- apostrophes, so "On my way" is { "on", "my", "way" }.
function PresetContract.tokens(word: string): { string }
	local out: { string } = {}
	for token in string.gmatch(string.lower(word), "[%w']+") do
		table.insert(out, token)
	end
	return out
end

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

--[[
	P-1: the Phase set AC-5 checks membership against, built from one side of
	`PhaseUnion.read` over `src/net/Remotes.luau` - READ, not copied. Raises
	unless exactly one declaration was found, it names at least one phase, and
	the set equals `PhaseUnion.KNOWN` as a set; a membership check against a
	set that was not read would refuse everything or nothing.
]]
function PresetContract.phaseSet(side: PhaseUnion.Side): { [string]: boolean }
	local violations: { string } = {}
	if side.declarations ~= 1 then
		table.insert(
			violations,
			`{side.path}: found {side.declarations} 'export type Phase =' declaration(s); expected exactly one`
		)
	end
	if #side.phases == 0 then
		table.insert(
			violations,
			`{side.path}: the Phase union names no phases - the extraction matched nothing`
		)
	end
	local set: { [string]: boolean } = {}
	for _, name in side.phases do
		set[name] = true
	end
	local known: { [string]: boolean } = {}
	for _, name in PhaseUnion.KNOWN do
		known[name] = true
		if not set[name] then
			table.insert(violations, `{side.path}: the Phase union lacks the known phase "{name}"`)
		end
	end
	for name in set do
		if not known[name] then
			table.insert(
				violations,
				`{side.path}: the Phase union names "{name}", which PhaseUnion.KNOWN does not`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`P-1: the Phase set could not be read out of {side.path}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
	return set
end

local function need(criterion: string, P: Presets)
	if typeof(P) ~= "table" then
		Contract.fail(`{criterion}: Presets is {Deep.show(P)}, expected the module table`)
	end
	if typeof(P.ALL) ~= "table" then
		Contract.fail(`{criterion}: Presets.ALL is {typeof(P.ALL)}, expected a list of presets`)
	end
end

local function needById(criterion: string, P: Presets)
	need(criterion, P)
	if typeof(P.byId) ~= "function" then
		Contract.fail(`{criterion}: Presets.byId is {typeof(P.byId)}, expected a function`)
	end
end

local function finish(criterion: string, violations: { string }, summary: string)
	if #violations > 0 then
		Contract.fail(
			`{criterion}: {#violations} violation(s) for {summary}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- `ALL[i].word` as a string for a message; a non-table entry is shown whole.
local function wordOf(entry: any): string
	if typeof(entry) == "table" and typeof(entry.word) == "string" then
		return entry.word
	end
	return Deep.show(entry)
end

local function wordSet(list: { any }, key: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, item in list do
		if typeof(item) == "table" and typeof(item[key]) == "string" then
			set[item[key]] = true
		end
	end
	return set
end

--[[ ================================================================
     AC-1 (settled): the module against mechanics.md §4.2, row for row.
     ================================================================ ]]

function PresetContract.tableMatchesTheSpec(P: Presets, ctx: Context)
	local criterion = "AC-1"
	need(criterion, P)
	local violations = PresetSpec.vacuity(ctx.rows, PresetSpec.EXPECTED_ROWS)
	finish(criterion, violations, `reading {PresetSpec.SPEC_PATH} §4.2 (nothing was compared)`)

	local ALL: { any } = P.ALL
	local rows = ctx.rows
	if #ALL ~= #rows then
		local inSpec, inModule = wordSet(rows, "word"), wordSet(ALL, "word")
		local missing: { string } = {}
		for _, row in rows do
			if not inModule[row.word] then
				table.insert(missing, `"{row.word}"`)
			end
		end
		local extra: { string } = {}
		for _, entry in ALL do
			if not inSpec[wordOf(entry)] then
				table.insert(extra, `"{wordOf(entry)}"`)
			end
		end
		table.insert(
			violations,
			`Presets.ALL has {#ALL} preset(s), mechanics.md §4.2 has {#rows}`
				.. (if #missing > 0
					then `; missing from the module: {table.concat(missing, ", ")}`
					else "")
				.. (if #extra > 0 then `; not in the document: {table.concat(extra, ", ")}` else "")
		)
	end
	for i = 1, math.min(#ALL, #rows) do
		local row, entry = rows[i], ALL[i]
		if typeof(entry) ~= "table" then
			table.insert(
				violations,
				`row {i}: Presets.ALL[{i}] is {Deep.show(entry)}, expected a preset`
			)
			continue
		end
		if entry.word ~= row.word then
			table.insert(
				violations,
				`row {i}: the module's word is {Deep.show(entry.word)}, mechanics.md §4.2 says "{row.word}"`
			)
		end
		if not Deep.equal(row.phases, entry.phases) then
			table.insert(
				violations,
				`row {i} "{row.word}": the module's phases are {Deep.show(entry.phases)}, `
					.. `mechanics.md §4.2 says {Deep.show(row.phases)}`
			)
		end
	end
	finish(criterion, violations, `Presets.ALL against {PresetSpec.SPEC_PATH} §4.2`)
end

--[[ ================================================================
     AC-2 (settled): the counts, read out of the tuning.
     ================================================================ ]]

function PresetContract.countsAgreeWithTheTuning(P: Presets, ctx: Context)
	local criterion = "AC-2"
	need(criterion, P)
	local channel = ctx.tuning.channel
	local violations: { string } = {}
	if #P.ALL ~= channel.preset_count then
		table.insert(
			violations,
			`#Presets.ALL is {#P.ALL}, tuning channel.preset_count is {channel.preset_count}`
		)
	end
	local sum = channel.preset_count + channel.ping_kinds
	if not (sum <= channel.presets_plus_pings_max) then
		table.insert(
			violations,
			`C1: preset_count + ping_kinds = {channel.preset_count} + {channel.ping_kinds} = {sum}, `
				.. `above presets_plus_pings_max = {channel.presets_plus_pings_max}`
		)
	end
	finish(criterion, violations, "the preset count against MechanicsTuning.channel (C1)")
end

--[[ ================================================================
     AC-3 (invented oracle): no token of a preset word names a fact.
     ================================================================ ]]

function PresetContract.noWordNamesAFact(P: Presets, _ctx: Context)
	local criterion = "AC-3"
	need(criterion, P)
	local violations: { string } = {}
	for i, entry in P.ALL :: { any } do
		if typeof(entry) ~= "table" or typeof(entry.word) ~= "string" then
			table.insert(violations, `row {i}: Presets.ALL[{i}].word is not a string`)
			continue
		end
		for _, token in PresetContract.tokens(entry.word) do
			local category = denied[token]
			if category ~= nil then
				table.insert(
					violations,
					`row {i} "{entry.word}": the token "{token}" is a {category} word (C2/C8)`
				)
			end
		end
	end
	finish(criterion, violations, "the fact denylist over every preset word (C2, C8)")
end

--[[ ================================================================
     AC-4 (mechanical): no terminal punctuation.
     ================================================================ ]]

function PresetContract.noWordEndsInTerminalPunctuation(P: Presets, _ctx: Context)
	local criterion = "AC-4"
	need(criterion, P)
	local violations: { string } = {}
	for i, entry in P.ALL :: { any } do
		if typeof(entry) ~= "table" or typeof(entry.word) ~= "string" then
			table.insert(violations, `row {i}: Presets.ALL[{i}].word is not a string`)
			continue
		end
		local last = string.sub(entry.word, -1)
		if last == "." or last == "!" or last == "?" then
			table.insert(
				violations,
				`row {i} "{entry.word}": ends in "{last}", terminal punctuation (C6)`
			)
		end
	end
	finish(criterion, violations, "the last character of every preset word (C6)")
end

--[[ ================================================================
     AC-5 (mechanical): phases non-empty and in the extracted Phase set.
     ================================================================ ]]

function PresetContract.phasesAreNonEmptyAndKnown(P: Presets, ctx: Context)
	local criterion = "AC-5"
	need(criterion, P)
	local violations: { string } = {}
	local known: { string } = {}
	for name in ctx.phases do
		table.insert(known, name)
	end
	table.sort(known)
	if #known == 0 then
		Contract.fail(
			`{criterion}: the Phase set read out of src/net/Remotes.luau is empty - membership against `
				.. `nothing would refuse everything or nothing`
		)
	end
	for i, entry in P.ALL :: { any } do
		if typeof(entry) ~= "table" or typeof(entry.phases) ~= "table" then
			table.insert(
				violations,
				`row {i} "{wordOf(entry)}": phases is {if typeof(entry) == "table"
					then Deep.show(entry.phases)
					else "absent"}, expected a list`
			)
			continue
		end
		if #entry.phases == 0 then
			table.insert(violations, `row {i} "{entry.word}": the phase list is empty`)
		end
		for _, phase in entry.phases :: { any } do
			if typeof(phase) ~= "string" or not ctx.phases[phase] then
				table.insert(
					violations,
					`row {i} "{entry.word}": the phase {Deep.show(phase)} is not one Remotes.Phase `
						.. `declares ({table.concat(known, ", ")})`
				)
			end
		end
	end
	finish(criterion, violations, "every preset's phase list against Remotes.Phase")
end

--[[ ================================================================
     P-3: id == index, key list exact, field set exact.
     ================================================================ ]]

function PresetContract.idsAreIndicesAndKeysArePinned(P: Presets, _ctx: Context)
	local criterion = "P-3"
	need(criterion, P)
	local violations: { string } = {}
	local ALL: { any } = P.ALL
	if #ALL ~= #PresetContract.KEYS then
		table.insert(
			violations,
			`#Presets.ALL is {#ALL}, the Contract pins {#PresetContract.KEYS} keys`
		)
	end
	for i = 1, math.max(#ALL, #PresetContract.KEYS) do
		local entry = ALL[i]
		local key = PresetContract.KEYS[i]
		if typeof(entry) ~= "table" then
			if entry ~= nil then
				table.insert(
					violations,
					`row {i}: Presets.ALL[{i}] is {Deep.show(entry)}, expected a preset`
				)
			end
			continue
		end
		if entry.id ~= i then
			table.insert(
				violations,
				`row {i} "{wordOf(entry)}": id is {Deep.show(entry.id)}, expected {i} (1-based position in ALL)`
			)
		end
		if entry.key ~= key then
			table.insert(
				violations,
				`row {i} "{wordOf(entry)}": key is {Deep.show(entry.key)}, the Contract pins {Deep.show(
					key
				)}`
			)
		end
		local fields: { string } = {}
		for field in pairs(entry) do
			table.insert(fields, tostring(field))
		end
		table.sort(fields)
		if not Deep.equal(PresetContract.FIELDS, fields) then
			table.insert(
				violations,
				`row {i} "{wordOf(entry)}": fields are {Deep.show(fields)}, expected exactly `
					.. `{Deep.show(PresetContract.FIELDS)} (no icon field; presentation is the client's)`
			)
		end
	end
	finish(criterion, violations, "id, key and field set of every preset")
end

--[[ ================================================================
     P-4: byId.
     ================================================================ ]]

function PresetContract.byIdReturnsTheEntryOrNil(P: Presets, _ctx: Context)
	local criterion = "P-4"
	needById(criterion, P)
	local violations: { string } = {}
	local ALL: { any } = P.ALL
	for i = 1, #ALL do
		local ok, got = pcall(P.byId, i)
		if not ok then
			table.insert(violations, `byId({i}) RAISED: {tostring(got)}`)
		elseif not rawequal(got, ALL[i]) then
			table.insert(
				violations,
				`byId({i}) returned {Deep.show(got)}, expected the same table as ALL[{i}] ("{wordOf(
					ALL[i]
				)}")`
			)
		end
	end
	local absent: { any } = { 0, #ALL + 1, 1.5, -1, "1" }
	for _, id in absent do
		local ok, got = pcall(P.byId, id)
		if not ok then
			table.insert(violations, `byId({Deep.show(id)}) RAISED: {tostring(got)}`)
		elseif got ~= nil then
			table.insert(
				violations,
				`byId({Deep.show(id)}) returned {Deep.show(got)}, expected nil`
			)
		end
	end
	finish(criterion, violations, "byId over 1..#ALL and over 0, #ALL + 1, 1.5, -1 and a string")
end

--[[ ================================================================
     P-5: frozen.
     ================================================================ ]]

function PresetContract.everyTableIsFrozen(P: Presets, _ctx: Context)
	local criterion = "P-5"
	need(criterion, P)
	local violations: { string } = {}
	if not table.isfrozen(P.ALL) then
		table.insert(violations, "Presets.ALL is not frozen")
	end
	for i, entry in P.ALL :: { any } do
		if typeof(entry) ~= "table" then
			continue
		end
		if not table.isfrozen(entry) then
			table.insert(violations, `row {i} "{wordOf(entry)}": the preset table is not frozen`)
		end
		if typeof(entry.phases) == "table" and not table.isfrozen(entry.phases) then
			table.insert(violations, `row {i} "{wordOf(entry)}": the phases list is not frozen`)
		end
	end
	finish(criterion, violations, "ALL, each preset and each phases list (table.isfrozen)")
end

PresetContract.CHECKS = {
	{ name = "tableMatchesTheSpec", ac = "AC-1", run = PresetContract.tableMatchesTheSpec },
	{
		name = "countsAgreeWithTheTuning",
		ac = "AC-2",
		run = PresetContract.countsAgreeWithTheTuning,
	},
	{ name = "noWordNamesAFact", ac = "AC-3", run = PresetContract.noWordNamesAFact },
	{
		name = "noWordEndsInTerminalPunctuation",
		ac = "AC-4",
		run = PresetContract.noWordEndsInTerminalPunctuation,
	},
	{
		name = "phasesAreNonEmptyAndKnown",
		ac = "AC-5",
		run = PresetContract.phasesAreNonEmptyAndKnown,
	},
	{
		name = "idsAreIndicesAndKeysArePinned",
		ac = "P-3",
		run = PresetContract.idsAreIndicesAndKeysArePinned,
	},
	{
		name = "byIdReturnsTheEntryOrNil",
		ac = "P-4",
		run = PresetContract.byIdReturnsTheEntryOrNil,
	},
	{ name = "everyTableIsFrozen", ac = "P-5", run = PresetContract.everyTableIsFrozen },
} :: { Check }

-- Every check against `P`; the names and messages of those that raised.
function PresetContract.failures(P: Presets, ctx: Context): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PresetContract.CHECKS do
		local ok, err = pcall(check.run, P, ctx)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PresetContract
