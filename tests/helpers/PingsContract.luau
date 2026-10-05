--!strict
--[[
	CHAN-005 AC-3, AC-4 and AC-5, written once as checks over a `Pings` MODULE
	handed in as a parameter - `{ validate, targetPosition, request }` - rather
	than over `src/server/channel/Pings.luau` by name. `tests/server/pings_test.luau`
	and `tests/net/ping_remote_test.luau` apply these to the real module;
	`tests/server/pings_controls_test.luau` and
	`tests/net/ping_remote_controls_test.luau` apply them to `PingsStubs.luau`'s
	reference and to implementations with EXACTLY ONE defect each, so that in
	RED - where the module does not exist and not one assertion in the real
	files has executed - every check here has still been EXECUTED and observed
	to refuse the implementation it exists to catch.

	EVERY CRITERION HERE IS MECHANICAL (story `## Contract`, "Oracle
	partition"): exact refusal reasons, exact call counts, exact arguments, and
	a range boundary pinned at exactly `ping_range_studs` (accepted) and
	`ping_range_studs + 0.01` (refused). Nothing is designed; it is read out of
	the Contract's check order, its positions clause and its `request` clause.

	THE FIXTURE IS HAND-BUILT with explicit room columns and rows, so every
	position below is a computed number (`pings_controls_test.luau` asserts
	them). Three rooms of a 2 x 2 grid, two doorways, four machines whose ids
	are NOT dense (1, 2, 5, 9 of `actuator_count` = 16) and are listed OUT of
	id order (2, 5, 1, 9): a validator indexing `machines[target]` finds the
	wrong machine or none, and 3 is an id the schema admits that no machine
	carries. Machine positions are read through the REAL `Machines.positionOf`
	(merged, GEN-002); the doorway midpoint is the Contract's formula, written
	here independently of anything in `src/`.

	THE STATE comes from the real `Procedure.start` (PROC-001), then has
	`committed` and `dark` written directly: `validate` reads both off the
	procedure and the Contract says a dark room is NOT a refusal (PO-5).
	Range is `procedure.tuning.channel.ping_range_studs` - one check hands in a
	tuning whose range differs from the module constant, so a validator that
	reads `MechanicsTuning` directly is caught.

	`lineOfSight` IS A SPY, as `LensViewContract.spy` is: a function of the two
	points that records every call. AC-5 is a call count and two arguments.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local DeclineContract = require("./DeclineContract")
local Deep = require("./Deep")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Procedure = require("../../src/server/procedure/Procedure")
local PingRemoteContract = require("./PingRemoteContract")
local RateContract = require("./RateContract")

local PingsContract = {}

export type Vec = { x: number, y: number, z: number }
export type Pings = any
export type Net = PingRemoteContract.Net
export type Tuning = typeof(MechanicsTuning)

PingsContract.REASONS = {
	"no_such_target",
	"committed_machine",
	"out_of_range",
	"out_of_sight",
	"setting_mismatch",
	"no_position",
}

PingsContract.NOW = 100
PingsContract.ROUND_SEED = 7
PingsContract.ROUND_SECONDS = 1000
PingsContract.SENDER = "kim"

-- Just past the inclusive boundary. Large enough that `sqrt(dx * dx)` is
-- unambiguously above the range, small enough to be "the boundary".
PingsContract.PAST = 0.01

--[[ ------------------------------------------------------------------------
     The fixture.
     --------------------------------------------------------------------- ]]

-- Room 1 at (column 1, row 1), room 2 at (2, 1), room 3 at (1, 2).
PingsContract.MACHINE_LIVE = 1 -- room 1, slot 1: live (first of track 1)
PingsContract.MACHINE_TO_COMMIT = 2 -- room 1, slot 4: the one committed by hand
PingsContract.MACHINE_FAR = 5 -- room 2, slot 1: a room away
PingsContract.MACHINE_DARK_NONLIVE = 9 -- room 3, slot 2: finale (not live), room darkened
PingsContract.ABSENT_MACHINES = { 3, 4, 16 } -- inside the schema's bound, no machine
PingsContract.DOORWAY_1_2 = 1 -- doors[1] = { a = 1, b = 2 }
PingsContract.DOORWAY_1_3 = 2 -- doors[2] = { a = 1, b = 3 }
PingsContract.ABSENT_DOORWAYS = { 3, 0, 12 } -- > #doors, 0, and the grid maximum
PingsContract.DARK_ROOM = 3

local FIXTURE_MACHINES = {
	{ id = 2, room = 1, slot = 4, keyClass = 2, tag = 1, requiredSetting = 3 },
	{ id = 5, room = 2, slot = 1, keyClass = 3, tag = 1, requiredSetting = 2 },
	{ id = 1, room = 1, slot = 1, keyClass = 1, tag = 1, requiredSetting = 1 },
	{ id = 9, room = 3, slot = 2, keyClass = 4, tag = 1, requiredSetting = 4 },
}

function PingsContract.facility(): any
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 1, row = 2 },
			},
			doors = { { a = 1, b = 2 }, { a = 1, b = 3 } },
			spawnRoom = 1,
		},
		placement = {
			machines = Deep.copy(FIXTURE_MACHINES),
			stepsPerClass = { [1] = 1, [2] = 1, [3] = 1, [4] = 1 },
		},
		steps = { tracks = { { 1, 5 }, { 2, 9 } }, finale = { 5, 9 } },
		spawnRoom = 1,
		par = 40,
		attempt = 1,
	}
end

-- A copy of the live tuning with `channel` keys overridden, frozen as the
-- module is. Typed `any` on the way in, as `LensViewContract.tuningWith` is.
function PingsContract.tuningWith(channelOverrides: { [string]: any }): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for key, value in pairs(channelOverrides) do
		fake.channel[key] = value
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

