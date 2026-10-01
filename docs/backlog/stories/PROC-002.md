---
id: PROC-002
title: The finale commits only when both machines are turned inside the window
slug: the-finale-commits-only-when-both-machin
epic: EPIC-05
type: feature
status: todo
phase: PLANNED
branch: story/PROC-002-the-finale-commits-only-when-both-machin
depends_on: [PROC-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. **The finale** (`mechanics.md` §3.2 and §5, G5 and G12; the
case list is exact in §5):

- The last step of each track forms one paired operation.
- **Both finale steps go live together**, once every ordinary step of both
  tracks is committed (`finale_live_together`).
- A correct turn on a live finale machine, when neither is armed, **arms** it
  and opens a window of `simultaneous_window_seconds` at that turn's server
  time.
- A correct turn on the other machine at or before the window's end commits
  **both**, together, at that time.
- A **wrong** turn on either machine is rejected like any wrong turn (+1). If a
  window is open, it closes and both machines disarm **with no second
  penalty**.
- A window reaching its end with one machine armed disarms both, at a cost of
  +1.
- In every case, one failed attempt at the finale costs exactly 1.

**The partner lamp.** Machine A's partner lamp is lit while the finale is live
**and** the holder of B's key class is within `partner_lamp_range_studs` of B,
and the same holds the other way round.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a Procedure with one ordinary step left in track 1 and track
  2's ordinary steps all committed, when `isLive` is asked about both finale
  machines, then neither is live. The moment the last ordinary step commits,
  both are live.
  *Control:* a rule that lights track 2's finale as soon as its own track is
  done must fail.
- **AC-2** — Given a live finale with neither machine armed, when machine A is
  turned correctly at `t`, then the result is `armed` and instability is
  unchanged. When B is then turned correctly at any `t' ≤ t +
  simultaneous_window_seconds`, both commit at `t'` and the Procedure is
  complete.
- **AC-3** — Given A armed at `t`, when `tick` runs at `t +
  simultaneous_window_seconds + ε` with B unturned, then both disarm, instability
  rises by exactly `instability_per_failed_pair` (1), and A's dial shows
  rejected until `actuation_reset_seconds` later.
- **AC-4** — Given A armed, when B is turned to a wrong setting inside the
  window, then the result is `rejected / wrong_setting`, both disarm, and
  instability rises by exactly 1 in total, not 2.
  *Control:* an implementation that charges the wrong turn and the closed window
  separately must fail, scoring 2.
- **AC-5** — Given A armed, when A is turned again, then it is `refused / armed`
  at no cost.
- **AC-6** — Given a live finale and accepted positions, when
  `Procedure.partnerLamps` is read, then A's lamp is lit exactly when the holder
  of B's class is within `partner_lamp_range_studs` of B (horizontally), and B's
  lamp the same way round. Both lamps are dark while the finale is not live.
  *Control:* a lamp that reads the holder's distance to *A* must fail a fixture
  where B's holder is standing at A.
- **AC-7** — Given the window's edge, when B is turned at exactly `t +
  simultaneous_window_seconds`, then both commit. The window is inclusive at its
  end, matching the rate limiter's inclusive comparison.

## Contract

**Module.** `src/server/procedure/Procedure.luau`, extended. This story adds:

    ProcedureState.armed: { machineId: number, closesAt: number }?
    Procedure.tick(state, assignment: Ring.Assignment, now: number, positions) -> (ProcedureState, Outcome?)
        -- this story: closes an expired window. PROC-003 adds instability consequences and outcomes.
    Procedure.partnerLamps(state, assignment, positions) -> { [number]: boolean }   -- finale machine id -> lit
    Procedure.isComplete(state) -> boolean

- `TurnResult`'s `armed` variant and the `refused / armed` reason already exist
  in `PROC-001`'s types. This story gives them behaviour.
- A disarmed machine's dial resets after `actuation_reset_seconds`, like any
  rejection (`mechanics.md` §5).
- At n = 3 after a disconnect, the finale's two key classes may belong to ring
  neighbours or to one player. The rules above do not change. One player
  holding both classes can arm A and walk to B inside the window only if the
  rooms are close enough, and that is the degraded round `roles.md` §6
  describes. There is no special case.

**Existing exports: none changed.** `PROC-001`'s signatures are kept. `tick`
is new.

**Oracle partition.** Every criterion is **settled** by `mechanics.md` §5's exact
case list. Each test names the case it pins.

## Deferred verifications

**D-1. One failed attempt, one point.** Use `scripts/mutate.sh` to add the
failed-pair penalty on the wrong-turn-with-window-open path. AC-4 **must** then
fail with 2. RED cannot run this. Owner: GATES.

## Out of scope

- What the lamps look like (`HUD-002`).
- Outcomes (`PROC-003`). `isComplete` is the fact `PROC-003` turns into
  `won / procedure_complete`.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-002` from `.claude/harness/models.conf`.
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

