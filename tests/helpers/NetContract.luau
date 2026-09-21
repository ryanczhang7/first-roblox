--!strict
--[[
	NET-001 AC-1 through AC-6 and AC-8, plus the Contract's own promises, written
	once as checks over a `Net` bundle - `{ Schema, Remotes, Wrapper }` - handed
	in as a parameter rather than over `src/net/*.luau` by name. The same
	arrangement as `TelemetryContract.luau` and `ProjectionContract.luau`, for
	the same reason.

	`tests/net/schema_test.luau`, `tests/net/remotes_test.luau` and
	`tests/net/wrapper_test.luau` apply these to the real modules.
	`tests/net/net_controls_test.luau` applies them to the deliberately wrong
	bundles in `NetStubs.luau`, so that in RED - where the production modules
	do not exist, the real files fail to load, and not one assertion in them
	has executed - every check here has still been EXECUTED and observed to
	reject the implementation it exists to catch. AC-7 is not here: it is a
	tree-scanning guard and lives in `tests/net/raw_remote_guard_test.luau`.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1..AC-4 and AC-8 are mechanical
	and pinned exactly, with the Contract's fixed readings: "wrong number of
	arguments" is a KEY COUNT under the one-payload signature, `rawArgs` being
	nil or a non-table is `shape`, and a non-integer where an integer is
	declared is `range` because 3.5 IS a number and the integers in [1, 16]
	are a domain. AC-5 and AC-6 are mechanical with the controls the criteria
	name - the reject-everything wrapper and the boolean-false wrapper - and
	`NetStubs.luau` writes both out. Nothing here is designed; it is read out
	of the story's `## Contract`.

	THE TEST REMOTE. `## Out of scope` says no real remote of the game is
	declared here, so every wrapper check declares its own:

	    args = Schema.shape({ token = Schema.integer(1, 16), flag = Schema.boolean() })

	Two fields, so that a payload can carry a `range` failure in one and a
	`shape` failure in the other - which is how the pipeline order inside one
	payload is pinned (AC-6). Names are unique per declaration because
	`Remotes` is a module-level registry that refuses a duplicate (AC-8), and
	the real suite and the controls suite share one process.

	THE FAILURE STRING PROTOCOL. The Contract's `Schema` type is structural -
	`{ validate: (any) -> (boolean, string?) }` - so a hand-written schema is a
	legal `args` and the wrapper has to read the KIND of a failure out of the
	string. The checks read it as the first word before a colon:
	`"shape: ..."` or `"range: ..."`. That is pinned in the story's Contract
	(amended in RED, with the reason beside it), and `kindOf` below is the one
	place the rule is spelled.

	Every message names its criterion, because the controls assert on the text.
]]

local Clock = require("../../src/shared/Clock")
local Deep = require("./Deep")

local NetContract = {}

export type Net = { Schema: any, Remotes: any, Wrapper: any }

export type Case = { label: string, args: any }

--[[
	The final assertion of every check goes through this rather than `assert`.
	MEASURED in SEAT-002's RED: under Lune, `assert(false, message)` truncates
	the message to 512 characters after the location prefix and `error` does
	not. The checks accumulate every violation, and a control whose needle lies
	beyond the cut can never match. Level 2 attributes the failure to the
	caller.
]]
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

local NAN = 0 / 0

NetContract.REASONS = { "identity", "shape", "range" }

local KNOWN_REASON: { [string]: boolean } = { identity = true, shape = true, range = true }

-- Unique per process, because `Remotes.define` refuses a duplicate name and the
-- runner loads every file into one process.
local declared = 0
local function uniqueName(label: string): string
	declared += 1
	return `NetTest_{label}_{declared}`
end

NetContract.uniqueName = uniqueName

--[[
	The kind a failure string leads with, or a readable non-answer. A substring
	search either way ("contains shape") is a needle whose negation is also a
	match, so the rule is anchored at the start of the string.
]]
local function kindOf(failure: any): string
	if typeof(failure) ~= "string" then
		return `<no failure string: {Deep.show(failure)}>`
	end
	local kind = string.match(failure :: string, "^(%l+):")
	if kind == nil then
		return `<failure string does not lead with a kind: "{failure}">`
	end
	return kind :: string
end

NetContract.kindOf = kindOf

--[[ ------------------------------------------------------------------------
     Fixtures
     ------------------------------------------------------------------------ ]]

-- A `GuardContext` in which exactly the listed players are seated. `phase` and
-- `clock` are the Contract's, present so that NET-002 and NET-003 change the
-- context by reading two fields that already exist; nothing here reads them.
function NetContract.context(seated: { string }, asked: { any }?): any
	local seatedSet: { [any]: boolean } = {}
	for _, id in seated do
		seatedSet[id] = true
	end
	return {
		isSeated = function(playerId: any): boolean
			if asked ~= nil then
				table.insert(asked :: { any }, playerId)
			end
			return seatedSet[playerId] == true
		end,
		phase = function(): string
			return "Round"
		end,
		clock = Clock.manual(0),
	}
end

-- The test remote, declared through the registry so that the definition the
-- wrapper receives is the one `Remotes.define` returns.
function NetContract.tokenRemote(net: Net, label: string): any
	return net.Remotes.define(uniqueName(label), {
		args = net.Schema.shape({
			token = net.Schema.integer(1, 16),
			flag = net.Schema.boolean(),
		}),
		legalPhases = { "Round" },
	})
end

-- A handler that records every invocation, so "ran exactly once" is a count.
function NetContract.recorder(): (any, { { playerId: any, args: any } })
	local calls: { { playerId: any, args: any } } = {}
	local handler = function(playerId: any, args: any)
		table.insert(calls, { playerId = playerId, args = args })
	end
	return handler, calls
