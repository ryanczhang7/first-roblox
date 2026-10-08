--!strict
--[[
	PROC-005 AC-1 through AC-3, written once as checks over a `Net` bundle -
	`{ Schema, Remotes, Wrapper }` - and a `Turn` REMOTE DEFINITION handed in as
	a parameter, rather than over `src/ReplicatedStorage/Net/GameRemotes.luau` by name. The same
	arrangement as `NetContract.luau` and `RateContract.luau`, for the same
	reason: `tests/net/turn_remote_test.luau` applies these to the real
	`GameRemotes.Turn`, and `tests/net/turn_remote_controls_test.luau` applies
	them to definitions declared with EXACTLY ONE defect each - a setting bound
	one too high, a second legal phase, a rate limit one second too long - so
	that in RED, where `GameRemotes.luau` does not exist and not one assertion
	in the real file has executed, every check here has still been EXECUTED and
	observed to reject the declaration it exists to catch.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE. AC-1 is
	SETTLED: every bound, phase and interval is READ from `MechanicsTuning`
	(`instance.actuator_count`, `instance.dial_settings`,
	`actuation.turn_rate_limit_seconds`) and the Contract's literal
	`legalPhases = { "Round" }`; nothing below writes 16, 4 or 1 where a
	constant is meant. "Declares no attempt limit and never declines" is pinned
	as `attemptLimit == nil` (PO decision 1). AC-2 and AC-3 are MECHANICAL:
	B4's adversarial triple - malformed, out-of-phase, flooded - through the
	REAL `Wrapper.guard` over the definition under test, with a spy handler
	whose call count is the assertion "the Procedure is never consulted".

	THE SCHEMA IS CHECKED THROUGH `args.validate`, never by reading the schema's
	structure: the `Schema` type is structural, so the only thing a definition
	promises is how it answers. Reasons are compared by EXACT EQUALITY on the
	`Rejection.reason` field and the kind is read off the failure string
	anchored at its start (`NetContract.kindOf`), never by substring - a needle
	whose negation also matches is not a needle (`rules.md`).

	NO ROBLOX, NO `Players`, NO ROUND, NO REAL TIME. The `GuardContext` is
	`RateContract.world`'s: `isSeated` answers for the listed players, `phase`
	is a mutable field, and the clock is `Clock.manual`, SET to each instant
	rather than accumulated, so `t + rate - EPSILON` and `t + rate` are the
	numbers they say and not a rounding of them. Every check builds its OWN
	guard: a limiter lives in the guard's closure, so no rate state leaks
	between checks. Nothing here re-declares `"Turn"`: the registry is
	process-wide and refuses a duplicate.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local NetContract = require("./NetContract")
local RateContract = require("./RateContract")

local TurnRemoteContract = {}

export type Net = { Schema: any, Remotes: any, Wrapper: any }

-- The one seated caller every guarded call is made by, so identity is never
-- what rejects. Not "p1": the Procedure fixture's holder is kim.
TurnRemoteContract.CALLER = "kim"

-- A start instant that is not 0, so `now - lastAccepted` and `now` differ.
TurnRemoteContract.START = 10

-- How far inside the rate limit the AC-3 second call lands. Checked against
-- the interval by the controls file: it must be strictly smaller.
TurnRemoteContract.EPSILON = 0.1

-- The Contract's legal phases, and the four that are not.
TurnRemoteContract.LEGAL_PHASES = { "Round" }
TurnRemoteContract.ILLEGAL_PHASES = { "Lobby", "Assignment", "Resolution", "Post" }

local function actuatorCount(): number
	return MechanicsTuning.instance.actuator_count
end

local function dialSettings(): number
	return MechanicsTuning.instance.dial_settings
end

function TurnRemoteContract.rateLimitSeconds(): number
	return MechanicsTuning.actuation.turn_rate_limit_seconds
end

-- A well-formed payload off both boundaries, so a bound that is one off in
-- either direction still accepts it and the positive control stays positive.
function TurnRemoteContract.wellFormed(): any
	return { machine = math.min(3, actuatorCount()), setting = math.min(2, dialSettings()) }
end

-- A well-formed payload AT both upper bounds.
function TurnRemoteContract.wellFormedAtTheMaximum(): any
	return { machine = actuatorCount(), setting = dialSettings() }
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

-- One guarded call; a raise is an outcome, not the end of the check.
local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

local function expectRejection(
	criterion: string,
	label: string,
	ok: boolean,
	result: any,
	expected: string
): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED instead of rejecting: {tostring(
			result
		)}`
	end
	if result == nil then
		return `{criterion}: {label} -> ACCEPTED (returned nil); the handler was reachable`
	end
	if typeof(result) ~= "table" then
		return `{criterion}: {label} -> rejected with {Deep.show(result)}, which names no check`
	end
	if result.reason ~= expected then
		return `{criterion}: {label} -> rejected for {Deep.show(result.reason)}, expected "{expected}"`
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

-- The definition must be a table with a callable `args.validate` before any
-- check can ask it anything; said once, so every check fails the same way on
-- a definition that is not one.
local function requireDefinition(criterion: string, definition: any)
	if typeof(definition) ~= "table" then
		Contract.fail(`{criterion}: the Turn definition is {Deep.show(definition)}, not a table`)
	end
	if typeof(definition.args) ~= "table" or typeof(definition.args.validate) ~= "function" then
		Contract.fail(
			`{criterion}: the Turn definition's args is {Deep.show(definition.args)}; it must be a Schema with a validate function`
		)
	end
end

-- A guard over `definition` with a recording handler and an injected context
-- in which exactly CALLER is seated, the phase is `phase`, and the clock
-- reads START.
local function guardWithSpy(
	net: Net,
	definition: any,
	phase: string
): (any, { any }, RateContract.World)
	local handler, calls = NetContract.recorder()
	local context, world =
		RateContract.world({ TurnRemoteContract.CALLER }, phase, TurnRemoteContract.START)
	local guarded = net.Wrapper.guard(definition, context, handler)
	return guarded, calls, world
end

--[[ ------------------------------------------------------------------------
     AC-1, settled: the schema, the phases, the rate limit, no attempt limit,
     and the registry.
     --------------------------------------------------------------------- ]]

type Expectation = { label: string, value: any, expect: string }

--[[
	The schema is `{ machine = integer(1, actuator_count), setting =
	integer(1, dial_settings) }`, pinned by how `args.validate` answers at
	0 / 1 / max / max + 1 for each field, a non-integer in each, a missing
	field, an extra field (`position`, `player`), and non-table payloads.
]]
function TurnRemoteContract.schemaIsIntegerMachineAndSettingAtTheTuningBounds(
	_net: Net,
	definition: any
)
	requireDefinition("AC-1", definition)
	local n, d = actuatorCount(), dialSettings()
	local cases: { Expectation } = {
		{
			label = `\{ machine = 1, setting = 1 } (both minimums)`,
			value = { machine = 1, setting = 1 },
			expect = "ok",
		},
		{
			label = `\{ machine = {n}, setting = {d} } (actuator_count, dial_settings)`,
			value = { machine = n, setting = d },
			expect = "ok",
		},
		{
			label = `\{ machine = 0, setting = 1 }`,
			value = { machine = 0, setting = 1 },
			expect = "range",
		},
		{
			label = `\{ machine = {n + 1}, setting = 1 } (actuator_count + 1)`,
			value = { machine = n + 1, setting = 1 },
			expect = "range",
		},
		{
			label = `\{ machine = 1, setting = 0 }`,
			value = { machine = 1, setting = 0 },
			expect = "range",
		},
		{
			label = `\{ machine = 1, setting = {d + 1} } (dial_settings + 1)`,
			value = { machine = 1, setting = d + 1 },
			expect = "range",
		},
		{
			label = "{ machine = 1.5, setting = 1 } (non-integer machine)",
			value = { machine = 1.5, setting = 1 },
			expect = "range",
		},
		{
			label = "{ machine = 1, setting = 1.5 } (non-integer setting)",
			value = { machine = 1, setting = 1.5 },
			expect = "range",
		},
		{ label = "{ machine = 1 } (missing setting)", value = { machine = 1 }, expect = "shape" },
		{ label = "{ setting = 1 } (missing machine)", value = { setting = 1 }, expect = "shape" },
		{
			label = "{ machine = 1, setting = 1, position = { x = 0, y = 0, z = 0 } } (extra position)",
			value = { machine = 1, setting = 1, position = { x = 0, y = 0, z = 0 } },
			expect = "shape",
		},
		{
			label = '{ machine = 1, setting = 1, player = "kim" } (extra player)',
			value = { machine = 1, setting = 1, player = "kim" },
			expect = "shape",
		},
		{
			label = '{ machine = "1", setting = 1 } (a string where an integer belongs)',
			value = { machine = "1", setting = 1 },
			expect = "shape",
		},
		{ label = "{} (zero keys)", value = {}, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = '"machine=1" (a string payload)', value = "machine=1", expect = "shape" },
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
			`AC-1: the Turn schema is not \{ machine = integer(1, {n}), setting = integer(1, {d}) } (actuator_count = {n}, dial_settings = {d}) - {#violations} of {#cases} cases:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- Exactly `{ "Round" }`: a list of length one whose only entry is "Round".
function TurnRemoteContract.legalPhasesAreExactlyRound(_net: Net, definition: any)
	requireDefinition("AC-1", definition)
	if not Deep.equal(definition.legalPhases, TurnRemoteContract.LEGAL_PHASES) then
		Contract.fail(
			`AC-1: Turn.legalPhases is {Deep.show(definition.legalPhases)}, expected exactly {Deep.show(
				TurnRemoteContract.LEGAL_PHASES
			)}`
		)
	end
end

-- `rateLimit.minIntervalSeconds` IS `MechanicsTuning.actuation.turn_rate_limit_seconds`.
function TurnRemoteContract.rateLimitIsTheTurnRateLimitFromTuning(_net: Net, definition: any)
	requireDefinition("AC-1", definition)
	local want = TurnRemoteContract.rateLimitSeconds()
	local rateLimit = definition.rateLimit
	if typeof(rateLimit) ~= "table" or rateLimit.minIntervalSeconds ~= want then
		Contract.fail(
			`AC-1: Turn.rateLimit is {Deep.show(rateLimit)}, expected \{ minIntervalSeconds = {want} } (MechanicsTuning.actuation.turn_rate_limit_seconds)`
		)
	end
end

-- PO decision 1: "declares no attempt limit and never declines" is
-- `attemptLimit == nil`. The field does not exist until CHAN-003.
function TurnRemoteContract.declaresNoAttemptLimit(_net: Net, definition: any)
	requireDefinition("AC-1", definition)
	if definition.attemptLimit ~= nil then
		Contract.fail(
			`AC-1: Turn.attemptLimit is {Deep.show(definition.attemptLimit)}; the Turn remote declares no attempt limit (PO decision 1: attemptLimit == nil)`
		)
	end
end

-- `Remotes.all()` lists this very table under its name - by identity, once.
function TurnRemoteContract.isTheDefinitionRemotesAllLists(net: Net, definition: any)
	requireDefinition("AC-1", definition)
	local all = net.Remotes.all()
	local byName: { any } = {}
	for _, entry in all do
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
			`AC-1: the definition Remotes.all() lists as {Deep.show(definition.name)} is not the same table as the Turn definition under test; a copy or a second declaration is not the registered remote`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2, mechanical: malformed calls through the real guard.
     --------------------------------------------------------------------- ]]

export type MalformedCase = { label: string, args: any, expect: string }

function TurnRemoteContract.malformedCases(): { MalformedCase }
	local d = dialSettings()
	local w = TurnRemoteContract.wellFormed()
	return {
		{
			label = `missing setting: \{ machine = {w.machine} }`,
			args = { machine = w.machine },
			expect = "shape",
		},
		{
			label = `machine = 0: \{ machine = 0, setting = {w.setting} }`,
			args = { machine = 0, setting = w.setting },
			expect = "range",
		},
		{
			label = `setting = dial_settings + 1: \{ machine = {w.machine}, setting = {d + 1} }`,
			args = { machine = w.machine, setting = d + 1 },
			expect = "range",
		},
		{
			label = `setting = 1.5: \{ machine = {w.machine}, setting = 1.5 }`,
			args = { machine = w.machine, setting = 1.5 },
			expect = "range",
		},
		{
			label = `an extra player key: \{ machine = {w.machine}, setting = {w.setting}, player = "kim" }`,
			args = { machine = w.machine, setting = w.setting, player = "kim" },
			expect = "shape",
		},
		{
			label = `a string payload: "machine={w.machine},setting={w.setting}"`,
			args = `machine={w.machine},setting={w.setting}`,
			expect = "shape",
		},
	}
end

--[[
	Seated caller, phase Round, so identity and phase cannot be what rejects.
	Each case is rejected for exactly the reason the Contract names, and the
	spy - "the Procedure" - is never called.
]]
function TurnRemoteContract.malformedCallsAreRejectedBeforeTheHandler(net: Net, definition: any)
	requireDefinition("AC-2", definition)
	local guarded, calls = guardWithSpy(net, definition, "Round")
	local cases = TurnRemoteContract.malformedCases()
	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, TurnRemoteContract.CALLER, case.args)
		local violation = expectRejection("AC-2", case.label, ok, result, case.expect)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#cases} malformed payloads; the Procedure must never be consulted for one`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 failed in {#violations} case(s) of {#cases}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3, mechanical: out of phase, and flooded.
     --------------------------------------------------------------------- ]]

-- A well-formed call by a seated caller in each of the four other phases is
-- `phase`, and the spy is never called.
function TurnRemoteContract.wellFormedCallOutOfRoundIsRejectedForPhase(net: Net, definition: any)
	requireDefinition("AC-3", definition)
	local guarded, calls, world = guardWithSpy(net, definition, "Round")
	local violations: { string } = {}
	for _, phase in TurnRemoteContract.ILLEGAL_PHASES do
		world.phase = phase
		local ok, result = call(guarded, TurnRemoteContract.CALLER, TurnRemoteContract.wellFormed())
		local violation = expectRejection(
			"AC-3",
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
			`AC-3: the handler ran {#calls} time(s) across {#TurnRemoteContract.ILLEGAL_PHASES} out-of-phase calls`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 (phase) failed in {#violations} case(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	Two well-formed in-phase calls at `t` and `t + rate - EPSILON`: the second
	is `rate` and the spy count stays at 1. A third at exactly `t + rate`
	passes and the count is 2 - the boundary that keeps a limit that is one
	second too long from passing.
]]
function TurnRemoteContract.secondCallInsideTheTurnRateLimitIsRejectedForRate(
	net: Net,
	definition: any
)
	requireDefinition("AC-3", definition)
	local rate = TurnRemoteContract.rateLimitSeconds()
	local eps = TurnRemoteContract.EPSILON
	assert(
		eps < rate,
		`the fixture's EPSILON {eps} must be smaller than turn_rate_limit_seconds {rate}`
	)
	local guarded, calls, world = guardWithSpy(net, definition, "Round")
	local caller = TurnRemoteContract.CALLER
	local violations: { string } = {}

	world.clock:set(TurnRemoteContract.START)
	local ok1, r1 = call(guarded, caller, TurnRemoteContract.wellFormed())
	local v1 = expectAcceptance("AC-3", "the first well-formed in-phase call, at t", ok1, r1)
	if v1 ~= nil then
		table.insert(violations, v1 :: string)
	end
	if #calls ~= 1 then
		table.insert(
			violations,
			`AC-3: after the first call the handler ran {#calls} time(s), expected 1`
		)
	end

	world.clock:set(TurnRemoteContract.START + rate - eps)
	local ok2, r2 = call(guarded, caller, TurnRemoteContract.wellFormed())
	local v2 = expectRejection(
		"AC-3",
		`the second call at t + {rate} - {eps} (inside turn_rate_limit_seconds = {rate})`,
		ok2,
		r2,
		"rate"
	)
	if v2 ~= nil then
		table.insert(violations, v2 :: string)
	end
	if #calls ~= 1 then
		table.insert(
			violations,
			`AC-3: after the rate-limited second call the handler ran {#calls} time(s) in total; it must stay at 1 - a turn refused for rate is not evaluated`
		)
	end

	world.clock:set(TurnRemoteContract.START + rate)
	local ok3, r3 = call(guarded, caller, TurnRemoteContract.wellFormed())
	local v3 = expectAcceptance("AC-3", `the third call at exactly t + {rate}`, ok3, r3)
	if v3 ~= nil then
		table.insert(violations, v3 :: string)
	end
	if #calls ~= 2 then
		table.insert(
			violations,
			`AC-3: after the third call the handler ran {#calls} time(s) in total, expected 2`
		)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-3 (rate, turn_rate_limit_seconds = {rate}) failed in {#violations} step(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The positive control: a well-formed in-Round call reaches the handler.
     A definition that rejects everything passes AC-2 and the phase half of
     AC-3 and fails here (and the rate half, whose first call it refuses).
     --------------------------------------------------------------------- ]]

