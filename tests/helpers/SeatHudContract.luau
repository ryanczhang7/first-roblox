--!strict
--[[
	HUD-007 AC-1 to AC-4 and the Words block, written once as checks over a
	bundle `{ Lobby, SeatCard, Relations, Words }`, so that the four
	`tests/client/*_test.luau` files can apply them to the real modules under
	`src/client/models/` and `src/client/Words.luau`, and
	`tests/client/seat_hud_controls_test.luau` can apply them to the wrong
	models in `SeatHudStubs.luau` - executed in RED, before the real modules
	exist.

	    LobbyModel.describe(view: { players: { string } }, playersMin: number, playersMax: number)
	        -> { state: "waiting" | "counting" | "full", glyph: string,
	             slots: { { playerId: string?, needed: boolean, hueToken: string? } } }
	    SeatCardModel.describe(seat: SeatViewLike)
	        -> { helper: Person, you: Person, partner: Person, samples: { Sample } }
	    RelationsModel.describe(seat: SeatViewLike, presence: { [string]: string }, dealt: SeatViewLike)
	        -> { helper: Chip, you: Chip, partner: Chip? }
	    Words.seat: { helper, you, partner, yours, theirs }   -- voice.md §2, "Seat card (C-05):"
	    Words.lobby: { alone }                               -- voice.md §2, "Lobby (C-26):"

	THE ORACLE IS PARTITIONED, as the story's `## Contract` partitions it:
	  * AC-1 to AC-3 are SETTLED by `components.md`'s C-26 / C-05 / C-04 state
	    tables, the Design notes DN-1..DN-9 and PO-1 / PO-2. Each check below
	    is named after the state it pins, and the expected values are the
	    story's `## Contract` block, restated as fixtures here. The hue
	    oracle is independent of every model: `hueFor(seatOrder, id)` is
	    `color.player.{index}`, computed in this file from the fixture, and
	    the key is also required to exist in `Theme.color`.
	  * AC-4 is MECHANICAL: `walk(kind, output)` returns every string that
	    begins `color.player.` and does not sit under the key `hueToken`
	    (DN-3), every `glyph` / `overlay` that is not a member of
	    `Theme.icons.system`, every state that has no glyph (PT-A7), and a
	    `you` that carries one (DN-4). The controls test drives it with
	    hand-built outputs, so it is observed reporting in RED.
	  * The WORDS are SETTLED by `voice.md` §2's optional-words paragraph,
	    read off disk through `VoiceSpec.parseQuotedWords`. Which KEY each
	    quoted word belongs to is the Contract's (`SEAT_KEYS`, in the
	    paragraph's order); the strings themselves are never restated here.

	THE RING FIXTURE. Four players `1001 -> 1002 -> 1003 -> 1004 -> 1001`
	(`Ring.luau`: σ(p) is p's DEPENDENT, the successor; σ⁻¹(p) the SUPPLIER,
	the predecessor). The viewer is 1003, so supplier 1002 (seat 2),
	dependent 1004 (seat 4) and the viewer (seat 3) all have DIFFERENT
	seat indices: a model that swaps supplier and dependent, or indexes the
	wrong hue, cannot pass by coincidence. The withdrawal fixtures follow
	`Ring.withdraw`: the leaver vanishes from `seatOrder`, the ring closes,
	and the leaver's key goes to its supplier.

	The checks accumulate violations and raise once, through `Contract.fail`,
	so a message carries every wrong field rather than the first.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local VoiceSpec = require("./VoiceSpec")
local Theme = require("../../src/client/Theme")

local SeatHudContract = {}

export type Bundle = { Lobby: any, SeatCard: any, Relations: any, Words: any }

export type SeatViewLike = {
	playerId: string,
	keyClasses: { number },
	lensClass: number,
	supplierId: string,
	dependentId: string,
	seatOrder: { string },
}

--[[ Fixtures ]]

-- Six ids in join order; the lobby fixtures take a prefix of this list.
SeatHudContract.IDS = table.freeze({ "1001", "1002", "1003", "1004", "1005", "1006" })

local function seatView(
	playerId: string,
	keyClasses: { number },
	lensClass: number,
	supplierId: string,
	dependentId: string,
	seatOrder: { string }
): SeatViewLike
	return {
		playerId = playerId,
		keyClasses = keyClasses,
		lensClass = lensClass,
		supplierId = supplierId,
		dependentId = dependentId,
		seatOrder = seatOrder,
	}
end

-- 1003's dealt view in the ring 1001 -> 1002 -> 1003 -> 1004 -> 1001.
function SeatHudContract.dealtP3(): SeatViewLike
	return seatView("1003", { 3 }, 4, "1002", "1004", { "1001", "1002", "1003", "1004" })
end

-- 1001's dealt view in the same ring: supplier 1004 (seat 4), dependent 1002 (seat 2).
function SeatHudContract.dealtP1(): SeatViewLike
	return seatView("1001", { 1 }, 2, "1004", "1002", { "1001", "1002", "1003", "1004" })
end

-- 1003's view after 1002 (its helper) withdrew: the ring is 1001 -> 1003 -> 1004 -> 1001,
-- so 1003's supplier is now 1001. 1002's key went to 1001, not to 1003.
function SeatHudContract.afterHelperLeft(): SeatViewLike
	return seatView("1003", { 3 }, 4, "1001", "1004", { "1001", "1003", "1004" })
end

-- 1003's view after 1004 (its partner) withdrew: 1003 -> 1001, and 1003 inherits class 4.
function SeatHudContract.afterPartnerLeft(): SeatViewLike
	return seatView("1003", { 3, 4 }, 4, "1002", "1001", { "1001", "1002", "1003" })
end

-- 1003's view after 1001 (neither relation) withdrew: relations intact, every seat index shifted.
function SeatHudContract.afterBystanderLeft(): SeatViewLike
	return seatView("1003", { 3 }, 4, "1002", "1004", { "1002", "1003", "1004" })
end

-- The contract's hue rule, computed here and nowhere near a model.
function SeatHudContract.hueFor(seatOrder: { string }, playerId: string): string
	local index = table.find(seatOrder, playerId)
	if index == nil then
		Contract.fail(`fixture error: {playerId} is not in seatOrder {Deep.show(seatOrder)}`)
	end
	return `color.player.{index}`
end

local function firstN(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = SeatHudContract.IDS[i]
	end
	return out
end

local function call(fn: any, ...: any): (boolean, any)
	return pcall(fn, ...)
end

local function describeLobby(bundle: Bundle, players: { string }, min: number, max: number): any
	local view = { players = players }
	local ok, result = call(bundle.Lobby.describe, view, min, max)
	if not ok then
		Contract.fail(
			`AC-1: LobbyModel.describe({#players} players, {min}, {max}) raised: {tostring(result)}`
		)
	end
	if typeof(result) ~= "table" then
		Contract.fail(`AC-1: LobbyModel.describe returned {typeof(result)}, wanted a table`)
	end
	return result
end

--[[ AC-1: the lobby panel (C-26, DN-1, DN-2) ]]

-- `(playersMin, playersMax)` pairs the lobby checks run over: tuning's 4/6,
-- a small pair where min + 1 == max, and one where min == max.
SeatHudContract.LOBBY_SIZES = table.freeze({ { 4, 6 }, { 2, 3 }, { 3, 3 } })

-- playersMax slots; the first playersMin needed; filled in players order with
-- color.player.{i}; nil past #players; no glyph on a slot (DN-2); fresh
-- tables; the view untouched; view.phase not read.
function SeatHudContract.lobbySlotsAreMaxLongNeededToMinAndHuedByIndex(bundle: Bundle)
	local violations: { string } = {}
	for _, pair in SeatHudContract.LOBBY_SIZES do
		local min, max = pair[1], pair[2]
		for count = 0, max do
			local players = firstN(count)
			local view = { players = players }
			local before = Deep.copy(view)
			local label = `({count} players, min {min}, max {max})`
			local ok, result = call(bundle.Lobby.describe, view, min, max)
			if not ok then
				table.insert(violations, `{label} raised: {tostring(result)}`)
				continue
			end
			local slots = if typeof(result) == "table" then result.slots else nil
			if typeof(slots) ~= "table" then
				table.insert(violations, `{label}: slots is {Deep.show(slots)}, wanted a table`)
				continue
			end
			if #slots ~= max then
				table.insert(violations, `{label}: {#slots} slot(s), wanted playersMax = {max}`)
			end
			for i = 1, math.max(#slots, max) do
				local want = {
					playerId = players[i],
					needed = i <= min,
					hueToken = if players[i] ~= nil then `color.player.{i}` else nil,
				}
				local diff = Deep.diff(want, slots[i])
				if diff ~= "" then
					table.insert(violations, `{label} slot {i}: {string.gsub(diff, "\n", "; ")}`)
				elseif want.hueToken ~= nil and Theme.color[want.hueToken] == nil then
					table.insert(
						violations,
						`{label} slot {i}: {want.hueToken} is not a key of Theme.color`
					)
				end
			end
			if result.slots == view.players then
				table.insert(violations, `{label}: slots IS view.players, wanted a fresh table`)
			end
			local okAgain, again = call(bundle.Lobby.describe, view, min, max)
			if okAgain and (again == result or again.slots == result.slots) then
				table.insert(violations, `{label}: a second describe returned the same table`)
			end
			local mutated = Deep.diff(before, view)
			if mutated ~= "" then
				table.insert(violations, `{label}: describe mutated the view: {mutated}`)
			end
			local okPhased, phased =
				call(bundle.Lobby.describe, { players = players, phase = "Round" }, min, max)
			if not okPhased then
				table.insert(
					violations,
					`{label} with view.phase = "Round" raised: {tostring(phased)}`
				)
			else
				local diff = Deep.diff(result, phased)
				if diff ~= "" then
					table.insert(
						violations,
						`{label}: view.phase is read; with "Round" it differs: {diff}`
					)
				end
			end
		end
	end
	if #violations > 0 then
		Contract.fail(`AC-1 slots: {#violations} fault(s):\n` .. Contract.firstFew(violations, 12))
	end
end

local function lobbyStateIs(
	bundle: Bundle,
	rows: { { count: number, min: number, max: number } },
	state: string,
	glyph: string,
	tag: string
)
	local violations: { string } = {}
	for _, row in rows do
		local label = `({row.count} players, min {row.min}, max {row.max})`
		local ok, result =
			call(bundle.Lobby.describe, { players = firstN(row.count) }, row.min, row.max)
		if not ok then
			table.insert(violations, `{label} raised: {tostring(result)}`)
		elseif typeof(result) ~= "table" then
			table.insert(violations, `{label}: returned {typeof(result)}`)
		else
			if result.state ~= state then
				table.insert(
					violations,
					`{label}: state is {Deep.show(result.state)}, wanted "{state}"`
				)
			end
			if result.glyph ~= glyph then
				table.insert(
					violations,
					`{label}: glyph is {Deep.show(result.glyph)}, wanted "{glyph}" (DN-1)`
				)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(`AC-1 {tag}: {#violations} fault(s):\n` .. Contract.firstFew(violations, 10))
	end
end

-- Below playersMin: waiting, glyph.wait. Includes nobody and one alone.
function SeatHudContract.lobbyWaitingBelowMin(bundle: Bundle)
	lobbyStateIs(bundle, {
		{ count = 0, min = 4, max = 6 },
		{ count = 1, min = 4, max = 6 },
		{ count = 3, min = 4, max = 6 },
		{ count = 1, min = 2, max = 3 },
		{ count = 0, min = 3, max = 3 },
		{ count = 2, min = 3, max = 3 },
	}, "waiting", "glyph.wait", "waiting")
end

-- At playersMin and up to playersMax - 1: counting, glyph.notyet.
function SeatHudContract.lobbyCountingAtMin(bundle: Bundle)
	lobbyStateIs(bundle, {
		{ count = 4, min = 4, max = 6 },
		{ count = 5, min = 4, max = 6 },
		{ count = 2, min = 2, max = 3 },
	}, "counting", "glyph.notyet", "counting")
end

-- At playersMax: full, glyph.done - also when min == max.
function SeatHudContract.lobbyFullAtMax(bundle: Bundle)
	lobbyStateIs(bundle, {
		{ count = 6, min = 4, max = 6 },
		{ count = 3, min = 2, max = 3 },
		{ count = 3, min = 3, max = 3 },
	}, "full", "glyph.done", "full")
end

--[[ AC-2: the seat card (C-05, DN-4, DN-9) ]]

SeatHudContract.SEAT_VIEWERS = { SeatHudContract.dealtP3, SeatHudContract.dealtP1 }

local function describeSeat(bundle: Bundle, seat: SeatViewLike): any
	local ok, result = call(bundle.SeatCard.describe, seat)
	if not ok then
		Contract.fail(
			`AC-2: SeatCardModel.describe(viewer {seat.playerId}) raised: {tostring(result)}`
		)
	end
	if typeof(result) ~= "table" then
		Contract.fail(`AC-2: SeatCardModel.describe returned {typeof(result)}, wanted a table`)
	end
	return result
end

local function personIs(bundle: Bundle, field: string, want: (SeatViewLike) -> any, tag: string)
	local violations: { string } = {}
	for _, make in SeatHudContract.SEAT_VIEWERS do
		local seat = make()
		local result = describeSeat(bundle, seat)
		local diff = Deep.diff(want(seat), result[field])
		if diff ~= "" then
			table.insert(
				violations,
				`viewer {seat.playerId}: {field} is wrong: {string.gsub(diff, "\n", "; ")}`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(`AC-2 {tag}: {#violations} fault(s):\n` .. Contract.firstFew(violations, 8))
	end
end

-- helper = { supplierId, hue by seatOrder, "glyph.eye" }.
function SeatHudContract.seatHelperIsTheSupplierWithTheEye(bundle: Bundle)
	personIs(bundle, "helper", function(seat)
		return {
			playerId = seat.supplierId,
			hueToken = SeatHudContract.hueFor(seat.seatOrder, seat.supplierId),
			glyph = "glyph.eye",
		}
	end, "helper")
end

-- partner = { dependentId, hue by seatOrder, "glyph.key" }.
function SeatHudContract.seatPartnerIsTheDependentWithTheKey(bundle: Bundle)
	personIs(bundle, "partner", function(seat)
		return {
			playerId = seat.dependentId,
			hueToken = SeatHudContract.hueFor(seat.seatOrder, seat.dependentId),
			glyph = "glyph.key",
		}
	end, "partner")
end

-- you = { playerId, hue by seatOrder, glyph nil } (DN-4), and the output is fresh.
function SeatHudContract.seatYouHasYourHueAndNoGlyph(bundle: Bundle)
	personIs(bundle, "you", function(seat)
		return {
			playerId = seat.playerId,
			hueToken = SeatHudContract.hueFor(seat.seatOrder, seat.playerId),
		}
	end, "you")
	local seat = SeatHudContract.dealtP3()
	local before = Deep.copy(seat)
	local first = describeSeat(bundle, seat)
	local second = describeSeat(bundle, seat)
	local violations: { string } = {}
	if first.you.glyph ~= nil then
		table.insert(violations, `you.glyph is {Deep.show(first.you.glyph)}, wanted nil (DN-4)`)
	end
	if first == second or first.you == second.you or first.samples == second.samples then
		table.insert(
			violations,
			"a second describe returned the same table(s); every returned table is fresh"
		)
	end
	local mutated = Deep.diff(before, seat)
	if mutated ~= "" then
		table.insert(violations, `describe mutated the seat view: {mutated}`)
	end
	if #violations > 0 then
		Contract.fail(`AC-2 you: {#violations} fault(s):\n` .. Contract.firstFew(violations, 4))
	end
end

-- samples = { { viewer's hue, "glyph.key" }, { dependent's hue, "glyph.eye" } }, exactly, in that order (DN-9).
-- The hues are computed from the seat, not read back from `you` / `partner`.
function SeatHudContract.seatSamplesAreYoursWithKeyThenPartnersWithEye(bundle: Bundle)
	local violations: { string } = {}
	for _, make in SeatHudContract.SEAT_VIEWERS do
		local seat = make()
		local result = describeSeat(bundle, seat)
		local want = {
			{
				hueToken = SeatHudContract.hueFor(seat.seatOrder, seat.playerId),
				glyph = "glyph.key",
			},
			{
				hueToken = SeatHudContract.hueFor(seat.seatOrder, seat.dependentId),
				glyph = "glyph.eye",
			},
		}
		local diff = Deep.diff(want, result.samples)
		if diff ~= "" then
			table.insert(
				violations,
				`viewer {seat.playerId}: samples are wrong: {string.gsub(diff, "\n", "; ")}`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 samples (DN-9): {#violations} fault(s):\n` .. Contract.firstFew(violations, 8)
		)
	end
end

-- A playerId absent from seatOrder raises, naming the id.
function SeatHudContract.seatUnknownIdRaisesNamingIt(bundle: Bundle)
	local seat = SeatHudContract.dealtP3()
	seat.seatOrder = { "1001", "1003", "1004" } -- 1002, the supplier, is missing
	local ok, result = call(bundle.SeatCard.describe, seat)
	if ok then
		Contract.fail(
			`AC-2: describe with supplier 1002 absent from seatOrder returned {Deep.show(result)} instead of raising`
		)
	end
	if string.find(tostring(result), "1002", 1, true) == nil then
		Contract.fail(
			`AC-2: the raise for an id absent from seatOrder does not name 1002; it said: {tostring(
				result
			)}`
		)
	end
end

--[[ AC-3: the relations strip (C-04, DN-5..DN-8, PO-1, PO-2) ]]

export type Presence = { [string]: string }

local function describeRelations(
	bundle: Bundle,
	seat: SeatViewLike,
	presence: Presence,
	dealt: SeatViewLike
): any
	local ok, result = call(bundle.Relations.describe, seat, presence, dealt)
	if not ok then
		Contract.fail(`AC-3: RelationsModel.describe raised: {tostring(result)}`)
	end
	if typeof(result) ~= "table" then
		Contract.fail(`AC-3: RelationsModel.describe returned {typeof(result)}, wanted a table`)
	end
	return result
end

local function chip(
	playerId: string,
	hueToken: string,
	glyph: string?,
	state: string,
	overlay: string?
): any
	return {
		playerId = playerId,
		hueToken = hueToken,
		glyph = glyph,
		state = state,
		struck = false,
		overlay = overlay,
	}
end

-- What C-04 shows for 1003 with its dealt ring intact, given the two relations' presence.
local function intactExpectation(
	dealt: SeatViewLike,
	helperState: string,
	partnerState: string
): any
	local order = dealt.seatOrder
	return {
		helper = chip(
			dealt.supplierId,
			SeatHudContract.hueFor(order, dealt.supplierId),
			"glyph.eye",
			helperState,
			if helperState == "away" then "glyph.wait" else nil
		),
		you = chip(
			dealt.playerId,
			SeatHudContract.hueFor(order, dealt.playerId),
			nil,
			"present",
			nil
		),
		partner = chip(
			dealt.dependentId,
			SeatHudContract.hueFor(order, dealt.dependentId),
			"glyph.key",
			partnerState,
			if partnerState == "away" then "glyph.wait" else nil
		),
	}
end

local function relationsAre(
	bundle: Bundle,
	rows: {
		{
			label: string,
			seat: SeatViewLike,
			presence: Presence,
			dealt: SeatViewLike,
			want: any,
		}
	},
	tag: string
)
	local violations: { string } = {}
	for _, row in rows do
		local ok, result = call(bundle.Relations.describe, row.seat, row.presence, row.dealt)
		if not ok then
			table.insert(violations, `{row.label}: raised {tostring(result)}`)
		else
			local diff = Deep.diff(row.want, result)
			if diff ~= "" then
				table.insert(violations, `{row.label}: {string.gsub(diff, "\n", "; ")}`)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(`AC-3 {tag}: {#violations} fault(s):\n` .. Contract.firstFew(violations, 10))
	end
end

-- present: headshot, hue ring, glyph; no overlay, not struck.
function SeatHudContract.relationsPresent(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "both relations present",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "present", ["1003"] = "present", ["1004"] = "present" },
			dealt = dealt,
			want = intactExpectation(dealt, "present", "present"),
		},
	}, "present")
end

-- loading: the fetch state, or the map having no entry for the id.
function SeatHudContract.relationsLoadingWhenFetchingOrUnlisted(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "both relations listed as loading",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "loading", ["1003"] = "present", ["1004"] = "loading" },
			dealt = dealt,
			want = intactExpectation(dealt, "loading", "loading"),
		},
		{
			label = "an empty presence map (nobody listed, the viewer included)",
			seat = SeatHudContract.dealtP3(),
			presence = {},
			dealt = dealt,
			want = intactExpectation(dealt, "loading", "loading"),
		},
		{
			label = "helper present, partner unlisted",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "present" },
			dealt = dealt,
			want = intactExpectation(dealt, "present", "loading"),
		},
	}, "loading")
