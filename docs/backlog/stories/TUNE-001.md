---
id: TUNE-001
title: Instance, channel and actuation constants match their specification
slug: instance-channel-and-actuation-constants
epic: EPIC-04
type: feature
status: in-progress
phase: RED
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
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1, as the agent reported
  of itself). Planned `fable`; dispatched with an explicit `model: fable`, which
  beat the definition's `model: opus`. 2026-09-30.

## Test plan

All unit level, under the repository's Lune runner (`lune run test`). Three
files, the ROUND-002 shape: a helper of check objects, a file that applies them
to the real module, and a controls file that requires **no production code** so
its assertions run in RED.

**`tests/helpers/MechanicsTuningSpec.luau`** - the guard. Parses `tuning.md`
through `GatedFs`, selects §2/§3/§4 by `## N.` heading (a `###` line does not
change the section), takes rows whose first cell is exactly one backticked name,
drops `INV_*`, classifies every remaining row as exactly one of number / boolean
/ reference / rule (`RULE_ROWS`, the contract's seven names), and reports
anything else as a parse problem. Check objects: `assertNoParseProblems` (AC-1),
`assertEverySectionHasRows` (AC-3), `missingOrMismatched` + `unspecified`
(AC-2, both directions; rule rows must be absent; a reference row must equal
the module's own value for its referent), `relationFindings` (AC-4, the six
relations, every operand read from a module-shaped table),
`freezeFindings` (AC-5, one attempted write per root table, per key and per
"new key", must raise AND leave the value unchanged). No number from the
document appears in it.

**`tests/helpers/MechanicsTuningFakes.luau`** - the baseline fake, built from
the parsed real rows (references resolved to their referent's value), plus
`with(table, key, value)`, `frozen()`, `frozenRootOnly()`, `frozenExcept(t)`,
`empty()`. Not a specification of the module.

**`tests/shared/mechanics_tuning_spec_test.luau`** - against the real module
(7 tests):

| Test | AC | Status in RED |
|---|---|---|
| every backticked row of §2-§4 is exactly one of the four kinds | AC-1 | **passes on arrival** (document exists) - earned by the fixture controls and by probe A below |
| at least one row from each of §2, §3, §4 | AC-3 | **passes on arrival** - earned by the fixture controls and by probe B below |
| every constant row is in `MechanicsTuning` with its value; no rule row is | AC-2 | fails: module absent |
| every key `MechanicsTuning` exposes is named by a constant row | AC-2 | fails: module absent |
| `MechanicsTuning` exposes exactly `instance`, `channel`, `actuation` | AC-2 (contract shape) | fails: module absent |
| every derived relation holds between `MechanicsTuning` and `Tuning` values | AC-4 | fails: module absent |
| assigning to the module, any table, or any nested value raises and changes nothing | AC-5 | fails: module absent |

**`tests/shared/mechanics_tuning_controls_test.luau`** - 24 controls, all
green in RED, none requiring `src/`. Two baselines; AC-1 x4 (the `5 s` row,
`spawn_room` given a number and a boolean, fixture collection incl. `###`
sub-tables / INV_ / §1 / §5 / §9 / struck-through exclusion, a 16-case cell
classifier table); AC-3 x2 (zero rows compare CLEAN then the floor fires; a §3
heading that no longer matches names §3 only); AC-2 x8 (`dial_settings` 5,
extra `vocabulary_size`, missing `ping_display_seconds`, a reference row that
disagrees with its referent, a referent moved alone naming both rows - D-1's
shape on the fake -, a rule row carried as a value, a boolean carried as a
number, a missing table); AC-4 x4 (baseline: every relation holds on the
document's own values; `procedure_length` 9; `preset_count` at the ceiling; a
missing operand); AC-5 x4 (frozen passes / unfrozen fails everywhere,
root-only freeze fails on nested writes only, one unfrozen table blamed alone,
a swallowing `__newindex` counts as a write that succeeded).

**Cost.** The whole suite runs in ~38 s locally (507 cases) with the new files
adding well under a second of that; the only I/O is one `GatedFs` read of
`tuning.md` per file, memoised, and no test spawns anything else. No per-test
timeouts exist in this runner, so there is nothing to budget.

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

**Command.** From the repository root:

    lune run test

The runner has no file filter; it walks `tests/` and prints one line per case.
The lines that matter are the ones for `tests/shared/mechanics_tuning_*`.
Fast gates: `bash scripts/gates.sh --fast`.

**Failure output, verbatim (RED, 2026-10-01, local run, 507 cases).** The five
failing cases all fail at the same line, for the right reason - the module does
not exist. The two parse-only cases pass; see "passed on arrival" below.

      pass  tests/shared/mechanics_tuning_spec_test.luau :: AC-1: every backticked row of tuning.md §2-§4 is exactly one of number, boolean, reference or rule
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-2: MechanicsTuning exposes exactly the tables instance, channel and actuation
            C:\Users\ryanc\Projects\first-roblox\tests\shared\mechanics_tuning_spec_test:42: src/shared/MechanicsTuning.luau did not load: error requiring module "../../src/shared/MechanicsTuning": could not resolve child component "MechanicsTuning"
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-2: every constant row of tuning.md §2-§4 is in MechanicsTuning with its specified value, and no rule row is
            C:\Users\ryanc\Projects\first-roblox\tests\shared\mechanics_tuning_spec_test:42: src/shared/MechanicsTuning.luau did not load: error requiring module "../../src/shared/MechanicsTuning": could not resolve child component "MechanicsTuning"
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-2: every key MechanicsTuning exposes is named by a constant row of tuning.md §2-§4
            C:\Users\ryanc\Projects\first-roblox\tests\shared\mechanics_tuning_spec_test:42: src/shared/MechanicsTuning.luau did not load: error requiring module "../../src/shared/MechanicsTuning": could not resolve child component "MechanicsTuning"
      pass  tests/shared/mechanics_tuning_spec_test.luau :: AC-3: the guard parses at least one row from each of tuning.md §2, §3 and §4
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-4: every derived relation tuning.md states holds between MechanicsTuning and Tuning values
            C:\Users\ryanc\Projects\first-roblox\tests\shared\mechanics_tuning_spec_test:42: src/shared/MechanicsTuning.luau did not load: error requiring module "../../src/shared/MechanicsTuning": could not resolve child component "MechanicsTuning"
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-5: assigning to MechanicsTuning, to any of its three tables, or to any nested value raises and changes nothing
            C:\Users\ryanc\Projects\first-roblox\tests\shared\mechanics_tuning_spec_test:42: src/shared/MechanicsTuning.luau did not load: error requiring module "../../src/shared/MechanicsTuning": could not resolve child component "MechanicsTuning"
    502 passed, 5 failed

The module is loaded through `pcall(require, ...)` so that the five criteria
fail by name rather than as one `LOAD FAIL`. All 24 cases in
`mechanics_tuning_controls_test.luau` pass; that file requires nothing under
`src/`, by design, so its assertions genuinely executed in RED.

**Files touched (all new, all `test` under `paths.conf`; nothing under `src/`,
no manifest, no config):**

- `tests/helpers/MechanicsTuningSpec.luau` - the guard (AC-1..AC-5 check objects)
- `tests/helpers/MechanicsTuningFakes.luau` - baseline and wrong fakes for the controls
- `tests/shared/mechanics_tuning_spec_test.luau` - real-module tests (AC mapping in `## Test plan`)
- `tests/shared/mechanics_tuning_controls_test.luau` - the controls (AC mapping in `## Test plan`)
- `.claude/tests/project-counters.test.sh` (`harness`, writable every phase):
  `BASE_FORMAT`/`BASE_LINT` 92 → 96 and the LAST MEASURED entry, read from the
  suite's own failure lines under `gates.sh --fast`, as HARNESS-022's RED did.
  **GREEN moves them again** when `src/shared/MechanicsTuning.luau` lands:
  96/96/17 → 97/97/18, narrow 17 → 18, `NARROW_TYPECHECK` 7 → 8.
- this story file: `## Test plan`, this section

**`bash scripts/gates.sh --fast` shape (2026-10-01, local).** `format` PASS
(96 files), `lint` PASS (96), `typecheck` PASS (17 - no src change),
`build` PASS; `unit` FAIL with exactly the five assertions above (`502 passed,
5 failed`, 64 s under the gate); `harness` FAIL on one precondition only -
"the working tree carries no stray .luau files" - because the four new files
are untracked until committed (`project-counters: 39 passed, 1 failed` after
the baseline move; 33/7 before it). No timeout, config or lint failure touches
the new files, so they are admissible to the gates that will judge them. The
`unit` floor (443) is below the count this story lands with (507 cases); the
contract has the orchestrator raise it at GATES.

**The export shape the tests already pin** (a test imports it; a different
guess is a failing test, not a style choice):

- Module path: `src/shared/MechanicsTuning.luau`, required as
  `require("../../src/shared/MechanicsTuning")` from `tests/shared/`. It must
  return a **table**.
- Its keys are exactly `instance`, `channel`, `actuation` - no more, no fewer
  (the "exposes exactly the tables" test sorts and compares the key list). Each
  is a table.
- `instance` carries every §2 constant row (31 numbers, 3 booleans, 6
  references = **40 keys**), `channel` every §3 row (9 + 4 + 1 = **14 keys**),
  `actuation` every §4 row (11 + 8 + 0 = **19 keys**), with the keys being the
  document's snake_case names verbatim. The `###` sub-tables ("The layout" in
  §2, "What the HUD shows" in §4) are included. **73 keys in total.**
- Values: a number row's value is a Luau `number` equal to the document's; a
  boolean row's is a Luau `boolean` (`typeof(actual) == row.kind` is checked,
  so `1` for `true` fails). A reference row (e.g. `ping_range_studs` = `` =
  `lens_read_range_studs` ``) is stored as a **value** equal to the module's
  own value for the referent; the referent may live in a different table
  (`channel.ping_range_studs` == `instance.lens_read_range_studs`). Chains
  resolve: `tag_alphabet_size` = `machines_per_class_max`, both numbers.
