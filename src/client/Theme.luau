--!strict
--[[
	THEME-001: the design tokens, as data the client draws with.

	`docs/wiki/design/tokens.md` IS THE SPECIFICATION; this module is source,
	the way `MechanicsTuning.luau` implements `tuning.md` (`architecture.md`
	§9.9). Every key is a token name from that document, verbatim, and every
	value is the document's. `tests/client/theme_test.luau` parses tokens.md
	off disk and compares it with this module row for row, in both directions,
	so a value changed here alone fails, naming the token and the line. Change
	the document first, through the Lead Designer.

	WHAT EACH TABLE HOLDS:

	    color   §1.1 and §1.2: { hex, transparency? }. A transparency exists
	            where the row states one (the scrim and the raised surface
	            at 0.12, the selected surface at 0). Emissive, stroke width
	            and use are presentation details a view adds; they are not
	            colours.
	    size    §5's first table: { x, y } in base pixels before `UIScale`.
	            A single value is a square; where a cell gives two values
	            (`size.reticle` "12 (idle), 20 (target)") the first is the
	            entry and the rest belong to the component story (C-1).
	    type    §3: the base size only (C-3). Font, line height and weight
	            arrive when a view needs them.
	    icons   §2.1 tags, §2.3 class patterns, §2.4 system glyphs, in table
	            order; `presets` maps each `Presets.ALL` key to its §2.5 icon
	            key. `Presets` carries no icon on purpose: Theme owns it.
	    audio   §8: every cue and its visual equivalent (A-6). A row that
	            names two cues is two entries, each with its half of the
	            visual (C-5).

	`detents(n)` is §2.2's dial layout: n detents spaced 360 / n degrees apart
	clockwise from the top, pips = index. It raises past 6, where pips stop
	being countable at a glance (PT-T6), and below 2, where there is no dial.

	The accessibility floor these values must meet (contrast, target and type
	sizes, achromatic system roles, separable player hues) is checked by the
	tests through `models/ColourMath.luau` and `models/ScreenScale.luau`; it is
	not re-checked at run time.

	Pure data and one pure function. Every level is frozen: a view that could
	rewrite a token would hand every later view its edit.
]]

export type Colour = { hex: string, transparency: number? }
export type Size = { x: number, y: number }
export type Detent = { angle: number, pips: number }

local DETENT_MIN = 2
local DETENT_MAX = 6

local function colour(hex: string, transparency: number?): Colour
	return table.freeze({ hex = hex, transparency = transparency })
end

local function size(x: number, y: number?): Size
	return table.freeze({ x = x, y = if y ~= nil then y else x })
end

local function cue(visual: string): { visual: string }
	return table.freeze({ visual = visual })
end

local color: { [string]: Colour } = table.freeze({
	-- §1.1 System roles (achromatic)
	["color.surface.scrim"] = colour("#0E1116", 0.12),
	["color.surface.raised"] = colour("#1B2029", 0.12),
	["color.surface.selected"] = colour("#2A313D", 0),
	["color.text.primary"] = colour("#FFFFFF"),
	["color.text.muted"] = colour("#B8C0CC"),
	["color.text.disabled"] = colour("#8A93A0"),
	["color.stroke.control"] = colour("#8A93A0"),
	["color.stroke.focus"] = colour("#FFFFFF"),
	["color.signal.on"] = colour("#FFFFFF"),
	["color.signal.off"] = colour("#2A313D"),
	["color.signal.lens"] = colour("#DDEBFF"),
	["color.world.housing"] = colour("#3A414C"),
	["color.world.pattern"] = colour("#C9D0DA"),
	["color.world.neutralTrim"] = colour("#5C6470"),
	-- §1.2 Player palette, by seat index
	["color.player.1"] = colour("#00B386"),
	["color.player.2"] = colour("#F0E442"),
	["color.player.3"] = colour("#E8671C"),
	["color.player.4"] = colour("#B58CFF"),
	["color.player.5"] = colour("#E69F00"),
	["color.player.6"] = colour("#56B4E9"),
	["color.player.none"] = colour("#8A93A0"),
})