end

local VALID = { token = 4, flag = true }

--[[
	AC-2's cases, with the Contract's reading of each phrase. `rawArgs` is one
	payload, so arity is key count; nil and non-table payloads are the two the
	signature admits and the prose does not name. A case with no `args` key IS
	the nil case.
]]
NetContract.SHAPE_CASES = {
	{ label = "wrong number of arguments (zero keys): {}", args = {} },
	{
		label = "wrong number of arguments (one key too many): { token = 4, flag = true, extra = 1 }",
		args = { token = 4, flag = true, extra = 1 },
	},
	{ label = 'wrong type: { token = "4", flag = true }', args = { token = "4", flag = true } },
	{
		label = "wrong type (a table where a number belongs): { token = {}, flag = true }",
		args = { token = {}, flag = true },
	},
	{ label = 'wrong type: { token = 4, flag = "true" }', args = { token = 4, flag = "true" } },
	{ label = "wrong type: { token = true, flag = true }", args = { token = true, flag = true } },
	{ label = "missing required field: { flag = true }", args = { flag = true } },
	{ label = "missing required field: { token = 4 }", args = { token = 4 } },
	{
		label = "extra unexpected field: { token = 4, flag = true, admin = true }",
		args = { token = 4, flag = true, admin = true },
	},
	{ label = "rawArgs is nil", args = nil },
	{ label = "rawArgs is a number: 7", args = 7 },
	{ label = 'rawArgs is a string: "token=4"', args = "token=4" },
	{ label = "rawArgs is a boolean: true", args = true },
	{ label = "rawArgs is a function", args = function() end },
} :: { Case }

-- AC-3's five cases, plus -inf, which is "below the minimum" for a number that
-- is not NaN.
NetContract.RANGE_CASES = {
	{ label = "below the minimum: token = 0", args = { token = 0, flag = true } },
	{ label = "above the maximum: token = 17", args = { token = 17, flag = true } },
	{ label = "NaN: token = 0/0", args = { token = NAN, flag = true } },
	{ label = "math.huge: token = math.huge", args = { token = math.huge, flag = true } },
	{ label = "-math.huge: token = -math.huge", args = { token = -math.huge, flag = true } },
	{
		label = "a non-integer where an integer is declared: token = 3.5",
		args = { token = 3.5, flag = true },
	},
} :: { Case }

-- AC-5's valid calls: both inclusive ends and both booleans.
NetContract.VALID_CASES = {
	{ label = "{ token = 4, flag = true }", args = { token = 4, flag = true } },
	{ label = "{ token = 1, flag = true } (the minimum)", args = { token = 1, flag = true } },
	{ label = "{ token = 16, flag = false } (the maximum)", args = { token = 16, flag = false } },
	{ label = "{ token = 8, flag = false }", args = { token = 8, flag = false } },
} :: { Case }

local function describeResult(result: any): string
	if typeof(result) == "table" then
		return `reason = {Deep.show(result.reason)}, detail = {Deep.show(result.detail)}`
	end
	return Deep.show(result)
end

--[[
	One guarded call, with the outcome classified for the accumulators. `raised`
	is its own outcome because the Contract says the guarded function never
	raises, and a raise inside a `pcall`-less loop would end the check at the
	first hostile payload and hide the rest.
]]
local function call(guarded: any, playerId: any, args: any): (boolean, any)
	local ok, result = pcall(guarded, playerId, args)
	return ok, result
end

--[[
	The per-case expectation for the rejection checks: no raise, a table, the
	expected reason. Returns a violation line or nil.
]]
local function expectRejection(
	criterion: string,
	case: Case,
	ok: boolean,
	result: any,
	expected: string
): string?
	if not ok then
		return `{criterion}: {case.label} -> the guarded call RAISED instead of rejecting: {tostring(
			result
		)}`
	end
	if result == nil then
		return `{criterion}: {case.label} -> ACCEPTED (returned nil); the handler was reachable`
	end
	if typeof(result) ~= "table" then
		return `{criterion}: {case.label} -> rejected with {Deep.show(result)}, which names no check`
	end
	if result.reason ~= expected then
		return `{criterion}: {case.label} -> rejected for {Deep.show(result.reason)}, expected "{expected}"`
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     The wrapper: AC-1 to AC-6
     ------------------------------------------------------------------------ ]]

--[[
	AC-1. The count is the assertion: "it ran" is weaker than "it ran once", and
	the second call is what pins "once PER CALL" rather than "once ever". The
	arguments the handler receives are compared structurally to what was sent.
]]
function NetContract.handlerRunsExactlyOnceWithTheValidatedArguments(net: Net)
	local definition = NetContract.tokenRemote(net, "ac1")
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local ok, result = call(guarded, "p1", { token = 4, flag = true })
	check(ok, `AC-1: a valid call raised: {tostring(result)}`)
	check(
		result == nil,
		`AC-1: a valid call by a seated player was rejected: {describeResult(result)}`
	)
	check(
		#calls == 1,
		`AC-1: the handler ran {#calls} time(s) for one valid call; it must run exactly once`
	)
	check(
		calls[1].playerId == "p1",
		`AC-1: the handler received playerId {Deep.show(calls[1].playerId)}, expected "p1"`
	)
	local diff = Deep.diff({ token = 4, flag = true }, calls[1].args)
	check(
		diff == "",
		`AC-1: the handler did not receive the validated arguments:\n{indent(diff)}\n`
			.. `  received: {Deep.show(calls[1].args)}`
	)

	local ok2, result2 = call(guarded, "p1", { token = 16, flag = false })
	check(
		ok2 and result2 == nil,
		`AC-1: a second valid call was not accepted: {describeResult(result2)}`
	)
	check(
		#calls == 2,
		`AC-1: after two valid calls the handler ran {#calls} time(s); once per call means 2`
	)
	local diff2 = Deep.diff({ token = 16, flag = false }, calls[2].args)
	check(diff2 == "", `AC-1: the second call's arguments were wrong:\n{indent(diff2)}`)
