--!strict
--[[
	SLICE-003: the pure composition root that connects the phase machine to the
	seating ring (`architecture.md` §9.2, D22). M1's machine emits `AssignSeats`
	and waits for `SeatsAssigned`; M2's `Ring.assign` deals and `Projection`
	says what each seat may know. This module is where they meet, so that "the
	pieces compose" is something a unit test can check. SLICE-005 adds M3: the
	facility `Generator`, the `Procedure` and the `Turn` remote's handler.

	ONE STEP, TWO MACHINE STEPS. `step` feeds the event to `PhaseMachine.step`.
	When that emits `AssignSeats`, the ring is dealt from THE EFFECT'S `players`
	and `Rng.fromSeed(effect.seed)` - never from `round.players`/`round.seed`,
	which are equal today and are not the contract - and the machine is stepped
	again with `SeatsAssigned` at the same `now`, so the state returned is in
	`Round`. `Ring.assign` derives its own `"seats"` stream; nothing here
	derives again.

	THE DEALING STEP GENERATES THE FACILITY from the same effect seed, with the
	state's tuning and (test seam only) `generatorPredicate`. On success the
	Procedure starts at that `now` with the injected config's `roundSeconds`,
	so its deadline and the machine's backstop share one duration (D11), and
	every seated player is placed at the spawn room's centre: `positions` is
	REPLACED and one `Placed` is emitted per player in seat order, each with
	its own table. `tracks` is replaced by exactly the dealt players, each
	`Positions.placed` at the centre with its refusal count carried, so the
	placement is the baseline the next sample is judged from. On failure the machine is stepped a THIRD time, at the same
	`now`, with `RoundResolved{ no_contest, generation_failed }`; seat views are
	still sent, because the ring was dealt.

	`SeatsAssigned` IS INTERNAL. One arriving from outside is ignored before
	the machine sees it: forwarded in `Assignment`, it would move to `Round`
	with no ring dealt.

	`PositionsSampled` AND `TurnRequested` NEVER REACH THE MACHINE. A sample is
	a claim (VIEW-004, §9.8): in every phase each `(playerId, sample)` is
	offered to that player's `Positions` track with the STATE'S tuning walk
	speed, and the batch MERGES - a player absent from it keeps their track.
	`positions` is then exactly the ACCEPTED positions, fresh copies; a player
	with no accepted sample is absent, and so in range of nothing. In `Round`
	only, every player whose refusals have run longer than
	`Positions.RESYNC_SECONDS` is placed back at their last accepted position,
	one `Placed` per player in ascending `playerId`; that is the only effect a
	sample ever emits. A turn in `Round` with a Procedure goes through
	`TurnRequests.handle` against the STORED positions, and the caller alone
	gets a `SendTo` of kind `TurnResult`; anywhere else it is ignored.

	THE MACHINE TAKES A `Tick` BEFORE THE PROCEDURE DOES. Then an undecided
	Procedure is ticked. An outcome that appears in this step - from that tick
	or from a turn - is fed to the machine as `RoundResolved` at the same
	`now`. Reversed, the resolved machine would take the Tick and move on to
	`Post`. Outside `Round` the machine ignores it, which is right when the
	backstop or quorum resolved the round first.

	EACH PLAYER IS SENT ONLY THEIR OWN VIEW. A seat view is a `SendTo`
	addressed to one player with `Projection.forPlayer(assignment, thatPlayer)`
	as its payload. No `Broadcast` ever carries one: the public broadcast is
	the `RoundView`, which holds the phase, the seconds left and who is
	playing, and nothing from the ring.

	A WITHDRAWAL HAPPENS ONLY WHEN THE MACHINE UNSEATED THE LEAVER - they are
	in the old `round.players` and not in the new one, with a ring dealt.
	Today that is a leave in `Round`, including the one that resolves the round
	below quorum. Recipients are the remaining players whose projected view
	CHANGED, in the new ring's seat order, and never the leaver. Every view
	changes today because `seatOrder` shrinks, but the rule is the diff (PO
	decision 2), not "send to everyone".

	THE RING, THE FACILITY AND THE PROCEDURE ARE CLEARED ON ENTERING `Lobby`.
	A stale ring in the next lobby would be withdrawn from, and seat views
	sent, for a round that is over. `positions` and `tracks` are kept: they
	are the last accepted samples, not round state.

	EFFECT ORDER within one step: the machine's pass-through effects (`Emit`,
	`PromptRematch`, `ComputeTrace`) in emission order with `AssignSeats`
	removed; then `Placed` in seat order; then the `SendTo` seat views in seat
	order; then the `SendTo` turn result; then at most one `Broadcast` of the
	`RoundView`, built from the state at the END of the step.

	`secondsLeft` IS RELATIVE. In `Round` with a Procedure it is the
	whole-second ceiling of `Procedure.deadline` minus `now`, so an instability
	penalty shows; elsewhere it is the ceiling of the config's duration minus
	the time spent in the phase. Never an absolute deadline: the server's
	clock is not the client's (§9.7). `nil` where the phase has no running
	clock - `Assignment`, `Resolution`, and a `Lobby` below `playersMin`,
	where the timer holds (§3).

	PURE: nothing handed in is mutated, and the effect list is always a table.
]]

