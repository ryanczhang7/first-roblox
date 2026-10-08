--!strict
--[[
	THEME-001: the reference implementation and the single-defect variants
	the controls in `tests/client/theme_controls_test.luau` drive through
	`ThemeContract`.

	THE REFERENCE IS BUILT FROM THE DOCUMENT, not written out. `PresetStubs`
	could copy ten words into a fixture; here the oracle partition forbids
	restating a hex value or a key list in a test, so `reference(ctx)` derives
	a Theme from `ctx.spec` (tokens.md as `TokenSpec` read it). That makes the
	baseline control weaker than CHAN-002's - a parser reading the document
	consistently wrong would agree with itself - which is why `TokenSpec`'s
	vacuity step pins every table's count and the controls test drives the
	parser over fixture texts separately.

	THE COLOUR ARITHMETIC is `ColourRef`, the test-side reference (its header
	says why one exists). The ScreenScale is layout.md §2's formula.

	Each `with(defect, ctx)` is the reference with EXACTLY ONE thing changed,
	so the set of checks that fire is attributable to that change. The
	story's required controls are `lensChanged`, `playerSevenAdded`,
	`mutedDarkened`, `strokeTinted` and `playerTwoIsFive`; the rest are the
	neighbours that pin each check's edges. `contrastConstant21` is D-1's
	shape: the reference with a ColourMath whose `contrast` is the constant 21,
	which must make `mutedDarkened` stop firing AC-2.

	WHAT THIS IS NOT: `src/client/Theme.luau`, or a sketch of one. Nothing
	here is frozen or typed the way the module must be; the Contract pins
	the shape, the stubs only satisfy it.
]]

local ColourRef = require("./ColourRef")
local ThemeContract = require("./ThemeContract")
local TokenSpec = require("./TokenSpec")

local ThemeStubs = {}

export type Defect =
	"lensChanged"
	| "playerSevenAdded"
	| "colourMissing"
	| "transparencyDropped"
	| "transparencyRaised"
	| "mutedDarkened"
	| "targetShrunk"
	| "captionShrunk"
	| "scaleUnclamped"
	| "breakpointAt400"
	| "strokeTinted"
	| "tagIsAGlyph"
	| "tagsTooFew"
	| "presetIconMissing"
	| "presetIconSwapped"
	| "detentsFromTheRight"
	| "detentsAcceptSeven"
	| "playerTwoIsFive"
	| "visualBlank"
	| "cueMissing"
	| "contrastConstant21"

-- layout.md §2, written out.
ThemeStubs.ScreenScale = {
	uiScale = function(width: number, height: number): number
		return math.clamp(
			math.min(width, height) / ThemeContract.SCALE_BASE,
			ThemeContract.SCALE_FLOOR,
			ThemeContract.SCALE_MAX
		)
	end,
	breakpoint = function(width: number, height: number): string
		return if math.min(width, height) < ThemeContract.COMPACT_BELOW
			then "compact"
			else "regular"
	end,
}

local function detents(n: number): { { angle: number, pips: number } }
	assert(
		n >= ThemeContract.DETENT_MIN and n <= ThemeContract.DETENT_MAX,
		`detents: {n} is outside {ThemeContract.DETENT_MIN}..{ThemeContract.DETENT_MAX}`
	)
	local out = {}
	for i = 1, n do
		table.insert(out, { angle = (i - 1) * 360 / n, pips = i })
	end
	return out
end

-- A Theme derived from the document. Plain tables, so a defect can be
-- applied by assignment.
function ThemeStubs.theme(ctx: ThemeContract.Context): any
	local spec = ctx.spec
	local color: { [string]: any } = {}
	for _, row in spec.colours do
		color[row.token] = { hex = row.hex, transparency = row.transparency }
	end
	local size: { [string]: any } = {}
	for _, row in spec.sizes do
		size[row.token] = { x = row.x, y = row.y }
	end
	local type_: { [string]: number } = {}
	for _, row in spec.type do
		type_[row.token] = row.size
	end
	local function keys(rows: { TokenSpec.KeyRow }): { string }
		local out = {}
		for _, row in rows do
			table.insert(out, row.key)
		end
		return out
	end
	local byWord: { [string]: string } = {}
	for _, row in spec.presetIcons do
		byWord[row.word] = row.key
	end
	local presets: { [string]: string } = {}
	for _, preset in ctx.presets do
		presets[preset.key] = byWord[preset.word]
	end
	local audio: { [string]: any } = {}
	for _, row in spec.audio do
		audio[row.cue] = { visual = row.visual }
	end
	return {
		color = color,
		size = size,
		type = type_,
		icons = {
			tags = keys(spec.tags),
			patterns = keys(spec.patterns),
			system = keys(spec.glyphs),
			presets = presets,
		},
		audio = audio,
		detents = detents,
	}