end

-- error: as loading, permanently; the state field alone distinguishes them (DN-8).
function SeatHudContract.relationsErrorKeepsTheGlyph(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "both headshot fetches failed",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "error", ["1003"] = "present", ["1004"] = "error" },
			dealt = dealt,
			want = intactExpectation(dealt, "error", "error"),
		},
	}, "error")
end

-- away: the relation glyph survives and overlay is glyph.wait (DN-7).
function SeatHudContract.relationsAwayOverlaysWaitAndKeepsTheRelationGlyph(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "both relations away",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "away", ["1003"] = "present", ["1004"] = "away" },
			dealt = dealt,
			want = intactExpectation(dealt, "away", "away"),
		},
		{
			label = "helper away, partner present",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "away", ["1003"] = "present", ["1004"] = "present" },
			dealt = dealt,
			want = intactExpectation(dealt, "away", "present"),
		},
	}, "away")
end

-- helper none (PO-1, DN-5): after 1002 withdrew, 1003's supplier is 1001, which is
-- not the dealt supplier. The chip is the struck eye with no id and no hue. You and
-- the partner keep their DEALT hues (PO-2): the current seatOrder would say 2 and 3.
function SeatHudContract.relationsHelperNoneAfterTheHelperLeft(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "helper 1002 withdrew; 1001 closed the ring",
			seat = SeatHudContract.afterHelperLeft(),
			presence = { ["1001"] = "present", ["1003"] = "present", ["1004"] = "present" },
			dealt = dealt,
			want = {
				helper = { glyph = "glyph.eye", state = "none", struck = true },
				you = chip("1003", "color.player.3", nil, "present", nil),
				partner = chip("1004", "color.player.4", "glyph.key", "present", nil),
			},
		},
	}, "helper none")
