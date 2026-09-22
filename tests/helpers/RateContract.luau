--!strict
--[[
	NET-003 AC-1 through AC-6, plus the two promises the story's `## Contract`
	makes about a rate rejection, written once as checks over a `Net` bundle -
	`{ Schema, Remotes, Wrapper, RateLimiter }` - handed in as a parameter
	rather than over `src/net/*.luau` by name. The same arrangement as
	`NetContract.luau` and `PhaseContract.luau`, for the same reason:
	`tests/net/rate_test.luau` applies these to the real modules and
	`tests/net/rate_controls_test.luau` applies them to the deliberately wrong
	bundles in `RateStubs.luau`, so that every check here has been EXECUTED
	and observed to reject the implementation it exists to catch before GREEN
	writes a line.

	NET-001's and NET-002's files are NOT modified by this story.
	`NetContract.luau` is required for its fixtures - `uniqueName`, `recorder`,
	the token schema shape - and nothing in it or in `PhaseContract.luau` is
	redefined here.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1 is settled: 1.5 is
	`tuning.md` §3's `signal_rate_limit_seconds`, marked derived, and it is READ
	OUT as `MIN_INTERVAL_SECONDS` below and declared on the test remote - never
	put into `src/shared/Tuning.luau`, whose scope is §1 and §5 and whose guard
	would fail on it. The boundary is inclusive: `now - lastAccepted >=
	minIntervalSeconds`, accepted exactly at the interval, and AC-1 is the ONLY
	check that lands exactly on it - every other check keeps its acceptances
	clear of the boundary so that a `>` implementation fails AC-1 alone.
	AC-2, AC-3, AC-5 and AC-6 are mechanical with the controls the criteria
	name, and `RateStubs.luau` writes them out. AC-4 is pinned exactly,
	structural form included: a remote with no `rateLimit` never reads the
	clock.

	NO TEST HERE SLEEPS, WAITS OR READS REAL TIME. `world()` hands back a
	context whose clock is `Clock.manual`, wrapped so that every `now()` read
	is counted; time moves only through `world.clock:set` and
	`world.clock:advance`. The boundary calls use `set(t + 1.5)` rather than
	accumulated `advance` steps, because `t + 1.4 + 0.1` is not `t + 1.5` in
	binary floating point and a rate limit test that lands on the boundary by
	accumulation is testing the rounding, not the comparison.

	THE ONE SUBTLE SHAPE IS AC-3's load case. Under a uniform 10 ms grid, an
	acceptance at `t + 1.5` puts the next boundary exactly on a grid point
	again, where `>` and `>=` disagree. So the load case runs 320 calls (3.2 s)
	and asserts the count served AFTER the first acceptance - 2 under either
	comparison (grid points 150 and 300 under `>=`, 151 and 302 under `>`) and
	0 under an implementation that records on rejection. The boundary belongs
	to AC-1 and AC-3 does not re-test it.
]]

local Clock = require("../../src/shared/Clock")
local Deep = require("./Deep")
local NetContract = require("./NetContract")

local RateContract = {}

export type Net = { Schema: any, Remotes: any, Wrapper: any, RateLimiter: any }

export type World = {
	phase: string,
	clock: Clock.ManualClock,
	clockReads: number,
}

--[[
	`tuning.md` §3, `signal_rate_limit_seconds` = 1.5, marked DERIVED. Settled:
	read out, not tuned. It reaches the wrapper through the remote's own
	declaration (`rateLimit = { minIntervalSeconds = 1.5 }`), and
	`tests/net/rate_limit_provenance_test.luau` anchors this literal to the
	document's table row so the number here cannot drift from the document
	unnoticed.
]]
RateContract.MIN_INTERVAL_SECONDS = 1.5

--[[
	The final assertion of every check goes through this rather than `assert`.
	MEASURED in SEAT-002's RED: under Lune, `assert(false, message)` truncates
	the message to 512 characters after the location prefix and `error` does
	not. Level 2 attributes the failure to the caller.
]]
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
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

local VALID = { token = 4, flag = true }

-- A start time that is not 0, so that `now - lastAccepted` and `now` are
-- different numbers and an implementation comparing the wrong one is visible.
local START = 10

--[[ ------------------------------------------------------------------------
     Fixtures
     ------------------------------------------------------------------------ ]]

