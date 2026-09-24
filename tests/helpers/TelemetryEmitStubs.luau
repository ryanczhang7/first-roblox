--!strict
--[[
	The wrong machines TEL-002's controls are aimed at, and the one baseline
	they are each one defect away from.

	THE STORY NAMES ITS CONTROLS (Contract §6): (a) bounce on every
	`PlayerLeft` in any phase, (b) no `departed` guard, (c) `at` from
	`os.clock()`, (d) `join` on every `PlayerJoined` including duplicates, (e)
	`first_round_complete` for every seated player every round. AC-5 and AC-9
	name theirs in the criterion itself. A criterion that names an
	implementation needs an implementation to point at, so the machines below
	really do run a lifecycle - by WRAPPING the real `PhaseMachine`, which the
	story permits, and post-processing what it returns.

	WHY A WRAPPER. In RED the machine emitted nothing, so against it AC-5 and
	every "at most once" half passed vacuously, and the only way to see the
	checks in `TelemetryEmitContract.luau` refuse anything was to hand them a
	machine that emits WRONGLY. The wrapper computes telemetry from
	`(state before, state after, event, now)` and nothing else - the same
	information the real emitter has - and carries the Contract §1 maps on the
	state it returns. It is the SOLE AUTHOR of a stub's telemetry: the real
	machine's own `Emit` effects are dropped (`Deep.controlEffects`) and only
	its control effects and state transitions pass through, so what a stub
	emits is fully determined by its defect flags whether or not the real
	machine emits. The baseline (`emitting`) passes every check; each control
	is that baseline with exactly ONE field of `defects` set, so a control that
	fires is attributable to that one field.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT the production module and it
	is not a sketch of one. GREEN writes the emitters INSIDE
	`src/server/round/PhaseMachine.luau` from the story's Contract §3, against
	the failing tests; a wrapper around `step` cannot ship because the Contract
	says the machine emits, `Effect` gains the variant, and `initial` takes the
	session id. It also has no types beyond `any`.

	`os.clock()` APPEARS BELOW ON PURPOSE. It is control (c). This file is a
	test helper - `.claude/harness/paths.conf` classifies `tests/**` as `test` -
	so `tests/shared/source_guard_test.luau`, which scans `classify.sh --list
	source`, does not see it. A `Clock.real()` would work too; the bare call is
	the shape the story's deferred verification D3 names.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `PhaseMachine` (ROUND-005)
	and `Event` (TEL-001) are merged, so in RED these controls are EXECUTED and
	`tests/server/telemetry_emit_controls_test.luau` records what each one
	actually did rather than what it was expected to do.
]]

local Deep = require("./Deep")
local Event = require("../../src/shared/telemetry/Event")
local PhaseMachine = require("../../src/server/round/PhaseMachine")

local Real: any = PhaseMachine

local TelemetryEmitStubs = {}