end

-- partner none (PO-1, DN-6): after 1004 withdrew, 1003's dependent is 1001; partner is nil.
function SeatHudContract.relationsPartnerNilAfterThePartnerLeft(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "partner 1004 withdrew; 1003 now feeds 1001",
			seat = SeatHudContract.afterPartnerLeft(),
			presence = { ["1001"] = "present", ["1002"] = "present", ["1003"] = "present" },
			dealt = dealt,
			want = {
				helper = chip("1002", "color.player.2", "glyph.eye", "present", nil),
				you = chip("1003", "color.player.3", nil, "present", nil),
			},
		},
	}, "partner none")
end

-- PO-2: after a bystander withdrew every current seat index shifted down by one,
-- but the hues are the dealt ones.
function SeatHudContract.relationsHuesComeFromTheDealtSeatOrder(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "1001 withdrew; seatOrder is now {1002, 1003, 1004}",
			seat = SeatHudContract.afterBystanderLeft(),
			presence = { ["1002"] = "present", ["1003"] = "present", ["1004"] = "present" },
			dealt = dealt,
			want = {
				helper = chip("1002", "color.player.2", "glyph.eye", "present", nil),
				you = chip("1003", "color.player.3", nil, "present", nil),
				partner = chip("1004", "color.player.4", "glyph.key", "present", nil),
			},
		},
	}, "dealt hues")