--[[
	A fresh procedure every call: `MACHINE_TO_COMMIT` committed, `DARK_ROOM`
	dark, nothing else touched. Fresh so a check that writes to one cannot
	leak into the next.
]]
function PingsContract.procedure(tuning: Tuning?): any
	local state: any = Procedure.start(
		PingsContract.facility(),
		PingsContract.NOW,
		(tuning or MechanicsTuning) :: any,
		PingsContract.ROUND_SEED,
		PingsContract.ROUND_SECONDS
	)
	state.committed[PingsContract.MACHINE_TO_COMMIT] = true
	state.dark[PingsContract.DARK_ROOM] = true
	return state
end

function PingsContract.range(procedure: any): number
	return procedure.tuning.channel.ping_range_studs
end

local function machineById(procedure: any, id: number): any
	for _, m in procedure.facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	error(`fixture: no machine {id}`)
end

-- The machine's world position through the real `Machines.positionOf`.
function PingsContract.machinePosition(procedure: any, id: number): Vec
	return Machines.positionOf(
		procedure.facility.layout,
		machineById(procedure, id),
		procedure.tuning
	)
end

-- The Contract's doorway position: the midpoint of its two rooms' centres,
-- a room's centre being `((column - 1) * pitch, 0, (row - 1) * pitch)`.
function PingsContract.doorwayPosition(procedure: any, id: number): Vec
	local layout = procedure.facility.layout
	local door = layout.doors[id]
	assert(door ~= nil, `fixture: no doorway {id}`)
	local pitch = procedure.tuning.instance.room_pitch_studs
	local function centre(roomId: number): Vec
		for _, room in layout.rooms do
			if room.id == roomId then
				return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
			end
		end
		error(`fixture: no room {roomId}`)
	end
	local a, b = centre(door.a), centre(door.b)
	return { x = (a.x + b.x) / 2, y = 0, z = (a.z + b.z) / 2 }
end

-- The position of any target the fixture knows, by the test's own oracle.
function PingsContract.positionOf(procedure: any, target: any): Vec
	if target.kind == "doorway" then
		return PingsContract.doorwayPosition(procedure, target.target)
	end
	return PingsContract.machinePosition(procedure, target.target)
end

function PingsContract.at(p: Vec, dx: number, dy: number, dz: number): Vec
	return { x = p.x + dx, y = p.y + dy, z = p.z + dz }
end

-- Target builders.
function PingsContract.machine(id: number): any
	return { kind = "machine", target = id }
end

function PingsContract.setting(id: number, setting: number?): any
	return { kind = "setting", target = id, setting = setting }
end

function PingsContract.doorway(id: number): any
	return { kind = "doorway", target = id }
end

-- Standing beside the target: half the range along x.
function PingsContract.beside(procedure: any, target: any): Vec
	return PingsContract.at(
		PingsContract.positionOf(procedure, target),
		PingsContract.range(procedure) / 2,
		0,
		0
	)
end

local function alwaysSeen(_from: Vec, _to: Vec): boolean
	return true
end
PingsContract.alwaysSeen = alwaysSeen

local function neverSeen(_from: Vec, _to: Vec): boolean
	return false
end
PingsContract.neverSeen = neverSeen

export type SpyRecord = { calls: { { from: any, to: any } } }

-- A line of sight answering `answer`, recording every call.
function PingsContract.spy(answer: boolean): ((Vec, Vec) -> boolean, SpyRecord)
	local record: SpyRecord = { calls = {} }
	local function los(from: Vec, to: Vec): boolean
		table.insert(record.calls, { from = from, to = to })
		return answer
	end
	return los, record
end

local function sameVec(a: any, b: Vec): boolean
	return typeof(a) == "table" and a.x == b.x and a.y == b.y and a.z == b.z
end

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

-- `validate` under pcall; a raise is a violation, not the end of the check.
local function validate(
	P: Pings,
	procedure: any,
	position: any,
	target: any,
	los: any
): (boolean, any, any)
	return pcall(P.validate, procedure, position, target, los)
end

local function expectAccepted(
	criterion: string,
	label: string,
	ok: boolean,
	accepted: any,
	reason: any
): string?
	if not ok then
		return `{criterion}: {label} -> validate RAISED: {tostring(accepted)}`
	end
	if accepted ~= true or reason ~= nil then
		return `{criterion}: {label} -> ({Deep.show(accepted)}, {Deep.show(reason)}), expected (true, nil)`
	end
	return nil
end

local function expectRefused(
	criterion: string,
	label: string,
	ok: boolean,
	accepted: any,
	reason: any,
	expected: string
): string?
	if not ok then
		return `{criterion}: {label} -> validate RAISED: {tostring(accepted)}`
	end
	if accepted ~= false or reason ~= expected then
		return `{criterion}: {label} -> ({Deep.show(accepted)}, {Deep.show(reason)}), expected (false, "{expected}")`
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     AC-3: accepted targets.
     --------------------------------------------------------------------- ]]

