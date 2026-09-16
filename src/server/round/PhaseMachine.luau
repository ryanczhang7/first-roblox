--!strict
--[[
	The round phase machine, per ROUND-003 and `docs/wiki/architecture.md`
	section 3: `Lobby -> Assignment -> Round -> Resolution -> Post -> Lobby`, as a
	PURE function of state.

	THREE PROPERTIES HOLD FOR EVERY CALL, and every one of them is a criterion:

	  * `step` is TOTAL. An event the phase does not recognise - a wrong-phase
	    event, a duplicate of one already consumed, one naming a player nobody
	    seated, one whose kind is not in the union at all - returns the state
	    unchanged with an empty effect list. A distributed system delivers late
	    and duplicate events, and a machine that throws on one is a machine a
	    lagging client can crash.

	  * `step` is PURE. It never mutates the state it was handed - not the
	    top-level table and not the `players` array inside it - so a transition
	    builds a new state with a new `players` array. A machine that mutates its
	    input makes "what did the machine do" unanswerable in a test, and it is
	    the defect that is violated first and noticed last.

	  * `step` is DETERMINISTIC. The same `(state, event, now)` yields the same
	    `(state', effects)` forever, including the seed the next round starts
	    from: it is DERIVED from this round's seed through `Rng`, never drawn
	    from a real random source, which would take purity with it.

	WHERE THE DURATIONS ARE EVALUATED, and it is deliberate. A phase's duration is
	checked inside the branch for an event the phase RECOGNISES - in practice
	`Tick` - and never at the top of `step`. AC-7 says an unrecognised event
	returns the state unchanged, with no exception for a duration that has already
	come due, and a duplicate `SeatsAssigned` that quietly ends the lobby is the
	same class of defect as one that throws, only quieter. Recorded in the story's
	`## Contract` amendment 4 and ruled on by the Lead PO.

	THE COMPARISON IS `now - phaseEnteredAt >= duration`, inclusive at the
	boundary, and `phaseEnteredAt` is the `now` of the step that ENTERED the
	phase - not of the step that noticed. A driver that ticks irregularly
	therefore cannot stretch a phase.

	`Assignment` and `Resolution` HAVE NO DURATION. Assignment is a step, not a
	pause: it waits for `SeatsAssigned` however long the clock runs. Resolution
	transitions on the next step it recognises, with the clock standing still. The
	visible pause after a round is `Post`.

	THE CONFIG RIDES IN THE STATE. `step` takes no config argument, so the
	`RoundConfig` handed to `initial` is carried on `RoundState` - the only place
	it can live given those two signatures. The story's Contract lists the other
	six fields and not this one; there is nowhere else to put it.

	WHAT THIS MODULE DOES NOT KNOW: Procedures, operations, actuators,
	instability, signals, budgets, marks, lenses. `Outcome.reason` is an OPAQUE
	string it stores and never inspects - if this machine ever needed to know why
	a round ended in order to route it, the routing would be wrong. It also needs
	no Roblox runtime: no `Instance`, no service, no scheduler, nothing but
	arithmetic over tables.

	THE LOBBY GATES ON A COUNT AS WELL AS A CLOCK (ROUND-004). It starts a round
	only at or above `playersMin`, seats at most `playersMax`, and unseats a
	player who leaves THE LOBBY. Below the minimum the lobby HOLDS rather than
	resetting: neither a join nor a leave ever rewrites `phaseEnteredAt`, so the
	time already served survives a late fourth player.

	OUT OF SCOPE HERE, so that nothing untested ships: the clock and quorum ways
	a round can end, including what a departure means once the round is under way
	(ROUND-005), and the driver that owns the real clock and performs the effects
	(`RoundService`). `PlayerLeft` outside the Lobby and `RematchAccepted`
	everywhere are in the event vocabulary and are ignored, which is exactly what
	`step` being total means.
]]

local Rng = require("@shared/Rng")
local RoundConfig = require("./RoundConfig")

local PhaseMachine = {}

export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"

export type PlayerId = string
export type RoundId = string

export type Outcome = {
	result: "won" | "lost" | "no_contest",
	reason: string, -- opaque to this module; M3 supplies the vocabulary
}

