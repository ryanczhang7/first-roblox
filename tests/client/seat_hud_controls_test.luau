--!strict
--[[
	The negative controls for HUD-007 AC-1 to AC-4 and the Words block, and
	the proof that each check in `tests/helpers/SeatHudContract.luau` refuses
	the model it exists to catch - plus the AC-4 walker's and the
	`VoiceSpec.parseQuotedWords` reader's own discrimination, driven in
	memory, since a walker that reported nothing would make AC-4 vacuous and
	a reader that found words under the wrong label would make the words
	checks vacuous.

	EVERY CONTROL IS ASSERTED TO FAIL EXACTLY THE CHECKS IT SHOULD, and the
	baseline to pass every check. The sets were MEASURED under
	`lune run test` in RED and pinned here; the story's `## Handoff` carries
	the same table as the mutation table GATES runs with `scripts/mutate.sh`.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE: the models are
	`SeatHudStubs.luau`, the walker runs over hand-built tables, and the
	reader runs over the real voice.md and over fixtures.
]]

local Contract = require("../helpers/SeatHudContract")
local Stubs = require("../helpers/SeatHudStubs")
local VoiceSpec = require("../helpers/VoiceSpec")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local CHECKS: { Named } = {
	{ label = "lobby slots", check = Contract.lobbySlotsAreMaxLongNeededToMinAndHuedByIndex },
	{ label = "lobby waiting", check = Contract.lobbyWaitingBelowMin },
	{ label = "lobby counting", check = Contract.lobbyCountingAtMin },
	{ label = "lobby full", check = Contract.lobbyFullAtMax },
	{ label = "seat helper", check = Contract.seatHelperIsTheSupplierWithTheEye },
	{ label = "seat partner", check = Contract.seatPartnerIsTheDependentWithTheKey },
	{ label = "seat you", check = Contract.seatYouHasYourHueAndNoGlyph },
	{ label = "seat samples", check = Contract.seatSamplesAreYoursWithKeyThenPartnersWithEye },
	{ label = "seat unknown id", check = Contract.seatUnknownIdRaisesNamingIt },
	{ label = "rel present", check = Contract.relationsPresent },
	{ label = "rel loading", check = Contract.relationsLoadingWhenFetchingOrUnlisted },
	{ label = "rel error", check = Contract.relationsErrorKeepsTheGlyph },
	{ label = "rel away", check = Contract.relationsAwayOverlaysWaitAndKeepsTheRelationGlyph },
	{ label = "rel helper none", check = Contract.relationsHelperNoneAfterTheHelperLeft },
	{ label = "rel partner none", check = Contract.relationsPartnerNilAfterThePartnerLeft },
	{ label = "rel dealt hues", check = Contract.relationsHuesComeFromTheDealtSeatOrder },
	{ label = "rel you", check = Contract.relationsYouIsAlwaysPresentWithNoGlyph },
	{ label = "rel unknown id", check = Contract.relationsUnknownIdRaisesNamingIt },
	{ label = "walk", check = Contract.everyOutputWalksClean },
	{ label = "words seat", check = Contract.wordsSeatMatchVoice },
	{ label = "words lobby", check = Contract.wordsLobbyMatchVoice },
}

local EXPECTED: { [string]: { string } } = {
	gtForGteAtMin = { "lobby counting" },
	fullNeverReported = { "lobby full" },
	glyphSameForEveryState = { "lobby counting", "lobby full" },
	slotsFromPlayersCount = { "lobby slots" },
	neededOffByOne = { "lobby slots" },
	hueByZeroIndex = { "lobby slots" },
	slotCarriesGlyph = { "lobby slots" },
	hueOnSlotName = { "lobby slots", "walk" },
	readsPhase = { "lobby slots" },
	lobbyMutatesView = { "lobby slots" },
	swapsSupplierDependent = { "seat helper", "seat partner", "seat samples" },
	swapsSampleGlyphs = { "seat samples" },
	samplesReversed = { "seat samples" },
	oneSample = { "seat samples" },
	hueByWrongIndex = { "seat helper", "seat partner", "seat you", "seat samples" },
	youHasGlyph = { "seat you", "walk" },
	echoesUnknownId = { "seat unknown id" },
	seatHueOnName = { "seat helper", "walk" },
	comparesSeatToItself = { "rel helper none" },
	-- "rel unknown id" is a measured extra: that check removes the id from
	-- dealt.seatOrder only, so a model indexing the current order still finds it.
	hueFromCurrentSeatOrder = { "rel helper none", "rel dealt hues", "rel unknown id" },
	missingPresenceIsPresent = { "rel loading" },
	awayDropsRelationGlyph = { "rel away", "walk" },
	awayNoOverlay = { "rel away" },
	noneKeepsPlayerId = { "rel helper none" },
	noneNotStruck = { "rel helper none" },
	helperNoneHasNoGlyph = { "rel helper none", "walk" },
	partnerNoneAsChip = { "rel partner none" },
	youStateFromPresence = { "rel loading", "rel you" },
	relUnknownIdEchoes = { "rel unknown id" },
	seatWordDrift = { "words seat" },
	extraSeatWord = { "words seat" },
	lobbyWordDrift = { "words lobby" },
}