end

function ThemeStubs.reference(ctx: ThemeContract.Context): ThemeContract.Impl
	return {
		Theme = ThemeStubs.theme(ctx),
		ColourMath = ColourRef,
		ScreenScale = ThemeStubs.ScreenScale,
	}
end

-- The reference with exactly one defect.
function ThemeStubs.with(defect: Defect, ctx: ThemeContract.Context): ThemeContract.Impl
	local impl = ThemeStubs.reference(ctx)
	local T = impl.Theme
	if defect == "lensChanged" then
		T.color["color.signal.lens"].hex = "#DDEBFE" -- AC-1's named control
	elseif defect == "playerSevenAdded" then
		T.color["color.player.7"] = { hex = "#FF00FF" } -- AC-1's named control
	elseif defect == "colourMissing" then
		T.color["color.world.pattern"] = nil
	elseif defect == "transparencyDropped" then
		T.color[ThemeContract.SCRIM_TOKEN].transparency = nil
	elseif defect == "transparencyRaised" then
		T.color[ThemeContract.SCRIM_TOKEN].transparency = 0.2
	elseif defect == "mutedDarkened" then
		T.color["color.text.muted"].hex = "#6A727E" -- AC-2's named control
	elseif defect == "targetShrunk" then
		T.size["size.target.min"] = { x = 48, y = 48 } -- 48 × 0.9 = 43.2
	elseif defect == "captionShrunk" then
		T.type["type.caption"] = 17 -- 17 × 0.9 = 15.3
	elseif defect == "scaleUnclamped" then
		impl.ScreenScale = {
			uiScale = function(w: number, h: number): number
				return math.min(w, h) / ThemeContract.SCALE_BASE
			end,
			breakpoint = ThemeStubs.ScreenScale.breakpoint,
		}
	elseif defect == "breakpointAt400" then
		impl.ScreenScale = {
			uiScale = ThemeStubs.ScreenScale.uiScale,
			breakpoint = function(w: number, h: number): string
				return if math.min(w, h) < 400 then "compact" else "regular"
			end,
		}
	elseif defect == "strokeTinted" then
		-- AC-4's named control: a system role given a player hue.
		T.color["color.stroke.control"].hex = T.color["color.player.3"].hex
	elseif defect == "tagIsAGlyph" then
		T.icons.tags[1] = T.icons.system[1]
	elseif defect == "tagsTooFew" then
		T.icons.tags = { T.icons.tags[1], T.icons.tags[2], T.icons.tags[3] }
	elseif defect == "presetIconMissing" then
		T.icons.presets[ctx.presets[1].key] = nil
	elseif defect == "presetIconSwapped" then
		local a, b = ctx.presets[1].key, ctx.presets[2].key
		T.icons.presets[a], T.icons.presets[b] = T.icons.presets[b], T.icons.presets[a]
	elseif defect == "detentsFromTheRight" then
		T.detents = function(n: number)
			local out = detents(n)
			for i, entry in out do
				entry.angle = i * 360 / n
			end
			return out
		end
	elseif defect == "detentsAcceptSeven" then
		T.detents = function(n: number)
			local out = {}
			for i = 1, n do
				table.insert(out, { angle = (i - 1) * 360 / n, pips = i })
			end
			return out
		end
	elseif defect == "playerTwoIsFive" then
		T.color["color.player.2"].hex = T.color["color.player.5"].hex -- AC-6's named control
	elseif defect == "visualBlank" then
		T.audio["sfx.ping"].visual = ""
	elseif defect == "cueMissing" then
		T.audio["sfx.ui.denied"] = nil
	elseif defect == "contrastConstant21" then
		local CM = table.clone(ColourRef)
		CM.contrast = function(_a: any, _b: any): number
			return 21
		end
		impl.ColourMath = CM
	else
		error(`unknown defect {tostring(defect)}`)
	end
	return impl
end

return ThemeStubs
