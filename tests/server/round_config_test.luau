--!strict
--[[
	ROUND-003's `src/server/round/RoundConfig.luau`: the durations and thresholds
	the phase machine is INJECTED with.

	Two different properties live here and they are tested separately on purpose.

	  1. THE MAPPING. `fromTuning` renames `ROUND-002`'s specification keys
	     (`lobby_seconds`) to the Contract's field names (`lobbySeconds`). The
	     values are SETTLED - `docs/wiki/game/tuning.md` is the specification,
	     `src/shared/Tuning.luau` transcribes it and `tests/shared/tuning_spec_test.luau`
	     guards the transcription. So this file READS THE NUMBERS OUT of `Tuning`
	     and never writes one down: a literal 60 here would be a third place for
	     the same constant to live and a quiet chance to re-tune a value a design
	     decision already fixed.

	  2. THE INJECTION. `fromTuning` must use the tuning table it is HANDED. The
	     second test passes a structural duplicate of `Tuning` carrying values
	     that appear nowhere in the real one, which is the only way to tell a
	     mapping from a module that reads the global `Tuning` and ignores its
	     argument.

	`Tuning` and its sub-tables are `table.freeze`d, so the fake below is built
	fresh rather than cloned-and-edited.
]]

local Deep = require("../helpers/Deep")
local Tuning = require("../../src/shared/Tuning")

local loaded, loadResult = pcall(require, "../../src/server/round/RoundConfig")

local function RoundConfig(): any
	assert(loaded, `src/server/round/RoundConfig.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- The Contract's six fields, and the `Tuning` key each one is taken from.
local MAPPING = {
	{ field = "lobbySeconds", section = "session", key = "lobby_seconds" },
	{ field = "postRoundSeconds", section = "session", key = "post_round_seconds" },
	{ field = "roundSeconds", section = "round", key = "round_seconds" },
	{ field = "playersMin", section = "session", key = "players_min" },
	{ field = "playersMax", section = "session", key = "players_max" },
	{ field = "minPlayersToContinue", section = "session", key = "min_players_to_continue" },
}

--[[
	A structural duplicate of `Tuning` with values that appear nowhere in the
	real one. Every number the mapping reads is distinct from every other, so a
	`fromTuning` that swaps two fields fails as loudly as one that ignores its
	argument.
]]
local FAKE = {
	session = {
		players_min = 11,
		players_max = 12,
		min_players_to_continue = 13,
		lobby_seconds = 14,
		post_round_seconds = 15,
		season_length_days = 16,
	},
	round = {
		round_seconds = 17,
		round_seconds_min = 18,
		round_seconds_max = 19,
		per_operation_seconds = 20,
		traversal_reserve_seconds = 21,
		first_round_within_seconds = 22,
		disconnect_grace_seconds = 23,
	},
}

local function sortedKeys(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [string]: any }) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return {
	["Contract: RoundConfig exports fromTuning as a plain field function"] = function()
		local module = RoundConfig()
		assert(
			typeof(module.fromTuning) == "function",
			`RoundConfig.fromTuning is {typeof(module.fromTuning)}, wanted a function`
		)
	end,

	["Contract: fromTuning returns exactly the six fields the Contract names, all numbers"] = function()
		local config = RoundConfig().fromTuning(Tuning)
		local expected = {
			"lobbySeconds",
			"minPlayersToContinue",
			"playersMax",
			"playersMin",
			"postRoundSeconds",
			"roundSeconds",
		}
		assert(
			Deep.equal(sortedKeys(config), expected),
			`fromTuning returned the fields {Deep.show(sortedKeys(config))}, wanted `
				.. `{Deep.show(expected)}`
		)
		for _, entry in MAPPING do
			assert(
				typeof(config[entry.field]) == "number",
				`{entry.field} is {typeof(config[entry.field])}, wanted a number`
			)
		end
	end,

	--[[
		The mapping, read out of `Tuning` rather than written down. `ROUND-002`
		owns whether `Tuning` matches `tuning.md`; this owns only the rename.
	]]
	["Contract: fromTuning maps each field to its specified Tuning constant"] = function()
		local config = RoundConfig().fromTuning(Tuning)
		local wrong: { string } = {}

		for _, entry in MAPPING do
			local specified = (Tuning :: any)[entry.section][entry.key]
			if config[entry.field] ~= specified then
				table.insert(
					wrong,
					`{entry.field} is {tostring(config[entry.field])}, wanted `
						.. `Tuning.{entry.section}.{entry.key} = {tostring(specified)}`
				)
			end
		end

		assert(
			#wrong == 0,
			`{#wrong} of {#MAPPING} fields do not carry their specified constant:\n`
				.. table.concat(wrong, "\n")
		)
	end,

	--[[
		The injection. Without this, a `fromTuning` that ignores its argument and
		requires `Tuning` itself passes every assertion above forever, and the
		design property the whole story rests on - a config a test can shrink to
		three seconds - is untested.
	]]
	["Contract: fromTuning reads the tuning table it was handed, not the Tuning module"] = function()
		local config = RoundConfig().fromTuning(FAKE)
		local wrong: { string } = {}

		for _, entry in MAPPING do
			local supplied = (FAKE :: any)[entry.section][entry.key]
			if config[entry.field] ~= supplied then
				table.insert(
					wrong,
					`{entry.field} is {tostring(config[entry.field])}, wanted the supplied `
						.. `{entry.section}.{entry.key} = {tostring(supplied)}`
				)
			end
		end

		assert(
			#wrong == 0,
			`fromTuning ignored {#wrong} of {#MAPPING} values in the table it was given:\n`
				.. table.concat(wrong, "\n")
		)
	end,

	--[[
		The two halves of the story agree on the field names. The phase machine's
		tests hand it a hand-written config; if `fromTuning` produced
		`lobby_seconds` while the machine read `lobbySeconds`, both suites would
		pass and the driver would get a machine that never leaves the lobby.
	]]
	["Contract: a config from fromTuning has the same shape the phase machine is driven with"] = function()
		local config = RoundConfig().fromTuning(Tuning)
		local fixture = {
			lobbySeconds = 3,
			postRoundSeconds = 2,
			roundSeconds = 20,
			playersMin = 4,
			playersMax = 6,
			minPlayersToContinue = 3,
		}
		assert(
			Deep.equal(sortedKeys(config), sortedKeys(fixture)),
			`fromTuning produces {Deep.show(sortedKeys(config))} but the phase machine's tests `
				.. `drive it with {Deep.show(sortedKeys(fixture))}`
		)
	end,
}
