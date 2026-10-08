--!strict
--[[
	THEME-001: the reader over `docs/wiki/design/tokens.md`.

	`tokens.md` IS the specification of `src/client/Theme.luau`
	(`architecture.md` §9.9). This module reads the tables out of the document,
	through `GatedFs` (the file is in the gate hash: project.conf has
	`covers | unit | docs/wiki/design/tokens.md`), so that `theme_test.luau`
	compares `Theme` to the document rather than to a copy of it typed into a
	test. AC-1 and AC-5 are SETTLED criteria: no hex value and no key list is
	restated anywhere under `tests/`.

	HOW A ROW IS LOCATED. The document is walked line by line; the current
	markdown heading (any level) is remembered by its leading number
	(`### 1.1 System roles` -> "1.1", `## 5. Sizes` -> "5"). A table row is a
	`|`-delimited line; the header row and the `|---|` row have no backticked
	cell where one is required and are skipped.

	  colours      ANY section: a row whose FIRST cell is exactly one backticked
	               `color.*` token (AC-1's wording). The hex is the first
	               `#RRGGBB` in the remaining cells; the transparency, where the
	               row states one, is the number after the word "transparency"
	               (`BackgroundTransparency` **0.12**, "transparency 0.12",
	               "transparency 0"). The heading is kept, so §1.1 (system) and
	               §1.2 (player) can be told apart.
	  pairings     §1.4: the Floor is the FOURTH cell. A first cell holding a
	               backticked `text.x` / `stroke.x` names `color.text.x` /
	               `color.stroke.x`; a first cell saying "player hues" names
	               every `color.player.<digit>` row (C-6: "read as every hue");
	               a first cell with only a hex names the colour rows carrying
	               that hex. Expanded to distinct (token, floor) pairs.
	  tags         §2.1, first cell.      patterns   §2.3, SECOND cell (the first
	               is the class index).   glyphs     §2.4, first cell.
	  presetIcons  §2.5: the preset word (second cell) and its icon key (third).
	               The link to `Presets.ALL` is the WORD, which both carry.
	  type         §3: the base size is the first number of the third cell
	               ("40 / 1.1" -> 40). C-3.
	  sizes        §5, rows whose first cell is `size.*` (the `world.*` table
	               under the same heading is not read): "56 × 56" -> 56, 56;
	               "32" -> a square; "12 (idle), 20 (target)" and "28 × 14, gap
	               4" -> the first value only. C-1.
	  audio        §8: a first cell naming two cues with " / " is two rows,
	               each taking the matching half of the visual cell when that
	               cell also splits in two, and the whole cell otherwise. C-5.

	VACUITY FIRST, as `PresetSpec` does. A parser that matches nothing compares
	nothing and passes forever, so `vacuity` is asserted BEFORE any comparison
	and pins the counts the document holds today - these are the one place a
	number about the document lives in a test, and they are counts, never
	values. `theme_controls_test.luau` drives `parse` over fixture texts that
	are wrong on purpose and shows each step firing.
]]

local fs = require("./GatedFs")

local TokenSpec = {}

TokenSpec.SPEC_PATH = "docs/wiki/design/tokens.md"

export type ColourRow = {
	line: number,
	token: string,
	hex: string,
	transparency: number?,
	section: string,
}
export type Pairing = { line: number, label: string, token: string, floor: number }
export type KeyRow = { line: number, key: string }
export type PresetIconRow = { line: number, word: string, key: string }
export type TypeRow = { line: number, token: string, size: number }
export type SizeRow = { line: number, token: string, x: number, y: number }
export type AudioRow = { line: number, cue: string, visual: string }

export type Spec = {
	colours: { ColourRow },
	pairings: { Pairing },
	tags: { KeyRow },
	patterns: { KeyRow },
	glyphs: { KeyRow },
	presetIcons: { PresetIconRow },
	type: { TypeRow },
	sizes: { SizeRow },
	audio: { AudioRow },
}

-- The section numbers the reader keys on. A renamed heading reads as zero
-- rows for that table, which vacuity reports.
TokenSpec.SECTIONS = table.freeze({
	system = "1.1",
	player = "1.2",
	pairings = "1.4",
	tags = "2.1",
	patterns = "2.3",
	glyphs = "2.4",
	presetIcons = "2.5",
	type = "3",
	sizes = "5",
	audio = "8",
})

-- The counts the document holds today (2026-10-08). Counts, not values: a
-- row added to or removed from tokens.md moves one of these, and that is the
-- drift guard working. `playerHues` and `presetIcons` are passed in by the
-- caller from `Tuning.session.players_max` and `#Presets.ALL`.
TokenSpec.EXPECTED = table.freeze({
	colours = 21, -- 14 system roles (§1.1) + 6 hues + `color.player.none` (§1.2)
	system = 14,
	-- 4 text/stroke rows + the "player hues" row read as 6 hues; the "violet"
	-- row names color.player.4 at the same floor again and dedupes away.
	pairings = 10,
	tags = 6,
	patterns = 6,
	glyphs = 16,
	type = 5,
	sizes = 10,
	audio = 14, -- 12 rows, two of them naming two cues (C-5)
})

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") :: string
end

-- The cells of a pipe-delimited row, trimmed. A line that is not a table row
-- yields an empty list.
local function cells(line: string): { string }
	local body = trim(line)
	if string.sub(body, 1, 1) ~= "|" then
		return {}
	end
	body = string.sub(body, 2)
	if string.sub(body, -1) == "|" then
		body = string.sub(body, 1, -2)
	end
	local out: { string } = {}
	for cell in string.gmatch(body .. "|", "([^|]*)|") do
		table.insert(out, trim(cell))
	end
	return out
end

-- The text of a cell that is exactly one backticked string, else nil.
local function backticked(cell: string?): string?
	if cell == nil then
		return nil
	end
	return string.match(cell, "^`([^`]+)`$")
end

local function firstHex(text: string): string?
	local hex = string.match(text, "#%x%x%x%x%x%x")
	return if hex ~= nil then string.upper(hex) else nil
end

local function firstNumber(text: string?): number?
	if text == nil then
		return nil
	end
	local n = string.match(text, "(%d+%.?%d*)")
	return if n ~= nil then tonumber(n) else nil
end

-- "1.1" from "### 1.1 System roles (achromatic)", "5" from "## 5. Sizes".
local function sectionOf(line: string): string?
	local number = string.match(line, "^#+%s+([%d%.]+)%s")
	if number == nil then
		return nil
	end
	return (string.gsub(number :: string, "%.$", ""))
end

local function split(text: string, separator: string): { string }
	local out: { string } = {}
	local from = 1
	while true do
		local s, e = string.find(text, separator, from, true)
		if s == nil then
			table.insert(out, trim(string.sub(text, from)))
			break
		end
		table.insert(out, trim(string.sub(text, from, (s :: number) - 1)))
		from = (e :: number) + 1
	end
	return out
end

type RawPairing = { line: number, label: string, kind: string, ref: string, floor: number }

-- Every table of `text`, in file order.
function TokenSpec.parse(text: string): Spec
	local spec: Spec = {
		colours = {},
		pairings = {},
		tags = {},
		patterns = {},
		glyphs = {},
		presetIcons = {},
		type = {},
		sizes = {},
		audio = {},
	}
	local rawPairings: { RawPairing } = {}
	local S = TokenSpec.SECTIONS
	local section = ""

	for lineNumber, raw in string.split(text, "\n") do
		local line = trim(raw)
		local heading = sectionOf(line)
		if heading ~= nil then
			section = heading :: string
			continue
		end
		local row = cells(line)
		if row[1] == nil then
			continue
		end
		local first = backticked(row[1])

		-- Colours: any section.
		if first ~= nil and string.match(first :: string, "^color%.") ~= nil then
			local rest = table.concat(row, " | ", 2)
			local hex = firstHex(rest)
			if hex ~= nil then
				local t = string.match(rest, "[Tt]ransparency[`%*%s]*(%d+%.?%d*)")
				table.insert(spec.colours, {
					line = lineNumber,
					token = first :: string,
					hex = hex :: string,
					transparency = if t ~= nil then tonumber(t) else nil,
					section = section,
				})
			end
			continue
		end

		if section == S.pairings then
			local floor = tonumber(row[4] or "")
			if floor == nil then
				continue
			end
			local named = string.match(row[1], "^`([%w_]+%.[%w_%.]+)`")
			local hex = firstHex(row[1])
			if named ~= nil then
				table.insert(rawPairings, {
					line = lineNumber,
					label = row[1],
					kind = "token",
					ref = "color." .. (named :: string),
					floor = floor :: number,
				})
			elseif string.find(string.lower(row[1]), "player hues", 1, true) ~= nil then
				table.insert(rawPairings, {
					line = lineNumber,
					label = row[1],
					kind = "players",
					ref = "",
					floor = floor :: number,
				})
			elseif hex ~= nil then
				table.insert(rawPairings, {
					line = lineNumber,
					label = row[1],
					kind = "hex",
					ref = hex :: string,
					floor = floor :: number,
				})
			end
		elseif section == S.tags and first ~= nil then
			table.insert(spec.tags, { line = lineNumber, key = first :: string })
		elseif section == S.patterns then
			local key = backticked(row[2])
			if key ~= nil then
				table.insert(spec.patterns, { line = lineNumber, key = key :: string })
			end
		elseif section == S.glyphs and first ~= nil then
			table.insert(spec.glyphs, { line = lineNumber, key = first :: string })
		elseif section == S.presetIcons then
			local word, key = backticked(row[2]), backticked(row[3])
			if word ~= nil and key ~= nil then
				table.insert(
					spec.presetIcons,
					{ line = lineNumber, word = word :: string, key = key :: string }
				)
			end
		elseif section == S.type and first ~= nil then
			local size = firstNumber(row[3])
			if size ~= nil then
				table.insert(
					spec.type,
					{ line = lineNumber, token = first :: string, size = size :: number }
				)
			end
		elseif section == S.sizes and first ~= nil and string.match(first :: string, "^size%.") then
			local value = row[2] or ""
			local x, y = string.match(value, "^(%d+)%s*×%s*(%d+)")
			if x == nil then
				x = string.match(value, "^(%d+)")
				y = x
			end
			if x ~= nil then
				table.insert(spec.sizes, {
					line = lineNumber,
					token = first :: string,
					x = tonumber(x) :: number,
					y = tonumber(y) :: number,
				})
			end
		elseif section == S.audio then
			local cues: { string } = {}
			for _, piece in split(row[1], "/") do
				local cue = backticked(piece)
				if cue ~= nil then
					table.insert(cues, cue :: string)
				end
			end
			if #cues == 0 then
				continue
			end
			local visuals = split(row[3] or "", "/")
			for i, cue in cues do
				local visual = if #visuals == #cues then visuals[i] else trim(row[3] or "")
				table.insert(spec.audio, { line = lineNumber, cue = cue, visual = visual })
			end
		end
	end

	-- Resolve the §1.4 rows against the colour rows, to distinct (token, floor).
	local seen: { [string]: boolean } = {}
	local function add(line: number, label: string, token: string, floor: number)
		local key = `{token}@{floor}`
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(spec.pairings, { line = line, label = label, token = token, floor = floor })
	end
	for _, p in rawPairings do
		if p.kind == "token" then
			add(p.line, p.label, p.ref, p.floor)
		elseif p.kind == "players" then
			for _, c in spec.colours do
				if string.match(c.token, "^color%.player%.%d+$") ~= nil then
					add(p.line, p.label, c.token, p.floor)
				end
			end
		else
			for _, c in spec.colours do
				if c.hex == p.ref then
					add(p.line, p.label, c.token, p.floor)
				end
			end
		end
	end

	return spec
end

-- The §1.1 rows.
function TokenSpec.systemColours(spec: Spec): { ColourRow }
	local out: { ColourRow } = {}
	for _, c in spec.colours do
		if c.section == TokenSpec.SECTIONS.system then
			table.insert(out, c)
		end
	end
	return out
end

-- `color.player.1` .. `color.player.N`, in seat order; `color.player.none`
-- is not a hue.
function TokenSpec.playerHues(spec: Spec): { ColourRow }
	local out: { ColourRow } = {}
	for _, c in spec.colours do
		if string.match(c.token, "^color%.player%.%d+$") ~= nil then
			table.insert(out, c)
		end
	end
	local function seat(row: ColourRow): number
		return tonumber(string.match(row.token, "%d+$")) :: number
	end
	table.sort(out, function(a: ColourRow, b: ColourRow): boolean
		return seat(a) < seat(b)
	end)
	return out
end

function TokenSpec.colour(spec: Spec, token: string): ColourRow?
	for _, c in spec.colours do
		if c.token == token then
			return c
		end
	end
	return nil
end

--[[
	Every way `parse` fails to have read the document, accumulated. Zero
	colour rows is "the extraction matched nothing" and returns at once;
	otherwise every table is held to today's count, every colour token is
	unique, the player hues number `playerHues` (from the tuning), the preset
	icons number `presetIcons` (from `Presets.ALL`), and each §1.4 row that
	prints a hex beside a token prints the hex the token's own row states.
]]
function TokenSpec.vacuity(spec: Spec, playerHues: number, presetIcons: number): { string }
	local out: { string } = {}
	local path = TokenSpec.SPEC_PATH
	local E = TokenSpec.EXPECTED
	if #spec.colours == 0 then
		table.insert(
			out,
			`{path}: no table row has a backticked color.* first cell with a #RRGGBB value - the `
				.. `extraction matched nothing, and a module compared against nothing would pass`
		)
		return out
	end

	local function count(what: string, got: number, want: number)
		if got ~= want then
			table.insert(out, `{path}: read {got} {what} row(s), expected {want}`)
		end
	end
	count("colour", #spec.colours, E.colours)
	count("§1.1 system colour", #TokenSpec.systemColours(spec), E.system)
	count("player hue", #TokenSpec.playerHues(spec), playerHues)
	count("§1.4 pairing (distinct token, floor)", #spec.pairings, E.pairings)
	count("§2.1 tag", #spec.tags, E.tags)
	count("§2.3 pattern", #spec.patterns, E.patterns)
	count("§2.4 glyph", #spec.glyphs, E.glyphs)
	count("§2.5 preset icon", #spec.presetIcons, presetIcons)
	count("§3 type", #spec.type, E.type)
	count("§5 size", #spec.sizes, E.sizes)
	count("§8 audio cue", #spec.audio, E.audio)

	local seen: { [string]: number } = {}
	for _, c in spec.colours do
		if seen[c.token] ~= nil then
			table.insert(
				out,
				`{path}:{c.line}: {c.token} is named twice (first at line {seen[c.token]})`
			)
		end
		seen[c.token] = c.line
	end

	for _, p in spec.pairings do
		local printed = firstHex(p.label)
		local row = TokenSpec.colour(spec, p.token)
		if row == nil then
			table.insert(out, `{path}:{p.line}: §1.4 names {p.token}, which no colour row defines`)
		elseif printed ~= nil and string.match(p.label, "^`") ~= nil and printed ~= row.hex then
			table.insert(
				out,
				`{path}:{p.line}: §1.4 prints {printed} beside {p.token}, whose row (line {row.line}) says {row.hex}`
			)
		end
	end

	return out
end

function TokenSpec.read(): string
	return fs.readFile(TokenSpec.SPEC_PATH)
end

function TokenSpec.describe(violations: { string }): string
	if #violations == 0 then
		return "(the document reads as the token tables)"
	end
	return table.concat(violations, "\n")
end

return TokenSpec