local function failing(bundle: any): ({ string }, { [string]: string })
	local labels: { string } = {}
	local messages: { [string]: string } = {}
	for _, named in CHECKS do
		local ok, err = pcall(named.check, bundle)
		if not ok then
			table.insert(labels, named.label)
			messages[named.label] = tostring(err)
		end
	end
	return labels, messages
end

local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local x, y = table.clone(a), table.clone(b)
	table.sort(x)
	table.sort(y)
	for i, v in x do
		if y[i] ~= v then
			return false
		end
	end
	return true
end

local function has(message: string, needle: string): boolean
	return string.find(message, needle, 1, true) ~= nil
end

local tests: { [string]: () -> () } = {}

tests["baseline: a correct model passes every HUD-007 check, which also shows VoiceSpec read the live voice.md optional words"] = function()
	local labels, messages = failing(Stubs.build({}))
	local detail: { string } = {}
	for _, label in labels do
		table.insert(detail, `{label}: {messages[label]}`)
	end
	assert(#labels == 0, `the baseline failed {#labels} check(s):\n` .. table.concat(detail, "\n"))
end

tests["every defect in SeatHudStubs.DEFECTS has an expected set here, and the reverse"] = function()
	local missing: { string } = {}
	for _, defect in Stubs.DEFECTS do
		if EXPECTED[defect] == nil then
			table.insert(missing, defect)
		end
	end
	assert(#missing == 0, `no expected set for: {table.concat(missing, ", ")}`)
	local stray: { string } = {}
	for defect in EXPECTED do
		if table.find(Stubs.DEFECTS, defect) == nil then
			table.insert(stray, defect)
		end
	end
	assert(
		#stray == 0,
		`expected sets for defects the stubs do not build: {table.concat(stray, ", ")}`
	)
end

for _, defect in Stubs.DEFECTS do
	tests[`control {defect}: fails exactly [{table.concat(EXPECTED[defect] or {}, ", ")}]`] = function()
		local want = EXPECTED[defect]
		assert(want ~= nil, `no expected set for {defect}`)
		local labels, messages = failing(Stubs.build({ [defect] = true }))
		if not same(labels, want :: { string }) then
			local detail: { string } = {}
			for _, label in labels do
				table.insert(detail, `  {label}: {messages[label]}`)
			end
			error(
				`{defect} failed [{table.concat(labels, ", ")}], expected [{table.concat(
					want :: { string },
					", "
				)}]\n` .. table.concat(detail, "\n"),
				0
			)
		end
	end
end

--[[ The messages name the thing. ]]

local function failureOf(check: Check, defect: string): string
	local ok, err = pcall(check, Stubs.build({ [defect] = true }))
	assert(ok == false, `{defect} passed the check`)
	return tostring(err)
end

tests["AC-2 control: the direction error (Ring.luau's header) is reported as helper.playerId 1004 where 1002 was wanted, in both viewers"] = function()
	local message = failureOf(Contract.seatHelperIsTheSupplierWithTheEye, "swapsSupplierDependent")
	assert(
		has(message, 'viewer 1003: helper is wrong: value.playerId: expected "1002", got "1004"'),
		message
	)
	assert(has(message, 'value.hueToken: expected "color.player.2", got "color.player.4"'), message)
	assert(has(message, "2 fault(s)"), message)
end

tests["AC-2 control (DN-9): swapped sample glyphs are reported on both samples and nothing else; the hues are untouched"] = function()
	local message =
		failureOf(Contract.seatSamplesAreYoursWithKeyThenPartnersWithEye, "swapsSampleGlyphs")
	assert(has(message, 'value.1.glyph: expected "glyph.key", got "glyph.eye"'), message)
	assert(has(message, 'value.2.glyph: expected "glyph.eye", got "glyph.key"'), message)
	assert(not has(message, "hueToken"), message)
end

tests["AC-1 control: > for >= is reported at exactly playersMin (4 of 4..6 and 2 of 2..3) and nowhere else"] = function()
	local message = failureOf(Contract.lobbyCountingAtMin, "gtForGteAtMin")
	assert(
		has(message, '(4 players, min 4, max 6): state is "waiting", wanted "counting"'),
		message
	)
	assert(
		has(message, '(2 players, min 2, max 3): state is "waiting", wanted "counting"'),
		message
	)
	assert(not has(message, "(5 players"), message)
	assert(has(message, "4 fault(s)"), message) -- state and glyph, twice
end

tests["AC-3 control (PO-1): comparing the seat to itself is reported as a helper chip that still has a playerId after the helper left"] = function()
	local message =
		failureOf(Contract.relationsHelperNoneAfterTheHelperLeft, "comparesSeatToItself")
	assert(has(message, 'value.helper.playerId: unexpected "1001"'), message)
	assert(has(message, 'value.helper.state: expected "none", got "present"'), message)
end

tests["AC-3 control (PO-2): hues from the current seatOrder are reported as color.player.1/2/3 where the dealt 2/3/4 were wanted"] = function()
	local message =
		failureOf(Contract.relationsHuesComeFromTheDealtSeatOrder, "hueFromCurrentSeatOrder")
	assert(
		has(message, 'value.helper.hueToken: expected "color.player.2", got "color.player.1"'),
		message
	)
	assert(
		has(message, 'value.you.hueToken: expected "color.player.3", got "color.player.2"'),
		message
	)
	assert(
		has(message, 'value.partner.hueToken: expected "color.player.4", got "color.player.3"'),
		message
	)
end

--[[ AC-4: the walker over hand-built outputs. These need no model at all. ]]

local function cleanLobby(): any
	return {
		state = "counting",
		glyph = "glyph.notyet",
		slots = {
			{ playerId = "1001", needed = true, hueToken = "color.player.1" },
			{ playerId = "1002", needed = true, hueToken = "color.player.2" },
			{ needed = false },
		},
	}
end

local function cleanSeat(): any
	return {
		helper = { playerId = "1002", hueToken = "color.player.2", glyph = "glyph.eye" },
		you = { playerId = "1003", hueToken = "color.player.3" },
		partner = { playerId = "1004", hueToken = "color.player.4", glyph = "glyph.key" },
		samples = {
			{ hueToken = "color.player.3", glyph = "glyph.key" },
			{ hueToken = "color.player.4", glyph = "glyph.eye" },
		},
	}
end

local function cleanRelations(): any
	return {
		helper = { glyph = "glyph.eye", state = "none", struck = true },
		you = { playerId = "1003", hueToken = "color.player.3", state = "present", struck = false },
		partner = {
			playerId = "1004",
			hueToken = "color.player.4",
			glyph = "glyph.key",
			state = "away",
			struck = false,
			overlay = "glyph.wait",
		},
	}
end

tests["AC-4 walker baseline: a clean lobby, seat card and relations output (partner nil too) each walk with 0 violations"] = function()
	local noPartner = cleanRelations()
	noPartner.partner = nil
	for _, case in
		{
			{ "lobby", cleanLobby() },
			{ "seat", cleanSeat() },
			{ "relations", cleanRelations() },
			{ "relations", noPartner },
		}
	do
		local violations = Contract.walk(case[1] :: any, case[2])
		assert(
			#violations == 0,
			`{case[1]}: {#violations} violation(s):\n{table.concat(violations, "\n")}`
		)
	end
end

tests["AC-4 walker control (DN-3): color.player.2 under textColour on a lobby slot is reported, naming the path, and the hueToken beside it is not"] = function()
	local output = cleanLobby()
	output.slots[2].textColour = "color.player.2"
	local violations = Contract.walk("lobby", output)
	assert(#violations == 1, `{#violations} violation(s):\n{table.concat(violations, "\n")}`)
	assert(has(violations[1], 'lobby.slots.2.textColour = "color.player.2"'), violations[1])
	assert(has(violations[1], "other than hueToken"), violations[1])
end

tests["AC-4 walker control (DN-3): a player hue nested two levels down under any other key is reported in a seat card"] = function()
	local output = cleanSeat()
	output.samples[1].labelColour = "color.player.3"
	local violations = Contract.walk("seat", output)
	assert(#violations == 1, `{#violations} violation(s):\n{table.concat(violations, "\n")}`)
	assert(has(violations[1], 'seat.samples.1.labelColour = "color.player.3"'), violations[1])
end

tests["AC-4 walker control (PT-A7): a nil glyph on a present partner chip is reported, and so is a nil glyph on a none helper"] = function()
	local output = cleanRelations()
	output.partner.glyph = nil
	output.helper.glyph = nil
	local violations = Contract.walk("relations", output)
	assert(#violations == 2, `{#violations} violation(s):\n{table.concat(violations, "\n")}`)
	table.sort(violations)
	assert(has(violations[1], "relations.helper.glyph is nil"), violations[1])
	assert(has(violations[2], "relations.partner.glyph is nil"), violations[2])
end

tests["AC-4 walker control (PT-A7): a lobby output with no glyph, and a seat sample with none, are each reported"] = function()
	local lobby = cleanLobby()
	lobby.glyph = nil
	local lobbyViolations = Contract.walk("lobby", lobby)
	assert(
		#lobbyViolations == 1 and has(lobbyViolations[1], "lobby.glyph is nil"),
		table.concat(lobbyViolations, "\n")
	)
	local seat = cleanSeat()
	seat.samples[2].glyph = nil
	local seatViolations = Contract.walk("seat", seat)
	assert(
		#seatViolations == 1 and has(seatViolations[1], "seat.samples[2].glyph is nil"),
		table.concat(seatViolations, "\n")
	)
end

tests["AC-4 walker control (DN-4): you.glyph = glyph.key is reported in a seat card and in a relations strip"] = function()
	local seat = cleanSeat()
	seat.you.glyph = "glyph.key"
	local seatViolations = Contract.walk("seat", seat)
	assert(
		#seatViolations == 1 and has(seatViolations[1], 'seat.you.glyph is "glyph.key", wanted nil'),
		table.concat(seatViolations, "\n")
	)
	local relations = cleanRelations()
	relations.you.glyph = "glyph.eye"
	local relViolations = Contract.walk("relations", relations)
	assert(
		#relViolations == 1
			and has(relViolations[1], 'relations.you.glyph is "glyph.eye", wanted nil'),
		table.concat(relViolations, "\n")
	)
end

tests["AC-4 walker control: a glyph that is not in Theme.icons.system (glyph.helper) and an overlay that is not (glyph.away) are each reported"] = function()
	local output = cleanRelations()
	output.partner.glyph = "glyph.helper"
	output.partner.overlay = "glyph.away"
	local violations = Contract.walk("relations", output)
	assert(#violations == 2, `{#violations} violation(s):\n{table.concat(violations, "\n")}`)
	table.sort(violations)
	assert(has(violations[1], '"glyph.helper": not a member of Theme.icons.system'), violations[1])
	assert(has(violations[2], '"glyph.away": not a member of Theme.icons.system'), violations[2])
end

--[[ The words reader's discrimination, over fixtures. ]]

local FIXTURE = table.concat({
	"## 2. The words",
	"",
	"| rematch | Again | `glyph.again` |",
	"",
	'Seat card (C-05): "Your helper", "You", "You help", "Yours to turn", "You can see',
	'these". Dial control (C-16): "Turn". Lobby (C-26): "Waiting for friends". Outcome',
	"words: `components.md` C-24.",
	"",
	"### 2.1 The phase label",
}, "\n")

tests["VoiceSpec.parseQuotedWords: reads the five seat-card words after their label, joining the wrapped one, and stops at the full stop"] = function()
	local words = VoiceSpec.parseQuotedWords(FIXTURE, "Seat card (C-05):")
	assert(#words == 5, `read {#words} words, wanted 5: {table.concat(words, " | ")}`)
	assert(words[1] == "Your helper", words[1])
	assert(words[5] == "You can see these", words[5])
	local lobby = VoiceSpec.parseQuotedWords(FIXTURE, "Lobby (C-26):")
	assert(#lobby == 1 and lobby[1] == "Waiting for friends", table.concat(lobby, " | "))
end

tests["VoiceSpec.parseQuotedWords: a label the text does not contain reads zero words, and the contract check reports that as vacuity rather than passing"] = function()
	local words = VoiceSpec.parseQuotedWords(FIXTURE, "Spectator (C-27):")
	assert(#words == 0, `read {#words} words under a label that is not there`)
	local live = VoiceSpec.parseQuotedWords(VoiceSpec.read(), "Spectator (C-27):")
	assert(
		#live == 0,
		`the live voice.md has a "Spectator (C-27):" label now; this control needs a different absent label`
	)
end

tests["VoiceSpec.parseQuotedWords: the live voice.md yields 5 seat-card words and 1 lobby word, read through the gate hash"] = function()
	local text = VoiceSpec.read()
	local seat = VoiceSpec.parseQuotedWords(text, Contract.SEAT_LABEL)
	local lobby = VoiceSpec.parseQuotedWords(text, Contract.LOBBY_LABEL)
	assert(
		#seat == #Contract.SEAT_KEYS,
		`voice.md: {#seat} seat-card words, the Contract names {#Contract.SEAT_KEYS} keys: {table.concat(
			seat,
			" | "
		)}`
	)
	assert(
		#lobby == #Contract.LOBBY_KEYS,
		`voice.md: {#lobby} lobby words, the Contract names {#Contract.LOBBY_KEYS} keys: {table.concat(
			lobby,
			" | "
		)}`
	)
	for _, word in seat do
		assert(
			word ~= "" and string.find(word, "\n", 1, true) == nil,
			`a seat-card word is empty or carries a newline: {word}`
		)
	end
end

return tests
