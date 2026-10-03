--!strict
--[[
	The wrong turn-cue views VIEW-002's controls are aimed at, and the
	reference each of them is a single defect away from.

	A FACTORY OVER A TABLE OF DEFECTS, as `LensViewStubs.luau` is: `defects`
	is empty for the reference and has exactly ONE field set for every control,
	so a control that fires is attributable to that one thing. The criteria
	and the Contract name their controls: AC-1's every-live-machine view, the
	direction error D-1 (ownership by lens, not key), the strict lookahead
	D-2, position-0-as-live D-3, next-not-excluding-live D-4, and the view
	that reads the shipped constant instead of `procedure.tuning`. The rest
	are the one-defect views AC-3 and AC-6 would otherwise have no control for.

	WHAT THIS IS NOT: it is not `src/server/seats/Projection.luau` and not a
	sketch of one. Every type is `any`, it uses whatever is shortest, and
	nothing here is held to SEAT-002's copy-helper ban. GREEN writes
	`turnCuesFor` from the story's Contract against the failing tests in
	`tests/server/turn_cues_test.luau`; nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `Ring` and `Procedure`
	are merged, so every number the controls file asserts is a measurement
	taken in RED, not a claim left for GREEN.
]]

local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Procedure = require("../../src/server/procedure/Procedure")
local Ring = require("../../src/server/seats/Ring")

local TurnCuesStubs = {}

export type View = (assignment: any, procedure: any, playerId: string) -> any

type Defects = {
	everyLive: boolean?, -- AC-1's named control: live lists every live machine, anyone's
	lensNotKey: boolean?, -- D-1: own = Ring.lensOf rather than keyClasses[p]
	strictLookahead: boolean?, -- D-2: `<` rather than `<=`
	positionZeroAsLive: boolean?, -- D-3: live = position 0, not Procedure.isLive
	nextIncludesLive: boolean?, -- D-4: next does not exclude live
	shippedLookahead: boolean?, -- read MechanicsTuning, not procedure.tuning
	descending: boolean?, -- lists sorted descending
	trackOrder: boolean?, -- lists in track order, never sorted
	extraKey: boolean?, -- a `playerId` field on the view
	sharedLists: boolean?, -- the same two tables handed back every call
	decoyIncluded: boolean?, -- an owned decoy appended to next
	duplicateCue: boolean?, -- the first live cue listed twice
}

local function machineById(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

local function make(defects: Defects): View
	local sharedLive: { number } = {}
	local sharedNext: { number } = {}
	return function(assignment: any, procedure: any, playerId: string): any
		local owned: { number } = if defects.lensNotKey
			then { Ring.lensOf(assignment, playerId) }
			else assignment.keyClasses[playerId]
		local lookahead = if defects.shippedLookahead
			then MechanicsTuning.instance.turn_cue_lookahead
			else procedure.tuning.instance.turn_cue_lookahead
		local live: { number } = if defects.sharedLists then sharedLive else {}
		local nextIds: { number } = if defects.sharedLists then sharedNext else {}
		if defects.sharedLists then
			table.clear(live)
			table.clear(nextIds)
		end
		local inTrack: { [number]: boolean } = {}
		for _, track in procedure.facility.steps.tracks do
			local position = 0
			for _, id in track do
				inTrack[id] = true
				if procedure.committed[id] ~= true then
					local m = machineById(procedure.facility, id)
					local isOwned = table.find(owned, m.keyClass) ~= nil
					local isLive = if defects.positionZeroAsLive
						then position == 0
						else Procedure.isLive(procedure, id)
					local inWindow = if defects.strictLookahead
						then position < lookahead
						else position <= lookahead
					if isLive and (isOwned or defects.everyLive) then
						table.insert(live, id)
					end
					if isOwned and inWindow and (not isLive or defects.nextIncludesLive) then
						table.insert(nextIds, id)
					end
					position += 1
				end
			end
		end
		if defects.decoyIncluded then
			for _, m in procedure.facility.placement.machines do
				if not inTrack[m.id] and table.find(owned, m.keyClass) ~= nil then
					table.insert(nextIds, m.id)
				end
			end
		end
		if defects.duplicateCue and #live > 0 then
			table.insert(live, live[1])
		end
		if not defects.trackOrder then
			local function order(a: number, b: number): boolean
				return if defects.descending then a > b else a < b
			end
			table.sort(live, order)
			table.sort(nextIds, order)
		end
		local view: any = { live = live, ["next"] = nextIds }
		if defects.extraKey then
			view.playerId = playerId
		end
		return view
	end
end

TurnCuesStubs.reference = make({})
TurnCuesStubs.everyLive = make({ everyLive = true })
TurnCuesStubs.lensNotKey = make({ lensNotKey = true })
TurnCuesStubs.strictLookahead = make({ strictLookahead = true })
TurnCuesStubs.positionZeroAsLive = make({ positionZeroAsLive = true })
TurnCuesStubs.nextIncludesLive = make({ nextIncludesLive = true })
TurnCuesStubs.shippedLookahead = make({ shippedLookahead = true })
TurnCuesStubs.descending = make({ descending = true })
TurnCuesStubs.trackOrder = make({ trackOrder = true })
TurnCuesStubs.extraKey = make({ extraKey = true })
TurnCuesStubs.sharedLists = make({ sharedLists = true })
TurnCuesStubs.decoyIncluded = make({ decoyIncluded = true })
TurnCuesStubs.duplicateCue = make({ duplicateCue = true })

return TurnCuesStubs
