--!strict
--[[
	HUD-007 AC-1: what the lobby panel (C-26) shows, as a pure function of the
	public `RoundView`'s `players` and the session's size limits.

	    slots  playersMax of them; the first playersMin are `needed` (drawn
	           with a solid border), the rest optional (dashed). Slot i holds
	           players[i], in join order, with hue `color.player.{i}` - the
	           hue that player keeps into the round (tokens.md §1.2). An empty
	           slot has neither id nor hue. Slots carry no glyph (DN-2).
	    state  "waiting" below playersMin (the countdown HOLDS,
	           `architecture.md` §3), "counting" from playersMin, "full" at
	           playersMax.
	    glyph  one per state, pairwise distinct (DN-1): waiting glyph.wait,
	           counting glyph.notyet, full glyph.done.

	There is no ready toggle. `view.phase` is not read: the client entry
	decides when the panel shows. PURE; every returned table is fresh. No
	words: the view draws `Words.lobby`.
]]

export type View = { players: { string } }
export type LobbyState = "waiting" | "counting" | "full"
export type Slot = { playerId: string?, needed: boolean, hueToken: string? }
export type Description = { state: LobbyState, glyph: string, slots: { Slot } }

local GLYPH: { [LobbyState]: string } = table.freeze({
	waiting = "glyph.wait",
	counting = "glyph.notyet",
	full = "glyph.done",
})

local function describe(view: View, playersMin: number, playersMax: number): Description
	local players = view.players
	local slots: { Slot } = {}
	for i = 1, playersMax do
		local playerId = players[i]
		slots[i] = {
			playerId = playerId,
			needed = i <= playersMin,
			hueToken = if playerId ~= nil then `color.player.{i}` else nil,
		}
	end
	local state: LobbyState = if #players >= playersMax
		then "full"
		elseif #players >= playersMin then "counting"
		else "waiting"
	return { state = state, glyph = GLYPH[state], slots = slots }
end

return table.freeze({
	describe = describe,
})
