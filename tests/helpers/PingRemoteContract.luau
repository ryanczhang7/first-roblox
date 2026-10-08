--!strict
--[[
	CHAN-005 AC-1 and AC-2, written once as checks over a `Net` bundle -
	`{ Schema, Remotes, Wrapper }` - and a `Ping` REMOTE DEFINITION handed in
	as a parameter, rather than over `src/ReplicatedStorage/Net/GameRemotes.luau` by name. The
	same arrangement as `TurnRemoteContract.luau`, for the same reason:
	`tests/net/ping_remote_test.luau` applies these to the real
	`GameRemotes.Ping`, and `tests/net/ping_remote_controls_test.luau` applies
	them to declarations with EXACTLY ONE defect each - the superseded literal
	3 as the rate, a target bound one too high, a second legal phase, no attempt
	floor - so that in RED, where `GameRemotes.Ping` does not exist and not one
	assertion in the real file has executed, every check here has still been
	EXECUTED and observed to reject the declaration it exists to catch.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE. AC-1 is
	SETTLED and is READ, never re-derived: the rate is what `RateLimitSpec`
	reads for `ping_rate_limit_seconds` out of `docs/wiki/game/tuning.md` (10),
	compared against `MechanicsTuning.channel.ping_rate_limit_seconds` and the
	published floor `RateLimitSpec.FLOOR_SECONDS`; the attempt floor is
	`MechanicsTuning.channel.channel_attempt_min_interval_seconds`; the schema
	bounds are `instance.actuator_count` and `instance.dial_settings`; the
	phases are the Contract's literal `{ "Round" }`. Nothing below writes 10,
	1, 16 or 4 where a constant is meant. The DECLARATION is compared - the
	table `Remotes.all()` lists - never a copy of the number.

	AC-2 IS MECHANICAL: B4's triple - malformed, out-of-phase, flooded -
	through the REAL `Wrapper.guard` over the definition under test, with a
	recording handler whose call count is the assertion "the handler never
	ran". The reasons are the Contract's, pinned against `Schema`: a literal
	mismatch and a missing field are `shape`, an out-of-domain integer is
	`range`. The two rate refusals are told apart by their WHOLE detail
	string (`DeclineContract.attemptDetail` / `sendDetail`): a substring of
	either is satisfied by the other.

	NO ROBLOX, NO `Players`, NO ROUND, NO REAL TIME. The `GuardContext` is
	`RateContract.world`'s: `isSeated` answers for the listed players, `phase`
	is a mutable field, and the clock is `Clock.manual`, SET to each instant.
	Every check builds its OWN guard, so no rate state leaks between checks.
	Nothing here declares `"Ping"`: the registry is process-wide and refuses a
	duplicate; `declare` names its declarations uniquely.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local DeclineContract = require("./DeclineContract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local NetContract = require("./NetContract")
local RateContract = require("./RateContract")
local RateLimitSpec = require("./RateLimitSpec")

local PingRemoteContract = {}

export type Net = { Schema: any, Remotes: any, Wrapper: any }

-- The one seated caller every guarded call is made by, so identity is never
-- what rejects.
PingRemoteContract.CALLER = "kim"

-- A start instant that is not 0, so `now - lastAccepted` and `now` differ.
PingRemoteContract.START = 10

-- How far past the attempt floor (and how far short of a limit) a call lands.
PingRemoteContract.EPSILON = 0.1

PingRemoteContract.LEGAL_PHASES = { "Round" }
PingRemoteContract.ILLEGAL_PHASES = { "Lobby", "Assignment", "Resolution", "Post" }

PingRemoteContract.KINDS = { "setting", "machine", "doorway" }

local function actuatorCount(): number
	return MechanicsTuning.instance.actuator_count
end

local function dialSettings(): number
	return MechanicsTuning.instance.dial_settings
end

-- AC-1's settled numbers, read where the Contract says they live.
function PingRemoteContract.rateLimitSeconds(): number
	return MechanicsTuning.channel.ping_rate_limit_seconds
end

function PingRemoteContract.attemptSeconds(): number
	return MechanicsTuning.channel.channel_attempt_min_interval_seconds
end

--[[
	The value `RateLimitSpec` reads for `ping_rate_limit_seconds` out of
	`tuning.md`: exactly one row, a bare number. Raises (naming the document)
	when the document does not fix it, so a comparison against nothing never
	passes.
]]
function PingRemoteContract.documentRateLimitSeconds(): number
	local name = RateLimitSpec.NAMES[2]
	assert(name == "ping_rate_limit_seconds", `RateLimitSpec.NAMES[2] is {name}`)
	local rows = RateLimitSpec.rowsNaming(RateLimitSpec.read(), name)
	local violations = RateLimitSpec.violations(rows, name, RateLimitSpec.FLOOR_SECONDS)
	if #violations > 0 then
		Contract.fail(
			`AC-1: {RateLimitSpec.SPEC_PATH} does not fix {name}:\n{RateLimitSpec.describe(
				violations
			)}`
		)
	end
	return tonumber(rows[1].valueCell) :: number
end

-- Well-formed payloads: one per kind, off the bounds where a bound exists.
function PingRemoteContract.wellFormedMachine(): any
	return { kind = "machine", target = math.min(3, actuatorCount()) }
end

function PingRemoteContract.wellFormedSetting(): any
	return {
		kind = "setting",
		target = math.min(3, actuatorCount()),
		setting = math.min(2, dialSettings()),
	}
end

function PingRemoteContract.wellFormedDoorway(): any
	return { kind = "doorway", target = 1 }
end

function PingRemoteContract.wellFormedAtTheMaximum(): any
	return { kind = "setting", target = actuatorCount(), setting = dialSettings() }
end

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

local function describeResult(result: any): string
	if typeof(result) == "table" then
		return `reason = {Deep.show(result.reason)}, detail = {Deep.show(result.detail)}`
	end
	return Deep.show(result)
end

local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

local function expectRejection(
	criterion: string,
	label: string,
	ok: boolean,
	result: any,
	expected: string,
	detail: string?
): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED instead of rejecting: {tostring(
			result
		)}`
	end
	if result == nil then
		return `{criterion}: {label} -> ACCEPTED (returned nil); expected a "{expected}" rejection`
	end
	if typeof(result) ~= "table" then
		return `{criterion}: {label} -> rejected with {Deep.show(result)}, which names no check`
	end
	if result.reason ~= expected then
		return `{criterion}: {label} -> rejected for {Deep.show(result.reason)}, expected "{expected}"`
	end
	if detail ~= nil and result.detail ~= detail then
		return `{criterion}: {label} -> rejected for "{expected}" with detail {Deep.show(
			result.detail
		)}, expected exactly {Deep.show(detail)}`
	end
	return nil
end

local function expectAcceptance(criterion: string, label: string, ok: boolean, result: any): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED: {tostring(result)}`
	end
	if result ~= nil then
		return `{criterion}: {label} -> REJECTED: {describeResult(result)}`
	end
	return nil
end

local function requireDefinition(criterion: string, definition: any)
	if typeof(definition) ~= "table" then
		Contract.fail(`{criterion}: the Ping definition is {Deep.show(definition)}, not a table`)
	end
	if typeof(definition.args) ~= "table" or typeof(definition.args.validate) ~= "function" then
		Contract.fail(
			`{criterion}: the Ping definition's args is {Deep.show(definition.args)}; it must be a Schema with a validate function`
		)
	end
end

type HandlerCall = { playerId: any, args: any, call: any }

-- A handler recording every invocation, with its third argument.
local function recorder(): (any, { HandlerCall })
	local calls: { HandlerCall } = {}
	local handler = function(playerId: any, args: any, control: any)
		table.insert(calls, { playerId = playerId, args = args, call = control })
	end
	return handler, calls
end

-- A guard over `definition` with a recording handler and an injected context
-- in which exactly CALLER is seated, the phase is `phase`, the clock reads START.
function PingRemoteContract.guardWithSpy(
	net: Net,
	definition: any,
	phase: string
): (any, { HandlerCall }, RateContract.World)
	local handler, calls = recorder()
	local context, world =
		RateContract.world({ PingRemoteContract.CALLER }, phase, PingRemoteContract.START)
	local guarded = net.Wrapper.guard(definition, context, handler)
	return guarded, calls, world
end

--[[ ------------------------------------------------------------------------
     The reference declaration, with one edit at a time. Shared by both
     controls files; declared under a unique name through the REAL
     `Remotes.define`.
     --------------------------------------------------------------------- ]]

export type Edits = {
	targetMax: number?,
	targetIsNumber: boolean?,
	settingRequired: boolean?,
	kinds: { string }?,
	acceptsPosition: boolean?,
	emptySchema: boolean?,
	legalPhases: { string }?,
	rateLimitSeconds: number?,
	noRateLimit: boolean?,
	attemptSeconds: number?,
	noAttemptLimit: boolean?,
}

function PingRemoteContract.declare(net: Net, label: string, edits: Edits): any
	local Schema = net.Schema
	local instance = MechanicsTuning.instance
	local kinds = edits.kinds or PingRemoteContract.KINDS
	local settingSchema = Schema.integer(1, instance.dial_settings)
	local fields: { [string]: any } = {
		kind = Schema.literal(table.unpack(kinds)),
		target = if edits.targetIsNumber
			then Schema.number(1, edits.targetMax or instance.actuator_count)
			else Schema.integer(1, edits.targetMax or instance.actuator_count),
		setting = if edits.settingRequired then settingSchema else Schema.optional(settingSchema),
	}
	if edits.acceptsPosition then
		fields.position = Schema.optional(Schema.shape({
			x = Schema.number(-1e9, 1e9),
			y = Schema.number(-1e9, 1e9),
			z = Schema.number(-1e9, 1e9),
		}))
	end
	local spec: { [string]: any } = {
		args = if edits.emptySchema then Schema.shape({}) else Schema.shape(fields),
		legalPhases = edits.legalPhases or table.clone(PingRemoteContract.LEGAL_PHASES),
	}
	if not edits.noRateLimit then
		spec.rateLimit = {
			minIntervalSeconds = edits.rateLimitSeconds or PingRemoteContract.rateLimitSeconds(),
		}
	end
	if not edits.noAttemptLimit then
		spec.attemptLimit = {
			minIntervalSeconds = edits.attemptSeconds or PingRemoteContract.attemptSeconds(),
		}
	end
	return net.Remotes.define(NetContract.uniqueName(label), spec)
end

--[[ ------------------------------------------------------------------------
     AC-1, settled: the schema, the phases, the rate, the attempt floor, the
     registry.
     --------------------------------------------------------------------- ]]

type Expectation = { label: string, value: any, expect: string }

--[[
	The schema is `{ kind = literal("setting", "machine", "doorway"), target =
	integer(1, actuator_count), setting = optional(integer(1, dial_settings)) }`,
	pinned by how `args.validate` answers: each kind accepted with and without
	a setting (the schema does not know a setting kind needs one - `validate`
	does), each bound at 0 / 1 / max / max + 1, a non-integer, a fourth kind,
	a missing field, an extra field and non-table payloads.
]]
function PingRemoteContract.schemaIsKindTargetAndOptionalSettingAtTheTuningBounds(
	_net: Net,
	definition: any
)
	requireDefinition("AC-1", definition)
	local n, d = actuatorCount(), dialSettings()
	local cases: { Expectation } = {
		{
			label = "{ kind = machine, target = 1 }",
			value = { kind = "machine", target = 1 },
			expect = "ok",
		},
		{
			label = `\{ kind = setting, target = {n}, setting = {d} } (both maxima)`,
			value = { kind = "setting", target = n, setting = d },
			expect = "ok",
		},
		{
			label = "{ kind = setting, target = 1, setting = 1 } (both minima)",
			value = { kind = "setting", target = 1, setting = 1 },
			expect = "ok",
		},
		{
			label = "{ kind = doorway, target = 1 }",
			value = { kind = "doorway", target = 1 },
			expect = "ok",
		},
		{
			label = "{ kind = setting, target = 1 } (a setting kind without a setting: the schema accepts, validate refuses)",
			value = { kind = "setting", target = 1 },
			expect = "ok",
		},
		{
			label = "{ kind = machine, target = 1, setting = 1 } (a setting on a machine kind: the schema accepts, validate refuses)",
			value = { kind = "machine", target = 1, setting = 1 },
			expect = "ok",
		},
		{
			label = '{ kind = "floor", target = 1 }',
			value = { kind = "floor", target = 1 },
			expect = "shape",
		},
		{
			label = '{ kind = "Machine", target = 1 } (case)',
			value = { kind = "Machine", target = 1 },
			expect = "shape",
		},
		{ label = "{ kind = 1, target = 1 }", value = { kind = 1, target = 1 }, expect = "shape" },
		{ label = "{ target = 1 } (missing kind)", value = { target = 1 }, expect = "shape" },
		{
			label = "{ kind = machine } (missing target)",
			value = { kind = "machine" },
			expect = "shape",
		},
		{
			label = "{ kind = machine, target = 0 }",
			value = { kind = "machine", target = 0 },
			expect = "range",
		},
		{
			label = `\{ kind = machine, target = {n + 1} } (actuator_count + 1)`,
			value = { kind = "machine", target = n + 1 },
			expect = "range",
		},
		{
			label = "{ kind = machine, target = 1.5 }",
			value = { kind = "machine", target = 1.5 },
			expect = "range",
		},
		{
			label = '{ kind = machine, target = "1" }',
			value = { kind = "machine", target = "1" },
			expect = "shape",
		},
		{
			label = "{ kind = setting, target = 1, setting = 0 }",
			value = { kind = "setting", target = 1, setting = 0 },
			expect = "range",
		},
		{
			label = `\{ kind = setting, target = 1, setting = {d + 1} } (dial_settings + 1)`,
			value = { kind = "setting", target = 1, setting = d + 1 },
			expect = "range",
		},
		{
			label = "{ kind = setting, target = 1, setting = 1.5 }",
			value = { kind = "setting", target = 1, setting = 1.5 },
			expect = "range",
		},
		{
			label = "{ kind = setting, target = 1, setting = false } (false is not nil)",
			value = { kind = "setting", target = 1, setting = false },
			expect = "shape",
		},
		{
			label = "{ kind = machine, target = 1, position = { x = 0, y = 0, z = 0 } } (extra position)",
			value = { kind = "machine", target = 1, position = { x = 0, y = 0, z = 0 } },
			expect = "shape",
		},
		{
			label = '{ kind = machine, target = 1, player = "kim" } (extra player)',
			value = { kind = "machine", target = 1, player = "kim" },
			expect = "shape",
		},
		{ label = "{} (zero keys)", value = {}, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = '"ping" (a string payload)', value = "ping", expect = "shape" },
	}
	local violations: { string } = {}
	for _, case in cases do
		local ok, valid, failure = pcall(definition.args.validate, case.value)
		if not ok then
			table.insert(violations, `{case.label} -> validate RAISED: {tostring(valid)}`)
		elseif case.expect == "ok" then
			if valid ~= true then
				table.insert(
					violations,
					`{case.label} -> rejected ({Deep.show(failure)}), expected acceptance`
				)
			end
		elseif valid ~= false then
			table.insert(violations, `{case.label} -> accepted, expected a {case.expect} failure`)
		else
			local kind = NetContract.kindOf(failure)
			if kind ~= case.expect then
				table.insert(violations, `{case.label} -> failed as {kind}, expected {case.expect}`)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-1: the Ping schema is not \{ kind = literal(setting, machine, doorway), target = integer(1, {n}), setting = optional(integer(1, {d})) } (actuator_count = {n}, dial_settings = {d}) - {#violations} of {#cases} cases:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- Exactly `{ "Round" }`.
function PingRemoteContract.legalPhasesAreExactlyRound(_net: Net, definition: any)
	requireDefinition("AC-1", definition)
	if not Deep.equal(definition.legalPhases, PingRemoteContract.LEGAL_PHASES) then
		Contract.fail(
			`AC-1: Ping.legalPhases is {Deep.show(definition.legalPhases)}, expected exactly {Deep.show(
				PingRemoteContract.LEGAL_PHASES
			)}`
		)
	end
end

--[[
	`rateLimit.minIntervalSeconds` IS the value `RateLimitSpec` reads for
	`ping_rate_limit_seconds` from `tuning.md`, IS
	`MechanicsTuning.channel.ping_rate_limit_seconds`, and is at least
	`RateLimitSpec.FLOOR_SECONDS`. The message carries the declared value and
	the document's, so the superseded literal 3 fails naming 3 and 10.
]]
function PingRemoteContract.rateLimitIsThePingRateLimitTheDocumentFixes(_net: Net, definition: any)
	requireDefinition("AC-1", definition)
	local document = PingRemoteContract.documentRateLimitSeconds()
	local module = PingRemoteContract.rateLimitSeconds()
	local floor = RateLimitSpec.FLOOR_SECONDS
	local rateLimit = definition.rateLimit
	local declared: any = if typeof(rateLimit) == "table" then rateLimit.minIntervalSeconds else nil
	local problems: { string } = {}
	if module ~= document then
		table.insert(
			problems,
			`MechanicsTuning.channel.ping_rate_limit_seconds is {module} but {RateLimitSpec.SPEC_PATH} fixes {document}; the module and the document disagree`
		)
	end
	if typeof(rateLimit) ~= "table" or declared ~= document then
		table.insert(
			problems,
			`Ping.rateLimit is {Deep.show(rateLimit)}, expected \{ minIntervalSeconds = {document} } - the value RateLimitSpec reads for ping_rate_limit_seconds from {RateLimitSpec.SPEC_PATH} ({document}), which MechanicsTuning.channel.ping_rate_limit_seconds carries ({module})`
		)
	end
	if typeof(declared) ~= "number" or not (declared >= floor) then
		table.insert(
			problems,
			`Ping.rateLimit.minIntervalSeconds is {Deep.show(declared)}, below RateLimitSpec.FLOOR_SECONDS = {floor} (the preset guideline, brief §0d #19, #23)`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-1 (rate): {#problems} problem(s):\n{indent(table.concat(problems, "\n"))}`
		)
	end
end

-- `attemptLimit.minIntervalSeconds` IS `channel_attempt_min_interval_seconds`.
function PingRemoteContract.attemptLimitIsTheChannelAttemptFloorFromTuning(
	_net: Net,
	definition: any
)
	requireDefinition("AC-1", definition)
	local want = PingRemoteContract.attemptSeconds()
	local attemptLimit = definition.attemptLimit
	if typeof(attemptLimit) ~= "table" or attemptLimit.minIntervalSeconds ~= want then
		Contract.fail(
			`AC-1: Ping.attemptLimit is {Deep.show(attemptLimit)}, expected \{ minIntervalSeconds = {want} } (MechanicsTuning.channel.channel_attempt_min_interval_seconds)`
		)
	end
end

-- `Remotes.all()` lists this very table under its name - by identity, once.
function PingRemoteContract.isTheDefinitionRemotesAllLists(net: Net, definition: any)
	requireDefinition("AC-1", definition)
	local byName: { any } = {}
	for _, entry in net.Remotes.all() do
		if typeof(entry) == "table" and entry.name == definition.name then
			table.insert(byName, entry)
		end
	end
	if #byName ~= 1 then
		Contract.fail(
			`AC-1: Remotes.all() lists {#byName} definition(s) named {Deep.show(definition.name)}, expected exactly one`
		)
	end
	if not rawequal(byName[1], definition) then
		Contract.fail(
			`AC-1: the definition Remotes.all() lists as {Deep.show(definition.name)} is not the same table as the Ping definition under test; a copy or a second declaration is not the registered remote`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2, mechanical: malformed, out of phase, flooded - through the real guard.
     --------------------------------------------------------------------- ]]

export type MalformedCase = { label: string, args: any, expect: string }

-- The Contract's "AC-2's reasons, pinned against Schema", verbatim.
function PingRemoteContract.malformedCases(): { MalformedCase }
	local n, d = actuatorCount(), dialSettings()
	local w = PingRemoteContract.wellFormedMachine()
	return {
		{
			label = `kind = "floor": \{ kind = "floor", target = {w.target} }`,
			args = { kind = "floor", target = w.target },
			expect = "shape",
		},
		{
			label = "a missing target: { kind = machine }",
			args = { kind = "machine" },
			expect = "shape",
		},
		{
			label = "target = 0: { kind = machine, target = 0 }",
			args = { kind = "machine", target = 0 },
			expect = "range",
		},
		{
			label = `target = {n + 1} (actuator_count + 1)`,
			args = { kind = "machine", target = n + 1 },
			expect = "range",
		},
		{
			label = `setting = {d + 1} (dial_settings + 1): \{ kind = setting, target = {w.target}, setting = {d + 1} }`,
			args = { kind = "setting", target = w.target, setting = d + 1 },
			expect = "range",
		},
		{ label = "target = 1.5", args = { kind = "machine", target = 1.5 }, expect = "range" },
		{
			label = "an extra position field",
			args = { kind = "machine", target = w.target, position = { x = 0, y = 0, z = 0 } },
			expect = "shape",
		},
		{ label = 'the payload is the string "ping"', args = "ping", expect = "shape" },
	}
end

function PingRemoteContract.malformedCallsAreRejectedBeforeTheHandler(net: Net, definition: any)
	requireDefinition("AC-2", definition)
	local guarded, calls = PingRemoteContract.guardWithSpy(net, definition, "Round")
	local cases = PingRemoteContract.malformedCases()
	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, PingRemoteContract.CALLER, case.args)
		local violation = expectRejection("AC-2", case.label, ok, result, case.expect)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#cases} malformed payloads; it must never run for one`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 (malformed) failed in {#violations} case(s) of {#cases}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- A well-formed call in each of the four other phases is `phase`; the handler never runs.
function PingRemoteContract.wellFormedCallOutOfRoundIsRejectedForPhase(net: Net, definition: any)
	requireDefinition("AC-2", definition)
	local guarded, calls, world = PingRemoteContract.guardWithSpy(net, definition, "Round")
	local violations: { string } = {}
	for _, phase in PingRemoteContract.ILLEGAL_PHASES do
		world.phase = phase
		local ok, result =
			call(guarded, PingRemoteContract.CALLER, PingRemoteContract.wellFormedMachine())
		local violation = expectRejection(
			"AC-2",
			`a well-formed call while the phase is {phase}`,
			ok,
			result,
			"phase"
		)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#PingRemoteContract.ILLEGAL_PHASES} out-of-phase calls`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 (phase) failed in {#violations} case(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	The attempt floor: two well-formed in-Round calls at `t` and
	`t + attempt - EPSILON` - the second is `rate` with the ATTEMPT detail
	(not the send detail), and the handler count stays 1. A third at exactly
	`t + attempt` is past the floor and is refused by the SEND limit instead:
	the floor is inclusive, and the two refusals are distinguishable.
]]
function PingRemoteContract.secondCallInsideTheAttemptFloorIsRejectedForRate(
	net: Net,
	definition: any
)
	requireDefinition("AC-2", definition)
	local attempt = PingRemoteContract.attemptSeconds()
	local rate = PingRemoteContract.rateLimitSeconds()
	local eps = PingRemoteContract.EPSILON
	assert(
		eps < attempt and attempt < rate,
		`fixture: need EPSILON {eps} < attempt {attempt} < rate {rate}`
	)
	local guarded, calls, world = PingRemoteContract.guardWithSpy(net, definition, "Round")
	local caller = PingRemoteContract.CALLER
	local start = PingRemoteContract.START
	local payload = PingRemoteContract.wellFormedMachine()
	local violations: { string } = {}
	local function push(v: string?)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end

	world.clock:set(start)
	local ok1, r1 = call(guarded, caller, payload)
	push(expectAcceptance("AC-2", "the first well-formed in-Round call, at t", ok1, r1))
	if #calls ~= 1 then
		push(`AC-2: after the first call the handler ran {#calls} time(s), expected 1`)
	end

	world.clock:set(start + attempt - eps)
	local ok2, r2 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-2",
			`the second call at t + {attempt} - {eps} (inside channel_attempt_min_interval_seconds = {attempt})`,
			ok2,
			r2,
			"rate",
			DeclineContract.attemptDetail(definition.name, attempt)
		)
	)

	world.clock:set(start + attempt)
	local ok3, r3 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-2",
			`the third call at exactly t + {attempt} (past the floor, inside the send limit)`,
			ok3,
			r3,
			"rate",
			DeclineContract.sendDetail(definition.name, rate)
		)
	)
	if #calls ~= 1 then
		push(
			`AC-2: after two rate-limited calls the handler ran {#calls} time(s) in total; expected 1`
		)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-2 (attempt floor = {attempt}) failed in {#violations} step(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	The send limit: an accepted call at `t`; a second at `t + attempt + EPSILON`
	(past the floor, well inside the limit) is `rate` with the SEND detail; a
	third at `t + rate - attempt` is still `rate`; a fourth at exactly `t +
	rate` runs the handler (count 2) - the boundary that keeps a limit one
	second too long, or the superseded 3, from passing. The third call sits a
	full attempt floor before the fourth so that the floor, which records the
	refused third call, does not refuse the fourth.
]]
function PingRemoteContract.secondAcceptedCallInsideTheSendLimitIsRejectedForRate(
	net: Net,
	definition: any
)
	requireDefinition("AC-2", definition)
	local attempt = PingRemoteContract.attemptSeconds()
	local rate = PingRemoteContract.rateLimitSeconds()
	local eps = PingRemoteContract.EPSILON
	assert(
		attempt + eps < rate - attempt,
		`fixture: need attempt + EPSILON ({attempt + eps}) < rate - attempt ({rate - attempt})`
	)
	local guarded, calls, world = PingRemoteContract.guardWithSpy(net, definition, "Round")
	local caller = PingRemoteContract.CALLER
	local start = PingRemoteContract.START
	local payload = PingRemoteContract.wellFormedDoorway()
	local sendDetail = DeclineContract.sendDetail(definition.name, rate)
	local violations: { string } = {}
	local function push(v: string?)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end

	world.clock:set(start)
	local ok1, r1 = call(guarded, caller, payload)
	push(expectAcceptance("AC-2", "the first well-formed in-Round call, at t", ok1, r1))
	if #calls ~= 1 then
		push(`AC-2: after the first call the handler ran {#calls} time(s), expected 1`)
	end

	world.clock:set(start + attempt + eps)
	local ok2, r2 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-2",
			`the second call at t + {attempt + eps} (past the attempt floor, inside ping_rate_limit_seconds = {rate})`,
			ok2,
			r2,
			"rate",
			sendDetail
		)
	)

	world.clock:set(start + rate - attempt)
	local ok3, r3 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-2",
			`the third call at t + {rate - attempt} (still inside the send limit)`,
			ok3,
			r3,
			"rate",
			sendDetail
		)
	)
	if #calls ~= 1 then
		push(
			`AC-2: after two send-limited calls the handler ran {#calls} time(s) in total; it must stay at 1 - a ping refused for rate is not evaluated`
		)
	end

	world.clock:set(start + rate)
	local ok4, r4 = call(guarded, caller, payload)
	push(expectAcceptance("AC-2", `the fourth call at exactly t + {rate}`, ok4, r4))
	if #calls ~= 2 then
		push(`AC-2: after the fourth call the handler ran {#calls} time(s) in total, expected 2`)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-2 (send limit = {rate}) failed in {#violations} step(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	The positive control: a well-formed in-Round call of each kind, and at both
	maxima, reaches the handler exactly once with the caller's id, exactly the
	payload, and a `CallControl` with a `decline` function (CHAN-003).
]]
function PingRemoteContract.wellFormedCallInRoundReachesTheHandlerWithTheValidatedArgs(
	net: Net,
	definition: any
)
	requireDefinition("AC-2 positive control", definition)
	local violations: { string } = {}
	for _, payload in
		{
			PingRemoteContract.wellFormedMachine(),
			PingRemoteContract.wellFormedSetting(),
			PingRemoteContract.wellFormedDoorway(),
			PingRemoteContract.wellFormedAtTheMaximum(),
		}
	do
		local guarded, calls = PingRemoteContract.guardWithSpy(net, definition, "Round")
		local ok, result = call(guarded, PingRemoteContract.CALLER, payload)
		local label = Deep.show(payload)
		local violation = expectAcceptance("AC-2 positive control", label, ok, result)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		elseif #calls ~= 1 then
			table.insert(
				violations,
				`{label} -> the handler ran {#calls} time(s), expected exactly once`
			)
		else
			local c = calls[1]
			if c.playerId ~= PingRemoteContract.CALLER then
				table.insert(
					violations,
					`{label} -> the handler received playerId {Deep.show(c.playerId)}, expected "{PingRemoteContract.CALLER}"`
				)
			end
			if not Deep.equal(c.args, payload) then
				table.insert(
					violations,
					`{label} -> the handler received args {Deep.show(c.args)}, expected exactly the payload`
				)
			end
			if typeof(c.call) ~= "table" or typeof(c.call.decline) ~= "function" then
				table.insert(
					violations,
					`{label} -> the handler received call = {Deep.show(c.call)}; expected a CallControl with a decline function`
				)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 positive control: a well-formed in-Round call must reach the handler once with exactly the payload:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The battery, named, so the controls can run every check against a
     definition and report exactly which fire.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Net, any) -> ...any }