--[[
	A machine, a setting on it and a doorway, each in range and in sight, are
	accepted - including a machine in a DARK room and a machine that is not
	live (PO-5: neither is a ping refusal), a doorway judged from its midpoint,
	and a sender a full room pitch below the floor (y is ignored).
]]
function PingsContract.acceptsMachinesSettingsAndDoorwaysInRangeAndInSight(P: Pings)
	need("AC-3", P, "validate")
	local s = PingsContract.procedure()
	local r = PingsContract.range(s)
	local live = PingsContract.MACHINE_LIVE
	local dark = PingsContract.MACHINE_DARK_NONLIVE
	assert(s.dark[PingsContract.DARK_ROOM] == true, "fixture: room 3 is not dark")
	assert(not Procedure.isLive(s, dark), `fixture: machine {dark} is live`)
	assert(Procedure.isLive(s, live), `fixture: machine {live} is not live`)
	local cases: { { label: string, target: any, position: Vec } } = {
		{
			label = `the live machine {live}, standing half the range away`,
			target = PingsContract.machine(live),
			position = PingsContract.beside(s, PingsContract.machine(live)),
		},
		{
			label = `a setting on machine {live}`,
			target = PingsContract.setting(live, 2),
			position = PingsContract.beside(s, PingsContract.machine(live)),
		},
		{
			label = `machine {dark} in the dark room, not live (PO-5)`,
			target = PingsContract.machine(dark),
			position = PingsContract.beside(s, PingsContract.machine(dark)),
		},
		{
			label = `a setting on machine {dark} in the dark room`,
			target = PingsContract.setting(dark, 1),
			position = PingsContract.beside(s, PingsContract.machine(dark)),
		},
		{
			label = "doorway 1 (rooms 1-2), standing at its midpoint",
			target = PingsContract.doorway(PingsContract.DOORWAY_1_2),
			position = PingsContract.positionOf(
				s,
				PingsContract.doorway(PingsContract.DOORWAY_1_2)
			),
		},
		{
			label = "doorway 2 (rooms 1-3), half the range along z",
			target = PingsContract.doorway(PingsContract.DOORWAY_1_3),
			position = PingsContract.at(
				PingsContract.positionOf(s, PingsContract.doorway(PingsContract.DOORWAY_1_3)),
				0,
				0,
				r / 2
			),
		},
		{
			label = `machine {live} from a room pitch below the floor (y is ignored)`,
			target = PingsContract.machine(live),
			position = PingsContract.at(
				PingsContract.machinePosition(s, live),
				0,
				-s.tuning.instance.room_pitch_studs,
				0
			),
		},
	}
	local violations: { string } = {}
	for _, case in cases do
		local ok, accepted, reason = validate(P, s, case.position, case.target, alwaysSeen)
		local v = expectAccepted("AC-3", case.label, ok, accepted, reason)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end
	finish("AC-3", violations, "targets that must be accepted")
end

--[[ ------------------------------------------------------------------------
     AC-3: each refusal, distinctly.
     --------------------------------------------------------------------- ]]

type RefusalCase = { label: string, target: any, position: Vec?, los: any, expect: string }

function PingsContract.refusalCases(s: any): { RefusalCase }
	local live = PingsContract.MACHINE_LIVE
	local committed = PingsContract.MACHINE_TO_COMMIT
	local far = PingsContract.MACHINE_FAR
	local nearLive = PingsContract.beside(s, PingsContract.machine(live))
	local nearCommitted = PingsContract.beside(s, PingsContract.machine(committed))
	local nearDoorway =
		PingsContract.positionOf(s, PingsContract.doorway(PingsContract.DOORWAY_1_2))
	local cases: { RefusalCase } = {}
	for _, id in PingsContract.ABSENT_MACHINES do
		table.insert(cases, {
			label = `machine {id}, an id no machine carries`,
			target = PingsContract.machine(id),
			position = nearLive,
			los = alwaysSeen,
			expect = "no_such_target",
		})
	end
	table.insert(cases, {
		label = `a setting on machine {PingsContract.ABSENT_MACHINES[1]}, which does not exist`,
		target = PingsContract.setting(PingsContract.ABSENT_MACHINES[1], 1),
		position = nearLive,
		los = alwaysSeen,
		expect = "no_such_target",
	})
	for _, id in PingsContract.ABSENT_DOORWAYS do
		table.insert(cases, {
			label = `doorway {id} (the layout has {#s.facility.layout.doors} doors)`,
			target = PingsContract.doorway(id),
			position = nearDoorway,
			los = alwaysSeen,
			expect = "no_such_target",
		})
	end
	table.insert(cases, {
		label = `the committed machine {committed}`,
		target = PingsContract.machine(committed),
		position = nearCommitted,
		los = alwaysSeen,
		expect = "committed_machine",
	})
	table.insert(cases, {
		label = `a setting on the committed machine {committed}`,
		target = PingsContract.setting(committed, 1),
		position = nearCommitted,
		los = alwaysSeen,
		expect = "committed_machine",
	})
	table.insert(cases, {
		label = `machine {far}, a room away from a sender beside machine {live}`,
		target = PingsContract.machine(far),
		position = nearLive,
		los = alwaysSeen,
		expect = "out_of_range",
	})
	table.insert(cases, {
		label = `a setting on machine {far}, a room away`,
		target = PingsContract.setting(far, 2),
		position = nearLive,
		los = alwaysSeen,
		expect = "out_of_range",
	})
	table.insert(cases, {
		label = `doorway 2 from a sender at doorway 1's midpoint`,
		target = PingsContract.doorway(PingsContract.DOORWAY_1_3),
		position = nearDoorway,
		los = alwaysSeen,
		expect = "out_of_range",
	})
	table.insert(cases, {
		label = `machine {live}, in range, line of sight false`,
		target = PingsContract.machine(live),
		position = nearLive,
		los = neverSeen,
		expect = "out_of_sight",
	})
	table.insert(cases, {
		label = "doorway 1, at its midpoint, line of sight false",
		target = PingsContract.doorway(PingsContract.DOORWAY_1_2),
		position = nearDoorway,
		los = neverSeen,
		expect = "out_of_sight",
	})
	table.insert(cases, {
		label = `a setting kind on machine {live} with setting = nil`,
		target = PingsContract.setting(live, nil),
		position = nearLive,
		los = alwaysSeen,
		expect = "setting_mismatch",
	})
	table.insert(cases, {
		label = `a machine kind on machine {live} carrying setting = 2`,
		target = { kind = "machine", target = live, setting = 2 },
		position = nearLive,
		los = alwaysSeen,
		expect = "setting_mismatch",
	})
	table.insert(cases, {
		label = "a doorway kind carrying setting = 1",
		target = { kind = "doorway", target = PingsContract.DOORWAY_1_2, setting = 1 },
		position = nearDoorway,
		los = alwaysSeen,
		expect = "setting_mismatch",
	})
	table.insert(cases, {
		label = `machine {live} from a sender with no accepted position`,
		target = PingsContract.machine(live),
		position = nil,
		los = alwaysSeen,
		expect = "no_position",
	})
	table.insert(cases, {
		label = "doorway 1 from a sender with no accepted position",
		target = PingsContract.doorway(PingsContract.DOORWAY_1_2),
		position = nil,
		los = alwaysSeen,
		expect = "no_position",
	})
	return cases
