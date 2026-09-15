--!strict
--[[
	The durations and thresholds the phase machine is INJECTED with, per
	ROUND-003 and `docs/wiki/architecture.md` section 3.

	This module does exactly one thing: it RENAMES `ROUND-002`'s specification
	keys (`lobby_seconds`) to the Contract's field names (`lobbySeconds`). It
	chooses no value and it computes none - `docs/wiki/game/tuning.md` is the
	specification, `src/shared/Tuning.luau` transcribes it, and
	`tests/shared/tuning_spec_test.luau` guards the transcription. A literal 60
	here would be a third place for the same constant to live.

	`fromTuning` READS THE TABLE IT IS HANDED. It never reaches for the `Tuning`
	module behind its argument's back, and that is the whole point of the
	injection: a test hands the machine a three-second lobby and runs a complete
	lifecycle in simulated seconds instead of nine real minutes. The `Tuning`
	require below supplies the argument's TYPE and nothing else; no value in this
	module is read from it.

	It does NOT require the phase machine. The dependency runs one way: the
	machine is handed a config, the config knows nothing about the machine.
]]

local Tuning = require("@shared/Tuning")

local RoundConfig = {}

export type RoundConfig = {
	lobbySeconds: number,
	postRoundSeconds: number,
	roundSeconds: number,
	playersMin: number,
	playersMax: number,
	minPlayersToContinue: number,
}

--[[
	The six fields, each from its specified constant.

	The parameter is typed STRUCTURALLY - Luau matches shape, not identity - so
	any table carrying `session` and `round` in the specified shape is a legal
	argument. That is what lets a test pass a duplicate of `Tuning` with values
	found nowhere in the real one and tell a mapping apart from a module that
	ignores its argument.
]]
function RoundConfig.fromTuning(tuning: Tuning.Tuning): RoundConfig
	return {
		lobbySeconds = tuning.session.lobby_seconds,
		postRoundSeconds = tuning.session.post_round_seconds,
		roundSeconds = tuning.round.round_seconds,
		playersMin = tuning.session.players_min,
		playersMax = tuning.session.players_max,
		minPlayersToContinue = tuning.session.min_players_to_continue,
	}
end

return RoundConfig
