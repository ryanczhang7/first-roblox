--!strict
--[[
	THEME-001: the colour arithmetic the accessibility floor is checked with -
	WCAG 2 luminance and contrast, compositing, chroma, CIE Lab and CIE76, and
	Machado 2009 colour-vision simulation. Pure arithmetic; no Instance, no
	Color3, so it runs under Lune as it does in the client.

	COLOURS ARE `RGB` tables of GAMMA-ENCODED sRGB channels in [0, 1], the
	form `fromHex` returns. Linear values exist only inside this module.

	THE READINGS ARE FIXED BY THE STORY'S CONTRACT, not chosen here:

	  C-6  `composite` is per channel in gamma-encoded sRGB,
	       `(1 - t) * fg + t * bg`, UNROUNDED. Contrast is WCAG 2: relative
	       luminance 0.2126 R + 0.7152 G + 0.0722 B over channels linearised
	       with the 0.03928 knee, and `(L1 + 0.05) / (L2 + 0.05)` with L1 the
	       lighter, so it is >= 1 in either order.
	  AC-4 `chroma` is max - min over [0, 1] channels, which is
	       (max - min) / 255 over 8-bit channels (amended from HSV saturation,
	       which scores near-black blue-greys as saturated).
	  C-7  `simulate` LINEARISES, multiplies by the severity-1.0 matrix,
	       clamps each channel to [0, 1] and re-encodes. Applying the matrix
	       to gamma-encoded values is a different, wrong reading: it gives
	       deutan 9.74 and hue-vs-grey 7.43 over the shipped player hues and
	       fails PT-T7, where the linear reading reproduces tokens.md §1.2's
	       published minima (34.9 / 20.7 / 13.5 / 11.2 / 28.6 / 16.8).
	       `toLab` goes linear RGB -> XYZ (D65, sRGB primaries) -> CIE Lab
	       with Xn 0.95047, Yn 1, Zn 1.08883; `deltaE` is CIE76.

	SOURCE OF THE MATRICES: G. M. Machado, M. M. Oliveira and L. A. F.
	Fernandes, "A Physiologically-based Model for Simulation of Color Vision
	Deficiency", IEEE Transactions on Visualization and Computer Graphics
	15(6):1291-1298, 2009 - the severity 1.0 rows of the published table of
	pre-computed matrices (protanopia, deuteranopia, tritanopia). They are
	published constants: do not tune them. Each row sums to 1, so a grey is a
	fixed point of every simulation - a cheap check that a row was not
	mistyped.

	`tests/client/colour_math_test.luau` holds this module to known values,
	to the six published minima and to the test-side reference
	(`tests/helpers/ColourRef.luau`, written separately from the same Contract)
	to 1e-6. Nothing in `src/` may require that reference.
]]

export type RGB = { r: number, g: number, b: number }
export type Lab = { L: number, a: number, b: number }
export type Mode = "protan" | "deutan" | "tritan"
type Matrix = { { number } }

-- Machado, Oliveira & Fernandes 2009, severity 1.0. Row-major, applied to
-- LINEAR RGB: out.r = M[1][1] r + M[1][2] g + M[1][3] b.
local MACHADO: { [Mode]: Matrix } = table.freeze({
	protan = table.freeze({
		table.freeze({ 0.152286, 1.052583, -0.204868 }),
		table.freeze({ 0.114503, 0.786281, 0.099216 }),
		table.freeze({ -0.003882, -0.048116, 1.051998 }),
	}),
	deutan = table.freeze({
		table.freeze({ 0.367322, 0.860646, -0.227968 }),
		table.freeze({ 0.280085, 0.672501, 0.047413 }),
		table.freeze({ -0.011820, 0.042940, 0.968881 }),
	}),
	tritan = table.freeze({
		table.freeze({ 1.255528, -0.076749, -0.178779 }),
		table.freeze({ -0.078411, 0.930809, 0.147602 }),
		table.freeze({ 0.004733, 0.691367, 0.303900 }),
	}),
}) :: any

-- CIE Lab reference white, D65.
local XN, YN, ZN = 0.95047, 1, 1.08883

