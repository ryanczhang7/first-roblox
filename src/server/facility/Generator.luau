--!strict
--[[
	The instance generator's resample loop, per GEN-004 and
	`docs/wiki/game/mechanics.md` §6.2 (G11), §6.3. It composes `Layout`,
	`Machines` and `Steps`, prices the result with `Par`, and returns the first
	attempt that passes every invariant - `tuning.md` §2's structural ones and
	`INV_traversal`, `par × schedule_slack ≤ round_seconds`. That last one is
	the floor (`loop.md` §1a): no facility is offered that a group doing nothing
	clever could not finish inside the clock.

	ONE ATTEMPT. Attempt `i` draws only from
	`Rng.fromSeed(seed):derive("instance"):derive("attempt-" .. i)`, and from
	that only through its `"layout"`, `"machines"` and `"steps"` sub-streams,
	derived once each and handed to exactly one stage. Sub-streams isolate the
	stages (D2): a stage that draws differently moves nothing upstream.

	THE CHECKS RUN IN ORDER, and the first non-empty report ends the attempt:
	`Layout.check`, `Machines.check`, `Steps.check`, `INV_traversal`, then the
	`predicateOverride` when one is passed. A stage whose upstream check failed
	is not run, so a malformed layout is never handed to `Machines.generate`.
	Each failure is recorded as `{ attempt, invariant }`, where `invariant` is
	the failing report's first string verbatim. After `generator_attempts_max`
	failures the result is `failed`; `Session` maps that to
	`no_contest / generation_failed` (SLICE-005), not here.

	THE TWO OVERRIDES ARE TEST SEAMS. `predicateOverride` exists for AC-4 and
	`stagesOverride` for AC-3; production passes nil for both. A stage
	override is called with exactly the real stage's signature.

	`round_seconds` IS READ FROM `@game/ReplicatedStorage/Shared/Tuning` AT LOAD, as `Ring` reads
	`min_players_to_continue`. `MechanicsTuning` does not carry it, and a
	second copy would be a second place for it to live. Everything else is
	read from the `tuning` argument.

	PURE. No module state, no Roblox API, and no argument is ever mutated. A
	`Facility` is plain data - exactly `layout`, `placement`, `steps`,
	`spawnRoom`, `par` and `attempt` - a function of the seed and the ring.
]]

local Layout = require("./Layout")
local Machines = require("./Machines")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Par = require("./Par")
local Ring = require("../seats/Ring")
local Rng = require("@game/ReplicatedStorage/Shared/Rng")
local Steps = require("./Steps")
local Tuning = require("@game/ReplicatedStorage/Shared/Tuning")

export type Facility = {
	layout: Layout.Layout,
	placement: Machines.Placement,
	steps: Steps.Steps,
	spawnRoom: number,
	par: number,
	attempt: number,
}
export type Failure = { attempt: number, invariant: string }
export type GenerateResult =
	{ kind: "facility", facility: Facility }
	| { kind: "failed", failures: { Failure } }
export type Stages = {
	layout: typeof(Layout.generate)?,
	machines: typeof(Machines.generate)?,
	steps: typeof(Steps.draw)?,
}

type Tuning = MechanicsTuning.MechanicsTuning

local Generator = {}

local ROUND_SECONDS = Tuning.round.round_seconds

-- C-4: the classes in play, the sorted union of every player's key classes.
local function classesOf(assignment: Ring.Assignment): { number }
	local seen: { [number]: boolean } = {}
	local classes: { number } = {}
	for _, p in assignment.players do
		local held: { Ring.KeyClass } = assignment.keyClasses[p] or {}
		for _, c in held do
			if not seen[c] then
				seen[c] = true
				table.insert(classes, c)
			end
		end
	end
	table.sort(classes)
	return classes
end

function Generator.generate(
	assignment: Ring.Assignment,
	seed: number,
	tuning: Tuning,
	predicateOverride: ((Facility) -> string?)?,
	stagesOverride: Stages?
): GenerateResult
	local t = tuning.instance
	local stages: Stages = stagesOverride or {}
	local generateLayout = stages.layout or Layout.generate
	local generateMachines = stages.machines or Machines.generate
	local drawSteps = stages.steps or Steps.draw
	local classes = classesOf(assignment)

	-- One attempt: the facility, or the first string of the first failing report.
	local function attempt(i: number): (Facility?, string?)
		local a = Rng.fromSeed(seed):derive("instance"):derive(`attempt-{i}`)

		local layout = generateLayout(a:derive("layout"), tuning)
		local report = Layout.check(layout, tuning)
		if #report > 0 then
			return nil, report[1]
		end

		local placement = generateMachines(a:derive("machines"), layout, classes, tuning)
		report = Machines.check(placement, layout, classes, tuning)
		if #report > 0 then
			return nil, report[1]
		end

		local steps = drawSteps(a:derive("steps"), layout, placement, assignment, tuning)
		report = Steps.check(steps, layout, placement, assignment, tuning)
		if #report > 0 then
			return nil, report[1]
		end

		local par = Par.compute(layout, placement, steps, assignment, tuning)
		if par * t.schedule_slack > ROUND_SECONDS then
			return nil,
				`INV_traversal:par {par} x schedule_slack {t.schedule_slack} = {par * t.schedule_slack}, `
					.. `over round_seconds {ROUND_SECONDS}`
		end

		local facility: Facility = {
			layout = layout,
			placement = placement,
			steps = steps,
			spawnRoom = layout.spawnRoom,
			par = par,
			attempt = i,
		}
		if predicateOverride then
			local refused = predicateOverride(facility)
			if refused ~= nil then
				return nil, refused
			end
		end
		return facility, nil
	end

	local failures: { Failure } = {}
	for i = 1, t.generator_attempts_max do
		local facility, invariant = attempt(i)
		if facility then
			return { kind = "facility", facility = facility }
		end
		table.insert(failures, { attempt = i, invariant = invariant :: string })
	end
	return { kind = "failed", failures = failures }
end

return table.freeze(Generator)
