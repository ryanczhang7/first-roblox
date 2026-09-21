--!strict
--[[
	The wrong phase-enforcing bundles NET-002's controls are aimed at, and the
	one baseline each of them is a single defect away from.

	TWO CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-4: "an implementation
	comparing only against the first entry of `legalPhases` passes AC-1 and
	AC-2 and must fail this" - `firstEntryOnly`. AC-6: "an implementation that
	captures the phase at declaration time passes every test that never
	changes phase, and must fail a test that guards once and calls in two
	different phases" - `capturesPhaseAtGuard`. The rest are the mutations
	`## Notes` asks the orchestrator to run at acceptance (the check moved
	ahead of shape) and the one-defect bundles the remaining checks would
	otherwise have no control for.

	IT IS A LAYER OVER `NetStubs.correct()`, not a second copy of it. The
	baseline here takes NET-001's correct stub bundle and wraps two exports:
	`Remotes.define` gains AC-5's refusal of an empty `legalPhases`, and
	`Wrapper.guard` gains the phase check at position 4 - after identity,
	shape and range, which the inner guard performs, and before the handler,
	which the outer guard withholds until the phase is legal. That is what
	lets one field of `defects` be the whole difference between the baseline
	and a control, and what keeps NET-001's own 19 checks satisfiable by
	every bundle here that is not built to break one.

	WHAT THIS IS NOT: `src/net/` or a sketch of it. GREEN writes the real
	check into `Wrapper.luau` and the real validation into `Remotes.luau`
	from the story's `## Contract`. Nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/phase_controls_test.luau` records what
	each one actually did.
]]

local NetStubs = require("./NetStubs")

local PhaseStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  Wrapper
	  * `ignoresPhase`            - no phase check at all: the pre-NET-002
	                                wrapper, and what the real suite fails on
	                                arrival
	  * `firstEntryOnly`          - compares against legalPhases[1] only
	                                (AC-4's control; mutation 2 of `## Notes`)
	  * `lastEntryOnly`           - compares against the last entry only
	  * `capturesPhaseAtGuard`    - reads context.phase() once, when guard()
	                                is called (AC-6's control; mutation 1)
	  * `phaseBeforeShape`        - the phase check runs after identity and
	                                before the schema (mutation 3)
	  * `phaseBeforeIdentity`     - the phase check runs first of all
	  * `phaseReasonIsShape`      - an out-of-phase call is rejected, but the
	                                reason says `shape`
	  * `runsHandlerOnPhaseReject`- the handler runs, then the call is rejected
	  * `rejectsEveryPhase`       - every phase is illegal, legal ones included
	                                (the positive control: passes AC-2)
	  * `prefixedDetail`          - detail leads with "phase: "
	  * `detailOmitsCurrent`      - detail names the legal phases only
	  * `detailOmitsLegal`        - detail names the current phase only
	  * `detailListsEveryPhase`   - detail names all five phases
	  Remotes
	  * `acceptsEmptyLegalPhases` - define() takes `{}` without complaint: the
	                                pre-NET-002 registry (AC-5)
	  * `registersBeforeRefusing` - define() registers the name and THEN
	                                raises, so the refused name is taken
]]
export type Defects = {
	ignoresPhase: boolean?,
	firstEntryOnly: boolean?,
	lastEntryOnly: boolean?,
	capturesPhaseAtGuard: boolean?,
	phaseBeforeShape: boolean?,
	phaseBeforeIdentity: boolean?,
	phaseReasonIsShape: boolean?,
	runsHandlerOnPhaseReject: boolean?,
	rejectsEveryPhase: boolean?,
	prefixedDetail: boolean?,
	detailOmitsCurrent: boolean?,
	detailOmitsLegal: boolean?,
	detailListsEveryPhase: boolean?,
	acceptsEmptyLegalPhases: boolean?,
	registersBeforeRefusing: boolean?,
}

export type Net = NetStubs.Net

local EVERY_PHASE = { "Lobby", "Assignment", "Round", "Resolution", "Post" }

