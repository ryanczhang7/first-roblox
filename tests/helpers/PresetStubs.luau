--!strict
--[[
	CHAN-002: the reference preset table and the single-defect variants the
	controls in `tests/shared/presets_controls_test.luau` drive through
	`PresetContract`.

	THE REFERENCE IS A FIXTURE COPY of mechanics.md §4.2, written out here on
	purpose: the baseline control ("the reference passes every check") is then
	an OBSERVATION that `PresetSpec` reads the real document into exactly these
	ten rows, these words, these phases, in this order. A reference built from
	the parser's own output would agree with the parser whatever it read.

	Each `with(defect)` is the reference with EXACTLY ONE thing changed, so the
	set of checks that fire is attributable to that change. `factTable` is the
	one exception the story names: AC-3's hand-built bad table.

	WHAT THIS IS NOT: `src/ReplicatedStorage/Shared/channel/Presets.luau`, or a sketch of one.
	`build` freezes everything because P-5 demands it of the module, not
	because the module must be built this way.
]]

local PresetContract = require("./PresetContract")

local PresetStubs = {}

export type Entry = { word: string, phases: { string } }

export type Defect =
	"wordChanged"
	| "rowRemoved"
	| "rowAdded"
	| "rowsSwapped"
	| "phaseDropped"
	| "phaseChanged"
	| "unknownPhase"
	| "terminalPunctuation"
	| "idOffByOne"
	| "keyChanged"
	| "iconField"
	| "byIdLenient"
	| "byIdReturnsCopy"
	| "unfrozenAll"
	| "unfrozenPreset"
	| "unfrozenPhases"

-- mechanics.md §4.2, as a fixture. The baseline control proves the copy.
PresetStubs.ROWS = table.freeze({
	{ word = "Ready", phases = { "Round", "Lobby" } },
	{ word = "Wait", phases = { "Round" } },
	{ word = "Go", phases = { "Round" } },
	{ word = "Help", phases = { "Round" } },
	{ word = "On my way", phases = { "Round" } },
	{ word = "Follow me", phases = { "Round" } },
	{ word = "Got it", phases = { "Round" } },
	{ word = "Thanks", phases = { "Round", "Post" } },
	{ word = "Nice one", phases = { "Round", "Post" } },
	{ word = "Well played", phases = { "Post" } },
}) :: { Entry }

type Options = {
	keys: { string }?,
	idOffset: number?,
	icon: boolean?,
	byId: ((ALL: { any }) -> (any) -> any)?,
	freezeAll: boolean?,
	freezePreset: boolean?,
	freezePhases: boolean?,
}

local function copyRows(rows: { Entry }): { Entry }
	local out: { Entry } = {}
	for _, row in rows do
		table.insert(out, { word = row.word, phases = table.clone(row.phases) })
	end
	return out
end

-- A Presets-shaped module over `rows`, the Contract's way unless an option
-- says otherwise.
function PresetStubs.build(rows: { Entry }, options: Options?): any
	local opts: Options = options or {}
	local keys = opts.keys or PresetContract.KEYS
	local ALL: { any } = {}
	for i, row in rows do
		local phases = table.clone(row.phases)
		if opts.freezePhases ~= false then
			table.freeze(phases)
		end
		local preset: { [string]: any } = {
			id = i + (opts.idOffset or 0),
			key = keys[i],
			word = row.word,
			phases = phases,
		}
		if opts.icon then
			preset.icon = "icon_" .. tostring(i)
		end
		if opts.freezePreset ~= false then
			table.freeze(preset)
		end
		ALL[i] = preset
	end
	if opts.freezeAll ~= false then
		table.freeze(ALL)
	end
	local byId = if opts.byId
		then opts.byId(ALL)
		else function(id: any): any
			return ALL[id]
		end
	return table.freeze({ ALL = ALL, byId = byId })
end

-- The Contract written out.
PresetStubs.reference = PresetStubs.build(PresetStubs.ROWS)

-- AC-3's hand-built bad table: six fact words, one per category C2/C8 names.
PresetStubs.FACT_WORDS = table.freeze({ "Red", "Two", "First", "Left", "Yes", "Hello" })

PresetStubs.factTable = PresetStubs.build((function(): { Entry }
	local rows: { Entry } = {}
	for _, word in PresetStubs.FACT_WORDS do
		table.insert(rows, { word = word, phases = { "Round" } })
	end
	return rows
end)())

-- The reference with exactly one defect.
function PresetStubs.with(defect: Defect): any
	local rows = copyRows(PresetStubs.ROWS)
	if defect == "wordChanged" then
		rows[3].word = "Go now" -- D-1's shape
		return PresetStubs.build(rows)
	elseif defect == "rowRemoved" then
		table.remove(rows, 4) -- Help
		return PresetStubs.build(rows)
	elseif defect == "rowAdded" then
		table.insert(rows, { word = "Okay", phases = { "Round" } })
		local keys = table.clone(PresetContract.KEYS)
		table.insert(keys, "okay")
		return PresetStubs.build(rows, { keys = keys })
	elseif defect == "rowsSwapped" then
		rows[2], rows[3] = rows[3], rows[2] -- Wait <-> Go; keys stay in Contract order
		return PresetStubs.build(rows)
	elseif defect == "phaseDropped" then
		rows[10].phases = {} -- D-2's shape: Well played loses Post
		return PresetStubs.build(rows)
	elseif defect == "phaseChanged" then
		rows[2].phases = { "Lobby" } -- Wait: Round -> Lobby
		return PresetStubs.build(rows)
	elseif defect == "unknownPhase" then
		rows[2].phases = { "Intermission" }
		return PresetStubs.build(rows)
	elseif defect == "terminalPunctuation" then
		rows[4].word = "Help!" -- D-3's shape
		return PresetStubs.build(rows)
	elseif defect == "idOffByOne" then
		return PresetStubs.build(rows, { idOffset = -1 })
	elseif defect == "keyChanged" then
		local keys = table.clone(PresetContract.KEYS)
		keys[3] = "go_now"
		return PresetStubs.build(rows, { keys = keys })
	elseif defect == "iconField" then
		return PresetStubs.build(rows, { icon = true })
	elseif defect == "byIdLenient" then
		return PresetStubs.build(rows, {
			byId = function(ALL: { any }): (any) -> any
				return function(id: any): any
					local n = tonumber(id)
					return if n ~= nil then ALL[math.floor(n)] else nil
				end
			end,
		})
	elseif defect == "byIdReturnsCopy" then
		return PresetStubs.build(rows, {
			byId = function(ALL: { any }): (any) -> any
				return function(id: any): any
					local entry = ALL[id]
					return if entry ~= nil then table.clone(entry) else nil
				end
			end,
		})
	elseif defect == "unfrozenAll" then
		return PresetStubs.build(rows, { freezeAll = false })
	elseif defect == "unfrozenPreset" then
		return PresetStubs.build(rows, { freezePreset = false })
	elseif defect == "unfrozenPhases" then
		return PresetStubs.build(rows, { freezePhases = false })
	end
	error(`unknown defect {tostring(defect)}`)
end

return PresetStubs
