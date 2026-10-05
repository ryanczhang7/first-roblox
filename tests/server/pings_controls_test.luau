--!strict
--[[
	The negative controls for CHAN-005 AC-3, AC-4 and AC-5, and the proof that
	each check in `tests/helpers/PingsContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/channel/Pings.luau` does not exist, every test in
	`tests/server/pings_test.luau` fails before its assertion runs, and so not
	one of that file's checks has been observed to accept or refuse anything.
	`PingsStubs.luau` needs only `Machines` and `MechanicsTuning`, which are
	merged, so what is asserted here is MEASURED in RED rather than claimed
	for GREEN. The story's handoff carries the table.

	THE REFERENCE is the Contract written out. Every check must ACCEPT it, or
	the check is wrong and the fix belongs HERE, in RED. Each control is the
	reference with EXACTLY ONE thing changed, so the set of checks that fire is
	attributable to that one change, and each control pins that set EXACTLY -
	a check that fires on a control it should not is as much a finding as one
	that stays quiet.

	THE DEFERRED VERIFICATIONS' SHAPES ARE HERE AS IMPLEMENTATIONS. D-2 is
	`strictRange`, D-3 is `sightBeforeRange`, D-4 is `noDecline` (its guarded
	half is in `ping_remote_controls_test.luau`). What is measured here is
	that the checks WOULD see them; D-2..D-4 THEMSELVES stay with GATES.

	THE FIXTURE'S NUMBERS are asserted first: room pitch 64, machines at
	+-16 from their room's centre, doorways at the rooms' midpoints. A check
	built on a fixture that moved would say nothing about the module.

	WHAT THIS IS NOT: `src/server/channel/Pings.luau`, or a sketch of one.
]]

local Contract = require("../helpers/PingsContract")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Stubs = require("../helpers/PingsStubs")