- The seven `RULE_ROWS` names (`key_classes`, `actuators_per_class`,
  `spawn_room`, `channel_limiter_consumed_by`, `ping_budget_per_player`,
  `blackout_selection`, `hud_round_clock_form`) must be **absent** from every
  table; a module carrying one fails AC-2 in both directions.
- AC-4 reads `MechanicsTuning.instance.{actuator_count, procedure_length,
  actuator_redundancy, steps_per_track, procedure_tracks,
  machine_spacing_min_studs, turn_range_studs, machines_per_class_max}`,
  `MechanicsTuning.channel.{preset_count, ping_kinds, presets_plus_pings_max}`
  and `Tuning.session.players_min`, `Tuning.round.{per_operation_seconds,
  round_seconds, traversal_reserve_seconds}` as numbers. `Tuning` is required
  directly (it exists); no change to its exports is pinned or expected.
- AC-5: a write to the module table (replace a sub-table, add a key), to each
  sub-table (overwrite **every** existing key, add a key) must **raise** and
  leave the value unchanged. `table.freeze` on all four tables satisfies it, as
  `Tuning.luau` does. A `__newindex` that raises also satisfies it; one that
  swallows silently does not.

**What the tests do NOT constrain:** key order; whether each table has a precise
record type or the contract's loose map type; comments (including the referent
comment on a reference row); which freezing mechanism; the error text of a
refused write; the module header. `Tuning.luau`'s two comment edits (contract)
are invisible to every test.

