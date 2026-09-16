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

	WHERE THE DURATIONS AND THE COUNT ARE EVALUATED, and it is deliberate. A
	phase's duration is checked inside the branch for an event the phase
	RECOGNISES - the clock on `Tick` and on `Tick` only - and never at the top of
	`step`. AC-7 says an unrecognised event returns the state unchanged, with no
	exception for a duration that has already come due, and a duplicate
	`SeatsAssigned` that quietly ends the lobby is the same class of defect as one
	that throws, only quieter. Recorded in the story's `## Contract` amendment 4
	and ruled on by the Lead PO.

	The round's QUORUM is half of the same rule and is consulted in exactly two
	branches: `Tick`, and `PlayerLeft` - the only event that can change the count
	(ROUND-005 Contract pin 2). A `RematchAccepted` or an off-union kind arriving
	at a `Round` already below quorum is still ignored in full; the next `Tick`
	is what ends it. And a `PlayerLeft` step evaluates quorum and NEVER the
	clock (pin 6), or AC-7's "the round continues" would become conditional on
	how much time had passed and a departure would be reported as a timeout.

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

	HOW A ROUND ENDS, AND IN WHAT ORDER (ROUND-005). Within a single `step` on a
	`Round` state, three terminal conditions are evaluated in a FIXED order and
	the first that holds wins (`architecture.md` section 3, where the list is
	stated once):

	  1. `RoundResolved` - an event carrying an outcome; recorded verbatim
	  2. `below_quorum`  - `#players < minPlayersToContinue`; `no_contest`
	  3. `clock`         - `now - phaseEnteredAt >= roundSeconds`; `lost`

	The order is the contract rather than an implementation detail: the trace
	reports the reason, so a reason that depends on evaluation order is a bug
	report nobody can reproduce. A round nobody can play did not run out of time,
	and an event describing something that happened INSIDE the round outranks the
	round running out around it. Here that order is structural - `RoundResolved`
	is a different event from `Tick`, so it never reaches the clock - and it is
	an ordering of two `if`s only in the one branch where both can hold.

	A QUORUM FAILURE IS NOT A LOSS. It is `no_contest`, so no loss is recorded
	and season progress is unaffected: the group did not fail, the lobby did
	(`mechanics.md` section 8). Recording it as `lost` would punish three people
	for a fourth person's connection, in a game whose whole retention thesis is
	that the same four people keep playing together.

	THE COMPARISON IS `#players < minPlayersToContinue`, STRICT. Three is a ring
	(`roles.md` section 6, `tuning.md` section 1), so a round that has fallen
	exactly TO the threshold continues; `<=` would end every three-player round
	silently.

	THE ENDING STEP EMITS NOTHING. The single `ComputeTrace` a round produces is
	still emitted by `Resolution -> Post`, so a machine that also emitted one on
	the way out of `Round` would emit two for every round that ended.

	A RESOLVED ROUND IS NOT RE-RESOLVED. `outcome` is written once, by the step
	that ended the round; in `Resolution` and `Post` neither the clock nor the
	count is consulted again, however far `now` has travelled.

	OUT OF SCOPE HERE, so that nothing untested ships: the degraded-round flag a
	round continuing at exactly `minPlayersToContinue` deserves in its trace
	(`roles.md` section 6) - deferred deliberately, because the trace is M3 and a
	field with no consumer rots - and the driver that owns the real clock and
	performs the effects (`RoundService`). `PlayerLeft` in `Assignment`,
	`Resolution` and `Post`, and `RematchAccepted` everywhere, are in the event
	vocabulary and are ignored, which is exactly what `step` being total means.
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
	The two outcomes this module OWNS, each built fresh on every call.

	A shared constant would hand the SAME table to every round that ended the
	same way, and one consumer writing into it would rewrite the outcome of every
	other - the aliasing defect `copyOf` exists to prevent, one field lower down.
	Every other `reason` is M3's, arrives inside a `RoundResolved` and is stored
	without being read: a machine that had to know why a round ended in order to
	route it would be routing on the wrong thing.
]]
local function clockOutcome(): Outcome
	return { result = "lost", reason = "clock" }
