--!strict
--[[
	NET-002 AC-1 through AC-6, plus the two promises the story's `## Contract`
	makes about a phase rejection, written once as checks over a `Net` bundle -
	`{ Schema, Remotes, Wrapper }` - handed in as a parameter rather than over
	`src/net/*.luau` by name. The same arrangement as `NetContract.luau`, for
	the same reason: `tests/net/phase_test.luau` applies these to the real
	modules and `tests/net/phase_controls_test.luau` applies them to the
	deliberately wrong bundles in `PhaseStubs.luau`, so that every check here
	has been EXECUTED and observed to reject the implementation it exists to
	catch before GREEN writes a line. AC-7 is not here: it is a tree-scanning
	guard and lives in `tests/net/phase_union_guard_test.luau`.

	NET-001's files are NOT modified by this story. `NetContract.luau` is
	required for its fixtures - `uniqueName`, `recorder`, the token schema
	shape - and nothing in it is redefined here.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1, AC-2 and AC-5 are mechanical
	and pinned exactly. AC-3 is settled: the check order is NET-001's Contract
	("Check order - fixed") and is read out, not re-derived - identity, shape
	and range all win over phase. AC-4 and AC-6 are mechanical with the
	controls the criteria name, and `PhaseStubs.luau` writes both out:
	`firstEntryOnly` and `capturesPhaseAtGuard`.

	THE ONE SUBTLE SHAPE IS AC-6. A check that builds a context, sets the
	phase and calls cannot tell a live `context.phase()` read from a value
	captured when `guard` was called, because only one phase is ever in play.
	So AC-2, AC-3 and AC-4 deliberately build a FRESH guard per phase - the
	natural shape, and the one a captured-phase implementation passes - and
	AC-6 alone guards ONCE and then calls in several phases. That is what
	makes the captured-phase control fail AC-6 and no other CRITERION - the
	single-assertion catch `## Notes` predicts for mutation 1. (The Contract's
	short-circuit check below counts `context.phase()` reads per call and
	catches it too; measured, and recorded in the controls suite.)

	THE PHASE IS A WORLD, NOT A CONSTANT. `PhaseContract.world` hands back a
	context whose `phase()` reads a mutable field and counts its reads, so a
	check can move the phase between calls and can say how many times the
	guard asked.
]]

local Clock = require("../../src/shared/Clock")
local Deep = require("./Deep")
local NetContract = require("./NetContract")

local PhaseContract = {}

export type Net = NetContract.Net

export type World = { phase: string, reads: number }

-- The five phases, in `PhaseMachine.luau`'s order. AC-2 names the four that
-- are not `Round`; AC-4 needs all five.
PhaseContract.PHASES = { "Lobby", "Assignment", "Round", "Resolution", "Post" }

-- Every phase except those in `except`, in the same order.
function PhaseContract.phasesExcept(except: { string }): { string }
	local out: { string } = {}
	for _, phase in PhaseContract.PHASES do
		if table.find(except, phase) == nil then
			table.insert(out, phase)
		end
	end
	return out
end

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
local NAN = 0 / 0

--[[ ------------------------------------------------------------------------
     Fixtures
     ------------------------------------------------------------------------ ]]

--[[
	A `GuardContext` whose phase is a field of the returned world rather than
	a constant: set `world.phase` between calls, read `world.reads` to know
	how many times the guard asked. `isSeated` answers for exactly the listed
	players; `clock` is the Contract's and nothing here reads it.
]]
function PhaseContract.world(seated: { string }, phase: string): (any, World)
	local seatedSet: { [any]: boolean } = {}
	for _, id in seated do
		seatedSet[id] = true
	end
	local world: World = { phase = phase, reads = 0 }
	local context = {
		isSeated = function(playerId: any): boolean
			return seatedSet[playerId] == true
		end,
		phase = function(): string
			world.reads += 1
			return world.phase
		end,
		clock = Clock.manual(0),
	}
	return context, world