function TurnRemoteContract.wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting(
	net: Net,
	definition: any
)
	requireDefinition("AC-2/AC-3 positive control", definition)
	local violations: { string } = {}
	for _, payload in
		{ TurnRemoteContract.wellFormed(), TurnRemoteContract.wellFormedAtTheMaximum() }
	do
		local guarded, calls = guardWithSpy(net, definition, "Round")
		local ok, result = call(guarded, TurnRemoteContract.CALLER, payload)
		local label = Deep.show(payload)
		local violation = expectAcceptance("AC-2/AC-3 positive control", label, ok, result)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		elseif #calls ~= 1 then
			table.insert(
				violations,
				`{label} -> the handler ran {#calls} time(s), expected exactly once`
			)
		else
			if calls[1].playerId ~= TurnRemoteContract.CALLER then
				table.insert(
					violations,
					`{label} -> the handler received playerId {Deep.show(calls[1].playerId)}, expected "{TurnRemoteContract.CALLER}"`
				)
			end
			if not Deep.equal(calls[1].args, payload) then
				table.insert(
					violations,
					`{label} -> the handler received args {Deep.show(calls[1].args)}, expected exactly the payload`
				)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2/AC-3 positive control: a well-formed in-Round call by the seated caller must reach the handler once with exactly \{ machine, setting }:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The battery, named, so the controls can run every check against a
     definition and report exactly which fire.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Net, any) -> () }