**Callers of changed signatures: none - checked against the tree.** `grep -rln
MechanicsTuning src tests` returns only the four new test files; nothing under
`src/` names it, and `Tuning.luau`'s exports are untouched.

**Tests that passed on arrival, and what earns them.** The two parse-only cases
in `mechanics_tuning_spec_test.luau` are green because `tuning.md` exists. Each
has fixture controls in the controls file (AC-1: the `5 s` row, the rule-row
given a number; AC-3: the zero-row vacuity control and the broken `## 3.`
heading), and each was probed against the REAL document with
`scripts/mutate.sh` (restore verified byte-for-byte both times):

*Probe A* - `s/^| \`room_count\` | 6 |/| \`room_count\` | 6 s |/` on
`docs/wiki/game/tuning.md`:

      FAIL  tests/shared/mechanics_tuning_controls_test.luau :: baseline: the real tuning.md parses with no problems and a row in every section
      docs/wiki/game/tuning.md:76 §2: "room_count" = "6 s" is none of number, boolean, reference (= `name`) or a RULE_ROWS name
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-1: every backticked row of tuning.md §2-§4 is exactly one of number, boolean, reference or rule
      docs/wiki/game/tuning.md:76 §2: "room_count" = "6 s" is none of number, boolean, reference (= `name`) or a RULE_ROWS name
    500 passed, 7 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20261001T002353Z.1320554.bak) ===

