--!strict
--[[
	SLICE-004 AC-3: the phase-label table in `docs/wiki/design/voice.md` §2.1,
	read off disk and never restated.

	The Contract (P-4) settles the player-facing word for each phase in that
	table, and `src/client/Words.luau` is the module that carries it into the
	client. AC-3's test compares `Words.phase` to this reader's rows, so a
	word changed in the document and not in the module - or the reverse - is
	a red line naming the phase. `TokenSpec.luau` does the same for
	`tokens.md`; the shape here is the same, one section, one table.

	THE READ GOES THROUGH `GatedFs` (HARNESS-022): the file must be in the
	gate hash, and `project.conf` has `covers | unit | docs/wiki/design/voice.md`
	for exactly this reader. A read outside the hash raises before reading.

	WHAT IS PARSED. The first heading whose text begins `### 2.1` opens the
	section; it closes at the next line beginning `#`. Inside it, every line
	of the form

	    | `Lobby` | Lobby |

	is a row: the internal phase name in backticks, then the player-facing
	word, trimmed. The header row and the `|---|---|` rule do not match the
	backtick shape and are skipped. A table under any other heading is not
	read, and a renamed heading reads as zero rows, which `vacuity` reports.

	`parse` is a pure function of text so that the controls test can drive it
	with fixtures - a renamed heading, a second table, a row with no
	backticks - and show the reader finds what it claims to and nothing else.
]]

local fs = require("./GatedFs")

local VoiceSpec = {}

VoiceSpec.PATH = "docs/wiki/design/voice.md"
VoiceSpec.SECTION = "2.1"

export type PhaseRow = { line: number, internal: string, facing: string }

function VoiceSpec.read(): string
	return fs.readFile(VoiceSpec.PATH)
end

-- Every `| \`Internal\` | Facing |` row under the `### <section>` heading.
function VoiceSpec.parsePhaseTable(text: string, section: string?): { PhaseRow }
	local wanted = section or VoiceSpec.SECTION
	local rows: { PhaseRow } = {}
	local inside = false
	local lineNumber = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		local stripped = (string.gsub(line, "\r$", ""))
		if string.sub(stripped, 1, 1) == "#" then
			local heading = string.match(stripped, "^###%s+([%d%.]+)")
			inside = heading == wanted
		elseif inside then
			local internal, facing = string.match(stripped, "^|%s*`([^`]+)`%s*|%s*(.-)%s*|%s*$")
			if internal ~= nil and facing ~= nil then
				table.insert(rows, { line = lineNumber, internal = internal, facing = facing })
			end
		end
	end
	return rows
end

-- Every way the rows fail to be a usable table, accumulated: none at all, a
-- phase named twice, or an empty player-facing cell.
function VoiceSpec.vacuity(rows: { PhaseRow }): { string }
	local out: { string } = {}
	if #rows == 0 then
		table.insert(out, `{VoiceSpec.PATH}: read 0 phase rows under §{VoiceSpec.SECTION}`)
	end
	local seen: { [string]: number } = {}
	for _, row in rows do
		if seen[row.internal] ~= nil then
			table.insert(
				out,
				`{VoiceSpec.PATH} line {row.line}: \`{row.internal}\` is already a row at line {seen[row.internal]}`
			)
		end
		seen[row.internal] = row.line
		if row.facing == "" then
			table.insert(
				out,
				`{VoiceSpec.PATH} line {row.line}: \`{row.internal}\` has an empty player-facing word`
			)
		end
	end
	return out
end

return VoiceSpec
