---
id: TRACE-001
title: The trace times every step and labels who was waiting
slug: the-trace-times-every-step-and-labels-wh
epic: EPIC-09
type: feature
status: todo
phase: PLANNED
branch: story/TRACE-001-the-trace-times-every-step-and-labels-wh
depends_on: [SLICE-006]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-09`. The post-round trace is a pure function of logs
(`mechanics.md` §7). This story computes its two structured parts:

- **the timeline**: per step, when it went live, its first read helper ping,
  when it was turned, and each position sample labelled *waiting for helper*,
  *waiting for turner*, *waiting for the other pair* (finale only) or
  *turning*;
- **the guesses**: turns that were not informed, and whether each was right.

Every term is defined exactly in `mechanics.md` §7, G12: "read helper ping",
"informed", "gap attribution", and step numbering in par's canonical order
(T1[1] = 1, T2[1] = 2, …, finale 7 and 8).

The logs already exist:
- the actuation log (`PROC-001`);
- the ping log, with `roomLit` (`CHAN-006`);
- the preset log (`CHAN-004`).

This story adds the last two inputs to `Session`: position samples at
`trace_position_sample_seconds`, and the assignment's changes over time. The
second is needed because "the player holding the lens at that moment" changes
with a disconnect.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a hand-built facility and logs, when `Trace.timeline` runs,
  then each step's `wentLive` is:
  - the round start, for a track's first step;
  - its predecessor's commit time, for any other ordinary step;
  - the last ordinary commit time, for both finale steps.

  Its `firstReadPing` is the earliest read helper ping on its machine, and its
  `turned` is its commit time. Steps are numbered in canonical order.
  *Control:* a timeline that numbers steps by commit order must fail a fixture
  where track 2's first step commits before track 1's.
- **AC-2** — Given a hand-built facility with a dark room, when the ping log
  contains a setting ping in that room by the lens holder, then that ping is not
  a read helper ping. A ping by a non-holder never is.
- **AC-3** — Given position samples, when gaps are labelled for a step from
  went-live to committed, then each sample is *waiting for helper* while no read
  helper ping exists yet. It is *waiting for turner* while one exists and the
  turner is outside `turn_range_studs`. Otherwise it is *turning*. On a finale
  step, a sample whose own conditions are met while the other finale step's are
  not is *waiting for the other pair*.
- **AC-4** — Given the actuation log, when `Trace.guesses` runs, then it lists
  every evaluated turn with no read helper ping on its machine at any earlier
  time, and whose turner did not hold the machine's lens at the time of the
  turn. Each entry records whether the turn committed or was armed (right) or
  was rejected (wrong).
  *Control:* a guess list that counts only pings made while the step was live
  must fail a fixture with an early ping (`mechanics.md` §7: "an early ping
  counts").
- **AC-5** — Given the lens holder changing mid-round (a disconnect transfer in
  the assignment log), when a turn by the inheritor on a transferred machine is
  classified, then it is informed. The inheritor holds the lens for that class
  after the transfer.

## Contract

**Module.** `src/server/trace/Trace.luau`, pure.

    export type Label = "waiting_for_helper" | "waiting_for_turner" | "waiting_for_other_pair" | "turning"
    export type StepTimeline = { step: number, wentLive: number, firstReadPing: number?, turned: number?,
                                 samples: { { at: number, label: Label } } }
    export type Guess = { step: number?, machineId: number, at: number, right: boolean }  -- step nil for a decoy
    export type Logs = { actuation: { Procedure.ActuationLogEntry }, pings: { Pings.PingLogEntry },
                         presets: { PresetSends.PresetLogEntry },
                         positions: { { at: number, positions: { [string]: Procedure.Vec } } },
                         assignments: { { at: number, assignment: Ring.Assignment } },
                         roundStart: number }
    Trace.timeline(facility: Generator.Facility, logs: Logs, tuning) -> { StepTimeline }
    Trace.guesses(facility: Generator.Facility, logs: Logs) -> { Guess }

`Session` gains `logs.positions`, sampled at `trace_position_sample_seconds`
from accepted positions, and `logs.assignments`, appended on every ring
change. It computes nothing from them. `TRACE-002` builds the view.

**Oracle partition.** AC-1 to AC-5 are **settled** by `mechanics.md` §7's
definitions. Every fixture is hand-built, with its expected labels written as a
table in the test.

## Deferred verifications

**D-1. Early pings count.** Use `scripts/mutate.sh` to restrict the informed
check to pings after `wentLive`. AC-4 **must** then fail. RED cannot run this.
Owner: GATES.

## Out of scope

- The headline, par against actual, and the view (`TRACE-002`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write TRACE-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/trace/Trace.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