*Probe B* - `s/^## 3\. The channel/## The channel/`:

      FAIL  tests/shared/mechanics_tuning_controls_test.luau :: baseline: the real tuning.md parses with no problems and a row in every section
      §3 (-> MechanicsTuning.channel): 0 rows parsed
      FAIL  tests/shared/mechanics_tuning_spec_test.luau :: AC-3: the guard parses at least one row from each of tuning.md §2, §3 and §4
      §3 (-> MechanicsTuning.channel): 0 rows parsed
    496 passed, 11 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20261001T002439Z.1324344.bak) ===

Probe B also turned four AC-2/AC-4 controls red with "the check passed, so the
check is vacuous": with §3 unnumbered its rows fall into §2's bucket, and the
fakes keyed on `channel.*` compare against nothing. That is the vacuous pass
AC-3 exists to prevent, observed rather than described.

**Negative controls - expected and measured.** The controls file requires no
production code, so every value below was **measured in RED**, both inside the
suite (the control passed) and outside it (a plain Lune script calling the
helpers directly, 2026-10-01). Document values are read out by the parser, not
typed; the wrong values are the controls' own. GREEN's job is to confirm the
same numbers against the shipped module (and D-1/D-2 at GATES).

| Control | Threshold / expectation | Wrong input | Measured in RED |
|---|---|---|---|
| Real document parses (baseline) | 0 problems; ≥1 row in each of §2, §3, §4 | - | §2 31/3/6 (+3 rule), §3 9/4/1 (+2), §4 11/8/0 (+2); 0 problems; matches the contract's counts |
| AC-1 `foo_seconds` / `5 s` | exactly 1 problem naming `foo_seconds` and `5 s`; `assertNoParseProblems` raises with `AC-1` | fixture row inside §2 | 1 problem; raised |
| AC-1 rule row given a value | exactly 1 problem naming `spawn_room`, `RULE_ROWS`, kind | `spawn_room` = `3`, then `true` | 1 problem each (`number`, `boolean`) |
| AC-1 fixture collection | 10 rows, kinds as listed, nothing from §1/§5/§9/INV_/`~~` | - | exact match |
| AC-1 cell classifier | 16 cells → expected kinds | `**4**`, `4 s`, `~4`, `True`, `= other`, `= \`a\`..\`b\``, prose, `none`, `""` → none | 16/16 |
| AC-3 zero rows | comparison over 0 rows returns **0 findings** against a drifted fake; floor raises naming `§2 (`, `§3 (`, `§4 (` | `{rows = {}}` | 0 findings; raised |
| AC-3 §3 heading broken | total row count unchanged; floor names `§3 (-> MechanicsTuning.channel): 0 rows parsed` and not §2/§4 | fixture | as expected |
| AC-2 `dial_settings` 5 | passes module→spec; fails spec→module naming `dial_settings`, `spec 4`, `module 5` | 5 | document value read = **4**; raised with both |
| AC-2 extra key | passes spec→module; fails module→spec naming `vocabulary_size`, `MechanicsTuning.channel`, `§3` | `channel.vocabulary_size = 16` | raised |
| AC-2 missing key | passes module→spec; fails spec→module naming `ping_display_seconds`, `spec 15`, `absent from the module` | `channel.ping_display_seconds = nil` | document value read = 15; raised |
| AC-2 reference disagrees | names `ping_range_studs`, `spec = \`lens_read_range_studs\``, `module 13`, `MechanicsTuning.instance.lens_read_range_studs is 12` | referent + 1 | referent read = **12**; raised |
| AC-2 referent moved alone (D-1's shape) | findings exactly `{lens_read_range_studs, ping_range_studs}` | `instance.lens_read_range_studs` = 13 | exactly those two |
| AC-2 rule row present | both directions name `spawn_room`; spec→module says "a rule row, not a constant" | `instance.spawn_room = 1` | raised, both |
| AC-2 wrong type | names `blackout_permanent`, `spec true (boolean)`, `module 1 (number)` | 1 | raised |
| AC-2 missing table | names `MechanicsTuning.channel is nil` | `channel = nil` | raised |
| AC-4 baseline | 0 findings on document values; 6 relations | - | **0 findings**; `RELATION_COUNT` = 6 |
| AC-4 `procedure_length` 9 | `per_operation_seconds` fails; `machine_spacing_min_studs` and `presets_plus_pings_max` do not; message shows `45 vs 40` and `procedure_length = 9` | 9 | findings = `actuator_count, steps_per_track, machines_per_class_max, per_operation_seconds`; lhs **45**, rhs **40** |
| AC-4 `preset_count` at ceiling | exactly `presets_plus_pings_max` fails | `preset_count` = 12 (read ceiling) | 12 + 1 = 13 > 12; exactly one finding |
| AC-4 missing operand | "cannot be computed", names `MechanicsTuning.instance.procedure_length is nil` | `procedure_length = nil` | raised |
| AC-5 frozen / unfrozen | frozen → 0 findings; unfrozen → one per attempted write = 4 + (40+1) + (14+1) + (19+1) | `table.freeze` ×4 vs none | **0** and **80** |
| AC-5 root-only freeze | >0 findings, all `MechanicsTuning.<table>.<key>`; none blaming the root | `table.freeze` on root only | **76** (= 80 − 4), none at root |
| AC-5 one table unfrozen | every finding starts `MechanicsTuning.channel.` | `frozenExcept("channel")` | **15** (14 keys + 1 new) |
| AC-5 swallowing `__newindex` | ≥1 finding "succeeded; the write must raise" on `instance.*` | `instance` replaced by an empty proxy with `__index` to the real table and an empty `__newindex` | **1** (the `__probe_key` write; the proxy has no raw keys, so `freezeFindings` iterates none - a reminder that the check enumerates the module's *raw* keys, which the real module's plain tables satisfy) |

**Deferred verifications.** D-1 and D-2 are owned by GATES and **RED declines
them in those words: they cannot be run here, because the module they mutate
does not exist.** What RED can say is that the same checks fire on fakes with
exactly those defects (rows "referent moved alone" and "missing key" above),
so when GATES runs `scripts/mutate.sh` on the shipped module the expected
output is: D-1 → AC-2 spec→module fails naming `lens_read_range_studs` (spec
12, module 13) and `ping_range_studs` (module 12 but
`MechanicsTuning.instance.lens_read_range_studs is 13`); D-2 → AC-2 fails
naming `turn_rate_limit_seconds` (spec 1, absent from the module).

**Discoveries that bear on the implementation.**

- The contract's counts re-measured exactly (awk independently of the guard,
  then the guard itself). No document inconsistency found; all six AC-4
  relations hold on today's values, so nothing goes to the Game Designer.