export type RoundState = {
	phase: Phase,
	phaseEnteredAt: number, -- the `now` at which the phase was entered
	roundId: RoundId,
	seed: number,
	players: { PlayerId }, -- seat order; stable within a round
	outcome: Outcome?,
	config: RoundConfig.RoundConfig, -- injected once, carried, never re-read
}

export type Event =
	{ kind: "PlayerJoined", playerId: PlayerId }
	| { kind: "PlayerLeft", playerId: PlayerId }
	| { kind: "Tick" }
	| { kind: "SeatsAssigned" }
	| { kind: "RoundResolved", outcome: Outcome }
	| { kind: "RematchAccepted", playerId: PlayerId }

export type Effect =
	{ kind: "AssignSeats", seed: number, players: { PlayerId } }
	| { kind: "PromptRematch" }
	| { kind: "ComputeTrace", roundId: RoundId }

--[[
	The label and the range the next round's seed is drawn with.

	`derive` mixes a label into a fresh stream identity (`Rng`, ROUND-001), so a
	round seed reproduces its successor on every machine and in every runtime,
	and adding another consumer of randomness under a different label shifts
	nothing here.
]]
local NEXT_ROUND_LABEL = "nextRound"
local MAX_SEED = 2147483647 -- 2^31 - 1

local function nextSeedFrom(seed: number): number
	return Rng.fromSeed(seed):derive(NEXT_ROUND_LABEL):nextInteger(1, MAX_SEED)
end

--[[
	A new state that shares no mutable table with the one it came from.

	`table.clone` alone is not enough and the difference is the whole of AC-6: a
	shallow copy keeps the CALLER's `players` array, and appending a seat to it
	afterwards mutates a state this function was only supposed to read.
]]
local function copyOf(state: RoundState): RoundState
	local copy = table.clone(state)
	copy.players = table.clone(state.players)
	return copy
end

-- A copy in `phase`, recording the `now` that entered it.
local function entering(state: RoundState, phase: Phase, now: number): RoundState
	local entered = copyOf(state)
	entered.phase = phase
	entered.phaseEnteredAt = now
	return entered
end

local function elapsedIn(state: RoundState, now: number): number
	return now - state.phaseEnteredAt
end

-- The seat `playerId` occupies, or `nil` if they are not seated.
local function seatOf(state: RoundState, playerId: PlayerId): number?
	for index, id in state.players do
		if id == playerId then
			return index
		end
	end
	return nil
end

local function isSeated(state: RoundState, playerId: PlayerId): boolean
	return seatOf(state, playerId) ~= nil
end

--[[
	A fresh Lobby, seating nobody, entered at 0.

	`initial` takes no `now`, so 0 is the only self-consistent answer: every
	duration in the Lobby is measured from `phaseEnteredAt`, and a value the
	caller never supplied cannot be anything else.
]]
function PhaseMachine.initial(
	config: RoundConfig.RoundConfig,
	seed: number,
	roundId: RoundId
): RoundState
	return {
		phase = "Lobby",
		phaseEnteredAt = 0,
		roundId = roundId,
		seed = seed,
		players = {},
		outcome = nil,
		config = config,
	}
end