end

-- you: state present whatever the map says, glyph nil (DN-4), no overlay; fresh output; inputs untouched.
function SeatHudContract.relationsYouIsAlwaysPresentWithNoGlyph(bundle: Bundle)
	local dealt = SeatHudContract.dealtP3()
	relationsAre(bundle, {
		{
			label = "the map lists the viewer as away",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "present", ["1003"] = "away", ["1004"] = "present" },
			dealt = dealt,
			want = intactExpectation(dealt, "present", "present"),
		},
	}, "you")
	local seat, presence = SeatHudContract.dealtP3(), { ["1002"] = "present", ["1004"] = "present" }
	local snapshot = Deep.copy({ seat = seat, presence = presence, dealt = dealt })
	local first = describeRelations(bundle, seat, presence, dealt)
	local second = describeRelations(bundle, seat, presence, dealt)
	local violations: { string } = {}
	if first.you.glyph ~= nil then
		table.insert(violations, `you.glyph is {Deep.show(first.you.glyph)}, wanted nil (DN-4)`)
	end
	if first == second or first.helper == second.helper or first.you == second.you then
		table.insert(
			violations,
			"a second describe returned the same table(s); every returned table is fresh"
		)
	end
	local mutated = Deep.diff(snapshot, { seat = seat, presence = presence, dealt = dealt })
	if mutated ~= "" then
		table.insert(violations, `describe mutated an input: {mutated}`)
	end
	if #violations > 0 then
		Contract.fail(`AC-3 you: {#violations} fault(s):\n` .. Contract.firstFew(violations, 4))
	end