-- §5, base pixels before UIScale.
local sizeTable: { [string]: Size } = table.freeze({
	["size.target.min"] = size(56, 56),
	["size.button.action"] = size(72, 72),
	["size.tile.preset"] = size(96, 112),
	["size.icon.hud"] = size(32),
	["size.icon.tile"] = size(40),
	["size.tag.cue"] = size(48),
	["size.arrow.cue"] = size(40),
	["size.chip.player"] = size(48),
	["size.progress.segment"] = size(28, 14),
	["size.reticle"] = size(12),
})

-- §3, base sizes before UIScale.
local typeTable: { [string]: number } = table.freeze({
	["type.display"] = 40,
	["type.title"] = 28,
	["type.label"] = 20,
	["type.body"] = 20,
	["type.caption"] = 18,
})

local icons = table.freeze({
	-- §2.1, in table order
	tags = table.freeze({
		"tag.circle",
		"tag.triangle",
		"tag.square",
		"tag.diamond",
		"tag.crescent",
		"tag.bolt",
	}),
	-- §2.3, by key class index
	patterns = table.freeze({
		"class.bars_h",
		"class.bars_v",
		"class.diagonal",
		"class.checker",
		"class.chevron",
		"class.crosshatch",
	}),
	-- §2.4, in table order
	system = table.freeze({
		"glyph.key",
		"glyph.eye",
		"glyph.live",
		"glyph.next",
		"glyph.done",
		"glyph.wrong",
		"glyph.notyet",
		"glyph.lens",
		"glyph.pair",
		"glyph.finale",
		"glyph.ping",
		"glyph.preset",
		"glyph.wait",
		"glyph.dark",
		"glyph.again",
		"glyph.guess",
	}),
	-- §2.5, keyed by `Presets.ALL[i].key`
	presets = table.freeze({
		help = "preset.help",
		on_my_way = "preset.on_my_way",
		follow_me = "preset.follow_me",
		wait = "preset.wait",
		go = "preset.go",
		ready = "preset.ready",
		got_it = "preset.got_it",
		thanks = "preset.thanks",
		nice_one = "preset.nice_one",
		well_played = "preset.well_played",
	}),
})

-- §8: cue -> its visual equivalent, verbatim.
local audio: { [string]: { visual: string } } = table.freeze({
	["sfx.commit"] = cue("room brightens; progress bar fills a segment"),
	["sfx.fail"] = cue("C-21 facility pulse at the screen edges"),
	["sfx.turn.wrong"] = cue("✕ on the dial control, shake"),
	["sfx.turn.notyet"] = cue("hourglass on the dial control"),
	["sfx.finale.armed"] = cue("armed ring on the dial control"),
	["sfx.blackout"] = cue("the room goes dark; C-21 with `glyph.dark`"),
	["sfx.ping"] = cue("the marker"),
	["sfx.ping.helper"] = cue("the helper badge + edge arrow"),
	["sfx.preset"] = cue("bubble + beacon"),
	["sfx.cue.live"] = cue("the live turn cue card appears"),
	["sfx.ui.press"] = cue("press state"),
	["sfx.ui.denied"] = cue("wait state"),
	["sfx.outcome.won"] = cue("the outcome banner"),
	["sfx.outcome.lost"] = cue("the outcome banner"),
})

local function detents(n: number): { Detent }
	if n ~= math.floor(n) or n < DETENT_MIN or n > DETENT_MAX then
		error(
			`Theme.detents: {tostring(n)} settings cannot be laid out; tokens.md §2.2 allows {DETENT_MIN}..{DETENT_MAX}`,
			2
		)
	end
	local out: { Detent } = {}
	for i = 1, n do
		out[i] = table.freeze({ angle = (i - 1) * 360 / n, pips = i })
	end
	return table.freeze(out)
end

return table.freeze({
	color = color,
	size = sizeTable,
	type = typeTable,
	icons = icons,
	audio = audio,
	detents = detents,
})
