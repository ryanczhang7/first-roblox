--!strict
--[[
	The wrong lobby / seat-card / relations models HUD-007's controls are
	aimed at, and the one baseline each of them is a single defect away from.

	In RED the real modules do not exist, the four `tests/client/*_test.luau`
	files are red at `require`, and not one of their assertions has run.
	Applying the same checks (`SeatHudContract.luau`) to a model that swaps
	supplier and dependent is how those assertions get observed rejecting
	something before GREEN starts - and the defect list doubles as the
	mutation table in the story's handoff: each entry is one `mutate.sh`
	expression GATES can run against the shipped module.

	IT IS A FACTORY OVER A TABLE OF DEFECTS: `defects` is empty for the
	baseline and has exactly ONE field set for every control. The baseline's
	`Words.seat` / `Words.lobby` restate voice.md §2's optional words - a stub
	may, the real module's test may not - and that restatement is what lets
	the controls test show the `VoiceSpec.parseQuotedWords` reader agrees
	with a table it did not parse.

	WHAT THIS IS NOT: `src/client/models/{LobbyModel,SeatCardModel,RelationsModel}.luau`
	or `src/client/Words.luau`, or a sketch of any of them. GREEN writes them
	from the story's `## Contract`; nothing here is to be copied.
]]

local SeatHudStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  lobby (AC-1)
	  * `gtForGteAtMin`         - `#players > playersMin` for `>=`: at exactly
	                              playersMin the panel still waits
	  * `fullNeverReported`     - at playersMax the state is "counting"
	  * `glyphSameForEveryState`- every state carries glyph.wait (DN-1)
	  * `slotsFromPlayersCount` - #slots == #players, not playersMax
	  * `neededOffByOne`        - needed is `i < playersMin`
	  * `hueByZeroIndex`        - color.player.0 for the first seat
	  * `slotCarriesGlyph`      - every filled slot carries glyph.key (DN-2)
	  * `hueOnSlotName`         - a filled slot carries `textColour = hueToken` (DN-3)
	  * `readsPhase`            - view.phase == "Round" forces "waiting"
	  * `lobbyMutatesView`      - describe appends "" to view.players
	  seat card (AC-2)
	  * `swapsSupplierDependent`- helper reads dependentId, partner reads supplierId
	                              (Ring.luau's direction error)
	  * `swapsSampleGlyphs`     - yours carries glyph.eye, the partner's glyph.key (DN-9)
	  * `samplesReversed`       - the partner's sample comes first
	  * `oneSample`             - only your sample is returned
	  * `hueByWrongIndex`       - every hue is the NEXT seat's (index + 1, wrapping)
	  * `youHasGlyph`           - you carries glyph.key (DN-4)
	  * `echoesUnknownId`       - an id absent from seatOrder gets color.player.none instead of a raise
	  * `seatHueOnName`         - helper carries `nameColour = hueToken` (DN-3)
	  relations (AC-3)
	  * `comparesSeatToItself`  - helper none iff seat.supplierId ~= seat.supplierId (never; PO-1)
	  * `hueFromCurrentSeatOrder` - hues indexed in seat.seatOrder, not dealt.seatOrder (PO-2)
	  * `missingPresenceIsPresent` - no map entry reads as "present", not "loading"
	  * `awayDropsRelationGlyph`- an away chip's glyph is nil (DN-7)
	  * `awayNoOverlay`         - an away chip has no glyph.wait overlay (DN-7)
	  * `noneKeepsPlayerId`     - the none helper still carries the new supplier's id and hue (DN-5)
	  * `noneNotStruck`         - the none helper has struck = false (DN-5)
	  * `helperNoneHasNoGlyph`  - the none helper has glyph = nil (DN-5 / PT-A7)
	  * `partnerNoneAsChip`     - partner none is a chip with state "none", not nil (DN-6)
	  * `youStateFromPresence`  - you.state is read from the map (so it can be "loading" or "away")
	  * `relUnknownIdEchoes`    - an id absent from dealt.seatOrder gets color.player.none instead of a raise
	  words
	  * `seatWordDrift`         - Words.seat.partner is "Partner"
	  * `extraSeatWord`         - Words.seat.ready exists
	  * `lobbyWordDrift`        - Words.lobby.alone is "Waiting for players"
]]
SeatHudStubs.DEFECTS = {
	"gtForGteAtMin",
	"fullNeverReported",
	"glyphSameForEveryState",
	"slotsFromPlayersCount",
	"neededOffByOne",
	"hueByZeroIndex",
	"slotCarriesGlyph",
	"hueOnSlotName",
	"readsPhase",
	"lobbyMutatesView",
	"swapsSupplierDependent",
	"swapsSampleGlyphs",
	"samplesReversed",
	"oneSample",
	"hueByWrongIndex",
	"youHasGlyph",
	"echoesUnknownId",
	"seatHueOnName",
	"comparesSeatToItself",
	"hueFromCurrentSeatOrder",
	"missingPresenceIsPresent",
	"awayDropsRelationGlyph",
	"awayNoOverlay",
	"noneKeepsPlayerId",
	"noneNotStruck",
	"helperNoneHasNoGlyph",
	"partnerNoneAsChip",
	"youStateFromPresence",
	"relUnknownIdEchoes",
	"seatWordDrift",
	"extraSeatWord",
	"lobbyWordDrift",
}

