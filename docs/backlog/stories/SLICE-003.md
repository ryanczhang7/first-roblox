---
id: SLICE-003
title: The session deals seats and sends each player only their own seat view
slug: the-session-deals-seats-and-sends-each-p
epic: EPIC-03
type: feature
status: todo
phase: PLANNED
branch: story/SLICE-003-the-session-deals-seats-and-sends-each-p
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`, the M3 walking skeleton. M1 built a phase machine that emits
`AssignSeats` and waits for `SeatsAssigned`; M2 built `Ring.assign` and the
allowlisted `Projection.forPlayer`. **Nothing connects them.** `architecture.md`
§9.2 (D22) puts that connection in a pure composition root, `Session`, so that
"the pieces compose" is something a required gate can check rather than
something only a Studio session shows.

This story is the thinnest `Session` that does real work: it carries out
`AssignSeats`, feeds `SeatsAssigned` back in the same step, sends each seated
player **their own** seat view and nobody else's, and broadcasts a minimal
public `RoundView` (phase and seconds left). Every later M3 piece (facility,
Procedure, channel, views) is added to this module by its own story.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a session with `players_min` joined players and the lobby
  timer elapsed, when a `Tick` is stepped, then in that one step the phase
  reaches `Round`, `Ring.assign` has been applied with the round's seed, and the
  resulting assignment equals `Ring.assign(players, Rng.fromSeed(seed))` for the
  seed the phase machine's `AssignSeats` effect carried.
  *Control:* a session that assigns with a fixed seed (not the effect's) must
  fail this AC across two consecutive rounds, whose seeds differ.
- **AC-2** — Given AC-1's step, when its effects are read, then there is exactly
  one `SendTo` effect of kind `SeatView` per seated player, addressed to that
  player, whose payload equals `Projection.forPlayer(assignment, thatPlayer)`,
  and **no `Broadcast` effect carries a seat view**.
  *Control:* a session that broadcasts the list of all seat views must fail.
- **AC-3** — Given a seated round, when a seated player leaves, then the session
  applies `Ring.withdraw` and sends a fresh `SeatView` to every remaining player
  whose view changed (at least the leaver's supplier, whose `keyClasses` grew),
  and to no one whose view is unchanged.
- **AC-4** — Given any step that changes the phase or the player count, and
  every `Tick` while the phase has a duration, when effects are read, then there
  is one `Broadcast` of kind `RoundView` whose payload is exactly
  `{ phase, secondsLeft, players, playersMin, playersMax }`: `secondsLeft` is the
  whole-second ceiling of the time left in `Lobby`, `Round` or `Post`, and `nil`
  in `Assignment` and `Resolution`, and in a `Lobby` below `players_min` (the
  timer holds, `architecture.md` §3).
- **AC-5** — Given the phase machine's own effects (`Emit`, `PromptRematch`,
  `ComputeTrace`), when a step produces them, then the session passes them
  through unchanged and in order; `AssignSeats` is the only one it consumes.

## Contract

**Module.** `src/server/session/Session.luau`, pure.

    export type SessionState = {
        round: PhaseMachine.RoundState,
        assignment: Ring.Assignment?,
    }
    -- Later M3 stories add facility, procedure, channel, positions (architecture.md §9.2).

    export type SessionEvent = PhaseMachine.Event   -- PlayerJoined, PlayerLeft, Tick, RematchAccepted
    -- SeatsAssigned is produced inside Session, never accepted from outside:
    -- a SessionEvent of kind SeatsAssigned is ignored like any unknown event (D5).

    export type RoundView = { phase: PhaseMachine.Phase, secondsLeft: number?, players: { string }, playersMin: number, playersMax: number }
    -- players: the round state's `players`, in join order (= seat order once dealt); public

    export type SessionEffect =
          { kind: "SendTo", playerId: string, payloadKind: "SeatView", payload: Projection.PublicSeatView }
        | { kind: "Broadcast", payloadKind: "RoundView", payload: RoundView }
        | PhaseMachine.Effect   -- minus AssignSeats, passed through

    Session.new(config: RoundConfig.RoundConfig, seed: number, roundId: string, sessionId: string) -> SessionState
    Session.step(state: SessionState, event: SessionEvent, now: number) -> (SessionState, { SessionEffect })

- `RoundView` lives here for now; `VIEW-003` moves it to
  `src/server/round/RoundView.luau` and widens it. Its field names are fixed by
  this story.
- `payloadKind` strings are exactly `Transport`'s kinds (`SLICE-002`), so the
  interpreter in `SLICE-004` maps effects one to one.
- `secondsLeft` is computed from `now − round.phaseEnteredAt` against the config
  duration, **never** sent as an absolute time: the server's clock is not the
  client's (`architecture.md` §9.7).
- The ring is dealt from `Rng.fromSeed(effect.seed)`. `Ring.assign` derives
  `"seats"` itself; `Session` does not derive again.

**Existing exports: no signature changes.** Callers are unaffected.

**Oracle partition.** AC-1, AC-2, AC-3 and AC-5 are **mechanical**: compare to
the M2 functions' own output, never to a hand copy. AC-4 is **settled**: the
durations are `RoundConfig`'s; read them, do not restate them.

## Deferred verifications

**D-1. AC-2 discriminates.** With `scripts/mutate.sh` changing the `SendTo`
effect's `playerId` to the first seated player for every view, AC-2 **must**
fail. RED cannot run this; there is no `Session` yet. Owner: GATES.

## Out of scope

- The facility, the Procedure, the channel, positions: later stories add them.
- Performing effects: the interpreter and the driver are `SLICE-004`.
- Rejoin within the grace window (`Ring.rejoin` exists; wiring it is `SEAT-004`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-003` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table. Only what lies BETWEEN these two markers is rewritten when
this command runs again; the rest of the section is yours and is preserved.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `fable` | the measured case. With a partitioned contract to work from, the brief carries the judgement and the weaker model writes sharper negative controls than the stronger one did without it |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

