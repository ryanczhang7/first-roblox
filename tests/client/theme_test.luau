--!strict
--[[
	THEME-001 AC-1 .. AC-7 and the Contract's C-1, C-3, C-4, C-5, applied to
	the real `src/client/Theme.luau`, `src/client/models/ScreenScale.luau` and
	`src/client/models/ColourMath.luau`.

	The three modules are required through `pcall` at the top and re-checked
	inside every test, as every suite here does. In RED none of them exists,
	so each test below fails at `impl()` with "src/client/Theme.luau did not
	load" - per criterion rather than one LOAD FAIL, so each missing behaviour
	is named separately. That is the right failure: the modules are absent,
	and no stub is made to stand in for them.

	THE CHECKS LIVE IN `tests/helpers/ThemeContract.luau` and are exercised in
	`tests/client/theme_controls_test.luau` against `ThemeStubs.luau`'s
	reference and implementations with exactly one defect each. That file is
	where each check is OBSERVED to fire, which matters in RED because not one
	assertion past `impl()` in THIS file executes until GREEN writes the
	modules.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-5's key sets, C-1,
	C-3, C-4 and C-5 are SETTLED - every value is read out of tokens.md §1-§8
	by `TokenSpec` (through GatedFs; the file is in the gate hash), the counts
	out of `MechanicsTuning`, `Tuning` and `Presets.ALL`. AC-2, AC-3, AC-4, AC-6
	and AC-7 are SETTLED thresholds over MECHANICAL arithmetic, and the
	arithmetic is the shipped `ColourMath`'s, so D-1 (contrast := 21) is seen
	by AC-2 here. `colour_math_test.luau` holds that arithmetic to C-6, C-7
	and tokens.md §1.2's published minima.

	WHAT THIS FILE DOES NOT PIN: whether the module tables are frozen; a
	transparency on a colour whose row states none (nil or any number); how
	`detents` is computed; any member beyond those the Contract names; how
	ColourMath is organised internally beyond the nine exports
	`colour_math_test.luau` lists.
]]

local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Presets = require("../../src/ReplicatedStorage/Shared/channel/Presets")
local ThemeContract = require("../helpers/ThemeContract")
local TokenSpec = require("../helpers/TokenSpec")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")

local THEME = "src/client/Theme.luau"
local SCREEN_SCALE = "src/client/models/ScreenScale.luau"
local COLOUR_MATH = "src/client/models/ColourMath.luau"

local themeLoaded, themeResult = pcall(require, "../../src/client/Theme")
local scaleLoaded, scaleResult = pcall(require, "../../src/client/models/ScreenScale")
local mathLoaded, mathResult = pcall(require, "../../src/client/models/ColourMath")

local function impl(): ThemeContract.Impl
	assert(themeLoaded, `{THEME} did not load: {tostring(themeResult)}`)
	assert(scaleLoaded, `{SCREEN_SCALE} did not load: {tostring(scaleResult)}`)
	assert(mathLoaded, `{COLOUR_MATH} did not load: {tostring(mathResult)}`)
	return { Theme = themeResult, ScreenScale = scaleResult, ColourMath = mathResult }
end

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

return {
	["AC-1: Theme.color holds every backticked color.* row of tokens.md with its hex and its stated transparency, and no colour no row names - after the reader's vacuity steps"] = function()
		ThemeContract.coloursMatchTheSpec(impl(), context())
	end,

	["AC-2 (PT-A1, PT-A4): every tokens.md §1.4 pairing, composited over #FFFFFF at the scrim's transparency per C-6, meets its Floor through ColourMath.contrast; the scrim's transparency is at most 0.12"] = function()
		ThemeContract.pairingsMeetTheFloor(impl(), context())
	end,

	["AC-3 (PT-A2, PT-A3): size.target.min, size.button.action and size.tile.preset × 0.9 are at least 44 on both axes, and every §3 type size × 0.9 is at least 16"] = function()
		ThemeContract.targetsAndTypeClearTheFloor(impl(), context())
	end,

	["AC-3 (PT-L1): ScreenScale.uiScale and .breakpoint give layout.md §2's values at 568×262, 667×339, 1024×700 and 1920×1000 (0.9 compact, 0.9 compact, 1.3 regular, 1.3 regular), and at the formula's clamp and breakpoint edges"] = function()
		ThemeContract.screenScaleMatchesLayout(impl(), context())
	end,

	["AC-4 (PT-T3): every tokens.md §1.1 system token has chroma (max − min) / 255 at most 0.15 through ColourMath.chroma (AC-4 as amended)"] = function()
		ThemeContract.systemColoursAreAchromatic(impl(), context())
	end,

	["AC-5 (PT-T4): Theme.icons.tags, .patterns, .system and the values of .presets are pairwise disjoint"] = function()
		ThemeContract.iconSetsAreDisjoint(impl(), context())
	end,

	["AC-5 (PT-T5): Theme.icons.tags has at least MechanicsTuning.instance.tag_alphabet_size keys"] = function()
		ThemeContract.tagAlphabetIsLargeEnough(impl(), context())
	end,

	["AC-5: Theme.icons.presets maps each Presets.ALL key to the tokens.md §2.5 icon key of that preset's word, and nothing else"] = function()
		ThemeContract.presetIconsMatchPresets(impl(), context())
	end,

	["AC-5 (PT-T6): Theme.detents(n) for n = 2..6 returns n entries with angle (i-1)·360/n clockwise from the top and pips i, and raises for 7 and 8"] = function()
		ThemeContract.detentsAreLaidOut(impl(), context())
	end,

	["AC-6 (PT-T7): the six player hues are pairwise CIE76 ΔE ≥ 30 in normal vision and ≥ 10 under Machado protan, deutan and tritan at severity 1.0; seats 1-4 ≥ 25 in all four; each hue ≥ 15 from #FFFFFF and #8A93A0 in all four - through ColourMath.simulate and .deltaE"] = function()
		ThemeContract.playerHuesAreSeparable(impl(), context())
	end,

	["AC-7 (PT-A5): every Theme.audio cue has a non-empty visual"] = function()
		ThemeContract.everyCueHasAVisual(impl(), context())
	end,

	["C-1: Theme.size holds every tokens.md §5 size.* row as { x, y } (a single value is a square; the first value where the cell gives two), and nothing else"] = function()
		ThemeContract.sizesMatchTheSpec(impl(), context())
	end,

	["C-3: Theme.type holds every tokens.md §3 token's base size, and nothing else"] = function()
		ThemeContract.typeMatchesTheSpec(impl(), context())
	end,

	["C-4: Theme.icons.tags, .patterns and .system are tokens.md §2.1, §2.3 and §2.4's keys, verbatim and in table order"] = function()
		ThemeContract.iconKeysMatchTheSpec(impl(), context())
	end,

	["C-5: Theme.audio's cue set is tokens.md §8's with the two-cue rows split into four cues, each with its half of the visual"] = function()
		ThemeContract.audioMatchesTheSpec(impl(), context())
	end,
}
