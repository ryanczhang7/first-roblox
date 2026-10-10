--!strict
--[[
	HUD-007 AC-2: what the seat card (C-05) shows, as a pure function of the
	private `SeatView` the server sends this player at the deal.

	    helper   seat.supplierId  - sigma^-1(p), WHO TELLS ME - glyph.eye
	    you      seat.playerId                               - no glyph (DN-4)
	    partner  seat.dependentId - sigma(p),    WHO I TELL   - glyph.key
	    samples  { your hue + glyph.key, the partner's hue + glyph.eye } (DN-9):
	             the machines yours to turn, and the lens-class machines you
	             can see, which are trimmed in the partner's hue (tokens.md §1.3).

	THE DIRECTION IS THE DEFECT TO FEAR. `Ring.luau`'s header warns that
	supplier and dependent are easy to swap, and a swap here would tell every
	player the opposite of the truth while looking entirely plausible.

	Hues: `color.player.{i}` for the id's 1-based index in `seat.seatOrder`
	(tokens.md §1.2). At deal time the current view IS the dealt view, so its
	own `seatOrder` is the dealt one (PO-2). An id not in the order raises,
	naming it: a hue guessed for a stranger would be somebody else's colour.

	`SeatViewLike` is the structural shape SLICE-003 pins, declared here
	because the client cannot require `src/server/` (`architecture.md` §1).
	`RelationsModel` re-uses it, and `hueFor`.

	PURE: no Instances, no services; the seat is never mutated and every
	returned table is fresh. No words: the view draws `Words.seat`.
]]

local Theme = require("../Theme")

export type SeatViewLike = {
	playerId: string,
	keyClasses: { number },
	lensClass: number,
	supplierId: string,
	dependentId: string,
	seatOrder: { string },
}

export type Person = { playerId: string, hueToken: string, glyph: string? }
export type Sample = { hueToken: string, glyph: string }
export type Description = {
	helper: Person,
	you: Person,
	partner: Person,
	samples: { Sample },
}

-- The hue token for `playerId`'s seat in `seatOrder`. Raises, naming the id
-- and the caller, when the id has no seat or its seat is past the palette.
local function hueFor(seatOrder: { string }, playerId: string, caller: string): string
	local index = table.find(seatOrder, playerId)
	if index == nil then
		error(`{caller}: player {tostring(playerId)} is not in seatOrder, so it has no hue`, 3)
	end
	local token = `color.player.{index}`
	if Theme.color[token] == nil then
		error(`{caller}: player {playerId} sits at index {index}, past the palette ({token})`, 3)
	end
	return token
end

local function describe(seat: SeatViewLike): Description
	local caller = "SeatCardModel.describe"
	local order = seat.seatOrder
	local helperHue = hueFor(order, seat.supplierId, caller)
	local youHue = hueFor(order, seat.playerId, caller)
	local partnerHue = hueFor(order, seat.dependentId, caller)
	return {
		helper = { playerId = seat.supplierId, hueToken = helperHue, glyph = "glyph.eye" },
		you = { playerId = seat.playerId, hueToken = youHue },
		partner = { playerId = seat.dependentId, hueToken = partnerHue, glyph = "glyph.key" },
		samples = {
			{ hueToken = youHue, glyph = "glyph.key" },
			{ hueToken = partnerHue, glyph = "glyph.eye" },
		},
	}
end

return table.freeze({
	describe = describe,
	hueFor = hueFor,
})