end

-- A playerId absent from dealt.seatOrder raises, naming it - for the viewer and for a relation.
function SeatHudContract.relationsUnknownIdRaisesNamingIt(bundle: Bundle)
	local cases = {
		{ missing = "1003", order = { "1001", "1002", "1004" } },
		{ missing = "1004", order = { "1001", "1002", "1003" } },
	}
	local violations: { string } = {}
	for _, case in cases do
		local dealt = SeatHudContract.dealtP3()
		dealt.seatOrder = case.order
		local ok, result = call(bundle.Relations.describe, SeatHudContract.dealtP3(), {}, dealt)
		if ok then
			table.insert(
				violations,
				`with {case.missing} absent from dealt.seatOrder: returned {Deep.show(result)} instead of raising`
			)
		elseif string.find(tostring(result), case.missing, 1, true) == nil then
			table.insert(
				violations,
				`with {case.missing} absent from dealt.seatOrder: the raise does not name it: {tostring(
					result
				)}`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 unknown id: {#violations} fault(s):\n` .. Contract.firstFew(violations, 4)
		)
	end
end

--[[ AC-4: the mechanical walk (DN-3, DN-4, PT-A7) ]]

export type Kind = "lobby" | "seat" | "relations"

local systemGlyphs: { [string]: boolean } = {}
for _, key in Theme.icons.system do
	systemGlyphs[key] = true
end

local function walkTable(value: any, path: string, violations: { string }, seen: { [any]: boolean })
	if typeof(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	for key, item in pairs(value :: { [any]: any }) do
		local here = `{path}.{tostring(key)}`
		if typeof(item) == "string" then
			if string.match(item, "^color%.player%.") ~= nil and key ~= "hueToken" then
				table.insert(
					violations,
					`{here} = "{item}": a player hue under a key other than hueToken (DN-3)`
				)
			end
			if (key == "glyph" or key == "overlay") and not systemGlyphs[item] then
				table.insert(violations, `{here} = "{item}": not a member of Theme.icons.system`)
			end
		elseif typeof(item) == "table" then
			walkTable(item, here, violations, seen)
		end
	end
end

local function needsGlyph(node: any, path: string, violations: { string })
	if typeof(node) ~= "table" then
		table.insert(violations, `{path}: is {typeof(node)}, wanted a table`)
	elseif node.glyph == nil then
		table.insert(violations, `{path}.glyph is nil: every state needs a glyph (PT-A7)`)
	end
end

-- Every DN-3 / DN-4 / PT-A7 violation in one model output, by kind. Empty when clean.
function SeatHudContract.walk(kind: Kind, output: any): { string }
	local violations: { string } = {}
	if typeof(output) ~= "table" then
		return { `{kind}: output is {typeof(output)}, wanted a table` }
	end
	walkTable(output, kind, violations, {})
	if kind == "lobby" then
		needsGlyph(output, kind, violations)
	elseif kind == "seat" then
		needsGlyph(output.helper, `{kind}.helper`, violations)
		needsGlyph(output.partner, `{kind}.partner`, violations)
		if typeof(output.samples) == "table" then
			for i, sample in output.samples do
				needsGlyph(sample, `{kind}.samples[{i}]`, violations)
			end
		else
			table.insert(violations, `{kind}.samples is {typeof(output.samples)}, wanted a table`)
		end
		if typeof(output.you) ~= "table" or output.you.glyph ~= nil then
			table.insert(
				violations,
				`{kind}.you.glyph is {Deep.show(
					if typeof(output.you) == "table" then output.you.glyph else output.you
				)}, wanted nil (DN-4)`
			)
		end
	elseif kind == "relations" then
		needsGlyph(output.helper, `{kind}.helper`, violations)
		if output.partner ~= nil then
			needsGlyph(output.partner, `{kind}.partner`, violations)
		end
		if typeof(output.you) ~= "table" or output.you.glyph ~= nil then
			table.insert(
				violations,
				`{kind}.you.glyph is {Deep.show(
					if typeof(output.you) == "table" then output.you.glyph else output.you
				)}, wanted nil (DN-4)`
			)
		end
	end
	return violations
end

-- Every output the AC-1..AC-3 checks build, as `{ label, kind, output }`.
function SeatHudContract.everyOutput(bundle: Bundle): { { label: string, kind: Kind, output: any } }
	local out: { { label: string, kind: Kind, output: any } } = {}
	for _, pair in SeatHudContract.LOBBY_SIZES do
		for count = 0, pair[2] do
			table.insert(out, {
				label = `lobby ({count} players, min {pair[1]}, max {pair[2]})`,
				kind = "lobby",
				output = describeLobby(bundle, firstN(count), pair[1], pair[2]),
			})
		end
	end
	for _, make in SeatHudContract.SEAT_VIEWERS do
		local seat = make()
		table.insert(out, {
			label = `seat card (viewer {seat.playerId})`,
			kind = "seat",
			output = describeSeat(bundle, seat),
		})
	end
	local dealt = SeatHudContract.dealtP3()
	local relationRows = {
		{
			label = "relations present",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "present", ["1004"] = "present" },
		},
		{ label = "relations loading", seat = SeatHudContract.dealtP3(), presence = {} },
		{
			label = "relations error",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "error", ["1004"] = "error" },
		},
		{
			label = "relations away",
			seat = SeatHudContract.dealtP3(),
			presence = { ["1002"] = "away", ["1004"] = "away" },
		},
		{
			label = "relations helper none",
			seat = SeatHudContract.afterHelperLeft(),
			presence = { ["1001"] = "present", ["1004"] = "present" },
		},
		{
			label = "relations partner none",
			seat = SeatHudContract.afterPartnerLeft(),
			presence = { ["1002"] = "present", ["1001"] = "present" },
		},
		{
			label = "relations after a bystander left",
			seat = SeatHudContract.afterBystanderLeft(),
			presence = { ["1002"] = "present", ["1004"] = "present" },
		},
	}
	for _, row in relationRows do
		table.insert(out, {
			label = row.label,
			kind = "relations",
			output = describeRelations(bundle, row.seat, row.presence, dealt),
		})
	end
	return out
