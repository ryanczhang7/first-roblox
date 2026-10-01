---
id: TRACE-002
title: The trace leads with one sentence and par against actual, naming no player
slug: the-trace-leads-with-one-sentence-and-pa
epic: EPIC-09
type: feature
status: todo
phase: PLANNED
branch: story/TRACE-002-the-trace-leads-with-one-sentence-and-pa
depends_on: [TRACE-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-09`. The trace a player reads (`mechanics.md` §7):

- **The headline.** The longest contiguous run of one *waiting* label on one
  step, in one of four fixed sentences. The number of seconds is rounded down,
  and ties go to the earlier run. When no run reaches
  `trace_headline_min_wait_seconds`, the sentence is "Nobody waited long." A
  no-contest round has no headline.
- **Par against actual.** The finishing time, or the final progress count,
  against the facility's stored par.
- The timeline and guesses from `TRACE-001`.

**It names steps, never players (T14).** `architecture.md` §9.11 makes that
structural: the `TraceView` type has no player field. It is broadcast once,
entering `Post`, which is the `ComputeTrace` effect the phase machine has
emitted since M1.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given hand-built timelines, when `Trace.headline` runs, then it
  returns one of the four sentence templates, filled with the step number and
  the whole seconds of the longest waiting run. Ties go to the earlier run. When
  no run reaches `trace_headline_min_wait_seconds`, it returns the fallback. A
  `no_contest` outcome returns no headline. Every result is at most 60
  characters.
  *Control:* a headline that rounds to the nearest second must fail a 40.6 s
  fixture.
- **AC-2** — Given an outcome and a facility, when `Trace.view` builds par
  against actual, then a win carries `{ finishedAt − roundStart, par }`, and a
  loss carries `{ committed, total, par }`. `committed` equals the last
  `RoundView.progress.committed`.
- **AC-3** — Given any `TraceView`, when every string and scalar in it is
  collected, then no seated player's id or name appears. The type declares no
  field of player type.
  *Control:* a view that includes a `turnerId` per step must fail.
- **AC-4** — Given the session entering `Post`, when effects are read, then
  exactly one `Broadcast` of kind `TraceView` is emitted, from the
  `ComputeTrace` step.

## Contract

**Module.** `src/server/trace/Trace.luau`, extended:

    export type TraceView = {
        outcome: { result: string, reason: string },
        headline: string?,
        par: number, actual: { seconds: number }? , reached: { committed: number, total: number }?,
        timeline: { { step: number, machineTag: number, room: number, wentLive: number,
                      firstReadPing: number?, turned: number?, gaps: { { label: string, seconds: number } } } },
        guesses: { { step: number?, machineTag: number, right: boolean } },
    }
    Trace.headline(timeline: { StepTimeline }, outcome, tuning) -> string?
    Trace.view(facility, logs, outcome, finalProgress, tuning) -> TraceView

- The sentence templates are data in this module, and are the exact strings in
  `mechanics.md` §7. A test reads them from the doc through `GatedFs`: the
  Lead PO added `mechanics.md`'s `covers` line at planning. The test never
  restates them.
- Times in the view are **seconds since round start**, never server clock
  values.

**Oracle partition.**
- AC-1 and AC-2 are **settled** by `mechanics.md` §7.
- AC-3 and AC-4 are **mechanical**.

## Deferred verifications

**D-1. The no-player property discriminates.** Use `scripts/mutate.sh` to add
the turner's id to each timeline row. AC-3 **must** then fail. RED cannot run
this. Owner: GATES.

## Out of scope

- The screen (`HUD-005`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write TRACE-002` from `.claude/harness/models.conf`.
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

