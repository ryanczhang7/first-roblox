--!strict
--[[
	HUD-007 AC-2 applied to the real `src/client/models/SeatCardModel.luau`.

	THE MODULE DOES NOT EXIST IN RED, so the require below fails and every
	test here FAILS naming the module that did not load. That is the right
	failure: it is the first thing AC-2 requires. The checks live in
	`tests/helpers/SeatHudContract.luau`, and every one of them has been
	OBSERVED to fire in `tests/client/seat_hud_controls_test.luau` against
	the model it exists to catch - above all the DIRECTION ERROR
	`src/server/seats/Ring.luau`'s header warns about: a model that reads
	`dependentId` as the helper. The fixture ring is 1001 -> 1002 -> 1003 ->
	1004 -> 1001 with viewer 1003, so supplier (seat 2), viewer (seat 3) and
	dependent (seat 4) all have different hue indices and a swap cannot pass
	by coincidence; a second viewer, 1001, has supplier 1004 and dependent
	1002.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    export type SeatViewLike = { playerId: string, keyClasses: { number }, lensClass: number,
	                                 supplierId: string, dependentId: string, seatOrder: { string } }
	    export type Person = { playerId: string, hueToken: string, glyph: string? }
	    export type Sample = { hueToken: string, glyph: string }
	    SeatCardModel.describe(seat: SeatViewLike)
	        -> { helper: Person, you: Person, partner: Person, samples: { Sample } }

	`SeatViewLike` is structural: the fixtures are plain tables with exactly
	`PublicSeatView`'s fields (`src/server/seats/Projection.luau`), and
	nothing here requires `src/server/`.

	Settled by components.md C-05, DN-4 and DN-9.
]]

local Contract = require("../helpers/SeatHudContract")

local MODEL = "src/client/models/SeatCardModel.luau"

local loaded, result = pcall(require, "@game/client/models/SeatCardModel")

local function bundle(): Contract.Bundle
	assert(loaded, `{MODEL} did not load: {tostring(result)}`)
	local model = result :: any
	assert(
		typeof(model) == "table" and typeof(model.describe) == "function",
		`{MODEL} must export describe as a function; it exports {typeof(model)}`
	)
	return { Lobby = nil, SeatCard = model, Relations = nil, Words = nil }
end

return {
	["AC-2 helper: the helper is supplierId (sigma^-1, the ring predecessor) with glyph.eye and the hue of its index in seatOrder - for viewer 1003 that is 1002 / color.player.2, for 1001 it is 1004 / color.player.4"] = function()
		Contract.seatHelperIsTheSupplierWithTheEye(bundle())
	end,

	["AC-2 partner: the partner is dependentId (sigma, the ring successor) with glyph.key and the hue of its index in seatOrder - for viewer 1003 that is 1004 / color.player.4, for 1001 it is 1002 / color.player.2"] = function()
		Contract.seatPartnerIsTheDependentWithTheKey(bundle())
	end,

	["AC-2 you: you is the viewer with the hue of its own index and glyph nil (DN-4); every returned table is fresh and the seat view is untouched"] = function()
		Contract.seatYouHasYourHueAndNoGlyph(bundle())
	end,

	["AC-2 samples (DN-9): exactly two, yours (viewer's hue + glyph.key) then the partner's (dependentId's hue + glyph.eye), hues computed from the seat and not read back from the people"] = function()
		Contract.seatSamplesAreYoursWithKeyThenPartnersWithEye(bundle())
	end,

	["AC-2: a playerId absent from seatOrder (supplier 1002 missing) raises naming 1002 rather than returning a hue"] = function()
		Contract.seatUnknownIdRaisesNamingIt(bundle())
	end,
}
