--!strict
--[[
	HUD-007 AC-3: what the relations strip (C-04) shows all round, as a pure
	function of the current `SeatView`, a presence map, and the DEALT seat
	view - the first `SeatView` this client received after leaving `Lobby`.

	WHY THE DEALT VIEW (PO-1). When a helper is withdrawn the ring closes: the
	dependent's new `supplierId` is the leaver's own supplier, whose lens reads
	the class it inherited, not yours (`mechanics.md` §8). No single SeatView
	can therefore say "no helper"; a change against the deal can.

	    helper   none iff seat.supplierId ~= dealt.supplierId:
	             { glyph.eye, struck, state "none" }, no id, no hue (DN-5)
	    partner  nil iff seat.dependentId ~= dealt.dependentId (DN-6)
	    else     { id, hue, relation glyph, state = presence[id] or "loading",
	               not struck, overlay glyph.wait iff away (DN-7, DN-8) }
	    you      always present, no glyph (DN-4)

	Hues come from `dealt.seatOrder` (PO-2): a withdrawal shortens the current
	order and shifts every later index, and a hue is stable for the round
	(tokens.md §1.2). An id not in the dealt order raises, naming it.

	PURE: no Instances, no services, inputs never mutated, every table fresh.
]]

local SeatCardModel = require("./SeatCardModel")

export type SeatViewLike = SeatCardModel.SeatViewLike
export type ChipState = "present" | "loading" | "error" | "away" | "none"
export type FetchState = "present" | "loading" | "error" | "away"
export type Presence = { [string]: FetchState }
export type Chip = {
	playerId: string?,
	hueToken: string?,
	glyph: string?,
	state: ChipState,
	struck: boolean,
	overlay: string?,
}
export type Description = { helper: Chip, you: Chip, partner: Chip? }

local CALLER = "RelationsModel.describe"

local function relation(
	playerId: string,
	glyph: string,
	presence: Presence,
	dealt: SeatViewLike
): Chip
	local state: ChipState = presence[playerId] or "loading"
	return {
		playerId = playerId,
		hueToken = SeatCardModel.hueFor(dealt.seatOrder, playerId, CALLER),
		glyph = glyph,
		state = state,
		struck = false,
		overlay = if state == "away" then "glyph.wait" else nil,
	}
end

local function describe(seat: SeatViewLike, presence: Presence, dealt: SeatViewLike): Description
	local helper: Chip
	if seat.supplierId ~= dealt.supplierId then
		helper = { glyph = "glyph.eye", state = "none", struck = true }
	else
		helper = relation(seat.supplierId, "glyph.eye", presence, dealt)
	end
	local partner: Chip? = nil
	if seat.dependentId == dealt.dependentId then
		partner = relation(seat.dependentId, "glyph.key", presence, dealt)
	end
	return {
		helper = helper,
		you = {
			playerId = seat.playerId,
			hueToken = SeatCardModel.hueFor(dealt.seatOrder, seat.playerId, CALLER),
			state = "present",
			struck = false,
		},
		partner = partner,
	}
end

return table.freeze({
	describe = describe,
})
