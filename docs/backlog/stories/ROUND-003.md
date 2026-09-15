---
id: ROUND-003
title: A round advances through all five phases on an injected clock
slug: a-round-advances-through-all-five-phases
epic: EPIC-01
type: feature
status: todo
phase: PLANNED
branch: story/ROUND-003-a-round-advances-through-all-five-phases
depends_on: [ROUND-001, ROUND-002]
required_gates: []
---

## Context

The walking skeleton of the game's server. `Lobby → Assignment → Round →
Resolution → Post → Lobby`, as a pure function of state driven by the injected
clock from `ROUND-001` and the durations from `ROUND-002`.

This is the one large system in the project that is **genre-independent**: it was
specified before amendment 8 replaced hidden-role deduction with
asymmetric-information co-op, and not a line of it moved when the genre changed.
Keeping it that way is a design constraint of this story, not a nice property —
see `## Out of scope`.

Read `docs/wiki/architecture.md` §3 for the transition table and the effect
vocabulary. This story builds the happy-path lifecycle; `ROUND-004` adds the lobby
gating and `ROUND-005` the three ways a round can end.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a fresh machine with `players_min` players seated, when the
  clock is advanced past `lobby_seconds`, then the phase becomes `Assignment` and
  not before: at `lobby_seconds − 0.1` elapsed the phase is still `Lobby`.
- **AC-2** — Given the machine in `Assignment`, when it entered that phase, then
  it emitted exactly one `AssignSeats` effect carrying the round's seed and the
  seated player list; and when a `SeatsAssigned` event is applied, then the phase
  becomes `Round`.
- **AC-3** — Given the machine in `Round`, when a `RoundResolved` event carrying an
  outcome is applied, then the phase becomes `Resolution` and the state records
  that outcome unchanged — the machine does not inspect, compute or override it.
- **AC-4** — Given the machine entering `Resolution`, when the next step occurs
  with no further input, then it emits a `ComputeTrace` effect and the phase
  becomes `Post` without waiting on the clock.
- **AC-5** — Given the machine in `Post`, when the clock is advanced past
  `post_round_seconds`, then a `PromptRematch` effect has been emitted and the
  phase returns to `Lobby` with a **new** round seed, distinct from the previous
  round's.
- **AC-6** — Given any state and any event, when `step` is called twice with
  identical `(state, event, now)`, then the two calls return equal states and equal
  effect lists, and the input state is not mutated.
- **AC-7** — Given a state in any phase, when an event that phase does not
  recognise is applied — including one it already consumed — then the state is
  returned unchanged with an empty effect list and no error is raised.
  *Control:* an implementation that raises on an unknown event **must** fail this.
- **AC-8** — Given a full lifecycle driven end to end by a manual clock, when the
  sequence of phases and effects is recorded, then it is exactly
  `Lobby, Assignment, Round, Resolution, Post, Lobby` with effects
  `AssignSeats, ComputeTrace, PromptRematch` in that order, and no Roblox runtime
  was required at any point.

## Contract

### `src/server/round/PhaseMachine.luau`

    export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"

    export type PlayerId = string
    export type RoundId  = string

    export type Outcome = {
        result: "won" | "lost" | "no_contest",
        reason: string,          -- opaque to this module; M3 supplies the vocabulary
    }

    export type RoundState = {
        phase:          Phase,
        phaseEnteredAt: number,      -- the `now` at which the phase was entered
        roundId:        RoundId,
        seed:           number,
        players:        { PlayerId },   -- seat order; stable within a round
        outcome:        Outcome?,
    }

    export type Event =
        | { kind: "PlayerJoined",  playerId: PlayerId }
        | { kind: "PlayerLeft",    playerId: PlayerId }
        | { kind: "Tick" }
        | { kind: "SeatsAssigned" }
        | { kind: "RoundResolved", outcome: Outcome }
        | { kind: "RematchAccepted", playerId: PlayerId }

    export type Effect =
        | { kind: "AssignSeats",   seed: number, players: { PlayerId } }
        | { kind: "Emit",          event: TelemetryEvent }   -- TEL-002 populates this
        | { kind: "ReplicateSeat", playerId: PlayerId, view: PublicSeatView }
        | { kind: "PromptRematch" }
        | { kind: "ComputeTrace",  roundId: RoundId }

    PhaseMachine.initial(config: RoundConfig, seed: number, roundId: RoundId) -> RoundState
    PhaseMachine.step(state: RoundState, event: Event, now: number) -> (RoundState, { Effect })

### `src/server/round/RoundConfig.luau`

    export type RoundConfig = {
        lobbySeconds:          number,
        postRoundSeconds:      number,
        roundSeconds:          number,
        playersMin:            number,
        playersMax:            number,
        minPlayersToContinue:  number,
    }

    RoundConfig.fromTuning(tuning) -> RoundConfig

The config is **injected**, never read from `Tuning` inside the machine. That is
what lets a test run a whole lifecycle in a few simulated seconds instead of nine
real minutes, and it is why `ROUND-002`'s placeholder values can move without
touching this module.

### The semantics behind each number and each rule

