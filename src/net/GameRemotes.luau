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

	TUNING IS READ THROUGH `@shared`. `architecture.md` section 1 forbids
	`net` -> `server`, and `MechanicsTuning` lives in `src/shared/`, so the
	bounds come from the constants rather than from literals that could drift.
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

return {
	Turn = Turn,
}
