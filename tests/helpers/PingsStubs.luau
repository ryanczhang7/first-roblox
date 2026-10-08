--!strict
--[[
	The wrong validators CHAN-005's negative controls are aimed at, and the one
	reference every check in `PingsContract.luau` must ACCEPT.

	THE CRITERIA AND THE DEFERRED VERIFICATIONS NAME THEIR CONTROLS. AC-3: "a
	validator that measures range from a client-supplied position must fail a
	fixture in which the payload is crafted to be in range and the server's
	position is not" - `clientPosition`. AC-4: "the same sequence with a
	handler that does not decline must be rejected for rate" - `noDecline`,
	which is also D-4's shape (the `call.decline()` removed). D-2's shape is
	`strictRange` (`<=` turned to `<`); D-3's is `sightBeforeRange` (the port
	asked before the range check). Each is here as an implementation, so that
	what GATES will mutate into the real module has already been seen to be
	caught by the checks that will judge it.

	THE POSITIVE CONTROL is `reference`: the Contract's check order and
	positions clause written out over the merged `Machines.positionOf`. It
	exists so that every check is shown to ACCEPT a correct implementation in
	RED: a check that refuses everything is indistinguishable from a broken
	one. Each wrong implementation is the reference with EXACTLY ONE thing
	changed, so the set of checks that fire is attributable to that one
	change, and `pings_controls_test.luau` pins that set EXACTLY.

	WHAT THIS IS NOT: `src/server/channel/Pings.luau`, or a sketch of one. It
	exports no types, freezes nothing, and its defects are parameters. GREEN
	writes the module from the story's Contract against `pings_test.luau` and
	`ping_remote_test.luau`; nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `Machines` and
	`MechanicsTuning` are merged - so these controls are EXECUTED in RED, and
	the controls tests record what each measured.
]]

local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")

local PingsStubs = {}

export type Defect =
	"clientPosition" -- AC-3's control: range from `target.position` when the payload carries one
	| "strictRange" -- D-2: exactly ping_range_studs is refused
	| "verticalRange" -- a 3-D distance
	| "sightBeforeRange" -- D-3: the port is asked before the range check
	| "sightFirst" -- the port is asked before every check
	| "noDecline" -- AC-4's control, D-4: a refusal does not decline
	| "declinesOnAccept" -- an accepted ping declines too
	| "refusalWithDetail" -- the PingRefused carries a second key
	| "ignoresCommitted" -- check 3 skipped
	| "settingUnchecked" -- check 1 skipped
	| "denseIds" -- machines looked up by list index, not by `id`
	| "doorwayAtRoomA" -- a doorway sits at its first room's centre, not the midpoint
	| "moduleRange" -- range read from MechanicsTuning, not procedure.tuning
	| "nilProcedureRaises" -- `request` indexes a nil procedure
	| "doorwayZeroIsDoorOne" -- doorway id 0 resolves to the first door
	| "committedBeforeExistence" -- check 3 runs before check 2
	| "positionBeforeCommitted" -- check 4 runs before check 3

PingsStubs.DEFECTS = {
	"clientPosition",
	"strictRange",
	"verticalRange",
	"sightBeforeRange",
	"sightFirst",
	"noDecline",
	"declinesOnAccept",
	"refusalWithDetail",
	"ignoresCommitted",
	"settingUnchecked",
	"denseIds",
	"doorwayAtRoomA",
	"moduleRange",
	"nilProcedureRaises",
	"doorwayZeroIsDoorOne",
	"committedBeforeExistence",
	"positionBeforeCommitted",
} :: { Defect }

type Vec = { x: number, y: number, z: number }

local function roomCentre(layout: any, roomId: number, pitch: number): Vec?
	for _, room in layout.rooms do
		if room.id == roomId then
			return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
		end
	end
	return nil
end