function PhaseStubs.build(defects: Defects): Net
	local base = NetStubs.correct()

	--[[ Remotes ]]

	local Remotes = {}

	function Remotes.define(name: string, spec: any): any
		local phases = spec.legalPhases
		local empty = typeof(phases) ~= "table" or #phases == 0
		if empty and not defects.acceptsEmptyLegalPhases then
			if defects.registersBeforeRefusing then
				base.Remotes.define(name, spec)
			end
			error(`Remotes.define: the remote "{name}" declares an empty legalPhases`, 2)
		end
		return base.Remotes.define(name, spec)
	end

	function Remotes.all(): { any }
		return base.Remotes.all()
	end

	--[[ Wrapper ]]

	local Wrapper = {}

	function Wrapper.guard(definition: any, context: any, handler: any): any
		local captured: any = nil
		if defects.capturesPhaseAtGuard then
			captured = context.phase()
		end

		local function currentPhase(): any
			if captured ~= nil then
				return captured
			end
			return context.phase()
		end

		local function describe(current: any): string
			local legal = table.concat(definition.legalPhases, ", ")
			local detail: string
			if defects.detailOmitsCurrent then
				detail = `legal in {legal}`
			elseif defects.detailOmitsLegal then
				detail = `the phase is {tostring(current)}`
			elseif defects.detailListsEveryPhase then
				detail =
					`the phase is {tostring(current)}; legal in {legal}; phases are {table.concat(
						EVERY_PHASE,
						", "
					)}`
			else
				detail = `the phase is {tostring(current)}; legal in {legal}`
			end
			if defects.prefixedDetail then
				detail = `phase: {detail}`
			end
			return detail
		end

		-- The phase check itself: nil when legal, a Rejection otherwise.
		local function phaseCheck(): any
			if defects.ignoresPhase then
				return nil
			end
			local current = currentPhase()
			local legal = definition.legalPhases
			local ok: boolean
			if defects.rejectsEveryPhase then
				ok = false
			elseif defects.firstEntryOnly then
				ok = legal[1] == current
			elseif defects.lastEntryOnly then
				ok = legal[#legal] == current
			else
				ok = table.find(legal, current) ~= nil
			end
			if ok then
				return nil
			end
			return {
				reason = if defects.phaseReasonIsShape then "shape" else "phase",
				detail = describe(current),
			}
		end

		-- The inner guard does identity, shape and range; the handler it is
		-- given performs the phase check and only then runs the real one.
		local pending: any = nil
		local inner = base.Wrapper.guard(definition, context, function(playerId: any, args: any)
			local rejection = phaseCheck()
			if rejection ~= nil then
				pending = rejection
				if defects.runsHandlerOnPhaseReject then
					handler(playerId, args)
				end
				return
			end
			handler(playerId, args)
		end)

		return function(playerId: any, rawArgs: any): any
			pending = nil
			-- The two misplacements: ahead of everything, or ahead of the schema
			-- but behind the seat check.
			local tooEarly = defects.phaseBeforeIdentity
				or (defects.phaseBeforeShape and context.isSeated(playerId))
			if tooEarly then
				local early = phaseCheck()
				if early ~= nil then
					return early
				end
			end
			local result = inner(playerId, rawArgs)
			if result ~= nil then
				return result
			end
			return pending
		end
	end

	return { Schema = base.Schema, Remotes = Remotes, Wrapper = Wrapper }
end

-- The baseline, and every control, as ready-made bundles. Each is built fresh
-- on access so that a check's declarations never collide across controls.
function PhaseStubs.correct(): Net
	return PhaseStubs.build({})
end

function PhaseStubs.with(defect: string): Net
	local defects: { [string]: boolean } = {}
	defects[defect] = true
	return PhaseStubs.build(defects :: any)
end

PhaseStubs.DEFECTS = {
	"ignoresPhase",
	"firstEntryOnly",
	"lastEntryOnly",
	"capturesPhaseAtGuard",
	"phaseBeforeShape",
	"phaseBeforeIdentity",
	"phaseReasonIsShape",
	"runsHandlerOnPhaseReject",
	"rejectsEveryPhase",
	"prefixedDetail",
	"detailOmitsCurrent",
	"detailOmitsLegal",
	"detailListsEveryPhase",
	"acceptsEmptyLegalPhases",
	"registersBeforeRefusing",
}

return PhaseStubs
