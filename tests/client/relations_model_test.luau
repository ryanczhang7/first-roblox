--!strict
--[[
	HUD-007 AC-3 applied to the real `src/client/models/RelationsModel.luau`.

	THE MODULE DOES NOT EXIST IN RED, so the require below fails and every
	test here FAILS naming the module that did not load. That is the right
	failure: it is the first thing AC-3 requires. The checks live in
	`tests/helpers/SeatHudContract.luau`, and every one of them has been
	OBSERVED to fire in `tests/client/seat_hud_controls_test.luau` against
	the model it exists to catch - the seat compared to itself instead of
	the dealt view (PO-1), hues from the current seatOrder (PO-2), a missing
	presence entry read as present, an away chip losing its relation glyph
	or its overlay, a none helper keeping an id or not struck, partner none
	as a chip, you's state read from the map.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    export type ChipState = "present" | "loading" | "error" | "away" | "none"
	    export type Chip = { playerId: string?, hueToken: string?, glyph: string?,
	                         state: ChipState, struck: boolean, overlay: string? }
	    RelationsModel.describe(seat: SeatViewLike, presence: { [string]: "present" | "loading" | "error" | "away" },
	                            dealt: SeatViewLike)
	        -> { helper: Chip, you: Chip, partner: Chip? }

	THE "HELPER LEFT" FIXTURE is built faithfully to `Ring.withdraw`: ring
	1001 -> 1002 -> 1003 -> 1004 -> 1001, viewer 1003 dealt { supplier 1002,
	dependent 1004 }. After 1002 withdraws, 1003's current view is
	{ supplier 1001, dependent 1004 } and seatOrder is { 1001, 1003, 1004 }:
	no single SeatView says "no helper" (PO-1), and every current seat index
	has shifted (PO-2).

	Settled by components.md C-04's state table, DN-5..DN-8, PO-1 and PO-2.
]]

local Contract = require("../helpers/SeatHudContract")

local MODEL = "src/client/models/RelationsModel.luau"

local loaded, result = pcall(require, "@game/client/models/RelationsModel")

local function bundle(): Contract.Bundle
	assert(loaded, `{MODEL} did not load: {tostring(result)}`)
	local model = result :: any
	assert(
		typeof(model) == "table" and typeof(model.describe) == "function",
		`{MODEL} must export describe as a function; it exports {typeof(model)}`
	)
	return { Lobby = nil, SeatCard = nil, Relations = model, Words = nil }
end

return {
	["AC-3 present: both relations present give helper { 1002, color.player.2, glyph.eye } and partner { 1004, color.player.4, glyph.key }, state present, struck false, overlay nil; you { 1003, color.player.3, glyph nil, present }"] = function()
		Contract.relationsPresent(bundle())
	end,

	["AC-3 loading: a relation listed as loading, or absent from the presence map (an empty map too), is loading with its glyph kept (DN-8); you stays present"] = function()
		Contract.relationsLoadingWhenFetchingOrUnlisted(bundle())
	end,

	["AC-3 error: a failed headshot fetch is error with the glyph kept, struck false, overlay nil - the state field alone distinguishes it from loading (DN-8)"] = function()
		Contract.relationsErrorKeepsTheGlyph(bundle())
	end,

	["AC-3 away: an away relation keeps its glyph (eye / key) and carries overlay glyph.wait; a present one beside it carries no overlay (DN-7)"] = function()
		Contract.relationsAwayOverlaysWaitAndKeepsTheRelationGlyph(bundle())
	end,

	["AC-3 helper none (PO-1, DN-5): after helper 1002 left and 1001 closed the ring, the helper chip is { glyph.eye, none, struck true } with no playerId and no hueToken, while you and the partner keep their DEALT hues 3 and 4"] = function()
		Contract.relationsHelperNoneAfterTheHelperLeft(bundle())
	end,

	["AC-3 partner none (PO-1, DN-6): after partner 1004 left and 1003 now feeds 1001, partner is nil and the helper chip is unchanged"] = function()
		Contract.relationsPartnerNilAfterThePartnerLeft(bundle())
	end,

	["AC-3 dealt hues (PO-2): after bystander 1001 left and every current seat index shifted, helper / you / partner are still color.player.2 / 3 / 4 from the dealt seatOrder"] = function()
		Contract.relationsHuesComeFromTheDealtSeatOrder(bundle())
	end,

	["AC-3 you: state present whatever the map says of the viewer, glyph nil (DN-4), overlay nil; every returned table is fresh and no input is mutated"] = function()
		Contract.relationsYouIsAlwaysPresentWithNoGlyph(bundle())
	end,

	["AC-3: a playerId absent from dealt.seatOrder (the viewer 1003, or the partner 1004) raises naming it rather than returning a hue"] = function()
		Contract.relationsUnknownIdRaisesNamingIt(bundle())
	end,
}
