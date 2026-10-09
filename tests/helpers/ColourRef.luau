--!strict
--[[
	THEME-001: the TEST-SIDE reference colour arithmetic.

	WHY A SECOND IMPLEMENTATION EXISTS. AC-2, AC-4 and AC-6 are settled
	thresholds over mechanical arithmetic (story `## Contract`, "Oracle
	partition"), and every one of their negative controls - the muted text
	darkened to `#6A727E`, the stroke tinted with a player hue, seat 2 given
	seat 5's hue - is a NUMBER a threshold must reject. In RED
	`src/client/models/ColourMath.luau` does not exist, so a control written
	only against it has never run and the thresholds in the suite are claims.
	This module is the instrument that lets `theme_controls_test.luau` MEASURE
	them in RED. `colour_math_test.luau` then holds the shipped module to the
	same numbers, and to the six minima `tokens.md` §1.2 publishes.

	IT IS NOT THE MODULE UNDER TEST and nothing in `src/` may require it. It
	is written to the Contract's reading and nothing else:

	  C-6  composite per channel in gamma-encoded sRGB, `(1 - t) * fg + t * bg`,
	       unrounded; WCAG 2 relative luminance from linearised sRGB;
	       contrast `(L1 + 0.05) / (L2 + 0.05)` with L1 the lighter.
	  C-7  Machado, Oliveira & Fernandes (IEEE TVCG 15(6), 2009) severity-1.0
	       matrices applied to LINEAR RGB, each channel clamped to [0, 1], then
	       XYZ (D65, sRGB primaries) -> CIE Lab (Xn 0.95047, Yn 1, Zn 1.08883)
	       -> CIE76.

	VERIFIED IN RED against the worked example the Contract names: under this
	reading the six seat minima come out 34.93 / 20.71 / 13.46 / 11.18 / 28.64
	/ 16.82, matching tokens.md §1.2's 34.9 / 20.7 / 13.5 / 11.2 / 28.6 / 16.8
	and the Lead PO's independent awk reproduction. The gamma-encoded reading
	gives deutan 9.74 and hue-vs-grey 7.43, which fail PT-T7. So a disagreement
	between this module and the shipped one is a defect in whichever departs
	from C-7, not a matter of taste.

	Colours are `RGB` tables with gamma-encoded channels in [0, 1]. `fromHex`
	is the only parser; a test never does channel arithmetic itself.
]]

local ColourRef = {}

export type RGB = { r: number, g: number, b: number }
export type Lab = { L: number, a: number, b: number }
export type Mode = "protan" | "deutan" | "tritan"

ColourRef.MODES = table.freeze({ "protan", "deutan", "tritan" }) :: { Mode }

-- Machado et al. 2009, Table 2 (the published severity-1.0 rows), applied to
-- linear RGB. Row-major: out_r = M[1][1] r + M[1][2] g + M[1][3] b.
ColourRef.MACHADO = table.freeze({
	protan = {
		{ 0.152286, 1.052583, -0.204868 },
		{ 0.114503, 0.786281, 0.099216 },
		{ -0.003882, -0.048116, 1.051998 },
	},
	deutan = {
		{ 0.367322, 0.860646, -0.227968 },
		{ 0.280085, 0.672501, 0.047413 },
		{ -0.011820, 0.042940, 0.968881 },
	},
	tritan = {
		{ 1.255528, -0.076749, -0.178779 },
		{ -0.078411, 0.930809, 0.147602 },
		{ 0.004733, 0.691367, 0.303900 },
	},
}) :: { [string]: { { number } } }

function ColourRef.fromHex(hex: string): RGB
	local digits = string.match(hex, "^#(%x%x%x%x%x%x)$")
	assert(digits ~= nil, `ColourRef.fromHex: "{hex}" is not #RRGGBB`)
	local d = digits :: string
	return {
		r = tonumber(string.sub(d, 1, 2), 16) :: number / 255,
		g = tonumber(string.sub(d, 3, 4), 16) :: number / 255,
		b = tonumber(string.sub(d, 5, 6), 16) :: number / 255,
	}
end

-- Rounded to 8 bits per channel, upper case. For messages and for the
-- Contract's `#2B2E32`; the arithmetic itself never rounds.
function ColourRef.toHex(c: RGB): string
	local function byte(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
end

-- sRGB transfer function, the WCAG 2 form.
local function linearise(v: number): number
	if v <= 0.03928 then
		return v / 12.92
	end
	return ((v + 0.055) / 1.055) ^ 2.4
end

local function encode(v: number): number
	if v <= 0.0031308 then
		return 12.92 * v
	end
	return 1.055 * v ^ (1 / 2.4) - 0.055
end

function ColourRef.toLinear(c: RGB): RGB
	return { r = linearise(c.r), g = linearise(c.g), b = linearise(c.b) }
end

function ColourRef.fromLinear(c: RGB): RGB
	return { r = encode(c.r), g = encode(c.g), b = encode(c.b) }
end

-- WCAG 2 relative luminance.
function ColourRef.luminance(c: RGB): number
	local l = ColourRef.toLinear(c)
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
end

-- WCAG 2 contrast ratio, >= 1 whichever order the two are given in.
function ColourRef.contrast(a: RGB, b: RGB): number
	local la, lb = ColourRef.luminance(a), ColourRef.luminance(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

-- C-6: `fg` drawn at `transparency` over `bg`, per channel, gamma-encoded,
-- unrounded.
function ColourRef.composite(fg: RGB, transparency: number, bg: RGB): RGB
	local t = transparency
	return {
		r = (1 - t) * fg.r + t * bg.r,
		g = (1 - t) * fg.g + t * bg.g,
		b = (1 - t) * fg.b + t * bg.b,
	}
end

-- Chroma: max - min over channels in [0, 1], which is (max - min) / 255 over
-- 8-bit channels - AC-4 as amended (THEME-001 `## Amendments`). A grey is 0,
-- a pure hue is 1, and a dark blue-grey like #0E1116 is 0.031.
function ColourRef.chroma(c: RGB): number
	return math.max(c.r, c.g, c.b) - math.min(c.r, c.g, c.b)
end

-- Linear RGB -> XYZ, D65, sRGB primaries (IEC 61966-2-1).
local function toXYZ(l: RGB): (number, number, number)
	local x = 0.4124564 * l.r + 0.3575761 * l.g + 0.1804375 * l.b
	local y = 0.2126729 * l.r + 0.7151522 * l.g + 0.0721750 * l.b
	local z = 0.0193339 * l.r + 0.1191920 * l.g + 0.9503041 * l.b
	return x, y, z
end

local function labF(t: number): number
	local delta = 6 / 29
	if t > delta ^ 3 then
		return t ^ (1 / 3)
	end
	return t / (3 * delta ^ 2) + 4 / 29
end

-- CIE Lab, D65 white (Xn 0.95047, Yn 1, Zn 1.08883).
function ColourRef.toLab(c: RGB): Lab
	local x, y, z = toXYZ(ColourRef.toLinear(c))
	local fx, fy, fz = labF(x / 0.95047), labF(y / 1), labF(z / 1.08883)
	return { L = 116 * fy - 16, a = 500 * (fx - fy), b = 200 * (fy - fz) }
end

-- CIE76: Euclidean distance in Lab.
function ColourRef.deltaE(a: RGB, b: RGB): number
	local p, q = ColourRef.toLab(a), ColourRef.toLab(b)
	return math.sqrt((p.L - q.L) ^ 2 + (p.a - q.a) ^ 2 + (p.b - q.b) ^ 2)
end

-- C-7: Machado severity 1.0 in LINEAR RGB, clamped, re-encoded so the result
-- is an ordinary RGB that `toLab` and `deltaE` accept.
function ColourRef.simulate(c: RGB, mode: Mode): RGB
	local m = ColourRef.MACHADO[mode]
	assert(m ~= nil, `ColourRef.simulate: unknown mode "{tostring(mode)}"`)
	local l = ColourRef.toLinear(c)
	local out = {
		r = math.clamp(m[1][1] * l.r + m[1][2] * l.g + m[1][3] * l.b, 0, 1),
		g = math.clamp(m[2][1] * l.r + m[2][2] * l.g + m[2][3] * l.b, 0, 1),
		b = math.clamp(m[3][1] * l.r + m[3][2] * l.g + m[3][3] * l.b, 0, 1),
	}
	return ColourRef.fromLinear(out)
end

return ColourRef