--[[
	`Tick` is the only event that consults the clock, and it consults it for the
	two phases that have a duration plus the one that transitions immediately.

	A tick the current phase has no answer for is ignored like any other
	unrecognised event: `Assignment` waits for `SeatsAssigned` however long the
	clock runs, and `Round` is left by an event, not by a timer, until ROUND-005
	adds the ways a round can end.
]]
local function onTick(state: RoundState, now: number): (RoundState, { Effect })
	--[[
		BOTH halves are re-tested on every tick, and the count gate is NOT
		LATCHED: the machine keeps no memory of a tick that found the time due
		while the lobby was short, so the round starts on the first tick after
		the count is reached (ROUND-004 AC-2, AC-3). The clock is a FLOOR on
		lobby dwell time, not the only condition for starting a round.

		It lives HERE, inside the `Tick` branch, rather than at the top of
		`step`: a duration is only ever consulted for an event the phase
		recognises (the header, and ROUND-003's Contract amendment 4), and the
		lobby's count is half of the same condition.
	]]
	if
		state.phase == "Lobby"
		and elapsedIn(state, now) >= state.config.lobbySeconds
		and #state.players >= state.config.playersMin
	then
		-- Emitted by the step that ENTERS Assignment, once - not once per step
		-- while the machine sits in it.
		local assignment = entering(state, "Assignment", now)
		return assignment,
			{ { kind = "AssignSeats", seed = state.seed, players = table.clone(state.players) } }
	end

	if state.phase == "Resolution" then
		-- No duration: the clock may stand exactly where it did on entry.
		return entering(state, "Post", now), { { kind = "ComputeTrace", roundId = state.roundId } }
	end

	if state.phase == "Post" and elapsedIn(state, now) >= state.config.postRoundSeconds then
		--[[
			The returning Lobby: a NEW seed, derived from this round's own, so
			the next round is a different instance and the derivation stays a
			pure function of the state; the outcome cleared, because it belonged
			to the round that just ended; the seated players KEPT, because they
			have been prompted to rematch and unseating them here would empty a
			lobby nobody left. The `roundId` is carried: this machine has no way
			to invent one, and the driver that will own that is `RoundService`.
		]]
		local lobby = entering(state, "Lobby", now)
		lobby.seed = nextSeedFrom(state.seed)
		lobby.outcome = nil
		return lobby, { { kind = "PromptRematch" } }
	end

	return state, {}
end

--[[
	The transition function. Total, pure, deterministic; see the header.

	The returned effect list is always a real array - empty means an empty table,
	never `nil` - because a driver that has to distinguish the two is a driver
	that will get it wrong once.
]]
function PhaseMachine.step(state: RoundState, event: Event, now: number): (RoundState, { Effect })
	if event.kind == "Tick" then
		return onTick(state, now)
	end

	if event.kind == "PlayerJoined" then
		--[[
			Three ways a join is refused, and a refusal is an unrecognised event
			in AC-7's sense - the same state back, an empty effect list, nothing
			raised and nothing mutated. Seating one player twice would put them
			in two seats of the same ring, and rejecting the surplus join at the
			door is this machine's job rather than the driver's: a driver that
			filters is a driver that can forget (ROUND-004 AC-4, AC-5).

			`phaseEnteredAt` is deliberately untouched on the path that DOES
			seat somebody. That one absence is the hold: the lobby time already
			served is never discarded by a join, or a lobby that gains and loses
			a player every thirty seconds never starts (M6).
		]]
		if
			state.phase ~= "Lobby"
			or isSeated(state, event.playerId)
			or #state.players >= state.config.playersMax
		then
			return state, {}
		end
		local seated = copyOf(state)
		table.insert(seated.players, event.playerId)
		return seated, {}
	end

	if event.kind == "PlayerLeft" then
		--[[
			A departure unseats in the LOBBY and nowhere else (ROUND-004
			Contract pin 2). What a mid-round departure means - the quorum
			against `minPlayersToContinue` - is ROUND-005's, and unseating here
			would silently change the seated list AFTER `AssignSeats` has
			already carried it, which is the ring SEAT-001 deals.

			`table.remove` on the COPY, closing the hole rather than copying the
			last element over it: seat order is join order, so the seated list
			is always a subsequence of it, and a swap-with-the-last is a correct
			SET removal that scrambles the ring (AC-6). A leave naming somebody
			who is not seated is an ordinary ignored event, and `phaseEnteredAt`
			survives a leave for the same reason it survives a join.
		]]
		local seat = if state.phase == "Lobby" then seatOf(state, event.playerId) else nil
		if seat == nil then
			return state, {}
		end
		local remaining = copyOf(state)
		table.remove(remaining.players, seat)
		return remaining, {}
	end

	if event.kind == "SeatsAssigned" then
		if state.phase ~= "Assignment" then
			return state, {}
		end
		return entering(state, "Round", now), {}
	end

	if event.kind == "RoundResolved" then
		if state.phase ~= "Round" then
			return state, {}
		end
		-- Recorded verbatim. The machine does not inspect, compute or override
		-- an outcome; M3 decides what resolves a round and M1 only routes it.
		local resolution = entering(state, "Resolution", now)
		resolution.outcome = event.outcome
		return resolution, {}
	end

	-- Everything else, including `RematchAccepted` and any kind the union does
	-- not contain: the state is a value and it comes back untouched.
	return state, {}
end

return PhaseMachine
