--!strict
--[[
	CHAN-002: the preset wheel, as frozen data.

	`docs/wiki/game/mechanics.md` §4.2 IS THE SPECIFICATION; this module is
	source. The words are the operator's (T12) and are taste; the count and
	the rules (§4.3, C1-C9) are not. `tests/shared/presets_test.luau` parses
	§4.2 off disk and compares it to `ALL` row for row - word, order and
	phases - so a preset changed here alone fails, naming it. Change the
	document first, and through the Lead PO.

	SHARED BY BOTH SIDES. The server validates a send against this table and
	the client draws the wheel from it, so every level is frozen (`ALL`, each
	preset, each phases list): a client that could rewrite the wheel could
	rewrite what the server checks.

	`id` IS THE POSITION IN `ALL` and the wire value; `key` is a stable ascii
	name for code and for the client's `Theme`, which owns the icon. There is
	no icon field here on purpose: presentation lives in `docs/wiki/design/`.

	`phases` IS `{ string }`, NOT A PHASE UNION. `src/shared/` cannot import
	`src/net/` (`architecture.md` §1), and a third textual copy of the union is
	what `phase_union_guard_test` exists to prevent. The test checks each name
	against the set it reads out of `Remotes.luau` instead.

	`byId` IS `ALL[id]`, guarded only by type. No `tonumber`, no flooring: a
	wire value of `1.5` or `"1"` is not an id, and coercing it would let a
	malformed send select a preset nobody chose.
]]

export type Preset = {
	id: number,
	key: string,
	word: string,
	phases: { string },
}

local function preset(id: number, key: string, word: string, phases: { string }): Preset
	return table.freeze({
		id = id,
		key = key,
		word = word,
		phases = table.freeze(phases),
	})
end

-- mechanics.md §4.2, in document order; phases in the order the table lists them.
local ALL: { Preset } = table.freeze({
	preset(1, "ready", "Ready", { "Round", "Lobby" }),
	preset(2, "wait", "Wait", { "Round" }),
	preset(3, "go", "Go", { "Round" }),
	preset(4, "help", "Help", { "Round" }),
	preset(5, "on_my_way", "On my way", { "Round" }),
	preset(6, "follow_me", "Follow me", { "Round" }),
	preset(7, "got_it", "Got it", { "Round" }),
	preset(8, "thanks", "Thanks", { "Round", "Post" }),
	preset(9, "nice_one", "Nice one", { "Round", "Post" }),
	preset(10, "well_played", "Well played", { "Post" }),
})

local function byId(id: any): Preset?
	if type(id) ~= "number" then
		return nil
	end
	return ALL[id]
end

return table.freeze({
	ALL = ALL,
	byId = byId,
})
