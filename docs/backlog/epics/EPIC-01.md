---
id: EPIC-01
title: A round runs itself, start to finish, with no Roblox in the room
status: done
stories: [ROUND-001, ROUND-002, ROUND-003, ROUND-004, ROUND-005]
---

## Goal

A complete round lifecycle — `Lobby → Assignment → Round → Resolution → Post →
Lobby` — runs as a pure function of state, driven by an injected clock, and is
exercised end to end by tests with no Roblox runtime, no rendering and no
remotes. Player count gates the lobby, three different conditions can end a round,
and the reason a round ended is deterministic.

This is milestone **M1**, and its definition of done is unchanged.

## Why now

Three reasons, in order of how expensive they are to get wrong.

1. **The clock and the random source must be injected from the first story.**
   `architecture.md` §2 and the `roblox-luau` profile both say so, and both say
   why: retrofitting either means rewriting the phase machine and the instance
   generator. There is no cheap later moment.
2. **The phase machine is the one large system that is genre-independent.** It was
   specified before the genre changed and did not move when amendment 8 replaced
   hidden-role deduction with asymmetric-information co-op. Building it now is
   work that survives whatever T5–T9 decide.
3. **Everything in M2 needs a phase to be legal in.** The trust boundary's
   phase-legality check has nothing to check against until this exists.

## Done when

The full round lifecycle is exercised by tests with no Roblox runtime involved —
including a round that ends by the clock, one that ends by an outcome event, one
that ends as a no-contest when the lobby empties below the continue threshold, and
a lobby that refuses to start below `players_min`.

And one property that is easy to lose and expensive to notice: **`PhaseMachine.step`
is deterministic and total.** The same `(state, event, now)` produces the same
`(state', effects)` on every run, an unknown event is ignored rather than fatal,
and no module under `src/` outside the two sanctioned adapters reads a real clock
or a real random source.

## Stories

1. **ROUND-001** — Clock and randomness are injected, and nothing else may read
   them. The `Clock` and `Rng` modules, seeded reproducibility, `derive`
   sub-streams, and the guard test that enumerates source modules through
   `scripts/classify.sh --list` and asserts nobody else touches `os.clock` or
   `math.random`.
2. **ROUND-002** — Session and round-timing constants match their specification.
   The `Tuning` module built from `docs/wiki/game/tuning.md` §1 and §5, frozen, with
   a guard that fails when the module and the specification disagree — and a guard
   that the constants the design deliberately does **not** have (§7) are absent.
3. **ROUND-003** — A round advances through all five phases on an injected clock,
   emitting effects as values rather than performing them.
4. **ROUND-004** — The lobby holds below `players_min` rather than resetting, and
   admits no more than `players_max`.
5. **ROUND-005** — A round ends on an outcome event, on clock expiry, or on the
   player count falling below `min_players_to_continue`, and the recorded reason is
   deterministic when two conditions land in the same step.

## Deliberately not in this epic

- **What resolves a round.** The machine routes an outcome; it never computes one.
  Procedures, operations, instability and blackout are M3, and keeping them out is
  what lets this epic's work survive the open questions in `architecture.md` §0.
- **Seat assignment.** `Assignment` is a phase here, not a mechanism. The ring is
  EPIC-02.
- **Remotes.** No network in M1 at all. The machine is fed events by a test in this
  epic and by the net layer in the next.
- **The post-round trace.** `Resolution` emits a `ComputeTrace` effect with nothing
  behind it. `mechanics.md` §7 is M3.
- **The rematch prompt UI.** `Post` emits `PromptRematch`; what a player sees is
  M3/M4.

---

## Closed

All five stories are DONE and the done-when is met, clause by clause, by tests
that run with no Roblox runtime in the room:

| Done-when clause | Where it is satisfied | Test |
|---|---|---|
| a round that ends by an outcome event | `ROUND-003` AC-3 | `AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged` |
| a round that ends by the clock | `ROUND-005` AC-1 | `AC-1: the clock ends the round at exactly roundSeconds elapsed, as lost(clock), and not before` |
| a round that ends as a no-contest when the lobby empties below the continue threshold | `ROUND-005` AC-2, AC-3 | `AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step`, `AC-3: a round that ended below quorum records no_contest and never lost` |
| a lobby that refuses to start below `players_min` | `ROUND-004` AC-1 | `AC-1: a lobby below players_min holds rather than starting, and an empty lobby is the same criterion at zero` |
| `step` is deterministic and total | `ROUND-003` AC-6, AC-7 | `PhaseMachineContract.stepIsDeterministic`, `.stepDoesNotMutateItsInput`, `.eventIsIgnored`, applied to the real machine and observed refusing the wrong ones in `phase_machine_controls_test.luau` |
| no module outside the two sanctioned adapters reads a real clock or random source | `ROUND-001` AC-5, AC-6 | `AC-5: no source module outside the Clock adapter reads a real time source` (and the `Rng` half), enumerated through `scripts/classify.sh --list` |

The full lifecycle — `Lobby -> Assignment -> Round -> Resolution -> Post ->
Lobby` — is exercised end to end in `phase_machine_test.luau`'s
`AC-8: a full lifecycle emits exactly AssignSeats, ComputeTrace, PromptRematch,
in that order`. Suite at close: **175 passed, 0 failed**, `unit` floor 175.

**What M1 deliberately still does not have**, so that the next epic is not
surprised by it: `RoundService` — the impure driver that owns the real clock and
performs the effects — has no story yet. The machine is fed events by a test
today and by the net layer in `EPIC-02`. The `ComputeTrace` effect carries a
round id and nothing behind it; the trace itself is M3. And the degraded-round
flag at `n = 3` (`roles.md` §6) is recorded as a deliberate omission in
`ROUND-005`'s Contract rather than as an oversight.