--[[
	A `GuardContext` whose clock is a `Clock.manual` the check drives and whose
	every `now()` read is counted: `world.clock:set(...)` and
	`world.clock:advance(...)` move time, `world.clockReads` says how many
	times the guard asked. `phase` is a mutable field, as in
	`PhaseContract.world`, so AC-5 can put one call out of phase. `isSeated`
	answers for exactly the listed players.
]]
function RateContract.world(seated: { string }, phase: string, startSeconds: number): (any, World)
	local seatedSet: { [any]: boolean } = {}
	for _, id in seated do
		seatedSet[id] = true
	end
	local manual = Clock.manual(startSeconds)
	local world: World = { phase = phase, clock = manual, clockReads = 0 }
	local context = {
		isSeated = function(playerId: any): boolean
			return seatedSet[playerId] == true
		end,
		phase = function(): string
			return world.phase
		end,
		clock = {
			now = function(): number
				world.clockReads += 1
				return manual.now()
			end,
		},
	}
	return context, world
end

--[[
	NET-001's test remote - `{ token = integer(1, 16), flag = boolean() }` -
	legal in `Round`, declared under a unique name, with the given `rateLimit`
	(or none). The declaration is the ONLY route by which 1.5 reaches the
	wrapper; see the header.
]]
function RateContract.remote(net: Net, label: string, minIntervalSeconds: number?): any
	local spec: { [string]: any } = {
		args = net.Schema.shape({
			token = net.Schema.integer(1, 16),
			flag = net.Schema.boolean(),
		}),
		legalPhases = { "Round" },
	}
	if minIntervalSeconds ~= nil then
		spec.rateLimit = { minIntervalSeconds = minIntervalSeconds }
	end
	return net.Remotes.define(NetContract.uniqueName(label), spec)
end

-- One guarded call, with a raise reported as an outcome rather than ending the
-- check: the Contract says the guarded function never raises.
local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

-- A violation line for a call expected to be rejected for `expected`, or nil.
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
	if typeof(result.detail) ~= "string" or result.detail == "" then
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

-- A step of a timed sequence: set the clock, call, expect. `offset` is added to
-- START so a label reads `t + 1.4` and the clock is SET, never accumulated.
type Step = { at: number, playerId: string, accept: boolean, label: string? }

local function runSteps(
	criterion: string,
	guarded: any,
	world: World,
	steps: { Step },
	violations: { string }
)
	for i, step in steps do
		world.clock:set(START + step.at)
		local ok, result = call(guarded, step.playerId, VALID)
		local label = step.label or `call {i}: {step.playerId} at t + {step.at}`
		local violation: string?
		if step.accept then
			violation = expectAcceptance(criterion, label, ok, result)
		else
			violation = expectRejection(criterion, label, ok, result, "rate")
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
end

local function expectedRuns(steps: { Step }): number
	local n = 0
	for _, step in steps do
		if step.accept then
			n += 1
		end
	end
	return n
end

--[[ ------------------------------------------------------------------------
     AC-1 to AC-6
     ------------------------------------------------------------------------ ]]

