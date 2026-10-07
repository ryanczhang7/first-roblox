--!strict
--[[
	The stand-in sessions SLICE-005's and VIEW-004's controls are aimed at,
	and the reference each of them is a single defect away from. Moved here
	from `tests/server/session_round_controls_test.luau` by VIEW-004 so that
	`tests/server/positions_controls_test.luau` can aim the same stand-ins at
	the session-level checks in `PositionsContract.luau`.

	`standIn(defects)` is a small implementation of the Contract (SLICE-003's
	behaviour, SLICE-005's C-2..C-5, VIEW-004's Positions wiring) with named
	defects switched on. With none it is the REFERENCE, the positive control.
	Each control is the reference with EXACTLY ONE defect, and pins the set of
	checks that fire EXACTLY.

	THE PLAUSIBILITY RULE IS INJECTED. `defects.positions` is the Positions
	module the stand-in composes - `PositionsStubs.reference` by default, or
	any one-defect module from `PositionsStubs.luau` (D-1's tolerance, D-2's
	exclusive bound, D-4's refuse-everything, D-5's inclusive resync), so a
	defect in the rule can be aimed at the session-level checks and the
	scripted rounds without a second copy of the rule. The session defects
	below are the wiring's own: raw samples stored past the rule (D-3's
	shape), a replacing store (today's Session), a resync that never fires,
	fires everywhere, places at the sample, descends, or also broadcasts, a
	deal that keeps stale tracks or drops the refusal counts, a `new` with no
	`tracks`, a walk speed read from the shipped tuning, aliased positions.

	WHAT THE REFERENCE IS NOT: `src/server/session/Session.luau`, or a sketch
	of one. GREEN writes the module from the story's Contract; nothing here is
	to be copied.
]]

local Deep = require("./Deep")
local Generator = require("../../src/server/facility/Generator")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local PhaseMachine = require("../../src/server/round/PhaseMachine")
local PositionsStubs = require("./PositionsStubs")
local Procedure = require("../../src/server/procedure/Procedure")
local Projection = require("../../src/server/seats/Projection")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/shared/Rng")
local RoundViewStubs = require("./RoundViewStubs")
local ScriptedRound = require("./ScriptedRound")
local TurnRequests = require("../../src/server/procedure/TurnRequests")

local SessionRoundStubs = {}

export type Defects = {
	-- Routing (SLICE-005 C-3 step 5)
	routesTickOutcomeOnNextTickOnly: boolean?, -- feeds RoundResolved one tick late
	skipsRoutingOnTick: boolean?, -- D-1's shape: a Tick never feeds RoundResolved
	skipsRoutingOnTurn: boolean?, -- D-2's shape: a turn never feeds it; the next Tick does
	procedureBeforeMachine: boolean?, -- the Procedure ticked before the machine takes the Tick
	-- C-5
	secondsLeftFromConfig: boolean?, -- D-3's shape
	-- AC-3 (SLICE-005)
	turnsWithEmptyPositions: boolean?, -- passes {} to the turn
	turnsWithPlacedPositions: boolean?, -- passes the Placed centres, ignoring every sample
	sendsTurnResultToEveryone: boolean?,
	broadcastsOnEveryTurn: boolean?,
	-- Samples (VIEW-004)
	positions: any?, -- the Positions module composed; PositionsStubs.reference by default
	storesRawSamples: boolean?, -- D-3's shape: every sample stored as the position, past the rule
	replacesSamples: boolean?, -- today's Session: the batch replaces the accepted positions
	storesSamplesByReference: boolean?, -- positions[p] IS event.samples[p]
	noResync: boolean?, -- needsResync never consulted
	resyncEverywhere: boolean?, -- resync in every phase, Lobby included
	resyncAtTheSample: boolean?, -- places at the refused sample rather than the accepted position
	resyncDescending: boolean?, -- Placed in descending playerId
	resyncAlsoBroadcasts: boolean?, -- a RoundView after the Placed effects
	resyncAliasesPosition: boolean?, -- Placed.position IS state.positions[p]
	dealKeepsOldTracks: boolean?, -- the deal places into the old tracks rather than replacing them
	dealDropsRefusals: boolean?, -- the deal starts every track from nil
	tracksMissingFromNew: boolean?, -- new omits tracks
	walkSpeedFromShippedTuning: boolean?, -- MechanicsTuning rather than state.tuning
	-- AC-1 (SLICE-005)
	generatesFromTheSessionSeed: boolean?, -- every round from the initial seed
	generatesFromAFixedSeed: boolean?, -- seed 0
	placesAtTheFirstMachine: boolean?, -- the wrong place
	aliasesPlacedPositions: boolean?, -- one centre table for every Placed and state.positions
	startsTheProcedureAtTimeZero: boolean?,
	-- AC-2 (SLICE-005)
	ignoresThePredicate: boolean?,
	staysInRoundOnGenerationFailure: boolean?,
	-- Clearing
	keepsFacilityAndProcedureInLobby: boolean?,
	-- SLICE-003's pass-through, on a session that emits Placed (D-4's shape)
	dropsEmits: boolean?,
	-- Purity
	mutatesStateOnSample: boolean?, -- writes the new positions into the input state
	mutatesTurnEvent: boolean?, -- marks the TurnRequested's args handled
}

