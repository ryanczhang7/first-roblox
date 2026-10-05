--!strict
--[[
	The negative controls for CHAN-005 AC-1, AC-2 and AC-4's guarded half, and
	the proof that each check in `tests/helpers/PingRemoteContract.luau` - and
	`PingsContract.refusedPingIsDeclinedAndTheNextValidPingInsideTheSendLimitIsAccepted`
	- means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `GameRemotes.Ping`
	is not declared and `Pings.luau` does not exist, every test in
	`tests/net/ping_remote_test.luau` fails before its assertion runs, and so
	not one of that file's checks has been observed to accept or reject
	anything. The declarations below need only `Schema`, `Remotes`, `Wrapper`,
	`MechanicsTuning` and `tuning.md`, and the AC-4 controls need
	`PingsStubs.luau`, all merged or test-side, so what is asserted here is
	MEASURED in RED rather than claimed for GREEN. The story's handoff carries
	the table.

	THE REFERENCE is the Contract's own spec - `{ kind = literal(setting,
	machine, doorway), target = integer(1, actuator_count), setting =
	optional(integer(1, dial_settings)) }`, `{ "Round" }`,
	`ping_rate_limit_seconds`, `channel_attempt_min_interval_seconds` -
	declared through the REAL `Remotes.define` under a unique name (never
	`"Ping"`: the registry is process-wide and the real module declares that
	one). Every check must ACCEPT it, or the check is wrong and the fix belongs
	HERE, in RED. Each control is the reference with EXACTLY ONE thing changed,
	so the set of checks that fire is attributable to that one change, and
	each control pins that set EXACTLY.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a declaration at a literal 3 (the
	superseded placeholder) must fail, naming 3 and 10" - `rateLiteral3`,
	whose message is asserted to carry both numbers. AC-4: "the same sequence
	with a handler that does not decline must be rejected for rate" - the
	reference declaration guarded over `PingsStubs.with("noDecline")`. D-1's
	shape (the rate mutated to 3) is `rateLiteral3` too; D-1 ITSELF stays with
	GATES.

	WHAT THIS IS NOT: `src/net/GameRemotes.luau`, or a sketch of one.
]]

local Contract = require("../helpers/PingRemoteContract")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local PingsContract = require("../helpers/PingsContract")
local PingsStubs = require("../helpers/PingsStubs")
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

local SCHEMA = "schemaIsKindTargetAndOptionalSettingAtTheTuningBounds"
local PHASES = "legalPhasesAreExactlyRound"
local RATE_DOC = "rateLimitIsThePingRateLimitTheDocumentFixes"
local ATTEMPT = "attemptLimitIsTheChannelAttemptFloorFromTuning"
local LISTED = "isTheDefinitionRemotesAllLists"
local MALFORMED = "malformedCallsAreRejectedBeforeTheHandler"
local OUT_OF_PHASE = "wellFormedCallOutOfRoundIsRejectedForPhase"
local ATTEMPT_RATE = "secondCallInsideTheAttemptFloorIsRejectedForRate"
local SEND_RATE = "secondAcceptedCallInsideTheSendLimitIsRejectedForRate"
local POSITIVE = "wellFormedCallInRoundReachesTheHandlerWithTheValidatedArgs"

-- The AC-4 guarded check over a reference declaration and a Pings module;
-- the message when it fires, or nil.
local function guardedFailure(label: string, P: any): string?
	local definition = declare(label, {})
	local ok, err = pcall(function(): any
		PingsContract.refusedPingIsDeclinedAndTheNextValidPingInsideTheSendLimitIsAccepted(
			net,
			definition,
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

	["baseline: the reference declaration - the Contract's spec under a unique name - passes every check in PingRemoteContract"] = function()
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

	["fixtures: tuning.md and MechanicsTuning agree on ping_rate_limit_seconds (10), the floor is 10, the attempt floor (1) sits between EPSILON and the rate, and the four-call send sequence fits"] = function()
		local document = Contract.documentRateLimitSeconds()
		local rate = Contract.rateLimitSeconds()
		local attempt = Contract.attemptSeconds()
		local eps = Contract.EPSILON
		local problems: { string } = {}
		if document ~= 10 then
			table.insert(
				problems,
				`tuning.md fixes ping_rate_limit_seconds at {document}, the story says 10`
			)
		end
		if rate ~= document then
			table.insert(
				problems,
				`MechanicsTuning.channel.ping_rate_limit_seconds is {rate}, tuning.md says {document}`
			)
		end
		if RateLimitSpec.FLOOR_SECONDS ~= 10 then
			table.insert(
				problems,
				`RateLimitSpec.FLOOR_SECONDS is {RateLimitSpec.FLOOR_SECONDS}, not 10`
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
		if not (attempt + eps < rate - attempt) then
			table.insert(
				problems,
				`the send sequence's second call ({attempt + eps}) is not before its third ({rate - attempt})`
			)
		end
		local w = Contract.wellFormedSetting()
		local m = Contract.wellFormedAtTheMaximum()
		local instance = MechanicsTuning.instance
		if
			not (
				w.target > 1
				and w.target <= instance.actuator_count
				and w.setting > 1
				and w.setting <= instance.dial_settings
			)
		then
			table.insert(
				problems,
				`wellFormedSetting() {Deep.show(w)} is not off both lower bounds and inside both domains`
			)
		end
		if m.target ~= instance.actuator_count or m.setting ~= instance.dial_settings then
			table.insert(problems, `wellFormedAtTheMaximum() is {Deep.show(m)}, not the two maxima`)
		end
		assert(
			#problems == 0,
			`the fixture no longer discriminates:\n{table.concat(problems, "\n")}`
		)
		print(
			`        [measured] document {document}, module {rate}, floor {RateLimitSpec.FLOOR_SECONDS}, attempt {attempt}, EPSILON {eps}`
		)
	end,

	--[[ ================================================================
	     AC-1's settled rate (the named control, and D-1's shape).
	     ================================================================ ]]

	["control (AC-1, required; D-1's shape): a declaration at the superseded literal 3 fails the rate check naming 3 and 10, and both rate-sequence checks (their details quote 3 and the 9 s call is accepted)"] = function()
		local messages =
			expectFires("rateLiteral3", declare("rateLiteral3", { rateLimitSeconds = 3 }), {
				RATE_DOC,
				ATTEMPT_RATE,
				SEND_RATE,
			})
		contains(
			messages[RATE_DOC],
			"Ping.rateLimit is { minIntervalSeconds = 3 }",
			"the declared 3"
		)
		contains(messages[RATE_DOC], "expected { minIntervalSeconds = 10 }", "the document's 10")
		contains(messages[RATE_DOC], "below RateLimitSpec.FLOOR_SECONDS = 10", "the floor")
		contains(messages[SEND_RATE], "the third call at t + 9", "the 9 s call")
	end,

	["control: minIntervalSeconds = ping_rate_limit_seconds + 1 fails the rate check (above the floor, but not the document's value) and both rate-sequence checks (the call at exactly t + 10 is refused)"] = function()
		local messages = expectFires(
			"rateLimitPlusOne",
			declare("rateLimitPlusOne", { rateLimitSeconds = Contract.rateLimitSeconds() + 1 }),
			{ RATE_DOC, ATTEMPT_RATE, SEND_RATE }
		)
		contains(
			messages[RATE_DOC],
			"Ping.rateLimit is { minIntervalSeconds = 11 }",
			"the declared 11"
		)
		assert(
			string.find(messages[RATE_DOC], "below RateLimitSpec.FLOOR_SECONDS", 1, true) == nil,
			`11 is not below the floor, but the message says so:\n{messages[RATE_DOC]}`
		)
		contains(messages[SEND_RATE], "the fourth call at exactly t + 10", "the boundary call")
	end,

	["control: no rateLimit at all fails the rate check and both rate-sequence checks - the second call reaches the handler"] = function()
		expectFires(
			"noRateLimit",
			declare("noRateLimit", { noRateLimit = true }),
			{ RATE_DOC, ATTEMPT_RATE, SEND_RATE }
		)
	end,

	--[[ ================================================================
	     AC-1's attempt floor.
	     ================================================================ ]]

	["control: no attemptLimit fails the attempt-limit check and the attempt-floor sequence (the 0.9 s call is refused with the SEND detail, not the attempt detail), and nothing else"] = function()
		local messages = expectFires(
			"noAttemptLimit",
			declare("noAttemptLimit", { noAttemptLimit = true }),
			{ ATTEMPT, ATTEMPT_RATE }
		)
		contains(messages[ATTEMPT], "Ping.attemptLimit is nil", "the missing floor")
		contains(
			messages[ATTEMPT_RATE],
			"is limited to one call per 10 s per player",
			"the send detail where the attempt detail was expected"
		)
	end,

	["control: an attempt floor of channel_attempt_min_interval_seconds + 1 fails the attempt-limit check and both rate-sequence checks"] = function()
		expectFires(
			"attemptPlusOne",
			declare("attemptPlusOne", { attemptSeconds = Contract.attemptSeconds() + 1 }),
			{ ATTEMPT, ATTEMPT_RATE, SEND_RATE }
		)
	end,

	--[[ ================================================================
	     AC-1's phases, schema and registry.
	     ================================================================ ]]

	["control: legalPhases { Round, Lobby } fails the phases check and AC-2's phase half - a Lobby call reaches the handler - and nothing else"] = function()
		expectFires(
			"legalInLobbyToo",
			declare("legalInLobbyToo", { legalPhases = { "Round", "Lobby" } }),
			{ PHASES, OUT_OF_PHASE }
		)
	end,

	["control: a target bound of actuator_count + 1 fails the schema check and AC-2 - target = 17 reaches the handler"] = function()
		expectFires(
			"targetUpperBoundPlusOne",
			declare(
				"targetUpperBoundPlusOne",
				{ targetMax = MechanicsTuning.instance.actuator_count + 1 }
			),
			{ SCHEMA, MALFORMED }
		)
	end,

	["control: target declared as number() rather than integer() fails the schema check and AC-2 - target = 1.5 reaches the handler"] = function()
		expectFires(
			"targetIsNumber",
			declare("targetIsNumber", { targetIsNumber = true }),
			{ SCHEMA, MALFORMED }
		)
	end,

	["control: a fourth kind literal, floor, fails the schema check and AC-2 - kind = floor reaches the handler"] = function()
		expectFires(
			"kindsIncludeFloor",
			declare("kindsIncludeFloor", { kinds = { "setting", "machine", "doorway", "floor" } }),
			{ SCHEMA, MALFORMED }
		)
	end,

	["control: a schema admitting an optional position field fails the schema check and AC-2 - the extra position reaches the handler"] = function()
		expectFires(
			"acceptsPosition",
			declare("acceptsPosition", { acceptsPosition = true }),
			{ SCHEMA, MALFORMED }
		)
	end,

	["control: setting declared required rather than optional fails the schema check and every check that sends a machine or doorway ping without one"] = function()
		expectFires("settingRequired", declare("settingRequired", { settingRequired = true }), {
			SCHEMA,
			MALFORMED,
			OUT_OF_PHASE,
			ATTEMPT_RATE,
			SEND_RATE,
			POSITIVE,
		})
	end,

	["control: an empty schema rejects every payload as shape - it fails the schema check, AC-2's range cases, the phase and both rate halves (never reached) and the positive control"] = function()
		expectFires("emptySchema", declare("emptySchema", { emptySchema = true }), {
			SCHEMA,
			MALFORMED,
			OUT_OF_PHASE,
			ATTEMPT_RATE,
			SEND_RATE,
			POSITIVE,
		})
	end,

	["control: a hand-built copy of the reference that was never passed through Remotes.define fails exactly the registry check - all() must list the table itself"] = function()
		local reference = declare("copied", {})
		expectFires("unregisteredCopy", table.clone(reference), { LISTED })
	end,

	--[[ ================================================================
	     AC-4 through the real guard: the reference declaration over Pings
	     implementations.
	     ================================================================ ]]

	["baseline (AC-4): the reference declaration guarded over the reference Pings passes the refused-then-valid sequence"] = function()
		local failure = guardedFailure("ac4reference", PingsStubs.reference)
		assert(
			failure == nil,
			`the AC-4 sequence fails on the reference, so the check or the fixture is wrong:\n{tostring(
				failure
			)}`
		)
		print("        [measured] AC-4 sequence: reference passes")
	end,

	["control (AC-4, required; D-4's shape): the same sequence over a request that does not decline is rejected for rate on the second, valid ping"] = function()
		local failure = guardedFailure("ac4noDecline", PingsStubs.with("noDecline"))
		assert(failure ~= nil, "the AC-4 sequence passed over a request that never declines")
		local message = failure :: string
		print(`        [measured] AC-4 sequence over noDecline:\n{message}`)
		contains(message, 'the guard answered { detail = "', "the second call's rejection")
		contains(message, 'reason = "rate" }, expected nil (accepted)', "rate on the second call")
		-- The first call's verdict is ALSO wrong - without a decline the guard
		-- accepts it - so the failure names that too, and request's return.
		contains(
			message,
			'the refused ping at t -> the guard answered nil, expected { detail = "',
			"the undeclined first call"
		)
	end,

	["control: a request that declines an accepted ping makes the second, valid ping declined rather than accepted"] = function()
		local failure = guardedFailure("ac4declinesOnAccept", PingsStubs.with("declinesOnAccept"))
		assert(
			failure ~= nil,
			"the AC-4 sequence passed over a request that declines accepted pings"
		)
		contains(
			failure :: string,
			'reason = "declined" }, expected nil (accepted)',
			"declined on the valid ping"
		)
	end,

	["control: a PingRefused carrying a detail key fails the sequence on request's return value"] = function()
		local failure = guardedFailure("ac4withDetail", PingsStubs.with("refusalWithDetail"))
		assert(failure ~= nil, "the AC-4 sequence passed over a request returning a detail")
		contains(
			failure :: string,
			'expected exactly { reason = "no_such_target" }',
			"the exact shape"
		)
	end,
}