type Defects = { [string]: boolean }

local function hueIn(order: { string }, id: string, echo: boolean, shift: number): string
	local index = table.find(order, id)
	if index == nil then
		if echo then
			return "color.player.none"
		end
		error(`stub: {id} is not in seatOrder`, 0)
	end
	if shift ~= 0 then
		index = (index - 1 + shift) % #order + 1
	end
	return `color.player.{index}`
end

local function buildLobby(d: Defects): any
	return {
		describe = function(view: any, playersMin: number, playersMax: number): any
			local players = view.players
			local n = #players
			local state: string
			if n >= playersMax and not d.fullNeverReported then
				state = "full"
			elseif if d.gtForGteAtMin then n > playersMin else n >= playersMin then
				state = "counting"
			else
				state = "waiting"
			end
			if d.readsPhase and view.phase == "Round" then
				state = "waiting"
			end
			local glyphs =
				{ waiting = "glyph.wait", counting = "glyph.notyet", full = "glyph.done" }
			local glyph = if d.glyphSameForEveryState then "glyph.wait" else glyphs[state]
			local slots: { any } = {}
			local count = if d.slotsFromPlayersCount then n else playersMax
			for i = 1, count do
				local id = players[i]
				local slot: any = {
					playerId = id,
					needed = if d.neededOffByOne then i < playersMin else i <= playersMin,
					hueToken = if id ~= nil
						then `color.player.{if d.hueByZeroIndex then i - 1 else i}`
						else nil,
				}
				if d.slotCarriesGlyph and id ~= nil then
					slot.glyph = "glyph.key"
				end
				if d.hueOnSlotName and id ~= nil then
					slot.textColour = slot.hueToken
				end
				slots[i] = slot
			end
			if d.lobbyMutatesView then
				view.players[n + 1] = ""
			end
			return { state = state, glyph = glyph, slots = slots }
		end,
	}
end

