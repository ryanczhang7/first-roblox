--!strict
--[[
	The negative controls for THEME-001 AC-1 .. AC-7 and C-1, C-3, C-4, C-5,
	and the proof that each check in `tests/helpers/ThemeContract.luau` and
	each vacuity step in `tests/helpers/TokenSpec.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/client/Theme.luau`, `models/ScreenScale.luau` and
	`models/ColourMath.luau` do not exist, every test in `theme_test.luau`
	stops at the require, and so not one of that file's checks has been
	observed to accept or refuse anything. This file needs only
	`MechanicsTuning`, `Tuning` and `Presets` (merged) and
	`docs/wiki/design/tokens.md`, so what is asserted here is MEASURED in RED
	rather than claimed for GREEN. The story's handoff carries the table.

	THE ARITHMETIC IS THE TEST-SIDE REFERENCE (`ColourRef`), so every number
	below - the composite, each contrast, each chroma, each ΔE - is a
	claim about C-6 and C-7 until `colour_math_test.luau` holds the shipped
	`ColourMath` to the same values. The `[measured]` lines are what the
	handoff quotes.

	THE REFERENCE is a Theme derived from the document (`ThemeStubs.theme`).
	Each other control is the reference with EXACTLY ONE thing changed and
	pins the set of checks that fire EXACTLY - a check that fires on a control
	it should not is as much a finding as one that stays quiet.

	D-1's SHAPE IS HERE AS A STUB (`contrastConstant21`): the same mutation of
	the real module through scripts/mutate.sh stays with GATES, because the
	module does not exist in RED.
]]

local ColourRef = require("../helpers/ColourRef")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Presets = require("../../src/ReplicatedStorage/Shared/channel/Presets")
local Stubs = require("../helpers/ThemeStubs")
local ThemeContract = require("../helpers/ThemeContract")
local TokenSpec = require("../helpers/TokenSpec")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")

local COLOURS = "coloursMatchTheSpec"
local PAIRINGS = "pairingsMeetTheFloor"
local TARGETS = "targetsAndTypeClearTheFloor"
local SCALE = "screenScaleMatchesLayout"
local ACHROMATIC = "systemColoursAreAchromatic"
local DISJOINT = "iconSetsAreDisjoint"
local TAG_COUNT = "tagAlphabetIsLargeEnough"
local PRESET_ICONS = "presetIconsMatchPresets"
local DETENTS = "detentsAreLaidOut"
local HUES = "playerHuesAreSeparable"
local VISUALS = "everyCueHasAVisual"
local SIZES = "sizesMatchTheSpec"
local TYPE = "typeMatchesTheSpec"
local ICON_KEYS = "iconKeysMatchTheSpec"
local AUDIO = "audioMatchesTheSpec"

local memo: ThemeContract.Context? = nil

local function context(): ThemeContract.Context
	if memo == nil then
		memo = {
			spec = TokenSpec.parse(TokenSpec.read()),
			mechanics = MechanicsTuning,
			session = Tuning.session,
			presets = Presets.ALL,
		}
	end
	return memo :: ThemeContract.Context
end

local function failingNames(
	impl: ThemeContract.Impl,
	ctx: ThemeContract.Context
): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in ThemeContract.failures(impl, ctx) do
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

-- An implementation fires EXACTLY the checks named, each with a message
-- opening with the criterion it belongs to. The measured set is printed for
-- the handoff.
local function expectFires(
	label: string,
	impl: ThemeContract.Impl,
	ctx: ThemeContract.Context,
	expected: { string }
): { [string]: string }
	local names, messages = failingNames(impl, ctx)
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
	local byName: { [string]: ThemeContract.Check } = {}
	for _, check in ThemeContract.CHECKS do
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

