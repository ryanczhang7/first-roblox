--!strict
--[[
	The negative controls for CHAN-004 AC-1, AC-2, AC-3, AC-4's guarded half
	and AC-7, and the proof that each check in
	`tests/helpers/PresetRemoteContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`GameRemotes.SendPreset` is not declared and `PresetSends.luau` does not
	exist, every test in `tests/net/preset_remote_test.luau` fails before its
	assertion runs, and so not one of that file's checks has been observed to
	accept or reject anything. The declarations below need only `Schema`,
	`Remotes`, `Wrapper`, `MechanicsTuning`, `Presets` and `tuning.md`, and
	the guarded controls need `PresetSendsStubs.luau`, all merged or
	test-side, so what is asserted here is MEASURED in RED rather than
	claimed for GREEN. The story's handoff carries the table.

	THE REFERENCE is the Contract's own spec - `{ preset = integer(1,
	preset_count) }`, the derived phase union, `preset_rate_limit_seconds`,
	`channel_attempt_min_interval_seconds` - declared through the REAL
	`Remotes.define` under a unique name (never `"SendPreset"`: the registry
	is process-wide and the real module declares that one). Every check must
	ACCEPT it, or the check is wrong and the fix belongs HERE, in RED. Each
	control is the reference with EXACTLY ONE thing changed, so the set of
	checks that fire is attributable to that one change, and each control
	pins that set EXACTLY.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a declaration at 9.5 must fail,
	naming both numbers" - `rate9point5`, whose message is asserted to carry
	9.5 and 10. AC-7: "a declaration keyed per preset (ten limiters) must
	fail this AC" - `declarePerPreset`, ten reference declarations behind a
	dispatcher (C-7), run against AC-7's check over `PresetSendsStubs.reference`.
	D-1's shape (the rate mutated to a literal) is `rate9point5` too; D-5's
	shape (the rate set to the attempt floor) is `rateIsTheAttemptFloor`.
	D-1 and D-5 THEMSELVES stay with GATES.

	WHAT THIS IS NOT: `src/net/GameRemotes.luau`, or a sketch of one.
]]

local Contract = require("../helpers/PresetRemoteContract")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local PhaseUnion = require("../helpers/PhaseUnion")
local Presets = require("../../src/shared/channel/Presets")
local PresetSendsStubs = require("../helpers/PresetSendsStubs")
local RateLimitSpec = require("../helpers/RateLimitSpec")
local Remotes = require("../../src/net/Remotes")
local Schema = require("../../src/net/Schema")
local Wrapper = require("../../src/net/Wrapper")

local net: Contract.Net = { Schema = Schema, Remotes = Remotes, Wrapper = Wrapper }

local function declare(label: string, edits: Contract.Edits): any
	return Contract.declare(net, label, edits)
end

local function failingNames(definition: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(net, definition) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, definition: any, expected: { string }): { [string]: string }
	local names, messages = failingNames(definition)
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {who} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{who} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: Contract.Check } = {}
	for _, check in Contract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{who}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

local RATE_DOC = "rateLimitIsThePresetRateLimitTheDocumentFixes"
local ATTEMPT = "attemptLimitIsTheChannelAttemptFloorFromTuning"
local LISTED = "isTheDefinitionRemotesAllLists"
local ATTEMPT_RATE = "secondCallInsideTheAttemptFloorIsRejectedForRate"
local SCHEMA = "schemaIsExactlyPresetIntegerOneToPresetCount"
local MALFORMED = "malformedCallsAreRejectedBeforeTheHandler"
local PHASES = "legalPhasesAreTheUnionOfThePresetTablesPhases"
local OUT_OF_UNION = "wellFormedCallOutsideTheUnionIsRejectedForPhase"
local IN_UNION = "wellFormedCallInEachLegalPhaseReachesTheHandler"

-- AC-4's guarded check over a subject and a PresetSends module; the message
-- when it fires, or nil.
local function ac4Failure(subject: any, P: any): string?
	local ok, err = pcall(function(): any
		Contract.outOfPhasePresetIsDeclinedAndTheNextLegalPresetAtTheAttemptFloorIsShown(
			net,
			subject,
			P
		)
		return nil
	end)
	if ok then
		return nil
	end
	return tostring(err)
end

-- AC-7's guarded check, likewise.
local function ac7Failure(subject: any, P: any): string?
	local ok, err = pcall(function(): any
		Contract.twoPlayersAreBothShownAndOnePlayersSecondPresetInsideTheLimitIsRate(
			net,
			subject,
			P
		)
		return nil
	end)
	if ok then
		return nil
	end
	return tostring(err)
end

return {
	--[[ ================================================================
	     The reference. Everything below is this declaration with one edit.
	     ================================================================ ]]

	["baseline: the reference declaration - the Contract's spec under a unique name - passes every check in PresetRemoteContract"] = function()
		local names, messages = failingNames(declare("reference", {}))
		if #names > 0 then
			local shown: { string } = {}
			for _, name in names do
				table.insert(shown, `{name}: {messages[name]}`)
			end
			error(
				`the reference fails {#names} check(s), so the check or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	--[[ ================================================================
	     The fixture's assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: tuning.md and MechanicsTuning agree on preset_rate_limit_seconds (10), the floor is 10, preset_count is 10, the attempt floor (1) sits between EPSILON and the rate, the derived union is { Lobby, Round, Post } and the phases outside it are { Assignment, Resolution }"] = function()
		local document = Contract.documentRateLimitSeconds()
		local rate = Contract.rateLimitSeconds()
		local attempt = Contract.attemptSeconds()
		local eps = Contract.EPSILON
		local problems: { string } = {}
		if document ~= 10 then
			table.insert(
				problems,
				`tuning.md fixes preset_rate_limit_seconds at {document}, the story says 10`
			)
		end
		if rate ~= document then
			table.insert(
				problems,
				`MechanicsTuning.channel.preset_rate_limit_seconds is {rate}, tuning.md says {document}`
			)
		end
		if RateLimitSpec.FLOOR_SECONDS ~= 10 then
			table.insert(
				problems,
				`RateLimitSpec.FLOOR_SECONDS is {RateLimitSpec.FLOOR_SECONDS}, not 10`
			)
		end
		if Contract.presetCount() ~= 10 or Contract.presetCount() ~= #Presets.ALL then
			table.insert(
				problems,
				`preset_count is {Contract.presetCount()} and Presets.ALL has {#Presets.ALL} rows; the story says 10`
			)
		end
		if attempt ~= 1 then
			table.insert(
				problems,
				`channel_attempt_min_interval_seconds is {attempt}, the story says 1`
			)
		end
		if not (eps > 0 and eps < attempt and attempt < rate) then
			table.insert(problems, `need 0 < EPSILON ({eps}) < attempt ({attempt}) < rate ({rate})`)
		end
		local legal = Contract.legalPhases()
		if not Deep.equal(legal, { "Lobby", "Round", "Post" }) then
			table.insert(
				problems,
				`the derived union is {Deep.show(legal)}, C-2 says Lobby, Round, Post`
			)
		end
		local illegal = Contract.illegalPhases()
		if not Deep.equal(illegal, { "Assignment", "Resolution" }) then
			table.insert(
				problems,
				`the phases outside the union are {Deep.show(illegal)}, expected Assignment, Resolution`
			)
		end
		-- The union is a union: the full phase list is longer than it.
		if #PhaseUnion.KNOWN ~= #legal + #illegal then
			table.insert(
				problems,
				`PhaseUnion.KNOWN has {#PhaseUnion.KNOWN} phases; legal + illegal is {#legal + #illegal}`
			)
		end
		assert(
			#problems == 0,
			`the fixture no longer discriminates:\n{table.concat(problems, "\n")}`
		)
		print(
			`        [measured] document {document}, module {rate}, floor {RateLimitSpec.FLOOR_SECONDS}, attempt {attempt}, EPSILON {eps}, union {Deep.show(
				legal
			)}`
		)
	end,

	--[[ ================================================================
	     AC-1's settled rate (the named control, and D-1's shape).
	     ================================================================ ]]

	["control (AC-1, required; D-1's shape): a declaration at 9.5 fails the rate check naming 9.5 and 10, and the attempt-floor sequence (the call at exactly the floor quotes 9.5), nothing else"] = function()
		local messages =
			expectFires("rate9point5", declare("rate9point5", { rateLimitSeconds = 9.5 }), {
				RATE_DOC,
				ATTEMPT_RATE,
			})
		contains(
			messages[RATE_DOC],
			"SendPreset.rateLimit is { minIntervalSeconds = 9.5 }",
			"the declared 9.5"
		)
		contains(messages[RATE_DOC], "expected { minIntervalSeconds = 10 }", "the document's 10")
		contains(messages[RATE_DOC], "below RateLimitSpec.FLOOR_SECONDS = 10", "the floor")
		contains(
			messages[ATTEMPT_RATE],
			"one call per 9.5 s per player",
			"the 9.5 in the send detail"
		)
	end,

	["control: minIntervalSeconds = preset_rate_limit_seconds + 1 fails the rate check (above the floor, but not the document's value) and the attempt-floor sequence"] = function()
		local messages = expectFires(
			"rateLimitPlusOne",
			declare("rateLimitPlusOne", { rateLimitSeconds = Contract.rateLimitSeconds() + 1 }),
			{ RATE_DOC, ATTEMPT_RATE }
		)
		contains(
			messages[RATE_DOC],
			"SendPreset.rateLimit is { minIntervalSeconds = 11 }",
			"the declared 11"
		)
		assert(
			string.find(messages[RATE_DOC], "below RateLimitSpec.FLOOR_SECONDS", 1, true) == nil,
			`11 is not below the floor, but the message says so:\n{messages[RATE_DOC]}`
		)
	end,

	["control: no rateLimit at all fails the rate check and the attempt-floor sequence - the call at the floor reaches the handler"] = function()
		local messages = expectFires(
			"noRateLimit",
			declare("noRateLimit", { noRateLimit = true }),
			{ RATE_DOC, ATTEMPT_RATE }
		)
		contains(messages[RATE_DOC], "SendPreset.rateLimit is nil", "the missing limit")
	end,

	--[[ ================================================================
	     AC-1's attempt floor.
	     ================================================================ ]]

	["control (C-10): no attemptLimit fails the attempt-limit check and the attempt-floor sequence (the 0.9 s call is refused with the SEND detail, not the attempt detail), and nothing else"] = function()
		local messages = expectFires(
			"noAttemptLimit",
			declare("noAttemptLimit", { noAttemptLimit = true }),
			{ ATTEMPT, ATTEMPT_RATE }
		)
		contains(messages[ATTEMPT], "SendPreset.attemptLimit is nil", "the missing floor")
		contains(
			messages[ATTEMPT_RATE],
			"is limited to one call per 10 s per player",
			"the send detail where the attempt detail was expected"
		)
	end,

	["control: an attempt floor of channel_attempt_min_interval_seconds + 1 fails the attempt-limit check and the attempt-floor sequence"] = function()
		expectFires(
			"attemptPlusOne",
			declare("attemptPlusOne", { attemptSeconds = Contract.attemptSeconds() + 1 }),
			{ ATTEMPT, ATTEMPT_RATE }
		)
	end,

	--[[ ================================================================
	     AC-3's phases (C-10: an extra phase, a missing phase).
	     ================================================================ ]]

	["control (C-10): legalPhases with Assignment added fails the phases check and AC-3's refusal half - an Assignment call reaches the handler - and nothing else"] = function()
		local messages = expectFires(
			"legalInAssignmentToo",
			declare(
				"legalInAssignmentToo",
				{ legalPhases = { "Lobby", "Assignment", "Round", "Post" } }
			),
			{ PHASES, OUT_OF_UNION }
		)
		contains(
			messages[OUT_OF_UNION],
			"a well-formed call while the phase is Assignment -> ACCEPTED",
			"the Assignment call"
		)
	end,

	["control (C-10): legalPhases without Post fails the phases check and AC-3's positive control - a Post call is rejected for phase - and nothing else"] = function()
		local messages = expectFires(
			"missingPost",
			declare("missingPost", { legalPhases = { "Lobby", "Round" } }),
			{ PHASES, IN_UNION }
		)
		contains(messages[IN_UNION], "in Post -> REJECTED", "the Post call")
	end,

	["control: legalPhases in the wrong order ({ Round, Lobby, Post }) fails exactly the phases check - the set is right, the order is C-2's"] = function()
		expectFires(
			"unorderedPhases",
			declare("unorderedPhases", { legalPhases = { "Round", "Lobby", "Post" } }),
			{ PHASES }
		)
	end,

	--[[ ================================================================
	     AC-2's schema (C-10: a bound one too high, number(), an optional to).
	     ================================================================ ]]

	["control (C-10): a preset bound of preset_count + 1 fails the schema check and AC-2's guarded half - preset = 11 reaches the handler"] = function()
		local messages = expectFires(
			"presetUpperBoundPlusOne",
			declare("presetUpperBoundPlusOne", { presetMax = Contract.presetCount() + 1 }),
			{ SCHEMA, MALFORMED }
		)
		contains(messages[MALFORMED], "preset = 11 (preset_count + 1) -> ACCEPTED", "the 11")
	end,

	["control (C-10): preset declared as number() rather than integer() fails the schema check and AC-2's guarded half - preset = 1.5 reaches the handler"] = function()
		local messages = expectFires(
			"presetIsNumber",
			declare("presetIsNumber", { presetIsNumber = true }),
			{ SCHEMA, MALFORMED }
		)
		contains(messages[MALFORMED], "preset = 1.5 -> ACCEPTED", "the 1.5")
	end,

	["control (C-10, C9): a schema admitting an optional `to` fails the schema check and AC-2's guarded half - a recipient reaches the handler - and nothing else"] = function()
		local messages = expectFires("acceptsTo", declare("acceptsTo", { acceptsTo = true }), {
			SCHEMA,
			MALFORMED,
		})
		contains(messages[SCHEMA], 'to = "lee" } (a recipient) -> accepted', "the recipient")
		contains(
			messages[MALFORMED],
			'a recipient: { preset = 1, to = "lee" } -> ACCEPTED',
			"the recipient through the guard"
		)
	end,

	["control: a hand-built copy of the reference that was never passed through Remotes.define fails exactly the registry check - all() must list the table itself"] = function()
		local reference = declare("copied", {})
		expectFires("unregisteredCopy", table.clone(reference), { LISTED })
	end,

	--[[ ================================================================
	     AC-4 through the real guard: the reference over PresetSends stubs.
	     ================================================================ ]]

	["baseline (AC-4): the reference declaration guarded over the reference PresetSends passes the out-of-phase-then-legal sequence"] = function()
		local failure = ac4Failure(declare("ac4reference", {}), PresetSendsStubs.reference)
		assert(
			failure == nil,
			`the AC-4 sequence fails on the reference, so the check or the fixture is wrong:\n{tostring(
				failure
			)}`
		)
		print("        [measured] AC-4 guarded sequence: reference passes")
	end,

	["control (AC-4): the same sequence over a send whose phase refusal does not decline is rejected for rate on the legal preset at the attempt floor"] = function()
		local failure =
			ac4Failure(declare("ac4noDecline", {}), PresetSendsStubs.with("noDeclineOnPhase"))
		assert(failure ~= nil, "the AC-4 sequence passed over a phase refusal that never declines")
		local message = failure :: string
		print(`        [measured] AC-4 guarded sequence over noDeclineOnPhase:\n{message}`)
		contains(
			message,
			"the out-of-phase preset at t -> the guard answered nil",
			"the undeclined first call"
		)
		contains(message, 'reason = "rate" }, expected nil (accepted)', "rate on the legal preset")
	end,

	["control (AC-4, D-4's shape): the same sequence over a send that skips the phase check shows Well played in Round - the guard accepts the first call and the state holds its entry"] = function()
		local failure =
			ac4Failure(declare("ac4skipsPhase", {}), PresetSendsStubs.with("skipsPhaseCheck"))
		assert(failure ~= nil, "the AC-4 sequence passed over a send with no phase check")
		local message = failure :: string
		contains(
			message,
			"the out-of-phase preset at t -> the guard answered nil",
			"the accepted first call"
		)
		contains(message, 'send returned { kind = "shown"', "it was shown")
	end,

	["control (AC-4): the same sequence over a send that calls the filter for an out-of-phase preset fails on the filter count"] = function()
		local failure = ac4Failure(
			declare("ac4filtersOutOfPhase", {}),
			PresetSendsStubs.with("filtersOutOfPhase")
		)
		assert(
			failure ~= nil,
			"the AC-4 sequence passed over a send that filters out-of-phase presets"
		)
		contains(
			failure :: string,
			"the filter was called 1 time(s) for the out-of-phase preset; expected never",
			"the filter count"
		)
	end,

	--[[ ================================================================
	     AC-7 through the real guard: one limiter across the wheel.
	     ================================================================ ]]

	["baseline (AC-7): the reference declaration guarded over the reference PresetSends passes the two-players-then-second-preset sequence"] = function()
		local failure = ac7Failure(declare("ac7reference", {}), PresetSendsStubs.reference)
		assert(
			failure == nil,
			`the AC-7 sequence fails on the reference, so the check or the fixture is wrong:\n{tostring(
				failure
			)}`
		)
		print("        [measured] AC-7 guarded sequence: reference passes")
	end,

	["control (AC-7, required): ten per-preset limiters behind a dispatcher let one player's second, different preset through 5 s later - the AC-7 check fails on the accepted call and the handler count"] = function()
		local perPreset = Contract.declarePerPreset(net, "ac7perPreset")
		assert(
			#perPreset.definitions == Contract.presetCount(),
			"the control did not declare one remote per preset"
		)
		local failure = ac7Failure(perPreset, PresetSendsStubs.reference)
		assert(failure ~= nil, "the AC-7 sequence passed over ten per-preset limiters")
		local message = failure :: string
		print(`        [measured] AC-7 guarded sequence over ten per-preset limiters:\n{message}`)
		contains(
			message,
			"at t + 5 (inside preset_rate_limit_seconds = 10) -> ACCEPTED",
			"the second preset got through"
		)
		contains(message, "the handler ran 3 time(s) in total; expected 2", "the handler count")
		-- And the dispatcher is otherwise the reference: every per-definition check accepts guard 1's definition.
		local names = failingNames(perPreset.definitions[1])
		assert(
			#names == 0,
			`the per-preset control's first definition fails {Deep.show(names)}; it must be the reference`
		)
	end,

	["control (D-5's shape): a send limit equal to the attempt floor lets the second preset through 5 s later - the AC-7 check fails, and the rate check names the floor's 1 against the document's 10"] = function()
		local definition =
			declare("rateIsTheAttemptFloor", { rateLimitSeconds = Contract.attemptSeconds() })
		local failure = ac7Failure(definition, PresetSendsStubs.reference)
		assert(failure ~= nil, "the AC-7 sequence passed with the send limit at the attempt floor")
		contains(
			failure :: string,
			'-> ACCEPTED (returned nil); expected a "rate" rejection',
			"the second preset got through"
		)
		local messages =
			expectFires("rateIsTheAttemptFloor", definition, { RATE_DOC, ATTEMPT_RATE })
		contains(
			messages[RATE_DOC],
			"SendPreset.rateLimit is { minIntervalSeconds = 1 }",
			"the declared 1"
		)
		contains(messages[RATE_DOC], "expected { minIntervalSeconds = 10 }", "the document's 10")
	end,

	["control (AC-7): the sequence over a send that declines a shown preset refunds every send - the second preset is accepted rather than rate"] = function()
		local failure =
			ac7Failure(declare("ac7declinesOnShown", {}), PresetSendsStubs.with("declinesOnShown"))
		assert(failure ~= nil, "the AC-7 sequence passed over a send that declines shown presets")
		contains(failure :: string, "sends preset", "the sequence")
		contains(failure :: string, 'REJECTED: reason = "declined"', "the first send was declined")
	end,

	["fixtures (AC-7): MechanicsTuning.channel.preset_count is 10, so the per-preset control declares ten remotes"] = function()
		assert(
			MechanicsTuning.channel.preset_count == 10,
			`preset_count is {MechanicsTuning.channel.preset_count}`
		)
	end,
}
