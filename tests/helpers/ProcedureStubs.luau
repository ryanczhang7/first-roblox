--!strict
--[[
	The wrong draws GEN-003's negative controls are aimed at, and the one
	reference each statistic must ACCEPT.

	THE CRITERIA NAME THEIR CONTROLS. AC-6: "a draw that picks the two finale
	machines without regard to ring adjacency or room distance (otherwise
	correct) must fall below the floor at n = 4". AC-7: "a draw that prefers
	machines whose requiredSetting is 1 when choosing steps must fail the step
	pool or the decoy pool". AC-7's seed cap has no named control, so this file
	supplies the obvious one: a draw that never produces a valid candidate.

	THE POSITIVE CONTROL is `reference`: the finale pair first - a uniform
	non-adjacent class pair from "finale", then a uniform machine pair of those
	classes in different rooms at least `paired_room_distance_min` apart (any
	pair when none qualifies, which is an invalid candidate) - then the
	remaining steps of each class as a uniform subset of its other machines
	from "choose", then the two tracks' leading steps as a shuffle of the rest
	from "order", re-shuffled until both tracks alternate (bounded, so a draw
	that cannot alternate returns an invalid candidate). It exists so that each
	statistic is shown to ACCEPT a correct draw in RED: a statistic that rejects
	everything is indistinguishable from a broken one. Each wrong draw is the
	reference with EXACTLY ONE thing changed, so a control that fires is
	attributable to that one thing.

	WHAT THIS IS NOT: `src/server/facility/Steps.luau`, or a sketch of one. It
	has no `check`, no exported types, and its ordering strategy is one of
	several the Contract allows. GREEN writes the module from the story's
	Contract against `tests/server/steps_test.luau`; nothing here is to be
	copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `Rng`, `MechanicsTuning`,
	`Layout`, `Machines` and `Ring` are merged - so these controls are EXECUTED
	in RED, and `tests/server/steps_controls_test.luau` records what each
	measured.
]]

local Contract = require("./ProcedureContract")
local Layout = require("../../src/server/facility/Layout")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")

type Machine = Contract.Machine
type Placement = Contract.Placement
type LayoutValue = Contract.Layout
type Assignment = Contract.Assignment
type Tuning = Contract.Tuning
type Steps = Contract.Steps

local ProcedureStubs = {}

export type FinaleRule = "guarded" | "blind"
export type ChooseRule = "draw" | "preferLow"

-- How many shuffles "order" may take before the draw gives up and returns
-- what it has (an invalid candidate, which `check` rejects).
ProcedureStubs.ORDER_ATTEMPTS = 32

local function alternates(track: { number }, byId: { [number]: Machine }): boolean
	for i = 2, #track do
		if byId[track[i - 1]].keyClass == byId[track[i]].keyClass then
			return false
		end
	end
	return true
end

