--!strict
--[[
	SLICE-003: the pure composition root that connects the phase machine to the
	seating ring (`architecture.md` §9.2, D22). M1's machine emits `AssignSeats`
	and waits for `SeatsAssigned`; M2's `Ring.assign` deals and `Projection`
	says what each seat may know. This module is where they meet, so that "the
	pieces compose" is something a unit test can check. SLICE-005 adds M3: the
	facility `Generator`, the `Procedure` and the `Turn` remote's handler.
	SLICE-006 adds the channel (`Pings`, `PresetSends`), the per-player views
	(`Projection.lensFor`, `turnCuesFor`) and the public `FacilityView`.

	PORTS ARE REQUIRED. `new(config, seed, roundId, sessionId, ports,
	options?)` raises unless `ports.lineOfSight` is a function: a defaulted
	always-true sight would let a lens read through walls the day a caller
	forgot it. `options` (`tuning`, `generatorPredicate`) is the sixth
	argument.

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
	one `Placed` per player in ascending `playerId`. A sample does not return
	early: a lens changes when its holder walks, so the views below are built
	after it like after any step. A turn in `Round` with a Procedure goes through
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
	the `RoundView` (VIEW-003, `round/RoundView.luau`), which holds only public
	facts - the phase, the seconds left, who is playing, the progress bar,
	instability, dark rooms, pings and each machine's public dial - and
	nothing from the ring.

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

	THE CHANNEL. A `PingRequested`, in any phase, is judged by `Pings.request`
	against the stored positions and the sight port - with no procedure
	outside `Round`, so there it is always `no_such_target`. A refusal goes to
	the sender alone as `PingRefused` (`request` has declined the call); an
	accepted ping is `Pings.accept`ed at `Pings.targetPosition`, lit unless
	`Procedure.isDark` says the machine's room is dark (a doorway is lit), and
	sends nothing itself: the `RoundView` shows it. Every `Tick` expires pings,
	and a machine committed in this step clears its pings. A `PresetSent`
	carries the driver's filter answer (`filtered`; the real filter yields, so
	it is not a port) and `PresetSends.send` is handed a non-yielding filter
	that returns it, so that module's own order still holds. A shown preset is
	one `Broadcast` at the sender's STORED position; a failed one goes to the
	sender alone. A sender with no stored position is declined and nothing
	else happens. The channel is replaced by a fresh one on entering `Lobby`,
	and kept through `Resolution` and `Post` for the trace.

	THE FACILITY VIEW is broadcast once, on the dealing step, when generation
	succeeded: the public map the clients draw (`RoundView.facility`).

	VIEWS ARE SENT WHEN THEY CHANGE. At the end of every step in `Round`, with
	a procedure, each seated player's `LensView` and `TurnCues` are built from
	the end state and each is sent, to that player alone, unless it is
	deep-equal to the last one sent to them (`state.sent`). The first of a
	round is always sent, because `sent` is emptied on the deal and on entering
	`Lobby`; a player no longer seated loses their entries. The `RoundView` is
	broadcast when SLICE-003's trigger fires - the phase or the player count
	changed, or a `Tick` in a timed phase - or when the view differs from the
	last one broadcast, `secondsLeft` aside: the clock moves on every step and
	the per-second `Tick` already carries it. No `Broadcast` carries a private
	view.

	EFFECT ORDER within one step: the machine's pass-through effects (`Emit`,
	`PromptRematch`, `ComputeTrace`) in emission order with `AssignSeats`
	removed; then `Placed` in seat order (or ascending `playerId` on a resync);
	then the `SendTo` seat views in seat order; then the `FacilityView`; then
	the reply to the caller (`TurnResult`, `PingRefused` or `PresetFailed`);
	then the `PresetShown`; then, per player in seat order, their `LensView`
	and their `TurnCues`; then at most one `Broadcast` of the `RoundView`,
	built by `RoundView.public` from the state at the END of the step, with
	`Pings.shown` in `Round` and no pings elsewhere. `secondsLeft` and every
	other field's rule live in that module.

	PURE: nothing handed in is mutated, and the effect list is always a table.
]]