end

local function quorumOutcome(): Outcome
	return { result = "no_contest", reason = "below_quorum" }
end

-- `#players < minPlayersToContinue`, strict. Three is a ring: see the header.
local function isBelowQuorum(state: RoundState): boolean
	return #state.players < state.config.minPlayersToContinue
end

--[[
	The `Resolution` a terminal condition produces: the outcome recorded once, by
	this step, and NO effects.

	The empty effect list is Contract pin 3 and it is the whole of AC-6. The one
	`ComputeTrace` a round produces belongs to `Resolution -> Post`; emitting one
	here as well would emit two, which is what "the round does not continue to
	accumulate effects after ending" is there to catch.
]]
local function resolvedAs(
	state: RoundState,
	outcome: Outcome,
	now: number
): (RoundState, { Effect })
	local resolution = entering(state, "Resolution", now)
	resolution.outcome = outcome
	return resolution, {}
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

	--[[
		The two terminal conditions a `Tick` can see, IN THE CONTRACT'S ORDER:
		quorum, then the clock. `RoundResolved` outranks both by arriving in its
		own branch, which never reaches here.

		The order is visible as the order of these two `if`s on purpose. A round
		nobody can play did not run out of time, so a step on which both hold
		records `below_quorum` - and it records it on every run, because nothing
		here depends on anything but `(state, event, now)`.
	]]
	if state.phase == "Round" and isBelowQuorum(state) then
		return resolvedAs(state, quorumOutcome(), now)
	end

	if state.phase == "Round" and elapsedIn(state, now) >= state.config.roundSeconds then
		--[[
			`elapsedIn` measures from the step that ENTERED `Round`, not from 0
			and not from the step that noticed, so a driver ticking irregularly
			can neither stretch the round nor cut it short. The comparison is
			inclusive at the boundary, exactly as the lobby's is.
		]]
		return resolvedAs(state, clockOutcome(), now)
	end

	if state.phase == "Resolution" then
		-- No duration: the clock may stand exactly where it did on entry. A
		-- round that has resolved is never re-resolved - neither the count nor
		-- the round clock is consulted in this phase or in `Post`.
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
			A departure unseats in TWO phases and nowhere else: the `Lobby`
			(ROUND-004 Contract pin 2) and `Round` (ROUND-005 Contract pin 1).
			In `Assignment`, `Resolution` and `Post` it is ignored in full -
			unseating in `Assignment` would silently change the seated list
			AFTER `AssignSeats` has already carried it, which is the ring
			SEAT-001 deals, and a resolved round is not re-resolved.

			`table.remove` on the COPY, closing the hole rather than copying the
			last element over it: seat order is join order, so the seated list
			is always a subsequence of it, and a swap-with-the-last is a correct
			SET removal that scrambles the ring (AC-6). A leave naming somebody
			who is not seated is an ordinary ignored event - in `Round` too, so
			it is not a departure and quorum is not evaluated for it - and
			`phaseEnteredAt` survives a leave for the same reason it survives a
			join.
		]]
		local unseats = state.phase == "Lobby" or state.phase == "Round"
		local seat = if unseats then seatOf(state, event.playerId) else nil
		if seat == nil then
			return state, {}
		end
		local remaining = copyOf(state)
		table.remove(remaining.players, seat)

		--[[
			Quorum is evaluated on THIS step, against the count left after the
			departure: the round ends on the step that took it below the
			threshold rather than on the tick that noticed afterwards.

			The clock is deliberately not consulted here (Contract pin 6). AC-7
			says a round that falls exactly to `minPlayersToContinue` continues,
			full stop - a machine that also checked the clock would end that
			round `lost(clock)` whenever the departure happened to land late, and
			would report a departure to players as a timeout.
		]]
		if remaining.phase == "Round" and isBelowQuorum(remaining) then
			return resolvedAs(remaining, quorumOutcome(), now)
		end
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