local Generator = require("../facility/Generator")
local MechanicsTuning = require("@shared/MechanicsTuning")
local PhaseMachine = require("../round/PhaseMachine")
local Positions = require("./Positions")
local Procedure = require("../procedure/Procedure")
local Projection = require("../seats/Projection")
local RoundConfig = require("../round/RoundConfig")
local Ring = require("../seats/Ring")
local Rng = require("@shared/Rng")
local TurnRequests = require("../procedure/TurnRequests")

local Session = {}

type Predicate = (Generator.Facility) -> string?

export type SessionOptions = {
	tuning: MechanicsTuning.MechanicsTuning?, -- default: the MechanicsTuning module
	generatorPredicate: Predicate?, -- default: nil (production); a test seam
}

export type SessionState = {
	round: PhaseMachine.RoundState,
	assignment: Ring.Assignment?,
	facility: Generator.Facility?,
	procedure: Procedure.ProcedureState?,
	positions: { [string]: Procedure.Vec }, -- the ACCEPTED positions only
	tracks: { [string]: Positions.Track }, -- each player's plausibility track
	tuning: MechanicsTuning.MechanicsTuning,
	generatorPredicate: Predicate?,
}
-- Later M3 stories add channel (§9.2).

-- `SeatsAssigned` is produced inside `step`; one from outside is ignored (D5).
export type SessionEvent =
	PhaseMachine.Event
	| { kind: "PositionsSampled", samples: { [string]: Procedure.Vec } }
	| { kind: "TurnRequested", playerId: string, args: { machine: number, setting: number } }

-- `VIEW-003` moves this to `src/server/round/RoundView.luau` and widens it.
export type RoundView = {
	phase: PhaseMachine.Phase,
	secondsLeft: number?,
	players: { string }, -- join order, which is seat order once dealt; public
	playersMin: number,
	playersMax: number,
}

export type SessionEffect = {
	kind: "SendTo",
	playerId: string,
	payloadKind: "SeatView",
	payload: Projection.PublicSeatView,
} | {
	kind: "SendTo",
	playerId: string,
	payloadKind: "TurnResult",
	payload: TurnRequests.TurnReply,
} | { kind: "Placed", playerId: string, position: Procedure.Vec } | {
	kind: "Broadcast",
	payloadKind: "RoundView",
	payload: RoundView,
} | PhaseMachine.Effect -- minus AssignSeats, which is consumed here

function Session.new(
	config: RoundConfig.RoundConfig,
	seed: number,
	roundId: string,
	sessionId: string,
	options: SessionOptions?
): SessionState
	local opts: SessionOptions = options or {}
	return {
		round = PhaseMachine.initial(config, seed, roundId, sessionId),
		assignment = nil,
		facility = nil,
		procedure = nil,
		positions = {},
		tracks = {},
		tuning = opts.tuning or MechanicsTuning,
		generatorPredicate = opts.generatorPredicate,
	}
end

local function contains(list: { string }, value: string): boolean
	for _, item in list do
		if item == value then
			return true
		end
	end
	return false
end

local function sameList<T>(a: { T }, b: { T }): boolean
	if #a ~= #b then
		return false
	end
	for index, item in a do
		if b[index] ~= item then
			return false
		end
	end
	return true
end