end

function PingsContract.refusesEachReasonDistinctly(P: Pings)
	need("AC-3", P, "validate")
	local s = PingsContract.procedure()
	local violations: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, case in PingsContract.refusalCases(s) do
		seen[case.expect] = true
		local ok, accepted, reason = validate(P, s, case.position, case.target, case.los)
		local v = expectRefused("AC-3", case.label, ok, accepted, reason, case.expect)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end
	for _, reason in PingsContract.REASONS do
		if not seen[reason] then
			table.insert(violations, `fixture: no case drives {reason}`)
		end
	end
	finish("AC-3", violations, "the six refusal reasons")
end

--[[
	The Contract's check order, where two refusals apply at once: a setting
	kind with no setting on an ABSENT machine is `setting_mismatch` (1 before
	2); an absent id marked committed is `no_such_target` (2 before 3); a
	committed machine from NO position is `committed_machine` (3 before 4); a
	live machine from no position with a false line of sight is `no_position`
	(4 before 5 and 6); a far machine with a false line of sight is
	`out_of_range` (5 before 6).
]]
function PingsContract.firstFailureWinsInTheContractsOrder(P: Pings)
	need("AC-3", P, "validate")
	local s = PingsContract.procedure()
	local absent = PingsContract.ABSENT_MACHINES[1]
	s.committed[absent] = true
	local live = PingsContract.MACHINE_LIVE
	local nearLive = PingsContract.beside(s, PingsContract.machine(live))
	local cases: { RefusalCase } = {
		{
			label = `a setting kind with no setting on absent machine {absent}`,
			target = PingsContract.setting(absent, nil),
			position = nearLive,
			los = alwaysSeen,
			expect = "setting_mismatch",
		},
		{
			label = `absent machine {absent}, marked committed`,
			target = PingsContract.machine(absent),
			position = nearLive,
			los = alwaysSeen,
			expect = "no_such_target",
		},
		{
			label = `the committed machine {PingsContract.MACHINE_TO_COMMIT} from no position`,
			target = PingsContract.machine(PingsContract.MACHINE_TO_COMMIT),
			position = nil,
			los = neverSeen,
			expect = "committed_machine",
		},
		{
			label = `machine {live} from no position, line of sight false`,
			target = PingsContract.machine(live),
			position = nil,
			los = neverSeen,
			expect = "no_position",
		},
		{
			label = `machine {PingsContract.MACHINE_FAR} a room away, line of sight false`,
			target = PingsContract.machine(PingsContract.MACHINE_FAR),
			position = nearLive,
			los = neverSeen,
			expect = "out_of_range",
		},
	}
	local violations: { string } = {}
	for _, case in cases do
		local ok, accepted, reason = validate(P, s, case.position, case.target, case.los)
		local v = expectRefused("AC-3", case.label, ok, accepted, reason, case.expect)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end
	finish(
		"AC-3",
		violations,
		"the check order (setting, existence, committed, position, range, sight)"
	)
end

--[[ ------------------------------------------------------------------------
     AC-3: the range boundary (D-2).
     --------------------------------------------------------------------- ]]

type RangeCase = { label: string, target: any, position: Vec, accept: boolean }

local function boundaryCases(s: any, target: any, name: string): { RangeCase }
	local r = PingsContract.range(s)
	local past = PingsContract.PAST
	local p = PingsContract.positionOf(s, target)
	return {
		{
			label = `{name}: exactly {r} along +x`,
			target = target,
			position = PingsContract.at(p, r, 0, 0),
			accept = true,
		},
		{
			label = `{name}: exactly {r} along -z`,
			target = target,
			position = PingsContract.at(p, 0, 0, -r),
			accept = true,
		},
		{
			label = `{name}: exactly {r} along +x and 500 up (a 3-D distance fails here)`,
			target = target,
			position = PingsContract.at(p, r, 500, 0),
			accept = true,
		},
		{
			label = `{name}: exactly {r} along -x and 500 down`,
			target = target,
			position = PingsContract.at(p, -r, -500, 0),
			accept = true,
		},
		{
			label = `{name}: {r + past} along +x (just past the range)`,
			target = target,
			position = PingsContract.at(p, r + past, 0, 0),
			accept = false,
		},
		{
			label = `{name}: {r + past} along +z`,
			target = target,
			position = PingsContract.at(p, 0, 0, r + past),
			accept = false,
		},
		{
			label = `{name}: 0.8 x range along both axes (1.13 x range on the diagonal)`,
			target = target,
			position = PingsContract.at(p, 0.8 * r, 0, 0.8 * r),
			accept = false,
		},
	}
end

local function runRangeCases(P: Pings, s: any, cases: { RangeCase }, violations: { string })
	for _, case in cases do
		local ok, accepted, reason = validate(P, s, case.position, case.target, alwaysSeen)
		local v = if case.accept
			then expectAccepted("AC-3", case.label, ok, accepted, reason)
			else expectRefused("AC-3", case.label, ok, accepted, reason, "out_of_range")
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end
end

--[[
	Exactly `ping_range_studs` (horizontally) is accepted for a machine, a
	setting and a doorway, whatever `y` is; `ping_range_studs + PAST` is
	refused `out_of_range`. `<` instead of `<=` fails the exactly-R cases
	(D-2); a 3-D distance fails the y cases.
]]
function PingsContract.rangeIsHorizontalAndInclusiveAtPingRangeStuds(P: Pings)
	need("AC-3", P, "validate")
	local s = PingsContract.procedure()
	local violations: { string } = {}
	runRangeCases(
		P,
		s,
		boundaryCases(s, PingsContract.machine(PingsContract.MACHINE_LIVE), "machine"),
		violations
	)
	runRangeCases(
		P,
		s,
		boundaryCases(s, PingsContract.setting(PingsContract.MACHINE_LIVE, 1), "setting"),
		violations
	)
	runRangeCases(
		P,
		s,
		boundaryCases(s, PingsContract.doorway(PingsContract.DOORWAY_1_3), "doorway"),
		violations
	)
	finish(
		"AC-3",
		violations,
		`the inclusive horizontal range boundary at ping_range_studs = {PingsContract.range(s)}`
	)
