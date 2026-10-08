--!strict
--[[
	THEME-001 AC-1 .. AC-7 and the Contract's C-1, C-3, C-4 and C-5, written
	once as checks over an IMPLEMENTATION handed in as a parameter -
	`{ Theme, ColourMath, ScreenScale }` - and a `Context` - `tokens.md` read
	off disk by `TokenSpec`, the tunings, and `Presets.ALL` - rather than over
	`src/client/Theme.luau` by name. `tests/client/theme_test.luau` applies
	these to the real modules; `tests/client/theme_controls_test.luau` applies
	them to `ThemeStubs.luau`'s reference and to implementations with EXACTLY
	ONE defect each, so that in RED - where the modules do not exist and every
	check against them stops at the require - every check here has still been
	EXECUTED and observed to refuse the thing it exists to catch.

	THE ORACLE PARTITION (story `## Contract`).
	  SETTLED by tokens.md   AC-1 (colours), AC-5's key sets, C-1 sizes, C-3
	                         type, C-4 icon keys, C-5 audio: every value is READ
	                         OUT of `ctx.spec`, never restated here.
	  SETTLED thresholds     AC-2 floors (read out of §1.4), the scrim ceiling
	  over mechanical        0.12 (PT-A4), the 44 / 16 floors at scale 0.9
	  arithmetic             (PT-A2, PT-A3), the 0.15 chroma ceiling
	                         (PT-T3), PT-T7's four ΔE thresholds, the layout.md
	                         §2 formula (PT-L1), the detent layout (PT-T6). The
	                         arithmetic is `impl.ColourMath`'s, so that D-1
	                         (contrast := 21) is seen by AC-2 through the
	                         shipped module.

	THE NUMBERS WRITTEN HERE, and where each comes from. Each is a threshold
	or a reference point an acceptance criterion states, not a token value:
	  SCALE_FLOOR 0.9, TARGET_MIN 44, TYPE_MIN 16   accessibility.md A-1, A-2
	  SCRIM_MAX 0.12                                 A-4 / PT-A4, AC-2
	  CHROMA_MAX 0.15                                PT-T3, AC-4 (amended: chroma, was HSV)
	  WORST_BACKGROUND #FFFFFF                       §1.4 "pure white behind
	                                                 the scrim"
	  PT_T7 30 / 10 / 25 / 15 and its two reference  accessibility.md §3
	  colours #FFFFFF, #8A93A0                       PT-T7, verbatim
	  SCALE_BASE 390, 0.9 .. 1.3, COMPACT_BELOW 480  layout.md §2
	  TARGETS                                        Contract C-2, by name
	  DETENT range 2..6                              PT-T6

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local TokenSpec = require("./TokenSpec")

local ThemeContract = {}

export type Impl = { Theme: any, ColourMath: any, ScreenScale: any }
export type Context = {
	spec: TokenSpec.Spec, -- tokens.md, read off disk
	mechanics: any, -- MechanicsTuning
	session: any, -- Tuning.session
	presets: { any }, -- Presets.ALL
}
export type Check = { name: string, ac: string, run: (Impl, Context) -> () }

ThemeContract.SCALE_FLOOR = 0.9
ThemeContract.TARGET_MIN = 44
ThemeContract.TYPE_MIN = 16
ThemeContract.SCRIM_MAX = 0.12
ThemeContract.CHROMA_MAX = 0.15
ThemeContract.WORST_BACKGROUND = "#FFFFFF"
ThemeContract.SCRIM_TOKEN = "color.surface.scrim"

-- C-2: the §5 rows that size something a player presses.
ThemeContract.TARGETS =
	table.freeze({ "size.target.min", "size.button.action", "size.tile.preset" })

-- PT-T7, accessibility.md §3.
ThemeContract.PT_T7 = table.freeze({
	normal = 30, -- pairwise, normal vision
	simulated = 10, -- pairwise, under each of the three simulations
	seats14 = 25, -- seats 1-4 pairwise, under all four modes
	vsReference = 15, -- each hue vs each reference colour, under all four modes
	references = table.freeze({ "#FFFFFF", "#8A93A0" }),
})
ThemeContract.MODES = table.freeze({ "protan", "deutan", "tritan" })
-- The four modes PT-T7 names, "normal" first. A list cannot start with nil,
-- so "normal" is a name here and `simulation` maps it to no simulation.
ThemeContract.ALL_MODES = table.freeze({ "normal", "protan", "deutan", "tritan" })

function ThemeContract.simulation(mode: string): string?
	return if mode == "normal" then nil else mode
end

-- layout.md §2 and PT-L1.
ThemeContract.SCALE_BASE = 390
ThemeContract.SCALE_MAX = 1.3
ThemeContract.COMPACT_BELOW = 480
ThemeContract.LAYOUT_CASES = table.freeze({
	-- The four sizes AC-3 names, with the values layout.md states.
	{ w = 568, h = 262, scale = 0.9, breakpoint = "compact" },
	{ w = 667, h = 339, scale = 0.9, breakpoint = "compact" },
	{ w = 1024, h = 700, scale = 1.3, breakpoint = "regular" },
	{ w = 1920, h = 1000, scale = 1.3, breakpoint = "regular" },
	-- The formula's own edges: both clamp points, a value inside the band,
	-- both sides of the breakpoint, and the width as the short side.
	{ w = 800, h = 351, scale = 0.9, breakpoint = "compact" },
	{ w = 800, h = 390, scale = 1.0, breakpoint = "compact" },
	{ w = 800, h = 429, scale = 1.1, breakpoint = "compact" },
	{ w = 800, h = 479, scale = 479 / 390, breakpoint = "compact" },
	{ w = 800, h = 480, scale = 480 / 390, breakpoint = "regular" },
	{ w = 800, h = 507, scale = 1.3, breakpoint = "regular" },
	{ w = 300, h = 800, scale = 0.9, breakpoint = "compact" },
})

ThemeContract.DETENT_MIN = 2
ThemeContract.DETENT_MAX = 6

local EPSILON = 1e-9

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
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

local function fmt(n: number): string
	return string.format("%.2f", n)
end

local function sortedKeys(t: { [string]: any }): { string }
	local out: { string } = {}
	for key in t do
		table.insert(out, tostring(key))
	end
	table.sort(out)
	return out
end

-- Every spec-driven check starts here: the document must have been read.
local function needSpec(criterion: string, ctx: Context)
	local violations = TokenSpec.vacuity(ctx.spec, ctx.session.players_max, #ctx.presets)
	finish(criterion, violations, `reading {TokenSpec.SPEC_PATH} (nothing was compared)`)
end

local function needTheme(criterion: string, impl: Impl)
	if typeof(impl) ~= "table" or typeof(impl.Theme) ~= "table" then
		Contract.fail(
			`{criterion}: Theme is {typeof((impl :: any).Theme)}, expected the module table`
		)
	end
end

local function needMember(criterion: string, impl: Impl, member: string, kind: string)
	needTheme(criterion, impl)
	local value = impl.Theme[member]
	if typeof(value) ~= kind then
		Contract.fail(`{criterion}: Theme.{member} is {typeof(value)}, expected a {kind}`)
	end
end

local function needColourMath(criterion: string, impl: Impl)
	if typeof(impl.ColourMath) ~= "table" then
		Contract.fail(
			`{criterion}: ColourMath is {typeof(impl.ColourMath)}, expected the module table`
		)
	end
	for _, fn in { "fromHex", "composite", "contrast", "chroma", "simulate", "deltaE" } do
		if typeof(impl.ColourMath[fn]) ~= "function" then
			Contract.fail(
				`{criterion}: ColourMath.{fn} is {typeof(impl.ColourMath[fn])}, expected a function`
			)
		end
	end
end

-- Theme.color[token].hex, upper-cased, or nil with a violation recorded.
local function hexOf(impl: Impl, token: string, violations: { string }): string?
	local entry = impl.Theme.color[token]
	if typeof(entry) ~= "table" or typeof(entry.hex) ~= "string" then
		table.insert(violations, `{token}: Theme.color has no entry with a hex string for it`)
		return nil
	end
	return string.upper(entry.hex)
end

--[[ ================================================================
     AC-1 (settled): Theme.color against every color.* row.
     ================================================================ ]]

function ThemeContract.coloursMatchTheSpec(impl: Impl, ctx: Context)
	local criterion = "AC-1"
	needMember(criterion, impl, "color", "table")
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local color: { [string]: any } = impl.Theme.color
	local named: { [string]: boolean } = {}

	for _, row in ctx.spec.colours do
		named[row.token] = true
		local entry = color[row.token]
		if typeof(entry) ~= "table" then
			table.insert(
				violations,
				`{row.token} (tokens.md line {row.line}): missing from Theme.color (got {Deep.show(
					entry
				)})`
			)
			continue
		end
		if typeof(entry.hex) ~= "string" or string.match(entry.hex, "^#%x%x%x%x%x%x$") == nil then
			table.insert(
				violations,
				`{row.token}: hex is {Deep.show(entry.hex)}, expected a #RRGGBB string`
			)
		elseif string.upper(entry.hex) ~= row.hex then
			table.insert(
				violations,
				`{row.token}: Theme says {string.upper(entry.hex)}, tokens.md line {row.line} says {row.hex}`
			)
		end
		if row.transparency ~= nil and entry.transparency ~= row.transparency then
			table.insert(
				violations,
				`{row.token}: transparency is {Deep.show(entry.transparency)}, tokens.md line {row.line} states {row.transparency}`
			)
		end
	end
	for _, token in sortedKeys(color) do
		if not named[token] then
			table.insert(violations, `{token}: in Theme.color, but no tokens.md row names it`)
		end
	end
	finish(criterion, violations, `Theme.color against every color.* row of {TokenSpec.SPEC_PATH}`)
end

--[[ ================================================================
     AC-2 (PT-A1, PT-A4): every §1.4 pairing over the worst composite.
     ================================================================ ]]

-- The worst composite per C-6, from Theme's own scrim. Exposed for the
-- controls, which print it.
function ThemeContract.worstComposite(impl: Impl): (any, number)
	local scrim = impl.Theme.color[ThemeContract.SCRIM_TOKEN]
	local CM = impl.ColourMath
	local t = scrim.transparency
	return CM.composite(CM.fromHex(scrim.hex), t, CM.fromHex(ThemeContract.WORST_BACKGROUND)), t
end

function ThemeContract.pairingsMeetTheFloor(impl: Impl, ctx: Context)
	local criterion = "AC-2"
	needMember(criterion, impl, "color", "table")
	needColourMath(criterion, impl)
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local CM = impl.ColourMath

	local scrim = impl.Theme.color[ThemeContract.SCRIM_TOKEN]
	if typeof(scrim) ~= "table" or typeof(scrim.hex) ~= "string" then
		Contract.fail(
			`{criterion}: Theme.color has no {ThemeContract.SCRIM_TOKEN} with a hex, so there is no composite to test against`
		)
	end
	if typeof(scrim.transparency) ~= "number" then
		Contract.fail(
			`{criterion}: {ThemeContract.SCRIM_TOKEN} has transparency {Deep.show(
				scrim.transparency
			)}, expected a number (PT-A4 needs one to bound)`
		)
	end
	if scrim.transparency > ThemeContract.SCRIM_MAX then
		table.insert(
			violations,
			`PT-A4: {ThemeContract.SCRIM_TOKEN} transparency is {scrim.transparency}, above the ceiling {ThemeContract.SCRIM_MAX}`
		)
	end

	local composite = ThemeContract.worstComposite(impl)
	for _, p in ctx.spec.pairings do
		local hex = hexOf(impl, p.token, violations)
		if hex == nil then
			continue
		end
		local ratio = CM.contrast(CM.fromHex(hex), composite)
		if typeof(ratio) ~= "number" or ratio < p.floor then
			table.insert(
				violations,
				`{p.token} {hex} over the worst composite (scrim at {scrim.transparency} over {ThemeContract.WORST_BACKGROUND}): `
					.. `contrast {if typeof(ratio) == "number" then fmt(ratio) else Deep.show(ratio)}, floor {p.floor} (tokens.md §1.4 line {p.line})`
			)
		end
	end
	finish(
		criterion,
		violations,
		"every tokens.md §1.4 pairing over the worst composite, and the scrim ceiling"
	)
end

--[[ ================================================================
     AC-3 (PT-A2, PT-A3): targets and type at the scale floor.
     ================================================================ ]]

function ThemeContract.targetsAndTypeClearTheFloor(impl: Impl, ctx: Context)
	local criterion = "AC-3"
	needMember(criterion, impl, "size", "table")
	needMember(criterion, impl, "type", "table")
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local floor = ThemeContract.SCALE_FLOOR

	for _, token in ThemeContract.TARGETS do
		local size = impl.Theme.size[token]
		if typeof(size) ~= "table" or typeof(size.x) ~= "number" or typeof(size.y) ~= "number" then
			table.insert(
				violations,
				`{token}: Theme.size has no \{ x, y } entry for it (C-2 names it a target)`
			)
			continue
		end
		for _, axis in { "x", "y" } do
			local rendered = size[axis] * floor
			if rendered < ThemeContract.TARGET_MIN then
				table.insert(
					violations,
					`PT-A2: {token}.{axis} = {size[axis]} × {floor} = {fmt(rendered)}, below {ThemeContract.TARGET_MIN}`
				)
			end
		end
	end

	local typeRows = 0
	for _, row in ctx.spec.type do
		typeRows += 1
		local size = impl.Theme.type[row.token]
		if typeof(size) ~= "number" then
			table.insert(violations, `{row.token}: Theme.type has no number for it`)
			continue
		end
		local rendered = size * floor
		if rendered < ThemeContract.TYPE_MIN then
			table.insert(
				violations,
				`PT-A3: {row.token} = {size} × {floor} = {fmt(rendered)}, below {ThemeContract.TYPE_MIN}`
			)
		end
	end
	if typeRows == 0 then
		table.insert(violations, "no type token was checked")
	end
	finish(criterion, violations, `the C-2 targets and every type token at scale {floor}`)
end

--[[ ================================================================
     AC-3 (PT-L1): uiScale and breakpoint, layout.md §2.
     ================================================================ ]]

function ThemeContract.screenScaleMatchesLayout(impl: Impl, _ctx: Context)
	local criterion = "AC-3"
	local SS = impl.ScreenScale
	if
		typeof(SS) ~= "table"
		or typeof(SS.uiScale) ~= "function"
		or typeof(SS.breakpoint) ~= "function"
	then
		Contract.fail(
			`{criterion}: ScreenScale is {Deep.show(SS)}, expected a table with uiScale and breakpoint functions`
		)
	end
	local violations: { string } = {}
	for _, case in ThemeContract.LAYOUT_CASES do
		local scale = SS.uiScale(case.w, case.h)
		if typeof(scale) ~= "number" or math.abs(scale - case.scale) > EPSILON then
			table.insert(
				violations,
				`PT-L1: uiScale({case.w}, {case.h}) is {Deep.show(scale)}, layout.md §2 gives {case.scale}`
			)
		end
		local bp = SS.breakpoint(case.w, case.h)
		if bp ~= case.breakpoint then
			table.insert(
				violations,
				`PT-L1: breakpoint({case.w}, {case.h}) is {Deep.show(bp)}, layout.md §2 gives "{case.breakpoint}"`
			)
		end
	end
	finish(
		criterion,
		violations,
		"uiScale and breakpoint at the four AC-3 sizes and the formula's edges"
	)
end

--[[ ================================================================
     AC-4 (PT-T3): every §1.1 token is achromatic.
     ================================================================ ]]

function ThemeContract.systemColoursAreAchromatic(impl: Impl, ctx: Context)
	local criterion = "AC-4"
	needMember(criterion, impl, "color", "table")
	needColourMath(criterion, impl)
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local CM = impl.ColourMath
	local checked = 0
	for _, row in TokenSpec.systemColours(ctx.spec) do
		local hex = hexOf(impl, row.token, violations)
		if hex == nil then
			continue
		end
		checked += 1
		local s = CM.chroma(CM.fromHex(hex))
		if typeof(s) ~= "number" or s > ThemeContract.CHROMA_MAX then
			table.insert(
				violations,
				`PT-T3: {row.token} {hex} has chroma {if typeof(s) == "number"
					then string.format("%.3f", s)
					else Deep.show(s)}, above {ThemeContract.CHROMA_MAX}`
			)
		end
	end
	if checked == 0 then
		table.insert(violations, "no system colour was checked")
	end
	finish(
		criterion,
		violations,
		`chroma (max - min) / 255 of every tokens.md §1.1 token (ceiling {ThemeContract.CHROMA_MAX})`
	)
end

--[[ ================================================================
     AC-5 (PT-T4, PT-T5, PT-T6): the four key sets, and the detents.
     ================================================================ ]]

local SETS = table.freeze({ "tags", "patterns", "system" })

local function needIcons(criterion: string, impl: Impl): any
	needMember(criterion, impl, "icons", "table")
	local icons = impl.Theme.icons
	for _, set in SETS do
		if typeof(icons[set]) ~= "table" then
			Contract.fail(
				`{criterion}: Theme.icons.{set} is {typeof(icons[set])}, expected a list of keys`
			)
		end
	end
	if typeof(icons.presets) ~= "table" then
		Contract.fail(
			`{criterion}: Theme.icons.presets is {typeof(icons.presets)}, expected a map of preset key -> icon key`
		)
	end
	return icons
end

function ThemeContract.iconSetsAreDisjoint(impl: Impl, _ctx: Context)
	local criterion = "AC-5"
	local icons = needIcons(criterion, impl)
	local violations: { string } = {}
	local owner: { [string]: string } = {}
	local function claim(set: string, key: any)
		if typeof(key) ~= "string" then
			table.insert(violations, `{set}: holds {Deep.show(key)}, expected a string key`)
			return
		end
		if owner[key] ~= nil then
			table.insert(violations, `PT-T4: "{key}" is in both {owner[key]} and {set}`)
			return
		end
		owner[key] = set
	end
	for _, set in SETS do
		for _, key in icons[set] :: { any } do
			claim(set, key)
		end
	end
	for _, key in sortedKeys(icons.presets) do
		claim("presets", icons.presets[key])
	end
	finish(
		criterion,
		violations,
		"pairwise disjointness of tags, patterns, system and preset icon keys"
	)
end

function ThemeContract.tagAlphabetIsLargeEnough(impl: Impl, ctx: Context)
	local criterion = "AC-5"
	local icons = needIcons(criterion, impl)
	local need = ctx.mechanics.instance.tag_alphabet_size
	if typeof(need) ~= "number" then
		Contract.fail(
			`{criterion}: MechanicsTuning.instance.tag_alphabet_size is {Deep.show(need)}`
		)
	end
	local violations: { string } = {}
	if #icons.tags < need then
		table.insert(
			violations,
			`PT-T5: Theme.icons.tags has {#icons.tags} key(s), MechanicsTuning.instance.tag_alphabet_size is {need}`
		)
	end
	finish(criterion, violations, "the tag alphabet against the tuning")
end

function ThemeContract.presetIconsMatchPresets(impl: Impl, ctx: Context)
	local criterion = "AC-5"
	local icons = needIcons(criterion, impl)
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local byWord: { [string]: TokenSpec.PresetIconRow } = {}
	for _, row in ctx.spec.presetIcons do
		byWord[row.word] = row
	end
	local expected: { [string]: boolean } = {}
	for i, preset in ctx.presets do
		expected[preset.key] = true
		local row = byWord[preset.word]
		if row == nil then
			table.insert(
				violations,
				`Presets.ALL[{i}] "{preset.word}" has no tokens.md §2.5 row, so its icon is unspecified`
			)
			continue
		end
		local got = icons.presets[preset.key]
		if got ~= row.key then
			table.insert(
				violations,
				`Theme.icons.presets["{preset.key}"] is {Deep.show(got)}, tokens.md §2.5 line {row.line} gives "{row.key}" for "{preset.word}"`
			)
		end
	end
	for _, key in sortedKeys(icons.presets) do
		if not expected[key] then
			table.insert(violations, `Theme.icons.presets["{key}"] names no Presets.ALL key`)
		end
	end
	finish(criterion, violations, "exactly one §2.5 icon per Presets.ALL key")
end

function ThemeContract.detentsAreLaidOut(impl: Impl, _ctx: Context)
	local criterion = "AC-5"
	needMember(criterion, impl, "detents", "function")
	local violations: { string } = {}
	local detents = impl.Theme.detents
	for n = ThemeContract.DETENT_MIN, ThemeContract.DETENT_MAX do
		local ok, result = pcall(detents, n)
		if not ok then
			table.insert(violations, `PT-T6: detents({n}) raised: {tostring(result)}`)
			continue
		end
		if typeof(result) ~= "table" or #result ~= n then
			table.insert(
				violations,
				`PT-T6: detents({n}) returned {Deep.show(result)}, expected {n} entries`
			)
			continue
		end
		for i = 1, n do
			local entry = result[i]
			local angle = (i - 1) * 360 / n
			if
				typeof(entry) ~= "table"
				or typeof(entry.angle) ~= "number"
				or math.abs(entry.angle - angle) > EPSILON
			then
				table.insert(
					violations,
					`PT-T6: detents({n})[{i}].angle is {Deep.show(
						if typeof(entry) == "table" then entry.angle else entry
					)}, expected {angle} (clockwise from the top)`
				)
			end
			if typeof(entry) ~= "table" or entry.pips ~= i then
				table.insert(
					violations,
					`PT-T6: detents({n})[{i}].pips is {Deep.show(
						if typeof(entry) == "table" then entry.pips else entry
					)}, expected {i}`
				)
			end
		end
	end
	for _, n in { ThemeContract.DETENT_MAX + 1, ThemeContract.DETENT_MAX + 2 } do
		local ok, result = pcall(detents, n)
		if ok then
			table.insert(
				violations,
				`PT-T6: detents({n}) returned {Deep.show(result)} instead of raising (pips stop being countable past {ThemeContract.DETENT_MAX})`
			)
		end
	end
	finish(
		criterion,
		violations,
		`detents for {ThemeContract.DETENT_MIN}..{ThemeContract.DETENT_MAX}, and refusal past {ThemeContract.DETENT_MAX}`
	)
end

--[[ ================================================================
     AC-6 (PT-T7): the player hues, pairwise, in four modes.
     ================================================================ ]]

-- The PT-T7 measurements over `hues` (hex strings, seat order): the minimum
-- pairwise ΔE per mode over all seats and over seats 1-4, and the minimum
-- hue-vs-reference ΔE over every mode. Exposed so the controls can print
-- the numbers the thresholds are compared against.
function ThemeContract.separation(CM: any, hues: { string }): { [string]: number }
	local out: { [string]: number } = {}
	local modes = ThemeContract.ALL_MODES
	local function colour(hex: string, mode: string?): any
		local c = CM.fromHex(hex)
		return if mode ~= nil then CM.simulate(c, mode) else c
	end
	for _, mode in modes do
		local m = ThemeContract.simulation(mode)
		local all, four = math.huge, math.huge
		for i = 1, #hues do
			for j = i + 1, #hues do
				local d = CM.deltaE(colour(hues[i], m), colour(hues[j], m))
				all = math.min(all, d)
				if j <= 4 then
					four = math.min(four, d)
				end
			end
		end
		out[mode] = all
		out[mode .. "14"] = four
	end
	local vs = math.huge
	for _, hex in hues do
		for _, ref in ThemeContract.PT_T7.references do
			for _, mode in modes do
				local m = ThemeContract.simulation(mode)
				vs = math.min(vs, CM.deltaE(colour(hex, m), colour(ref, m)))
			end
		end
	end
	out.vsReference = vs
	return out
end

function ThemeContract.playerHuesAreSeparable(impl: Impl, ctx: Context)
	local criterion = "AC-6"
	needMember(criterion, impl, "color", "table")
	needColourMath(criterion, impl)
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local CM = impl.ColourMath
	local T = ThemeContract.PT_T7

	local hues: { string } = {}
	for _, row in TokenSpec.playerHues(ctx.spec) do
		local hex = hexOf(impl, row.token, violations)
		if hex ~= nil then
			table.insert(hues, hex)
		end
	end
	finish(criterion, violations, "reading the player hues out of Theme.color")
	if #hues < 2 then
		Contract.fail(`{criterion}: only {#hues} player hue(s) to compare`)
	end

	local function colour(hex: string, mode: string?): any
		local c = CM.fromHex(hex)
		return if mode ~= nil then CM.simulate(c, mode) else c
	end
	local modes = ThemeContract.ALL_MODES
	for _, label in modes do
		local mode = ThemeContract.simulation(label)
		local pairFloor = if mode == nil then T.normal else T.simulated
		for i = 1, #hues do
			for j = i + 1, #hues do
				local d = CM.deltaE(colour(hues[i], mode), colour(hues[j], mode))
				if d < pairFloor then
					table.insert(
						violations,
						`PT-T7 {label}: seats {i} ({hues[i]}) and {j} ({hues[j]}) are ΔE {fmt(d)} apart, floor {pairFloor}`
					)
				end
				if j <= 4 and d < T.seats14 then
					table.insert(
						violations,
						`PT-T7 {label}, seats 1-4: seats {i} ({hues[i]}) and {j} ({hues[j]}) are ΔE {fmt(
							d
						)} apart, floor {T.seats14}`
					)
				end
			end
			for _, ref in T.references do
				local d = CM.deltaE(colour(hues[i], mode), colour(ref, mode))
				if d < T.vsReference then
					table.insert(
						violations,
						`PT-T7 {label}: seat {i} ({hues[i]}) is ΔE {fmt(d)} from {ref}, floor {T.vsReference}`
					)
				end
			end
		end
	end
	finish(
		criterion,
		violations,
		"CIE76 separation of the player hues in normal vision and under Machado protan, deutan and tritan"
	)
end

--[[ ================================================================
     AC-7 (PT-A5): every cue has a visual.
     ================================================================ ]]

function ThemeContract.everyCueHasAVisual(impl: Impl, _ctx: Context)
	local criterion = "AC-7"
	needMember(criterion, impl, "audio", "table")
	local violations: { string } = {}
	local cues = sortedKeys(impl.Theme.audio)
	if #cues == 0 then
		table.insert(violations, "Theme.audio is empty, so nothing was checked")
	end
	for _, cue in cues do
		local entry = impl.Theme.audio[cue]
		if
			typeof(entry) ~= "table"
			or typeof(entry.visual) ~= "string"
			or string.match(entry.visual, "^%s*$") ~= nil
		then
			table.insert(
				violations,
				`PT-A5: {cue} has visual {Deep.show(
					if typeof(entry) == "table" then entry.visual else entry
				)}, expected a non-empty string`
			)
		end
	end
	finish(criterion, violations, "the visual equivalent of every Theme.audio cue")
end

--[[ ================================================================
     C-1, C-3, C-4, C-5 (settled): the other tables, row for row.
     ================================================================ ]]

function ThemeContract.sizesMatchTheSpec(impl: Impl, ctx: Context)
	local criterion = "C-1"
	needMember(criterion, impl, "size", "table")
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local named: { [string]: boolean } = {}
	for _, row in ctx.spec.sizes do
		named[row.token] = true
		local entry = impl.Theme.size[row.token]
		if
			typeof(entry) ~= "table"
			or typeof(entry.x) ~= "number"
			or typeof(entry.y) ~= "number"
		then
			table.insert(
				violations,
				`{row.token}: Theme.size has {Deep.show(entry)}, expected \{ x = {row.x}, y = {row.y} }`
			)
		elseif entry.x ~= row.x or entry.y ~= row.y then
			table.insert(
				violations,
				`{row.token}: Theme.size says {entry.x} × {entry.y}, tokens.md §5 line {row.line} says {row.x} × {row.y}`
			)
		end
	end
	for _, token in sortedKeys(impl.Theme.size) do
		if not named[token] then
			table.insert(violations, `{token}: in Theme.size, but no tokens.md §5 row names it`)
		end
	end
	finish(criterion, violations, "Theme.size against tokens.md §5")
end

function ThemeContract.typeMatchesTheSpec(impl: Impl, ctx: Context)
	local criterion = "C-3"
	needMember(criterion, impl, "type", "table")
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local named: { [string]: boolean } = {}
	for _, row in ctx.spec.type do
		named[row.token] = true
		local got = impl.Theme.type[row.token]
		if got ~= row.size then
			table.insert(
				violations,
				`{row.token}: Theme.type says {Deep.show(got)}, tokens.md §3 line {row.line} says {row.size}`
			)
		end
	end
	for _, token in sortedKeys(impl.Theme.type) do
		if not named[token] then
			table.insert(violations, `{token}: in Theme.type, but no tokens.md §3 row names it`)
		end
	end
	finish(criterion, violations, "Theme.type against tokens.md §3")
end

function ThemeContract.iconKeysMatchTheSpec(impl: Impl, ctx: Context)
	local criterion = "C-4"
	local icons = needIcons(criterion, impl)
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local tables: { [string]: { TokenSpec.KeyRow } } = {
		tags = ctx.spec.tags,
		patterns = ctx.spec.patterns,
		system = ctx.spec.glyphs,
	}
	for _, set in SETS do
		local rows = tables[set]
		local got: { any } = icons[set]
		local want: { string } = {}
		for _, row in rows do
			table.insert(want, row.key)
		end
		if not Deep.equal(want, got) then
			table.insert(
				violations,
				`Theme.icons.{set} is {Deep.show(got)}, tokens.md gives {Deep.show(want)} (verbatim, in table order)`
			)
		end
	end
	finish(
		criterion,
		violations,
		"Theme.icons.tags, .patterns and .system against tokens.md §2.1, §2.3 and §2.4"
	)
end

function ThemeContract.audioMatchesTheSpec(impl: Impl, ctx: Context)
	local criterion = "C-5"
	needMember(criterion, impl, "audio", "table")
	needSpec(criterion, ctx)
	local violations: { string } = {}
	local named: { [string]: boolean } = {}
	for _, row in ctx.spec.audio do
		named[row.cue] = true
		local entry = impl.Theme.audio[row.cue]
		if typeof(entry) ~= "table" then
			table.insert(
				violations,
				`{row.cue}: missing from Theme.audio (tokens.md §8 line {row.line})`
			)
		elseif entry.visual ~= row.visual then
			table.insert(
				violations,
				`{row.cue}: visual is {Deep.show(entry.visual)}, tokens.md §8 line {row.line} says "{row.visual}"`
			)
		end
	end
	for _, cue in sortedKeys(impl.Theme.audio) do
		if not named[cue] then
			table.insert(violations, `{cue}: in Theme.audio, but no tokens.md §8 row names it`)
		end
	end
	finish(criterion, violations, "Theme.audio against tokens.md §8, two-cue rows split")
end

ThemeContract.CHECKS = {
	{ name = "coloursMatchTheSpec", ac = "AC-1", run = ThemeContract.coloursMatchTheSpec },
	{ name = "pairingsMeetTheFloor", ac = "AC-2", run = ThemeContract.pairingsMeetTheFloor },
	{
		name = "targetsAndTypeClearTheFloor",
		ac = "AC-3",
		run = ThemeContract.targetsAndTypeClearTheFloor,
	},
	{
		name = "screenScaleMatchesLayout",
		ac = "AC-3",
		run = ThemeContract.screenScaleMatchesLayout,
	},
	{
		name = "systemColoursAreAchromatic",
		ac = "AC-4",
		run = ThemeContract.systemColoursAreAchromatic,
	},
	{ name = "iconSetsAreDisjoint", ac = "AC-5", run = ThemeContract.iconSetsAreDisjoint },
	{
		name = "tagAlphabetIsLargeEnough",
		ac = "AC-5",
		run = ThemeContract.tagAlphabetIsLargeEnough,
	},
	{ name = "presetIconsMatchPresets", ac = "AC-5", run = ThemeContract.presetIconsMatchPresets },
	{ name = "detentsAreLaidOut", ac = "AC-5", run = ThemeContract.detentsAreLaidOut },
	{ name = "playerHuesAreSeparable", ac = "AC-6", run = ThemeContract.playerHuesAreSeparable },
	{ name = "everyCueHasAVisual", ac = "AC-7", run = ThemeContract.everyCueHasAVisual },
	{ name = "sizesMatchTheSpec", ac = "C-1", run = ThemeContract.sizesMatchTheSpec },
	{ name = "typeMatchesTheSpec", ac = "C-3", run = ThemeContract.typeMatchesTheSpec },
	{ name = "iconKeysMatchTheSpec", ac = "C-4", run = ThemeContract.iconKeysMatchTheSpec },
	{ name = "audioMatchesTheSpec", ac = "C-5", run = ThemeContract.audioMatchesTheSpec },
} :: { Check }

-- Every check against `impl`; the names and messages of those that raised.
function ThemeContract.failures(impl: Impl, ctx: Context): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in ThemeContract.CHECKS do
		local ok, err = pcall(check.run, impl, ctx)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return ThemeContract
