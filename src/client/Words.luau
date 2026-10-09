--!strict
--[[
	SLICE-004: the player-facing words the client draws, as data.

	`docs/wiki/design/voice.md` IS THE SPECIFICATION. `phase` is §2.1's table,
	internal phase name -> player-facing word, verbatim; the provisional label
	is the phase's own name (operator decision, 2026-10-08).
	`tests/client/phase_clock_model_test.luau` reads §2.1 off disk and compares
	it with this table row for row, in both directions, so a word changed here
	alone fails. Change the document first, through the Lead Designer.
]]

local phase: { [string]: string } = table.freeze({
	Lobby = "Lobby",
	Assignment = "Assignment",
	Round = "Round",
	Resolution = "Resolution",
	Post = "Post",
})

return table.freeze({
	phase = phase,
})