Lock coverage: SUPPRESSED by `src/server/round/RoundView.luau` (source), `src/server/session/Session.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Oracle partition as in `## Contract`. Every expected value is computed by the
M2 module that owns it; RED must not hand-copy a seat view.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain:
       * the exact command that runs the new tests
       * the failure output, and why it is the RIGHT failure
       * every file touched, and which AC each test covers
       * the EXPORT SHAPE the tests already pin: every module they import, the
         exact exported names and signatures, and the types the assertions
         destructure. Not a suggestion - a test already imports them, so a
         wrong guess is a compile error. Say what the tests do NOT constrain
         too, so it stays the implementer's choice.
       * any test that passed on arrival, and the probe or negative control
         that earns it
       * the EXPECTED VALUE of every negative control, as a table: threshold,
         candidate range, and the number the control measured. In RED the
         suite fails at import, so no assertion in it has run - the controls
         are claims until GREEN confirms them against the shipped module
       * anything discovered that changes the approach -->

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A test that is wrong is never edited into passing, and the
     return is not a footnote - it is the story failing to be one clean cycle,
     and the next person needs to know why. One block per return:
       * which test, what it asserted, and what was wrong with it
       * how the defect was found
       * what it asserts now
       * what earns it, since "watched it fail" cannot apply once the
         implementation exists - the corrected assertion passes on its first
         run and every run after, whether or not it asserts anything: either a
         PROBE (mutate the specific behaviour the test pins, paste the red,
         confirm the revert) or, where the defect was cost rather than
         correctness, a BEFORE/AFTER measurement taken under the gate command -
         not the plain test command, which is the faster one.
         PASTE THE OUTPUT. check-boundaries.sh refuses a PR whose Regressions
         or Gate probes section describes a failure without showing one
       * whether GREEN was a no-op, and the command output proving the source
         was untouched and still passes -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Scaffold inventory

<!-- REQUIRED for a bootstrap or chore story that writes production code under
     SCAFFOLD, where nothing forces a test to exist first, and for a spike that
     commits its throwaway code. Omit otherwise.
     One line per production file written, and for anything with behaviour
     rather than configuration, the test that covers it:
       src/core/palette.ts        - src/core/palette.test.ts
       vite.config.ts             - configuration, no behaviour
     check-boundaries.sh refuses the PR if any changed source file is not
     named here. -->

## Notes