-- Field by field, over exactly the fields `PublicSeatView` declares.
local function sameView(a: Projection.PublicSeatView, b: Projection.PublicSeatView): boolean
	return a.playerId == b.playerId
		and a.lensClass == b.lensClass
		and a.supplierId == b.supplierId
		and a.dependentId == b.dependentId
		and sameList(a.keyClasses, b.keyClasses)
		and sameList(a.seatOrder, b.seatOrder)
end

local function seatView(assignment: Ring.Assignment, playerId: string): SessionEffect
	return {
		kind = "SendTo",
		playerId = playerId,
		payloadKind = "SeatView",
		payload = Projection.forPlayer(assignment, playerId),
	}
end

local function vec(v: Procedure.Vec): Procedure.Vec
	return { x = v.x, y = v.y, z = v.z }
end

-- A fresh copy of every accepted position; a player never accepted is absent.
local function acceptedPositions(tracks: { [string]: Positions.Track }): { [string]: Procedure.Vec }
	local positions: { [string]: Procedure.Vec } = {}
	for playerId, track in tracks do
		if track.accepted ~= nil then
			positions[playerId] = vec(track.accepted)
		end
	end
	return positions
end

-- The spawn room's centre, per `Machines.luau`'s header (§9.8).
local function spawnCentre(
	facility: Generator.Facility,
	tuning: MechanicsTuning.MechanicsTuning
): Procedure.Vec
	local pitch = tuning.instance.room_pitch_studs
	for _, room in facility.layout.rooms do
		if room.id == facility.spawnRoom then
			return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
		end
	end
	error(`Session: spawn room {facility.spawnRoom} is not in the layout`)
end

-- The whole seconds left in a timed phase, or `nil` where no clock runs.
local function secondsLeftIn(
	round: PhaseMachine.RoundState,
	procedure: Procedure.ProcedureState?,
	now: number
): number?
	local config = round.config
	if round.phase == "Round" and procedure ~= nil then
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

local function roundView(
	round: PhaseMachine.RoundState,
	procedure: Procedure.ProcedureState?,
	now: number
): SessionEffect
	return {
		kind = "Broadcast",
		payloadKind = "RoundView",
		payload = {
			phase = round.phase,
			secondsLeft = secondsLeftIn(round, procedure, now),
			players = table.clone(round.players),
			playersMin = round.config.playersMin,
			playersMax = round.config.playersMax,
		},
	}
end

local function passThrough(into: { SessionEffect }, effects: { PhaseMachine.Effect })
	for _, effect in effects do
		if effect.kind ~= "AssignSeats" then
			table.insert(into, effect)
		end
	end
end

