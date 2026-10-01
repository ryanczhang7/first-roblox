---
id: TUNE-001
title: Instance, channel and actuation constants match their specification
slug: instance-channel-and-actuation-constants
epic: EPIC-04
type: feature
status: todo
phase: PLANNED
branch: story/TUNE-001-instance-channel-and-actuation-constants
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-04`. `tuning.md` is the specification of every constant. Its §1 and
§5 are implemented in `src/shared/Tuning.luau` and guarded by ROUND-002's
`tests/helpers/TuningSpec.luau`. §2 (the instance and the layout), §3 (pings and
presets) and §4 (actuation, instability and the HUD's round state) have **no
module yet**. `Tuning.luau`'s header deferred them until the mechanics that read
them existed, and every M3 story from here on reads them.

`architecture.md` D19 puts them in a second module, `MechanicsTuning`, with its
own drift guard. ROUND-002's frozen guard asserts that `Tuning.luau` carries §1
and §5 exactly, so adding sub-tables there would turn it red.

This story also closes two loose ends:

- `Tuning.luau`'s header promised that `per_operation_seconds = (round_seconds −
  traversal_reserve_seconds) / procedure_length` would "become a test" once
  `procedure_length` existed.
- Two stale comments in `Tuning.luau`: line 15 names "the signal channel", and
  line 71 labels `players_max` "derived: channel contention", which `tuning.md`
  §1 has called a placeholder since the third pass.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `tuning.md` §2, §3 and §4 parsed off disk, when every row
  whose first cell is a bare backticked name (and whose name does not start with
  `INV_`) is classified, then each is exactly one of four kinds:
  - **number** — the value cell is a bare decimal;
  - **boolean** — the value cell is `true` or `false`;
  - **reference** — the value cell is exactly `` = `other_name` ``;
  - **rule** — the name is in the guard's explicit `RULE_ROWS` list.

  A row that fits none of these fails the test, naming the row. So does a name
  in `RULE_ROWS` that the document gives a number or a boolean.
  *Control:* a document fixture with a new row `` `foo_seconds` | 5 s `` must
  fail, naming `foo_seconds`.
- **AC-2** — Given the same rows, when they are compared with
  `MechanicsTuning`, then every number and boolean row exists under the
  module's table for its section (§2 → `instance`, §3 → `channel`,
  §4 → `actuation`) with an equal value. Every reference row exists there with
  a value equal to the module's value for the named constant. Rule rows are
  absent from the module. The module has no key that no row names.
  *Controls:* a module with `dial_settings` = 5 must fail, naming 4 and 5. A
  module with an extra key `vocabulary_size` must fail, naming it. A module
  missing `ping_display_seconds` must fail, naming it.
- **AC-3** — Given the parser, when it runs over the real document, then it
  finds at least one row in each of §2, §3 and §4, and fails rather than
  compares nothing if any section yields zero rows.
- **AC-4** — Given `MechanicsTuning` and `Tuning`, when the derived relations
  the document states are computed from module values, then they hold:
  - `actuator_count = procedure_length × actuator_redundancy`;
  - `steps_per_track = procedure_length / procedure_tracks`;
  - `machine_spacing_min_studs = 2 × turn_range_studs`;
  - `machines_per_class_max = ceil(procedure_length / players_min) × actuator_redundancy`;
  - `Tuning.round.per_operation_seconds = (round_seconds − traversal_reserve_seconds) / procedure_length`;
  - `preset_count + ping_kinds ≤ presets_plus_pings_max`.

  *Control:* the `per_operation_seconds` relation must fail against a fixture
  whose `procedure_length` is 9.
- **AC-5** — Given `MechanicsTuning`, when any consumer tries to assign to it,
  to any of its three tables, or to a nested value, then the assignment raises.
  The whole structure is frozen, as `Tuning` is.

## Contract

**Module.** `src/shared/MechanicsTuning.luau`, shared, frozen data. Keys are the
specification's snake_case names, verbatim, as in `Tuning.luau`.

    export type MechanicsTuning = {
        instance: { [string]: number | boolean },   -- tuning.md §2, including "The layout" sub-table
        channel: { [string]: number | boolean },    -- tuning.md §3
        actuation: { [string]: number | boolean },  -- tuning.md §4, including the HUD sub-table
    }

Write each table with named fields so `--!strict` catches a typo. The loose map
type above is the guard's view; GREEN may declare a precise record type per
table. Reference rows are stored as **values**, with a comment naming the
referent. The guard, not the module, proves the equality.

**The guard.** `tests/helpers/MechanicsTuningSpec.luau` reads `tuning.md`
through `GatedFs`. It selects sections by `## N.` heading number, as
`TuningSpec` does, and takes rows whose first cell, trimmed, is exactly a
backticked name. Sub-tables under `###` headings belong to their `##` section.
The invariants table is excluded by the `INV_` prefix. `RULE_ROWS` as of this
planning pass, verified by a parse on 2026-09-30:

    key_classes, actuators_per_class, spawn_room,               -- §2
    channel_limiter_consumed_by, ping_budget_per_player,        -- §3
    blackout_selection, hud_round_clock_form                    -- §4

Counts from the same parse, which RED re-measures rather than trusting:

| Section | Number rows | Boolean rows | Reference rows |
|---|---|---|---|
| §2 | 31 | 3 | 6 |
| §3 | 9 | 4 | 1 |
| §4 | 11 | 8 | 0 |

**Do not reuse `TuningSpec.parse` or `RateLimitSpec`.** Their scopes are
deliberately narrower, as `RateLimitSpec`'s header explains. This guard is a
sibling, not an extension.

**`Tuning.luau`** keeps its values unchanged. Only two comments change: line
15 ("the signal channel" becomes "the channel") and line 71 (`players_max`'s
label becomes "placeholder: tuning.md §1, replace via playtest P-N").
ROUND-002's guard does not read comments.

**Existing exports: no signature changes.**

**At GATES, by the orchestrator:** raise `project.conf`'s `floor | unit` from 443
to the suite count this story lands with. It has been 443 since before
ROUND-006's 476, and a floor below the real count lets a lost file of tests go
unnoticed.

**Oracle partition.** AC-2 and AC-4 are **settled**: the values and relations
are `tuning.md`'s. Read them out, and never restate a number in a test. AC-1 and
AC-3 are **mechanical**, with fixture controls for every vacuity step. AC-5 is
**mechanical**.

## Deferred verifications

**D-1. A wrong value is caught, not only a missing one.** Use `scripts/mutate.sh`
to set `MechanicsTuning`'s `lens_read_range_studs` to 13. AC-2 **must** then
fail, naming it. So must the reference row `ping_range_studs`, which now
disagrees with its referent. RED cannot run this, because the module does not
exist. Owner: GATES.

**D-2. A removed key is caught.** Use `scripts/mutate.sh` to delete the
`turn_rate_limit_seconds` line. AC-2 **must** then fail, naming it. Owner: GATES.

## Out of scope

- Any consumer of these constants. Each arrives with its mechanic.
- `tuning.md` itself, which belongs to the Game Designer. If the guard finds the
  document inconsistent, RED stops and the Lead PO takes it to the Game
  Designer.
- The `players_max` value, which stays 6.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write TUNE-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/shared/MechanicsTuning.luau` (source), `tests/helpers/MechanicsTuningSpec.luau` (test), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`. RED reads every value from the document or the
module and never from this story.

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

