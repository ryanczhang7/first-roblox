--!strict
--[[
	SLICE-003: the pure composition root that connects the phase machine to the
	seating ring (`architecture.md` §9.2, D22). M1's machine emits `AssignSeats`
	and waits for `SeatsAssigned`; M2's `Ring.assign` deals and `Projection`
	says what each seat may know. This module is where they meet, so that "the
	pieces compose" is something a unit test can check.

	ONE STEP, TWO MACHINE STEPS. `step` feeds the event to `PhaseMachine.step`.
	When that emits `AssignSeats`, the ring is dealt from THE EFFECT'S `players`
	and `Rng.fromSeed(effect.seed)` - never from `round.players`/`round.seed`,
	which are equal today and are not the contract - and the machine is stepped
	again with `SeatsAssigned` at the same `now`, so the state returned is in
	`Round`. `Ring.assign` derives its own `"seats"` stream; nothing here
	derives again.

	`SeatsAssigned` IS INTERNAL. One arriving from outside is ignored before
	the machine sees it: forwarded in `Assignment`, it would move to `Round`
	with no ring dealt.

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

	THE RING IS CLEARED ON ENTERING `Lobby`. A stale ring in the next lobby
	would be withdrawn from, and seat views sent, for a round that is over.

	EFFECT ORDER within one step: the machine's pass-through effects (`Emit`,
	`PromptRematch`, `ComputeTrace`) in emission order with `AssignSeats`
	removed; then the `SendTo` seat views in seat order; then at most one
	`Broadcast` of the `RoundView`, built from the state at the END of the step.

	`secondsLeft` IS RELATIVE. It is the whole-second ceiling of the config's
	duration minus the time spent in the phase, never an absolute deadline:
	the server's clock is not the client's (§9.7). `nil` where the phase has no
	running clock - `Assignment`, `Resolution`, and a `Lobby` below
	`playersMin`, where the timer holds (§3).

	PURE: nothing handed in is mutated, and the effect list is always a table.
]]

local PhaseMachine = require("../round/PhaseMachine")
local Projection = require("../seats/Projection")
local RoundConfig = require("../round/RoundConfig")
local Ring = require("../seats/Ring")
local Rng = require("@shared/Rng")

local Session = {}

export type SessionState = {
	round: PhaseMachine.RoundState,
	assignment: Ring.Assignment?,
}
-- Later M3 stories add facility, procedure, channel, positions (§9.2).

-- `SeatsAssigned` is produced inside `step`; one from outside is ignored (D5).
export type SessionEvent = PhaseMachine.Event

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
} | { kind: "Broadcast", payloadKind: "RoundView", payload: RoundView } | PhaseMachine.Effect -- minus AssignSeats, which is consumed here

function Session.new(
	config: RoundConfig.RoundConfig,
	seed: number,
	roundId: string,
	sessionId: string
): SessionState
	return { round = PhaseMachine.initial(config, seed, roundId, sessionId), assignment = nil }
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

-- The whole seconds left in a timed phase, or `nil` where no clock runs.
local function secondsLeftIn(round: PhaseMachine.RoundState, now: number): number?
	local config = round.config
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

local function roundView(round: PhaseMachine.RoundState, now: number): SessionEffect
	return {
		kind = "Broadcast",
		payloadKind = "RoundView",
		payload = {
			phase = round.phase,
			secondsLeft = secondsLeftIn(round, now),
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

	local before = state.round
	local round, machineEffects = PhaseMachine.step(before, event, now)
	local effects: { SessionEffect } = {}
	passThrough(effects, machineEffects)

	local sends: { SessionEffect } = {}
	local assignment = state.assignment

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

	if round.phase == "Lobby" and before.phase ~= "Lobby" then
		assignment = nil
	end

	for _, send in sends do
		table.insert(effects, send)
	end

	local timed = round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post"
	if
		round.phase ~= before.phase
		or #round.players ~= #before.players
		or (event.kind == "Tick" and timed)
	then
		table.insert(effects, roundView(round, now))
	end

	return { round = round, assignment = assignment }, effects
end

return Session
