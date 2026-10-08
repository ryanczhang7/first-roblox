--!strict
--[[
	The wrong lens views VIEW-001's controls are aimed at, and the reference
	each of them is a single defect away from.

	A FACTORY OVER A TABLE OF DEFECTS, as `ProjectionStubs.luau` is: `defects`
	is empty for the reference and has exactly ONE field set for every control,
	so a control that fires is attributable to that one thing. The criteria
	name their controls: AC-1 says a view gating on range only (any class) must
	fail the class clause and one gating on class only (any range) must fail
	the range clause; the Contract's D-1..D-4 name the direction error, the
	missing lit check, the strict boundary and the early line-of-sight call.
	The rest are the one-defect views the remaining criteria would otherwise
	have no control for.

	WHAT THIS IS NOT: it is not `src/server/seats/Projection.luau` and not a
	sketch of one. The reference is the five-clause filter only as far as the
	checks can see - every type is `any`, it uses whatever iteration is
	shortest, and nothing here is held to SEAT-002's copy-helper ban. GREEN
	writes `lensFor` from the story's Contract against the failing tests in
	`tests/server/lens_view_test.luau`; nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `Ring`, `Machines` and
	`Procedure` are merged, so every number the controls file asserts is a
	measurement taken in RED, not a claim left for GREEN.
]]

local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Procedure = require("../../src/server/procedure/Procedure")
local Ring = require("../../src/server/seats/Ring")

local LensViewStubs = {}

export type Vec = { x: number, y: number, z: number }
export type View = (
	assignment: any,
	procedure: any,
	playerId: string,
	position: Vec?,
	los: any
) -> any

type Defects = {
	anyClass: boolean?, -- gate on range only (AC-1's first named control)
	anyRange: boolean?, -- gate on class only (AC-1's second named control)
	ignoreDark: boolean?, -- D-2
	ignoreCommitted: boolean?,
	ignoreSight: boolean?,
	keyNotLens: boolean?, -- D-1: compare against the player's own KEY
	sightFirst: boolean?, -- D-4: ask line of sight before anything else
	sightTwice: boolean?, -- ask twice per eligible machine
	shippedRange: boolean?, -- read the constant from MechanicsTuning, not procedure.tuning
	strictRange: boolean?, -- D-3: `<` rather than `<=`
	threeDRange: boolean?, -- include y in the distance
	nilPositionNotEmpty: boolean?, -- `{}` rather than `{ readings = {} }` for nil
	nilPositionConsultsSight: boolean?, -- ask line of sight even with no position
	extraKeyOnReading: boolean?, -- a `room` field on each reading
	extraKeyOnView: boolean?, -- a `playerId` field on the view
	descending: boolean?, -- readings in descending machineId
	listOrder: boolean?, -- readings in placement order, never sorted
	settingIsTag: boolean?, -- the wrong number in `setting`
	sharedList: boolean?, -- the same readings table handed back every call
}

local function horizontal(a: Vec, b: Vec): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

local function make(defects: Defects): View
	local shared: { any } = {}
	return function(
		assignment: any,
		procedure: any,
		playerId: string,
		position: Vec?,
		los: any
	): any
		if position == nil then
			if defects.nilPositionConsultsSight then
				for _, m in procedure.facility.placement.machines do
					los(
						{ x = 0, y = 0, z = 0 },
						Machines.positionOf(procedure.facility.layout, m, procedure.tuning)
					)
				end
			end
			if defects.nilPositionNotEmpty then
				return {}
			end
			return { readings = {} }
		end
		local at: Vec = position :: Vec
		local wanted = if defects.keyNotLens
			then assignment.keyClasses[playerId][1]
			else Ring.lensOf(assignment, playerId)
		local range = if defects.shippedRange
			then MechanicsTuning.instance.lens_read_range_studs
			else procedure.tuning.instance.lens_read_range_studs
		local readings: { any } = if defects.sharedList then shared else {}
		if defects.sharedList then
			table.clear(shared)
		end
		for _, m in procedure.facility.placement.machines do
			local mp = Machines.positionOf(procedure.facility.layout, m, procedure.tuning)
			local seenEarly = if defects.sightFirst then los(at, mp) else nil
			if not defects.anyClass and m.keyClass ~= wanted then
				continue
			end
			local d = if defects.threeDRange
				then math.sqrt(horizontal(at, mp) ^ 2 + (at.y - mp.y) ^ 2)
				else horizontal(at, mp)
			local inRange = if defects.strictRange then d < range else d <= range
			if not defects.anyRange and not inRange then
				continue
			end
			if not defects.ignoreDark and Procedure.isDark(procedure, m.room) then
				continue
			end
			if not defects.ignoreCommitted and procedure.committed[m.id] == true then
				continue
			end
			if not defects.ignoreSight then
				local seen = if seenEarly ~= nil then seenEarly else los(at, mp)
				if defects.sightTwice then
					seen = los(at, mp) and seen
				end
				if not seen then
					continue
				end
			end
			local reading: any = {
				machineId = m.id,
				setting = if defects.settingIsTag then m.tag else m.requiredSetting,
			}
			if defects.extraKeyOnReading then
				reading.room = m.room
			end
			table.insert(readings, reading)
		end
		if not defects.listOrder then
			table.sort(readings, function(a: any, b: any): boolean
				return if defects.descending
					then a.machineId > b.machineId
					else a.machineId < b.machineId
			end)
		end
		local view: any = { readings = readings }
		if defects.extraKeyOnView then
			view.playerId = playerId
		end
		return view
	end
end

LensViewStubs.reference = make({})
LensViewStubs.rangeOnly = make({ anyClass = true })
LensViewStubs.classOnly = make({ anyRange = true })
LensViewStubs.ignoreDark = make({ ignoreDark = true })
LensViewStubs.ignoreCommitted = make({ ignoreCommitted = true })
LensViewStubs.ignoreSight = make({ ignoreSight = true })
LensViewStubs.keyNotLens = make({ keyNotLens = true })
LensViewStubs.sightFirst = make({ sightFirst = true })
LensViewStubs.sightTwice = make({ sightTwice = true })
LensViewStubs.shippedRange = make({ shippedRange = true })
LensViewStubs.strictRange = make({ strictRange = true })
LensViewStubs.threeDRange = make({ threeDRange = true })
LensViewStubs.nilPositionNotEmpty = make({ nilPositionNotEmpty = true })
LensViewStubs.nilPositionConsultsSight = make({ nilPositionConsultsSight = true })
LensViewStubs.extraKeyOnReading = make({ extraKeyOnReading = true })
LensViewStubs.extraKeyOnView = make({ extraKeyOnView = true })
LensViewStubs.descending = make({ descending = true })
LensViewStubs.listOrder = make({ listOrder = true })
LensViewStubs.settingIsTag = make({ settingIsTag = true })
LensViewStubs.sharedList = make({ sharedList = true })

return LensViewStubs
