--!strict
--[[
	HUD-007 AC-1 applied to the real `src/client/models/LobbyModel.luau`.

	THE MODULE DOES NOT EXIST IN RED, so the require below fails and every
	test here FAILS naming the module that did not load. That is the right
	failure: it is the first thing AC-1 requires. The checks live in
	`tests/helpers/SeatHudContract.luau`, and every one of them has been
	OBSERVED to fire in `tests/client/seat_hud_controls_test.luau` against
	the model it exists to catch - `>` for `>=` at playersMin, full never
	reported, slots counted from the players, a zero-indexed hue, a glyph on
	a slot, a hue on a slot's text, the phase read, the view mutated.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    LobbyModel.describe(view: { players: { string } }, playersMin: number, playersMax: number)
	        -> { state: "waiting" | "counting" | "full", glyph: string,
	             slots: { { playerId: string?, needed: boolean, hueToken: string? } } }

	Settled by components.md C-26 and DN-1 / DN-2; each test is named after
	the state it pins.
]]

local Contract = require("../helpers/SeatHudContract")

local MODEL = "src/client/models/LobbyModel.luau"

local loaded, result = pcall(require, "@game/client/models/LobbyModel")

local function bundle(): Contract.Bundle
	assert(loaded, `{MODEL} did not load: {tostring(result)}`)
	local model = result :: any
	assert(
		typeof(model) == "table" and typeof(model.describe) == "function",
		`{MODEL} must export describe as a function; it exports {typeof(model)}`
	)
	return { Lobby = model, SeatCard = nil, Relations = nil, Words = nil }
end

return {
	["AC-1 slots: playersMax slots, the first playersMin needed, filled in players order with color.player.{i} (a Theme.color key), nil past #players, no glyph on a slot (DN-2), fresh tables, the view untouched and its phase unread"] = function()
		Contract.lobbySlotsAreMaxLongNeededToMinAndHuedByIndex(bundle())
	end,

	["AC-1 waiting: below playersMin (nobody, one alone, playersMin - 1) the state is waiting with glyph.wait - the countdown holds"] = function()
		Contract.lobbyWaitingBelowMin(bundle())
	end,

	["AC-1 counting: at exactly playersMin and up to playersMax - 1 the state is counting with glyph.notyet"] = function()
		Contract.lobbyCountingAtMin(bundle())
	end,

	["AC-1 full: at playersMax the state is full with glyph.done, also when playersMin == playersMax"] = function()
		Contract.lobbyFullAtMax(bundle())
	end,
}
