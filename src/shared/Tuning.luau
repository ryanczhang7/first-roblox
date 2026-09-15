--!strict
--[[
	The session and round-timing constants, per ROUND-002.

	`docs/wiki/game/tuning.md` IS THE SPECIFICATION; this module is source. If a
	value here and a value there disagree, that is a defect to raise with the
	Lead PO rather than to fix by editing either side - and
	`tests/shared/tuning_spec_test.luau` is the guard that makes the rule
	enforceable: it parses §1 and §5 off disk and compares them to this table by
	name. That is why the keys are the specification's own snake_case names,
	verbatim. A translation table would be a second place for the two documents
	to disagree.

	SCOPE is `tuning.md` §1 (session and lobby) and §5 (round timing) only.
	§2-§4 and §6 - the instance, the signal channel, actuation and instability,
	difficulty bands - are M3 and land with the mechanics that read them, so that
	a placeholder is not frozen into source a year before anything uses it. §7
	records constants this design deliberately does not have; nothing here may
	reintroduce one.

	UNITS. Every `*_seconds` is seconds; `season_length_days` is days; `players_*`
	and `min_players_to_continue` are counts of seated players.

	`per_operation_seconds` is `(round_seconds - traversal_reserve_seconds) /
	procedure_length` in the specification. It is carried here as a SPECIFIED
	VALUE rather than computed, because `procedure_length` is an M3 constant that
	does not exist yet; when it arrives the relation becomes a test.

	AMENDMENT 12 IS CARRIED, NOT RESOLVED. `lobby_seconds` 60 + `round_seconds`
	480 = 540 exceeds `first_round_within_seconds` 480, so A5's day-1 promise is
	violated by the specification itself (product-brief §0c, amendment 12; also
	`tuning.md` §8, last row). That is an open operator decision. This module
	transcribes the specified values and a test fails if anybody "fixes" it here.

	FREEZING. `table.freeze` is applied to `session`, to `round` AND to the module
	table, so that no consumer can make a round's behaviour depend on load order.
	A frozen outer table with mutable children would satisfy nothing.
]]

export type SessionTuning = {
	players_min: number,
	players_max: number,
	min_players_to_continue: number,
	lobby_seconds: number,
	post_round_seconds: number,
	season_length_days: number,
}

export type RoundTuning = {
	round_seconds: number,
	round_seconds_min: number,
	round_seconds_max: number,
	per_operation_seconds: number,
	traversal_reserve_seconds: number,
	first_round_within_seconds: number,
	disconnect_grace_seconds: number,
}

export type Tuning = {
	session: SessionTuning,
	round: RoundTuning,
}

-- `tuning.md` §1. Session and lobby.
local session: SessionTuning = table.freeze({
	players_min = 4, -- derived: product-brief §0b amendment 1
	players_max = 6, -- derived: channel contention. Supersedes A4's cap of 16.
	min_players_to_continue = 3, -- derived: a 3-cycle ring is still a ring
	lobby_seconds = 60, -- taste: UX pacing, the Lead Designer owns it
	post_round_seconds = 45, -- placeholder: the post-round trace is four items of reading
	season_length_days = 28, -- derived: A2 #2 measures days 8-28
})

-- `tuning.md` §5. Round timing.
local round: RoundTuning = table.freeze({
	round_seconds = 480, -- placeholder: moves together with `procedure_length`
	round_seconds_min = 360, -- derived: A3 pillar 5
	round_seconds_max = 600, -- derived: A3 pillar 5
	per_operation_seconds = 45, -- derived: (round_seconds - traversal_reserve) / procedure_length
	traversal_reserve_seconds = 120, -- placeholder: a guess with no observation behind it
	first_round_within_seconds = 480, -- derived; conflicts with 60 + 480. Amendment 12, open.
	disconnect_grace_seconds = 30, -- placeholder: replace with observed reconnect times
})

local Tuning: Tuning = table.freeze({
	session = session,
	round = round,
})

return Tuning