end

-- A range that differs from the module constant, so `procedure.tuning` is the source.
PingsContract.FIXTURE_RANGE = 20

--[[
	Range is `procedure.tuning.channel.ping_range_studs`, not
	`MechanicsTuning`'s: with a tuning whose range is FIXTURE_RANGE, exactly
	FIXTURE_RANGE is accepted and FIXTURE_RANGE + PAST refused, and a stand at
	the module constant plus half a stud - inside the fixture's range, outside
	the module's - is accepted.
]]
function PingsContract.rangeIsReadFromTheProceduresTuning(P: Pings)
	need("AC-3", P, "validate")
	local moduleRange = MechanicsTuning.channel.ping_range_studs
	local fixtureRange = PingsContract.FIXTURE_RANGE
	assert(
		fixtureRange > moduleRange + 1,
		`fixture: FIXTURE_RANGE {fixtureRange} must exceed the module's {moduleRange} + 1`
	)
	local s = PingsContract.procedure(PingsContract.tuningWith({ ping_range_studs = fixtureRange }))
	assert(
		PingsContract.range(s) == fixtureRange,
		"fixture: the procedure's tuning does not carry FIXTURE_RANGE"
	)
	local target = PingsContract.machine(PingsContract.MACHINE_LIVE)
	local cases = boundaryCases(s, target, `machine under ping_range_studs = {fixtureRange}`)
	table.insert(cases, {
		label = `machine: {moduleRange + 0.5} along +x (outside the module's {moduleRange}, inside the procedure's {fixtureRange})`,
		target = target,
		position = PingsContract.at(PingsContract.positionOf(s, target), moduleRange + 0.5, 0, 0),
		accept = true,
	})
	local violations: { string } = {}
	runRangeCases(P, s, cases, violations)
	finish("AC-3", violations, `a procedure whose tuning fixes ping_range_studs = {fixtureRange}`)
end

--[[
	AC-3's named control. A payload crafted with a `position` field that IS in
	range, from a sender whose SERVER position is a room away: `out_of_range`.
	The schema rejects the extra field at `shape` on the wire, so this drives
	`validate` directly with the position argument the test controls, as the
	Contract says; a validator that reads the payload's position accepts here.
]]
function PingsContract.rangeIsMeasuredFromTheServersPositionNotAPayloadField(P: Pings)
	need("AC-3", P, "validate")
	local s = PingsContract.procedure()
	local live = PingsContract.MACHINE_LIVE
	local far = PingsContract.MACHINE_FAR
	local crafted = PingsContract.beside(s, PingsContract.machine(live))
	local server = PingsContract.beside(s, PingsContract.machine(far))
	local violations: { string } = {}
	local targets: { { label: string, target: any } } = {
		{
			label = `machine {live} with a crafted in-range position field`,
			target = { kind = "machine", target = live, position = crafted },
		},
		{
			label = `doorway 1 with a crafted position field at its midpoint`,
			target = {
				kind = "doorway",
				target = PingsContract.DOORWAY_1_2,
				position = PingsContract.positionOf(
					s,
					PingsContract.doorway(PingsContract.DOORWAY_1_2)
				),
			},
		},
	}
	for _, t in targets do
		local ok, accepted, reason = validate(P, s, server, t.target, alwaysSeen)
		local v = expectRefused(
			"AC-3 control",
			`{t.label}, server position beside machine {far}`,
			ok,
			accepted,
			reason,
			"out_of_range"
		)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
		-- And the same target from the server position that IS in range is
		-- accepted, so the field's presence is simply ignored, not refused.
		local ok2, accepted2, reason2 = validate(P, s, t.target.position, t.target, alwaysSeen)
		local v2 = expectAccepted(
			"AC-3 control",
			`{t.label}, server position in range`,
			ok2,
			accepted2,
			reason2
		)
		if v2 ~= nil then
			table.insert(violations, v2 :: string)
		end
	end
	finish(
		"AC-3 control",
		violations,
		"range measured from the server's accepted position, never from the payload"
	)
end

--[[ ------------------------------------------------------------------------
     AC-3: `targetPosition`.
     --------------------------------------------------------------------- ]]

function PingsContract.targetPositionIsPositionOfForMachinesAndTheMidpointForDoorways(P: Pings)
	need("AC-3", P, "targetPosition")
	local s = PingsContract.procedure()
	local violations: { string } = {}
	local function expectVec(label: string, target: any, want: Vec)
		local ok, got = pcall(P.targetPosition, s, target)
		if not ok then
			table.insert(violations, `{label} -> targetPosition RAISED: {tostring(got)}`)
		elseif not Deep.equal(got, want) then
			table.insert(violations, `{label} -> {Deep.show(got)}, expected {Deep.show(want)}`)
		end
	end
	local function expectNil(label: string, target: any)
		local ok, got = pcall(P.targetPosition, s, target)
		if not ok then
			table.insert(violations, `{label} -> targetPosition RAISED: {tostring(got)}`)
		elseif got ~= nil then
			table.insert(violations, `{label} -> {Deep.show(got)}, expected nil`)
		end
	end
	for _, id in
		{
			PingsContract.MACHINE_LIVE,
			PingsContract.MACHINE_TO_COMMIT,
			PingsContract.MACHINE_FAR,
			PingsContract.MACHINE_DARK_NONLIVE,
		}
	do
		local want = PingsContract.machinePosition(s, id)
		expectVec(`machine {id}`, PingsContract.machine(id), want)
		expectVec(`a setting on machine {id}`, PingsContract.setting(id, 1), want)
		expectVec(
			`a setting kind on machine {id} with setting = nil (setting is not looked at)`,
			PingsContract.setting(id, nil),
			want
		)
	end
	for _, id in { PingsContract.DOORWAY_1_2, PingsContract.DOORWAY_1_3 } do
		expectVec(`doorway {id}`, PingsContract.doorway(id), PingsContract.doorwayPosition(s, id))
	end
	for _, id in PingsContract.ABSENT_MACHINES do
		expectNil(`absent machine {id}`, PingsContract.machine(id))
		expectNil(`a setting on absent machine {id}`, PingsContract.setting(id, 1))
	end
	for _, id in PingsContract.ABSENT_DOORWAYS do
		expectNil(`absent doorway {id}`, PingsContract.doorway(id))
	end
	finish(
		"AC-3",
		violations,
		"targetPosition (Machines.positionOf for machines and settings, the rooms' midpoint for doorways, nil for no target)"
	)