local function buildSeatCard(d: Defects): any
	return {
		describe = function(seat: any): any
			local supplier, dependent = seat.supplierId, seat.dependentId
			if d.swapsSupplierDependent then
				supplier, dependent = dependent, supplier
			end
			local shift = if d.hueByWrongIndex then 1 else 0
			local function hue(id: string): string
				return hueIn(seat.seatOrder, id, d.echoesUnknownId == true, shift)
			end
			local helper: any =
				{ playerId = supplier, hueToken = hue(supplier), glyph = "glyph.eye" }
			local you: any = {
				playerId = seat.playerId,
				hueToken = hue(seat.playerId),
				glyph = if d.youHasGlyph then "glyph.key" else nil,
			}
			local partner: any =
				{ playerId = dependent, hueToken = hue(dependent), glyph = "glyph.key" }
			if d.seatHueOnName then
				helper.nameColour = helper.hueToken
			end
			local samples: { any } = {
				{ hueToken = you.hueToken, glyph = "glyph.key" },
				{ hueToken = partner.hueToken, glyph = "glyph.eye" },
			}
			if d.swapsSampleGlyphs then
				samples[1].glyph, samples[2].glyph = "glyph.eye", "glyph.key"
			end
			if d.samplesReversed then
				samples = { samples[2], samples[1] }
			end
			if d.oneSample then
				samples = { samples[1] }
			end
			return { helper = helper, you = you, partner = partner, samples = samples }
		end,
	}
end

local function buildRelations(d: Defects): any
	return {
		describe = function(seat: any, presence: any, dealt: any): any
			local order = if d.hueFromCurrentSeatOrder then seat.seatOrder else dealt.seatOrder
			local function hue(id: string): string
				return hueIn(order, id, d.relUnknownIdEchoes == true, 0)
			end
			local function stateOf(id: string): string
				local state = presence[id]
				if state == nil then
					return if d.missingPresenceIsPresent then "present" else "loading"
				end
				return state
			end
			local function chip(id: string, glyph: string): any
				local state = stateOf(id)
				local c: any = {
					playerId = id,
					hueToken = hue(id),
					glyph = glyph,
					state = state,
					struck = false,
					overlay = if state == "away" and not d.awayNoOverlay then "glyph.wait" else nil,
				}
				if d.awayDropsRelationGlyph and state == "away" then
					c.glyph = nil
				end
				return c
			end
			local helperGone = if d.comparesSeatToItself
				then seat.supplierId ~= seat.supplierId
				else seat.supplierId ~= dealt.supplierId
			local helper: any
			if helperGone then
				helper = {
					playerId = if d.noneKeepsPlayerId then seat.supplierId else nil,
					hueToken = if d.noneKeepsPlayerId then hue(seat.supplierId) else nil,
					glyph = if d.helperNoneHasNoGlyph then nil else "glyph.eye",
					state = "none",
					struck = not d.noneNotStruck,
				}
			else
				helper = chip(seat.supplierId, "glyph.eye")
			end
			local partner: any = nil
			if seat.dependentId ~= dealt.dependentId then
				if d.partnerNoneAsChip then
					partner = { glyph = "glyph.key", state = "none", struck = true }
				end
			else
				partner = chip(seat.dependentId, "glyph.key")
			end
			local you: any = {
				playerId = seat.playerId,
				hueToken = hue(seat.playerId),
				state = if d.youStateFromPresence then stateOf(seat.playerId) else "present",
				struck = false,
			}
			return { helper = helper, you = you, partner = partner }
		end,
	}
end

local function buildWords(d: Defects): any
	local seat: { [string]: string } = {
		helper = "Your helper",
		you = "You",
		partner = "You help",
		yours = "Yours to turn",
		theirs = "You can see these",
	}
	if d.seatWordDrift then
		seat.partner = "Partner"
	end
	if d.extraSeatWord then
		seat.ready = "Ready"
	end
	local lobby: { [string]: string } = {
		alone = if d.lobbyWordDrift then "Waiting for players" else "Waiting for friends",
	}
	return table.freeze({ seat = table.freeze(seat), lobby = table.freeze(lobby) })
end

function SeatHudStubs.build(
	defects: Defects
): { Lobby: any, SeatCard: any, Relations: any, Words: any }
	return {
		Lobby = buildLobby(defects),
		SeatCard = buildSeatCard(defects),
		Relations = buildRelations(defects),
		Words = buildWords(defects),
	}
end

return SeatHudStubs