local function failingNames(P: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(P) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(defect: Stubs.Defect, expected: { string })
	local names, messages = failingNames(Stubs.with(defect))
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {defect} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{defect} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
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
			`{defect}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local ACCEPTS = "acceptsMachinesSettingsAndDoorwaysInRangeAndInSight"
local REFUSES = "refusesEachReasonDistinctly"
local ORDER = "firstFailureWinsInTheContractsOrder"
local BOUNDARY = "rangeIsHorizontalAndInclusiveAtPingRangeStuds"
local TUNING = "rangeIsReadFromTheProceduresTuning"
local SERVER_POSITION = "rangeIsMeasuredFromTheServersPositionNotAPayloadField"
local POSITION = "targetPositionIsPositionOfForMachinesAndTheMidpointForDoorways"
local LOS_ONCE = "lineOfSightIsAskedOnceFromTheSenderToTheTarget"
local LOS_NEVER = "lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck"
local REQ_REFUSE = "requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal"
local REQ_ACCEPT = "requestAcceptsWithoutDeclining"

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

return {
	--[[ ================================================================
	     The fixture, as numbers.
	     ================================================================ ]]

	["fixtures: the hand-built facility puts machines at +-16 from a 64-stud room pitch and doorways at the rooms' midpoints - (-16,0,-16), (16,0,16), (48,0,-16), (16,0,48); (32,0,0), (0,0,32)"] = function()
		local s = Contract.procedure()
		local pitch = s.tuning.instance.room_pitch_studs
		assert(
			pitch == 64,
			`room_pitch_studs is {pitch}; the fixture's documented numbers assume 64`
		)
		assert(
			Contract.range(s) == 12,
			`ping_range_studs is {Contract.range(s)}; the story's boundary is 12`
		)
		assert(MechanicsTuning.instance.actuator_count == 16, "actuator_count is not 16")
		local want: { [string]: Contract.Vec } = {
			["machine 1"] = { x = -16, y = 0, z = -16 },
			["machine 2"] = { x = 16, y = 0, z = 16 },
			["machine 5"] = { x = 48, y = 0, z = -16 },
			["machine 9"] = { x = 16, y = 0, z = 48 },
			["doorway 1"] = { x = 32, y = 0, z = 0 },
			["doorway 2"] = { x = 0, y = 0, z = 32 },
		}
		local got: { [string]: Contract.Vec } = {
			["machine 1"] = Contract.machinePosition(s, 1),
			["machine 2"] = Contract.machinePosition(s, 2),
			["machine 5"] = Contract.machinePosition(s, 5),
			["machine 9"] = Contract.machinePosition(s, 9),
			["doorway 1"] = Contract.doorwayPosition(s, 1),
			["doorway 2"] = Contract.doorwayPosition(s, 2),
		}
		assert(Deep.equal(got, want), `the fixture's positions moved:\n{Deep.diff(want, got)}`)
		-- The far machine is genuinely far from a sender beside the live one, and
		-- every absent id is inside the schema's bound.
		local beside = Contract.beside(s, Contract.machine(Contract.MACHINE_LIVE))
		local far = Contract.machinePosition(s, Contract.MACHINE_FAR)
		local d = math.sqrt((beside.x - far.x) ^ 2 + (beside.z - far.z) ^ 2)
		assert(d > 2 * Contract.range(s), `machine 5 is only {d} from the sender beside machine 1`)
		for _, id in Contract.ABSENT_MACHINES do
			assert(
				id >= 1 and id <= MechanicsTuning.instance.actuator_count,
				`absent id {id} is outside the schema`
			)
			for _, m in s.facility.placement.machines do
				assert(m.id ~= id, `machine {id} exists; it is listed as absent`)
			end
		end
		assert(#s.facility.layout.doors == 2, "the fixture has not got two doors")
		assert(
			s.committed[Contract.MACHINE_TO_COMMIT] == true and s.dark[Contract.DARK_ROOM] == true,
			"the fixture's committed/dark marks are missing"
		)
		print(`        [measured] fixture positions: {Deep.show(got)}`)
	end,

	--[[ ================================================================
	     The reference. Everything below is this implementation with one edit.
	     ================================================================ ]]

	["baseline: the reference implementation - the Contract written out - passes every check in PingsContract"] = function()
		local names, messages = failingNames(Stubs.reference)
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
	     AC-3's named control, and the range.
	     ================================================================ ]]

	["control (AC-3, required): a validator measuring range from the payload's position field accepts a crafted in-range payload from a server position a room away - exactly the server-position check fires, naming out_of_range"] = function()
		local messages = expectFires("clientPosition", { SERVER_POSITION })
		contains(
			messages[SERVER_POSITION],
			'(true, nil), expected (false, "out_of_range")',
			"the control's verdict"
		)
	end,

	["control (D-2's shape): a strict range comparison refuses exactly ping_range_studs - the boundary check and the tuning-range check fire, nothing else"] = function()
		local messages = expectFires("strictRange", { BOUNDARY, TUNING })
		contains(messages[BOUNDARY], "exactly 12 along +x", "the boundary case")
	end,

	["control: a 3-D distance refuses a sender exactly in range but far above or below - the boundary, tuning-range and acceptance checks fire"] = function()
		expectFires("verticalRange", { ACCEPTS, BOUNDARY, TUNING })
	end,

	["control: a range read from MechanicsTuning instead of procedure.tuning fails exactly the tuning-range check"] = function()
		expectFires("moduleRange", { TUNING })
	end,

	--[[ ================================================================
	     AC-5's order (D-3).
	     ================================================================ ]]

	["control (D-3's shape): the port asked before the range check fires the never-asked check (out_of_range targets consulted it) and the order check (out_of_sight beat out_of_range), nothing else"] = function()
		local messages = expectFires("sightBeforeRange", { ORDER, LOS_NEVER })
		contains(messages[LOS_NEVER], "lineOfSight was called 1 time(s)", "the call count")
	end,

	["control: the port asked before every check fires the never-asked check and the order check"] = function()
		expectFires("sightFirst", { ORDER, LOS_NEVER })
	end,

	--[[ ================================================================
	     AC-3's refusals and the order.
	     ================================================================ ]]

	["control: a validator that ignores committed machines fails the refusal, order, never-asked and request-refusal checks"] = function()
		local messages = expectFires("ignoresCommitted", { REFUSES, ORDER, LOS_NEVER, REQ_REFUSE })
		contains(
			messages[REFUSES],
			'expected (false, "committed_machine")',
			"the committed verdict"
		)
	end,

	["control: a validator that never checks the setting fails the refusal, order, never-asked and request-refusal checks"] = function()
		local messages = expectFires("settingUnchecked", { REFUSES, ORDER, LOS_NEVER, REQ_REFUSE })
		contains(messages[REFUSES], 'expected (false, "setting_mismatch")', "the mismatch verdict")
	end,

	["control: committed checked before existence fails exactly the order check"] = function()
		local messages = expectFires("committedBeforeExistence", { ORDER })
		contains(messages[ORDER], 'expected (false, "no_such_target")', "existence first")
	end,

	["control: position checked before committed fails exactly the order check"] = function()
		local messages = expectFires("positionBeforeCommitted", { ORDER })
		contains(messages[ORDER], 'expected (false, "committed_machine")', "committed first")
	end,

	["control: machines looked up by list index rather than by id - the fixture's ids are not dense and not in order - fails every check that touches a machine"] = function()
		expectFires("denseIds", {
			ACCEPTS,
			REFUSES,
			ORDER,
			BOUNDARY,
			TUNING,
			SERVER_POSITION,
			POSITION,
			LOS_ONCE,
			LOS_NEVER,
			REQ_REFUSE,
			REQ_ACCEPT,
		})
	end,

	["control: doorway id 0 resolving to the first door fails the refusal, targetPosition and request-refusal checks"] = function()
		local messages = expectFires("doorwayZeroIsDoorOne", { REFUSES, POSITION, REQ_REFUSE })
		contains(messages[POSITION], "absent doorway 0", "the doorway-0 case")
	end,

	["control: a doorway placed at its first room's centre instead of the midpoint fails the acceptance, refusal, boundary, server-position, targetPosition, once-asked and both request checks"] = function()
		local messages = expectFires("doorwayAtRoomA", {
			ACCEPTS,
			REFUSES,
			BOUNDARY,
			SERVER_POSITION,
			POSITION,
			LOS_ONCE,
			REQ_REFUSE,
			REQ_ACCEPT,
		})
		contains(
			messages[POSITION],
			"doorway 1 -> { x = 0, y = 0, z = 0 }, expected { x = 32, y = 0, z = 0 }",
			"the midpoint"
		)
	end,

	--[[ ================================================================
	     AC-4: request.
	     ================================================================ ]]

	["control (AC-4, D-4's shape): a request whose refusal does not decline fails exactly the request-refusal check, on the decline count"] = function()
		local messages = expectFires("noDecline", { REQ_REFUSE })
		contains(
			messages[REQ_REFUSE],
			"call.decline() was called 0 time(s), expected exactly once",
			"the decline count"
		)
	end,

	["control: a request that declines an accepted ping fails exactly the request-acceptance check"] = function()
		local messages = expectFires("declinesOnAccept", { REQ_ACCEPT })
		contains(
			messages[REQ_ACCEPT],
			"on an ACCEPTED ping; expected never",
			"the decline on acceptance"
		)
	end,

	["control: a PingRefused carrying a detail key fails exactly the request-refusal check - the result is { reason } and nothing else"] = function()
		local messages = expectFires("refusalWithDetail", { REQ_REFUSE })
		contains(messages[REQ_REFUSE], "expected exactly { reason =", "the exact shape")
	end,

	["control: a request that indexes a nil procedure fails exactly the request-refusal check, on the procedure == nil case"] = function()
		local messages = expectFires("nilProcedureRaises", { REQ_REFUSE })
		contains(messages[REQ_REFUSE], "procedure == nil -> request RAISED", "the nil case")
	end,
}