PingRemoteContract.CHECKS = {
	{
		name = "schemaIsKindTargetAndOptionalSettingAtTheTuningBounds",
		ac = "AC-1",
		run = PingRemoteContract.schemaIsKindTargetAndOptionalSettingAtTheTuningBounds,
	},
	{
		name = "legalPhasesAreExactlyRound",
		ac = "AC-1",
		run = PingRemoteContract.legalPhasesAreExactlyRound,
	},
	{
		name = "rateLimitIsThePingRateLimitTheDocumentFixes",
		ac = "AC-1",
		run = PingRemoteContract.rateLimitIsThePingRateLimitTheDocumentFixes,
	},
	{
		name = "attemptLimitIsTheChannelAttemptFloorFromTuning",
		ac = "AC-1",
		run = PingRemoteContract.attemptLimitIsTheChannelAttemptFloorFromTuning,
	},
	{
		name = "isTheDefinitionRemotesAllLists",
		ac = "AC-1",
		run = PingRemoteContract.isTheDefinitionRemotesAllLists,
	},
	{
		name = "malformedCallsAreRejectedBeforeTheHandler",
		ac = "AC-2",
		run = PingRemoteContract.malformedCallsAreRejectedBeforeTheHandler,
	},
	{
		name = "wellFormedCallOutOfRoundIsRejectedForPhase",
		ac = "AC-2",
		run = PingRemoteContract.wellFormedCallOutOfRoundIsRejectedForPhase,
	},
	{
		name = "secondCallInsideTheAttemptFloorIsRejectedForRate",
		ac = "AC-2",
		run = PingRemoteContract.secondCallInsideTheAttemptFloorIsRejectedForRate,
	},
	{
		name = "secondAcceptedCallInsideTheSendLimitIsRejectedForRate",
		ac = "AC-2",
		run = PingRemoteContract.secondAcceptedCallInsideTheSendLimitIsRejectedForRate,
	},
	{
		name = "wellFormedCallInRoundReachesTheHandlerWithTheValidatedArgs",
		ac = "AC-2 positive control",
		run = PingRemoteContract.wellFormedCallInRoundReachesTheHandlerWithTheValidatedArgs,
	},
} :: { Check }

-- Every check against `definition`; the names of those that raised, with
-- their messages, in CHECKS order.
function PingRemoteContract.failures(
	net: Net,
	definition: any
): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PingRemoteContract.CHECKS do
		local ok, err = pcall(check.run, net, definition)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PingRemoteContract
