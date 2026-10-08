--!strict
--[[
	CHAN-006 AC-1 .. AC-6 and the Contract's C-2 (purity) and C-3 (`new`),
	written once as checks over a `Pings` MODULE handed in as a parameter -
	`{ new, accept, tick, onCommitted, shown, request, targetPosition }` -
	rather than over `src/server/channel/Pings.luau` by name.
	`tests/server/ping_lifecycle_test.luau` applies these to the real module;
	`tests/server/ping_lifecycle_controls_test.luau` applies them to
	`PingLifecycleStubs.luau`'s reference and to implementations with EXACTLY
	ONE defect each, so that in RED - where the five functions do not exist
	and every check against the real module stops at `need()` - every check
	here has still been EXECUTED and observed to refuse the implementation it
	exists to catch.

	THE ORACLE PARTITION (story `## Contract`). AC-2 is SETTLED: the duration
	is READ OUT of `tuning.channel.ping_display_seconds` (15 in
	`MechanicsTuning`; a substituted tuning says 4) and never re-derived here.
	Every other criterion is MECHANICAL: exact maps, exact lists, exact keys,
	exact order, exact counts, compared with `Deep.equal` so an extra key, a
	missing key or a wrong value is reported by name.

	TIMES ARE CHOSEN SO THE SUMS ARE EXACT IN BINARY (C-5): `at = 10`, so the
	boundary is exactly `25` for the module's 15 and exactly `14` for the
	substituted 4. `EPSILON = 1e-6` is AC-2's epsilon.

	THE ACTIVE SET IS KEYED BY `senderId` (C-4), and the checks compare the
	whole `active` map against an expected map, so an implementation keyed
	any other way fails every check that reads the set. That is deliberate:
	the key is the mechanism that makes "one per player" structural.

	POSITIONS ARE LITERALS here; nothing lifecycle-side computes one. The one
	check that drives `request` (AC-5's refusal clause) uses `PingsContract`'s
	hand-built facility and its independent position oracle.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PingsContract = require("./PingsContract")

local PingLifecycleContract = {}

export type Vec = { x: number, y: number, z: number }
export type Pings = any

PingLifecycleContract.AT = 10
PingLifecycleContract.EPSILON = 1e-6
PingLifecycleContract.SUBSTITUTED_DISPLAY_SECONDS = 4

-- The substituted tuning (C-1): the live tuning with one channel value changed.
function PingLifecycleContract.substitutedTuning(): any
	return PingsContract.tuningWith({
		ping_display_seconds = PingLifecycleContract.SUBSTITUTED_DISPLAY_SECONDS,
	})
end

-- Literal positions: nothing here depends on where a target really is.
PingLifecycleContract.POS_M1 = { x = -16, y = 0, z = -16 }
PingLifecycleContract.POS_M2 = { x = 16, y = 0, z = 16 }
PingLifecycleContract.POS_D1 = { x = 32, y = 0, z = 0 }
PingLifecycleContract.POS_D2 = { x = 0, y = 0, z = 32 }

local AT = PingLifecycleContract.AT
local EPSILON = PingLifecycleContract.EPSILON
local POS_M1 = PingLifecycleContract.POS_M1
local POS_M2 = PingLifecycleContract.POS_M2
local POS_D1 = PingLifecycleContract.POS_D1
local POS_D2 = PingLifecycleContract.POS_D2

local machine = PingsContract.machine
local setting = PingsContract.setting
local doorway = PingsContract.doorway

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

local function need(criterion: string, P: Pings, name: string)
	if typeof(P) ~= "table" then
		Contract.fail(`{criterion}: Pings is {Deep.show(P)}, expected the module table`)
	end
	if typeof(P[name]) ~= "function" then
		Contract.fail(`{criterion}: Pings.{name} is {typeof(P[name])}, expected a function`)
	end
end

local function finish(criterion: string, violations: { string }, summary: string)
	if #violations > 0 then
		Contract.fail(
			`{criterion}: {#violations} violation(s) for {summary}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- A call under pcall; a raise is reported as a violation, never as the end
-- of the check.
local function call(P: Pings, name: string, ...: any): (boolean, any)
	return pcall(P[name], ...)
end

local function count(map: any): number
	local n = 0
	for _ in pairs(map) do
		n += 1
	end
	return n
end

-- The ActivePing the Contract says `accept` stores (C-4).
local function activeEntry(senderId: string, target: any, at: number): any
	return {
		senderId = senderId,
		kind = target.kind,
		target = target.target,
		setting = target.setting,
		at = at,
	}
end

-- The PingLogEntry the Contract says `accept` appends (C-4).
local function logEntry(
	senderId: string,
	target: any,
	position: Vec,
	at: number,
	roomLit: boolean
): any
	return {
		senderId = senderId,
		kind = target.kind,
		target = target.target,
		setting = target.setting,
		position = { x = position.x, y = position.y, z = position.z },
		at = at,
		roomLit = if target.kind == "doorway" then true else roomLit,
	}
end

-- `accept` with a raise turned into a violation and a nil state after it.
local function accept(
	criterion: string,
	violations: { string },
	P: Pings,
	state: any,
	senderId: string,
	target: any,
	position: Vec,
	now: number,
	roomLit: boolean
): any
	local ok, result = call(P, "accept", state, senderId, target, position, now, roomLit)
	if not ok then
		table.insert(
			violations,
			`{criterion}: accept({senderId}, {Deep.show(target)}, at {now}) RAISED: {tostring(
				result
			)}`
		)
		return nil
	end
	if
		typeof(result) ~= "table"
		or typeof(result.active) ~= "table"
		or typeof(result.log) ~= "table"
	then
		table.insert(
			violations,
			`{criterion}: accept({senderId}, {Deep.show(target)}, at {now}) returned {Deep.show(
				result
			)}, expected a PingState with active and log tables`
		)
		return nil
	end
	return result
end

local function expectActive(
	criterion: string,
	violations: { string },
	label: string,
	state: any,
	expected: { [string]: any }
)
	if state == nil then
		return
	end
	if not Deep.equal(expected, state.active) then
		table.insert(
			violations,
			`{criterion}: {label} -> the active set holds {count(state.active)} ping(s), expected exactly {count(
				expected
			)}:\n{indent(Deep.diff(expected, state.active))}`
		)
	end
end

local function expectLog(
	criterion: string,
	violations: { string },
	label: string,
	state: any,
	expected: { any }
)
	if state == nil then
		return
	end
	if not Deep.equal(expected, state.log) then
		table.insert(
			violations,
			`{criterion}: {label} -> the log holds {#state.log} entries, expected exactly {#expected}, in order:\n{indent(
				Deep.diff(expected, state.log)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     C-3: new().
     --------------------------------------------------------------------- ]]

-- `new()` is `{ active = {}, log = {} }`, nothing else in it, fresh every call.
function PingLifecycleContract.newReturnsAnEmptyStateFreshEachCall(P: Pings)
	need("C-3", P, "new")
	local violations: { string } = {}
	local ok, first = call(P, "new")
	if not ok then
		Contract.fail(`C-3: new() RAISED: {tostring(first)}`)
	end
	if not Deep.equal({ active = {}, log = {} }, first) then
		table.insert(
			violations,
			`C-3: new() returned {Deep.show(first)}, expected exactly \{ active = \{}, log = \{} }:\n{indent(
				Deep.diff({ active = {}, log = {} }, first)
			)}`
		)
	end
	local _, second = call(P, "new")
	if rawequal(first, second) then
		table.insert(
			violations,
			"C-3: new() returned the same table twice; expected a fresh state each call"
		)
	elseif typeof(first) == "table" and typeof(second) == "table" then
		if rawequal(first.active, second.active) then
			table.insert(violations, "C-3: two new() states share one active map")
		end
		if rawequal(first.log, second.log) then
			table.insert(violations, "C-3: two new() states share one log")
		end
	end
	finish("C-3", violations, "new()")
end

--[[ ------------------------------------------------------------------------
     AC-1: one active ping per sender; a new one replaces the old one now.
     --------------------------------------------------------------------- ]]

--[[
	kim pings machine 1 at 10, then doorway 1 at 12, then a setting at 13: after
	each accepted ping the active set holds EXACTLY ONE entry for kim - the
	newest, with exactly { senderId, kind, target, setting?, at = now }. The
	old one is gone at once (not at 25, when it would have expired): a tick at
	24 still shows only the newest.
]]
function PingLifecycleContract.aSecondPingBySameSenderReplacesTheFirstAtOnce(P: Pings)
	need("AC-1", P, "new")
	need("AC-1", P, "accept")
	need("AC-1", P, "tick")
	local violations: { string } = {}
	local s0 = P.new()
	local s1 = accept("AC-1", violations, P, s0, "kim", machine(1), POS_M1, AT, false)
	expectActive("AC-1", violations, "after kim's first ping (machine 1 at 10)", s1, {
		kim = activeEntry("kim", machine(1), AT),
	})
	if s1 == nil then
		finish("AC-1", violations, "replacement")
		return
	end
	local s2 = accept("AC-1", violations, P, s1, "kim", doorway(1), POS_D1, AT + 2, false)
	expectActive("AC-1", violations, "after kim's second ping (doorway 1 at 12)", s2, {
		kim = activeEntry("kim", doorway(1), AT + 2),
	})
	if s2 == nil then
		finish("AC-1", violations, "replacement")
		return
	end
	local s3 = accept("AC-1", violations, P, s2, "kim", setting(2, 3), POS_M2, AT + 3, true)
	expectActive("AC-1", violations, "after kim's third ping (setting 3 on machine 2 at 13)", s3, {
		kim = activeEntry("kim", setting(2, 3), AT + 3),
	})
	if s3 ~= nil then
		-- Gone NOW, not expired later: before the first ping's own expiry
		-- (10 + 15 = 25) a tick still shows only the newest.
		local ok, ticked = call(P, "tick", s3, AT + 14, MechanicsTuning)
		if not ok then
			table.insert(violations, `AC-1: tick at 24 RAISED: {tostring(ticked)}`)
		else
			expectActive(
				"AC-1",
				violations,
				"after a tick at 24, before the first ping would have expired",
				ticked,
				{
					kim = activeEntry("kim", setting(2, 3), AT + 3),
				}
			)
		end
	end
	-- A second sender is not affected by kim's replacements.
	if s3 ~= nil then
		local s4 = accept("AC-1", violations, P, s3, "lee", machine(1), POS_M1, AT + 4, false)
		local s5 = accept("AC-1", violations, P, s4, "kim", machine(1), POS_M1, AT + 5, false)
		expectActive("AC-1", violations, "after lee pings and kim replaces again", s5, {
			kim = activeEntry("kim", machine(1), AT + 5),
			lee = activeEntry("lee", machine(1), AT + 4),
		})
	end
	finish("AC-1", violations, "replacement")
end

--[[ ------------------------------------------------------------------------
     AC-2: a ping lasts ping_display_seconds, half-open (C-5).
     --------------------------------------------------------------------- ]]

--[[
	For the module's tuning (15) AND a substituted one (4): a ping made at 10
	is active at 10, at 10 + d - 1e-6, and gone at exactly 10 + d and after.
	Two pings made at different times expire independently. `tick` never
	touches the log. The duration is read out of the tuning handed in.
]]
function PingLifecycleContract.aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade(P: Pings)
	need("AC-2", P, "new")
	need("AC-2", P, "accept")
	need("AC-2", P, "tick")
	local violations: { string } = {}
	local tunings: { { label: string, tuning: any } } = {
		{ label = "the module's tuning", tuning = MechanicsTuning },
		{ label = "a substituted tuning", tuning = PingLifecycleContract.substitutedTuning() },
	}
	for _, t in tunings do
		local d = t.tuning.channel.ping_display_seconds
		local s1 = accept("AC-2", violations, P, P.new(), "kim", machine(1), POS_M1, AT, false)
		if s1 == nil then
			break
		end
		local present = { kim = activeEntry("kim", machine(1), AT) }
		local cases: { { now: number, label: string, expected: any } } = {
			{ now = AT, label = `at the moment it was made (now = {AT})`, expected = present },
			{
				now = AT + d - EPSILON,
				label = `just before expiry (now = {AT} + {d} - 1e-6)`,
				expected = present,
			},
			{ now = AT + d, label = `gone at exactly {AT} + {d} = {AT + d}`, expected = {} },
			{ now = AT + d + 1, label = `gone after expiry (now = {AT + d + 1})`, expected = {} },
		}
		for _, case in cases do
			local ok, ticked = call(P, "tick", s1, case.now, t.tuning)
			if not ok then
				table.insert(
					violations,
					`AC-2 ({t.label}, d = {d}): tick at {case.now} RAISED: {tostring(ticked)}`
				)
			else
				expectActive(
					"AC-2",
					violations,
					`{t.label} (d = {d}), {case.label}`,
					ticked,
					case.expected
				)
				if ticked ~= nil and not Deep.equal(s1.log, ticked.log) then
					table.insert(
						violations,
						`AC-2 ({t.label}, d = {d}): tick at {case.now} changed the log:\n{indent(
							Deep.diff(s1.log, ticked.log)
						)}`
					)
				end
			end
		end
		-- Independent expiry: lee's ping at 10 + d/2 outlives kim's.
		local s2 = accept("AC-2", violations, P, s1, "lee", doorway(2), POS_D2, AT + d / 2, false)
		if s2 ~= nil then
			local ok, ticked = call(P, "tick", s2, AT + d, t.tuning)
			if ok then
				expectActive(
					"AC-2",
					violations,
					`{t.label} (d = {d}), at {AT + d} kim's ping is gone and lee's (made at {AT + d / 2}) stays`,
					ticked,
					{
						lee = activeEntry("lee", doorway(2), AT + d / 2),
					}
				)
			end
		end
	end
	-- An empty state ticks to an empty state.
	local ok, ticked = call(P, "tick", P.new(), AT + 100, MechanicsTuning)
	if ok then
		expectActive("AC-2", violations, "an empty state ticked", ticked, {})
	end
	finish("AC-2", violations, "expiry at ping_display_seconds")
end

--[[ ------------------------------------------------------------------------
     AC-3: a commit clears the pings on that machine, and nothing else (C-6).
     --------------------------------------------------------------------- ]]

local function fiveSenders(criterion: string, violations: { string }, P: Pings): any
	local s = P.new()
	s = accept(criterion, violations, P, s, "kim", setting(1, 2), POS_M1, AT, false)
	s = s and accept(criterion, violations, P, s, "lee", machine(1), POS_M1, AT + 1, false)
	s = s and accept(criterion, violations, P, s, "pat", machine(2), POS_M2, AT + 2, true)
	s = s and accept(criterion, violations, P, s, "ann", doorway(1), POS_D1, AT + 3, false)
	s = s and accept(criterion, violations, P, s, "bob", setting(2, 4), POS_M2, AT + 4, true)
	return s
end

local function fiveActive(): { [string]: any }
	return {
		kim = activeEntry("kim", setting(1, 2), AT),
		lee = activeEntry("lee", machine(1), AT + 1),
		pat = activeEntry("pat", machine(2), AT + 2),
		ann = activeEntry("ann", doorway(1), AT + 3),
		bob = activeEntry("bob", setting(2, 4), AT + 4),
	}
end

--[[
	Five pings: a setting and a machine ping on machine 1, a machine and a
	setting ping on machine 2, and a DOORWAY ping whose id is numerically 1.
	Committing machine 1 clears exactly kim's and lee's; the doorway ping with
	the same number survives (C-6), as do both pings on machine 2. Committing
	a machine nobody pinged clears nothing. The log is untouched.
]]
function PingLifecycleContract.aCommitClearsSettingAndMachinePingsOnThatMachineOnly(P: Pings)
	need("AC-3", P, "new")
	need("AC-3", P, "accept")
	need("AC-3", P, "onCommitted")
	local violations: { string } = {}
	local s = fiveSenders("AC-3", violations, P)
	if s == nil then
		finish("AC-3", violations, "commit clears")
		return
	end
	expectActive("AC-3", violations, "the five pings before any commit", s, fiveActive())
	local cases: { { machine: number, label: string, expected: { [string]: any } } } = {
		{
			machine = 1,
			label = "machine 1 commits: kim's setting and lee's machine ping go; ann's doorway 1 (the same number, a doorway) and both pings on machine 2 stay",
			expected = {
				pat = activeEntry("pat", machine(2), AT + 2),
				ann = activeEntry("ann", doorway(1), AT + 3),
				bob = activeEntry("bob", setting(2, 4), AT + 4),
			},
		},
		{
			machine = 2,
			label = "machine 2 commits: pat's machine and bob's setting ping go; everything on machine 1 and the doorway stay",
			expected = {
				kim = activeEntry("kim", setting(1, 2), AT),
				lee = activeEntry("lee", machine(1), AT + 1),
				ann = activeEntry("ann", doorway(1), AT + 3),
			},
		},
		{
			machine = 7,
			label = "machine 7, which nobody pinged, commits: nothing changes",
			expected = fiveActive(),
		},
	}
	for _, case in cases do
		local ok, after = call(P, "onCommitted", s, case.machine)
		if not ok then
			table.insert(violations, `AC-3: onCommitted({case.machine}) RAISED: {tostring(after)}`)
		else
			expectActive("AC-3", violations, case.label, after, case.expected)
			if after ~= nil and not Deep.equal(s.log, after.log) then
				table.insert(
					violations,
					`AC-3: onCommitted({case.machine}) changed the log:\n{indent(
						Deep.diff(s.log, after.log)
					)}`
				)
			end
		end
	end
	finish("AC-3", violations, "commit clears")
end

--[[ ------------------------------------------------------------------------
     AC-4: two senders on one target both show, each with its sender.
     --------------------------------------------------------------------- ]]

function PingLifecycleContract.twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender(P: Pings)
	need("AC-4", P, "new")
	need("AC-4", P, "accept")
	need("AC-4", P, "shown")
	local violations: { string } = {}
	local s = P.new()
	s = accept("AC-4", violations, P, s, "kim", machine(1), POS_M1, AT, false)
	s = s and accept("AC-4", violations, P, s, "lee", machine(1), POS_M1, AT + 1, false)
	expectActive("AC-4", violations, "kim and lee both ping machine 1", s, {
		kim = activeEntry("kim", machine(1), AT),
		lee = activeEntry("lee", machine(1), AT + 1),
	})
	s = s and accept("AC-4", violations, P, s, "pat", setting(1, 2), POS_M1, AT + 2, false)
	s = s and accept("AC-4", violations, P, s, "zoe", setting(1, 2), POS_M1, AT + 3, false)
	expectActive("AC-4", violations, "pat and zoe both ping setting 2 on machine 1 as well", s, {
		kim = activeEntry("kim", machine(1), AT),
		lee = activeEntry("lee", machine(1), AT + 1),
		pat = activeEntry("pat", setting(1, 2), AT + 2),
		zoe = activeEntry("zoe", setting(1, 2), AT + 3),
	})
	if s ~= nil then
		local ok, shown = call(P, "shown", s)
		if not ok then
			table.insert(violations, `AC-4: shown RAISED: {tostring(shown)}`)
		elseif typeof(shown) ~= "table" or #shown ~= 4 then
			table.insert(
				violations,
				`AC-4: shown returned {Deep.show(shown)}, expected four entries (two per target)`
			)
		end
	end
	finish("AC-4", violations, "two senders on one target")
end

--[[ ------------------------------------------------------------------------
     AC-5: the log.
     --------------------------------------------------------------------- ]]

--[[
	A sequence of accepted pings, a replacement, an expiry, a commit and a
	final ping: after EVERY step the log is exactly the accepted pings so far,
	in order, each `{ senderId, kind, target, setting?, position, at,
	roomLit }` - so a log trimmed at the replacement, at the tick or at the
	commit is reported at the step that trimmed it. `shown` leaves it alone.
]]
function PingLifecycleContract.theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved(
	P: Pings
)
	need("AC-5", P, "new")
	need("AC-5", P, "accept")
	need("AC-5", P, "tick")
	need("AC-5", P, "onCommitted")
	need("AC-5", P, "shown")
	local violations: { string } = {}
	local expected: { any } = {}
	local s = P.new()
	expectLog("AC-5", violations, "a new state", s, expected)

	local function ping(
		senderId: string,
		target: any,
		position: Vec,
		now: number,
		roomLit: boolean,
		label: string
	)
		if s == nil then
			return
		end
		s = accept("AC-5", violations, P, s, senderId, target, position, now, roomLit)
		table.insert(expected, logEntry(senderId, target, position, now, roomLit))
		expectLog("AC-5", violations, label, s, expected)
	end

	ping("kim", machine(1), POS_M1, AT, false, "after kim's machine ping (dark room)")
	ping("lee", setting(2, 3), POS_M2, AT + 1, true, "after lee's setting ping (lit room)")
	ping(
		"kim",
		doorway(1),
		POS_D1,
		AT + 2,
		false,
		"after kim REPLACES with a doorway ping - the first entry stays"
	)
	if s ~= nil then
		local ok, ticked = call(P, "tick", s, AT + 30, MechanicsTuning)
		if ok then
			s = ticked
			expectLog(
				"AC-5",
				violations,
				"after a tick at 40 expired everything - the log keeps all three",
				s,
				expected
			)
		else
			table.insert(violations, `AC-5: tick RAISED: {tostring(ticked)}`)
		end
	end
	ping("pat", machine(2), POS_M2, AT + 31, true, "after pat's machine ping")
	if s ~= nil then
		local ok, after = call(P, "onCommitted", s, 2)
		if ok then
			s = after
			expectLog(
				"AC-5",
				violations,
				"after machine 2 commits and clears pat's ping - the log keeps all four",
				s,
				expected
			)
		else
			table.insert(violations, `AC-5: onCommitted RAISED: {tostring(after)}`)
		end
	end
	ping("kim", machine(1), POS_M1, AT + 40, false, "after kim's third ping")
	if s ~= nil then
		local before = Deep.copy(s.log)
		local ok, err = call(P, "shown", s)
		if ok and not Deep.equal(before, s.log) then
			table.insert(
				violations,
				`AC-5: shown changed the log:\n{indent(Deep.diff(before, s.log))}`
			)
		elseif not ok then
			table.insert(violations, `AC-5: shown RAISED: {tostring(err)}`)
		end
	end
	finish("AC-5", violations, "the log over a sequence")
end

--[[
	`roomLit` is logged as given for a machine and a setting ping, and as
	`true` for a doorway ping whatever was passed (C-4).
]]
function PingLifecycleContract.aDoorwayPingAlwaysLogsRoomLitTrue(P: Pings)
	need("AC-5", P, "new")
	need("AC-5", P, "accept")
	local violations: { string } = {}
	local cases: { { target: any, position: Vec, given: boolean, expected: boolean } } = {
		{ target = doorway(1), position = POS_D1, given = false, expected = true },
		{ target = doorway(2), position = POS_D2, given = true, expected = true },
		{ target = machine(1), position = POS_M1, given = false, expected = false },
		{ target = machine(2), position = POS_M2, given = true, expected = true },
		{ target = setting(1, 2), position = POS_M1, given = false, expected = false },
		{ target = setting(2, 1), position = POS_M2, given = true, expected = true },
	}
	for _, case in cases do
		local s = accept(
			"AC-5",
			violations,
			P,
			P.new(),
			"kim",
			case.target,
			case.position,
			AT,
			case.given
		)
		if s ~= nil then
			local entry = s.log[1]
			local got = if typeof(entry) == "table" then entry.roomLit else nil
			if got ~= case.expected then
				table.insert(
					violations,
					`AC-5: a {case.target.kind} ping accepted with roomLit = {tostring(case.given)} logged roomLit = {Deep.show(
						got
					)}, expected {tostring(case.expected)}`
				)
			end
		end
	end
	finish("AC-5", violations, "roomLit in the log")
end

--[[
	AC-5's refusal clause (C-8). `request` is driven to each refusal beside a
	state and the state is unchanged; in a mixed sequence only the accepted
	calls reach `accept`, so the log holds exactly the accepted pings with the
	target's position - never a sender's.
]]
function PingLifecycleContract.aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog(P: Pings)
	need("AC-5", P, "new")
	need("AC-5", P, "accept")
	need("AC-5", P, "request")
	need("AC-5", P, "targetPosition")
	local violations: { string } = {}
	local procedure = PingsContract.procedure()
	local live = PingsContract.MACHINE_LIVE
	local committed = PingsContract.MACHINE_TO_COMMIT
	local absent = PingsContract.ABSENT_MACHINES[1]
	local positions: { [string]: Vec } = {
		kim = PingsContract.beside(procedure, machine(live)),
		lee = PingsContract.beside(procedure, machine(live)),
	}
	local steps: { { sender: string, target: any, refusal: string? } } = {
		{ sender = "kim", target = machine(live), refusal = nil },
		{ sender = "kim", target = machine(committed), refusal = "committed_machine" },
		{ sender = "lee", target = machine(absent), refusal = "no_such_target" },
		{ sender = "lee", target = setting(live, 2), refusal = nil },
		{ sender = "pat", target = machine(live), refusal = "no_position" },
		{ sender = "kim", target = setting(live), refusal = "setting_mismatch" },
		{ sender = "kim", target = setting(live, 1), refusal = nil },
	}
	local s = P.new()
	local expected: { any } = {}
	local now = AT
	for i, step in steps do
		now += 1
		local control = PingsContract.control()
		local snapshot = Deep.copy(s)
		local ok, result = call(
			P,
			"request",
			procedure,
			positions,
			step.sender,
			step.target,
			control,
			PingsContract.alwaysSeen
		)
		if not ok then
			table.insert(violations, `AC-5: step {i} request RAISED: {tostring(result)}`)
			break
		end
		if step.refusal ~= nil then
			if not Deep.equal({ reason = step.refusal }, result) then
				table.insert(
					violations,
					`AC-5: step {i} ({step.sender} -> {Deep.show(step.target)}) returned {Deep.show(
						result
					)}, expected the refusal {step.refusal}`
				)
			end
			if not Deep.equal(snapshot, s) then
				table.insert(
					violations,
					`AC-5: step {i}, a refused ping, changed the state:\n{indent(
						Deep.diff(snapshot, s)
					)}`
				)
			end
		else
			if result ~= nil then
				table.insert(
					violations,
					`AC-5: step {i} ({step.sender} -> {Deep.show(step.target)}) returned {Deep.show(
						result
					)}, expected acceptance (nil)`
				)
			end
			local position = P.targetPosition(procedure, step.target)
			local oracle = PingsContract.positionOf(procedure, step.target)
			s = accept("AC-5", violations, P, s, step.sender, step.target, position, now, true)
			table.insert(expected, logEntry(step.sender, step.target, oracle, now, true))
			if s == nil then
				break
			end
		end
	end
	expectLog("AC-5", violations, "after 7 requests of which 3 were accepted", s, expected)
	finish("AC-5", violations, "refused pings and the log")
end

--[[ ------------------------------------------------------------------------
     AC-6: shown.
     --------------------------------------------------------------------- ]]

--[[
	`shown` is exactly `{ senderId, kind, target, setting? }` per active ping,
	sorted ascending by senderId; `setting` only on a setting ping; nothing
	else - no `at`, no position, no expiry. An empty state shows `{}`. The
	list is fresh: not the active map, not the same list twice, and adding to
	it leaves the state alone.
]]
function PingLifecycleContract.shownIsExactlySenderKindTargetAndSettingSortedBySender(P: Pings)
	need("AC-6", P, "new")
	need("AC-6", P, "accept")
	need("AC-6", P, "shown")
	local violations: { string } = {}
	local ok, empty = call(P, "shown", P.new())
	if not ok then
		Contract.fail(`AC-6: shown(new()) RAISED: {tostring(empty)}`)
	end
	if not Deep.equal({}, empty) then
		table.insert(violations, `AC-6: shown(new()) is {Deep.show(empty)}, expected \{}`)
	end
	local s = P.new()
	s = accept("AC-6", violations, P, s, "zoe", setting(2, 3), POS_M2, AT, true)
	s = s and accept("AC-6", violations, P, s, "ann", machine(1), POS_M1, AT + 1, false)
	s = s and accept("AC-6", violations, P, s, "kim", doorway(2), POS_D2, AT + 2, false)
	s = s and accept("AC-6", violations, P, s, "lee", setting(1, 1), POS_M1, AT + 3, true)
	if s == nil then
		finish("AC-6", violations, "shown")
		return
	end
	local expected = {
		{ senderId = "ann", kind = "machine", target = 1 },
		{ senderId = "kim", kind = "doorway", target = 2 },
		{ senderId = "lee", kind = "setting", target = 1, setting = 1 },
		{ senderId = "zoe", kind = "setting", target = 2, setting = 3 },
	}
	local okShown, shown = call(P, "shown", s)
	if not okShown then
		Contract.fail(`AC-6: shown RAISED: {tostring(shown)}`)
	end
	if not Deep.equal(expected, shown) then
		table.insert(
			violations,
			`AC-6: shown is not exactly \{ senderId, kind, target, setting? } per ping sorted by senderId `
				.. `(an at, a position or an expiry is a leak):\n{indent(Deep.diff(expected, shown))}`
		)
	end
	if rawequal(shown, s.active) then
		table.insert(
			violations,
			"AC-6: shown returned the active map itself, expected a fresh list"
		)
	end
	local _, again = call(P, "shown", s)
	if rawequal(shown, again) then
		table.insert(
			violations,
			"AC-6: shown returned the same list twice, expected a fresh list each call"
		)
	end
	if typeof(shown) == "table" then
		local snapshot = Deep.copy(s)
		table.insert(shown, { senderId = "mallory", kind = "machine", target = 9 })
		if not Deep.equal(snapshot, s) then
			table.insert(
				violations,
				`AC-6: adding to the shown list changed the state:\n{indent(Deep.diff(snapshot, s))}`
			)
		end
	end
	finish("AC-6", violations, "shown")
end

--[[ ------------------------------------------------------------------------
     C-2: purity.
     --------------------------------------------------------------------- ]]

--[[
	Each of `accept`, `tick` and `onCommitted` returns a NEW state and leaves
	the one it was given - its active map, its log, and the arguments -
	deep-equal to a snapshot taken before the call. Checked on a call that
	changes something and on one that changes nothing.
]]
function PingLifecycleContract.acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput(
	P: Pings
)
	need("C-2", P, "new")
	need("C-2", P, "accept")
	need("C-2", P, "tick")
	need("C-2", P, "onCommitted")
	local violations: { string } = {}
	local base = fiveSenders("C-2", violations, P)
	if base == nil then
		finish("C-2", violations, "purity")
		return
	end
	local target = setting(1, 2)
	local position = { x = -16, y = 0, z = -16 }
	local ops: { { label: string, run: (any) -> any } } = {
		{
			label = "accept (a new sender)",
			run = function(s: any)
				return P.accept(s, "zoe", target, position, AT + 5, false)
			end,
		},
		{
			label = "accept (a replacement)",
			run = function(s: any)
				return P.accept(s, "kim", target, position, AT + 6, false)
			end,
		},
		{
			label = "tick (expiring everything)",
			run = function(s: any)
				return P.tick(s, AT + 100, MechanicsTuning)
			end,
		},
		{
			label = "tick (expiring nothing)",
			run = function(s: any)
				return P.tick(s, AT + 4, MechanicsTuning)
			end,
		},
		{
			label = "onCommitted (clearing two)",
			run = function(s: any)
				return P.onCommitted(s, 1)
			end,
		},
		{
			label = "onCommitted (clearing nothing)",
			run = function(s: any)
				return P.onCommitted(s, 7)
			end,
		},
	}
	for _, op in ops do
		local snapshot = Deep.copy(base)
		local targetSnapshot = Deep.copy(target)
		local positionSnapshot = Deep.copy(position)
		local ok, result = pcall(op.run, base)
		if not ok then
			table.insert(violations, `C-2: {op.label} RAISED: {tostring(result)}`)
		else
			if rawequal(result, base) then
				table.insert(
					violations,
					`C-2: {op.label} returned the state it was given, expected a new one`
				)
			end
			if not Deep.equal(snapshot, base) then
				table.insert(
					violations,
					`C-2: {op.label} mutated the state it was given:\n{indent(
						Deep.diff(snapshot, base)
					)}`
				)
			end
			if
				not Deep.equal(targetSnapshot, target) or not Deep.equal(positionSnapshot, position)
			then
				table.insert(
					violations,
					`C-2: {op.label} mutated the target or position it was given`
				)
			end
		end
	end
	finish("C-2", violations, "purity")
end

--[[ ------------------------------------------------------------------------
     The check table.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Pings) -> () }

PingLifecycleContract.CHECKS = {
	{
		name = "newReturnsAnEmptyStateFreshEachCall",
		ac = "C-3",
		run = PingLifecycleContract.newReturnsAnEmptyStateFreshEachCall,
	},
	{
		name = "aSecondPingBySameSenderReplacesTheFirstAtOnce",
		ac = "AC-1",
		run = PingLifecycleContract.aSecondPingBySameSenderReplacesTheFirstAtOnce,
	},
	{
		name = "aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade",
		ac = "AC-2",
		run = PingLifecycleContract.aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade,
	},
	{
		name = "aCommitClearsSettingAndMachinePingsOnThatMachineOnly",
		ac = "AC-3",
		run = PingLifecycleContract.aCommitClearsSettingAndMachinePingsOnThatMachineOnly,
	},
	{
		name = "twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender",
		ac = "AC-4",
		run = PingLifecycleContract.twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender,
	},
	{
		name = "theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved",
		ac = "AC-5",
		run = PingLifecycleContract.theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved,
	},
	{
		name = "aDoorwayPingAlwaysLogsRoomLitTrue",
		ac = "AC-5",
		run = PingLifecycleContract.aDoorwayPingAlwaysLogsRoomLitTrue,
	},
	{
		name = "aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog",
		ac = "AC-5",
		run = PingLifecycleContract.aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog,
	},
	{
		name = "shownIsExactlySenderKindTargetAndSettingSortedBySender",
		ac = "AC-6",
		run = PingLifecycleContract.shownIsExactlySenderKindTargetAndSettingSortedBySender,
	},
	{
		name = "acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput",
		ac = "C-2",
		run = PingLifecycleContract.acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput,
	},
} :: { Check }

-- Every check against `P`; the names and messages of those that raised.
function PingLifecycleContract.failures(P: Pings): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PingLifecycleContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PingLifecycleContract
