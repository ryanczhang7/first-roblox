---
id: SLICE-005
title: The session runs the facility and the Procedure, and scripted turns win or lose a round
slug: the-session-runs-the-facility-and-the-pr
epic: EPIC-08
type: feature
status: todo
phase: PLANNED
branch: story/SLICE-005-the-session-runs-the-facility-and-the-pr
depends_on: [SLICE-003, GEN-004, PROC-003, PROC-005]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-08`. EPIC-04 built the facility generator and EPIC-05 built the
Procedure, each as pure modules tested alone. This story composes them into
`Session` (`architecture.md` §9.2, D22):

- When seats are dealt, the facility is generated. On failure, the round
  resolves `no_contest / generation_failed`.
- Entering `Round` starts the Procedure and places every player in
  `spawn_room`.
- `PositionsSampled` stores samples. They are unfiltered until `VIEW-004`.
- A `TurnRequested` from the guarded `Turn` remote goes through
  `TurnRequests.handle`. The turner gets a private `TurnResult`.
- On every `Tick`, the Procedure is advanced. Its outcome is fed to the phase
  machine as `RoundResolved` **in the same step**.

The evidence is a **headless round**. Four scripted players, teleported by
test code to the right rooms, win a generated facility through `Session.step`
alone. A second script loses it to instability.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given four joined players and the lobby elapsed, when the session
  steps into `Round`, then it holds a facility equal to
  `Generator.generate(assignment, seed)` for the round seed, and a Procedure
  started at that step's `now` with that seed. It also emits one `Placed` per
  player at `spawn_room`'s centre.
- **AC-2** — Given a generator that fails every attempt (an injected
  predicate), when the session steps into `Round`, then in the same step the
  phase machine records `RoundResolved{ no_contest, generation_failed }` and
  moves to `Resolution`.
- **AC-3** — Given a running round, when a `TurnRequested` arrives, then the
  Procedure sees the caller's id, the requested machine and setting, and the
  **stored** positions. The caller alone receives a `SendTo` of kind
  `TurnResult` carrying `TurnRequests.reply(result)`.
- **AC-4** — Given a script that, for each step in canonical order, places the
  step's helper and turner at the machine and turns it to its required setting,
  when it runs through `Session.step` over at least 50 seeds at each n in
  `{4, 5, 6}`, then every round ends `won / procedure_complete`, and the phase
  machine is in `Resolution` → `Post` within the next ticks.
  *Control:* the same script with turns sent from the spawn room, out of reach,
  must never win. Every turn is refused, and the round ends `lost / clock`.
- **AC-5** — Given a script that turns the live step to a wrong setting
  `instability_max` times, when it runs, then the round ends `lost /
  instability`. The deadline seen by a `RoundView` built mid-round
  (`secondsLeft`) has dropped by `instability_clock_penalty_seconds` per point.
- **AC-6** — Given a round where time alone runs out, when the Procedure's
  deadline passes, then the session records `lost / clock` on that tick, not
  later when the phase machine's backstop fires.

## Contract

`src/server/session/Session.luau`, extended. No new module.

    SessionState gains: facility: Generator.Facility?, procedure: Procedure.ProcedureState?,
                        positions: { [string]: Procedure.Vec }
    SessionEvent gains: { kind: "PositionsSampled", samples: { [string]: Procedure.Vec } }
                      | { kind: "TurnRequested", playerId: string, args: { machine: number, setting: number } }
    SessionEffect gains: { kind: "SendTo", playerId, payloadKind: "TurnResult", payload: TurnRequests.TurnReply }
                       | { kind: "Placed", playerId: string, position: Procedure.Vec }

- `Placed` is performed by the driver as a character teleport. `VIEW-004`
  reads it as the plausibility baseline.
- `TurnRequested` is built by the `Turn` remote's handler in the driver's
  `Transport.bind` call (`SLICE-007`). The event trusts the wrapper, which has
  already validated shape, range, phase and rate (`PROC-005`).
- **The within-step order** is: apply the event; if it is `Tick`, call
  `Procedure.tick`; if an outcome resulted, step the phase machine with
  `RoundResolved`; pass through every phase-machine effect.
  (`architecture.md` §9.2.)
- `RoundView.public` (`VIEW-003`) reads `Procedure.deadline` for `secondsLeft`.
  Wiring the widened view is `SLICE-006`. This story asserts `secondsLeft`
  through whatever `RoundView` exists when it runs.

**The test script** lives in `tests/helpers/ScriptedRound.luau` and is shared
with `SLICE-006`. It reads the facility's steps, helpers and turners only
through `Ring` and the facility, as a player cannot. **It is a test oracle, and
it may read the secret.**

**Existing exports.** `Session.step` and `Session.new` keep their signatures.
Their event and effect unions widen, which is additive. `SLICE-003`'s tests
must still pass unchanged.

**Oracle partition.**
- AC-1 to AC-3 and AC-6 are **mechanical**, compared against the pure modules'
  own outputs.
- AC-4 and AC-5 are **settled** outcomes over a scripted round, each with a
  control that must fail.

## Deferred verifications

**D-1. The same-step routing is real.** Use `scripts/mutate.sh` to delay feeding
the Procedure's outcome to the next tick. AC-6 **must** then fail. RED cannot
run this. Owner: GATES.

## Out of scope

- Pings, presets and the per-player views (`SLICE-006`).
- Position plausibility (`VIEW-004`).
- The real teleport and position sampling (`SLICE-007`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-005` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/session/Session.luau` (source), `tests/helpers/ScriptedRound.luau` (test), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`.

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