- **`phaseEnteredAt`** is the `now` passed to the `step` that entered the phase,
  not the `now` of the step that noticed. A phase's duration is measured from
  entry, so a driver that ticks irregularly cannot stretch a phase.
- **The comparison is `now - phaseEnteredAt >= duration`**, inclusive. At exactly
  `lobby_seconds` the phase leaves. AC-1's `− 0.1` pins the other side.
- **`Assignment` is a step, not a pause.** It has no duration. It waits for
  `SeatsAssigned`, which the driver produces by calling `Ring.assign` (SEAT-001).
  Until SEAT-001 exists, the driver is a test.
- **`Resolution` has no duration either.** It transitions on the next step. The
  visible pause after a round is `Post`, which is where `post_round_seconds` lives
  and where the trace is read.
- **A new seed per round.** AC-5 requires the returning `Lobby` to carry a seed
  distinct from the last round's. Derive it deterministically from the machine's
  own state — `Rng.fromSeed(previousSeed):derive("nextRound"):nextInteger(...)` or
  equivalent — **not** from a real random source, or `step` stops being pure and
  AC-6 becomes unsatisfiable.
- **`step` is total.** Unknown event, duplicate event, event for a player not
  seated: return `(state, {})`. AC-7. Late and duplicate delivery is normal in a
  networked game; a machine that throws is a machine a lagging client can crash.
- **`step` never mutates.** It returns a new `RoundState`. AC-6's non-mutation
  clause is the one that will be violated first and noticed last.

### What this module must not contain

No reference to Procedures, operations, actuators, instability, signals, budgets,
marks or lenses. `Outcome.reason` is an opaque string that M3 fills in. If the
implementation needs to know *why* a round ended in order to route it, the routing
is wrong.

### Test-only dependencies

None.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1..AC-5, AC-8 | **Mechanical** | Pin the transition table exactly, from `architecture.md` §3. Precision beats invention; leave nothing open-ended. |
| AC-6, AC-7 | **Mechanical, with a control each** | Purity and totality. The controls are named in the criteria. AC-6's non-mutation half needs a deep comparison of the input state before and after, not an identity check. |
| — | **Settled** | The durations come from `ROUND-002`, which reads them from `tuning.md`. Do not choose or calibrate a duration. |

## Deferred verifications

None. Every criterion here can be exercised in RED against a machine that does not
yet exist, and the two controls (AC-7's raising implementation, AC-6's mutating
one) can be demonstrated against a hand-written stub.

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

This story is almost entirely **mechanical**: the transition table is written down
in `architecture.md` §3 and the job is to pin it exactly. Brief RED accordingly —
precision, not invention. The one place judgement is wanted is AC-6's non-mutation
assertion, where the obvious test (compare references) asserts nothing.

## Out of scope

- **Lobby player-count gating.** `ROUND-004`. This story seats `players_min`
  players and leaves them there.
- **Clock expiry and quorum loss ending a round.** `ROUND-005`.
- **What actually resolves a round.** M3. The machine routes `RoundResolved`; it
  never computes an outcome.
- **The seat assignment itself.** `AssignSeats` is an effect with nothing behind it
  until SEAT-001.
- **Telemetry.** The `Emit` effect is in the vocabulary and this story emits none.
  `TEL-002` adds the emitters.
- **The trace.** `ComputeTrace` is emitted and nothing consumes it. `mechanics.md`
  §7 is M3.
- **The driver.** `RoundService.luau` — the impure loop that owns the real clock
  and performs effects — is not needed until something networked exists. Tests
  drive `step` directly.

## Game design

Implements the round structure in `docs/wiki/game/loop.md` and brief A4, with the
amendments in product-brief §0b/§0c applied: no vote, no elimination, no hidden
faction (amendment 8), and a `Post` phase lengthened to 45 seconds because the
post-round trace is four items of reading (`tuning.md` §1).

The design decision this story protects: **the round is short and the post-round
is deliberately not.** A4 calls the rematch prompt "the highest-value thirty
seconds in the product" and A2 #2 makes intentional co-play the headline retention
signal. `PromptRematch` being an effect the machine emits — rather than something
the UI decides to show — is what makes that testable.

Edge cases the rules produce, and where each is handled:

| Case | Here or elsewhere |
|---|---|
| Two terminal conditions in the same step | `ROUND-005` — precedence is specified there |
| Player count below `players_min` at lobby end | `ROUND-004` — the timer **holds**, it does not reset |
| Player count below `min_players_to_continue` mid-round | `ROUND-005` — `no_contest`, no loss recorded |
| Disconnect and rejoin changing the ring | `SEAT-003` |

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Change the phase-duration comparison from `>=` to `>`. Predicted: AC-1's
   boundary assertion goes red and little else — a single assertion, which is where
   a vacuous boundary test hides.
2. Make `step` mutate and return the input state. Predicted: AC-6's non-mutation
   assertion goes red. If it stays green, AC-6 was written as an identity check.
3. Make the returning `Lobby` reuse the previous seed. Predicted: AC-5's distinct-
   seed assertion goes red.

Run mutation 1 first.

**Raise the `unit` floor** to the new real count.