end

--[[ ------------------------------------------------------------------------
     AC-5: the line-of-sight port.
     --------------------------------------------------------------------- ]]

--[[
	For a target that passes checks 1-5 the port is called EXACTLY once, with
	the sender's accepted position as `from` and the target's position as
	`to`; `true` accepts and `false` refuses `out_of_sight`. For a machine, a
	setting and a doorway.
]]
function PingsContract.lineOfSightIsAskedOnceFromTheSenderToTheTarget(P: Pings)
	need("AC-5", P, "validate")
	local s = PingsContract.procedure()
	local live = PingsContract.MACHINE_LIVE
	local targets: { { label: string, target: any } } = {
		{ label = `machine {live}`, target = PingsContract.machine(live) },
		{ label = `a setting on machine {live}`, target = PingsContract.setting(live, 3) },
		{ label = "doorway 2", target = PingsContract.doorway(PingsContract.DOORWAY_1_3) },
	}
	local violations: { string } = {}
	for _, t in targets do
		local position = PingsContract.at(PingsContract.positionOf(s, t.target), 3, 1, -4)
		local want = PingsContract.positionOf(s, t.target)
		for _, answer in { true, false } do
			local los, record = PingsContract.spy(answer)
			local label = `{t.label}, line of sight answering {answer}`
			local ok, accepted, reason = validate(P, s, position, t.target, los)
			local v = if answer
				then expectAccepted("AC-5", label, ok, accepted, reason)
				else expectRefused("AC-5", label, ok, accepted, reason, "out_of_sight")
			if v ~= nil then
				table.insert(violations, v :: string)
			end
			if #record.calls ~= 1 then
				table.insert(
					violations,
					`AC-5: {label} -> lineOfSight was called {#record.calls} time(s), expected exactly once`
				)
			end
			for i, c in record.calls do
				if not sameVec(c.from, position) then
					table.insert(
						violations,
						`AC-5: {label} -> call {i}'s from is {Deep.show(c.from)}, expected the sender's accepted position {Deep.show(
							position
						)}`
					)
				end
				if not sameVec(c.to, want) then
					table.insert(
						violations,
						`AC-5: {label} -> call {i}'s to is {Deep.show(c.to)}, expected the target's position {Deep.show(
							want
						)}`
					)
				end
			end
		end
	end
	finish("AC-5", violations, "the line-of-sight call for an otherwise-valid target")
end

--[[
	The port is NEVER called for a target that fails checks 1-5: one case per
	earlier reason, with a spy that would answer `true` - so a validator asking
	the port early is caught by the count, not by the verdict.
]]
function PingsContract.lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck(P: Pings)
	need("AC-5", P, "validate")
	local s = PingsContract.procedure()
	local live = PingsContract.MACHINE_LIVE
	local nearLive = PingsContract.beside(s, PingsContract.machine(live))
	local cases: { { label: string, target: any, position: Vec?, expect: string } } = {
		{
			label = "setting_mismatch (setting kind, no setting)",
			target = PingsContract.setting(live, nil),
			position = nearLive,
			expect = "setting_mismatch",
		},
		{
			label = "setting_mismatch (machine kind, setting given)",
			target = { kind = "machine", target = live, setting = 1 },
			position = nearLive,
			expect = "setting_mismatch",
		},
		{
			label = `no_such_target (machine {PingsContract.ABSENT_MACHINES[1]})`,
			target = PingsContract.machine(PingsContract.ABSENT_MACHINES[1]),
			position = nearLive,
			expect = "no_such_target",
		},
		{
			label = `no_such_target (doorway {PingsContract.ABSENT_DOORWAYS[1]})`,
			target = PingsContract.doorway(PingsContract.ABSENT_DOORWAYS[1]),
			position = nearLive,
			expect = "no_such_target",
		},
		{
			label = `committed_machine (machine {PingsContract.MACHINE_TO_COMMIT})`,
			target = PingsContract.machine(PingsContract.MACHINE_TO_COMMIT),
			position = PingsContract.beside(
				s,
				PingsContract.machine(PingsContract.MACHINE_TO_COMMIT)
			),
			expect = "committed_machine",
		},
		{
			label = "no_position",
			target = PingsContract.machine(live),
			position = nil,
			expect = "no_position",
		},
		{
			label = `out_of_range (machine {PingsContract.MACHINE_FAR} from beside machine {live})`,
			target = PingsContract.machine(PingsContract.MACHINE_FAR),
			position = nearLive,
			expect = "out_of_range",
		},
		{
			label = `out_of_range (machine {live} at range + {PingsContract.PAST})`,
			target = PingsContract.machine(live),
			position = PingsContract.at(
				PingsContract.machinePosition(s, live),
				PingsContract.range(s) + PingsContract.PAST,
				0,
				0
			),
			expect = "out_of_range",
		},
	}
	local violations: { string } = {}
	local total = 0
	for _, case in cases do
		local los, record = PingsContract.spy(true)
		local ok, accepted, reason = validate(P, s, case.position, case.target, los)
		local v = expectRefused("AC-5", case.label, ok, accepted, reason, case.expect)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
		total += #record.calls
		if #record.calls ~= 0 then
			table.insert(
				violations,
				`AC-5: {case.label} -> lineOfSight was called {#record.calls} time(s); it must not be consulted for a target that already failed`
			)
		end
	end
	finish(
		"AC-5",
		violations,
		`targets failing an earlier check ({total} line-of-sight calls across {#cases} cases, expected 0)`
	)