local Generator = require("../facility/Generator")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Pings = require("../channel/Pings")
local PhaseMachine = require("../round/PhaseMachine")
local Positions = require("./Positions")
local PresetSends = require("../channel/PresetSends")
local Procedure = require("../procedure/Procedure")
local Projection = require("../seats/Projection")
local RoundConfig = require("../round/RoundConfig")
local RoundView = require("../round/RoundView")
local Ring = require("../seats/Ring")
local Rng = require("@game/ReplicatedStorage/Shared/Rng")
local TurnRequests = require("../procedure/TurnRequests")

local Session = {}

type Predicate = (Generator.Facility) -> string?

export type SessionOptions = {
	tuning: MechanicsTuning.MechanicsTuning?, -- default: the MechanicsTuning module
	generatorPredicate: Predicate?, -- default: nil (production); a test seam
}

export type SessionPorts = {
	lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean,
}

-- The driver's answer from the yielding text filter (§9.5.1).
export type FilterResult = { ok: true, text: string } | { ok: false }

export type ChannelState = { presets: PresetSends.PresetState, pings: Pings.PingState }

-- The last value sent to each audience.
export type Sent = {
	roundView: RoundView.RoundView?,
	lens: { [string]: Projection.LensView },
	cues: { [string]: Projection.TurnCues },
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
	channel: ChannelState,
	sent: Sent,
	ports: SessionPorts,
}

-- `SeatsAssigned` is produced inside `step`; one from outside is ignored (D5).
export type SessionEvent =
	PhaseMachine.Event
	| { kind: "PositionsSampled", samples: { [string]: Procedure.Vec } }
	| { kind: "TurnRequested", playerId: string, args: { machine: number, setting: number } }
	| {
		kind: "PresetSent",
		playerId: string,
		presetId: number,
		filtered: FilterResult,
		call: PresetSends.CallControl,
	}
	| {
		kind: "PingRequested",
		playerId: string,
		target: Pings.PingTarget,
		call: Pings.CallControl,
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
} | {
	kind: "SendTo",
	playerId: string,
	payloadKind: "LensView",
	payload: Projection.LensView,
} | {
	kind: "SendTo",
	playerId: string,
	payloadKind: "TurnCues",
	payload: Projection.TurnCues,
} | {
	kind: "SendTo",
	playerId: string,
	payloadKind: "PingRefused",
	payload: Pings.PingRefused,
} | {
	kind: "SendTo",
	playerId: string,
	payloadKind: "PresetFailed",
	payload: PresetSends.PresetFailed,
} | {
	kind: "Placed",
	playerId: string,
	position: Procedure.Vec,
} | {
	kind: "Broadcast",
	payloadKind: "RoundView",
	payload: RoundView.RoundView,
} | {
	kind: "Broadcast",
	payloadKind: "PresetShown",
	payload: PresetSends.PresetShown,
} | {
	kind: "Broadcast",
	payloadKind: "FacilityView",
	payload: RoundView.FacilityView,
} | PhaseMachine.Effect -- minus AssignSeats, which is consumed here

local function freshChannel(): ChannelState
	return { presets = PresetSends.new(), pings = Pings.new() }
end

function Session.new(
	config: RoundConfig.RoundConfig,
	seed: number,
	roundId: string,
	sessionId: string,
	ports: SessionPorts,
	options: SessionOptions?
): SessionState
	if typeof(ports) ~= "table" or typeof(ports.lineOfSight) ~= "function" then
		error("Session.new: ports.lineOfSight must be a function (no default sight)", 2)
	end
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
		channel = freshChannel(),
		sent = { roundView = nil, lens = {}, cues = {} },
		ports = ports,
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

-- Structural equality over plain data: the views are tables of tables of
-- numbers, strings and booleans. An absent value equals only an absent one.
local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- C-6 as amended: the clock is not a change. `secondsLeft` moves with `now`
-- on every step, and the per-second Tick already carries it.
local function sameRoundView(a: RoundView.RoundView, b: RoundView.RoundView?): boolean
	if b == nil then
		return false
	end
	local x = table.clone(a)
	local y = table.clone(b)
	x.secondsLeft = nil
	y.secondsLeft = nil
	return deepEqual(x, y)
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

