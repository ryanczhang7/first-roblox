---
id: PROC-003
title: Instability shortens the clock, darkens rooms and ends the round in a fixed order
slug: instability-shortens-the-clock-darkens-r
epic: EPIC-05
type: feature
status: todo
phase: PLANNED
branch: story/PROC-003-instability-shortens-the-clock-darkens-r
depends_on: [PROC-002]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. What instability does (`mechanics.md` §5; `tuning.md` §4; G7 and
G12):

- **Clock.** Each point removes `instability_clock_penalty_seconds`
  immediately.
- **Blackout.** At each multiple of `instability_blackout_threshold` below
  `instability_max`, the server draws `blackout_rooms_per_threshold` rooms. It
  draws without replacement from rooms not yet dark, with probability
  proportional to each room's weight. A room's weight is the sum over its
  uncommitted steps of `blackout_weight_live_step` (live or armed) and
  `blackout_weight_waiting_step` (waiting). Decoys and committed steps weigh 0.
  If every lit room weighs 0, the draw is uniform among lit rooms. A dark room
  is never drawn again, and blackout is permanent. The draw uses the round
  seed's `rng:derive("blackout")`.
- **Loss** at `instability_max`.
- **Outcomes**, and the order they resolve in within one event: a win
  (`won / procedure_complete`) first, then `lost / instability`, then
  `lost / clock`.

`architecture.md` D11 makes the Procedure the owner of the round's deadline:
`roundStart + round_seconds − penalties`. The phase machine's own clock is a
backstop that can never fire first.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a Procedure started at `t0`, when `Procedure.deadline` is
  read, then it is `t0 + round_seconds`. After k instability points, it is
  `t0 + round_seconds − k × instability_clock_penalty_seconds`.
- **AC-2** — Given instability rising from `threshold − 1` to `threshold`, when
  the turn that caused it returns, then exactly `blackout_rooms_per_threshold`
  lit rooms are dark, and they were drawn by the specified weighting. Rising to
  a non-multiple darkens nothing. Reaching `instability_max` darkens nothing,
  because the round ends first.
- **AC-3** — Given a facility where one lit room holds all the uncommitted
  steps and the other lit rooms hold only decoys or committed steps, when a
  crossing happens, then that room is always the one darkened. Given rooms of
  weights 3 and 1 and 20,000 seeded crossings, the heavier room is chosen with
  frequency 0.75 ± 0.02.
  *Controls:* a uniform draw must fail both. It picks the zero-weight rooms
  and scores about 0.5 on the second.
- **AC-4** — Given every lit room at weight 0, when a crossing happens, then a lit
  room is still darkened (a uniform draw). Given every room already dark, then
  nothing happens and nothing raises. An already-dark room is never drawn.
- **AC-5** — Given one seed, when the same sequence of wrong turns is replayed,
  then the same rooms go dark in the same order. Drawing from the `"blackout"`
  sub-stream moves no generator draw.
- **AC-6** — Given the last finale commit, when it arrives before the deadline,
  then `tick` or `turn` yields `{ result = "won", reason =
  "procedure_complete" }`. When a wrong turn takes instability to
  `instability_max` **and** its penalty takes the clock to 0 or below, then the
  outcome is `lost / instability`. When the deadline passes by time alone, it is
  `lost / clock`.
  *Control:* an implementation that checks the clock before instability must
  fail the second clause.
- **AC-7** — Given the Procedure has produced an outcome, when any later turn
  or tick arrives, then the state and the outcome do not change. A decided round
  stays decided.
- **AC-8** — Given a dark room, when `Procedure.isDark(room)` is read, then it is
  true for the rest of the round. `VIEW-001` reads this to withhold lens
  contents there.

## Contract

**Module.** `src/server/procedure/Procedure.luau`, extended. This story adds:

    ProcedureState.startedAt: number
    ProcedureState.penaltySeconds: number
    ProcedureState.dark: { [number]: boolean }      -- room id -> dark
    ProcedureState.outcome: PhaseMachine.Outcome?
    ProcedureState.blackoutRng: Rng.Rng             -- Rng.fromSeed(roundSeed):derive("blackout")
    Procedure.start(facility, now, tuning, roundSeed: number) -> ProcedureState   -- CHANGED: gains roundSeed
    Procedure.deadline(state) -> number
    Procedure.isDark(state, room: number) -> boolean
    Procedure.blackoutWeights(state) -> { [number]: number }   -- lit room -> weight; exported for AC-3

- **Changed signature: `Procedure.start` gains `roundSeed`.** Callers as of
  `PROC-002`'s DONE: `tests/server/procedure_*` only. RED lists them from the
  tree and updates them in this RED. That is a change to its own epic's tests,
  not to a frozen DONE story's test, **provided `PROC-001` and `PROC-002` are
  the only callers**. Confirm with `rg "Procedure.start" src tests`.
- `Outcome` is the phase machine's type. `src/server/procedure/` may require
  `src/server/round/` (same layer).
- The draw: build the list of lit rooms in ascending id, compute the weights,
  and draw with `blackoutRng:nextInteger` over the cumulative integer weights.
  Weights are integers (both weight constants are integers). The uniform
  fallback draws over the list itself.

**Oracle partition.** AC-1, AC-2, AC-4 and AC-6 to AC-8 are **settled** by
`mechanics.md` §5 and `tuning.md` §4: read every number from `MechanicsTuning`
or `Tuning`. AC-3's first clause is **settled** (zero weight is never drawn
while a positive weight exists). Its second clause is **oracle-free**, a
frequency with a uniform draw as its control. AC-5 is **mechanical**.

## Deferred verifications

**D-1. The weighting is what separates the rooms.** Use `scripts/mutate.sh` to
make every weight 1. AC-3 **must** then fail on both clauses. RED cannot run
this. Owner: GATES.

**D-2. Order of outcomes.** Use `scripts/mutate.sh` to swap the instability and
clock checks. AC-6's second clause **must** then fail. Owner: GATES.

## Out of scope

- Telling players (`VIEW-003` carries instability, the deadline and dark rooms,
  and `HUD-001` shows them).
- Feeding the outcome to the phase machine (`SLICE-005`).
- `unwinnable`, which has no M3 trigger (`mechanics.md` §8).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-003` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/procedure/Procedure.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

