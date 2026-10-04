--!strict
--[[
	The negative controls for PROC-005 AC-1 through AC-3, and the proof that
	each check in `tests/helpers/TurnRemoteContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/net/GameRemotes.luau` does not exist, every test in
	`tests/net/turn_remote_test.luau` fails before its assertion runs, and so
	not one of that file's checks has been observed to accept or reject
	anything. The declarations below need only `Schema`, `Remotes`, `Wrapper`
	and `MechanicsTuning`, which are merged, so what is asserted here is
	MEASURED in RED rather than claimed for GREEN. The story's handoff carries
	the table.

	THE REFERENCE is the Contract's own spec - `{ machine = integer(1,
	actuator_count), setting = integer(1, dial_settings) }`, `{ "Round" }`,
	`turn_rate_limit_seconds` - declared through the REAL `Remotes.define`
	under a unique name (never `"Turn"`: the registry is process-wide and the
	real module declares that one). Every check must ACCEPT it, or the check
	is wrong and the fix belongs HERE, in RED. Each control is the reference
	with EXACTLY ONE thing changed, so the set of checks that fire is
	attributable to that one change, and each control pins that set EXACTLY -
	a check that fires on a control it should not is as much a finding as one
	that stays quiet.

	THE DEFERRED VERIFICATIONS' SHAPES ARE HERE AS DECLARATIONS. D-3 mutates
	the real module's `minIntervalSeconds` to `+ 1` and its setting bound to
	`dial_settings + 1`; `rateLimitPlusOne` and `settingUpperBoundPlusOne` are
	those two edits made to the reference, so that what is measured here is
	that the checks WOULD see them. D-3 ITSELF stays with GATES.

	WHAT THIS IS NOT: `src/net/GameRemotes.luau`, or a sketch of one. GREEN
	writes the module from the story's Contract against
	`turn_remote_test.luau`; nothing here is to be copied.
]]

local Contract = require("../helpers/TurnRemoteContract")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local NetContract = require("../helpers/NetContract")
local Remotes = require("../../src/net/Remotes")
local Schema = require("../../src/net/Schema")
local Wrapper = require("../../src/net/Wrapper")

local net: Contract.Net = { Schema = Schema, Remotes = Remotes, Wrapper = Wrapper }

type Edits = {
	machineMin: number?,
	settingMax: number?,
	settingIsNumber: boolean?,
	acceptsPlayer: boolean?,
	emptySchema: boolean?,
	legalPhases: { string }?,
	rateLimitSeconds: number?,
	noRateLimit: boolean?,
	attemptLimit: { minIntervalSeconds: number }?,
}

-- The reference spec with the named edits, declared under a unique name.
local function declare(label: string, edits: Edits): any
	local instance = MechanicsTuning.instance
	local fields: { [string]: any } = {
		machine = Schema.integer(edits.machineMin or 1, instance.actuator_count),
		setting = if edits.settingIsNumber
			then Schema.number(1, instance.dial_settings)
			else Schema.integer(1, edits.settingMax or instance.dial_settings),
	}
	if edits.acceptsPlayer then
		fields.player = Schema.optional(Schema.literal("kim"))
	end
	local spec: { [string]: any } = {
		args = if edits.emptySchema then Schema.shape({}) else Schema.shape(fields),
		legalPhases = edits.legalPhases or table.clone(Contract.LEGAL_PHASES),
	}
	if not edits.noRateLimit then
		spec.rateLimit = {
			minIntervalSeconds = edits.rateLimitSeconds or Contract.rateLimitSeconds(),
		}
	end
	local definition = Remotes.define(NetContract.uniqueName(label), spec)
	if edits.attemptLimit ~= nil then
		definition.attemptLimit = edits.attemptLimit
	end
	return definition
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
local function expectFires(who: string, definition: any, expected: { string })
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
end

local SCHEMA = "schemaIsIntegerMachineAndSettingAtTheTuningBounds"
local PHASES = "legalPhasesAreExactlyRound"
local RATE_LIMIT = "rateLimitIsTheTurnRateLimitFromTuning"
local ATTEMPT = "declaresNoAttemptLimit"
local LISTED = "isTheDefinitionRemotesAllLists"
local MALFORMED = "malformedCallsAreRejectedBeforeTheHandler"
local OUT_OF_PHASE = "wellFormedCallOutOfRoundIsRejectedForPhase"
local RATE = "secondCallInsideTheTurnRateLimitIsRejectedForRate"
local POSITIVE = "wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting"

return {
	--[[ ================================================================
	     The reference. Everything below is this declaration with one edit.
	     ================================================================ ]]

	["baseline: the reference declaration - the Contract's spec under a unique name - passes every check in TurnRemoteContract"] = function()
		local names, messages = failingNames(declare("reference", {}))
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		if #names > 0 then
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

	["fixtures: EPSILON is inside turn_rate_limit_seconds, the well-formed payloads are inside both domains and off both lower bounds, and dial_settings + 1 and 1.5 are outside the setting domain"] = function()
		local instance = MechanicsTuning.instance
		local rate = Contract.rateLimitSeconds()
		local w = Contract.wellFormed()
		local m = Contract.wellFormedAtTheMaximum()
		local problems: { string } = {}
		if not (Contract.EPSILON > 0 and Contract.EPSILON < rate) then
			table.insert(problems, `EPSILON {Contract.EPSILON} is not strictly inside (0, {rate})`)
		end
		if not (w.machine > 1 and w.machine <= instance.actuator_count) then
			table.insert(
				problems,
				`wellFormed().machine {w.machine} is not in (1, actuator_count = {instance.actuator_count}]`
			)
		end
		if not (w.setting > 1 and w.setting <= instance.dial_settings) then
			table.insert(
				problems,
				`wellFormed().setting {w.setting} is not in (1, dial_settings = {instance.dial_settings}]`
			)
		end
		if m.machine ~= instance.actuator_count or m.setting ~= instance.dial_settings then
			table.insert(problems, `wellFormedAtTheMaximum() is {Deep.show(m)}, not the two maxima`)
		end
		if math.floor(1.5) == 1.5 or instance.dial_settings + 1 <= instance.dial_settings then
			table.insert(problems, "the range cases are not outside the domain")
		end
		assert(
			#problems == 0,
			`the fixture no longer discriminates:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ ================================================================
	     AC-1's settled values: each bound, the phases, the rate.
	     ================================================================ ]]

	["control (D-3's second edit): a setting bound of dial_settings + 1 fails the schema check and AC-2 - the dial_settings + 1 call reaches the handler"] = function()
		expectFires(
			"settingUpperBoundPlusOne",
			declare("settingUpperBoundPlusOne", {
				settingMax = MechanicsTuning.instance.dial_settings + 1,
			}),
			{ SCHEMA, MALFORMED }
		)
	end,

	["control: a machine bound starting at 0 fails the schema check and AC-2 - machine = 0 reaches the handler"] = function()
		expectFires("machineLowerBoundZero", declare("machineLowerBoundZero", { machineMin = 0 }), {
			SCHEMA,
			MALFORMED,
		})
	end,

	["control: setting declared as number() rather than integer() fails the schema check and AC-2 - setting = 1.5 reaches the handler"] = function()
		expectFires("settingIsNumber", declare("settingIsNumber", { settingIsNumber = true }), {
			SCHEMA,
			MALFORMED,
		})
	end,

	["control: a schema admitting an optional player field fails the schema check and AC-2 - the extra player key reaches the handler"] = function()
		expectFires("acceptsPlayer", declare("acceptsPlayer", { acceptsPlayer = true }), {
			SCHEMA,
			MALFORMED,
		})
	end,

	["control: legalPhases { Round, Lobby } fails the phases check and AC-3's phase half - a Lobby call reaches the handler - and nothing else"] = function()
		expectFires(
			"legalInLobbyToo",
			declare("legalInLobbyToo", { legalPhases = { "Round", "Lobby" } }),
			{
				PHASES,
				OUT_OF_PHASE,
			}
		)
	end,

	["control (D-3's first edit): minIntervalSeconds = turn_rate_limit_seconds + 1 fails the rate-limit check and AC-3's rate half - the call at exactly t + rate is refused"] = function()
		expectFires(
			"rateLimitPlusOne",
			declare("rateLimitPlusOne", { rateLimitSeconds = Contract.rateLimitSeconds() + 1 }),
			{ RATE_LIMIT, RATE }
		)
	end,

	["control: no rateLimit at all fails the rate-limit check and AC-3's rate half - the second call inside the interval reaches the handler"] = function()
		expectFires(
			"noRateLimit",
			declare("noRateLimit", { noRateLimit = true }),
			{ RATE_LIMIT, RATE }
		)
	end,

	-- CHAN-003 Return 1. The floor is a WELL-FORMED `RateLimit` - the wrapper
	-- now reads it and raises on a bare number - and it sits BELOW every gap
	-- between calls that reach stage 5 in these checks. The smallest such gap
	-- is EPSILON: the rate check's second call (t + rate - EPSILON) is recorded
	-- by the attempt limiter even though the send limiter refuses it (the floor
	-- runs first and is never refunded), so the third call at t + rate is only
	-- EPSILON after the floor's last acceptance. MEASURED against GREEN's
	-- wrapper: EPSILON / 2 fires exactly declaresNoAttemptLimit; EPSILON itself,
	-- 0.2, 0.5 and 3 also fire the AC-3 rate check (see the story's
	-- `## Regressions`, Return 1).
	["control: a definition carrying a well-formed attemptLimit below every call gap fails exactly the attempt-limit check"] = function()
		expectFires(
			"declaresAttemptLimit",
			declare("declaresAttemptLimit", {
				attemptLimit = { minIntervalSeconds = Contract.EPSILON / 2 },
			}),
			{ ATTEMPT }
		)
	end,

	["control: a hand-built copy of the reference that was never passed through Remotes.define fails exactly the registry check - all() must list the table itself"] = function()
		local reference = declare("copied", {})
		local copy = table.clone(reference)
		expectFires("unregisteredCopy", copy, { LISTED })
	end,

	--[[ ================================================================
	     The positive control: a schema that rejects everything.
	     ================================================================ ]]

	["control: an empty schema rejects every payload as shape - it fails the schema check, AC-2's range cases, both halves of AC-3 (phase and rate are never reached) and the positive control"] = function()
		expectFires("emptySchema", declare("emptySchema", { emptySchema = true }), {
			SCHEMA,
			MALFORMED,
			OUT_OF_PHASE,
			RATE,
			POSITIVE,
		})
	end,
}