--[[
	A draw from a finale rule and a choose rule:

	    finale  "guarded"    non-adjacent classes, rooms ≥ paired_room_distance_min apart  (the Contract)
	            "blind"      any two classes, any two of their machines              (AC-6's control)
	    choose  "draw"       a uniform subset of each class's other machines          (the Contract)
	            "preferLow"  machines with requiredSetting 1 first, then a uniform subset (AC-7's control)
]]
function ProcedureStubs.drawWith(finaleRule: FinaleRule, chooseRule: ChooseRule): Contract.Draw
	return function(
		rng: Rng.Rng,
		layout: LayoutValue,
		placement: Placement,
		assignment: Assignment,
		tuning: Tuning
	): Steps
		local chooseRng = rng:derive("choose")
		local orderRng = rng:derive("order")
		local finaleRng = rng:derive("finale")
		local t = tuning.instance

		local byId = Contract.machineById(placement)
		local classes = Contract.classesInPlay(assignment)
		local byClass: { [number]: { Machine } } = {}
		for _, c in classes do
			byClass[c] = {}
		end
		for _, m in placement.machines do
			if byClass[m.keyClass] ~= nil then
				table.insert(byClass[m.keyClass], m)
			end
		end

		-- The finale pair of classes.
		local classPairs: { { number } } = {}
		for i = 1, #classes do
			for j = i + 1, #classes do
				local a, b = classes[i], classes[j]
				local ha = Contract.holderOf(assignment, a) :: string
				local hb = Contract.holderOf(assignment, b) :: string
				if finaleRule == "blind" or not Contract.ringNeighbours(assignment, ha, hb) then
					table.insert(classPairs, { a, b })
				end
			end
		end
		local pair = classPairs[finaleRng:nextInteger(1, #classPairs)]
		local ca, cb = pair[1], pair[2]

		-- The finale pair of machines.
		local every: { { Machine } } = {}
		local apart: { { Machine } } = {}
		for _, ma in byClass[ca] do
			for _, mb in byClass[cb] do
				table.insert(every, { ma, mb })
				if
					ma.room ~= mb.room
					and Layout.distance(layout, ma.room, mb.room) >= t.paired_room_distance_min
				then
					table.insert(apart, { ma, mb })
				end
			end
		end
		local pool = if finaleRule == "blind" or #apart == 0 then every else apart
		local chosen = pool[finaleRng:nextInteger(1, #pool)]
		local f1, f2 = chosen[1], chosen[2]

		-- The remaining steps of each class, in class order.
		local rest: { Machine } = {}
		for _, c in classes do
			local need = placement.stepsPerClass[c]
			if c == ca then
				need -= 1
			end
			if c == cb then
				need -= 1
			end
			local available: { Machine } = {}
			for _, m in byClass[c] do
				if m ~= f1 and m ~= f2 then
					table.insert(available, m)
				end
			end
			local order = chooseRng:shuffle(available)
			if chooseRule == "preferLow" then
				local ones: { Machine } = {}
				local others: { Machine } = {}
				for _, m in order do
					table.insert(if m.requiredSetting == 1 then ones else others, m)
				end
				order = table.move(others, 1, #others, #ones + 1, ones)
			end
			for i = 1, need do
				table.insert(rest, order[i])
			end
		end

		-- The order: the leading steps of each track are a shuffle of the rest.
		local lead = t.steps_per_track - 1
		local track1: { number } = {}
		local track2: { number } = {}
		for _ = 1, ProcedureStubs.ORDER_ATTEMPTS do
			local perm = orderRng:shuffle(rest)
			track1, track2 = {}, {}
			for i = 1, lead do
				track1[i] = perm[i].id
				track2[i] = perm[lead + i].id
			end
			track1[lead + 1] = f1.id
			track2[lead + 1] = f2.id
			if alternates(track1, byId) and alternates(track2, byId) then
				break
			end
		end

		return { tracks = { track1, track2 }, finale = { f1.id, f2.id } }
	end
end

-- The positive control.
ProcedureStubs.reference = ProcedureStubs.drawWith("guarded", "draw")

-- AC-6's control: the finale pair chosen blind to ring adjacency and room distance.
ProcedureStubs.finaleBlind = ProcedureStubs.drawWith("blind", "draw")

-- AC-7's control: steps prefer machines whose requiredSetting is 1.
ProcedureStubs.preferLowSetting = ProcedureStubs.drawWith("guarded", "preferLow")

-- The seed cap's control: the reference's draws, then no tracks at all, so
-- every candidate is rejected under `INV_balanced_steps:shape`.
ProcedureStubs.neverValid = function(
	rng: Rng.Rng,
	layout: LayoutValue,
	placement: Placement,
	assignment: Assignment,
	tuning: Tuning
): Steps
	local s = ProcedureStubs.reference(rng, layout, placement, assignment, tuning)
	return { tracks = {}, finale = s.finale }
end

return ProcedureStubs