local function fromHex(hex: string): RGB
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	if r == nil then
		error(`ColourMath.fromHex: "{hex}" is not #RRGGBB`, 2)
	end
	return {
		r = (tonumber(r, 16) :: number) / 255,
		g = (tonumber(g, 16) :: number) / 255,
		b = (tonumber(b, 16) :: number) / 255,
	}
end

local function toByte(v: number): number
	return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
end

-- Upper case, rounded to 8 bits. For display and comparison; the arithmetic
-- above never rounds.
local function toHex(c: RGB): string
	return string.format("#%02X%02X%02X", toByte(c.r), toByte(c.g), toByte(c.b))
end

-- sRGB decode, in the WCAG 2 form (knee 0.03928).
local function toLinearChannel(v: number): number
	if v <= 0.03928 then
		return v / 12.92
	end
	return ((v + 0.055) / 1.055) ^ 2.4
end

-- sRGB encode, the inverse.
local function toGammaChannel(v: number): number
	if v <= 0.0031308 then
		return 12.92 * v
	end
	return 1.055 * v ^ (1 / 2.4) - 0.055
end

local function toLinear(c: RGB): RGB
	return { r = toLinearChannel(c.r), g = toLinearChannel(c.g), b = toLinearChannel(c.b) }
end

local function fromLinear(c: RGB): RGB
	return { r = toGammaChannel(c.r), g = toGammaChannel(c.g), b = toGammaChannel(c.b) }
end

local function luminance(c: RGB): number
	local l = toLinear(c)
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
end

local function contrast(a: RGB, b: RGB): number
	local la, lb = luminance(a), luminance(b)
	local lighter, darker = math.max(la, lb), math.min(la, lb)
	return (lighter + 0.05) / (darker + 0.05)
end

-- `fg` drawn at `transparency` (Roblox's sense: 0 opaque, 1 invisible) over
-- `bg`. C-6.
local function composite(fg: RGB, transparency: number, bg: RGB): RGB
	local t = transparency
	return {
		r = (1 - t) * fg.r + t * bg.r,
		g = (1 - t) * fg.g + t * bg.g,
		b = (1 - t) * fg.b + t * bg.b,
	}
end

local function chroma(c: RGB): number
	return math.max(c.r, c.g, c.b) - math.min(c.r, c.g, c.b)
end

local function labF(t: number): number
	local delta = 6 / 29
	if t > delta * delta * delta then
		return t ^ (1 / 3)
	end
	return t / (3 * delta * delta) + 4 / 29
end

local function toLab(c: RGB): Lab
	local l = toLinear(c)
	-- sRGB primaries, D65 (IEC 61966-2-1).
	local x = 0.4124564 * l.r + 0.3575761 * l.g + 0.1804375 * l.b
	local y = 0.2126729 * l.r + 0.7151522 * l.g + 0.0721750 * l.b
	local z = 0.0193339 * l.r + 0.1191920 * l.g + 0.9503041 * l.b
	local fx, fy, fz = labF(x / XN), labF(y / YN), labF(z / ZN)
	return { L = 116 * fy - 16, a = 500 * (fx - fy), b = 200 * (fy - fz) }
end

local function deltaE(a: RGB, b: RGB): number
	local p, q = toLab(a), toLab(b)
	local dL, da, db = p.L - q.L, p.a - q.a, p.b - q.b
	return math.sqrt(dL * dL + da * da + db * db)
end

local function simulate(c: RGB, mode: Mode): RGB
	local m = MACHADO[mode]
	if m == nil then
		error(`ColourMath.simulate: unknown mode "{tostring(mode)}"`, 2)
	end
	local l = toLinear(c)
	local function row(i: number): number
		local k = m[i]
		return math.clamp(k[1] * l.r + k[2] * l.g + k[3] * l.b, 0, 1)
	end
	return fromLinear({ r = row(1), g = row(2), b = row(3) })
end

return table.freeze({
	MACHADO = MACHADO,
	fromHex = fromHex,
	toHex = toHex,
	toLinear = toLinear,
	fromLinear = fromLinear,
	luminance = luminance,
	contrast = contrast,
	composite = composite,
	chroma = chroma,
	toLab = toLab,
	deltaE = deltaE,
	simulate = simulate,
})