function Session.step(
	state: SessionState,
	event: SessionEvent,
	now: number
): (SessionState, { SessionEffect })
	if event.kind == "SeatsAssigned" then
		return state, {}
	end

	if event.kind == "PositionsSampled" then
		local walkSpeed = state.tuning.instance.walk_speed_studs_per_second
		local tracks: { [string]: Positions.Track } = table.clone(state.tracks)
		for playerId, sample in event.samples do
			tracks[playerId] = (Positions.offer(tracks[playerId], sample, now, walkSpeed))
		end

		local effects: { SessionEffect } = {}
		if state.round.phase == "Round" then
			local due: { string } = {}
			for playerId, track in tracks do
				if Positions.needsResync(track, now) then
					table.insert(due, playerId)
				end
			end
			table.sort(due)
			for _, playerId in due do
				local track = tracks[playerId]
				local at = track.accepted :: Procedure.Vec
				tracks[playerId] = Positions.placed(track, at, now)
				table.insert(effects, { kind = "Placed", playerId = playerId, position = vec(at) })
			end
		end

		local next_ = table.clone(state)
		next_.tracks = tracks
		next_.positions = acceptedPositions(tracks)
		return next_, effects
	end

	local before = state.round
	local round = before
	local assignment = state.assignment
	local facility = state.facility
	local procedure = state.procedure
	local positions = state.positions
	local tracks = state.tracks
	local effects: { SessionEffect } = {}
	local placed: { SessionEffect } = {}
	local sends: { SessionEffect } = {}
	local reply: SessionEffect? = nil
	-- An outcome the Procedure reached in THIS step, to route to the machine.
	local reached: PhaseMachine.Outcome? = nil

	if event.kind == "TurnRequested" then
		if procedure == nil or assignment == nil or round.phase ~= "Round" then
			return state, {}
		end
		local undecided = procedure.outcome == nil
		local turned, result =
			TurnRequests.handle(procedure, assignment, event.playerId, event.args, now, positions)
		procedure = turned
		reply = {
			kind = "SendTo",
			playerId = event.playerId,
			payloadKind = "TurnResult",
			payload = TurnRequests.reply(result),
		}
		if undecided and turned.outcome ~= nil then
			reached = turned.outcome
		end
	else
		local machineEffects
		round, machineEffects = PhaseMachine.step(before, event, now)
		passThrough(effects, machineEffects)

		local deal: PhaseMachine.Effect? = nil
		for _, effect in machineEffects do
			if effect.kind == "AssignSeats" then
				deal = effect
			end
		end

		if deal ~= nil and deal.kind == "AssignSeats" then
			local dealt = Ring.assign(deal.players, Rng.fromSeed(deal.seed))
			local seated, seatedEffects = PhaseMachine.step(round, { kind = "SeatsAssigned" }, now)
			round = seated
			passThrough(effects, seatedEffects)
			for _, playerId in dealt.players do
				table.insert(sends, seatView(dealt, playerId))
			end
			assignment = dealt

			local generated =
				Generator.generate(dealt, deal.seed, state.tuning, state.generatorPredicate)
			if generated.kind == "facility" then
				facility = generated.facility
				procedure = Procedure.start(
					generated.facility,
					now,
					state.tuning,
					deal.seed,
					round.config.roundSeconds
				)
				local centre = spawnCentre(generated.facility, state.tuning)
				positions = {}
				tracks = {}
				for _, playerId in dealt.players do
					positions[playerId] = vec(centre)
					tracks[playerId] = Positions.placed(state.tracks[playerId], centre, now)
					table.insert(
						placed,
						{ kind = "Placed", playerId = playerId, position = vec(centre) }
					)
				end
			else
				facility = nil
				procedure = nil
				local resolved, resolvedEffects = PhaseMachine.step(round, {
					kind = "RoundResolved",
					outcome = { result = "no_contest", reason = "generation_failed" },
				}, now)
				round = resolved
				passThrough(effects, resolvedEffects)
			end
		elseif
			event.kind == "PlayerLeft"
			and assignment ~= nil
			and contains(before.players, event.playerId)
			and not contains(round.players, event.playerId)
		then
			local old = assignment
			local withdrawn = Ring.withdraw(old, event.playerId)
			for _, playerId in withdrawn.players do
				local fresh = Projection.forPlayer(withdrawn, playerId)
				if not sameView(fresh, Projection.forPlayer(old, playerId)) then
					table.insert(sends, {
						kind = "SendTo",
						playerId = playerId,
						payloadKind = "SeatView",
						payload = fresh,
					})
				end
			end
			assignment = withdrawn
		end

		-- After the machine has taken the Tick, never before (C-3).
		if
			event.kind == "Tick"
			and procedure ~= nil
			and procedure.outcome == nil
			and assignment ~= nil
		then
			local ticked = Procedure.tick(procedure, assignment, now, positions)
			procedure = ticked
			reached = ticked.outcome
		end
	end

	if reached ~= nil then
		local resolved, resolvedEffects = PhaseMachine.step(
			round,
			{ kind = "RoundResolved", outcome = table.clone(reached) },
			now
		)
		round = resolved
		passThrough(effects, resolvedEffects)
	end

	if round.phase == "Lobby" and before.phase ~= "Lobby" then
		assignment = nil
		facility = nil
		procedure = nil
	end

	for _, effect in placed do
		table.insert(effects, effect)
	end
	for _, send in sends do
		table.insert(effects, send)
	end
	if reply ~= nil then
		table.insert(effects, reply)
	end

	local timed = round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post"
	if
		round.phase ~= before.phase
		or #round.players ~= #before.players
		or (event.kind == "Tick" and timed)
	then
		table.insert(effects, roundView(round, procedure, now))
	end

	return {
		round = round,
		assignment = assignment,
		facility = facility,
		procedure = procedure,
		positions = positions,
		tracks = tracks,
		tuning = state.tuning,
		generatorPredicate = state.generatorPredicate,
	},
		effects
end

return Session