end

-- NET-001's test remote - `{ token = integer(1, 16), flag = boolean() }` -
-- declared through the registry with the given legal phases, under a unique
-- name. The label must not contain a phase name: the detail check below
-- asserts on phase names as substrings of the rejection detail, and a remote
-- name carrying one would satisfy the needle by accident.
function PhaseContract.remote(net: Net, label: string, legalPhases: { string }): any
	for _, phase in PhaseContract.PHASES do
		assert(
			string.find(label, phase, 1, true) == nil,
			`the remote label "{label}" contains the phase name "{phase}"`
		)
	end
	return net.Remotes.define(NetContract.uniqueName(label), {
		args = net.Schema.shape({
			token = net.Schema.integer(1, 16),
			flag = net.Schema.boolean(),
		}),
		legalPhases = legalPhases,
	})
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

--[[ ------------------------------------------------------------------------
     AC-1 to AC-6
     ------------------------------------------------------------------------ ]]

--[[
	AC-1. A remote legal only in `Round`, a seated player, a valid payload,
	the phase `Round`: the handler runs, once, with the arguments. This is the
	positive control for the whole story - a wrapper that rejects every phase
	passes AC-2 and fails here.
]]
function PhaseContract.handlerRunsInTheOnlyLegalPhase(net: Net)
	local definition = PhaseContract.remote(net, "ac1", { "Round" })
	local handler, calls = NetContract.recorder()
	local context = PhaseContract.world({ "p1" }, "Round")
	local guarded = net.Wrapper.guard(definition, context, handler)

	local ok, result = call(guarded, "p1", VALID)
	check(ok, `AC-1: a valid call in the legal phase raised: {tostring(result)}`)
	check(
		result == nil,
		`AC-1: a valid call by a seated player in the remote's only legal phase was rejected: `
			.. describeResult(result)
	)
	check(#calls == 1, `AC-1: the handler ran {#calls} time(s) for one valid call in phase`)
	check(
		calls[1].playerId == "p1",
		`AC-1: the handler received playerId {Deep.show(calls[1].playerId)}, expected "p1"`
	)
	local diff = Deep.diff(VALID, calls[1].args)
	check(diff == "", `AC-1: the handler did not receive the validated arguments:\n{indent(diff)}`)
end

--[[
	AC-2. The same remote, called in each of the four other phases: the
	handler does not run and the reason is `"phase"` in EVERY case, with a
	non-empty detail. A fresh guard per phase - deliberately the shape a
	captured-phase implementation passes; AC-6 is where that is caught.
]]
function PhaseContract.outOfPhaseCallIsRejectedForPhase(net: Net)
	local definition = PhaseContract.remote(net, "ac2", { "Round" })
	local handler, calls = NetContract.recorder()
	local phases = PhaseContract.phasesExcept({ "Round" })

	local violations: { string } = {}
	for _, phase in phases do
		local context = PhaseContract.world({ "p1" }, phase)
		local guarded = net.Wrapper.guard(definition, context, handler)
		local ok, result = call(guarded, "p1", VALID)
		local label = `a valid call by a seated player while the phase is {phase}`
		local violation = expectRejection("AC-2", label, ok, result, "phase")
		if violation ~= nil then
			table.insert(violations, violation :: string)
		elseif typeof(result.detail) ~= "string" or result.detail == "" then
			table.insert(
				violations,
				`AC-2: {label} -> detail is {Deep.show(result.detail)}; must be a non-empty string`
			)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#phases} out-of-phase calls; it must not `
				.. `run at all`
		)
	end
	check(
		#violations == 0,
		`AC-2: {#violations} violation(s) across {#phases} out-of-phase calls:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	AC-3, settled by NET-001's fixed check order: identity, shape and range
	all fire BEFORE phase. Out of phase, an unseated caller is `identity`, a
	malformed payload is `shape`, an out-of-range one is `range`, and only a
	call that passed all three is `phase`. The spy schema pins the same thing
	from the other side: it is consulted exactly once before a phase rejection,
	so the phase check cannot have run ahead of it.
]]
function PhaseContract.earlierChecksWinOverPhase(net: Net)
	local definition = PhaseContract.remote(net, "ac3", { "Round" })
	local handler, calls = NetContract.recorder()
	local context = PhaseContract.world({ "p1" }, "Lobby")
	local guarded = net.Wrapper.guard(definition, context, handler)

	local cases: { { label: string, playerId: any, args: any, expected: string } } = {
		{
			label = "unseated + valid payload, out of phase -> identity",
			playerId = "p2",
			args = VALID,
			expected = "identity",
		},
		{
			label = "seated + {} (arity), out of phase -> shape",
			playerId = "p1",
			args = {},
			expected = "shape",
		},
		{
			label = 'seated + { token = "4", flag = true } (wrong type), out of phase -> shape',
			playerId = "p1",
			args = { token = "4", flag = true },
			expected = "shape",
		},
		{
			label = "seated + nil, out of phase -> shape",
			playerId = "p1",
			args = nil,
			expected = "shape",
		},
		{
			label = "seated + 7 (non-table), out of phase -> shape",
			playerId = "p1",
			args = 7,
			expected = "shape",
		},
		{
			label = "seated + { token = 99, flag = true } (range), out of phase -> range",
			playerId = "p1",
			args = { token = 99, flag = true },
			expected = "range",
		},
		{
			label = "seated + { token = 0/0, flag = true } (NaN), out of phase -> range",
			playerId = "p1",
			args = { token = NAN, flag = true },
			expected = "range",
		},
		{
			label = 'seated + { token = 99, flag = "no" } (range and shape), out of phase -> shape',
			playerId = "p1",
			args = { token = 99, flag = "no" },
			expected = "shape",
		},
		{
			label = "seated + valid payload, out of phase -> phase",
			playerId = "p1",
			args = VALID,
			expected = "phase",
		},
	}

	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, case.playerId, case.args)
		local violation = expectRejection("AC-3", case.label, ok, result, case.expected)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) across {#cases} rejected calls`
		)
	end

	-- The spy: a phase rejection is reached THROUGH the schema, once.
	local consulted = 0
	local spy = {
		validate = function(_value: any): (boolean, string?)
			consulted += 1
			return true, nil
		end,
	}
	local spied = net.Remotes.define(NetContract.uniqueName("ac3spy"), {
		args = spy,
		legalPhases = { "Round" },
	})
	local spyHandler, spyCalls = NetContract.recorder()
	local spyGuarded = net.Wrapper.guard(spied, context, spyHandler)
	local ok, result = call(spyGuarded, "p1", { anything = 1 })
	local violation = expectRejection(
		"AC-3",
		"spy schema: seated + accepted payload, out of phase -> phase",
		ok,
		result,
		"phase"
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if consulted ~= 1 then
		table.insert(
			violations,
			`AC-3: the schema was consulted {consulted} time(s) before the phase rejection; shape and `
				.. `range run before phase, so it must be consulted exactly once`
		)
	end
	if #spyCalls > 0 then
		table.insert(violations, `AC-3: the spy remote's handler ran {#spyCalls} time(s)`)
	end

	-- And in phase the valid payload is accepted: a fresh guard, so this
	-- check stays blind to a captured phase on purpose.
	local inPhase = net.Wrapper.guard(definition, PhaseContract.world({ "p1" }, "Round"), handler)
	local ok2, result2 = call(inPhase, "p1", VALID)
	local accepted = expectAcceptance("AC-3", "seated + valid payload, in phase", ok2, result2)
	if accepted ~= nil then
		table.insert(violations, accepted :: string)
	elseif #calls ~= 1 then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) for one valid call in phase`
		)
	end

	check(
		#violations == 0,
		`AC-3: {#violations} violation(s) across {#cases + 3} calls:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	AC-4. A remote legal in three phases - first, middle and last of the list,
	so that "compare against the first entry", "the last entry" and "the
	list" are three different answers - runs in each of them and is rejected
	for `phase` in the other two. A fresh guard per phase, as in AC-2.
]]
function PhaseContract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse(net: Net)
	local legal = { "Lobby", "Round", "Post" }
	local definition = PhaseContract.remote(net, "ac4", legal)
	local handler, calls = NetContract.recorder()

	local violations: { string } = {}
	for _, phase in PhaseContract.PHASES do
		local context = PhaseContract.world({ "p1" }, phase)
		local guarded = net.Wrapper.guard(definition, context, handler)
		local before = #calls
		local ok, result = call(guarded, "p1", VALID)
		local isLegal = table.find(legal, phase) ~= nil
		local label =
			`a valid call while the phase is {phase} ({if isLegal then "legal" else "not legal"})`
		local violation: string?
		if isLegal then
			violation = expectAcceptance("AC-4", label, ok, result)
		else
			violation = expectRejection("AC-4", label, ok, result, "phase")
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		else
			local ran = #calls - before
			local expected = if isLegal then 1 else 0
			if ran ~= expected then
				table.insert(
					violations,
					`AC-4: {label} -> the handler ran {ran} time(s), expected {expected}`
				)
			end
		end
	end
	check(
		#violations == 0,
		`AC-4: {#violations} violation(s) across {#PhaseContract.PHASES} phases - an implementation `
			.. `comparing against one entry of legalPhases fails here:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[
	AC-5. `legalPhases = {}` is a DECLARATION error: `define` raises, naming
	the remote and the field; the registry does not grow; and the name is
	still free, so a refused declaration has not poisoned it. The one-phase
	list beside it is the boundary from the other side.
]]
function PhaseContract.emptyLegalPhasesIsADeclarationError(net: Net)
	local schema = net.Schema.shape({ token = net.Schema.integer(1, 16) })
	local name = NetContract.uniqueName("ac5")
	local before = #net.Remotes.all()

	local ok, err = pcall(net.Remotes.define, name, { args = schema, legalPhases = {} })
	check(
		ok == false,
		`AC-5: declaring "{name}" with an empty legalPhases did not fail; define returned {Deep.show(
			err
		)}`
	)
	check(
		string.find(tostring(err), name, 1, true) ~= nil,
		`AC-5: the failure does not name the remote "{name}": {tostring(err)}`
	)
	check(
		string.find(tostring(err), "legalPhases", 1, true) ~= nil,
		`AC-5: the failure does not name the field legalPhases: {tostring(err)}`
	)

	local all = net.Remotes.all()
	check(
		#all == before,
		`AC-5: the registry has {#all} entries after the refused declaration; it had {before}`
	)
	for _, entry in all do
		check(entry.name ~= name, `AC-5: the refused remote "{name}" is in Remotes.all()`)
	end

	local ok2, retried =
		pcall(net.Remotes.define, name, { args = schema, legalPhases = { "Round" } })
	check(
		ok2 == true,
		`AC-5: after the refusal, declaring "{name}" with one legal phase failed: {tostring(retried)}`
	)
	check(
		typeof(retried) == "table" and retried.name == name,
		`AC-5: the retried declaration returned {Deep.show(retried)}`
	)
	local diff = Deep.diff({ "Round" }, retried.legalPhases)
	check(diff == "", `AC-5: the retried declaration's legalPhases differ:\n{indent(diff)}`)
	check(
		#net.Remotes.all() == before + 1,
		`AC-5: Remotes.all() has {#net.Remotes.all()} entries after the retry; expected {before + 1}`
	)
end

--[[
	AC-6. Guard ONCE, then call while the world moves through several phases.
	The guard is built while the phase is `Lobby`; the calls in `Round` must
	be accepted and the calls in `Lobby` and `Post` rejected. A second guard
	built while the phase is `Round` is then rejected once the phase moves.
	An implementation that captures `context.phase()` when `guard` is called
	answers every call with the phase of construction and fails here - and
	only here, because every other check builds a fresh guard per phase.
]]
function PhaseContract.phaseIsReadAtTheMomentOfEachCall(net: Net)
	local definition = PhaseContract.remote(net, "ac6", { "Round" })
	local violations: { string } = {}

	local handler, calls = NetContract.recorder()
	local context, world = PhaseContract.world({ "p1" }, "Lobby")
	local guarded = net.Wrapper.guard(definition, context, handler)

	local sequence: { { phase: string, accept: boolean } } = {
		{ phase = "Lobby", accept = false },
		{ phase = "Round", accept = true },
		{ phase = "Post", accept = false },
		{ phase = "Round", accept = true },
	}
	local expectedRuns = 0
	for i, step in sequence do
		world.phase = step.phase
		local readsBefore = world.reads
		local ok, result = call(guarded, "p1", VALID)
		local label = `guarded in Lobby, call {i} while the phase is {step.phase}`
		local violation: string?
		if step.accept then
			expectedRuns += 1
			violation = expectAcceptance("AC-6", label, ok, result)
			if violation == nil and world.reads == readsBefore then
				violation = `AC-6: {label} -> context.phase() was not consulted during the call; the `
					.. `phase it accepted was not the phase of the moment`
			end
		else
			violation = expectRejection("AC-6", label, ok, result, "phase")
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls ~= expectedRuns then
		table.insert(
			violations,
			`AC-6: the handler ran {#calls} time(s) over {#sequence} calls; {expectedRuns} were in phase`
		)
	end

	-- The other direction: guarded in the legal phase, called after it moved.
	local handler2, calls2 = NetContract.recorder()
	local context2, world2 = PhaseContract.world({ "p1" }, "Round")
	local guarded2 = net.Wrapper.guard(definition, context2, handler2)
	local sequence2: { { phase: string, accept: boolean } } = {
		{ phase = "Round", accept = true },
		{ phase = "Assignment", accept = false },
		{ phase = "Round", accept = true },
	}
	local expectedRuns2 = 0
	for i, step in sequence2 do
		world2.phase = step.phase
		local ok, result = call(guarded2, "p1", VALID)
		local label = `guarded in Round, call {i} while the phase is {step.phase}`
		local violation: string?
		if step.accept then
			expectedRuns2 += 1
			violation = expectAcceptance("AC-6", label, ok, result)
		else
			violation = expectRejection("AC-6", label, ok, result, "phase")
		end
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls2 ~= expectedRuns2 then
		table.insert(
			violations,
			`AC-6: the second handler ran {#calls2} time(s) over {#sequence2} calls; {expectedRuns2} `
				.. `were in phase`
		)
	end

	check(
		#violations == 0,
		`AC-6: {#violations} violation(s) across {#sequence + #sequence2} calls - an implementation that `
			.. `captures the phase when the remote is guarded fails here:\n{indent(
				table.concat(violations, "\n")
			)}`
	)
end

--[[ ------------------------------------------------------------------------
     The Contract's own promises about a phase rejection
     ------------------------------------------------------------------------ ]]

--[[
	Contract, "`detail` for a phase rejection": both halves are recoverable -
	the phase that was current and EVERY phase that was legal - and there is
	no `"phase: "` prefix, because `reason` already says which check fired.
	The two phases that are neither current nor legal must be ABSENT, or
	"contains Round" would be satisfied by a detail that lists all five.
]]
function PhaseContract.phaseRejectionDetailNamesTheCurrentAndEveryLegalPhase(net: Net)
	local legal = { "Round", "Post" }
	local current = "Lobby"
	local definition = PhaseContract.remote(net, "detail", legal)
	local handler = NetContract.recorder()
	local guarded = net.Wrapper.guard(definition, PhaseContract.world({ "p1" }, current), handler)

	local ok, result = call(guarded, "p1", VALID)
	local rejected = expectRejection(
		"detail",
		"a valid call in Lobby against { Round, Post }",
		ok,
		result,
		"phase"
	)
	check(rejected == nil, rejected or "")
	local detail = result.detail
	check(
		typeof(detail) == "string" and detail ~= "",
		`detail: the phase rejection's detail is {Deep.show(detail)}; must be a non-empty string`
	)

	local violations: { string } = {}
	if string.match(detail, "^phase:") ~= nil then
		table.insert(
			violations,
			`detail leads with "phase:", a second encoding of reason that a refactor could let drift: `
				.. `"{detail}"`
		)
	end
	if string.find(detail, current, 1, true) == nil then
		table.insert(violations, `detail does not name the current phase {current}: "{detail}"`)
	end
	for _, phase in legal do
		if string.find(detail, phase, 1, true) == nil then
			table.insert(violations, `detail does not name the legal phase {phase}: "{detail}"`)
		end
	end
	for _, phase in PhaseContract.phasesExcept({ current, "Round", "Post" }) do
		if string.find(detail, phase, 1, true) ~= nil then
			table.insert(
				violations,
				`detail names {phase}, which is neither the current phase nor a legal one - the two `
					.. `halves are not recoverable from a detail that lists every phase: "{detail}"`
			)
		end
	end
	check(
		#violations == 0,
		`the phase rejection's detail failed in {#violations} way(s):\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

--[[
	Contract: "first failure wins and short-circuits" - the phase check is
	position 4, so `context.phase()` is not consulted when identity, shape or
	range has already fired, and is consulted for a call that reaches it.
]]
function PhaseContract.phaseIsNotConsultedWhenAnEarlierCheckFails(net: Net)
	local definition = PhaseContract.remote(net, "shortcircuit", { "Round" })
	local handler, calls = NetContract.recorder()
	local context, world = PhaseContract.world({ "p1" }, "Lobby")
	local guarded = net.Wrapper.guard(definition, context, handler)

	local cases: { { label: string, playerId: any, args: any, expected: string, reads: boolean } } =
		{
			{
				label = "an unseated caller (identity)",
				playerId = "p2",
				args = VALID,
				expected = "identity",
				reads = false,
			},
			{
				label = "a malformed payload (shape)",
				playerId = "p1",
				args = {},
				expected = "shape",
				reads = false,
			},
			{
				label = "an out-of-range payload (range)",
				playerId = "p1",
				args = { token = 99, flag = true },
				expected = "range",
				reads = false,
			},
			{
				label = "a valid payload out of phase (phase)",
				playerId = "p1",
				args = VALID,
				expected = "phase",
				reads = true,
			},
		}

	local violations: { string } = {}
	for _, case in cases do
		local before = world.reads
		local ok, result = call(guarded, case.playerId, case.args)
		local violation = expectRejection("short-circuit", case.label, ok, result, case.expected)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
		local reads = world.reads - before
		if case.reads and reads == 0 then
			table.insert(
				violations,
				`short-circuit: {case.label} -> context.phase() was not consulted, yet the call was `
					.. `judged on its phase`
			)
		elseif not case.reads and reads > 0 then
			table.insert(
				violations,
				`short-circuit: {case.label} -> context.phase() was consulted {reads} time(s); an `
					.. `earlier check fails first and nothing after it runs`
			)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`short-circuit: the handler ran {#calls} time(s); every case is a rejection`
		)
	end
	check(
		#violations == 0,
		`short-circuit: {#violations} violation(s) across {#cases} calls:\n{indent(
			table.concat(violations, "\n")
		)}`
	)
end

return PhaseContract
