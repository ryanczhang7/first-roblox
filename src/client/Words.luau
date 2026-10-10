--!strict
--[[
	SLICE-004: the player-facing words the client draws, as data.

	`docs/wiki/design/voice.md` IS THE SPECIFICATION. `phase` is §2.1's table,
	internal phase name -> player-facing word, verbatim; the provisional label
	is the phase's own name (operator decision, 2026-10-08).
	`tests/client/phase_clock_model_test.luau` reads §2.1 off disk and compares
	it with this table row for row, in both directions, so a word changed here
	alone fails. Change the document first, through the Lead Designer.

	HUD-007 adds `seat` (C-05, the seat card) and `lobby` (C-26, the lobby
	panel): §2's optional words, verbatim. They are read by the VIEWS only;
	no model returns a word. `tests/client/seat_hud_outputs_test.luau` reads
	§2 off disk and compares both tables with it, keys and order included.
]]

local phase: { [string]: string } = table.freeze({
	Lobby = "Lobby",
	Assignment = "Assignment",
	Round = "Round",
	Resolution = "Resolution",
	Post = "Post",
})

-- voice.md §2, "Seat card (C-05):", in the document's order.
local seat = table.freeze({
	helper = "Your helper",
	you = "You",
	partner = "You help",
	yours = "Yours to turn",
	theirs = "You can see these",
})

-- voice.md §2, "Lobby (C-26):".
local lobby = table.freeze({
	alone = "Waiting for friends",
})

return table.freeze({
	phase = phase,
	seat = seat,
	lobby = lobby,
})