--[[
	AC-1, settled. One remote at 1.5, one guard, one seated player: accepted
	at `t`, rejected for `rate` at `t + 1.4`, accepted at `t + 1.5` - the
	inclusive boundary, `now - lastAccepted >= minIntervalSeconds`. The three
	calls of the criterion and nothing else, so that a `>` implementation
	fails exactly one line here and nothing anywhere else.
]]
function RateContract.acceptsAtTheIntervalAndRejectsInsideIt(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "ac1", min)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	local steps: { Step } = {
		{ at = 0, playerId = "p1", accept = true, label = "the first call, at t" },
		{ at = 1.4, playerId = "p1", accept = false, label = "the same player at t + 1.4" },
		{
			at = min,
			playerId = "p1",
			accept = true,
			label = `the same player at t + {min}, exactly the interval`,
		},
	}
	local violations: { string } = {}
	runSteps("AC-1", guarded, world, steps, violations)
	local runs = expectedRuns(steps)
	if #calls ~= runs then
		table.insert(
			violations,
			`AC-1: the handler ran {#calls} time(s) over {#steps} calls; {runs} were outside the interval`
		)
	end
	check(
		#violations == 0,
		`AC-1: {#violations} violation(s) across {#steps} calls at minIntervalSeconds = {min} - the `
			.. `comparison is now - lastAccepted >= minIntervalSeconds, inclusive:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[
	AC-2. Two seated players, one guard. A is accepted at `t` and rejected at
	`t + 0.5`; B, at the same `t + 0.5`, is accepted - B has never called. Then
	each is held to their OWN interval: B at `t + 0.6` is rejected against B's
	acceptance, and A at `t + 0.6` against A's. An implementation with one
	shared timestamp accepts A, rejects A, and then rejects B too.
]]
function RateContract.playersAreLimitedIndependently(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "ac2", min)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "A", "B" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	local steps: { Step } = {
		{ at = 0, playerId = "A", accept = true, label = "A at t" },
		{ at = 0.5, playerId = "A", accept = false, label = "A at t + 0.5 (inside A's interval)" },
		{
			at = 0.5,
			playerId = "B",
			accept = true,
			label = "B at t + 0.5, the same instant A is rate-limited",
		},
		{
			at = 0.6,
			playerId = "B",
			accept = false,
			label = "B at t + 0.6 (inside B's own interval)",
		},
		{ at = 0.6, playerId = "A", accept = false, label = "A at t + 0.6 (still inside A's)" },
	}
	local violations: { string } = {}
	runSteps("AC-2", guarded, world, steps, violations)
	local runs = expectedRuns(steps)
	if #calls ~= runs then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) over {#steps} calls; {runs} were accepted`
		)
	end
	for _, entry in calls do
		if entry.playerId ~= "A" and entry.playerId ~= "B" then
			table.insert(violations, `AC-2: the handler saw playerId {Deep.show(entry.playerId)}`)
		end
	end
	check(
		#violations == 0,
		`AC-2: {#violations} violation(s) across {#steps} calls by two players - an implementation `
			.. `with one shared last-accepted timestamp fails here:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[
	AC-3. The interval is measured from the last ACCEPTED call. One player
	accepted at `t`, then rejected at `t + 0.5`, `t + 1.0` and `t + 1.4`; at
	`t + 1.6` they are accepted, 1.6 s after the acceptance and 0.2 s after the
	last rejection. An implementation that records the timestamp on rejection
	answers `t + 1.6` with "0.2 s since your last call".

	Then the load case the criterion describes: from a fresh acceptance, 320
	calls at 10 ms - 3.2 simulated seconds, no waiting - must be served exactly
	twice more (every 1.5 s, at grid points 150 and 300 under `>=`, 151 and
	302 under `>`). Under the defective implementation every call moves the
	timestamp and the player is served 0 times: locked out forever.
]]
function RateContract.intervalIsMeasuredFromTheLastAcceptedCall(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "ac3", min)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	local steps: { Step } = {
		{ at = 0, playerId = "p1", accept = true, label = "accepted at t" },
		{ at = 0.5, playerId = "p1", accept = false, label = "rejected at t + 0.5" },
		{ at = 1.0, playerId = "p1", accept = false, label = "rejected at t + 1.0" },
		{ at = 1.4, playerId = "p1", accept = false, label = "rejected at t + 1.4" },
		{
			at = 1.6,
			playerId = "p1",
			accept = true,
			label = "t + 1.6: 1.6 s after the last ACCEPTED call, 0.2 s after the last attempt",
		},
	}
	local violations: { string } = {}
	runSteps("AC-3", guarded, world, steps, violations)
	local runs = expectedRuns(steps)
	if #calls ~= runs then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) over {#steps} calls; {runs} were outside the interval`
		)
	end

	-- The load case. A fresh guard and player so the count is clean.
	local loadHandler, loadCalls = NetContract.recorder()
	local loadContext, loadWorld = RateContract.world({ "p9" }, "Round", START)
	local loadGuarded = net.Wrapper.guard(definition, loadContext, loadHandler)
	local first = call(loadGuarded, "p9", VALID)
	if not first or #loadCalls ~= 1 then
		table.insert(
			violations,
			`AC-3: the load case's first call at t was not accepted (the handler ran {#loadCalls} time(s))`
		)
	end
	local total = 320
	local served = 0
	local raised: string? = nil
	for i = 1, total do
		loadWorld.clock:set(START + i / 100)
		local ok, result = call(loadGuarded, "p9", VALID)
		if not ok then
			raised = raised or `AC-3: load call {i} RAISED: {tostring(result)}`
		elseif result == nil then
			served += 1
		elseif typeof(result) ~= "table" or result.reason ~= "rate" then
			raised = raised
				or `AC-3: load call {i} -> {describeResult(result)}, expected reason "rate"`
		end
	end
	if raised ~= nil then
		table.insert(violations, raised :: string)
	end
	if served ~= 2 then
		table.insert(
			violations,
			`AC-3: over {total} calls at 10 ms ({total / 100} s of 100 Hz) after an acceptance, the `
				.. `player was served {served} time(s); a limit of one call per {min} s serves them 2 `
				.. `times - an implementation that records the timestamp on rejection locks them out `
				.. `forever`
		)
	end
	if #loadCalls ~= served + 1 then
		table.insert(
			violations,
			`AC-3: the load handler ran {#loadCalls} time(s) for {served + 1} accepted calls`
		)
	end

	check(
		#violations == 0,
		`AC-3: {#violations} violation(s) across {#steps + 1 + total} calls - an implementation that `
			.. `updates the timestamp on rejection fails here:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[
	AC-4. A remote declared with NO `rateLimit`: fifty calls by one player at
	one frozen instant, every one accepted, the handler run fifty times, and
	the clock read ZERO times - counted from BEFORE `guard()` is called, so
	the structural form ("never reads the clock at all") covers construction
	as well as the calls.
]]
function RateContract.remoteWithoutRateLimitIsNeverLimited(net: Net)
	local definition = RateContract.remote(net, "ac4", nil)
	check(
		definition.rateLimit == nil,
		`AC-4: the test remote was declared without a rateLimit but has {Deep.show(
			definition.rateLimit
		)}`
	)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local readsBeforeGuard = world.clockReads
	local guarded = net.Wrapper.guard(definition, context, handler)

	local total = 50
	local violations: { string } = {}
	local rejected = 0
	local firstRejection: string? = nil
	for i = 1, total do
		local ok, result = call(guarded, "p1", VALID)
		local violation = expectAcceptance("AC-4", `call {i} at the same instant`, ok, result)
		if violation ~= nil then
			rejected += 1
			firstRejection = firstRejection or violation
		end
	end
	if rejected > 0 then
		table.insert(
			violations,
			`AC-4: {rejected} of {total} calls were not accepted; the first: {firstRejection}`
		)
	end
	if #calls ~= total then
		table.insert(violations, `AC-4: the handler ran {#calls} time(s) over {total} calls`)
	end
	local reads = world.clockReads - readsBeforeGuard
	if reads ~= 0 then
		table.insert(
			violations,
			`AC-4: context.clock.now() was read {reads} time(s) across guard() and {total} calls; a `
				.. `remote with no rateLimit never reads the clock`
		)
	end
	check(
		#violations == 0,
		`AC-4: {#violations} violation(s) for a remote with no rateLimit:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	AC-5. Rate is check 5 of 5. After an acceptance at `t`, four calls at
	`t + 1.0` that fail identity, shape, range and phase are rejected for
	THOSE reasons - and read the clock zero times, which is the structural
	half. Then the behavioural half, from both sides of the interval:

	  * a valid call at `t + 2.0` is accepted - so none of the four advanced
	    the player's timestamp to `t + 1.0`;
	  * an out-of-phase call at `t + 4.0` (outside the interval, so a limiter
	    consulted ahead of the phase check WOULD accept and record it) is
	    rejected for `phase`, and a valid call at `t + 5.0` is then accepted -
	    so the phase-rejected call advanced nothing either;
	  * and a valid call at `t + 5.5` is rejected for `rate`, the positive
	    control inside the check: the limiter exists and is measured from
	    `t + 5.0`.

	Gaps of 2.0 and 3.0 keep every acceptance clear of the boundary, which
	belongs to AC-1.
]]
function RateContract.earlierRejectionsDoNotAdvanceTheLimiter(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "ac5", min)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	type Case = {
		label: string,
		at: number,
		phase: string,
		playerId: string,
		args: any,
		expected: string?,
	}
	local cases: { Case } = {
		{
			label = "valid at t -> accepted",
			at = 0,
			phase = "Round",
			playerId = "p1",
			args = VALID,
		},
		{
			label = "unseated caller at t + 1.0 -> identity",
			at = 1.0,
			phase = "Round",
			playerId = "p2",
			args = VALID,
			expected = "identity",
		},
		{
			label = "malformed {} at t + 1.0 -> shape",
			at = 1.0,
			phase = "Round",
			playerId = "p1",
			args = {},
			expected = "shape",
		},
		{
			label = "{ token = 99, flag = true } at t + 1.0 -> range",
			at = 1.0,
			phase = "Round",
			playerId = "p1",
			args = { token = 99, flag = true },
			expected = "range",
		},
		{
			label = "valid but out of phase (Lobby) at t + 1.0 -> phase",
			at = 1.0,
			phase = "Lobby",
			playerId = "p1",
			args = VALID,
			expected = "phase",
		},
		{
			label = "valid at t + 2.0 -> accepted (nothing above advanced the timestamp)",
			at = 2.0,
			phase = "Round",
			playerId = "p1",
			args = VALID,
		},
		{
			label = "valid but out of phase (Lobby) at t + 4.0, outside the interval -> phase",
			at = 4.0,
			phase = "Lobby",
			playerId = "p1",
			args = VALID,
			expected = "phase",
		},
		{
			label = "valid at t + 5.0 -> accepted (the phase-rejected call advanced nothing)",
			at = 5.0,
			phase = "Round",
			playerId = "p1",
			args = VALID,
		},
		{
			label = "valid at t + 5.5 -> rate (the limiter is measured from t + 5.0)",
			at = 5.5,
			phase = "Round",
			playerId = "p1",
			args = VALID,
			expected = "rate",
		},
	}

	local violations: { string } = {}
	local expectedRunCount = 0
	for _, case in cases do
		world.phase = case.phase
		world.clock:set(START + case.at)
		local readsBefore = world.clockReads
		local ok, result = call(guarded, case.playerId, case.args)
		local violation: string?
		if case.expected == nil then
			expectedRunCount += 1
			violation = expectAcceptance("AC-5", case.label, ok, result)
		else
			violation = expectRejection("AC-5", case.label, ok, result, case.expected :: string)
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
		local reads = world.clockReads - readsBefore
		if case.expected ~= nil and case.expected ~= "rate" and reads > 0 then
			table.insert(
				violations,
				`AC-5: {case.label} -> context.clock.now() was read {reads} time(s); rate is check 5 `
					.. `and a call an earlier check rejected never reaches it`
			)
		end
	end
	if #calls ~= expectedRunCount then
		table.insert(
			violations,
			`AC-5: the handler ran {#calls} time(s) over {#cases} calls; {expectedRunCount} were accepted`
		)
	end
	check(
		#violations == 0,
		`AC-5: {#violations} violation(s) across {#cases} calls - a limiter consulted before identity, `
			.. `shape, range or phase, or advanced by a call they rejected, fails here:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[
	AC-6, a unit criterion on `RateLimiter` itself. One entry per PLAYER
	holding a timestamp per key (the Contract's pinned shape): a player who
	uses two remotes is ONE entry; `forget` removes the whole entry, so the
	player is new again - their next call at the same instant is allowed;
	`size()` counts players. Then a full round: eight players join and call
	two remotes each, three leave, the rest leave - and at every step
	`size()` equals the number still seated. Forgetting a player the limiter
	never saw is a no-op, not a raise.
]]
function RateContract.forgetRemovesThePlayerAndSizeCountsSeatedPlayers(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	check(
		net.RateLimiter ~= nil,
		"AC-6: src/net/RateLimiter.luau did not load - the limiter is a new module and AC-6 is a unit "
			.. "criterion on it"
	)
	check(
		typeof(net.RateLimiter.new) == "function",
		`AC-6: RateLimiter.new is {typeof(net.RateLimiter.new)}; expected a function`
	)
	local limiter = net.RateLimiter.new(min)
	check(typeof(limiter) == "table", `AC-6: RateLimiter.new({min}) returned {Deep.show(limiter)}`)
	for _, method in { "allow", "forget", "size" } do
		check(
			typeof(limiter[method]) == "function",
			`AC-6: the limiter's {method} is {typeof(limiter[method])}; expected a method`
		)
	end

	local violations: { string } = {}
	local function expectSize(label: string, expected: number)
		local ok, size = pcall(function()
			return limiter:size()
		end)
		if not ok then
			table.insert(violations, `AC-6: size() RAISED {label}: {tostring(size)}`)
		elseif size ~= expected then
			table.insert(
				violations,
				`AC-6: size() is {Deep.show(size)} {label}; expected {expected}`
			)
		end
	end
	local function expectAllow(
		label: string,
		playerId: string,
		key: string,
		now: number,
		expected: boolean
	)
		local ok, allowed = pcall(function()
			return limiter:allow(playerId, key, now)
		end)
		if not ok then
			table.insert(
				violations,
				`AC-6: allow("{playerId}", "{key}", {now}) RAISED: {tostring(allowed)}`
			)
		elseif allowed ~= expected then
			table.insert(
				violations,
				`AC-6: allow("{playerId}", "{key}", {now}) returned {Deep.show(allowed)} ({label}); `
					.. `expected {expected}`
			)
		end
	end
	local function forget(playerId: string)
		local ok, err = pcall(function()
			limiter:forget(playerId)
		end)
		if not ok then
			table.insert(violations, `AC-6: forget("{playerId}") RAISED: {tostring(err)}`)
		end
	end

	expectSize("before any call", 0)
	expectAllow("first call", "p1", "remoteA", 0, true)
	expectSize("after p1's first call", 1)
	expectAllow("inside the interval on the same key", "p1", "remoteA", 0.5, false)
	expectSize("after p1's rejected call", 1)
	expectAllow("a second key is independent of the first", "p1", "remoteB", 0.5, true)
	expectSize("after p1 used a second remote - one entry per PLAYER, not per (player, key)", 1)
	expectAllow("a second player", "p2", "remoteA", 0.5, true)
	expectSize("after p2's first call", 2)

	forget("p1")
	expectSize("after forget(p1)", 1)
	expectAllow(
		"p1 is new again after forget: allowed at the instant p1 was just refused",
		"p1",
		"remoteA",
		0.5,
		true
	)
	expectSize("after p1 returned", 2)
	forget("p2")
	forget("p1")
	expectSize("after both left", 0)
	forget("never-seen")
	expectSize("after forgetting a player the limiter never saw", 0)

	-- A full round.
	local seated: { string } = {}
	for i = 1, 8 do
		local id = `player{i}`
		table.insert(seated, id)
		expectAllow(`{id} joins and calls remoteA`, id, "remoteA", 100, true)
		expectAllow(`{id} calls remoteB`, id, "remoteB", 100, true)
		expectAllow(`{id} calls remoteA again inside the interval`, id, "remoteA", 100.1, false)
		expectSize(`with {#seated} seated`, #seated)
	end
	for _, leaver in { "player2", "player5", "player8" } do
		forget(leaver)
		local index = table.find(seated, leaver)
		if index ~= nil then
			table.remove(seated, index)
		end
		expectSize(`after {leaver} left, with {#seated} seated`, #seated)
	end
	while #seated > 0 do
		local leaver = table.remove(seated) :: string
		forget(leaver)
		expectSize(`after {leaver} left, with {#seated} seated`, #seated)
	end

	check(
		#violations == 0,
		`AC-6: {#violations} violation(s) - a limiter whose forget is a no-op, or whose size counts `
			.. `(player, key) pairs, fails here:\n{indent(table.concat(violations, "\n"))}`
	)
end

--[[ ------------------------------------------------------------------------
     The Contract's own promises about a rate rejection
     ------------------------------------------------------------------------ ]]

--[[
	Contract, "`detail` for a rate rejection": a remote declared at 1.5 under
	a unique name, called twice at one instant - the second is `rate`, and its
	detail is non-empty, does not lead with `rate:`, contains the remote's name
	as a plain substring and contains `1.5`. Wording otherwise free; how long
	the caller waited is deliberately NOT pinned (a float difference).
]]
function RateContract.rateRejectionDetailNamesTheRemoteAndTheInterval(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "detail", min)
	local handler = NetContract.recorder()
	local context = RateContract.world({ "p1" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	local ok1, result1 = call(guarded, "p1", VALID)
	local accepted = expectAcceptance("detail", "the first call at t", ok1, result1)
	check(accepted == nil, accepted or "")
	local ok, result = call(guarded, "p1", VALID)
	local rejected =
		expectRejection("detail", "the second call at the same instant", ok, result, "rate")
	check(rejected == nil, rejected or "")
	local detail = result.detail :: string

	local violations: { string } = {}
	if string.match(detail, "^rate:") ~= nil then
		table.insert(
			violations,
			`detail leads with "rate:", a second encoding of reason that a refactor could let drift: `
				.. `"{detail}"`
		)
	end
	if string.find(detail, definition.name, 1, true) == nil then
		table.insert(violations, `detail does not name the remote "{definition.name}": "{detail}"`)
	end
	if string.find(detail, tostring(min), 1, true) == nil then
		table.insert(violations, `detail does not carry the required interval {min}: "{detail}"`)
	end
	check(
		#violations == 0,
		`the rate rejection's detail failed in {#violations} way(s):\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	Contract, "`context.clock.now()` is read per call that reaches check 5,
	and not before". For a remote that declares a rateLimit: zero reads on a
	call identity, shape, range or phase rejected; at least one read on a
	call that reaches check 5, accepted or rate-rejected; and the value
	compared is the one THAT call returned - the guard is built at `t`, the
	clock is moved to `t + 40` before the first call, and a call 2.5 s after
	that is accepted, which a clock captured at `guard()` (0 s elapsed
	forever) refuses.
]]
function RateContract.clockIsReadOnlyByCallsThatReachTheRateCheck(net: Net)
	local min = RateContract.MIN_INTERVAL_SECONDS
	local definition = RateContract.remote(net, "clockreads", min)
	local handler, calls = NetContract.recorder()
	local context, world = RateContract.world({ "p1" }, "Round", START)
	local guarded = net.Wrapper.guard(definition, context, handler)

	type Case = {
		label: string,
		at: number,
		phase: string,
		playerId: string,
		args: any,
		expected: string?,
		reads: boolean,
	}
	local cases: { Case } = {
		{
			label = "an unseated caller (identity)",
			at = 40,
			phase = "Round",
			playerId = "p2",
			args = VALID,
			expected = "identity",
			reads = false,
		},
		{
			label = "a malformed payload (shape)",
			at = 40,
			phase = "Round",
			playerId = "p1",
			args = {},
			expected = "shape",
			reads = false,
		},
		{
			label = "an out-of-range payload (range)",
			at = 40,
			phase = "Round",
			playerId = "p1",
			args = { token = 99, flag = true },
			expected = "range",
			reads = false,
		},
		{
			label = "a valid payload out of phase (phase)",
			at = 40,
			phase = "Lobby",
			playerId = "p1",
			args = VALID,
			expected = "phase",
			reads = false,
		},
		{
			label = "a valid payload in phase at t + 40, the guard having been built at t (accepted)",
			at = 40,
			phase = "Round",
			playerId = "p1",
			args = VALID,
			reads = true,
		},
		{
			label = "the same player at t + 40.5 (rate)",
			at = 40.5,
			phase = "Round",
			playerId = "p1",
			args = VALID,
			expected = "rate",
			reads = true,
		},
		{
			label = "the same player at t + 42.5, 2.5 s after the acceptance (accepted - the clock of the "
				.. "moment, not the clock at guard())",
			at = 42.5,
			phase = "Round",
			playerId = "p1",
			args = VALID,
			reads = true,
		},
	}

	local violations: { string } = {}
	local expectedRunCount = 0
	for _, case in cases do
		world.phase = case.phase
		world.clock:set(START + case.at)
		local before = world.clockReads
		local ok, result = call(guarded, case.playerId, case.args)
		local violation: string?
		if case.expected == nil then
			expectedRunCount += 1
			violation = expectAcceptance("clock", case.label, ok, result)
		else
			violation = expectRejection("clock", case.label, ok, result, case.expected :: string)
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
		local reads = world.clockReads - before
		if case.reads and reads == 0 then
			table.insert(
				violations,
				`clock: {case.label} -> context.clock.now() was not read during the call, yet the call `
					.. `was judged on its timing`
			)
		elseif not case.reads and reads > 0 then
			table.insert(
				violations,
				`clock: {case.label} -> context.clock.now() was read {reads} time(s); an earlier check `
					.. `fails first and nothing after it runs`
			)
		end
	end
	if #calls ~= expectedRunCount then
		table.insert(
			violations,
			`clock: the handler ran {#calls} time(s) over {#cases} calls; {expectedRunCount} were accepted`
		)
	end
	check(
		#violations == 0,
		`clock: {#violations} violation(s) across {#cases} calls:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

return RateContract
