--!strict
--[[
	HUD-007 AC-4 (mechanical) and the Words block, applied to the real
	`src/client/models/{LobbyModel,SeatCardModel,RelationsModel}.luau` and
	`src/client/Words.luau`.

	IN RED THE THREE MODELS DO NOT EXIST, so the AC-4 test FAILS naming the
	first module that did not load. `Words.luau` exists (SLICE-004) but has
	no `seat` and no `lobby` table yet, so the two Words tests FAIL on
	`Words.seat is nil, wanted a table`. Both are the right failure.

	AC-4 walks EVERY output the AC-1 to AC-3 checks build (22 of them: 14
	lobby states, 2 seat cards, 7 relations strips - `SeatHudContract.everyOutput`)
	and asserts, mechanically:
	  * every string matching `^color%.player%.` sits under the key `hueToken` (DN-3);
	  * every LobbyModel output has a non-nil glyph (DN-1);
	  * every non-nil Chip and every Person other than `you` has a non-nil glyph (PT-A7);
	  * `you.glyph` is nil in C-05 and C-04 (DN-4);
	  * every glyph and overlay value is a member of `Theme.icons.system`.
	The walker's own discrimination - a hue under `textColour`, a nil glyph
	on a chip, `you` carrying a glyph, a glyph outside the Theme - is pinned
	in `tests/client/seat_hud_controls_test.luau` over hand-built outputs.

	THE WORDS are settled by `docs/wiki/design/voice.md` §2's optional-words
	paragraph, read off disk through `VoiceSpec.parseQuotedWords` (the way
	`Words.phase` is read through `parsePhaseTable`); no word is restated
	here. Which KEY each quoted word belongs to is the Contract's:
	`seat = { helper, you, partner, yours, theirs }` in the paragraph's
	order, `lobby = { alone }`. Both tables are frozen.

	    Words.seat:  { helper: string, you: string, partner: string, yours: string, theirs: string }
	    Words.lobby: { alone: string }
]]

local Contract = require("../helpers/SeatHudContract")

local MODULES = {
	Lobby = "src/client/models/LobbyModel.luau",
	SeatCard = "src/client/models/SeatCardModel.luau",
	Relations = "src/client/models/RelationsModel.luau",
}

local lobbyLoaded, lobbyResult = pcall(require, "@game/client/models/LobbyModel")
local seatLoaded, seatResult = pcall(require, "@game/client/models/SeatCardModel")
local relationsLoaded, relationsResult = pcall(require, "@game/client/models/RelationsModel")
local wordsLoaded, wordsResult = pcall(require, "@game/client/Words")

local WORDS = "src/client/Words.luau"

local function models(): Contract.Bundle
	assert(lobbyLoaded, `{MODULES.Lobby} did not load: {tostring(lobbyResult)}`)
	assert(seatLoaded, `{MODULES.SeatCard} did not load: {tostring(seatResult)}`)
	assert(relationsLoaded, `{MODULES.Relations} did not load: {tostring(relationsResult)}`)
	return { Lobby = lobbyResult, SeatCard = seatResult, Relations = relationsResult, Words = nil }
end

local function words(): Contract.Bundle
	assert(wordsLoaded, `{WORDS} did not load: {tostring(wordsResult)}`)
	return { Lobby = nil, SeatCard = nil, Relations = nil, Words = wordsResult }
end

return {
	["AC-4: over every lobby, seat-card and relations output the AC-1..AC-3 tests build, a color.player.* value appears only under hueToken, every state and every non-you person or chip has a glyph from Theme.icons.system, and you.glyph is nil"] = function()
		Contract.everyOutputWalksClean(models())
	end,

	["Words.seat is exactly voice.md §2's five seat-card words, read from the file, under helper / you / partner / yours / theirs in that order, and frozen"] = function()
		Contract.wordsSeatMatchVoice(words())
	end,

	["Words.lobby is exactly voice.md §2's one lobby word, read from the file, under alone, and frozen"] = function()
		Contract.wordsLobbyMatchVoice(words())
	end,
}
