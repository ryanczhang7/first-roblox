--!strict
--[[
	THEME-001, Contract C-6 and C-7: the shipped
	`src/client/models/ColourMath.luau` does the arithmetic the Contract
	fixes, and does it the way the test-side reference (`ColourRef`) does.

	WHY THIS FILE EXISTS beside `theme_test.luau`. AC-2, AC-4 and AC-6 are
	thresholds over arithmetic, and `theme_test.luau` runs them through the
	shipped module. A module that applied the Machado matrix to gamma-encoded
	values would fail AC-6 against the shipped tokens (C-7: deutan 9.74,
	hue-vs-grey 7.43) - but a module that returned, say, ΔE 100 for every pair
	would pass it. The controls in `theme_controls_test.luau` are driven
	through `ColourRef` and cannot see the shipped module. So this file:

	  1. pins the shipped module to the worked example C-7 names - the six
	     minima tokens.md §1.2 publishes, to one decimal, and the Lead PO's
	     independent reproduction to two;
	  2. pins known values with no reference at all: contrast(white, black)
	     = 21, luminance(white) = 1, Lab L of white = 100, the composite the
	     Contract prints (#2B2E32), the chroma of a grey = 0;
	  3. drives the story's three arithmetic controls through the SHIPPED
	     module - the numbers `theme_controls_test.luau` measured through the
	     reference, now confirmed against the thing that ships. GREEN's
	     "confirm each recorded value" step is this file going green.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    ColourMath.fromHex(hex: string) -> RGB         -- "#RRGGBB" -> { r, g, b } in [0, 1], gamma-encoded
	    ColourMath.toHex(rgb: RGB) -> string           -- "#RRGGBB", upper case, rounded to 8 bits
	    ColourMath.luminance(rgb: RGB) -> number       -- WCAG 2 relative luminance
	    ColourMath.contrast(a: RGB, b: RGB) -> number  -- WCAG 2 ratio >= 1, order-independent
	    ColourMath.composite(fg: RGB, transparency: number, bg: RGB) -> RGB  -- C-6, unrounded
	    ColourMath.chroma(rgb: RGB) -> number          -- max(r, g, b) - min(r, g, b), i.e. (max - min) / 255 over 8-bit channels (AC-4 as amended)
	    ColourMath.toLab(rgb: RGB) -> { L, a, b }      -- D65, Xn 0.95047 Yn 1 Zn 1.08883
	    ColourMath.deltaE(a: RGB, b: RGB) -> number    -- CIE76
	    ColourMath.simulate(rgb: RGB, mode: "protan" | "deutan" | "tritan") -> RGB  -- C-7

	In RED the module does not exist and every case fails at `CM()`.

	D-1 (GATES): with `contrast` mutated to the constant 21, the cases named
	"D-1" below go red - the control 2.82 reads 21 and passes its floor
	wrongly, and contrast(white, white) reads 21 rather than 1 - while
	`theme_test.luau`'s AC-2 stays green. Restored, all pass again.
]]

local ColourRef = require("../helpers/ColourRef")
local Presets = require("../../src/ReplicatedStorage/Shared/channel/Presets")
local ThemeContract = require("../helpers/ThemeContract")
local TokenSpec = require("../helpers/TokenSpec")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")

local COLOUR_MATH = "src/client/models/ColourMath.luau"

local loaded, loadResult = pcall(require, "../../src/client/models/ColourMath")

local function CM(): any
	assert(loaded, `{COLOUR_MATH} did not load: {tostring(loadResult)}`)
	return loadResult
end

local function fmt(n: number, decimals: number?): string
	return string.format(`%.{decimals or 2}f`, n)
end

local function near(got: number, want: number, tolerance: number, what: string)
	assert(
		typeof(got) == "number" and math.abs(got - want) <= tolerance,
		`{what}: got {tostring(got)}, expected {want} ± {tolerance}`
	)
end

-- The player hues and the scrim, read out of tokens.md - never restated.
local memo: { hues: { string }, scrim: TokenSpec.ColourRow, muted: TokenSpec.ColourRow }? = nil

local function tokens()
	if memo == nil then
		local spec = TokenSpec.parse(TokenSpec.read())
		local v = TokenSpec.vacuity(spec, Tuning.session.players_max, #Presets.ALL)
		assert(#v == 0, TokenSpec.describe(v))
		local hues: { string } = {}
		for _, row in TokenSpec.playerHues(spec) do
			table.insert(hues, row.hex)
		end
		memo = {
			hues = hues,
			scrim = TokenSpec.colour(spec, ThemeContract.SCRIM_TOKEN) :: TokenSpec.ColourRow,
			muted = TokenSpec.colour(spec, "color.text.muted") :: TokenSpec.ColourRow,
		}
	end
	return memo :: { hues: { string }, scrim: TokenSpec.ColourRow, muted: TokenSpec.ColourRow }
end

local function worstComposite(M: any): any
	local scrim = tokens().scrim
	return M.composite(
		M.fromHex(scrim.hex),
		scrim.transparency :: number,
		M.fromHex(ThemeContract.WORST_BACKGROUND)
	)
end

return {
	--[[ Known values, no reference needed. ]]

	["fromHex parses #RRGGBB into gamma-encoded channels in [0, 1], and toHex rounds back to upper-case #RRGGBB"] = function()
		local M = CM()
		local c = M.fromHex("#FF8000")
		near(c.r, 1, 1e-12, "r")
		near(c.g, 128 / 255, 1e-12, "g")
		near(c.b, 0, 1e-12, "b")
		assert(M.toHex(c) == "#FF8000", `toHex round-trip gave {tostring(M.toHex(c))}`)
		assert(
			M.toHex(M.fromHex("#0e1116")) == "#0E1116",
			"lower-case input is not upper-cased on the way out"
		)
	end,

	["luminance: white is 1, black is 0, and #808080 is about 0.2159 (WCAG 2 linearisation)"] = function()
		local M = CM()
		near(M.luminance(M.fromHex("#FFFFFF")), 1, 1e-9, "white")
		near(M.luminance(M.fromHex("#000000")), 0, 1e-9, "black")
		near(M.luminance(M.fromHex("#808080")), 0.2159, 5e-4, "mid grey")
	end,

	["D-1: contrast(white, black) is 21, contrast(white, white) is 1, and the ratio is the same in either order"] = function()
		local M = CM()
		local white, black = M.fromHex("#FFFFFF"), M.fromHex("#000000")
		near(M.contrast(white, black), 21, 1e-9, "white on black")
		near(M.contrast(black, white), 21, 1e-9, "black on white")
		near(M.contrast(white, white), 1, 1e-9, "white on white")
	end,

	["composite (C-6): the scrim at its stated transparency over #FFFFFF rounds to #2B2E32, and is (1 - t)·fg + t·bg per channel, unrounded"] = function()
		local M = CM()
		local composite = worstComposite(M)
		assert(
			M.toHex(composite) == "#2B2E32",
			`composite is {tostring(M.toHex(composite))}, C-6 says #2B2E32`
		)
		local scrim = M.fromHex(tokens().scrim.hex)
		local t = tokens().scrim.transparency :: number
		near(composite.r, (1 - t) * scrim.r + t, 1e-12, "r is unrounded")
		near(composite.g, (1 - t) * scrim.g + t, 1e-12, "g is unrounded")
		near(composite.b, (1 - t) * scrim.b + t, 1e-12, "b is unrounded")
		-- Full transparency is the background; none is the foreground.
		assert(
			M.toHex(M.composite(scrim, 1, M.fromHex("#FFFFFF"))) == "#FFFFFF",
			"t = 1 is not the background"
		)
		assert(
			M.toHex(M.composite(scrim, 0, M.fromHex("#FFFFFF"))) == tokens().scrim.hex,
			"t = 0 is not the foreground"
		)
	end,

	["chroma (AC-4 as amended): a grey is 0, a pure hue is 1, #808040 is 64/255, #0E1116 is 8/255 (0.031, where HSV saturation read 0.364), #8A93A0 is 22/255"] = function()
		local M = CM()
		near(M.chroma(M.fromHex("#FFFFFF")), 0, 1e-12, "white")
		near(M.chroma(M.fromHex("#000000")), 0, 1e-12, "black")
		near(M.chroma(M.fromHex("#FF0000")), 1, 1e-12, "red")
		near(M.chroma(M.fromHex("#808040")), 64 / 255, 1e-12, "half")
		near(M.chroma(M.fromHex("#0E1116")), 8 / 255, 1e-12, "dark blue-grey")
		near(M.chroma(M.fromHex("#8A93A0")), 22 / 255, 1e-12, "grey-blue")
	end,

	["toLab: white is L 100 a 0 b 0 (D65), black is L 0, and deltaE(white, black) is 100"] = function()
		local M = CM()
		local white = M.toLab(M.fromHex("#FFFFFF"))
		near(white.L, 100, 1e-3, "L of white")
		near(white.a, 0, 1e-2, "a of white")
		near(white.b, 0, 1e-2, "b of white")
		near(M.toLab(M.fromHex("#000000")).L, 0, 1e-9, "L of black")
		near(M.deltaE(M.fromHex("#FFFFFF"), M.fromHex("#000000")), 100, 1e-3, "ΔE white-black")
		near(
			M.deltaE(M.fromHex("#E8671C"), M.fromHex("#E8671C")),
			0,
			1e-12,
			"ΔE of a colour with itself"
		)
	end,

	["simulate (C-7): a grey is unchanged in every mode (the Machado rows sum to 1), pure red under deutan rounds to #A39000 and under protan to #6D5F00 (linear-RGB reading), and every channel is clamped to [0, 1]"] = function()
		local M = CM()
		for _, mode in ThemeContract.MODES do
			assert(
				M.toHex(M.simulate(M.fromHex("#808080"), mode)) == "#808080",
				`a grey changed under {mode}: {tostring(
					M.toHex(M.simulate(M.fromHex("#808080"), mode))
				)}`
			)
		end
		assert(
			M.toHex(M.simulate(M.fromHex("#FF0000"), "deutan")) == "#A39000",
			`red under deutan is {tostring(M.toHex(M.simulate(M.fromHex("#FF0000"), "deutan")))}`
		)
		assert(
			M.toHex(M.simulate(M.fromHex("#FF0000"), "protan")) == "#6D5F00",
			`red under protan is {tostring(M.toHex(M.simulate(M.fromHex("#FF0000"), "protan")))}`
		)
		for _, hex in { "#FF0000", "#00FF00", "#0000FF", "#FFFF00" } do
			for _, mode in ThemeContract.MODES do
				local s = M.simulate(M.fromHex(hex), mode)
				for _, ch in { "r", "g", "b" } do
					assert(
						s[ch] >= 0 and s[ch] <= 1,
						`{hex} under {mode}: {ch} = {s[ch]} is outside [0, 1]`
					)
				end
			end
		end
	end,

	--[[ C-7's worked example: the published minima. ]]

	["C-7 worked example: over the shipped player hues the PT-T7 minima are 34.9 / 20.7 / 13.5 / 11.2 (seats 1-6 normal, protan, deutan, tritan), 28.6 (seats 1-4) and 16.8 (vs #FFFFFF and #8A93A0) to one decimal - tokens.md §1.2's published table - and 34.93 / 20.71 / 13.46 / 11.18 / 28.64 / 16.82 to two"] = function()
		local M = CM()
		local sep = ThemeContract.separation(M, tokens().hues)
		local seats14 = math.min(sep.normal14, sep.protan14, sep.deutan14, sep.tritan14)
		print(
			`        [measured, shipped] normal {fmt(sep.normal)}, protan {fmt(sep.protan)}, deutan {fmt(
				sep.deutan
			)}, tritan {fmt(sep.tritan)}, seats 1-4 {fmt(seats14)}, vs references {fmt(
				sep.vsReference
			)}`
		)
		near(sep.normal, 34.9, 0.05, "seats 1-6 normal (tokens.md §1.2)")
		near(sep.protan, 20.7, 0.05, "seats 1-6 protan")
		near(sep.deutan, 13.5, 0.05, "seats 1-6 deutan")
		near(sep.tritan, 11.2, 0.05, "seats 1-6 tritan")
		near(seats14, 28.6, 0.05, "seats 1-4")
		near(sep.vsReference, 16.8, 0.05, "vs references")
		assert(
			fmt(sep.normal) == "34.93" and fmt(sep.protan) == "20.71",
			"the PO's reproduction, seats 1-6 normal/protan"
		)
		assert(
			fmt(sep.deutan) == "13.46" and fmt(sep.tritan) == "11.18",
			"the PO's reproduction, seats 1-6 deutan/tritan"
		)
		assert(
			fmt(seats14) == "28.64" and fmt(sep.vsReference) == "16.82",
			"the PO's reproduction, seats 1-4 and vs references"
		)
	end,

	--[[ The shipped module against the reference, where the reference was verified. ]]

	["agreement: over the player hues, the scrim and the two PT-T7 references, the shipped simulate/deltaE, contrast and chroma agree with the test-side reference to 1e-6"] = function()
		local M = CM()
		local colours = table.clone(tokens().hues)
		table.insert(colours, tokens().scrim.hex)
		for _, ref in ThemeContract.PT_T7.references do
			table.insert(colours, ref)
		end
		local violations: { string } = {}
		for _, a in colours do
			near(M.chroma(M.fromHex(a)), ColourRef.chroma(ColourRef.fromHex(a)), 1e-6, `chroma {a}`)
			for _, b in colours do
				local shipped = M.contrast(M.fromHex(a), M.fromHex(b))
				local reference = ColourRef.contrast(ColourRef.fromHex(a), ColourRef.fromHex(b))
				if math.abs(shipped - reference) > 1e-6 then
					table.insert(
						violations,
						`contrast({a}, {b}): shipped {shipped}, reference {reference}`
					)
				end
				for _, mode in ThemeContract.ALL_MODES do
					local m = ThemeContract.simulation(mode)
					local sa = if m then M.simulate(M.fromHex(a), m) else M.fromHex(a)
					local sb = if m then M.simulate(M.fromHex(b), m) else M.fromHex(b)
					local ra = if m
						then ColourRef.simulate(ColourRef.fromHex(a), m)
						else ColourRef.fromHex(a)
					local rb = if m
						then ColourRef.simulate(ColourRef.fromHex(b), m)
						else ColourRef.fromHex(b)
					local d, r = M.deltaE(sa, sb), ColourRef.deltaE(ra, rb)
					if math.abs(d - r) > 1e-6 then
						table.insert(
							violations,
							`deltaE({a}, {b}) under {mode}: shipped {d}, reference {r}`
						)
					end
				end
			end
		end
		assert(#violations == 0, `{#violations} disagreement(s):\n{table.concat(violations, "\n")}`)
	end,

	--[[ The story's arithmetic controls, through the SHIPPED module. ]]

	["D-1, control (AC-2) through the shipped module: #6A727E over the worst composite reads 2.82, below the 4.5 floor, while the shipped color.text.muted reads 7.47"] = function()
		local M = CM()
		local composite = worstComposite(M)
		local control = M.contrast(M.fromHex("#6A727E"), composite)
		local muted = M.contrast(M.fromHex(tokens().muted.hex), composite)
		print(
			`        [measured, shipped] AC-2 control #6A727E: {fmt(control)}; color.text.muted: {fmt(
				muted
			)}`
		)
		assert(fmt(control) == "2.82", `the control reads {fmt(control)}, expected 2.82`)
		assert(control < 4.5, "the control must fall below the text floor")
		assert(fmt(muted) == "7.47", `color.text.muted reads {fmt(muted)}, expected 7.47`)
	end,

	["control (AC-4) through the shipped module: color.player.3's hue has chroma 0.800, far above 0.15, while every §1.1 token is at most 0.133"] = function()
		local M = CM()
		local vermillion = M.chroma(M.fromHex(tokens().hues[3]))
		print(
			`        [measured, shipped] AC-4 control {tokens().hues[3]}: chroma {fmt(vermillion, 3)}`
		)
		assert(
			fmt(vermillion, 3) == "0.800",
			`chroma of seat 3 is {fmt(vermillion, 3)}, expected 0.800`
		)
		assert(vermillion > ThemeContract.CHROMA_MAX, "a player hue must exceed the system ceiling")
	end,

	["control (AC-6) through the shipped module: with seat 2 given seat 5's hue, the seats 1-6 minimum is 0.00 in every mode and the seats 1-4 minimum under protan is 20.71, below 25"] = function()
		local M = CM()
		local hues = table.clone(tokens().hues)
		hues[2] = hues[5]
		local sep = ThemeContract.separation(M, hues)
		print(
			`        [measured, shipped] AC-6 control: normal {fmt(sep.normal)}, protan {fmt(
				sep.protan
			)}, deutan {fmt(sep.deutan)}, tritan {fmt(sep.tritan)}, seats 1-4 protan {fmt(
				sep.protan14
			)}`
		)
		for _, mode in ThemeContract.ALL_MODES do
			near(sep[mode], 0, 1e-9, `seats 1-6 minimum under {mode}`)
		end
		assert(
			fmt(sep.protan14) == "20.71",
			`seats 1-4 under protan is {fmt(sep.protan14)}, expected 20.71`
		)
		assert(
			sep.protan14 < ThemeContract.PT_T7.seats14,
			"the control must fall below the seats 1-4 floor"
		)
	end,
}