-- Whether a ping's target is in a lit room: a setting or machine ping is
-- judged by its machine's room, and a doorway is always lit.
local function targetLit(procedure: Procedure.ProcedureState, target: Pings.PingTarget): boolean
	if target.kind == "doorway" then
		return true
	end
	for _, machine in procedure.facility.placement.machines do
		if machine.id == target.target then
			return not Procedure.isDark(procedure, machine.room)
		end
	end
	return true
end

local function passThrough(into: { SessionEffect }, effects: { PhaseMachine.Effect })
	for _, effect in effects do
		if effect.kind ~= "AssignSeats" then
			table.insert(into, effect)
		end
	end
end

-- Entries of players still in `players`, so a leaver is never compared against.
local function seatedOnly<T>(entries: { [string]: T }, players: { string }): { [string]: T }
	local kept: { [string]: T } = {}
	for playerId, value in entries do
		if contains(players, playerId) then
			kept[playerId] = value
		end
	end
	return kept
end

function Session.step(
	state: SessionState,
	event: SessionEvent,
	now: number
): (SessionState, { SessionEffect })
	if event.kind == "SeatsAssigned" then
		return state, {}
	end

	local before = state.round
	local round = before
	local assignment = state.assignment
	local facility = state.facility
	local procedure = state.procedure
	local positions = state.positions
	local tracks = state.tracks
	local channel = state.channel
	local effects: { SessionEffect } = {}
	local placed: { SessionEffect } = {}
	local sends: { SessionEffect } = {}
	local facilityView: SessionEffect? = nil
	local reply: SessionEffect? = nil
	local shown: SessionEffect? = nil
	local dealt = false
	-- An outcome the Procedure reached in THIS step, to route to the machine.
	local reached: PhaseMachine.Outcome? = nil

	if event.kind == "PositionsSampled" then
		local walkSpeed = state.tuning.instance.walk_speed_studs_per_second
		tracks = table.clone(state.tracks)
		for playerId, sample in event.samples do
			tracks[playerId] = (Positions.offer(tracks[playerId], sample, now, walkSpeed))
		end

		if round.phase == "Round" then
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
				table.insert(placed, { kind = "Placed", playerId = playerId, position = vec(at) })
			end
		end
		positions = acceptedPositions(tracks)
	elseif event.kind == "TurnRequested" then
		if procedure ~= nil and assignment ~= nil and round.phase == "Round" then
			local undecided = procedure.outcome == nil
			local turned, result = TurnRequests.handle(
				procedure,
				assignment,
				event.playerId,
				event.args,
				now,
				positions
			)
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
		end
	elseif event.kind == "PingRequested" then
		local judged = if round.phase == "Round" then procedure else nil
		local refused = Pings.request(
			judged,
			positions,
			event.playerId,
			event.target,
			event.call,
			state.ports.lineOfSight
		)
		if refused ~= nil then
			reply = {
				kind = "SendTo",
				playerId = event.playerId,
				payloadKind = "PingRefused",
				payload = refused,
			}
		elseif judged ~= nil then
			local at = Pings.targetPosition(judged, event.target) :: Procedure.Vec
			channel = {
				presets = channel.presets,
				pings = Pings.accept(
					channel.pings,
					event.playerId,
					event.target,
					at,
					now,
					targetLit(judged, event.target)
				),
			}
		end
	elseif event.kind == "PresetSent" then
		local position = positions[event.playerId]
		if position == nil then
			-- PO-4: nothing to show it at, and inventing a place would be a lie.
			event.call.decline()
			return state, {}
		end
		local filtered = event.filtered
		local function filter(_senderId: string, _word: string): (boolean, string?)
			if filtered.ok == true then
				return true, filtered.text
			end
			return false, nil
		end
		local presets, result = PresetSends.send(
			channel.presets,
			event.playerId,
			event.presetId,
			round.phase,
			position,
			now,
			filter,
			event.call
		)
		channel = { presets = presets, pings = channel.pings }
		if result.kind == "shown" then
			shown = { kind = "Broadcast", payloadKind = "PresetShown", payload = result.shown }
		else
			reply = {
				kind = "SendTo",
				playerId = event.playerId,
				payloadKind = "PresetFailed",
				payload = result.failed,
			}
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
			local ring = Ring.assign(deal.players, Rng.fromSeed(deal.seed))
			local seated, seatedEffects = PhaseMachine.step(round, { kind = "SeatsAssigned" }, now)
			round = seated
			passThrough(effects, seatedEffects)
			for _, playerId in ring.players do
				table.insert(sends, seatView(ring, playerId))
			end
			assignment = ring

			local generated =
				Generator.generate(ring, deal.seed, state.tuning, state.generatorPredicate)
			if generated.kind == "facility" then
				dealt = true
				facility = generated.facility
				facilityView = {
					kind = "Broadcast",
					payloadKind = "FacilityView",
					payload = RoundView.facility(generated.facility),
				}
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
				for _, playerId in ring.players do
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

	-- The pings' clock, in every phase, before any view is built (C-4).
	if event.kind == "Tick" then
		channel =
			{ presets = channel.presets, pings = Pings.tick(channel.pings, now, state.tuning) }
	end
	-- A machine committed in this step - by a turn or a tick - clears its pings.
	local previous = state.procedure
	if previous ~= nil and procedure ~= nil then
		for id, committed in procedure.committed do
			if committed == true and previous.committed[id] ~= true then
				channel =
					{ presets = channel.presets, pings = Pings.onCommitted(channel.pings, id) }
			end
		end
	end

	local enteredLobby = round.phase == "Lobby" and before.phase ~= "Lobby"
	if enteredLobby then
		assignment = nil
		facility = nil
		procedure = nil
		channel = freshChannel()
	end

	-- The private views (C-6): each sent to its player alone, iff it changed.
	local lastLens = state.sent.lens
	local lastCues = state.sent.cues
	if dealt or enteredLobby then
		lastLens = {}
		lastCues = {}
	end
	local private: { SessionEffect } = {}
	if round.phase == "Round" and procedure ~= nil and assignment ~= nil then
		local lens: { [string]: Projection.LensView } = {}
		local cues: { [string]: Projection.TurnCues } = {}
		for _, playerId in assignment.players do
			local lensView = Projection.lensFor(
				assignment,
				procedure,
				playerId,
				positions[playerId],
				state.ports.lineOfSight
			)
			local turnCues = Projection.turnCuesFor(assignment, procedure, playerId)
			if not deepEqual(lensView, lastLens[playerId]) then
				table.insert(private, {
					kind = "SendTo",
					playerId = playerId,
					payloadKind = "LensView",
					payload = lensView,
				})
			end
			if not deepEqual(turnCues, lastCues[playerId]) then
				table.insert(private, {
					kind = "SendTo",
					playerId = playerId,
					payloadKind = "TurnCues",
					payload = turnCues,
				})
			end
			lens[playerId] = lensView
			cues[playerId] = turnCues
		end
		lastLens = lens
		lastCues = cues
	elseif assignment ~= nil then
		lastLens = seatedOnly(lastLens, assignment.players)
		lastCues = seatedOnly(lastCues, assignment.players)
	end

	-- The public view, from the END state of the step.
	local view = RoundView.public({
		round = round,
		procedure = procedure,
		assignment = assignment,
		positions = positions,
		pings = if round.phase == "Round" then Pings.shown(channel.pings) else {},
		tuning = state.tuning,
	}, now)
	local timed = round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post"
	local triggered = round.phase ~= before.phase
		or #round.players ~= #before.players
		or (event.kind == "Tick" and timed)
	local lastView = state.sent.roundView
	local broadcastView = triggered or not sameRoundView(view, lastView)
	if broadcastView then
		lastView = view
	end

	for _, effect in placed do
		table.insert(effects, effect)
	end
	for _, send in sends do
		table.insert(effects, send)
	end
	if facilityView ~= nil then
		table.insert(effects, facilityView)
	end
	if reply ~= nil then
		table.insert(effects, reply)
	end
	if shown ~= nil then
		table.insert(effects, shown)
	end
	for _, send in private do
		table.insert(effects, send)
	end
	if broadcastView then
		table.insert(effects, { kind = "Broadcast", payloadKind = "RoundView", payload = view })
	end

	local after: SessionState = {
		round = round,
		assignment = assignment,
		facility = facility,
		procedure = procedure,
		positions = positions,
		tracks = tracks,
		tuning = state.tuning,
		generatorPredicate = state.generatorPredicate,
		channel = channel,
		sent = { roundView = lastView, lens = lastLens, cues = lastCues },
		ports = state.ports,
	}
	return after, effects
end

return Session