local function contains(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local function vec(v: any): any
	return { x = v.x, y = v.y, z = v.z }
end

function SessionRoundStubs.standIn(defects: Defects): any
	local S = {}
	local initialSeed = 0
	local P: any = defects.positions or PositionsStubs.reference

	-- SLICE-006 C-2: ports is the fifth argument, options the sixth. This
	-- stand-in is SLICE-005's and reads neither port; `SessionChannelStubs`
	-- wraps it with the channel, the views and the port.
	function S.new(
		config: any,
		seed: number,
		roundId: string,
		sessionId: string,
		_ports: any,
		options: any?
	): any
		initialSeed = seed
		local state: any = {
			round = PhaseMachine.initial(config, seed, roundId, sessionId),
			assignment = nil,
			facility = nil,
			procedure = nil,
			positions = {},
			tracks = {},
			tuning = if options and options.tuning then options.tuning else MechanicsTuning,
			generatorPredicate = if options then options.generatorPredicate else nil,
		}
		if defects.tracksMissingFromNew then
			state.tracks = nil
		end
		return state
	end

	local function seatView(assignment: any, p: string): any
		return {
			kind = "SendTo",
			playerId = p,
			payloadKind = "SeatView",
			payload = Projection.forPlayer(assignment, p),
		}
	end

	local function pass(into: { any }, effects: { any })
		for _, e in effects do
			if e.kind == "AssignSeats" or (defects.dropsEmits and e.kind == "Emit") then
				continue
			end
			table.insert(into, e)
		end
	end

	-- The accepted positions, fresh, from the tracks.
	local function acceptedOf(tracks: any): any
		local positions: any = {}
		for p, track in tracks do
			if track.accepted ~= nil then
				positions[p] = vec(track.accepted)
			end
		end
		return positions
	end

	local function next_(
		state: any,
		round: any,
		assignment: any,
		facility: any,
		procedure: any,
		positions: any,
		tracks: any
	): any
		return {
			round = round,
			assignment = assignment,
			facility = facility,
			procedure = procedure,
			positions = positions,
			tracks = tracks,
			tuning = state.tuning,
			generatorPredicate = state.generatorPredicate,
		}
	end

	local function secondsLeft(_state: any, round: any, procedure: any, now: number): number?
		local config = round.config
		if round.phase == "Round" and procedure ~= nil and not defects.secondsLeftFromConfig then
			return math.ceil(Procedure.deadline(procedure) - now)
		end
		local duration: number? = nil
		if round.phase == "Lobby" and #round.players >= config.playersMin then
			duration = config.lobbySeconds
		elseif round.phase == "Round" then
			duration = config.roundSeconds
		elseif round.phase == "Post" then
			duration = config.postRoundSeconds
		end
		if duration == nil then
			return nil
		end
		return math.ceil(duration - (now - round.phaseEnteredAt))
	end

	-- VIEW-003 (C-1, C-10): the ten-key view, built by the reference view
	-- builder from the END-state pieces, with this stand-in's own secondsLeft
	-- (so `secondsLeftFromConfig` still reaches the payload) and pings = {}
	-- as Session sends until SLICE-006.
	local function roundView(
		state: any,
		round: any,
		procedure: any,
		assignment: any,
		positions: any,
		now: number
	): any
		local payload = RoundViewStubs.reference.public({
			round = round,
			procedure = procedure,
			assignment = assignment,
			positions = positions,
			pings = {},
			tuning = state.tuning,
		}, now)
		payload.secondsLeft = secondsLeft(state, round, procedure, now)
		return {
			kind = "Broadcast",
			payloadKind = "RoundView",
			payload = payload,
		}
	end

	local placedMap: { [string]: any } = {}

	function S.step(state: any, event: any, now: number): (any, { any })
		if event.kind == "SeatsAssigned" then
			return state, {}
		end
		if event.kind == "PositionsSampled" then
			local walkSpeed = if defects.walkSpeedFromShippedTuning
				then MechanicsTuning.instance.walk_speed_studs_per_second
				else state.tuning.instance.walk_speed_studs_per_second
			local tracks = table.clone(state.tracks or {})
			local positions: any
			if defects.replacesSamples then
				positions = {}
			else
				positions = Deep.copy(state.positions)
			end
			for p, v in event.samples do
				local track, ok = P.offer(tracks[p], v, now, walkSpeed)
				tracks[p] = track
				if ok or defects.storesRawSamples then
					positions[p] = if defects.storesSamplesByReference then v else vec(v)
				elseif defects.replacesSamples and track.accepted ~= nil then
					positions[p] = vec(track.accepted)
				end
			end
			local effects: { any } = {}
			local resyncHere = if defects.resyncEverywhere
				then true
				else state.round.phase == "Round"
			if resyncHere and not defects.noResync then
				local due: { string } = {}
				for p, track in tracks do
					if P.needsResync(track, now) then
						table.insert(due, p)
					end
				end
				table.sort(due, function(a: string, b: string): boolean
					return if defects.resyncDescending then a > b else a < b
				end)
				for _, p in due do
					local at = if defects.resyncAtTheSample and event.samples[p] ~= nil
						then event.samples[p]
						else tracks[p].accepted
					tracks[p] = P.placed(tracks[p], at, now)
					local stored = vec(at)
					positions[p] = stored
					table.insert(effects, {
						kind = "Placed",
						playerId = p,
						position = if defects.resyncAliasesPosition then stored else vec(at),
					})
				end
				if #due > 0 and defects.resyncAlsoBroadcasts then
					table.insert(
						effects,
						roundView(
							state,
							state.round,
							state.procedure,
							state.assignment,
							positions,
							now
						)
					)
				end
			end
			if defects.mutatesStateOnSample then
				state.positions = positions
			end
			return next_(
				state,
				state.round,
				state.assignment,
				state.facility,
				state.procedure,
				positions,
				tracks
			),
				effects
		end
		if event.kind == "TurnRequested" then
			if defects.mutatesTurnEvent then
				event.args.handled = true
			end
			if state.procedure == nil or state.round.phase ~= "Round" then
				return state, {}
			end
			local positions = state.positions
			if defects.turnsWithEmptyPositions then
				positions = {}
			elseif defects.turnsWithPlacedPositions then
				positions = placedMap
			end
			local procedure, result = TurnRequests.handle(
				state.procedure,
				state.assignment,
				event.playerId,
				event.args,
				now,
				positions
			)
			local round = state.round
			local effects: { any } = {}
			if
				state.procedure.outcome == nil
				and procedure.outcome ~= nil
				and not defects.skipsRoutingOnTurn
			then
				local resolved, more = PhaseMachine.step(
					round,
					{ kind = "RoundResolved", outcome = procedure.outcome },
					now
				)
				round = resolved
				pass(effects, more)
			end
			local reply = TurnRequests.reply(result)
			if defects.sendsTurnResultToEveryone then
				for _, p in state.assignment.players do
					table.insert(effects, {
						kind = "SendTo",
						playerId = p,
						payloadKind = "TurnResult",
						payload = reply,
					})
				end
			else
				table.insert(effects, {
					kind = "SendTo",
					playerId = event.playerId,
					payloadKind = "TurnResult",
					payload = reply,
				})
			end
			if round.phase ~= state.round.phase or defects.broadcastsOnEveryTurn then
				table.insert(
					effects,
					roundView(state, round, procedure, state.assignment, state.positions, now)
				)
			end
			return next_(
				state,
				round,
				state.assignment,
				state.facility,
				procedure,
				state.positions,
				state.tracks
			),
				effects
		end

		local before = state.round
		local assignment, facility, procedure, positions, tracks =
			state.assignment, state.facility, state.procedure, state.positions, state.tracks
		local effects: { any } = {}
		local tickedEarly = false

		-- Defect: the Procedure first, then the machine.
		if
			defects.procedureBeforeMachine
			and event.kind == "Tick"
			and procedure ~= nil
			and procedure.outcome == nil
		then
			procedure = Procedure.tick(procedure, assignment, now, positions)
			tickedEarly = true
			if procedure.outcome ~= nil then
				local resolved, more = PhaseMachine.step(
					before,
					{ kind = "RoundResolved", outcome = procedure.outcome },
					now
				)
				before = resolved
				pass(effects, more)
			end
		end

		local round, machineEffects = PhaseMachine.step(before, event, now)
		pass(effects, machineEffects)
		local placed: { any } = {}
		local sends: { any } = {}

		local deal: any = nil
		for _, e in machineEffects do
			if e.kind == "AssignSeats" then
				deal = e
			end
		end

		if deal ~= nil then
			local dealt = Ring.assign(deal.players, Rng.fromSeed(deal.seed))
			local seated, more = PhaseMachine.step(round, { kind = "SeatsAssigned" }, now)
			round = seated
			pass(effects, more)
			assignment = dealt
			local genSeed = if defects.generatesFromTheSessionSeed
				then initialSeed
				elseif defects.generatesFromAFixedSeed then 0
				else deal.seed
			local predicate = if defects.ignoresThePredicate then nil else state.generatorPredicate
			local result = Generator.generate(dealt, genSeed, state.tuning, predicate)
			if result.kind == "facility" then
				facility = result.facility
				procedure = Procedure.start(
					facility,
					if defects.startsTheProcedureAtTimeZero then 0 else now,
					state.tuning,
					deal.seed,
					round.config.roundSeconds
				)
				local centre = ScriptedRound.spawnCentre(facility, state.tuning)
				if defects.placesAtTheFirstMachine then
					centre = Machines.positionOf(
						facility.layout,
						facility.placement.machines[1],
						state.tuning
					)
				end
				local old = state.tracks or {}
				tracks = if defects.dealKeepsOldTracks then table.clone(old) else {}
				placedMap = {}
				for _, p in dealt.players do
					tracks[p] =
						P.placed(if defects.dealDropsRefusals then nil else old[p], centre, now)
					placedMap[p] = vec(centre)
				end
				positions = acceptedOf(tracks)
				for _, p in dealt.players do
					if defects.aliasesPlacedPositions then
						positions[p] = centre
					end
					table.insert(placed, {
						kind = "Placed",
						playerId = p,
						position = if defects.aliasesPlacedPositions then centre else vec(centre),
					})
				end
			elseif not defects.staysInRoundOnGenerationFailure then
				local resolved, third = PhaseMachine.step(round, {
					kind = "RoundResolved",
					outcome = { result = "no_contest", reason = "generation_failed" },
				}, now)
				round = resolved
				pass(effects, third)
			end
			for _, p in dealt.players do
				table.insert(sends, seatView(dealt, p))
			end
		elseif
			event.kind == "PlayerLeft"
			and assignment ~= nil
			and contains(before.players, event.playerId)
			and not contains(round.players, event.playerId)
		then
			local old = assignment
			local withdrawn = Ring.withdraw(old, event.playerId)
			for _, p in withdrawn.players do
				if
					not Deep.equal(Projection.forPlayer(withdrawn, p), Projection.forPlayer(old, p))
				then
					table.insert(sends, seatView(withdrawn, p))
				end
			end
			assignment = withdrawn
		end

		if event.kind == "Tick" and procedure ~= nil and not tickedEarly then
			if defects.routesTickOutcomeOnNextTickOnly or defects.skipsRoutingOnTurn then
				-- An outcome already held (from an earlier tick or an unrouted
				-- turn) is fed now, late.
				if procedure.outcome ~= nil and round.phase == "Round" then
					local resolved, more = PhaseMachine.step(
						round,
						{ kind = "RoundResolved", outcome = procedure.outcome },
						now
					)
					round = resolved
					pass(effects, more)
				end
			end
			if procedure.outcome == nil then
				local ticked = Procedure.tick(procedure, assignment, now, positions)
				if
					ticked.outcome ~= nil
					and not defects.skipsRoutingOnTick
					and not defects.routesTickOutcomeOnNextTickOnly
				then
					local resolved, more = PhaseMachine.step(
						round,
						{ kind = "RoundResolved", outcome = ticked.outcome },
						now
					)
					round = resolved
					pass(effects, more)
				end
				procedure = ticked
			end
		end

		if round.phase == "Lobby" and before.phase ~= "Lobby" then
			assignment = nil
			if not defects.keepsFacilityAndProcedureInLobby then
				facility = nil
				procedure = nil
			end
		end

		for _, e in placed do
			table.insert(effects, e)
		end
		for _, e in sends do
			table.insert(effects, e)
		end
		local timed = round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post"
		if
			round.phase ~= before.phase
			or #round.players ~= #before.players
			or (event.kind == "Tick" and timed)
		then
			table.insert(effects, roundView(state, round, procedure, assignment, positions, now))
		end
		return next_(state, round, assignment, facility, procedure, positions, tracks), effects
	end

	return S
end

SessionRoundStubs.reference = SessionRoundStubs.standIn({})

return SessionRoundStubs
