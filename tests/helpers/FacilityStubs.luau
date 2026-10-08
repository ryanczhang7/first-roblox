--!strict
--[[
	The wrong computes and generators GEN-004's negative controls are aimed at,
	and the one reference each check must ACCEPT.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a compute that sums the helper's
	and the turner's walks instead of taking the maximum must fail fixture 4.
	One that adds the finale's two sub-steps sequentially must fail fixture 3."
	AC-3 (the brief): "a stub generator that hands every stage the same
	un-derived attempt stream; the controls test must show AC-3's assertion
	rejects it." The deferred verifications D-1 to D-4 name three more shapes -
	a summed par inside the generator, a generator with no `INV_traversal`
	check, the machines stage on the layout's stream, and an attempt number one
	off its stream - and each is a generator here, so that what GATES will
	mutate into the real module has already been seen to be caught by the
	checks that will judge it.

	THE POSITIVE CONTROL is `generateWith(nil)`: C-4 written out over the real
	`Layout`, `Machines` and `Steps` (all merged) with `computeWith({})` for
	par. It exists so that every check is shown to ACCEPT a correct generator
	in RED: a check that rejects everything is indistinguishable from a broken
	one. Each wrong generator is the reference with EXACTLY ONE thing changed,
	so a control that fires is attributable to that one thing.

	`computeWith({})` is a SECOND, parameterised writing of `mechanics.md`
	§6.3, kept apart from `FacilityContract.par` on purpose: the controls file
	shows the two agree on the fixtures and on 3,000 real compositions, which
	pins the oracle from two directions. Each wrong compute is `computeWith`
	with one rule flipped.

	WHAT THIS IS NOT: `src/server/facility/Par.luau` or `Generator.luau`, or a
	sketch of either. There are no exported types, no `table.freeze`, and the
	seams are test parameters. GREEN writes both modules from the story's
	Contract against `par_test.luau` and `generator_test.luau`; nothing here is
	to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/server/facility_controls_test.luau` records
	what each measured.
]]

local Contract = require("./FacilityContract")
local Layout = require("../../src/server/facility/Layout")
local Machines = require("../../src/server/facility/Machines")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local Steps = require("../../src/server/facility/Steps")

type LayoutValue = Contract.Layout
type Placement = Contract.Placement
type StepsValue = Contract.Steps
type Assignment = Contract.Assignment
type Tuning = Contract.Tuning
type Facility = Contract.Facility

local FacilityStubs = {}

--[[ ------------------------------------------------------------------------
     Par, with one rule flipped at a time.

         combine  "max"          the helper and the turner walk in parallel  (C-2)
                  "sum"          their walks are added                       (AC-1's first control)
         finale   "unit"         one unit: max over both sub-steps, one P+T  (C-2)
                  "sequential"   two more ordinary steps, each with its P+T  (AC-1's second control)
         order    "interleaved"  T1[1], T2[1], T1[2], T2[2], ...              (C-2)
                  "trackwise"    all of track 1, then all of track 2         (an extra control)
     --------------------------------------------------------------------- ]]

export type ParRules = {
	combine: ("max" | "sum")?,
	finale: ("unit" | "sequential")?,
	order: ("interleaved" | "trackwise")?,
}

function FacilityStubs.computeWith(rules: ParRules): Contract.Compute
	local combine = rules.combine or "max"
	local finaleRule = rules.finale or "unit"
	local order = rules.order or "interleaved"
	return function(
		layout: LayoutValue,
		placement: Placement,
		steps: StepsValue,
		assignment: Assignment,
		tuning: Tuning
	): number
		local t = tuning.instance
		local distance = Contract.distanceFn(layout)
		local pos: { [string]: number } = {}
		for _, p in assignment.players do
			pos[p] = layout.spawnRoom
		end

		local function cost(id: number): (number, Contract.Participants)
			local who = Contract.participantsOf(placement, assignment, id)
			local h = distance(pos[who.helper], who.room) * t.room_traversal_seconds
			local u = distance(pos[who.turner], who.room) * t.room_traversal_seconds
			return if combine == "sum" then h + u else math.max(h, u), who
		end
		local function move(who: Contract.Participants)
			pos[who.helper] = who.room
			pos[who.turner] = who.room
		end

		local ordinary: { number }
		local finale: { number }
		if order == "trackwise" then
			ordinary = {}
			for _, track in steps.tracks do
				for i = 1, #track - 1 do
					table.insert(ordinary, track[i])
				end
			end
			finale = table.clone(steps.finale)
		else
			ordinary, finale = Contract.scheduleOrder(steps)
		end

		local total = 0
		for _, id in ordinary do
			local d, who = cost(id)
			total += d + t.par_ping_seconds + t.par_turn_seconds
			move(who)
		end
		if finaleRule == "sequential" then
			for _, id in finale do
				local d, who = cost(id)
				total += d + t.par_ping_seconds + t.par_turn_seconds
				move(who)
			end
		else
			local longest = 0
			for _, id in finale do
				local d = cost(id)
				longest = math.max(longest, d)
			end
			total += longest + t.par_ping_seconds + t.par_turn_seconds
		end
		return total
	end
end

-- The reference compute: every rule as C-2 states it.
FacilityStubs.computeReference = FacilityStubs.computeWith({})
-- AC-1's first control: the helper's and the turner's walks are summed.
FacilityStubs.computeSumWalks = FacilityStubs.computeWith({ combine = "sum" })
-- AC-1's second control: the finale's two sub-steps are taken one after the other.
FacilityStubs.computeSequentialFinale = FacilityStubs.computeWith({ finale = "sequential" })
-- An extra control: track 1 in full, then track 2, instead of alternating.
FacilityStubs.computeTrackwise = FacilityStubs.computeWith({ order = "trackwise" })

--[[ ------------------------------------------------------------------------
     Generators, C-4 with one defect at a time.

         nil                       the reference
         "sharedStream"            every stage is handed the un-derived attempt stream `a`  (AC-3's control)
         "machinesOnLayoutStream"  the machines stage is handed a:derive("layout")           (D-3's shape)
         "attemptOffByOne"         attempt i draws from "attempt-" .. (i + 1)                (D-4's shape)
         "noTraversal"             INV_traversal is never checked                            (D-2's shape)
         "sumWalks"                par is computed with summed walks                         (D-1's shape)
         "returnsRejected"         the first attempt is returned whether or not it passed    (AC-4 / AC-5's shape)
     --------------------------------------------------------------------- ]]

export type Defect =
	"sharedStream"
	| "machinesOnLayoutStream"
	| "attemptOffByOne"
	| "noTraversal"
	| "sumWalks"
	| "returnsRejected"

function FacilityStubs.generateWith(defect: Defect?): Contract.Generate
	local compute = if defect == "sumWalks"
		then FacilityStubs.computeSumWalks
		else FacilityStubs.computeReference
	return function(
		assignment: Assignment,
		seed: number,
		tuning: Tuning,
		predicateOverride: ((Facility) -> string?)?,
		stagesOverride: Contract.Stages?
	): any
		local stages = stagesOverride or {}
		local layoutStage = stages.layout or Layout.generate
		local machinesStage = stages.machines or Machines.generate
		local stepsStage = stages.steps or Steps.draw
		local classes = Contract.classesOf(assignment)
		local failures: { { attempt: number, invariant: string } } = {}

		for i = 1, tuning.instance.generator_attempts_max do
			local streamIndex = if defect == "attemptOffByOne" then i + 1 else i
			local a = Rng.fromSeed(seed):derive("instance"):derive(`attempt-{streamIndex}`)
			local layoutRng, machinesRng, stepsRng
			if defect == "sharedStream" then
				layoutRng, machinesRng, stepsRng = a, a, a
			elseif defect == "machinesOnLayoutStream" then
				layoutRng, machinesRng, stepsRng =
					a:derive("layout"), a:derive("layout"), a:derive("steps")
			else
				layoutRng, machinesRng, stepsRng =
					a:derive("layout"), a:derive("machines"), a:derive("steps")
			end

			local function fail(invariant: string)
				table.insert(failures, { attempt = i, invariant = invariant })
			end

			local layout = layoutStage(layoutRng, tuning)
			local report = Layout.check(layout, tuning)
			if #report > 0 then
				fail(report[1])
				continue
			end
			local placement = machinesStage(machinesRng, layout, classes, tuning)
			report = Machines.check(placement, layout, classes, tuning)
			if #report > 0 then
				fail(report[1])
				continue
			end
			local steps = stepsStage(stepsRng, layout, placement, assignment, tuning)
			report = Steps.check(steps, layout, placement, assignment, tuning)
			local facility: Facility = {
				layout = layout,
				placement = placement,
				steps = steps,
				spawnRoom = layout.spawnRoom,
				par = 0,
				attempt = i,
			}
			if defect == "returnsRejected" then
				facility.par = compute(layout, placement, steps, assignment, tuning)
				return { kind = "facility", facility = facility }
			end
			if #report > 0 then
				fail(report[1])
				continue
			end
			local par = compute(layout, placement, steps, assignment, tuning)
			facility.par = par
			if defect ~= "noTraversal" and not Contract.traversalOk(par, tuning) then
				fail(Contract.traversalFailure(par, tuning))
				continue
			end
			if predicateOverride ~= nil then
				local verdict = predicateOverride(facility)
				if verdict ~= nil then
					fail(verdict)
					continue
				end
			end
			return { kind = "facility", facility = facility }
		end
		return { kind = "failed", failures = failures }
	end
end

FacilityStubs.reference = FacilityStubs.generateWith(nil)
FacilityStubs.sharedStream = FacilityStubs.generateWith("sharedStream")
FacilityStubs.machinesOnLayoutStream = FacilityStubs.generateWith("machinesOnLayoutStream")
FacilityStubs.attemptOffByOne = FacilityStubs.generateWith("attemptOffByOne")
FacilityStubs.noTraversal = FacilityStubs.generateWith("noTraversal")
FacilityStubs.sumWalks = FacilityStubs.generateWith("sumWalks")
FacilityStubs.returnsRejected = FacilityStubs.generateWith("returnsRejected")

return FacilityStubs