- The guard treats a `RULE_ROWS` name whose cell is a **reference** as a parse
  problem too, not only a number or boolean: AC-1 says "exactly one of four
  kinds", and a rule row that is also a reference is two. Today no row is
  affected. Noted in case the document grows one; the fix would be a `RULE_ROWS`
  edit, not a guard edit.
- Referents are resolved against the **module** (all three tables), not the
  document, which is what AC-2's wording asks and what makes D-1 fire twice.
  A reference to a §1/§5 constant (none today) would be reported as "the
  module has no `x` under instance, channel or actuation" - the right outcome,
  since `MechanicsTuning` should not shadow `Tuning`.
- `--!strict` note for GREEN: the contract's loose `{ [string]: number |
  boolean }` type is only the guard's view. Named-field record types per table
  are compatible with every assertion here (the tests index with `[]` through
  `any`).
- The contract counts were not hard-coded as assertions. The per-section floor
  is ≥1, and the module→spec direction supplies the rest: once the module has
  73 keys, a parser that dropped any row reports that key as unspecified.

**Dispatch model.** `.claude/agents/test-developer.md` declares `model: opus`;
this session reports itself as **Fable 5.1 (`claude-fable-5-1`)**, so the
dispatch's override won over the agent definition, consistent with the planned
`fable` row. The orchestrator records what resolved, by name, under
`## Model guidance` → Resolved.

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