-- What the REFERENCE itself fires, memoised. Every single-defect control is
-- asserted RELATIVE to it: the defect must add exactly `expected`. The
-- baseline case below is where "the reference fires nothing" is asserted, so
-- it is the one case that moves if the criterion or the document changes
-- (as AC-4 did in this story's RED: HSV saturation -> chroma, `## Amendments`).
local baselineNames: { string }? = nil

local function baseline(): { string }
	if baselineNames == nil then
		local names = failingNames(Stubs.reference(context()), context())
		baselineNames = names
	end
	return baselineNames :: { string }
end

local function plusBaseline(expected: { string }): { string }
	local out = table.clone(baseline())
	for _, name in expected do
		if not table.find(out, name) then
			table.insert(out, name)
		end
	end
	return out
end

-- The tokens.md line a row was read from, so a control can name it without
-- hard-coding a number that moves whenever the document is edited above it.
local function lineOf(table_: string, key: string): number
	local spec = context().spec
	local rows: { any } = (spec :: any)[table_]
	for _, row in rows do
		if row.token == key or row.cue == key or row.word == key then
			return row.line
		end
	end
	error(`no {table_} row for {key}`)
end

local function defect(name: Stubs.Defect, expected: { string }): { [string]: string }
	return expectFires(name, Stubs.with(name, context()), context(), plusBaseline(expected))
end

local function fmt(n: number): string
	return string.format("%.2f", n)
end

-- A tokens.md fixture: a heading, a header row, a separator, `rows`.
local function section(heading: string, header: string, rows: { string }): string
	local lines = { heading, "", header, "|---|---|---|---|" }
	for _, row in rows do
		table.insert(lines, row)
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

return {
	--[[ ================================================================
	     The settled numbers, read out.
	     ================================================================ ]]

	["settled: tokens.md reads as 21 colours (14 system, players_max = 6 hues), 10 pairings, 6 tags, 6 patterns, 16 glyphs, #Presets.ALL = 10 preset icons, 5 type, 10 sizes, 14 cues; tag_alphabet_size is 4"] = function()
		local ctx = context()
		local spec = ctx.spec
		local v = TokenSpec.vacuity(spec, ctx.session.players_max, #ctx.presets)
		assert(#v == 0, `the real document fails vacuity:\n{TokenSpec.describe(v)}`)
		assert(ctx.session.players_max == 6, `players_max is {ctx.session.players_max}`)
		assert(#ctx.presets == 10, `#Presets.ALL is {#ctx.presets}`)
		assert(
			ctx.mechanics.instance.tag_alphabet_size == 4,
			`tag_alphabet_size is {ctx.mechanics.instance.tag_alphabet_size}`
		)
		assert(
			#spec.tags == 6 and #spec.tags >= ctx.mechanics.instance.tag_alphabet_size,
			`{#spec.tags} tags, tag_alphabet_size {ctx.mechanics.instance.tag_alphabet_size}`
		)
		print(
			`        [measured] colours = {#spec.colours}, system = {#TokenSpec.systemColours(spec)}, hues = {#TokenSpec.playerHues(
				spec
			)}, pairings = {#spec.pairings}, tags = {#spec.tags}, patterns = {#spec.patterns}, glyphs = {#spec.glyphs}, presetIcons = {#spec.presetIcons}, type = {#spec.type}, sizes = {#spec.sizes}, audio = {#spec.audio}`
		)
	end,

	--[[ ================================================================
	     The reader against fixtures that are wrong on purpose.
	     ================================================================ ]]

	["control (AC-1, required): a document with no backticked color.* row yields zero colours, and vacuity fails with 'matched nothing' rather than comparing nothing"] = function()
		local text = section("### 1.1 System roles", "| Token | Value | Use |", {
			"| color.surface.scrim | `#0E1116` | not backticked |",
			"| `tag.circle` | ● | not a colour |",
		})
		local spec = TokenSpec.parse(text)
		assert(#spec.colours == 0, `read {#spec.colours} colour(s)`)
		local v = TokenSpec.vacuity(spec, 6, 10)
		assert(#v == 1, `expected one vacuity violation, got {#v}:\n{TokenSpec.describe(v)}`)
		contains(v[1], "the extraction matched nothing", "zero rows")
	end,

	["control: the real document with one colour row, one tag and one cue removed fails vacuity naming each count - and with a token row doubled, names the duplicate"] = function()
		local real = TokenSpec.read()
		local function without(text: string, needle: string): string
			local out, n = string.gsub(text, "\n|[^\n]*`" .. needle .. "`[^\n]*", "", 1)
			assert(n == 1, `the fixture has no row for {needle}`)
			return out
		end
		local dropped = without(
			without(without(real, "tag%.bolt"), "sfx%.ping%.helper"),
			"color%.world%.pattern"
		)
		local v = TokenSpec.vacuity(TokenSpec.parse(dropped), 6, 10)
		local described = TokenSpec.describe(v)
		contains(described, "read 20 colour row(s), expected 21", "colours")
		contains(described, "read 13 §1.1 system colour row(s), expected 14", "system")
		contains(described, "read 5 §2.1 tag row(s), expected 6", "tags")
		contains(described, "read 13 §8 audio cue row(s), expected 14", "audio")
		assert(#v == 4, `expected four violations, got {#v}:\n{described}`)

		local doubled, n = string.gsub(real, "\n(|[^\n]*`color%.signal%.off`[^\n]*)", "\n%1\n%1", 1)
		assert(n == 1, "the fixture has no row for color.signal.off")
		v = TokenSpec.vacuity(TokenSpec.parse(doubled), 6, 10)
		described = TokenSpec.describe(v)
		contains(described, "read 22 colour row(s), expected 21", "colours")
		contains(
			described,
			`color.signal.off is named twice (first at line {lineOf("colours", "color.signal.off")})`,
			"duplicate"
		)
		assert(
			#v == 3,
			`expected three violations (colours, system, duplicate), got {#v}:\n{described}`
		)
	end,

	["control: a §1.4 row printing a hex that disagrees with the token's own row is reported, and a §1.4 token no colour row defines is reported"] = function()
		local real = TokenSpec.read()
		local text =
			string.gsub(real, "| `text%.muted` `#B8C0CC` |", "| `text.muted` `#B8C0CD` |", 1)
		text =
			string.gsub(text, "| `stroke%.control` `#8A93A0` |", "| `stroke.ghost` `#8A93A0` |", 1)
		local v = TokenSpec.vacuity(TokenSpec.parse(text), 6, 10)
		local described = TokenSpec.describe(v)
		contains(
			described,
			"§1.4 prints #B8C0CD beside color.text.muted, whose row",
			"disagreeing hex"
		)
		contains(
			described,
			"§1.4 names color.stroke.ghost, which no colour row defines",
			"unknown token"
		)
	end,

	["reader: the transparency is read from `BackgroundTransparency` **0.12**, from 'transparency 0.12' and from 'transparency 0', and is nil where a row states none"] = function()
		local spec = TokenSpec.parse(section("### 1.1 System roles", "| Token | Value | Use |", {
			"| `color.a` | `#000000`, `BackgroundTransparency` **0.12** | |",
			"| `color.b` | `#000001`, transparency 0.25 | |",
			"| `color.c` | `#000002`, transparency 0 | |",
			"| `color.d` | `#000003` emissive | |",
		}))
		assert(#spec.colours == 4, `read {#spec.colours}`)
		assert(spec.colours[1].transparency == 0.12, Deep.show(spec.colours[1]))
		assert(spec.colours[2].transparency == 0.25, Deep.show(spec.colours[2]))
		assert(spec.colours[3].transparency == 0, Deep.show(spec.colours[3]))
		assert(spec.colours[4].transparency == nil, Deep.show(spec.colours[4]))
		assert(spec.colours[1].section == "1.1", spec.colours[1].section)
	end,

	["reader: a §1.4 'player hues' row expands to every color.player.<n> row, a hex-only first cell resolves by hex, and a repeated (token, floor) is read once"] = function()
		local text = section("### 1.2 Player palette", "| Token | Seat | Value | Why |", {
			"| `color.player.1` | 1 | `#00B386` green | |",
			"| `color.player.2` | 2 | `#F0E442` yellow | |",
			"| `color.player.none` | spectator | `#8A93A0` | |",
		}) .. section(
			"### 1.4 Contrast floor",
			"| Foreground | On scrim | On worst | Floor | Use |",
			{
				"| `text.primary` `#FFFFFF` | 18.9 | **13.6** | 4.5 | any text |",
				"| player hues (worst: yellow) | 5.75 | **4.15** | 3.0 | swatches |",
				"| green `#00B386` | 7.35 | 5.30 | 3.0 | |",
			}
		)
		local spec = TokenSpec.parse(text)
		local got: { string } = {}
		for _, p in spec.pairings do
			table.insert(got, `{p.token}@{p.floor}`)
		end
		assert(
			Deep.equal({ "color.text.primary@4.5", "color.player.1@3", "color.player.2@3" }, got),
			Deep.show(got)
		)
		assert(#TokenSpec.playerHues(spec) == 2, "player.none was read as a hue")
	end,

	["reader: §5 reads '56 × 56', '32', '12 (idle), 20 (target)' and '28 × 14, gap 4' as C-1 says, and skips the world.* table under the same heading"] = function()
		local spec = TokenSpec.parse(section("## 5. Sizes", "| Token | Value | Notes |", {
			"| `size.a` | 56 × 56 | |",
			"| `size.b` | 32 | |",
			"| `size.c` | 12 (idle), 20 (target) | |",
			"| `size.d` | 28 × 14, gap 4 | |",
			"| `world.e` | 1.6 studs | |",
		}))
		local got: { string } = {}
		for _, s in spec.sizes do
			table.insert(got, `{s.token}={s.x}x{s.y}`)
		end
		assert(
			Deep.equal({ "size.a=56x56", "size.b=32x32", "size.c=12x12", "size.d=28x14" }, got),
			Deep.show(got)
		)
	end,

	["reader: a §8 row naming two cues splits into two, each taking its half of a two-part visual and the whole of a one-part visual (C-5); §3 takes the base size before the slash"] = function()
		local spec =
			TokenSpec.parse(section("## 8. Audio cue names", "| Cue | Heard by | Visual |", {
				"| `sfx.a` | x | one thing |",
				"| `sfx.b` / `sfx.c` | x | b state / c state |",
				"| `sfx.d` / `sfx.e` | x | the banner |",
			}) .. section(
				"## 3. Type",
				"| Token | Font | Base size / line height | Weight | Use |",
				{
					"| `type.t` | Fredoka One | 40 / 1.1 | regular | |",
				}
			))
		local got: { string } = {}
		for _, a in spec.audio do
			table.insert(got, `{a.cue}={a.visual}`)
		end
		assert(
			Deep.equal({
				"sfx.a=one thing",
				"sfx.b=b state",
				"sfx.c=c state",
				"sfx.d=the banner",
				"sfx.e=the banner",
			}, got),
			Deep.show(got)
		)
		assert(#spec.type == 1 and spec.type[1].size == 40, Deep.show(spec.type))
	end,

	--[[ ================================================================
	     The reference, and the shape of RED.
	     ================================================================ ]]

	["baseline: the reference derived from the real tokens.md passes every check against the real tokens.md, the real tunings and the real Presets - including AC-4 as amended to chroma (worst §1.1 token signal.lens at 0.133)"] = function()
		local names, messages = failingNames(Stubs.reference(context()), context())
		if #names > 0 then
			local shown: { string } = {}
			for _, name in names do
				table.insert(shown, `{name}: {messages[name]}`)
			end
			error(
				`the reference fails {#names} check(s), so the check, the reader, the document or the criterion is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#ThemeContract.CHECKS} checks`)
	end,

	["baseline: an empty implementation fails every check at need(), naming the missing member - the shape of RED against the real modules"] = function()
		local names, messages =
			failingNames({ Theme = {}, ColourMath = {}, ScreenScale = {} }, context())
		assert(
			#names == #ThemeContract.CHECKS,
			`{#names} of {#ThemeContract.CHECKS} checks fired on an empty implementation`
		)
		for _, name in names do
			contains(messages[name], "expected a", name)
		end
	end,

	["measured: the worst composite, every §1.4 contrast, every §1.1 chroma and the PT-T7 minima under the test-side reference arithmetic (C-6, C-7), for the handoff table"] = function()
		local ctx = context()
		local impl = Stubs.reference(ctx)
		local CM = ColourRef
		local composite, t = ThemeContract.worstComposite(impl)
		print(
			`        [measured] composite of scrim at {t} over {ThemeContract.WORST_BACKGROUND}: {CM.toHex(
				composite
			)}`
		)
		assert(
			CM.toHex(composite) == "#2B2E32",
			`composite is {CM.toHex(composite)}, C-6 says #2B2E32`
		)
		local worstText, worstThree = math.huge, math.huge
		for _, p in ctx.spec.pairings do
			local ratio = CM.contrast(CM.fromHex(impl.Theme.color[p.token].hex), composite)
			print(
				`        [measured] {p.token} {impl.Theme.color[p.token].hex}: contrast {fmt(ratio)}, floor {p.floor}`
			)
			if p.floor == 4.5 then
				worstText = math.min(worstText, ratio)
			else
				worstThree = math.min(worstThree, ratio)
			end
		end
		assert(fmt(worstText) == "7.47", `worst text contrast {fmt(worstText)}, C-6 says 7.47`)
		assert(
			fmt(worstThree) == "4.17",
			`worst floor-3.0 contrast {fmt(worstThree)}, C-6 says 4.17`
		)
		local control = CM.contrast(CM.fromHex("#6A727E"), composite)
		print(`        [measured] AC-2 control #6A727E: contrast {fmt(control)}`)
		assert(fmt(control) == "2.82", `the AC-2 control measures {fmt(control)}, C-6 says 2.82`)

		for _, row in TokenSpec.systemColours(ctx.spec) do
			print(
				`        [measured] {row.token} {row.hex}: chroma {string.format(
					"%.3f",
					CM.chroma(CM.fromHex(row.hex))
				)}`
			)
		end
		local hues: { string } = {}
		for _, row in TokenSpec.playerHues(ctx.spec) do
			table.insert(hues, row.hex)
		end
		local sep = ThemeContract.separation(CM, hues)
		print(
			`        [measured] PT-T7 seats 1-6: normal {fmt(sep.normal)}, protan {fmt(sep.protan)}, deutan {fmt(
				sep.deutan
			)}, tritan {fmt(sep.tritan)}; seats 1-4 min {fmt(
				math.min(sep.normal14, sep.protan14, sep.deutan14, sep.tritan14)
			)}; vs references {fmt(sep.vsReference)}`
		)
		-- tokens.md §1.2's published minima, to one decimal (C-7's worked example).
		assert(fmt(sep.normal) == "34.93" and fmt(sep.protan) == "20.71", "seats 1-6 normal/protan")
		assert(fmt(sep.deutan) == "13.46" and fmt(sep.tritan) == "11.18", "seats 1-6 deutan/tritan")
		assert(
			fmt(math.min(sep.normal14, sep.protan14, sep.deutan14, sep.tritan14)) == "28.64",
			"seats 1-4"
		)
		assert(fmt(sep.vsReference) == "16.82", "vs references")
	end,

	--[[ ================================================================
	     AC-1 (settled).
	     ================================================================ ]]

	["control (AC-1, required): color.signal.lens changed to #DDEBFE fails exactly AC-1, naming the token and both values"] = function()
		local messages = defect("lensChanged", { COLOURS })
		contains(messages[COLOURS], "color.signal.lens: Theme says #DDEBFE, tokens.md line", "lens")
		contains(messages[COLOURS], "says #DDEBFF", "the document's value")
		contains(messages[COLOURS], "1 violation(s)", "one")
	end,

	["control (AC-1, required): an extra color.player.7 fails exactly AC-1, naming it as named by no row"] = function()
		local messages = defect("playerSevenAdded", { COLOURS })
		contains(
			messages[COLOURS],
			"color.player.7: in Theme.color, but no tokens.md row names it",
			"player.7"
		)
		contains(messages[COLOURS], "1 violation(s)", "one")
	end,

	["control (AC-1): a §1.1 colour missing from Theme (world.pattern) fails AC-1 naming it and its line, and AC-4, which cannot measure a token that is not there"] = function()
		local messages = defect("colourMissing", { COLOURS, ACHROMATIC })
		contains(
			messages[COLOURS],
			`color.world.pattern (tokens.md line {lineOf("colours", "color.world.pattern")}): missing from Theme.color`,
			"missing"
		)
		contains(
			messages[ACHROMATIC],
			"color.world.pattern: Theme.color has no entry with a hex string for it",
			"AC-4 refuses rather than skips"
		)
	end,

	["control (AC-1 + AC-2): the scrim's transparency dropped fails AC-1 naming the stated 0.12, and AC-2 refuses to composite without one"] = function()
		local messages = defect("transparencyDropped", { COLOURS, PAIRINGS })
		contains(
			messages[COLOURS],
			`color.surface.scrim: transparency is nil, tokens.md line {lineOf(
				"colours",
				"color.surface.scrim"
			)} states 0.12`,
			"AC-1"
		)
		contains(
			messages[PAIRINGS],
			"color.surface.scrim has transparency nil, expected a number",
			"AC-2"
		)
	end,

	["control (AC-1): a parser that matches no rows fails every spec-driven check with 'matched nothing' and compares nothing"] = function()
		local ctx = context()
		local empty = {
			spec = TokenSpec.parse(""),
			mechanics = ctx.mechanics,
			session = ctx.session,
			presets = ctx.presets,
		}
		local messages = expectFires("emptyRows", Stubs.reference(ctx), empty, {
			COLOURS,
			PAIRINGS,
			TARGETS,
			ACHROMATIC,
			PRESET_ICONS,
			HUES,
			SIZES,
			TYPE,
			ICON_KEYS,
			AUDIO,
		})
		contains(messages[COLOURS], "the extraction matched nothing", "vacuity")
		contains(messages[COLOURS], "(nothing was compared)", "nothing compared")
		lacks(messages[COLOURS], "Theme says", "the comparison must not have run")
	end,

	--[[ ================================================================
	     AC-2 (PT-A1, PT-A4).
	     ================================================================ ]]

	["control (AC-2, required; D-1's subject): color.text.muted darkened to #6A727E fails AC-2 at contrast 2.82 against floor 4.5, and AC-1 since the value changed"] = function()
		local messages = defect("mutedDarkened", { COLOURS, PAIRINGS })
		contains(
			messages[PAIRINGS],
			"color.text.muted #6A727E over the worst composite (scrim at 0.12 over #FFFFFF): contrast 2.82, floor 4.5",
			"2.82"
		)
		contains(messages[PAIRINGS], "1 violation(s)", "only muted")
	end,

	["control (AC-2): the scrim raised to transparency 0.2 fails AC-2 on PT-A4's ceiling (every pairing still clears its floor), and AC-1"] = function()
		local messages = defect("transparencyRaised", { COLOURS, PAIRINGS })
		contains(
			messages[PAIRINGS],
			"PT-A4: color.surface.scrim transparency is 0.2, above the ceiling 0.12",
			"ceiling"
		)
		contains(messages[PAIRINGS], "1 violation(s)", "only the ceiling")
	end,

	["control (D-1's shape): with contrast returning the constant 21, the muted-darkened control no longer fires AC-2 - so AC-2 depends on ColourMath.contrast, which is what GATES must show against the shipped module"] = function()
		local ctx = context()
		local impl = Stubs.with("mutedDarkened", ctx)
		impl.ColourMath = Stubs.with("contrastConstant21", ctx).ColourMath
		local messages =
			expectFires("mutedDarkened+contrast21", impl, ctx, plusBaseline({ COLOURS }))
		assert(messages[PAIRINGS] == nil, "AC-2 fired through a constant contrast")
		-- And the constant alone, on the reference, changes nothing else.
		defect("contrastConstant21", {})
	end,

	--[[ ================================================================
	     AC-3 (PT-A2, PT-A3, PT-L1).
	     ================================================================ ]]

	["control (AC-3): size.target.min at 48 × 48 fails AC-3 on both axes (43.20 < 44) and C-1 against the document"] = function()
		local messages = defect("targetShrunk", { TARGETS, SIZES })
		contains(messages[TARGETS], "PT-A2: size.target.min.x = 48 × 0.9 = 43.20, below 44", "x")
		contains(messages[TARGETS], "PT-A2: size.target.min.y = 48 × 0.9 = 43.20, below 44", "y")
		contains(
			messages[SIZES],
			`size.target.min: Theme.size says 48 × 48, tokens.md §5 line {lineOf(
				"sizes",
				"size.target.min"
			)} says 56 × 56`,
			"C-1"
		)
	end,

	["control (AC-3): type.caption at 17 fails AC-3 (15.30 < 16) and C-3 against the document"] = function()
		local messages = defect("captionShrunk", { TARGETS, TYPE })
		contains(messages[TARGETS], "PT-A3: type.caption = 17 × 0.9 = 15.30, below 16", "caption")
		contains(
			messages[TYPE],
			`type.caption: Theme.type says 17, tokens.md §3 line {lineOf("type", "type.caption")} says 18`,
			"C-3"
		)
	end,

	["control (AC-3): a uiScale without the clamp fails PT-L1 at the four AC-3 sizes (0.67, 0.87, 1.79, 2.56) and where the width is the short side - and passes at the clamp edges, where clamped and unclamped agree"] = function()
		local messages = defect("scaleUnclamped", { SCALE })
		contains(messages[SCALE], "uiScale(568, 262) is 0.67", "568 × 262")
		contains(messages[SCALE], "layout.md §2 gives 0.9", "the stated value")
		contains(messages[SCALE], "uiScale(1920, 1000) is 2.56", "1920 × 1000")
		contains(messages[SCALE], "uiScale(300, 800) is 0.76", "width as the short side")
		lacks(messages[SCALE], "uiScale(800, 351)", "the lower clamp edge agrees")
		lacks(messages[SCALE], "uiScale(800, 507)", "the upper clamp edge agrees")
		contains(messages[SCALE], "5 violation(s)", "four sizes plus the narrow one")
	end,

	["control (AC-3): a breakpoint at 400 passes the four AC-3 sizes and is caught only by the formula's edges (429, 479 compact; 480 regular)"] = function()
		local messages = defect("breakpointAt400", { SCALE })
		contains(
			messages[SCALE],
			'breakpoint(800, 479) is "regular", layout.md §2 gives "compact"',
			"479"
		)
		lacks(messages[SCALE], "breakpoint(568, 262)", "the AC-3 sizes pass")
		lacks(messages[SCALE], "breakpoint(1024, 700)", "the AC-3 sizes pass")
	end,

	--[[ ================================================================
	     AC-4 (PT-T3).
	     ================================================================ ]]

	["control (AC-4, required): color.stroke.control set to color.player.3's hue fails AC-4 naming it at chroma 0.800, and AC-1 since the value changed"] = function()
		local messages = defect("strokeTinted", { COLOURS, ACHROMATIC })
		contains(
			messages[ACHROMATIC],
			"PT-T3: color.stroke.control #E8671C has chroma 0.800, above 0.15",
			"stroke"
		)
		contains(messages[COLOURS], "color.stroke.control: Theme says #E8671C", "AC-1")
	end,

	--[[ ================================================================
	     AC-5 (PT-T4, PT-T5, PT-T6).
	     ================================================================ ]]

	["control (AC-5): a tag key that is also a system glyph fails AC-5 naming both sets, and C-4 against the document"] = function()
		local messages = defect("tagIsAGlyph", { DISJOINT, ICON_KEYS })
		contains(messages[DISJOINT], 'PT-T4: "glyph.key" is in both tags and system', "both sets")
	end,

	["control (AC-5): three tags fail AC-5 against tag_alphabet_size = 4, and C-4 against the document"] = function()
		local messages = defect("tagsTooFew", { TAG_COUNT, ICON_KEYS })
		contains(
			messages[TAG_COUNT],
			"PT-T5: Theme.icons.tags has 3 key(s), MechanicsTuning.instance.tag_alphabet_size is 4",
			"count"
		)
	end,

	["control (AC-5): a preset with no icon, and two presets' icons swapped, each fail AC-5 naming the key, the §2.5 icon and the word"] = function()
		local missing = defect("presetIconMissing", { PRESET_ICONS })
		contains(
			missing[PRESET_ICONS],
			`Theme.icons.presets["ready"] is nil, tokens.md §2.5 line {lineOf(
				"presetIcons",
				"Ready"
			)} gives "preset.ready" for "Ready"`,
			"missing"
		)
		local swapped = defect("presetIconSwapped", { PRESET_ICONS })
		contains(swapped[PRESET_ICONS], 'Theme.icons.presets["ready"] is "preset.wait"', "swapped")
		contains(swapped[PRESET_ICONS], "2 violation(s)", "both")
	end,

	["control (AC-5): detents starting at 360/n instead of the top fail PT-T6 on every angle; detents that accept 7 fail PT-T6 on the refusal"] = function()
		local right = defect("detentsFromTheRight", { DETENTS })
		contains(
			right[DETENTS],
			"PT-T6: detents(2)[1].angle is 180, expected 0 (clockwise from the top)",
			"n = 2"
		)
		contains(right[DETENTS], "20 violation(s)", "2 + 3 + 4 + 5 + 6 angles")
		local seven = defect("detentsAcceptSeven", { DETENTS })
		contains(seven[DETENTS], "PT-T6: detents(7) returned", "seven")
		contains(seven[DETENTS], "instead of raising", "no raise")
		contains(seven[DETENTS], "2 violation(s)", "7 and 8")
	end,

	--[[ ================================================================
	     AC-6 (PT-T7).
	     ================================================================ ]]

	["control (AC-6, required): color.player.2 given color.player.5's value fails AC-6 - ΔE 0.00 between seats 2 and 5 in all four modes, and seats 2-3 under protan (20.71) and deutan (14.06) below the seats 1-4 floor - and AC-1 since the value changed"] = function()
		local messages = defect("playerTwoIsFive", { COLOURS, HUES })
		contains(
			messages[HUES],
			"PT-T7 normal: seats 2 (#E69F00) and 5 (#E69F00) are ΔE 0.00 apart, floor 30",
			"normal"
		)
		contains(
			messages[HUES],
			"PT-T7 protan: seats 2 (#E69F00) and 5 (#E69F00) are ΔE 0.00 apart, floor 10",
			"protan"
		)
		contains(
			messages[HUES],
			"PT-T7 deutan: seats 2 (#E69F00) and 5 (#E69F00) are ΔE 0.00 apart, floor 10",
			"deutan"
		)
		contains(
			messages[HUES],
			"PT-T7 tritan: seats 2 (#E69F00) and 5 (#E69F00) are ΔE 0.00 apart, floor 10",
			"tritan"
		)
		contains(
			messages[HUES],
			"PT-T7 protan, seats 1-4: seats 2 (#E69F00) and 3 (#E8671C) are ΔE 20.71 apart, floor 25",
			"seats 1-4 protan"
		)
		contains(
			messages[HUES],
			"PT-T7 deutan, seats 1-4: seats 2 (#E69F00) and 3 (#E8671C) are ΔE 14.06 apart, floor 25",
			"seats 1-4 deutan"
		)
		contains(messages[HUES], "6 violation(s)", "four modes at ΔE 0, plus two seats 1-4 pairs")
	end,

	--[[ ================================================================
	     AC-7 (PT-A5) and C-5.
	     ================================================================ ]]

	["control (AC-7): sfx.ping with an empty visual fails AC-7 naming it, and C-5 against the document"] = function()
		local messages = defect("visualBlank", { VISUALS, AUDIO })
		contains(
			messages[VISUALS],
			'PT-A5: sfx.ping has visual "", expected a non-empty string',
			"AC-7"
		)
		contains(
			messages[AUDIO],
			`sfx.ping: visual is "", tokens.md §8 line {lineOf("audio", "sfx.ping")} says "the marker"`,
			"C-5"
		)
	end,

	["control (C-5): sfx.ui.denied missing - the second cue of a two-cue row - fails exactly C-5, naming the row"] = function()
		local messages = defect("cueMissing", { AUDIO })
		contains(
			messages[AUDIO],
			`sfx.ui.denied: missing from Theme.audio (tokens.md §8 line {lineOf(
				"audio",
				"sfx.ui.denied"
			)})`,
			"C-5"
		)
	end,
}