--[[
	One field per control, and each one is a single edit to the emitter below.

	  * `bounceInEveryPhase`     - a `PlayerLeft` in Resolution or Post emits
	                               `bounce_before_resolution` instead of
	                               `session_end` (AC-5's named control; D1)
	  * `leaveIgnoresDeparted`   - `PlayerLeft` sets `departed` but never reads
	                               it, so a duplicate departure by a player who
	                               is still seated emits twice (AC-6; D2)
	  * `noDepartedMap`          - the map is neither written nor read anywhere:
	                               D2 taken literally ("remove the departed
	                               guard"), measured for what ELSE it breaks
	  * `realClock`              - `at` from `os.clock()` (AC-9's named
	                               control; D3)
	  * `joinOnEveryJoin`        - `join` on every `PlayerJoined`, accepted or
	                               refused, first or duplicate (AC-1)
	  * `firstRoundForEveryone`  - `first_round_complete` for every seated
	                               player on every resolving step (AC-7)
]]
export type Defects = {
	bounceInEveryPhase: boolean?,
	leaveIgnoresDeparted: boolean?,
	noDepartedMap: boolean?,
	realClock: boolean?,
	joinOnEveryJoin: boolean?,
	firstRoundForEveryone: boolean?,
}

local function isSeated(players: { string }, playerId: string): boolean
	for _, id in players do
		if id == playerId then
			return true
		end
	end
	return false
end

local function makeMachine(defects: Defects): any
	local machine = {}

	function machine.initial(config: any, seed: number, roundId: string, sessionId: string): any
		local state = Real.initial(config, seed, roundId)
		state.sessionId = sessionId
		state.departed = {}
		state.rematched = {}
		state.roundsSeated = {}
		return state
	end

	local function stamp(now: number): number
		if defects.realClock then
			return os.clock()
		end
		return now
	end

	function machine.step(state: any, event: any, now: number): (any, { any })
		local after, effects = Real.step(state, event, now)
		local emits: { any } = {}

		local function emit(name: string, playerId: string?, fields: any)
			table.insert(emits, {
				kind = "Emit",
				event = Event.new(name, stamp(now), state.sessionId, playerId, fields),
			})
		end

		--[[
			`Real.step` returns either the SAME table (an ignored event) or a
			copy whose maps still alias the input's. Purity (ROUND-003 AC-6)
			needs a fresh state with its own maps before anything is written,
			and it needs it exactly once per step.
		]]
		local fresh = false
		local function writable(): any
			if not fresh then
				if after == state then
					after = table.clone(state)
					after.players = table.clone(state.players)
				end
				after.departed = table.clone(state.departed)
				after.rematched = table.clone(state.rematched)
				after.roundsSeated = table.clone(state.roundsSeated)
				fresh = true
			end
			return after
		end

		local function departed(playerId: string): boolean
			if defects.noDepartedMap then
				return false
			end
			return state.departed[playerId] == true
		end

		local playerId: string? = if typeof(event.playerId) == "string" then event.playerId else nil
		local seatedBefore = playerId ~= nil and isSeated(state.players, playerId)

		if event.kind == "PlayerJoined" and playerId ~= nil then
			local accepted = #after.players == #state.players + 1
			if defects.joinOnEveryJoin then
				emit("join", playerId, {})
			end
			if accepted then
				local next = writable()
				if next.roundsSeated[playerId] == nil then
					next.roundsSeated[playerId] = 0
					if not defects.joinOnEveryJoin then
						emit("join", playerId, {})
					end
				end
				if not defects.noDepartedMap then
					next.departed[playerId] = nil -- P2a
				end
			end
		end

		if event.kind == "PlayerLeft" and playerId ~= nil and seatedBefore then
			local consult = not defects.leaveIgnoresDeparted
			if not (consult and departed(playerId)) then
				local next = writable()
				if not defects.noDepartedMap then
					next.departed[playerId] = true
				end
				local phase = state.phase
				local before = phase == "Lobby" or phase == "Assignment" or phase == "Round"
				if before or defects.bounceInEveryPhase then
					emit("bounce_before_resolution", playerId, { phase = phase })
				else
					emit("session_end", playerId, { phase = phase })
				end
			end
		end

		if
			event.kind == "RematchAccepted"
			and playerId ~= nil
			and state.phase == "Post"
			and seatedBefore
		then
			if not departed(playerId) and state.rematched[playerId] ~= true then
				local next = writable()
				next.rematched[playerId] = true
				emit("rematch_accepted", playerId, { roundId = state.roundId })
			end
		end

		if state.phase == "Assignment" and after.phase == "Round" then
			local next = writable()
			for _, id in next.players do
				next.roundsSeated[id] = (next.roundsSeated[id] or 0) + 1
			end
		end

		if state.phase == "Round" and after.phase == "Resolution" then
			local next = writable()
			local outcome = next.outcome
			emit("round_complete", nil, {
				roundId = next.roundId,
				result = outcome.result,
				reason = outcome.reason,
			})
			for _, id in next.players do
				local first = next.roundsSeated[id] == 1
				local gone = if defects.noDepartedMap then false else next.departed[id] == true
				if defects.firstRoundForEveryone or (first and not gone) then
					emit("first_round_complete", id, { roundId = next.roundId, scope = "session" })
				end
			end
		end

		if state.phase == "Post" and after.phase == "Lobby" then
			local next = writable()
			next.departed = {}
			next.rematched = {}
		end

		--[[
			The wrapper is the SOLE author of every stub's telemetry, so each
			defect flag fully determines what is emitted. The real machine's own
			`Emit` effects are dropped here and only its CONTROL effects pass
			through; the wrapper was first measured against a machine that
			emitted nothing, and once the real emitters landed (GREEN, 2026-09-24)
			keeping them made every wrapped machine emit each event twice -
			baseline included, so all seven controls failed on the double `join`
			before reaching their own defect. See `## Regressions` in TEL-002.
		]]
		local combined: { any } = Deep.controlEffects(effects)
		for _, emitEffect in emits do
			table.insert(combined, emitEffect)
		end
		return after, combined
	end

	return machine
end

TelemetryEmitStubs.makeMachine = makeMachine

--[[
	The baseline: the real machine, wrapped, emitting exactly what Contract §3
	says. Every control below is this machine with exactly one defect set.
]]
TelemetryEmitStubs.emitting = makeMachine({})

--[[
	AC-5's control, named in the criterion: bounce on every `PlayerLeft`. "An
	implementation emitting on every PlayerLeft passes AC-4 and must fail this."
	It is also the implementation that ships if nobody writes the phase check.
]]
TelemetryEmitStubs.bouncingEverywhere = makeMachine({ bounceInEveryPhase = true })

--[[
	AC-6's control (b): the `departed` guard is written but never consulted on
	a `PlayerLeft`. A departure in Round unseats, so P1 still refuses the
	duplicate there; a departure in Assignment, Resolution or Post does not,
	and the duplicate emits a second bounce or session_end.
]]
TelemetryEmitStubs.forgetfulLeave = makeMachine({ leaveIgnoresDeparted = true })

--[[
	D2 read literally: the `departed` map removed altogether. Measured rather
	than predicted, because removing the map also lets an Assignment leaver
	collect a `first_round_complete` (AC-7, P3) and a departed player a
	`rematch_accepted` (AC-8).
]]
TelemetryEmitStubs.noDepartedMap = makeMachine({ noDepartedMap = true })

--[[
	AC-9's control, named in the criterion: `at` from a real clock. Every
	shape is right - name, bucket, player, session, fields - so every check
	that drops `at` is green for it, and only AC-9 (and ROUND-003 AC-6's
	determinism, which a real clock also breaks) sees it.
]]
TelemetryEmitStubs.realClock = makeMachine({ realClock = true })

--[[
	AC-1's control (d): `join` on every `PlayerJoined`, whether or not the
	lobby seated anybody.
]]
TelemetryEmitStubs.joiningTwice = makeMachine({ joinOnEveryJoin = true })

--[[
	AC-7's control (e): `first_round_complete` for every seated player on
	every resolving step. In a FIRST round with nobody departed it is
	indistinguishable from the baseline, which is why AC-2 is green for it and
	AC-7 drives a second round and an Assignment leaver.
]]
TelemetryEmitStubs.firstRoundForEveryone = makeMachine({ firstRoundForEveryone = true })

return TelemetryEmitStubs
