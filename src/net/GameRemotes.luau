--!strict
--[[
	PROC-005: this game's remote declarations. Pure data: requiring the module
	calls `Remotes.define` once per declaration and returns the definitions by
	name. Lune and Roblox both cache a require, so each name is declared once
	per process, and nothing may declare a name here a second time.

	`Turn` (B4, `mechanics.md` §5 G12, `tuning.md` §4). A client's claim to
	turn one machine's dial to one setting. The machine and setting are CLAIMS:
	the schema bounds them to what the facility can hold, and the server judges
	reach against its own accepted positions (`architecture.md` §9.8), which is
	why the schema has no field for a position. Legal only in `Round`, and
	limited to one call per `turn_rate_limit_seconds`; a call refused for rate
	never reaches the Procedure and costs nothing.

	`Ping` (CHAN-005, B4, `mechanics.md` §4.1 G9, `tuning.md` §3). A client's
	claim to point at one dial setting, one machine or one doorway. Like
	`Turn`, the target is a CLAIM and the schema has no field for a position:
	`target` is bounded by `actuator_count` (a 3 x 3 grid has at most 12
	doorways, so every doorway id is inside it too) and `setting` by
	`dial_settings`; whether the target exists, is in range of the server's
	accepted position and is in sight is `server/channel/Pings`' to judge.
	Legal only in `Round`. Two limits (CHAN-003): one SEND per
	`ping_rate_limit_seconds` - the stricter reading of CA-1 - and one ATTEMPT
	per `channel_attempt_min_interval_seconds`. A ping refused for its target
	declines the call, so it costs the attempt floor and not the send limit.

	`SendPreset` (CHAN-004, B4, `mechanics.md` §4.2 C4/C9, `tuning.md` §3). A
	client's request to broadcast one preset from the wheel. The payload is the
	preset's id and nothing else: `preset` is bounded by `preset_count`, and
	`Schema.shape` refuses any other key, so the wire cannot carry a recipient
	(C9) or a position - the sender's position is the server's accepted sample.
	`legalPhases` is the union of `Presets.ALL[*].phases` in phase-machine
	order; whether THIS preset is legal now is `server/channel/PresetSends`'
	to judge, and a preset refused for its own phases or by the filter declines
	the call. One SEND per `preset_rate_limit_seconds` across the whole wheel -
	one limiter, not one per preset (C4) - and one ATTEMPT per
	`channel_attempt_min_interval_seconds`.

	TUNING IS READ THROUGH `@shared`. `architecture.md` section 1 forbids
	`net` -> `server`, and `MechanicsTuning` lives in `src/shared/`, so the
	bounds and the limits come from the constants rather than from literals
	that could drift.
]]

local MechanicsTuning = require("@shared/MechanicsTuning")
local Remotes = require("./Remotes")
local Schema = require("./Schema")

local Turn = Remotes.define("Turn", {
	args = Schema.shape({
		machine = Schema.integer(1, MechanicsTuning.instance.actuator_count),
		setting = Schema.integer(1, MechanicsTuning.instance.dial_settings),
	}),
	legalPhases = { "Round" },
	rateLimit = { minIntervalSeconds = MechanicsTuning.actuation.turn_rate_limit_seconds },
})

local Ping = Remotes.define("Ping", {
	args = Schema.shape({
		kind = Schema.literal("setting", "machine", "doorway"),
		target = Schema.integer(1, MechanicsTuning.instance.actuator_count),
		setting = Schema.optional(Schema.integer(1, MechanicsTuning.instance.dial_settings)),
	}),
	legalPhases = { "Round" },
	rateLimit = { minIntervalSeconds = MechanicsTuning.channel.ping_rate_limit_seconds },
	attemptLimit = {
		minIntervalSeconds = MechanicsTuning.channel.channel_attempt_min_interval_seconds,
	},
})

local SendPreset = Remotes.define("SendPreset", {
	args = Schema.shape({
		preset = Schema.integer(1, MechanicsTuning.channel.preset_count),
	}),
	-- The union of `Presets.ALL[*].phases` in phase-machine order (C-2). The
	-- test derives it from the table, so a preset row changed alone re-reds.
	legalPhases = { "Lobby", "Round", "Post" },
	rateLimit = { minIntervalSeconds = MechanicsTuning.channel.preset_rate_limit_seconds },
	attemptLimit = {
		minIntervalSeconds = MechanicsTuning.channel.channel_attempt_min_interval_seconds,
	},
})

return {
	Turn = Turn,
	Ping = Ping,
	SendPreset = SendPreset,
}
