--!strict
--[[
	CHAN-003 AC-1 through AC-5, plus the promises the story's `## Contract`
	makes about `RateLimiter.refund`, `CallControl` and the two stage-5
	details, written once as checks over a bundle -
	`{ Schema, Remotes, Wrapper, RateLimiter, RejectionReporter }` - handed in
	as a parameter rather than over `src/ReplicatedStorage/Net/*.luau` by name. The same
	arrangement as `RateContract.luau` and `RejectionContract.luau`, for the
	same reason: `tests/net/decline_test.luau` applies these to the real
	modules and `tests/net/decline_controls_test.luau` applies them to the
	deliberately wrong bundles in `DeclineStubs.luau`, so that every check here
	has been EXECUTED and observed to refuse the implementation it exists to
	catch before GREEN writes a line.

	EVERY CRITERION IS MECHANICAL and the controls are hand-written wrong
	implementations (`## Contract`, "Oracle partition"). Nothing here is
	designed: the two rate details, the `declined` rejection, the refund
	semantics and the clock-once rule are read out of the Contract's
	"Semantics pinned in PLANNED" and pinned exactly.

	THE TWO DETAILS ARE MATCHED WHOLE. AC-2's needle is "attempt" versus
	"call" inside otherwise identical sentences, and a substring search for
	either word is satisfied by the other sentence's neighbourhood. So every
	rate detail here is compared by `==` against the full string the Contract
	gives, with the remote's name and the declared interval interpolated.

	THE INTERVALS ARE FIXTURES, declared on the test remote and never read
	out of `src/ReplicatedStorage/Shared/`. SEND = 10 and ATTEMPT = 1 are the shape the design
	describes (`architecture.md` §9.5: a 10 s refundable send limit over a 1 s
	non-refundable attempt floor), chosen so that "after the attempt floor but
	well inside the send limit" is a wide window; the mechanism is
	value-agnostic and CHAN-004/005 are where the real rows reach a remote.

	NO ROBLOX, NO `Players`, NO ROUND, AND NO REAL TIME. `GuardContext` is
	`RateContract.world`'s, whose clock is a counted `Clock.manual`. AC-3
	reads the limiter's state back through the wrapper with a call at
	`t0 + interval - epsilon`, which is EARLIER than the declined call at
	`t1`; `Clock.manual.set` may move backwards by design ("for test setup
	only"), and the limiter compares numbers. That is the only instrument
	through which "the state is exactly what it was after t0" can be read
	from outside - with monotonic time a cleared key and a restored key both
	allow every later call - and the same property is pinned directly on
	`RateLimiter.refund`, where `now` is a plain parameter.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local NetContract = require("./NetContract")
local RateContract = require("./RateContract")

local DeclineContract = {}

export type Bundle = {
	Schema: any,
	Remotes: any,
	Wrapper: any,
	RateLimiter: any,
	RejectionReporter: any,
}

-- Fixture intervals; see the header.
DeclineContract.SEND_SECONDS = 10
DeclineContract.ATTEMPT_SECONDS = 1

-- A session id for the telemetry check, distinct from TEL-003's.
DeclineContract.SESSION_ID = "session-CHAN-003-a"

local SEND = DeclineContract.SEND_SECONDS
local ATTEMPT = DeclineContract.ATTEMPT_SECONDS
local SESSION_ID = DeclineContract.SESSION_ID

-- A start time that is not 0, so that `now - lastAccepted` and `now` are
-- different numbers and an implementation comparing the wrong one is visible.
local START = 100

-- Well inside a 10 s send limit and past a 1 s attempt floor.
local EPSILON = 0.1

local VALID = { token = 4, flag = true }

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

local function describeResult(result: any): string
	if typeof(result) == "table" then
		return `reason = {Deep.show(result.reason)}, detail = {Deep.show(result.detail)}`
	end
	return Deep.show(result)
end

--[[ ------------------------------------------------------------------------
     The Contract's exact strings
     ------------------------------------------------------------------------ ]]

function DeclineContract.attemptDetail(name: string, seconds: number): string
	return `"{name}" is limited to one attempt per {seconds} s per player`
end

function DeclineContract.sendDetail(name: string, seconds: number): string
	return `"{name}" is limited to one call per {seconds} s per player`
end

function DeclineContract.declinedDetail(name: string): string
	return `"{name}" declined the call`
end

--[[ ------------------------------------------------------------------------
     Fixtures
     ------------------------------------------------------------------------ ]]

--[[
	NET-001's test remote, legal in `Round`, declared under a unique name,
	with the given send limit (`rateLimit`) and attempt floor
	(`attemptLimit`), either of which may be nil.
]]
function DeclineContract.remote(
	bundle: Bundle,
	label: string,
	sendSeconds: number?,
	attemptSeconds: number?
): any
	local spec: { [string]: any } = {
		args = bundle.Schema.shape({
			token = bundle.Schema.integer(1, 16),
			flag = bundle.Schema.boolean(),
		}),
		legalPhases = { "Round" },
	}
	if sendSeconds ~= nil then
		spec.rateLimit = { minIntervalSeconds = sendSeconds }
	end
	if attemptSeconds ~= nil then
		spec.attemptLimit = { minIntervalSeconds = attemptSeconds }
	end
	return bundle.Remotes.define(NetContract.uniqueName(label), spec)
end

type HandlerCall = { playerId: any, args: any, call: any }

--[[
	A handler that records every invocation with the third argument it was
	given, and declines when `script.declineNext` is true at the moment it
	runs (then clears it, so each decline is asked for explicitly). A handler
	that is asked to decline but was handed no `CallControl` records a
	violation naming what it received instead of raising inside the wrapper:
	the Contract says the wrapper does not contain a handler error, so a
	raise here would surface as "the guarded call RAISED" and hide the cause.
]]
local function decliningHandler(
	criterion: string,
	violations: { string }
): (
	any,
	{ HandlerCall },
	{ declineNext: boolean, declineTimes: number }
)
	local calls: { HandlerCall } = {}
	local script = { declineNext = false, declineTimes = 1 }
	local handler = function(playerId: any, args: any, call: any)
		table.insert(calls, { playerId = playerId, args = args, call = call })
		if not script.declineNext then
			return
		end
		script.declineNext = false
		if typeof(call) ~= "table" or typeof(call.decline) ~= "function" then
			table.insert(
				violations,
				`{criterion}: the handler was asked to decline but received call = {Deep.show(call)} `
					.. `as its third argument; expected a CallControl with a decline function`
			)
			return
		end
		for _ = 1, script.declineTimes do
			call.decline()
		end
	end
	return handler, calls, script
end

local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

-- A violation line for a call expected to be rejected for `expected`, or nil.
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
			.. ` ({describeResult(result)})`
	end
	if detail ~= nil then
		if result.detail ~= detail then
			return `{criterion}: {label} -> detail is {Deep.show(result.detail)}; expected exactly `
				.. `{Deep.show(detail)}`
		end
	elseif typeof(result.detail) ~= "string" or result.detail == "" then
		return `{criterion}: {label} -> detail is {Deep.show(result.detail)}; must be a non-empty string`
	end
	return nil
end

-- A violation line for a call expected to be accepted, or nil.
local function expectAcceptance(criterion: string, label: string, ok: boolean, result: any): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED: {tostring(result)}`
	end
	if result ~= nil then
		return `{criterion}: {label} -> REJECTED: {describeResult(result)}`
	end
	return nil
end

local function finish(criterion: string, violations: { string }, summary: string)
	if #violations ~= 0 then
		Contract.fail(
			`{criterion}: {#violations} violation(s) {summary}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- The limiter module, or a failure naming it: `refund` is this story's
-- addition to a module that exists, so its absence is named by field.
local function newLimiter(bundle: Bundle, criterion: string, seconds: number): any
	if bundle.RateLimiter == nil then
		Contract.fail(`{criterion}: src/ReplicatedStorage/Net/RateLimiter.luau did not load`)
	end
	local limiter = bundle.RateLimiter.new(seconds)
	if typeof(limiter) ~= "table" then
		Contract.fail(`{criterion}: RateLimiter.new({seconds}) returned {Deep.show(limiter)}`)
	end
	if typeof(limiter.refund) ~= "function" then
		Contract.fail(
			`{criterion}: RateLimiter.refund is {typeof(limiter.refund)}; the Contract adds `
				.. `refund(self, playerId, key, acceptedAt) to the limiter and this check is a unit `
				.. `criterion on it`
		)
	end
	return limiter
end

local function allow(limiter: any, playerId: string, key: string, now: number): (boolean, any)
	return pcall(function()
		return limiter:allow(playerId, key, now)
	end)
end

local function refund(limiter: any, playerId: string, key: string, at: number): (boolean, any)
	return pcall(function()
		return limiter:refund(playerId, key, at)
	end)
end

local function size(limiter: any): (boolean, any)
	return pcall(function()
		return limiter:size()
	end)
end

local function expectAllow(
	criterion: string,
	violations: { string },
	limiter: any,
	label: string,
	playerId: string,
	key: string,
	now: number,
	expected: boolean
)
	local ok, allowed = allow(limiter, playerId, key, now)
	if not ok then
		table.insert(violations, `{criterion}: {label} -> allow RAISED: {tostring(allowed)}`)
	elseif allowed ~= expected then
		table.insert(
			violations,
			`{criterion}: {label} -> allow({playerId}, {key}, {now}) returned {Deep.show(allowed)}; `
				.. `expected {expected}`
		)
	end
end

local function expectRefund(
	criterion: string,
	violations: { string },
	limiter: any,
	label: string,
	playerId: string,
	key: string,
	at: number
)
	local ok, err = refund(limiter, playerId, key, at)
	if not ok then
		table.insert(
			violations,
			`{criterion}: {label} -> refund({playerId}, {key}, {at}) RAISED: {tostring(err)}; `
				.. `refund never raises`
		)
	end
end

local function expectSize(
	criterion: string,
	violations: { string },
	limiter: any,
	label: string,
	expected: number
)
	local ok, held = size(limiter)
	if not ok then
		table.insert(violations, `{criterion}: {label} -> size() RAISED: {tostring(held)}`)
	elseif held ~= expected then
		table.insert(
			violations,
			`{criterion}: {label} -> size() is {Deep.show(held)}; expected {expected}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1
     ------------------------------------------------------------------------ ]]

--[[
	AC-1. A remote with a send limit and no attempt floor. The handler
	declines the first call; the same player calls again after the attempt
	floor would have passed and well inside the send limit, and the second
	call passes the rate stage: the handler runs and nothing is rejected for
	rate. The criterion's own control runs beside it - the same sequence with
	a handler that never declines is `rate` on the second call - so a wrapper
	that refunds every call fails here too.
]]
function DeclineContract.declinedCallDoesNotCostTheSendLimit(bundle: Bundle)
	local violations: { string } = {}

	-- The criterion.
	local definition = DeclineContract.remote(bundle, "ac1", SEND, nil)
	local handler, calls, script = decliningHandler("AC-1", violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = bundle.Wrapper.guard(definition, context, handler)

	world.clock:set(START)
	script.declineNext = true
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectRejection(
		"AC-1",
		"the first call at t, which the handler declines",
		ok,
		result,
		"declined"
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	world.clock:set(START + ATTEMPT + EPSILON)
	ok, result = call(guarded, "p1", VALID)
	violation = expectAcceptance(
		"AC-1",
		`the same player at t + {ATTEMPT + EPSILON}, after the attempt floor and well inside the `
			.. `{SEND} s send limit, with the first call declined`,
		ok,
		result
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #calls ~= 2 then
		table.insert(
			violations,
			`AC-1: the handler ran {#calls} time(s) over two calls; a declined call ran it once and `
				.. `the refunded second call must reach it`
		)
	end

	-- The control: the same sequence, nothing declined, is rate on call two.
	local plain = DeclineContract.remote(bundle, "ac1control", SEND, nil)
	local plainHandler, plainCalls = NetContract.recorder()
	local plainContext, plainWorld = RateContract.world({ "p1" }, "Round", START)
	local plainGuarded = bundle.Wrapper.guard(plain, plainContext, plainHandler)
	plainWorld.clock:set(START)
	ok, result = call(plainGuarded, "p1", VALID)
	violation = expectAcceptance("AC-1 control", "the first call at t, not declined", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	plainWorld.clock:set(START + ATTEMPT + EPSILON)
	ok, result = call(plainGuarded, "p1", VALID)
	violation = expectRejection(
		"AC-1 control",
		`the same player at t + {ATTEMPT + EPSILON} with nothing declined`,
		ok,
		result,
		"rate",
		DeclineContract.sendDetail(plain.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #plainCalls ~= 1 then
		table.insert(
			violations,
			`AC-1 control: the handler ran {#plainCalls} time(s) over two calls; the send limit `
				.. `holds the second`
		)
	end

	finish("AC-1", violations, "for a declined call against the send limit")
end

--[[ ------------------------------------------------------------------------
     AC-2
     ------------------------------------------------------------------------ ]]

--[[
	AC-2. A remote declaring both limits. Two calls inside the attempt floor
	are `rate` on the second whether or not the first was declined, and the
	detail is the ATTEMPT sentence, matched whole. The second half pins the
	Contract's stage-5 order on the same remote: past the floor but inside
	the send limit the detail is the SEND sentence; the attempt acceptance
	that call made stands even though the send limiter refused it, so a call
	inside the floor after it is `rate` for the attempt again.
]]
function DeclineContract.attemptFloorIsNeverRefunded(bundle: Bundle)
	local violations: { string } = {}
	local attemptDetail = DeclineContract.attemptDetail
	local sendDetail = DeclineContract.sendDetail

	-- Declined first call.
	local declinedRemote = DeclineContract.remote(bundle, "ac2declined", SEND, ATTEMPT)
	local handler, _, script = decliningHandler("AC-2", violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = bundle.Wrapper.guard(declinedRemote, context, handler)

	world.clock:set(START)
	script.declineNext = true
	local ok, result = call(guarded, "p1", VALID)
	local violation =
		expectRejection("AC-2", "the first call at t, declined", ok, result, "declined")
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(START + ATTEMPT - EPSILON)
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		"AC-2",
		`the same player at t + {ATTEMPT - EPSILON}, inside the attempt floor, after a DECLINED call`,
		ok,
		result,
		"rate",
		attemptDetail(declinedRemote.name, ATTEMPT)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	-- Accepted first call: the same verdict and the same detail.
	local keptRemote = DeclineContract.remote(bundle, "ac2kept", SEND, ATTEMPT)
	local keptHandler = NetContract.recorder()
	local keptContext, keptWorld = RateContract.world({ "p1" }, "Round", START)
	local keptGuarded = bundle.Wrapper.guard(keptRemote, keptContext, keptHandler)

	keptWorld.clock:set(START)
	ok, result = call(keptGuarded, "p1", VALID)
	violation = expectAcceptance("AC-2", "the first call at t, not declined", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	keptWorld.clock:set(START + ATTEMPT - EPSILON)
	ok, result = call(keptGuarded, "p1", VALID)
	violation = expectRejection(
		"AC-2",
		`the same player at t + {ATTEMPT - EPSILON}, inside the attempt floor, after an ACCEPTED call`,
		ok,
		result,
		"rate",
		attemptDetail(keptRemote.name, ATTEMPT)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	-- Stage-5 order, on the kept remote: past the floor, inside the send
	-- limit, the send sentence; the attempt acceptance that call made stands.
	keptWorld.clock:set(START + ATTEMPT)
	ok, result = call(keptGuarded, "p1", VALID)
	violation = expectRejection(
		"AC-2 (order)",
		`the same player at t + {ATTEMPT}, exactly the attempt floor and inside the send limit`,
		ok,
		result,
		"rate",
		sendDetail(keptRemote.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	keptWorld.clock:set(START + ATTEMPT + EPSILON)
	ok, result = call(keptGuarded, "p1", VALID)
	violation = expectRejection(
		"AC-2 (order)",
		`the same player at t + {ATTEMPT + EPSILON}, inside the floor of the call the SEND limiter `
			.. `refused - that attempt acceptance stands`,
		ok,
		result,
		"rate",
		attemptDetail(keptRemote.name, ATTEMPT)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	keptWorld.clock:set(START + 2 * ATTEMPT)
	ok, result = call(keptGuarded, "p1", VALID)
	violation = expectRejection(
		"AC-2 (order)",
		`the same player at t + {2 * ATTEMPT}, past that floor and still inside the send limit`,
		ok,
		result,
		"rate",
		sendDetail(keptRemote.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	finish("AC-2", violations, "for the attempt floor")
end

--[[
	The Contract's stage-5 step 1: when the attempt floor refuses, the send
	limiter is not consulted and records nothing. Observable through a
	declined call: at `t` the call is declined (the send limiter holds
	nothing), at `t + 0.5` the floor refuses - a wrapper that consulted the
	send limiter anyway would record 0.5 there - and at `t + 1.5` the call is
	accepted, which the recorded 0.5 would have refused.
]]
function DeclineContract.sendLimiterIsNotConsultedWhenTheAttemptFloorRefuses(bundle: Bundle)
	local violations: { string } = {}
	local definition = DeclineContract.remote(bundle, "step1", SEND, ATTEMPT)
	local handler, calls, script = decliningHandler("Contract (step 1)", violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = bundle.Wrapper.guard(definition, context, handler)

	world.clock:set(START)
	script.declineNext = true
	local ok, result = call(guarded, "p1", VALID)
	local violation =
		expectRejection("Contract (step 1)", "the call at t, declined", ok, result, "declined")
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(START + ATTEMPT / 2)
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		"Contract (step 1)",
		`the call at t + {ATTEMPT / 2}, inside the attempt floor`,
		ok,
		result,
		"rate",
		DeclineContract.attemptDetail(definition.name, ATTEMPT)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(START + ATTEMPT + ATTEMPT / 2)
	ok, result = call(guarded, "p1", VALID)
	violation = expectAcceptance(
		"Contract (step 1)",
		`the call at t + {ATTEMPT + ATTEMPT / 2}: the floor has passed and the send limiter holds `
			.. `nothing - it was refunded at t and must not have recorded the refused attempt at `
			.. `t + {ATTEMPT / 2}`,
		ok,
		result
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #calls ~= 2 then
		table.insert(
			violations,
			`Contract (step 1): the handler ran {#calls} time(s) over three calls; expected 2`
		)
	end
	finish("Contract (step 1)", violations, "when the attempt floor refuses")
end

--[[ ------------------------------------------------------------------------
     AC-3
     ------------------------------------------------------------------------ ]]

--[[
	AC-3, through the wrapper. A send-limited remote, no attempt floor. p1 is
	accepted at t0, accepted at t1 = t0 + SEND and declines. The send
	limiter's state for p1 is then exactly what it was after t0: a call at
	t0 + SEND - epsilon is refused and one at t0 + SEND is allowed. The clock
	is SET to those instants (see the header): a refund that cleared the key
	would accept the first of them.
]]
function DeclineContract.refundRestoresThePreviousAcceptance(bundle: Bundle)
	local violations: { string } = {}
	local definition = DeclineContract.remote(bundle, "ac3", SEND, nil)
	local handler, calls, script = decliningHandler("AC-3", violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = bundle.Wrapper.guard(definition, context, handler)

	local t0 = START
	local t1 = START + SEND

	world.clock:set(t0)
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectAcceptance("AC-3", "the call at t0, kept", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	world.clock:set(t1)
	script.declineNext = true
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		"AC-3",
		`the call at t1 = t0 + {SEND}, accepted by the limiter and then declined`,
		ok,
		result,
		"declined"
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	world.clock:set(t0 + SEND - EPSILON)
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		"AC-3",
		`the call at t0 + {SEND} - {EPSILON}: still refused, because the key holds t0 again - a `
			.. `refund that CLEARED the key would accept this`,
		ok,
		result,
		"rate",
		DeclineContract.sendDetail(definition.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	world.clock:set(t0 + SEND)
	ok, result = call(guarded, "p1", VALID)
	violation = expectAcceptance(
		"AC-3",
		`the call at t0 + {SEND}: allowed, exactly as it was after t0 - a wrapper that did not `
			.. `refund holds t1 and refuses this`,
		ok,
		result
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #calls ~= 3 then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) over four calls; expected 3 (t0, t1, t0 + {SEND})`
		)
	end
	finish("AC-3", violations, "for the send limiter's state after a decline")
end

--[[
	AC-3 on `RateLimiter.refund` directly, where `now` is a parameter and
	nothing pretends to be a clock. Restores ONE acceptance: after accepting
	at t0 and t1 and refunding t1 the key holds t0; a second refund of t1 is
	a no-op (the key's last acceptance is t0, not t1), and so is a refund
	naming a time that was never an acceptance.
]]
function DeclineContract.refundRestoresTheAcceptanceBeforeItOnTheLimiter(bundle: Bundle)
	local criterion = "AC-3 (limiter)"
	local limiter = newLimiter(bundle, criterion, SEND)
	local violations: { string } = {}
	local t0 = START
	local t1 = START + SEND
	local key = "k"

	expectAllow(criterion, violations, limiter, "accept p1 at t0", "p1", key, t0, true)
	expectAllow(criterion, violations, limiter, "accept p1 at t1 = t0 + SEND", "p1", key, t1, true)
	expectRefund(criterion, violations, limiter, "refund the acceptance at t1", "p1", key, t1)
	expectAllow(
		criterion,
		violations,
		limiter,
		"after the refund, t0 + SEND - epsilon is refused (the key holds t0, not nothing)",
		"p1",
		key,
		t0 + SEND - EPSILON,
		false
	)
	expectAllow(
		criterion,
		violations,
		limiter,
		"after the refund, t0 + SEND is allowed (the key holds t0, not t1)",
		"p1",
		key,
		t0 + SEND,
		true
	)

	-- Restores exactly one acceptance: a second refund of the same instant
	-- is a no-op, and so is one naming an instant that never was accepted.
	local second = newLimiter(bundle, criterion, SEND)
	expectAllow(
		criterion,
		violations,
		second,
		"accept p1 at t0 (second limiter)",
		"p1",
		key,
		t0,
		true
	)
	expectAllow(
		criterion,
		violations,
		second,
		"accept p1 at t1 (second limiter)",
		"p1",
		key,
		t1,
		true
	)
	expectRefund(criterion, violations, second, "refund t1 once", "p1", key, t1)
	expectRefund(criterion, violations, second, "refund t1 a second time", "p1", key, t1)
	expectRefund(
		criterion,
		violations,
		second,
		"refund an instant never accepted",
		"p1",
		key,
		t1 + 1
	)
	expectAllow(
		criterion,
		violations,
		second,
		"after refunding t1 twice, t0 + SEND - epsilon is still refused - the second refund did not "
			.. "unwind t0 as well",
		"p1",
		key,
		t0 + SEND - EPSILON,
		false
	)
	expectSize(criterion, violations, second, "after refunding t1 twice, p1 is still held", 1)

	finish(criterion, violations, "on RateLimiter.refund")
end

--[[
	The Contract's guard: a refund naming an acceptance that is no longer the
	last one is a no-op. Accept t0, t1, t2; refund t1; the key still holds
	t2. D-3's mutation - a refund that unwinds whatever the last acceptance
	was - must fail here.
]]
function DeclineContract.refundOfAStaleAcceptanceIsANoOp(bundle: Bundle)
	local criterion = "Contract (stale refund)"
	local limiter = newLimiter(bundle, criterion, SEND)
	local violations: { string } = {}
	local key = "k"
	local t0, t1, t2 = START, START + SEND, START + 2 * SEND

	expectAllow(criterion, violations, limiter, "accept p1 at t0", "p1", key, t0, true)
	expectAllow(criterion, violations, limiter, "accept p1 at t1", "p1", key, t1, true)
	expectAllow(criterion, violations, limiter, "accept p1 at t2", "p1", key, t2, true)
	expectRefund(
		criterion,
		violations,
		limiter,
		"refund t1, which is no longer the last",
		"p1",
		key,
		t1
	)
	expectAllow(
		criterion,
		violations,
		limiter,
		"t2 + SEND - epsilon is still refused: the key holds t2, and a refund of t1 is a no-op",
		"p1",
		key,
		t2 + SEND - EPSILON,
		false
	)
	expectAllow(criterion, violations, limiter, "t2 + SEND is allowed", "p1", key, t2 + SEND, true)
	finish(criterion, violations, "for a refund naming a stale acceptance")
end

--[[
	The Contract's bookkeeping: refunding a player's ONLY acceptance removes
	the key, and with no key left removes the player, so `size()` drops - a
	player whose only acceptance was refunded holds nothing (NET-003 AC-6).
	A player holding another key is still held.
]]
function DeclineContract.refundOfAPlayersOnlyAcceptanceRemovesThePlayer(bundle: Bundle)
	local criterion = "Contract (empty entry)"
	local limiter = newLimiter(bundle, criterion, SEND)
	local violations: { string } = {}
	local t0 = START

	expectSize(criterion, violations, limiter, "fresh", 0)
	expectAllow(criterion, violations, limiter, "accept p1 on k1 at t0", "p1", "k1", t0, true)
	expectSize(criterion, violations, limiter, "after one acceptance", 1)
	expectRefund(criterion, violations, limiter, "refund p1's only acceptance", "p1", "k1", t0)
	expectSize(criterion, violations, limiter, "after refunding p1's only acceptance", 0)
	expectAllow(
		criterion,
		violations,
		limiter,
		"p1 on k1 at t0 again: the key was removed, so the same instant is allowed",
		"p1",
		"k1",
		t0,
		true
	)

	-- Two keys: refunding one leaves the player held by the other.
	expectAllow(criterion, violations, limiter, "accept p1 on k2 at t0", "p1", "k2", t0, true)
	expectRefund(criterion, violations, limiter, "refund p1 on k1 at t0", "p1", "k1", t0)
	expectSize(criterion, violations, limiter, "after refunding k1 with k2 still held", 1)
	expectAllow(
		criterion,
		violations,
		limiter,
		"p1 on k1 at t0 is allowed again",
		"p1",
		"k1",
		t0,
		true
	)
	expectAllow(
		criterion,
		violations,
		limiter,
		"p1 on k2 at t0 + SEND - epsilon is still refused: k2 was not touched",
		"p1",
		"k2",
		t0 + SEND - EPSILON,
		false
	)

	-- Two players: refunding one player's only acceptance leaves the other.
	expectAllow(criterion, violations, limiter, "accept p2 on k1 at t0", "p2", "k1", t0, true)
	expectSize(criterion, violations, limiter, "with p1 and p2 held", 2)
	expectRefund(criterion, violations, limiter, "refund p2's only acceptance", "p2", "k1", t0)
	expectSize(criterion, violations, limiter, "after refunding p2's only acceptance", 1)
	finish(criterion, violations, "for the entry a refund empties")
end

--[[
	The Contract: a refund for an unknown player, an unknown key, or an
	instant that is not the key's last acceptance is a no-op and never
	raises, and the state it did not touch is unchanged.
]]
function DeclineContract.refundOfAnUnknownPlayerOrKeyNeverRaises(bundle: Bundle)
	local criterion = "Contract (unknown refund)"
	local limiter = newLimiter(bundle, criterion, SEND)
	local violations: { string } = {}
	local t0 = START

	expectRefund(criterion, violations, limiter, "a stranger on a fresh limiter", "nobody", "k", t0)
	expectSize(criterion, violations, limiter, "after refunding a stranger", 0)
	expectAllow(criterion, violations, limiter, "accept p1 on k at t0", "p1", "k", t0, true)
	expectRefund(criterion, violations, limiter, "a stranger with p1 held", "nobody", "k", t0)
	expectRefund(criterion, violations, limiter, "p1 on a key never used", "p1", "other", t0)
	expectRefund(
		criterion,
		violations,
		limiter,
		"p1 on k at an instant that was never accepted",
		"p1",
		"k",
		t0 + 1
	)
	expectSize(criterion, violations, limiter, "after three no-op refunds", 1)
	expectAllow(
		criterion,
		violations,
		limiter,
		"p1 on k at t0 + SEND - epsilon is still refused: nothing was refunded",
		"p1",
		"k",
		t0 + SEND - EPSILON,
		false
	)
	finish(criterion, violations, "for refunds that name nothing")
end

--[[ ------------------------------------------------------------------------
     AC-4
     ------------------------------------------------------------------------ ]]

--[[
	AC-4. A declining handler makes the wrapper return exactly
	`{ reason = "declined", detail = '"<name>" declined the call' }`, with
	a send limit, with both limits, and with neither (nothing to refund, the
	result is still `declined`). The handler receives a fresh `CallControl`
	on every call - `{ decline = function }` - and a call that is never
	declined returns nil.
]]
function DeclineContract.declinedCallReturnsADeclinedRejection(bundle: Bundle)
	local violations: { string } = {}
	local shapes: { { label: string, send: number?, attempt: number? } } = {
		{ label = "a remote with a send limit only", send = SEND, attempt = nil },
		{ label = "a remote with both limits", send = SEND, attempt = ATTEMPT },
		{ label = "a remote with an attempt floor only", send = nil, attempt = ATTEMPT },
		{ label = "a remote with neither limit", send = nil, attempt = nil },
	}
	for _, shape in shapes do
		local definition = DeclineContract.remote(bundle, "ac4", shape.send, shape.attempt)
		local handler, calls, script = decliningHandler("AC-4", violations)
		local context, world = RateContract.world({ "p1" }, "Round", START)
		local guarded = bundle.Wrapper.guard(definition, context, handler)
		world.clock:set(START)
		script.declineNext = true
		local ok, result = call(guarded, "p1", VALID)
		if not ok then
			table.insert(
				violations,
				`AC-4: {shape.label}, declined -> the guarded call RAISED: {tostring(result)}`
			)
			continue
		end
		local expected = {
			reason = "declined",
			detail = DeclineContract.declinedDetail(definition.name),
		}
		local diff = Deep.diff(expected, result)
		if diff ~= "" then
			table.insert(
				violations,
				`AC-4: {shape.label}, declined -> the result is not the Contract's Rejection:\n{indent(
					diff
				)}`
			)
		end
		if #calls ~= 1 then
			table.insert(
				violations,
				`AC-4: {shape.label} -> the handler ran {#calls} time(s) for one declined call`
			)
		elseif
			typeof(calls[1].call) ~= "table"
			or typeof((calls[1].call :: any).decline) ~= "function"
		then
			table.insert(
				violations,
				`AC-4: {shape.label} -> the handler's third argument is {Deep.show(calls[1].call)}; `
					.. `expected a CallControl with a decline function`
			)
		end
	end
	finish("AC-4", violations, "for the declined Rejection")
end

--[[
	The Contract: `call` is fresh per call, and a call that is never declined
	keeps its acceptance - the result is nil and the next call inside the
	send limit is `rate`. The two CallControls of two calls are different
	tables; a wrapper handing out one shared control refunds the wrong call
	when a handler keeps it.
]]
function DeclineContract.callControlIsFreshPerCallAndAnUndeclinedCallKeepsItsAcceptance(
	bundle: Bundle
)
	local criterion = "Contract (fresh call)"
	local violations: { string } = {}
	local definition = DeclineContract.remote(bundle, "fresh", SEND, nil)
	local handler, calls = decliningHandler(criterion, violations)
	local context, world = RateContract.world({ "p1", "p2" }, "Round", START)
	local guarded = bundle.Wrapper.guard(definition, context, handler)

	world.clock:set(START)
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectAcceptance(criterion, "p1 at t, never declined", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	ok, result = call(guarded, "p2", VALID)
	violation = expectAcceptance(criterion, "p2 at t, never declined", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(START + SEND - EPSILON)
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		criterion,
		`p1 at t + {SEND - EPSILON}: the undeclined acceptance stands`,
		ok,
		result,
		"rate",
		DeclineContract.sendDetail(definition.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end

	if #calls ~= 2 then
		table.insert(violations, `{criterion}: the handler ran {#calls} time(s); expected 2`)
	else
		local first, second = calls[1].call, calls[2].call
		-- Indexed over `calls`, not over `{ first, second }`: a list literal of
		-- two nils is EMPTY, and the loop over it ran zero times against the
		-- real wrapper on arrival (which passes no third argument), so this
		-- check was green for the wrong reason. Observed in RED and fixed
		-- before the phase ended; see `## Handoff`.
		for i = 1, 2 do
			local control = calls[i].call
			if typeof(control) ~= "table" or typeof(control.decline) ~= "function" then
				table.insert(
					violations,
					`{criterion}: call {i}'s CallControl is {Deep.show(control)}; expected `
						.. `\{ decline = function \}`
				)
			end
		end
		if first ~= nil and first == second then
			table.insert(
				violations,
				`{criterion}: both calls received the SAME CallControl table; the wrapper hands the `
					.. `handler a fresh one on every call`
			)
		end
	end
	finish(criterion, violations, "for the CallControl and an undeclined call")
end

--[[
	The Contract: declining twice is a no-op the second time. After an
	acceptance at t0 and a call at t1 declined twice, the key holds t0 - not
	nothing, which is what unwinding twice would leave.
]]
function DeclineContract.decliningTwiceIsANoOpTheSecondTime(bundle: Bundle)
	local criterion = "Contract (decline twice)"
	local violations: { string } = {}
	local definition = DeclineContract.remote(bundle, "twice", SEND, nil)
	local handler, calls, script = decliningHandler(criterion, violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local t0, t1 = START, START + SEND

	world.clock:set(t0)
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectAcceptance(criterion, "the call at t0, kept", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(t1)
	script.declineNext = true
	script.declineTimes = 2
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(criterion, "the call at t1, declined TWICE", ok, result, "declined")
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(t0 + SEND - EPSILON)
	ok, result = call(guarded, "p1", VALID)
	violation = expectRejection(
		criterion,
		`the call at t0 + {SEND} - {EPSILON}: the key holds t0; a second decline that unwound t0 `
			.. `as well would accept this`,
		ok,
		result,
		"rate",
		DeclineContract.sendDetail(definition.name, SEND)
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #calls ~= 2 then
		table.insert(violations, `{criterion}: the handler ran {#calls} time(s); expected 2`)
	end
	finish(criterion, violations, "for a call declined twice")
end

--[[
	A reporter-and-emitter context: `RateContract.world`'s plus
	`telemetry = { reporter, emit }`, with every batch `emit` is handed kept.
]]
local function telemetryWorld(seated: { string }, reporter: any): (any, RateContract.World, { any })
	local context, world = RateContract.world(seated, "Round", START)
	local batches: { any } = {}
	context.telemetry = {
		reporter = reporter,
		emit = function(batch: any)
			table.insert(batches, batch)
		end,
	}
	return context, world, batches
end

-- A spy reporter recording every `record` call and answering a hand-built
-- event, so what the wrapper does with the answer is observable.
local function spyReporter(): (any, { any })
	local calls: { any } = {}
	local spy = {}
	function spy.record(_self: any, playerId: any, remoteName: any, reason: any, now: any): any
		local entry = { playerId = playerId, remoteName = remoteName, reason = reason, now = now }
		table.insert(calls, entry)
		return { spy = true, reason = reason }
	end
	function spy.flush(_self: any, _now: any): { any }
		return {}
	end
	return spy, calls
end

--[[
	The Contract: `decline()` after the wrapper has returned - a handler that
	kept `call` - still refunds, and nothing is returned or emitted. p1 is
	accepted at t0 and at t1 = t0 + SEND, where the handler keeps the
	control; the late decline at t1 + 1 records and emits nothing, and a call
	at t1 + SEND / 2 is accepted - it is SEND / 2 after t1, which an
	unrefunded key would refuse, and 1.5 x SEND after t0.
]]
function DeclineContract.declineAfterTheWrapperReturnedStillRefundsAndEmitsNothing(bundle: Bundle)
	local criterion = "Contract (late decline)"
	local violations: { string } = {}
	local definition = DeclineContract.remote(bundle, "late", SEND, nil)
	local kept: { any } = {}
	local handler = function(_playerId: any, _args: any, control: any)
		table.insert(kept, control)
	end
	local spy, records = spyReporter()
	local context, world, batches = telemetryWorld({ "p1" }, spy)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local t0, t1 = START, START + SEND

	world.clock:set(t0)
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectAcceptance(criterion, "the call at t0", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	world.clock:set(t1)
	ok, result = call(guarded, "p1", VALID)
	violation = expectAcceptance(criterion, "the call at t1 = t0 + SEND", ok, result)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #kept ~= 2 or typeof(kept[2]) ~= "table" or typeof(kept[2].decline) ~= "function" then
		table.insert(
			violations,
			`{criterion}: the handler kept {Deep.show(kept)}; expected two CallControls with a `
				.. `decline function`
		)
		finish(criterion, violations, "for a decline after the wrapper returned")
		return
	end

	local recordsBefore, batchesBefore = #records, #batches
	world.clock:set(t1 + 1)
	local declineOk, declineErr = pcall(kept[2].decline)
	if not declineOk then
		table.insert(
			violations,
			`{criterion}: decline() after the wrapper returned RAISED: {tostring(declineErr)}`
		)
	end
	if #records ~= recordsBefore or #batches ~= batchesBefore then
		table.insert(
			violations,
			`{criterion}: the late decline called reporter:record {#records - recordsBefore} time(s) `
				.. `and emit {#batches - batchesBefore} time(s); the result has already gone, so `
				.. `nothing is recorded or emitted`
		)
	end

	world.clock:set(t1 + SEND / 2)
	ok, result = call(guarded, "p1", VALID)
	violation = expectAcceptance(
		criterion,
		`the call at t1 + {SEND / 2}: the late decline refunded t1, so the key holds t0 and this `
			.. `is {SEND + SEND / 2} after it`,
		ok,
		result
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #records ~= recordsBefore or #batches ~= batchesBefore then
		table.insert(
			violations,
			`{criterion}: across the late decline and an accepted call, record was called `
				.. `{#records - recordsBefore} time(s) and emit {#batches - batchesBefore} time(s); `
				.. `expected 0 and 0`
		)
	end
	finish(criterion, violations, "for a decline after the wrapper returned")
end

--[[
	AC-4's telemetry half, end to end with the bundle's real reporter: a
	declined call is recorded like any non-rate reason - one batch of one
	`remote_rejected` event carrying `reason = "declined"` and `count = 1`,
	stamped with the clock - and five declines at one instant are five
	events of count 1, uncoalesced. The wiring is also pinned with a spy:
	`record(playerId, remoteName, "declined", now)` exactly once per declined
	call, then `emit({ event })` exactly once.
]]
function DeclineContract.declinedIsRecordedLikeAnyOtherReason(bundle: Bundle)
	local criterion = "AC-4 (telemetry)"
	local violations: { string } = {}

	-- Wiring, with the spy.
	local definition = DeclineContract.remote(bundle, "ac4spy", SEND, ATTEMPT)
	local handler, _, script = decliningHandler(criterion, violations)
	local spy, records = spyReporter()
	local context, world, batches = telemetryWorld({ "p1" }, spy)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	world.clock:set(START)
	script.declineNext = true
	local ok, result = call(guarded, "p1", VALID)
	local violation = expectRejection(criterion, "the declined call", ok, result, "declined")
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #records ~= 1 then
		table.insert(
			violations,
			`{criterion}: reporter:record was called {#records} time(s) for one declined call; `
				.. `exactly once`
		)
	else
		local diff = Deep.diff(
			{ playerId = "p1", remoteName = definition.name, reason = "declined", now = START },
			records[1]
		)
		if diff ~= "" then
			table.insert(
				violations,
				`{criterion}: record(playerId, remoteName, reason, now) was called with the wrong `
					.. `arguments:\n{indent(diff)}`
			)
		end
	end
	if #batches ~= 1 then
		table.insert(
			violations,
			`{criterion}: emit was called {#batches} time(s) for one declined call; exactly once`
		)
	elseif typeof(batches[1]) ~= "table" or #batches[1] ~= 1 then
		table.insert(
			violations,
			`{criterion}: emit was handed {Deep.show(batches[1])}; a batch of exactly one event`
		)
	else
		local diff = Deep.diff({ spy = true, reason = "declined" }, batches[1][1])
		if diff ~= "" then
			table.insert(
				violations,
				`{criterion}: the emitted event is not the one record returned:\n{indent(diff)}`
			)
		end
	end

	-- End to end, with the real reporter.
	if bundle.RejectionReporter == nil then
		table.insert(
			violations,
			`{criterion}: src/ReplicatedStorage/Net/RejectionReporter.luau did not load`
		)
		finish(criterion, violations, "for a declined call's telemetry")
		return
	end
	local reporter =
		bundle.RejectionReporter.new(bundle.RejectionReporter.INTERVAL_SECONDS, SESSION_ID)
	local realRemote = DeclineContract.remote(bundle, "ac4real", SEND, ATTEMPT)
	local realHandler, _, realScript = decliningHandler(criterion, violations)
	local realContext, realWorld, realBatches = telemetryWorld({ "p1" }, reporter)
	local realGuarded = bundle.Wrapper.guard(realRemote, realContext, realHandler)

	-- Five declines at one instant: a fresh guard each so the limiters do
	-- not refuse them first, and the SAME reporter so coalescing would show.
	local total = 5
	for i = 1, total do
		local each = bundle.Wrapper.guard(realRemote, realContext, realHandler)
		realWorld.clock:set(START + 1)
		realScript.declineNext = true
		ok, result = call(each, "p1", VALID)
		violation =
			expectRejection(criterion, `decline {i} of {total} at t + 1`, ok, result, "declined")
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #realBatches ~= total then
		table.insert(
			violations,
			`{criterion}: {total} declines at one instant emitted {#realBatches} batch(es); declined `
				.. `is never coalesced, so exactly {total}`
		)
	end
	for i, batch in realBatches do
		if typeof(batch) ~= "table" or #batch ~= 1 then
			table.insert(
				violations,
				`{criterion}: batch {i} is {Deep.show(batch)}; a batch of exactly one event`
			)
			continue
		end
		local expected = {
			name = "remote_rejected",
			at = START + 1,
			bucket = "D1",
			sessionId = SESSION_ID,
			playerId = "p1",
			fields = { remote = realRemote.name, reason = "declined", count = 1 },
		}
		local diff = Deep.diff(expected, batch[1])
		if diff ~= "" then
			table.insert(
				violations,
				`{criterion}: event {i} of {total} is not the Contract's:\n{indent(diff)}`
			)
		end
	end
	-- `realGuarded` is a sixth guard over the same remote; one more decline
	-- through it is one more event, and a flush afterwards has nothing.
	realWorld.clock:set(START + 2)
	realScript.declineNext = true
	call(realGuarded, "p1", VALID)
	local flushed = reporter:flush(START + 3)
	if #flushed ~= 0 then
		table.insert(
			violations,
			`{criterion}: flush after {total + 1} declines returned {#flushed} event(s); declined is `
				.. `not coalesced, so nothing is pending`
		)
	end
	finish(criterion, violations, "for a declined call's telemetry")
end

--[[ ------------------------------------------------------------------------
     AC-5 and the Contract's registry promise
     ------------------------------------------------------------------------ ]]

--[[
	AC-5. A call that reaches stage 5 reads `context.clock.now()` exactly
	once, whether the remote declares both limits, the send limit alone or
	the attempt floor alone, and whatever stage 5 then does with the value -
	accept, refuse for the attempt floor, refuse for the send limit, or run
	a handler that declines. A remote declaring neither reads it zero times
	across `guard()` and every call. No telemetry in the context, so the
	stamp read TEL-003 makes on a rejection is not in the count.
]]
function DeclineContract.stageFiveReadsTheClockExactlyOnce(bundle: Bundle)
	local violations: { string } = {}
	type Step = { label: string, at: number, decline: boolean, expected: string? }
	type Shape = { label: string, send: number?, attempt: number?, steps: { Step } }
	local shapes: { Shape } = {
		{
			label = "both limits",
			send = SEND,
			attempt = ATTEMPT,
			steps = {
				{ label = "accepted at t", at = 0, decline = false },
				{
					label = "attempt-refused at t + 0.5",
					at = 0.5,
					decline = false,
					expected = "rate",
				},
				{ label = "send-refused at t + 1", at = 1, decline = false, expected = "rate" },
				{
					label = "declined at t + SEND",
					at = SEND,
					decline = true,
					expected = "declined",
				},
				{ label = "accepted at t + SEND + 1", at = SEND + 1, decline = false },
			},
		},
		{
			label = "send limit only",
			send = SEND,
			attempt = nil,
			steps = {
				{ label = "accepted at t", at = 0, decline = false },
				{ label = "send-refused at t + 1", at = 1, decline = false, expected = "rate" },
				{
					label = "declined at t + SEND",
					at = SEND,
					decline = true,
					expected = "declined",
				},
			},
		},
		{
			label = "attempt floor only",
			send = nil,
			attempt = ATTEMPT,
			steps = {
				{ label = "accepted at t", at = 0, decline = false },
				{
					label = "attempt-refused at t + 0.5",
					at = 0.5,
					decline = false,
					expected = "rate",
				},
				{ label = "declined at t + 1", at = 1, decline = true, expected = "declined" },
			},
		},
	}
	for _, shape in shapes do
		local definition = DeclineContract.remote(bundle, "clock", shape.send, shape.attempt)
		local handler, _, script = decliningHandler("AC-5", violations)
		local context, world = RateContract.world({ "p1" }, "Round", START)
		local readsBeforeGuard = world.clockReads
		local guarded = bundle.Wrapper.guard(definition, context, handler)
		if world.clockReads ~= readsBeforeGuard then
			table.insert(
				violations,
				`AC-5: {shape.label} -> guard() read the clock {world.clockReads - readsBeforeGuard} `
					.. `time(s); the clock is read by calls, never at construction`
			)
		end
		for _, step in shape.steps do
			world.clock:set(START + step.at)
			script.declineNext = step.decline
			local before = world.clockReads
			local ok, result = call(guarded, "p1", VALID)
			local violation: string?
			if step.expected == nil then
				violation = expectAcceptance("AC-5", `{shape.label}, {step.label}`, ok, result)
			else
				violation = expectRejection(
					"AC-5",
					`{shape.label}, {step.label}`,
					ok,
					result,
					step.expected :: string
				)
			end
			if violation ~= nil then
				table.insert(violations, violation :: string)
			end
			local reads = world.clockReads - before
			if reads ~= 1 then
				table.insert(
					violations,
					`AC-5: {shape.label}, {step.label} -> context.clock.now() was read {reads} time(s) `
						.. `during the call; a call reaching stage 5 reads it exactly once`
				)
			end
		end
	end

	-- Neither limit: zero reads, through guard() and fifty calls, declined
	-- or not.
	local bare = DeclineContract.remote(bundle, "clockless", nil, nil)
	local handler, calls, script = decliningHandler("AC-5", violations)
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local readsBeforeGuard = world.clockReads
	local guarded = bundle.Wrapper.guard(bare, context, handler)
	local total = 50
	for i = 1, total do
		script.declineNext = i % 2 == 0
		local ok, result = call(guarded, "p1", VALID)
		local violation: string?
		if i % 2 == 0 then
			violation = expectRejection(
				"AC-5",
				`neither limit, call {i} (declined)`,
				ok,
				result,
				"declined"
			)
		else
			violation = expectAcceptance("AC-5", `neither limit, call {i}`, ok, result)
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls ~= total then
		table.insert(
			violations,
			`AC-5: neither limit -> the handler ran {#calls} time(s) over {total} calls`
		)
	end
	local reads = world.clockReads - readsBeforeGuard
	if reads ~= 0 then
		table.insert(
			violations,
			`AC-5: neither limit -> context.clock.now() was read {reads} time(s) across guard() and `
				.. `{total} calls; a remote with no limiter never reads the clock`
		)
	end
	finish("AC-5", violations, "for the clock reads of stage 5")
end

--[[
	The Contract: `Remotes.define` copies `attemptLimit` field by field, as it
	copies `rateLimit`; a declaration without one has `attemptLimit = nil`.
]]
function DeclineContract.defineCopiesTheAttemptLimit(bundle: Bundle)
	local criterion = "Contract (define)"
	local violations: { string } = {}
	local both = DeclineContract.remote(bundle, "defineboth", SEND, ATTEMPT)
	local diff = Deep.diff({ minIntervalSeconds = ATTEMPT }, both.attemptLimit)
	if diff ~= "" then
		table.insert(
			violations,
			`{criterion}: definition.attemptLimit differs from what was declared:\n{indent(diff)}`
		)
	end
	diff = Deep.diff({ minIntervalSeconds = SEND }, both.rateLimit)
	if diff ~= "" then
		table.insert(
			violations,
			`{criterion}: definition.rateLimit differs from what was declared:\n{indent(diff)}`
		)
	end
	local attemptOnly = DeclineContract.remote(bundle, "defineattempt", nil, ATTEMPT)
	diff = Deep.diff({ minIntervalSeconds = ATTEMPT }, attemptOnly.attemptLimit)
	if diff ~= "" then
		table.insert(
			violations,
			`{criterion}: an attempt-only declaration's attemptLimit differs:\n{indent(diff)}`
		)
	end
	if attemptOnly.rateLimit ~= nil then
		table.insert(
			violations,
			`{criterion}: an attempt-only declaration has rateLimit = {Deep.show(
				attemptOnly.rateLimit
			)}`
		)
	end
	local bare = DeclineContract.remote(bundle, "definebare", nil, nil)
	if bare.attemptLimit ~= nil then
		table.insert(
			violations,
			`{criterion}: a declaration with no attemptLimit has attemptLimit = {Deep.show(
				bare.attemptLimit
			)}`
		)
	end
	finish(criterion, violations, "for Remotes.define and attemptLimit")
end

return DeclineContract