TurnRemoteContract.CHECKS = {
	{
		name = "schemaIsIntegerMachineAndSettingAtTheTuningBounds",
		ac = "AC-1",
		run = TurnRemoteContract.schemaIsIntegerMachineAndSettingAtTheTuningBounds,
	},
	{
		name = "legalPhasesAreExactlyRound",
		ac = "AC-1",
		run = TurnRemoteContract.legalPhasesAreExactlyRound,
	},
	{
		name = "rateLimitIsTheTurnRateLimitFromTuning",
		ac = "AC-1",
		run = TurnRemoteContract.rateLimitIsTheTurnRateLimitFromTuning,
	},
	{
		name = "declaresNoAttemptLimit",
		ac = "AC-1",
		run = TurnRemoteContract.declaresNoAttemptLimit,
	},
	{
		name = "isTheDefinitionRemotesAllLists",
		ac = "AC-1",
		run = TurnRemoteContract.isTheDefinitionRemotesAllLists,
	},
	{
		name = "malformedCallsAreRejectedBeforeTheHandler",
		ac = "AC-2",
		run = TurnRemoteContract.malformedCallsAreRejectedBeforeTheHandler,
	},
	{
		name = "wellFormedCallOutOfRoundIsRejectedForPhase",
		ac = "AC-3",
		run = TurnRemoteContract.wellFormedCallOutOfRoundIsRejectedForPhase,
	},
	{
		name = "secondCallInsideTheTurnRateLimitIsRejectedForRate",
		ac = "AC-3",
		run = TurnRemoteContract.secondCallInsideTheTurnRateLimitIsRejectedForRate,
	},
	{
		name = "wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting",
		ac = "positive control",
		run = TurnRemoteContract.wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting,
	},
} :: { Check }

-- Every check against `definition`; the names of those that raised, with
-- their messages, in CHECKS order.
function TurnRemoteContract.failures(
	net: Net,
	definition: any
): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in TurnRemoteContract.CHECKS do
		local ok, err = pcall(check.run, net, definition)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return TurnRemoteContract
