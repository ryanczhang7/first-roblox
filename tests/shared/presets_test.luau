--!strict
--[[
	CHAN-002: the preset table obeys the countable preset-guideline rules.
	AC-1 .. AC-5 and the Contract's P-3, P-4 and P-5, applied to the real
	`src/ReplicatedStorage/Shared/channel/Presets.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as every suite here does. In RED the module does not exist,
	so each test below fails at `presets()` with
	"src/ReplicatedStorage/Shared/channel/Presets.luau did not load" - per criterion rather
	than one LOAD FAIL, so each missing behaviour is named separately. That is
	the right failure: the module is absent, and no stub is made to stand in
	for it.

	THE CHECKS LIVE IN `tests/helpers/PresetContract.luau` and are exercised
	in `tests/shared/presets_controls_test.luau` against `PresetStubs.luau`'s
	reference and tables with exactly one defect each. That file is where each
	check is OBSERVED to fire, which matters in RED because not one assertion
	past `presets()` in THIS file executes until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`): AC-1 and AC-2 are SETTLED -
	the words and phases are read out of mechanics.md §4.2 by `PresetSpec`
	(through GatedFs; the file is in the gate hash), the counts out of
	`MechanicsTuning.channel`. AC-3's denylist is INVENTED and lives in
	`PresetContract.DENYLIST`; its control is the hand-built bad table in the
	controls file. AC-4, AC-5 and P-3 .. P-5 are MECHANICAL. P-1: the Phase
	set is READ out of `src/ReplicatedStorage/Net/Remotes.luau` by `PhaseUnion` and asserted
	equal to `PhaseUnion.KNOWN` before any membership check; no list of phase
	names is written here.

	WHAT THIS FILE DOES NOT PIN: whether the module table itself is frozen
	(only ALL, each preset and each phases list); how `byId` is implemented
	(index, map or loop - only its results); whether `phases` is a type alias
	or `{ string }` inline; any member beyond `ALL` and `byId`.
]]

local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PhaseUnion = require("../helpers/PhaseUnion")
local PresetContract = require("../helpers/PresetContract")
local PresetSpec = require("../helpers/PresetSpec")
local fs = require("../helpers/GatedFs")

local REMOTES = "src/ReplicatedStorage/Net/Remotes.luau"

local loaded, loadResult = pcall(require, "../../src/ReplicatedStorage/Shared/channel/Presets")

local function presets(): any
	assert(
		loaded,
		`src/ReplicatedStorage/Shared/channel/Presets.luau did not load: {tostring(loadResult)}`
	)
	return loadResult
end

local memo: PresetContract.Context? = nil

local function context(): PresetContract.Context
	if memo == nil then
		memo = {
			rows = PresetSpec.rows(PresetSpec.read()),
			phases = PresetContract.phaseSet(PhaseUnion.read(REMOTES, fs.readFile(REMOTES))),
			tuning = MechanicsTuning,
		}
	end
	return memo :: PresetContract.Context
end

return {
	["AC-1: Presets.ALL agrees row for row with mechanics.md §4.2 read off disk - same words, same order, same phases - after the reader's three vacuity steps (ten rows, each with a word and at least one phase)"] = function()
		PresetContract.tableMatchesTheSpec(presets(), context())
	end,

	["AC-2: #Presets.ALL == MechanicsTuning.channel.preset_count, and preset_count + ping_kinds <= presets_plus_pings_max (C1), every number read from the tuning"] = function()
		PresetContract.countsAgreeWithTheTuning(presets(), context())
	end,

	["AC-3: no lower-cased token of any preset word is a colour, shape, number, digit, ordinal, sequence, direction, polarity or greeting word (C2, C8) - 'one' excepted, per mechanics.md §4.2 T12"] = function()
		PresetContract.noWordNamesAFact(presets(), context())
	end,

	["AC-4: no preset word ends in '.', '!' or '?' (C6)"] = function()
		PresetContract.noWordEndsInTerminalPunctuation(presets(), context())
	end,

	["AC-5: every preset's phase list is non-empty and every entry is one of the phases Remotes.Phase declares, the set read out of src/ReplicatedStorage/Net/Remotes.luau and equal to PhaseUnion.KNOWN"] = function()
		PresetContract.phasesAreNonEmptyAndKnown(presets(), context())
	end,

	["P-3: ALL[i].id == i, the keys are exactly ready, wait, go, help, on_my_way, follow_me, got_it, thanks, nice_one, well_played in order, and each preset has exactly the fields id, key, word, phases"] = function()
		PresetContract.idsAreIndicesAndKeysArePinned(presets(), context())
	end,

	["P-4: byId(id) is the same table as ALL[id] for 1..#ALL, and nil for 0, #ALL + 1, 1.5, -1 and a string"] = function()
		PresetContract.byIdReturnsTheEntryOrNil(presets(), context())
	end,

	["P-5: ALL, each preset and each phases list are frozen (table.isfrozen)"] = function()
		PresetContract.everyTableIsFrozen(presets(), context())
	end,
}