end

--[[ ------------------------------------------------------------------------
     AC-4: `request`.
     --------------------------------------------------------------------- ]]

-- A `CallControl` counting its declines.
function PingsContract.control(): (any, { declines: number })
	local count = { declines = 0 }
	local control = {
		decline = function()
			count.declines += 1
		end,
	}
	return control, count
end

local function request(
	P: Pings,
	procedure: any,
	positions: any,
	senderId: string,
	target: any,
	control: any,
	los: any
): (boolean, any)
	return pcall(P.request, procedure, positions, senderId, target, control, los)
end

-- Exactly `{ reason = <reason> }`: one key, that one.
local function expectRefusal(
	label: string,
	ok: boolean,
	result: any,
	reason: string,
	declines: number,
	violations: { string }
)
	if not ok then
		table.insert(violations, `{label} -> request RAISED: {tostring(result)}`)
		return
	end
	if not Deep.equal(result, { reason = reason }) then
		table.insert(
			violations,
			`{label} -> request returned {Deep.show(result)}, expected exactly \{ reason = "{reason}" }`
		)
	end
	if declines ~= 1 then
		table.insert(
			violations,
			`{label} -> call.decline() was called {declines} time(s), expected exactly once`
		)
	end
end

--[[
	Every refusal `validate` can produce, through `request`: the result is
	exactly `{ reason = <reason> }` and `call.decline()` ran exactly once.
	Plus `request`'s own two: `procedure == nil` is `no_such_target`, and a
	sender absent from `positions` is `no_position`.
]]
function PingsContract.requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal(P: Pings)
	need("AC-4", P, "request")
	local s = PingsContract.procedure()
	local sender = PingsContract.SENDER
	local violations: { string } = {}
	for _, case in PingsContract.refusalCases(s) do
		local positions: { [string]: Vec } = {}
		if case.position ~= nil then
			positions[sender] = case.position :: Vec
		end
		local control, count = PingsContract.control()
		local ok, result = request(P, s, positions, sender, case.target, control, case.los)
		expectRefusal(`AC-4: {case.label}`, ok, result, case.expect, count.declines, violations)
	end
	do
		local control, count = PingsContract.control()
		local positions = {
			[sender] = PingsContract.beside(s, PingsContract.machine(PingsContract.MACHINE_LIVE)),
		}
		local ok, result = request(
			P,
			nil,
			positions,
			sender,
			PingsContract.machine(PingsContract.MACHINE_LIVE),
			control,
			alwaysSeen
		)
		expectRefusal(
			"AC-4: procedure == nil",
			ok,
			result,
			"no_such_target",
			count.declines,
			violations
		)
	end
	do
		local control, count = PingsContract.control()
		local positions = {
			somebodyElse = PingsContract.beside(
				s,
				PingsContract.machine(PingsContract.MACHINE_LIVE)
			),
		}
		local ok, result = request(
			P,
			s,
			positions,
			sender,
			PingsContract.machine(PingsContract.MACHINE_LIVE),
			control,
			alwaysSeen
		)
		expectRefusal(
			"AC-4: positions[senderId] missing (another player's position present)",
			ok,
			result,
			"no_position",
			count.declines,
			violations
		)
	end
	finish(
		"AC-4",
		violations,
		"request on a refused ping (decline once, return exactly { reason })"
	)
end

--[[
	An accepted ping through `request` returns `nil` and never calls
	`decline`; `positions` and the target are read, not written.
]]
function PingsContract.requestAcceptsWithoutDeclining(P: Pings)
	need("AC-4", P, "request")
	local s = PingsContract.procedure()
	local sender = PingsContract.SENDER
	local live = PingsContract.MACHINE_LIVE
	local violations: { string } = {}
	local targets: { { label: string, target: any } } = {
		{ label = `machine {live}`, target = PingsContract.machine(live) },
		{ label = `a setting on machine {live}`, target = PingsContract.setting(live, 2) },
		{ label = "doorway 1", target = PingsContract.doorway(PingsContract.DOORWAY_1_2) },
		{
			label = `machine {PingsContract.MACHINE_DARK_NONLIVE} in the dark room`,
			target = PingsContract.machine(PingsContract.MACHINE_DARK_NONLIVE),
		},
	}
	for _, t in targets do
		local positions =
			{ [sender] = PingsContract.beside(s, t.target), other = { x = 1e6, y = 0, z = 1e6 } }
		local before = Deep.copy(positions)
		local targetBefore = Deep.copy(t.target)
		local control, count = PingsContract.control()
		local ok, result = request(P, s, positions, sender, t.target, control, alwaysSeen)
		if not ok then
			table.insert(violations, `AC-4: {t.label} -> request RAISED: {tostring(result)}`)
		elseif result ~= nil then
			table.insert(
				violations,
				`AC-4: {t.label} -> request returned {Deep.show(result)}, expected nil for an accepted ping`
			)
		end
		if count.declines ~= 0 then
			table.insert(
				violations,
				`AC-4: {t.label} -> call.decline() was called {count.declines} time(s) on an ACCEPTED ping; expected never`
			)
		end
		if not Deep.equal(positions, before) then
			table.insert(
				violations,
				`AC-4: {t.label} -> request wrote to positions: {Deep.diff(before, positions)}`
			)
		end
		if not Deep.equal(t.target, targetBefore) then
			table.insert(
				violations,
				`AC-4: {t.label} -> request wrote to the target: {Deep.diff(targetBefore, t.target)}`
			)
		end
	end
	finish("AC-4", violations, "request on an accepted ping (nil, undeclined)")
end