end

--[[
	AC-2. Every case is `shape`, the handler never runs, and the guarded call
	never raises - a raise is reported as its own violation rather than ending
	the loop. Violations are accumulated and reported once, by label.
]]
function NetContract.malformedPayloadIsRejectedForShape(net: Net)
	local definition = NetContract.tokenRemote(net, "ac2")
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local violations: { string } = {}
	for _, case in NetContract.SHAPE_CASES do
		local ok, result = call(guarded, "p1", case.args)
		local violation = expectRejection("AC-2", case, ok, result, "shape")
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#NetContract.SHAPE_CASES} malformed payloads; `
				.. `it must not run at all`
		)
	end
	check(
		#violations == 0,
		`AC-2 failed in {#violations} case(s) of {#NetContract.SHAPE_CASES}:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	AC-3. Every case is `range` - and `range` is by construction distinct from
	`shape`, so an implementation that files 3.5 or NaN under `shape` fails by
	name here rather than passing a test that only asked "rejected".
]]
function NetContract.outOfRangeNumberIsRejectedForRange(net: Net)
	local definition = NetContract.tokenRemote(net, "ac3")
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local violations: { string } = {}
	for _, case in NetContract.RANGE_CASES do
		local ok, result = call(guarded, "p1", case.args)
		local violation = expectRejection("AC-3", case, ok, result, "range")
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) across {#NetContract.RANGE_CASES} out-of-range payloads`
		)
	end
	check(
		#violations == 0,
		`AC-3 failed in {#violations} case(s) of {#NetContract.RANGE_CASES}:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	AC-4. The payload is VALID, so identity is the only check that can fire; and
	`isSeated` is a spy, so the check is shown to have asked about the caller
	rather than about nobody.
]]
function NetContract.unseatedPlayerIsRejectedForIdentity(net: Net)
	local definition = NetContract.tokenRemote(net, "ac4")
	local handler, calls = NetContract.recorder()
	local asked: { any } = {}
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }, asked), handler)

	local violations: { string } = {}
	for _, stranger in { "p2", "", "P1" } do
		local ok, result = call(guarded, stranger, VALID)
		local violation = expectRejection(
			"AC-4",
			{ label = `unseated player {Deep.show(stranger)} with a valid payload`, args = VALID },
			ok,
			result,
			"identity"
		)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(violations, `AC-4: the handler ran {#calls} time(s) for unseated players`)
	end
	local askedAboutP2 = false
	for _, id in asked do
		if id == "p2" then
			askedAboutP2 = true
		end
	end
	if not askedAboutP2 then
		table.insert(
			violations,
			`AC-4: context.isSeated was never asked about "p2"; it was asked about: {Deep.show(
				asked
			)}`
		)
	end
	check(#violations == 0, `AC-4 failed:\n{indent(table.concat(violations, "\n"))}`)
end

--[[
	AC-5, the positive control. A wrapper that rejects everything passes AC-2,
	AC-3 and AC-4 and fails exactly here: every valid call must come back nil.
]]
function NetContract.validCallIsAccepted(net: Net)
	local definition = NetContract.tokenRemote(net, "ac5")
	local handler = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local violations: { string } = {}
	for _, case in NetContract.VALID_CASES do
		local ok, result = call(guarded, "p1", case.args)
		if not ok then
			table.insert(violations, `AC-5: valid call {case.label} RAISED: {tostring(result)}`)
		elseif result ~= nil then
			table.insert(
				violations,
				`AC-5: valid call {case.label} by a seated player was REJECTED: {describeResult(
					result
				)}`
			)
		end
	end
	check(
		#violations == 0,
		`AC-5 failed in {#violations} case(s) of {#NetContract.VALID_CASES} - a wrapper that rejects `
			.. `everything fails here:\n{indent(table.concat(violations, "\n"))}`
	)
end

--[[
	AC-6, first half: every rejection is a `Rejection` - a table whose `reason`
	is one of the three checks and whose `detail` is a non-empty string. A
	single boolean `false` fails this on every case.
]]
function NetContract.rejectionNamesTheCheckThatFired(net: Net)
	local definition = NetContract.tokenRemote(net, "ac6")
	local handler = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local cases: { { label: string, playerId: string, args: any } } = {
		{ label = "identity: unseated player, valid payload", playerId = "p2", args = VALID },
	}
	for _, case in NetContract.SHAPE_CASES do
		table.insert(cases, { label = case.label, playerId = "p1", args = case.args })
	end
	for _, case in NetContract.RANGE_CASES do
		table.insert(cases, { label = case.label, playerId = "p1", args = case.args })
	end

	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, case.playerId, case.args)
		if not ok then
			table.insert(violations, `AC-6: {case.label} -> RAISED: {tostring(result)}`)
		elseif typeof(result) ~= "table" then
			table.insert(
				violations,
				`AC-6: {case.label} -> the rejection is {Deep.show(result)}, not a table naming the check that fired`
			)
		elseif typeof(result.reason) ~= "string" or not KNOWN_REASON[result.reason] then
			table.insert(
				violations,
				`AC-6: {case.label} -> reason is {Deep.show(result.reason)}; must be one of identity, shape, range`
			)
		elseif typeof(result.detail) ~= "string" or result.detail == "" then
			table.insert(
				violations,
				`AC-6: {case.label} -> detail is {Deep.show(result.detail)}; must be a non-empty string`
			)
		end
	end
	check(
		#violations == 0,
		`AC-6 failed in {#violations} case(s) of {#cases} - an implementation returning a single `
			.. `boolean false fails here:\n{indent(table.concat(violations, "\n"))}`
	)
end

--[[
	AC-6, second half: the order. identity before shape before range, first
	failure wins. The two-field payload is what makes shape-before-range
	observable inside ONE payload: `token = 99` is a range failure and
	`flag = "no"` a shape failure, and the pipeline order says `shape`. The
	`range` case beside it is what stops "always shape" from passing.
]]
function NetContract.checksRunIdentityThenShapeThenRange(net: Net)
	local definition = NetContract.tokenRemote(net, "ac6order")
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local cases: { { label: string, playerId: string, args: any, expected: string } } = {
		{
			label = "unseated + {} (arity) -> identity",
			playerId = "p2",
			args = {},
			expected = "identity",
		},
		{
			label = "unseated + { token = 99, flag = true } (range) -> identity",
			playerId = "p2",
			args = { token = 99, flag = true },
			expected = "identity",
		},
		{
			label = "unseated + nil -> identity",
			playerId = "p2",
			args = nil,
			expected = "identity",
		},
		{
			label = "unseated + 7 (non-table) -> identity",
			playerId = "p2",
			args = 7,
			expected = "identity",
		},
		{
			label = 'unseated + { token = "x", flag = 1 } (shape) -> identity',
			playerId = "p2",
			args = { token = "x", flag = 1 },
			expected = "identity",
		},
		{
			label = 'seated + { token = 99, flag = "no" } (range in one field, shape in the other) -> shape',
			playerId = "p1",
			args = { token = 99, flag = "no" },
			expected = "shape",
		},
		{
			label = "seated + { token = 0/0, flag = 1 } (NaN in one field, shape in the other) -> shape",
			playerId = "p1",
			args = { token = NAN, flag = 1 },
			expected = "shape",
		},
		{
			label = "seated + { token = 99, flag = true } (range only) -> range",
			playerId = "p1",
			args = { token = 99, flag = true },
			expected = "range",
		},
	}

	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, case.playerId, case.args)
		local violation = expectRejection(
			"AC-6 order",
			{ label = case.label, args = case.args },
			ok,
			result,
			case.expected
		)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-6 order: the handler ran {#calls} time(s); every case is a rejection`
		)
	end
	check(
		#violations == 0,
		`AC-6 order failed in {#violations} case(s) of {#cases}:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[ ------------------------------------------------------------------------
     The wrapper: the Contract's own promises
     ------------------------------------------------------------------------ ]]

-- Contract: "It never raises: an exploiter must not be able to error a server
-- thread by sending a table where a number belongs." Hostile payloads AND
-- hostile player ids; every outcome is nil or a Rejection.
function NetContract.guardedCallNeverRaises(net: Net)
	local definition = NetContract.tokenRemote(net, "noraise")
	local handler = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local deep: any = { token = 4, flag = true }
	for _ = 1, 40 do
		deep = { token = deep, flag = true }
	end

	local hostile: { { label: string, playerId: any, args: any } } = {
		{ label = "a function as rawArgs", playerId = "p1", args = function() end },
		{ label = "a thread as rawArgs", playerId = "p1", args = coroutine.create(function() end) },
		{
			label = "a table where a number belongs",
			playerId = "p1",
			args = { token = {}, flag = true },
		},
		{
			label = "a function where a boolean belongs",
			playerId = "p1",
			args = { token = 4, flag = print },
		},
		{ label = "a payload nested 40 deep", playerId = "p1", args = deep },
		{
			label = "a table-valued key",
			playerId = "p1",
			args = { token = 4, flag = true, [{}] = 1 },
		},
		{ label = "an array payload", playerId = "p1", args = { 4, true } },
		{ label = "a 100 KB string as rawArgs", playerId = "p1", args = string.rep("x", 100_000) },
		{ label = "negative zero", playerId = "p1", args = { token = -0, flag = true } },
		{ label = "2^63", playerId = "p1", args = { token = 2 ^ 63, flag = true } },
		{ label = "a numeric playerId", playerId = 123, args = VALID },
		{ label = "a nil playerId", playerId = nil, args = VALID },
		{ label = "a table playerId", playerId = {}, args = VALID },
		{ label = "nil and nil", playerId = nil, args = nil },
	}

	local violations: { string } = {}
	for _, case in hostile do
		local ok, result = call(guarded, case.playerId, case.args)
		if not ok then
			table.insert(violations, `never raises: {case.label} -> RAISED: {tostring(result)}`)
		elseif result ~= nil and typeof(result) ~= "table" then
			table.insert(
				violations,
				`never raises: {case.label} -> returned {Deep.show(result)}, which is neither nil nor a Rejection`
			)
		end
	end
	check(
		#violations == 0,
		`the guarded function raised or returned a non-Rejection in {#violations} case(s) of {#hostile}:\n`
			.. indent(table.concat(violations, "\n"))
	)
end

--[[
	Contract: "First failure wins and short-circuits." With a spy schema, an
	unseated caller must be rejected for identity WITHOUT the schema being
	consulted; a seated caller must reach it. The Contract's `Schema` type is
	structural, so a hand-written `{ validate }` is a legal `args`.
]]
function NetContract.identityFailureShortCircuitsBeforeTheSchema(net: Net)
	local consulted = 0
	local spy = {
		validate = function(_value: any): (boolean, string?)
			consulted += 1
			return true, nil
		end,
	}
	local definition = net.Remotes.define(uniqueName("shortcircuit"), {
		args = spy,
		legalPhases = { "Round" },
	})
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	local ok, result = call(guarded, "p2", { anything = 1 })
	check(ok, `short-circuit: the unseated call raised: {tostring(result)}`)
	check(
		typeof(result) == "table" and result.reason == "identity",
		`short-circuit: the unseated call was not rejected for identity: {describeResult(result)}`
	)
	check(
		consulted == 0,
		`short-circuit: the schema was consulted {consulted} time(s) for an unseated caller; identity `
			.. `fails first and nothing after it runs`
	)
	check(#calls == 0, `short-circuit: the handler ran {#calls} time(s) for an unseated caller`)

	local ok2, result2 = call(guarded, "p1", { anything = 1 })
	check(
		ok2 and result2 == nil,
		`short-circuit: the seated call was not accepted: {describeResult(result2)}`
	)
	check(
		consulted == 1,
		`short-circuit: the schema was consulted {consulted} time(s) for one seated call`
	)
	check(#calls == 1, `short-circuit: the handler ran {#calls} time(s) for one accepted call`)
end

--[[
	Contract: the wrapper reads the kind off the schema's failure string. A
	schema that says "range: ..." yields a `range` rejection carrying that
	detail; "shape: ..." yields `shape`; `true` is acceptance.
]]
function NetContract.wrapperReadsTheKindFromTheSchemasFailureString(net: Net)
	local answer: any = true
	local message: string? = nil
	local spy = {
		validate = function(_value: any): (boolean, string?)
			return answer, message
		end,
	}
	local definition =
		net.Remotes.define(uniqueName("kind"), { args = spy, legalPhases = { "Round" } })
	local handler, calls = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, NetContract.context({ "p1" }), handler)

	answer, message = false, "range: token 99 is above the maximum 16"
	local ok, result = call(guarded, "p1", { token = 99 })
	check(ok, `kind: the range call raised: {tostring(result)}`)
	check(
		typeof(result) == "table" and result.reason == "range",
		`kind: "range: ..." from the schema became {describeResult(result)}, expected reason "range"`
	)
	check(
		typeof(result) == "table"
			and typeof(result.detail) == "string"
			and string.find(result.detail, "token 99 is above the maximum 16", 1, true) ~= nil,
		`kind: the rejection's detail does not carry the schema's text: {describeResult(result)}`
	)

	answer, message = false, "shape: expected a table"
	local ok2, result2 = call(guarded, "p1", 7)
	check(ok2, `kind: the shape call raised: {tostring(result2)}`)
	check(
		typeof(result2) == "table" and result2.reason == "shape",
		`kind: "shape: ..." from the schema became {describeResult(result2)}, expected reason "shape"`
	)

	answer, message = true, nil
	local ok3, result3 = call(guarded, "p1", { token = 4 })
	check(
		ok3 and result3 == nil,
		`kind: a schema that accepts did not lead to acceptance: {describeResult(result3)}`
	)
	check(
		#calls == 1,
		`kind: the handler ran {#calls} time(s) across two rejections and one acceptance`
	)
end

--[[ ------------------------------------------------------------------------
     Remotes: the registry and AC-8
     ------------------------------------------------------------------------ ]]

--[[
	Contract: `define` returns the declaration with the four fields as given
	(`rateLimit` optional), and `all()` lists it. `all()` returns a COPY: a
	live registry handed out is the quiet way a validated remote becomes an
	unvalidated one, which is AC-8's semantics from the other side.
]]
function NetContract.defineReturnsTheDeclarationAndAllListsIt(net: Net)
	local schema = net.Schema.shape({ token = net.Schema.integer(1, 16) })
	local name = uniqueName("define")
	local before = #net.Remotes.all()
	local definition = net.Remotes.define(name, {
		args = schema,
		legalPhases = { "Round", "Lobby" },
		rateLimit = { minIntervalSeconds = 1.5 },
	})

	check(
		typeof(definition) == "table",
		`define returned {Deep.show(definition)}, not a definition`
	)
	check(
		definition.name == name,
		`definition.name is {Deep.show(definition.name)}, expected "{name}"`
	)
	check(definition.args == schema, `definition.args is not the schema that was declared`)
	local phases = Deep.diff({ "Round", "Lobby" }, definition.legalPhases)
	check(phases == "", `definition.legalPhases differs from what was declared:\n{indent(phases)}`)
	local rate = Deep.diff({ minIntervalSeconds = 1.5 }, definition.rateLimit)
	check(rate == "", `definition.rateLimit differs from what was declared:\n{indent(rate)}`)

	local all = net.Remotes.all()
	check(typeof(all) == "table", `Remotes.all() returned {Deep.show(all)}`)
	check(
		#all == before + 1,
		`Remotes.all() has {#all} entries after one define; it had {before} before`
	)
	local listed = false
	for _, entry in all do
		if entry == definition then
			listed = true
		end
	end
	check(listed, `Remotes.all() does not contain the definition define() returned`)

	-- The optional field is optional.
	local bare =
		net.Remotes.define(uniqueName("bare"), { args = schema, legalPhases = { "Round" } })
	check(
		bare.rateLimit == nil,
		`a declaration with no rateLimit has rateLimit = {Deep.show(bare.rateLimit)}`
	)

	-- A copy, not the registry.
	local escaped = net.Remotes.all()
	table.insert(escaped, { name = "Smuggled", args = schema, legalPhases = {} })
	local smuggled = false
	for _, entry in net.Remotes.all() do
		if entry.name == "Smuggled" then
			smuggled = true
		end
	end
	check(
		not smuggled,
		`Remotes.all() hands out the live registry; a caller inserted a definition into it`
	)
end

--[[
	AC-8. The second declaration FAILS - raises, naming the name - and the
	registry still holds the first, by identity. A registry that silently
	replaces passes "define twice" and ships.
]]
function NetContract.redeclaringANameFails(net: Net)
	local name = uniqueName("ac8")
	local first = net.Remotes.define(name, {
		args = net.Schema.shape({ token = net.Schema.integer(1, 16) }),
		legalPhases = { "Round" },
	})
	local before = #net.Remotes.all()

	local looser = net.Schema.shape({})
	local ok, err = pcall(net.Remotes.define, name, { args = looser, legalPhases = { "Round" } })
	check(
		ok == false,
		`AC-8: declaring "{name}" a second time did not fail; it returned {Deep.show(err)}`
	)
	check(
		string.find(tostring(err), name, 1, true) ~= nil,
		`AC-8: the failure does not name the duplicated remote "{name}": {tostring(err)}`
	)

	local all = net.Remotes.all()
	check(
		#all == before,
		`AC-8: the registry has {#all} entries after the refused declaration; it had {before}`
	)
	local kept, replaced = false, false
	for _, entry in all do
		if entry == first then
			kept = true
		elseif entry.name == name then
			replaced = true
		end
	end
	check(kept, `AC-8: the first declaration of "{name}" is no longer in Remotes.all()`)
	check(
		not replaced,
		`AC-8: a different declaration of "{name}" is in Remotes.all(); the first was replaced`
	)
	check(first.args ~= looser, `AC-8: the first declaration's schema was overwritten in place`)

	-- The registry is not poisoned by the refusal.
	local other =
		net.Remotes.define(uniqueName("ac8other"), { args = looser, legalPhases = { "Round" } })
	check(
		typeof(other) == "table",
		`AC-8: a fresh name could not be declared after a refused duplicate`
	)
end

--[[ ------------------------------------------------------------------------
     Schema: the validators, where the logic lives
     ------------------------------------------------------------------------ ]]

type Expectation = { label: string, value: any, expect: string }

-- `expect` is "ok", "shape" or "range". Accumulates every mismatch.
local function runExpectations(who: string, schema: any, cases: { Expectation }): { string }
	local violations: { string } = {}
	for _, case in cases do
		local ok, valid, failure = pcall(schema.validate, case.value)
		if not ok then
			table.insert(violations, `{who}: {case.label} -> validate RAISED: {tostring(valid)}`)
		elseif case.expect == "ok" then
			if valid ~= true then
				table.insert(
					violations,
					`{who}: {case.label} -> rejected ({Deep.show(failure)}), expected acceptance`
				)
			elseif failure ~= nil then
				table.insert(
					violations,
					`{who}: {case.label} -> accepted but returned a failure string too: {Deep.show(
						failure
					)}`
				)
			end
		else
			if valid ~= false then
				table.insert(
					violations,
					`{who}: {case.label} -> accepted, expected a {case.expect} failure`
				)
			else
				local kind = kindOf(failure)
				if kind ~= case.expect then
					table.insert(
						violations,
						`{who}: {case.label} -> failed as {kind}, expected {case.expect}`
					)
				end
			end
		end
	end
	return violations
end

local function report(who: string, violations: { string }, total: number)
	check(
		#violations == 0,
		`{who} failed in {#violations} case(s) of {total}:\n{indent(table.concat(violations, "\n"))}`
	)
end

function NetContract.integerSchemaAcceptsTheInclusiveDomainAndRejectsByKind(net: Net)
	local schema = net.Schema.integer(1, 16)
	local cases: { Expectation } = {
		{ label = "1 (the minimum)", value = 1, expect = "ok" },
		{ label = "16 (the maximum)", value = 16, expect = "ok" },
		{ label = "4", value = 4, expect = "ok" },
		{ label = "0 (below)", value = 0, expect = "range" },
		{ label = "17 (above)", value = 17, expect = "range" },
		{ label = "-1", value = -1, expect = "range" },
		{ label = "NaN", value = NAN, expect = "range" },
		{ label = "math.huge", value = math.huge, expect = "range" },
		{ label = "-math.huge", value = -math.huge, expect = "range" },
		{ label = "3.5 (non-integer)", value = 3.5, expect = "range" },
		{ label = "0.999 (non-integer, below)", value = 0.999, expect = "range" },
		{ label = "16.5 (non-integer, above)", value = 16.5, expect = "range" },
		{ label = '"4" (a string)', value = "4", expect = "shape" },
		{ label = "true", value = true, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = "{}", value = {}, expect = "shape" },
		{ label = "{ 4 }", value = { 4 }, expect = "shape" },
		{ label = "a function", value = function() end, expect = "shape" },
	}
	report("Schema.integer(1, 16)", runExpectations("Schema.integer(1, 16)", schema, cases), #cases)

	-- A single-point domain, and a negative one: the bounds are read, not assumed.
	local point = runExpectations("Schema.integer(3, 3)", net.Schema.integer(3, 3), {
		{ label = "3", value = 3, expect = "ok" },
		{ label = "2", value = 2, expect = "range" },
		{ label = "4", value = 4, expect = "range" },
	})
	local negative = runExpectations("Schema.integer(-5, -1)", net.Schema.integer(-5, -1), {
		{ label = "-5", value = -5, expect = "ok" },
		{ label = "-1", value = -1, expect = "ok" },
		{ label = "0", value = 0, expect = "range" },
		{ label = "-6", value = -6, expect = "range" },
		{ label = "-2.5", value = -2.5, expect = "range" },
	})
	report("Schema.integer bounds", table.move(negative, 1, #negative, #point + 1, point), 8)
end

function NetContract.numberSchemaAcceptsTheInclusiveDomainAndRejectsByKind(net: Net)
	local schema = net.Schema.number(0, 1.5)
	local cases: { Expectation } = {
		{ label = "0 (the minimum)", value = 0, expect = "ok" },
		{ label = "1.5 (the maximum)", value = 1.5, expect = "ok" },
		{ label = "0.75", value = 0.75, expect = "ok" },
		{ label = "1", value = 1, expect = "ok" },
		{ label = "-0.1 (below)", value = -0.1, expect = "range" },
		{ label = "1.6 (above)", value = 1.6, expect = "range" },
		{ label = "NaN", value = NAN, expect = "range" },
		{ label = "math.huge", value = math.huge, expect = "range" },
		{ label = "-math.huge", value = -math.huge, expect = "range" },
		{ label = '"0.5" (a string)', value = "0.5", expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = "true", value = true, expect = "shape" },
		{ label = "{}", value = {}, expect = "shape" },
	}
	report("Schema.number(0, 1.5)", runExpectations("Schema.number(0, 1.5)", schema, cases), #cases)
end

function NetContract.booleanSchemaAcceptsOnlyBooleans(net: Net)
	local schema = net.Schema.boolean()
	local cases: { Expectation } = {
		{ label = "true", value = true, expect = "ok" },
		{ label = "false", value = false, expect = "ok" },
		{ label = "1", value = 1, expect = "shape" },
		{ label = "0", value = 0, expect = "shape" },
		{ label = '"true"', value = "true", expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = "{}", value = {}, expect = "shape" },
	}
	report("Schema.boolean()", runExpectations("Schema.boolean()", schema, cases), #cases)
end

function NetContract.literalSchemaAcceptsOnlyTheGivenStrings(net: Net)
	local schema = net.Schema.literal("fast", "slow")
	local cases: { Expectation } = {
		{ label = '"fast"', value = "fast", expect = "ok" },
		{ label = '"slow"', value = "slow", expect = "ok" },
		{ label = '"Fast" (case)', value = "Fast", expect = "shape" },
		{ label = '"" (empty)', value = "", expect = "shape" },
		{ label = '"fastest" (prefix)', value = "fastest", expect = "shape" },
		{ label = '"fast " (trailing space)', value = "fast ", expect = "shape" },
		{ label = "1", value = 1, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = "true", value = true, expect = "shape" },
		{ label = '{ "fast" }', value = { "fast" }, expect = "shape" },
	}
	report(
		"Schema.literal",
		runExpectations('Schema.literal("fast", "slow")', schema, cases),
		#cases
	)

	local single = runExpectations('Schema.literal("only")', net.Schema.literal("only"), {
		{ label = '"only"', value = "only", expect = "ok" },
		{ label = '"other"', value = "other", expect = "shape" },
	})
	report('Schema.literal("only")', single, 2)
end

--[[
	Exact keys, both directions, with the pipeline order inside one payload: a
	structural failure anywhere beats a domain failure anywhere. And nested,
	because a shape holds shapes.
]]
function NetContract.shapeSchemaIsExact(net: Net)
	local schema = net.Schema.shape({ a = net.Schema.integer(1, 3), b = net.Schema.boolean() })
	local cases: { Expectation } = {
		{ label = "{ a = 1, b = true }", value = { a = 1, b = true }, expect = "ok" },
		{ label = "{ a = 3, b = false }", value = { a = 3, b = false }, expect = "ok" },
		{ label = "{} (zero keys)", value = {}, expect = "shape" },
		{ label = "{ a = 1 } (missing b)", value = { a = 1 }, expect = "shape" },
		{ label = "{ b = true } (missing a)", value = { b = true }, expect = "shape" },
		{
			label = "{ a = 1, b = true, c = 1 } (extra key)",
			value = { a = 1, b = true, c = 1 },
			expect = "shape",
		},
		{
			label = "{ a = 1, b = true, [1] = 2 } (extra array key)",
			value = { a = 1, b = true, [1] = 2 },
			expect = "shape",
		},
		{
			label = "{ a = 1, b = true, admin = true }",
			value = { a = 1, b = true, admin = true },
			expect = "shape",
		},
		{
			label = '{ a = "1", b = true } (wrong type)',
			value = { a = "1", b = true },
			expect = "shape",
		},
		{
			label = "{ a = {}, b = true } (a table where a number belongs)",
			value = { a = {}, b = true },
			expect = "shape",
		},
		{ label = "nil", value = nil, expect = "shape" },
		{ label = "7", value = 7, expect = "shape" },
		{ label = '"x"', value = "x", expect = "shape" },
		{ label = "true", value = true, expect = "shape" },
		{ label = "a function", value = function() end, expect = "shape" },
		{ label = "{ a = 9, b = true } (range)", value = { a = 9, b = true }, expect = "range" },
		{ label = "{ a = 0, b = false } (range)", value = { a = 0, b = false }, expect = "range" },
		{
			label = "{ a = 2.5, b = true } (non-integer -> range)",
			value = { a = 2.5, b = true },
			expect = "range",
		},
		{
			label = '{ a = 9, b = "x" } (range in a, shape in b -> shape)',
			value = { a = 9, b = "x" },
			expect = "shape",
		},
		{
			label = "{ a = 9 } (range in a, missing b -> shape)",
			value = { a = 9 },
			expect = "shape",
		},
		{
			label = "{ a = 9, b = true, c = 1 } (range in a, extra c -> shape)",
			value = { a = 9, b = true, c = 1 },
			expect = "shape",
		},
	}
	report(
		"Schema.shape",
		runExpectations("Schema.shape({ a = integer(1, 3), b = boolean() })", schema, cases),
		#cases
	)

	local nested = net.Schema.shape({ inner = net.Schema.shape({ n = net.Schema.integer(0, 1) }) })
	local nestedCases: { Expectation } = {
		{ label = "{ inner = { n = 1 } }", value = { inner = { n = 1 } }, expect = "ok" },
		{
			label = "{ inner = { n = 2 } } (nested range)",
			value = { inner = { n = 2 } },
			expect = "range",
		},
		{
			label = '{ inner = { n = "1" } } (nested wrong type)',
			value = { inner = { n = "1" } },
			expect = "shape",
		},
		{ label = "{ inner = {} } (nested missing)", value = { inner = {} }, expect = "shape" },
		{
			label = "{ inner = { n = 1, x = 1 } } (nested extra)",
			value = { inner = { n = 1, x = 1 } },
			expect = "shape",
		},
		{
			label = "{ inner = 1 } (non-table where a shape belongs)",
			value = { inner = 1 },
			expect = "shape",
		},
		{ label = "{} (missing inner)", value = {}, expect = "shape" },
	}
	report(
		"nested Schema.shape",
		runExpectations(
			"Schema.shape({ inner = shape({ n = integer(0, 1) }) })",
			nested,
			nestedCases
		),
		#nestedCases
	)

	-- An empty shape accepts exactly the empty table.
	local empty = runExpectations("Schema.shape({})", net.Schema.shape({}), {
		{ label = "{}", value = {}, expect = "ok" },
		{ label = "{ x = 1 }", value = { x = 1 }, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
	})
	report("Schema.shape({})", empty, 3)
end

function NetContract.optionalSchemaAcceptsNilAndDefersToTheInner(net: Net)
	local schema = net.Schema.optional(net.Schema.integer(1, 3))
	local cases: { Expectation } = {
		{ label = "nil", value = nil, expect = "ok" },
		{ label = "2", value = 2, expect = "ok" },
		{ label = '"2"', value = "2", expect = "shape" },
		{ label = "9", value = 9, expect = "range" },
		{ label = "false (not nil)", value = false, expect = "shape" },
	}
	report(
		"Schema.optional",
		runExpectations("Schema.optional(integer(1, 3))", schema, cases),
		#cases
	)

	local inShape = net.Schema.shape({
		a = net.Schema.integer(1, 3),
		b = net.Schema.optional(net.Schema.integer(1, 3)),
	})
	local shapeCases: { Expectation } = {
		{ label = "{ a = 1 } (optional absent)", value = { a = 1 }, expect = "ok" },
		{ label = "{ a = 1, b = 2 } (optional present)", value = { a = 1, b = 2 }, expect = "ok" },
		{ label = '{ a = 1, b = "x" }', value = { a = 1, b = "x" }, expect = "shape" },
		{ label = "{ a = 1, b = 9 }", value = { a = 1, b = 9 }, expect = "range" },
		{
			label = "{ a = 1, c = 2 } (optional absent, extra key)",
			value = { a = 1, c = 2 },
			expect = "shape",
		},
		{ label = "{ b = 2 } (required absent)", value = { b = 2 }, expect = "shape" },
	}
	report(
		"Schema.optional in a shape",
		runExpectations("Schema.shape({ a = integer, b = optional(integer) })", inShape, shapeCases),
		#shapeCases
	)
end

-- `validate` never raises, whatever it is handed, and always answers in the
-- Contract's two-value shape.
function NetContract.validateNeverRaisesOnHostileInput(net: Net)
	local deep: any = 1
	for _ = 1, 40 do
		deep = { deep }
	end
	local hostile: { { label: string, value: any } } = {
		{ label = "a function", value = function() end },
		{ label = "a thread", value = coroutine.create(function() end) },
		{ label = "a table nested 40 deep", value = deep },
		{ label = "a table-valued key", value = { [{}] = 1 } },
		{ label = "a 100 KB string", value = string.rep("x", 100_000) },
		{ label = "negative zero", value = -0 },
		{ label = "2^63", value = 2 ^ 63 },
		{ label = "NaN", value = NAN },
		{ label = "nil", value = nil },
	}
	local schemas: { { label: string, schema: any } } = {
		{ label = "integer(1, 16)", schema = net.Schema.integer(1, 16) },
		{ label = "number(0, 1)", schema = net.Schema.number(0, 1) },
		{ label = "boolean()", schema = net.Schema.boolean() },
		{ label = 'literal("a")', schema = net.Schema.literal("a") },
		{
			label = "shape({ n = integer(1, 2) })",
			schema = net.Schema.shape({ n = net.Schema.integer(1, 2) }),
		},
		{ label = "optional(boolean())", schema = net.Schema.optional(net.Schema.boolean()) },
	}

	local violations: { string } = {}
	local total = 0
	for _, s in schemas do
		for _, h in hostile do
			total += 1
			local ok, valid, failure = pcall(s.schema.validate, h.value)
			if not ok then
				table.insert(violations, `{s.label} on {h.label} -> RAISED: {tostring(valid)}`)
			elseif typeof(valid) ~= "boolean" then
				table.insert(
					violations,
					`{s.label} on {h.label} -> first return is {Deep.show(valid)}, not a boolean`
				)
			elseif valid == false and typeof(failure) ~= "string" then
				table.insert(
					violations,
					`{s.label} on {h.label} -> rejected with no failure string: {Deep.show(failure)}`
				)
			elseif valid == false and kindOf(failure) ~= "shape" and kindOf(failure) ~= "range" then
				table.insert(violations, `{s.label} on {h.label} -> {kindOf(failure)}`)
			end
		end
	end
	check(
		#violations == 0,
		`validate raised or misreported in {#violations} case(s) of {total}:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

return NetContract