end

-- The AC-4 assertion: the walk over every output reports nothing.
function SeatHudContract.everyOutputWalksClean(bundle: Bundle)
	local outputs = SeatHudContract.everyOutput(bundle)
	local violations: { string } = {}
	for _, entry in outputs do
		for _, v in SeatHudContract.walk(entry.kind, entry.output) do
			table.insert(violations, `{entry.label}: {v}`)
		end
	end
	if #outputs < 15 then
		Contract.fail(
			`AC-4: only {#outputs} output(s) were built; the walk would be over too little`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-4: {#violations} violation(s) over {#outputs} output(s):\n`
				.. Contract.firstFew(violations, 12)
		)
	end
end

--[[ Words: voice.md §2's optional words, read off disk ]]

SeatHudContract.SEAT_LABEL = "Seat card (C-05):"
SeatHudContract.LOBBY_LABEL = "Lobby (C-26):"
-- The Contract's keys, in the paragraph's order.
SeatHudContract.SEAT_KEYS = table.freeze({ "helper", "you", "partner", "yours", "theirs" })
SeatHudContract.LOBBY_KEYS = table.freeze({ "alone" })

local function wordsMatch(table_: any, keys: { string }, label: string, name: string)
	local words = VoiceSpec.parseQuotedWords(VoiceSpec.read(), label)
	if #words == 0 then
		Contract.fail(
			`{VoiceSpec.PATH}: read 0 quoted words after "{label}"; the check would be over nothing`
		)
	end
	local violations: { string } = {}
	if #words ~= #keys then
		table.insert(
			violations,
			`voice.md lists {#words} word(s) after "{label}", the Contract names {#keys} key(s)`
		)
	end
	if typeof(table_) ~= "table" then
		Contract.fail(`Words.{name} is {typeof(table_)}, wanted a table`)
	end
	for i, key in keys do
		if table_[key] ~= words[i] then
			table.insert(
				violations,
				`Words.{name}.{key} is {Deep.show(table_[key])}; voice.md says {Deep.show(words[i])}`
			)
		end
	end
	for key, value in pairs(table_) do
		if table.find(keys, key) == nil then
			table.insert(
				violations,
				`Words.{name}.{tostring(key)} = {Deep.show(value)} is in the module, but the Contract names no such key`
			)
		end
	end
	if not table.isfrozen(table_) then
		table.insert(violations, `Words.{name} is not frozen`)
	end
	if #violations > 0 then
		Contract.fail(
			`Words.{name}: {#violations} drift(s) from voice.md "{label}":\n`
				.. Contract.firstFew(violations, 8)
		)
	end
end

function SeatHudContract.wordsSeatMatchVoice(bundle: Bundle)
	wordsMatch(bundle.Words.seat, SeatHudContract.SEAT_KEYS, SeatHudContract.SEAT_LABEL, "seat")
end

function SeatHudContract.wordsLobbyMatchVoice(bundle: Bundle)
	wordsMatch(bundle.Words.lobby, SeatHudContract.LOBBY_KEYS, SeatHudContract.LOBBY_LABEL, "lobby")
end

return SeatHudContract