--[[
	AC-4 through the REAL guard. `definition` is the Ping declaration (the
	real one in `ping_remote_test`, a reference one in the controls), `P` the
	module. The handler is the two-line adapter `SLICE-007` will ship: build
	a `PingTarget` from the validated args, call `request` with the fixture
	procedure and positions, hand it the wrapper's `call`.

	  t                 : a refused target (an absent machine) -> the guard
	                      answers `declined`; `request` returned exactly
	                      `{ reason = "no_such_target" }`.
	  t + attempt + EPS : a valid target, past the attempt floor and well
	                      inside the send limit -> the guard answers nil, the
	                      handler ran, `request` returned nil.

	A handler whose refusal does NOT decline leaves the first call's
	acceptance in the send limiter, and the second call is `rate` (D-4).
]]
function PingsContract.refusedPingIsDeclinedAndTheNextValidPingInsideTheSendLimitIsAccepted(
	net: Net,
	definition: any,
	P: Pings
)
	need("AC-4", P, "request")
	assert(
		typeof(definition) == "table" and typeof(definition.name) == "string",
		"AC-4: the Ping definition is not a declaration"
	)
	local s = PingsContract.procedure()
	local sender = PingRemoteContract.CALLER
	local attempt = PingRemoteContract.attemptSeconds()
	local rate = PingRemoteContract.rateLimitSeconds()
	local eps = PingRemoteContract.EPSILON
	local start = PingRemoteContract.START
	local live = PingsContract.MACHINE_LIVE
	local absent = PingsContract.ABSENT_MACHINES[1]
	local positions = { [sender] = PingsContract.beside(s, PingsContract.machine(live)) }

	local results: { any } = {}
	local handlerRuns = 0
	local function handler(playerId: string, args: any, control: any)
		handlerRuns += 1
		local target = { kind = args.kind, target = args.target, setting = args.setting }
		results[handlerRuns] = P.request(s, positions, playerId, target, control, alwaysSeen)
	end
	local context, world = RateContract.world({ sender }, "Round", start)
	local guarded = net.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}

	world.clock:set(start)
	local ok1, r1 = pcall(guarded, sender, { kind = "machine", target = absent })
	if not ok1 then
		table.insert(violations, `AC-4: the refused ping at t RAISED: {tostring(r1)}`)
	else
		local want =
			{ reason = "declined", detail = DeclineContract.declinedDetail(definition.name) }
		if not Deep.equal(r1, want) then
			table.insert(
				violations,
				`AC-4: the refused ping at t -> the guard answered {Deep.show(r1)}, expected {Deep.show(
					want
				)}`
			)
		end
		if handlerRuns ~= 1 then
			table.insert(
				violations,
				`AC-4: after the refused ping the handler ran {handlerRuns} time(s), expected 1`
			)
		elseif not Deep.equal(results[1], { reason = "no_such_target" }) then
			table.insert(
				violations,
				`AC-4: the refused ping -> request returned {Deep.show(results[1])}, expected exactly \{ reason = "no_such_target" }`
			)
		end
	end

	world.clock:set(start + attempt + eps)
	local ok2, r2 = pcall(guarded, sender, { kind = "machine", target = live })
	if not ok2 then
		table.insert(
			violations,
			`AC-4: the valid ping at t + {attempt + eps} RAISED: {tostring(r2)}`
		)
	else
		if r2 ~= nil then
			table.insert(
				violations,
				`AC-4: the valid ping at t + {attempt + eps} (past the attempt floor {attempt}, inside the send limit {rate}) -> the guard answered {Deep.show(
					r2
				)}, expected nil (accepted)`
			)
		end
		if handlerRuns ~= 2 then
			table.insert(
				violations,
				`AC-4: after the valid ping the handler ran {handlerRuns} time(s) in total, expected 2`
			)
		elseif results[2] ~= nil then
			table.insert(
				violations,
				`AC-4: the valid ping -> request returned {Deep.show(results[2])}, expected nil`
			)
		end
	end
	finish(
		"AC-4",
		violations,
		"a refused ping followed by a valid one inside the send limit, through the guarded remote"
	)
end

--[[ ------------------------------------------------------------------------
     The batteries, named.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Pings) -> ...any }

PingsContract.CHECKS = {
	{
		name = "acceptsMachinesSettingsAndDoorwaysInRangeAndInSight",
		ac = "AC-3",
		run = PingsContract.acceptsMachinesSettingsAndDoorwaysInRangeAndInSight,
	},
	{
		name = "refusesEachReasonDistinctly",
		ac = "AC-3",
		run = PingsContract.refusesEachReasonDistinctly,
	},
	{
		name = "firstFailureWinsInTheContractsOrder",
		ac = "AC-3",
		run = PingsContract.firstFailureWinsInTheContractsOrder,
	},
	{
		name = "rangeIsHorizontalAndInclusiveAtPingRangeStuds",
		ac = "AC-3",
		run = PingsContract.rangeIsHorizontalAndInclusiveAtPingRangeStuds,
	},
	{
		name = "rangeIsReadFromTheProceduresTuning",
		ac = "AC-3",
		run = PingsContract.rangeIsReadFromTheProceduresTuning,
	},
	{
		name = "rangeIsMeasuredFromTheServersPositionNotAPayloadField",
		ac = "AC-3 control",
		run = PingsContract.rangeIsMeasuredFromTheServersPositionNotAPayloadField,
	},
	{
		name = "targetPositionIsPositionOfForMachinesAndTheMidpointForDoorways",
		ac = "AC-3",
		run = PingsContract.targetPositionIsPositionOfForMachinesAndTheMidpointForDoorways,
	},
	{
		name = "lineOfSightIsAskedOnceFromTheSenderToTheTarget",
		ac = "AC-5",
		run = PingsContract.lineOfSightIsAskedOnceFromTheSenderToTheTarget,
	},
	{
		name = "lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck",
		ac = "AC-5",
		run = PingsContract.lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck,
	},
	{
		name = "requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal",
		ac = "AC-4",
		run = PingsContract.requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal,
	},
	{
		name = "requestAcceptsWithoutDeclining",
		ac = "AC-4",
		run = PingsContract.requestAcceptsWithoutDeclining,
	},
} :: { Check }

-- Every module-level check against `P`; the names of those that raised.
function PingsContract.failures(P: Pings): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PingsContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PingsContract