-- The module table for `defect` (nil: the reference).
function PingsStubs.with(defect: Defect?): any
	local function machineOf(facility: any, id: number): any
		if defect == "denseIds" then
			return facility.placement.machines[id]
		end
		for _, m in facility.placement.machines do
			if m.id == id then
				return m
			end
		end
		return nil
	end

	local function targetPosition(procedure: any, target: any): Vec?
		local layout = procedure.facility.layout
		if target.kind == "doorway" then
			local id = target.target
			if defect == "doorwayZeroIsDoorOne" and id == 0 then
				id = 1
			end
			local door = layout.doors[id]
			if door == nil then
				return nil
			end
			local pitch = procedure.tuning.instance.room_pitch_studs
			local a = roomCentre(layout, door.a, pitch) :: Vec
			local b = roomCentre(layout, door.b, pitch) :: Vec
			if defect == "doorwayAtRoomA" then
				return a
			end
			return { x = (a.x + b.x) / 2, y = 0, z = (a.z + b.z) / 2 }
		end
		local m = machineOf(procedure.facility, target.target)
		if m == nil then
			return nil
		end
		return Machines.positionOf(layout, m, procedure.tuning)
	end

	local function settingMismatch(target: any): boolean
		if target.kind == "setting" then
			return target.setting == nil
		end
		return target.setting ~= nil
	end

	local function committed(procedure: any, target: any): boolean
		return target.kind ~= "doorway" and procedure.committed[target.target] == true
	end

	local function outOfRange(procedure: any, from: Vec, to: Vec): boolean
		local range = if defect == "moduleRange"
			then MechanicsTuning.channel.ping_range_studs
			else procedure.tuning.channel.ping_range_studs
		local dx = from.x - to.x
		local dz = from.z - to.z
		local squared = dx * dx + dz * dz
		if defect == "verticalRange" then
			local dy = from.y - to.y
			squared += dy * dy
		end
		local distance = math.sqrt(squared)
		if defect == "strictRange" then
			return distance >= range
		end
		return distance > range
	end

	local function validate(
		procedure: any,
		senderPosition: Vec?,
		target: any,
		lineOfSight: any
	): (boolean, string?)
		local position = targetPosition(procedure, target)
		if defect == "sightFirst" and lineOfSight(senderPosition, position) ~= true then
			return false, "out_of_sight"
		end
		if defect ~= "settingUnchecked" and settingMismatch(target) then
			return false, "setting_mismatch"
		end
		if defect == "committedBeforeExistence" and committed(procedure, target) then
			return false, "committed_machine"
		end
		if position == nil then
			return false, "no_such_target"
		end
		if defect == "positionBeforeCommitted" and senderPosition == nil then
			return false, "no_position"
		end
		if defect ~= "ignoresCommitted" and committed(procedure, target) then
			return false, "committed_machine"
		end
		if senderPosition == nil then
			return false, "no_position"
		end
		local from: Vec = senderPosition :: Vec
		if defect == "clientPosition" and typeof(target.position) == "table" then
			from = target.position
		end
		if defect == "sightBeforeRange" and lineOfSight(senderPosition, position) ~= true then
			return false, "out_of_sight"
		end
		if outOfRange(procedure, from, position) then
			return false, "out_of_range"
		end
		if defect ~= "sightBeforeRange" and defect ~= "sightFirst" then
			if lineOfSight(senderPosition, position) ~= true then
				return false, "out_of_sight"
			end
		end
		return true, nil
	end

	local function refused(reason: string): any
		if defect == "refusalWithDetail" then
			return { reason = reason, detail = `ping refused: {reason}` }
		end
		return { reason = reason }
	end

	local function request(
		procedure: any,
		positions: any,
		senderId: string,
		target: any,
		call: any,
		lineOfSight: any
	): any
		-- Decided up front: the analyser narrows `defect` through a branch
		-- condition and then refuses a second comparison inside it.
		local declines = defect ~= "noDecline"
		local checksNilProcedure = defect ~= "nilProcedureRaises"
		local declinesOnAccept = defect == "declinesOnAccept"
		if procedure == nil and checksNilProcedure then
			if declines then
				call.decline()
			end
			return refused("no_such_target")
		end
		local ok, reason = validate(procedure, positions[senderId], target, lineOfSight)
		if not ok then
			if declines then
				call.decline()
			end
			return refused(reason :: string)
		end
		if declinesOnAccept then
			call.decline()
		end
		return nil
	end

	return { validate = validate, targetPosition = targetPosition, request = request }
end

-- The positive control.
PingsStubs.reference = PingsStubs.with(nil)

return PingsStubs