**PLANNED → RED checks (lead-po, 2026-09-30).**

- **Gate.** `unit` is `required` and `covers` both `src/shared/**` and
  `docs/wiki/game/tuning.md`; no `required_gates` entry is needed.
- **Callers of changed signatures.** None: the contract changes no existing
  export (`Tuning.luau` changes two comments only). `MechanicsTuning` is new, so
  it has no callers. RED's handoff confirms this against the tree.
- **Epic done-when.** EPIC-04 done-when 1 is exactly AC-1..AC-3 plus AC-2's
  "a changed value on either side fails, naming it". Done-when 2..6 belong to
  GEN-001..GEN-004. No gap, so no PO decision.
- **Contract re-measured independently** (awk over `tuning.md`, not the
  guard): §2 31/3/6, §3 9/4/1, §4 11/8/0 number/boolean/reference rows, and the
  seven non-classifiable rows are exactly `RULE_ROWS`. All six AC-4 relations
  hold on today's values; AC-4's control (`procedure_length` 9) gives 40 ≠ 45.

### The orchestrator's RED acceptance (2026-09-30)

1. **Resolved model:** recorded under `## Model guidance`.
2. **Tests read and run by the orchestrator:** `lune run test` → `502 passed,
   5 failed`. All five failures are in `mechanics_tuning_spec_test.luau`, line 42,
   `could not resolve child component "MechanicsTuning"`: the right reason. The
   24 controls in `mechanics_tuning_controls_test.luau` require nothing under
   `src/` and pass, so their measured values are evidence, not claims.
3. **`tuning.md` untouched by the probes:** `git status` lists only the story,
   `.claude/tests/project-counters.test.sh` and the four new test files.
4. **`gates.sh --fast`:** format PASS (96), lint PASS (96), typecheck PASS (17),
   build PASS; `unit` FAIL with exactly the five demand failures (57 s);
   `harness` FAIL on the precondition "the working tree carries no stray .luau
   files" only (`project-counters: 39 passed, 1 failed`), because RED was
   uncommitted. Admissible. RED is committed, as ROUND-006 did, and `harness` is
   re-run on that commit below.
