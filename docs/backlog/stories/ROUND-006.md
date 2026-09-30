---
id: ROUND-006
title: Third-pass tuning lands: a 420 s round, a 60 s reserve, rate limits at the preset floor
slug: third-pass-tuning-lands-a-420-s-round-a
epic: EPIC-01
type: feature
status: done
phase: DONE
branch: story/ROUND-006-third-pass-tuning-lands-a-420-s-round-a
depends_on: [ROUND-002, NET-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

The operator's decisions of 2026-09-30 (product-brief §0d) change two things the
M0-M2 tree already carries. **#18** sets `round_seconds` = 420, so 60 + 420 = 480
meets A5's day-1 promise and amendment 12 is closed. **#19(a)** redesigns the
signal channel as a compliant preset system; the Game Designer's third pass of
`docs/wiki/game/` follows from it, re-derives `traversal_reserve_seconds` as 60,
and supersedes `signal_rate_limit_seconds` (1.5) with `preset_rate_limit_seconds`
and `ping_rate_limit_seconds`, both 10 (#23 for pings).

That third pass is written but not committed, and three test files read
`tuning.md` directly, so landing it alone turns `main` red: measured on
2026-09-30 against the working tree, `lune run test` gave **445 passed, 7
failed**, and **464 passed, 7 failed** once HARNESS-021/022 had merged
(re-measured at the start of RED; the same seven). The brief's "Consequences for the tree" names this story as the one the
documents land with. It moves `src/shared/Tuning.luau` to the new §5, corrects the
tests whose premise the operator's decisions changed, re-points NET-003's
provenance guard at the preset design, and records the change to ROUND-002's
frozen AC-2.

Epic: `EPIC-01`. Bounded by `docs/wiki/game/tuning.md` §3, §5 and §9 (third
pass), product-brief §0d #18, #19, #23, and `docs/wiki/architecture.md` (the
module is `src/shared/Tuning.luau`, read by `RoundConfig.fromTuning` and `Ring`).

**Which required gate would fail if this story's artifact broke:** `unit`
(`lune run test`, required). All three guards live in it. No optional gate is
involved, so `required_gates` stays empty.

## Acceptance criteria

- **AC-1** - Given the module, when `Tuning.round` is read, then `round_seconds` is
  **420** and `traversal_reserve_seconds` is **60**, and every other constant of
  `tuning.md` §1 and §5 keeps its current value: `round_seconds_min` 360,
  `round_seconds_max` 600, `per_operation_seconds` 45,
  `first_round_within_seconds` 480, `disconnect_grace_seconds` 30, and §1 unchanged.
  *Control:* the module as it stands today (480 / 120) **must** fail, and the
  failure **must** name `round_seconds` with both 420 and 480, and
  `traversal_reserve_seconds` with both 60 and 120.
- **AC-2** - Given the third-pass `tuning.md` and the module, when ROUND-002's
  guard runs, then all three sides of its triangle agree: the specification's §1
  and §5 against the module (both directions), and the specification against
  ROUND-002's criteria as amended (A-1: 420 / 60). The guard's own liveness
  checks - the row floor of 13, the expected names, no unread row - still pass.
  *Control:* with `tuning.md` §5's `round_seconds` row put back to 480, the
  drift check **must** fail naming `round_seconds`, 420 and 480, and the
  controls suite's baseline **must** fail with it.
- **AC-3** - Given the module, when the day-1 promise is checked, then
  `lobby_seconds + round_seconds <= first_round_within_seconds` (60 + 420 = 480 <=
  480), and `first_round_within_seconds` is still 480. The test that pinned
  amendment 12 *open* now pins it *closed*.
  *Control:* the module at `round_seconds` 480 **must** fail this, naming 540 and
  480. A module that "fixed" the promise by raising `first_round_within_seconds`
  to 540 **must** fail it too.
- **AC-4** - Given `docs/wiki/game/tuning.md`, when the rate-limit provenance guard
  runs, then exactly one table row has `` `preset_rate_limit_seconds` `` as its
  first cell and exactly one has `` `ping_rate_limit_seconds` ``; each value cell
  is a bare number; each number is **at least 10**, the preset guideline's "10
  seconds per send" (brief §0d #19, applied to pings by #23). No table row has
  the bare `` `signal_rate_limit_seconds` `` as its first cell; the struck-through
  §9 record is not a live row.
  *Control:* a document with `ping_rate_limit_seconds` at 3 (its second-pass
  value) **must** be reported, naming the constant, 3 and 10. A document with a
  live `signal_rate_limit_seconds` row **must** be reported as a superseded
  constant. A document with neither rate row **must** be reported as matching
  nothing, not passed as comparing nothing.
- **AC-5** - Given the story branch with the third-pass documents committed, when
  `lune run test` runs, then it reports **0 failed**, and the passed count is at
  least **471**, the total measured before this story (464 + 7). No test is
  deleted or skipped to get there.

## Contract

Every block here is pinned by the Lead PO at PLANNED. **RED may amend a block in
place, with a reason written beside it, and GREEN builds what the amended block
says.** This is not `## Amendments`: that section is for criteria, which are
frozen once the story leaves PLANNED.

### How the documents land, in this order

1. **PLANNED commit, on the story branch, before `phase.sh set ROUND-006 RED`.**
   It carries: this story file; the third-pass `docs/wiki/game/{loop,mechanics,
   roles,tuning,playtest}.md` exactly as the Game Designer left them in the
   working tree; ROUND-002's `## Amendments` entry A-1 and its AC-2 text (below);
   and NET-003's `## Notes` entry (below). No source and no test.
   The suite on that commit is 464 / 7 red, and that is correct: the branch is
   not `main`, and RED starts from the spec-driven tests already failing for the
   right reason.
2. **RED** corrects the tests whose premise changed and leaves the demand red.
3. **GREEN** moves `Tuning.luau`.
4. **GATES** runs the full gates, and the deferred mutations below.
5. The PR merges docs, tests and source together. `main` never sees the documents
   without the code.

Checked against the harness, not assumed:

- `check-boundaries.sh` 3a counts **source** and **test** files only.
  `docs/wiki/game/tuning.md` classifies as `docs` (`bash scripts/classify.sh`),
  and the PR changes both source and tests, so 3a passes.
- ~~**The gate record's tree hash does not cover `docs/`.**~~ **Amended by the
  Lead PO at the start of RED:** HARNESS-021 merged after this was written and
  put `docs/wiki/game/tuning.md` into the gate tree hash through a
  `covers | unit | docs/wiki/game/tuning.md` line in `project.conf`. An edit to
  `tuning.md` after a gate run now makes `check-boundaries.sh` refuse the record.
  The other four game docs are not in the hash, and no test reads them. **The
  rule stands anyway: no edit to `docs/wiki/game/**` after the PLANNED commit**,
  because they are the Game Designer's.
- **Tests read files through `tests/helpers/GatedFs.luau`, never `@lune/fs`**
  (HARNESS-022, `docs/wiki/stack.md`). `tests/shared/gated_fs_test.luau` fails any
  file under `tests/` holding a `"@lune/fs"` literal in code. `RateLimitSpec`
  already uses `GatedFs`; the rewritten provenance test keeps its fixtures in
  memory and reads the real document only through `RateLimitSpec.read()`.
- `check-boundaries.sh` 3d compares the `## Acceptance criteria` of **the story
  that claims the branch only**. That is ROUND-006, which is new in this PR, so
  3d notes "nothing to freeze the criteria against". **CI does not look at
  ROUND-002's or NET-003's files at all.** The entries below land by discipline
  and are checked at REVIEW. `TuningSpec.luau`'s own header already requires the
  ROUND-002 entry for any change to `ACCEPTANCE`.

### ROUND-002: `## Amendments` A-1 (written by the Lead PO in the PLANNED commit)

- **AC-2**: `round_seconds` 480 becomes **420**; `traversal_reserve_seconds` 120
  becomes **60**. Every other value in AC-2 is unchanged.
- **Approved by:** the operator (ryanczhang7), 2026-09-30. For `round_seconds`
  that is brief §0d #18. For `traversal_reserve_seconds` it is the Game
  Designer's third-pass re-derivation under #19(a), **confirmed by the operator
  in chat on 2026-09-30 ("approve 60")**.
- **Why:** the value changed because the design changed, not because the test was
  wrong. `tuning.md` is the specification by its first paragraph.
- Also record in the same entry that ROUND-002's `## Out of scope` bullet ("resolving
  amendment 12's day-1 conflict") is **overtaken** by #18: the conflict is
  resolved in the specification, and ROUND-006 AC-3 pins the result.

### NET-003: a `## Notes` entry, not `## Amendments`

NET-003's criteria do **not** change. AC-1 says "a remote with
`minIntervalSeconds = 1.5`", and that is still a true, tested statement about a
value-agnostic limiter. What is superseded is the **provenance** of 1.5: NET-003's
Contract and oracle partition said it was `tuning.md` §3's
`signal_rate_limit_seconds`. That was contract, not criteria. The Notes entry
says: superseded by brief §0d #19 on 2026-09-30; from ROUND-006 on, 1.5 is a
**fixture** interval with no design provenance; the provenance guard reads the
preset design's rate floor instead; M3's channel story declares the real remotes
at 10.

### `src/shared/Tuning.luau` (GREEN)

Values only. **No change to `SessionTuning`, `RoundTuning`, `Tuning` or the
freezing.**

    round_seconds             = 420  -- taste (operator, brief §0d #18)
    traversal_reserve_seconds = 60   -- placeholder: re-derived, third pass (the opening read and walk)
    first_round_within_seconds = 480 -- derived: A5; met exactly by 60 + 420

The header's "AMENDMENT 12 IS CARRIED, NOT RESOLVED" paragraph is rewritten to
say it is **resolved** by #18, and that ROUND-006 AC-3 pins the promise met.
`per_operation_seconds` stays 45, and its comment says (420 - 60) / 8.

Semantics, one sentence per number:
- `round_seconds` 420 - the round's length in seconds, lobby excluded; the phase
  machine reads it through `RoundConfig.fromTuning` as `roundSeconds`.
- `traversal_reserve_seconds` 60 - the time before a round's first step can
  commit (reading the first turn cue and making the first walk). Nothing in M0-M2
  reads it.
- `first_round_within_seconds` 480 - A5: a new player's first round must *end*
  within 8 minutes of joining, so `lobby_seconds + round_seconds` must not
  exceed it. `<=`, not `==`: meeting it with slack is still meeting it.

### `tests/helpers/TuningSpec.luau` (RED)

`TuningSpec.ACCEPTANCE.round.round_seconds` 480 becomes 420 and
`traversal_reserve_seconds` 120 becomes 60, under ROUND-002 A-1. The header gets
one line naming A-1 and ROUND-006. Nothing else in the file changes. That single
edit is what un-reds the drift check and the four controls, because
`TuningFakes.correct()` is built from `ACCEPTANCE`.

### `tests/shared/tuning_test.luau` (RED)

- `"AC-2: every round constant ..."` is **unchanged**. After the `ACCEPTANCE`
  edit it is red against the module's 480 / 120, which is the demand.
- `"AC-2: the day-1 conflict amendment 12 records is carried, not resolved"` is
  **rewritten** to AC-3 of this story, under a new name that says the promise is
  met (for example `"ROUND-006 AC-3: lobby_seconds + round_seconds meets
  first_round_within_seconds - amendment 12 is closed"`). It keeps the
  `first_round_within_seconds == 480` assertion, which is what catches a module
  "fixing" the promise at 540. The comparison flips to `<=`. The failure message
  names all three numbers and their sum.

### `tests/shared/tuning_controls_test.luau` (RED)

One test edited: `"AC-4 control: a constant that is not a number fails and is
named"`. The fake becomes the **string `"420"`**, so the only defect is the type.
That is a sharper control than `"480"`, which was also a wrong value. The needle
`"spec 480"` becomes `"spec 420"`. Everything else in the file is untouched.

### `tests/helpers/RateLimitSpec.luau` and `tests/net/rate_limit_provenance_test.luau` (RED)

The reader stays textual, local and section-agnostic, and `rowsNaming` is kept
exactly as it is (first-cell exact match on a backticked name). Pinned shape:

    RateLimitSpec.SPEC_PATH    = "docs/wiki/game/tuning.md"                          -- unchanged
    RateLimitSpec.NAMES        = { "preset_rate_limit_seconds", "ping_rate_limit_seconds" }
    RateLimitSpec.SUPERSEDED   = "signal_rate_limit_seconds"
    RateLimitSpec.FLOOR_SECONDS = 10   -- brief §0d #19 quoting the preset guideline; #23 for pings
    RateLimitSpec.rowsNaming(text: string, name: string) -> { Row }                  -- unchanged
    RateLimitSpec.violations(rows: { Row }, name: string, floor: number) -> { string }
    RateLimitSpec.supersededViolations(text: string) -> { string }
    RateLimitSpec.read() -> string                                                   -- unchanged
    RateLimitSpec.describe(violations: { string }) -> string                         -- unchanged

- `violations` keeps its three vacuity steps in order: exactly one row, a numeric
  value cell asserted before any comparison, and then **`value >= floor`**
  (previously `value == expected`). The below-floor message names the constant,
  the document's value and the floor, and says the floor is the preset
  guideline's.
- `supersededViolations` reports any row whose first cell is the bare backticked
  `SUPERSEDED` name. The §9 row's first cell is `` ~~`signal_rate_limit_seconds`~~ ``,
  which is not a match, and that is the intended reading.
- `RateLimitSpec.NAME` is removed. Its only caller is
  `tests/net/rate_limit_provenance_test.luau` (grep below).
- **Why `>=` 10 and not `== 10`.** Equality would be a second copy of the
  document's number with no oracle behind it. The floor *is* an oracle, a
  published compliance requirement the operator adopted, and it fails for the
  change that matters: a rate lowered below compliance.

The provenance test file is rewritten around AC-4. It has one guard test per
name in `NAMES` plus one for `SUPERSEDED`, and in-memory fixture controls for
each vacuity step: no row, two rows, a value of `10 s`, a below-floor value of
3, a longer name containing the wanted one, and a live superseded row. It no
longer requires `RateContract`, because nothing in it compares against the rate
suite any more.

### The rate suite keeps 1.5, and why

`RateContract.MIN_INTERVAL_SECONDS` stays **1.5**, and so does every timing in
`rate_test`, `rate_controls_test` and TEL-003's `RejectionContract.luau` (8 call
sites). The limiter is value-agnostic: `RateLimiter.new(minIntervalSeconds)`
takes its interval from the remote's declaration. Moving the fixture to 10 would
rewrite 28 counted controls and a telemetry suite for no behaviour, and would
mean amending NET-003's AC-1 and AC-3. A fractional interval also keeps the
float-boundary reasoning in `RateContract`'s header valid. **RED rewrites only
the header comments** of `RateContract.luau` (lines 19-24 and 64-71) and
`RateStubs.luau` where they claim provenance: 1.5 is a fixture, chosen for its
fractional boundary.

### Stale comments

| File | In scope? | Why |
|---|---|---|
| `src/shared/Tuning.luau` header, amendment 12 | **yes, GREEN** | the file is already being changed, and the comment would contradict AC-3 |
| `src/net/RateLimiter.luau:36-38` | **yes, GREEN** | it cites the exact row this story re-points. One comment: the interval comes from the remote's declaration, and for M3's remotes that is `tuning.md` §3's `preset_rate_limit_seconds` / `ping_rate_limit_seconds` |
| `src/server/seats/Projection.luau:44-47` (`pairings`, `fragments`, `mechanics.md` §4.5) | **no** | the file is otherwise untouched, and the correct replacement is a decision about what M3's projection carries. Under the redesign it is turn cues and lens contents, which is M3 planning (brief §0d: `/plan-product` must be re-run for M3), not a transcription. Deferred there by name |
| `tests/helpers/RateContract.luau`, `RateStubs.luau` headers | **yes, RED** | see above |
| `docs/wiki/game/tuning.md` header table (lines 34-40, "goes red") | **no** | the Game Designer's file, frozen for this story by the landing rule above. Once this story is DONE the table describes a past transition; the Game Designer refreshes it in their next pass |
| `docs/wiki/architecture.md` §0's M3 list | **no** | M3 re-planning |

### Callers of changed signatures and consumers of changed values

Grepped on 2026-09-30 (`rg -n "round_seconds|traversal_reserve|per_operation_seconds|first_round_within|shared/Tuning|ACCEPTANCE|RateLimitSpec\.|MIN_INTERVAL_SECONDS" src tests lune`):

- **No production signature changes.** `Tuning`'s types are untouched.
- **Consumers of the changed values:**
  - `src/server/round/RoundConfig.luau:50` maps `round_seconds` to `roundSeconds`.
    `tests/server/round_config_test.luau:118` compares it to `Tuning`, not to a
    literal, so it is value-agnostic and stays green.
  - `src/server/seats/Ring.luau:101` reads `min_players_to_continue` only.
  - `tests/helpers/RingContract.luau:764` reads `disconnect_grace_seconds` only.
  - `tests/server/phase_machine_test.luau` injects its own durations. There is no
    literal 480 or 420 there.
  - **Nothing in `src/` or `tests/` reads `traversal_reserve_seconds` or
    `per_operation_seconds`** except the ROUND-002 guard.
- **`TuningSpec.ACCEPTANCE`** (value change): `tests/shared/tuning_test.luau:35,
  62`, `tests/helpers/TuningFakes.luau:41-42`, and internal to `TuningSpec`.
- **`RateLimitSpec.violations` (semantics and parameter) and `RateLimitSpec.NAME`
  (removed):** only `tests/net/rate_limit_provenance_test.luau`.
- **`RateContract.MIN_INTERVAL_SECONDS`**: unchanged in value. The provenance test
  stops requiring it; the 7 uses in `RateContract.luau` and 8 in
  `RejectionContract.luau` are untouched.

**RED's handoff must state that this list was re-checked against the tree.**

### No new `.luau` file

`.claude/tests/project-counters.test.sh` (the required `harness` gate) pins
`.luau` file counts under `src`, `tests` and `lune`. This story edits files and
adds none. If RED finds it must add one, it amends this block and updates the
counters in the same phase, as TEL-003 did.

### The seven failing assertions, and one more that will fail at GREEN

Measured on 2026-09-30 by `timeout 500 lune run test` (445 passed, 7 failed; 464 / 7 after HARNESS-021/022) with
the third pass in the working tree:

| # | Test | Why it fails now | Class | RED does | Earned by |
|---|---|---|---|---|---|
| 1 | `tuning_spec_test` "every constant §1 and §5 names is in the module with a matching value" | spec 420 / 60, module 480 / 120 | **demand** | nothing | its red; GREEN clears it |
| 2 | `tuning_spec_test` "tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze" | `ACCEPTANCE` pins 480 / 120 | **wrong premise** (frozen literals) | edits `ACCEPTANCE` under A-1; the file itself is not edited | probe P1 |
| 3 | `tuning_controls_test` "baseline: a correct module passes..." | `TuningFakes.correct()` is built from `ACCEPTANCE` | **wrong premise** | same `ACCEPTANCE` edit | P1 |
| 4 | `tuning_controls_test` "a constant that is not a number..." | needle `"spec 480"`, and the `ACCEPTANCE` drift | **wrong premise** (literal needle) | needle becomes `"spec 420"`, fake becomes `"420"`, plus the `ACCEPTANCE` edit | P1 |
| 5 | `tuning_controls_test` "a constant the specification does not name..." | the fake's 480 / 120 fail the spec-to-module half | **wrong premise** | `ACCEPTANCE` edit only | P1 |
| 6 | `tuning_controls_test` "vote_seconds = 30 fails and is named" | as 5 | **wrong premise** | `ACCEPTANCE` edit only | P1 |
| 7 | `rate_limit_provenance_test` "AC-1 provenance: ... signal_rate_limit_seconds ..." | no such row: superseded (§9) | **wrong premise** (superseded row) | rewritten around AC-4 | probes P2, P3 |
| 8 | `tuning_test` "AC-2: every round constant ... holds its specified value" | green now; red once `ACCEPTANCE` moves | **demand** | nothing | its red in RED; GREEN clears it |
| 9 | `tuning_test` "the day-1 conflict amendment 12 records is carried, not resolved" | green now; would go red at GREEN (60 + 420 is not > 480) | **wrong premise** (inverted by #18) | rewritten to AC-3 | its own red in RED: the module is still 480, and 540 > 480 |

After RED the suite is red on exactly #1, #8 and the rewritten #9, all for the
module's 480 / 120. Everything corrected in place (#2-#7) is **green on arrival**,
because the documents already say 420 / 60 / 10. The rules call that a test never
observed to fail, so RED earns each one with a `scripts/mutate.sh` probe against
**the specification file**, the thing those tests pin. Paste the output in
`## Handoff`.

- **P1:** in `docs/wiki/game/tuning.md`, the §5 `round_seconds` row 420 to 480.
  Predicted: #2 red naming `round_seconds`, 420 and 480; #3, #4, #5, #6 red; #1
  still red, but its message no longer lists `round_seconds`, only
  `traversal_reserve_seconds`. Restored and verified by `mutate.sh`.
- **P2:** the `ping_rate_limit_seconds` row 10 to 3. Predicted: the ping guard
  red, naming 3 and 10; the preset guard and the superseded guard green.
- **P3:** the `preset_rate_limit_seconds` row's name renamed to
  `preset_rate_limit_secs`. Predicted: the preset guard red with the
  "matched nothing" message.

These probes need no permission beyond `mutate.sh`, which is allowed in every
phase, and they touch no source.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2 | **Settled** | 420 is the operator's (#18); 60 is `tuning.md` §5 (third pass); 10 is the guideline (#19, #23). **Read them out. Do not derive, tune or "calibrate" them**, and do not re-derive `per_operation_seconds`. |
| AC-3 | **Settled, with a mechanical control** | The inequality is A5's, `<=`. Pin the `== 480` half exactly: it is what catches the 540 "fix". |
| AC-4 | **Oracle-free reader, settled floor** | You are re-shaping an invented reader, so the vacuity steps and fixture controls are the point. The floor of 10 is settled, not yours to choose. |
| AC-5 | **Mechanical** | The count is a measurement: 471 before the story (464 + 7). |

### Test-only dependencies

None. `@lune/fs` is already used.

## Deferred verifications

**D-1. The module's value is load-bearing for AC-1, AC-2 and AC-3.** With
`src/shared/Tuning.luau`'s `round_seconds` put back to 480 by
`scripts/mutate.sh`, the spec-to-module guard (#1), `tuning_test`'s AC-2 value
check (#8) and the rewritten day-1 test (#9) **must** all go red, naming
`round_seconds`, 420 and 480, and 540 for #9. Then the file is restored and the
suite is green again. RED cannot run this: the module is still 480 in RED, so
there is nothing to mutate *back*. Owner: GATES.

*Result (GATES, 2026-09-30, run by the orchestrator):* **as predicted.**
`bash scripts/mutate.sh src/shared/Tuning.luau 's/round_seconds = 420,/round_seconds = 480,/' -- lune run test`

    FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
      round_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 420, module 480
    FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
      round_seconds: expected 420, module has 480
    FAIL  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds - amendment 12 is closed
      tuning_test:161: ROUND-006 AC-3: lobby_seconds 60 + round_seconds 480 = 540, which exceeds first_round_within_seconds 480. ...
    473 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_shared_Tuning.luau.20260930T224256Z.1135948.bak) ===

**D-2. A wrong value, not a revert.** With `traversal_reserve_seconds` set to 61
(a value no document has ever held), #1 and #8 **must** go red naming
`traversal_reserve_seconds`, 60 and 61, and the day-1 test **must stay green**
(it does not read the reserve). This proves the guard catches corruption as well
as reversion. Owner: GATES.

*Result (GATES, 2026-09-30, run by the orchestrator):* **as predicted.**
`bash scripts/mutate.sh src/shared/Tuning.luau 's/traversal_reserve_seconds = 60,/traversal_reserve_seconds = 61,/' -- lune run test`

    FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
      traversal_reserve_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 60, module 61
    FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
      traversal_reserve_seconds: expected 60, module has 61
    pass  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets ...
    474 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_shared_Tuning.luau.20260930T224338Z.1138473.bak) ===

**D-3. The `==` half of AC-3.** With `first_round_within_seconds` set to 540 in
the module, the day-1 test **must** go red on its `== 480` assertion. So must the
spec-to-module guard, naming `first_round_within_seconds`. Owner: GATES.

*Result (GATES, 2026-09-30, run by the orchestrator):* **as predicted**, plus
`tuning_test`'s AC-2 value check, which also reads the constant.
`bash scripts/mutate.sh src/shared/Tuning.luau 's/first_round_within_seconds = 480,/first_round_within_seconds = 540,/' -- lune run test`

    FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
      first_round_within_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 480, module 540
    FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
      first_round_within_seconds: expected 480, module has 540
    FAIL  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds - amendment 12 is closed
      tuning_test:150: ROUND-006 AC-3: first_round_within_seconds is 540, A5 says 480. ...
    473 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_shared_Tuning.luau.20260930T224413Z.1140494.bak) ===

AC-3 failed at line 150, the `== 480` assertion. The sum check alone (540 <= 540)
would have passed.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write ROUND-006` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `.claude/hooks/lib.sh` (tooling), `scripts/classify.sh` (tooling), `scripts/gates.sh` (tooling) (+16 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

The RED brief carries the oracle partition from `## Contract`. AC-1, AC-2 and the
floor in AC-4 are **settled** (read the numbers out). AC-4's reader is
**oracle-free** (fixture controls for every vacuity step). AC-3 and AC-5 are
**mechanical**. The partitioned contract is what the `fable` row for RED depends
on.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; no override was reported to this dispatch).
- RED - `test-developer` - `claude-opus-5-5` (Opus 5.5, from the session's own
  model identification). Planned `fable`; it ran on Opus 5.5, so this RED is
  not evidence about the weaker model. Whether a session setting or an override
  won is not visible from inside the dispatch.
  *Orchestrator:* the cause is known from outside it. The dispatch passed no
  `model` override, so the agent definition's `model: opus`
  (`.claude/agents/test-developer.md:5`) won over the plan's `fable` row. That
  was an omission in the dispatch, not a decision.

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

- **Any M3 remote, constant or mechanic.** No preset, ping, wheel, turn cue or
  channel code; no remote declared at 10 s. M3's channel story declares the real
  remotes, and it is where a provenance guard compares a *declaration* against
  `preset_rate_limit_seconds` / `ping_rate_limit_seconds`.
- **Adding any §2, §3, §4 or §6 constant to `src/shared/Tuning.luau`.** The
  module's scope is §1 and §5, and ROUND-002's module-to-spec guard fails any key
  those sections do not name. That includes both rate constants.
- **Changing `RateContract.MIN_INTERVAL_SECONDS` or any NET-003 or TEL-003 test
  other than the provenance file and its helper.** See the Contract.
- **Changing any acceptance criterion of NET-003**, or editing ROUND-002 beyond
  the A-1 entry and the AC-2 text it authorises.
- **Editing `docs/wiki/game/**`**, which is the Game Designer's. That includes
  the stale header table in `tuning.md`. The documents land as written, in the
  PLANNED commit.
- **`src/server/seats/Projection.luau`'s M3 comment**, and `architecture.md` §0's
  M3 list. Both need M3 re-planning, not transcription.
- **Wiring `per_operation_seconds` or `traversal_reserve_seconds` into anything.**
  No consumer exists and this story creates none. `per_operation_seconds` stays a
  carried value, not a computed one, until `procedure_length` exists in source.
- **The phase machine and `RoundConfig`.** They read `round_seconds` through
  `Tuning` and need no change. If either needs one, that is a finding to report,
  not a change to make.
- **The harness gap this story exposes** (tests read `docs/`, and the gate hash
  excludes `docs/`). It is recorded in `## Notes`, and fixing it is a HARNESS story.

## Test plan

All unit level (`lune run test`, gate `unit`). No new `.luau` file.

| AC | Test (file :: name) | Kind |
|---|---|---|
| AC-1 | `tuning_test` :: "AC-2: every round constant tuning.md §5 names holds its specified value" (unchanged; `ACCEPTANCE` now 420 / 60) | demand, red |
| AC-1 | `tuning_test` :: "AC-1: every session constant ..." and both "exposes no constant" tests (unchanged) | regression, green |
| AC-1, AC-2 | `tuning_spec_test` :: "AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value" (unchanged) | demand, red |
| AC-2 | `tuning_spec_test` :: "AC-4: tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze" (unchanged file; `ACCEPTANCE` moved under A-1) | green on arrival, earned by P1 |
| AC-2 | `tuning_spec_test` liveness: row floor 13, expected names, no unread row (unchanged) | green, still passing |
| AC-2 | `tuning_controls_test` :: baseline, "a constant that is not a number" (fake `"420"`, needle `spec 420`), "a constant the specification does not name", "vote_seconds = 30" | green on arrival, earned by P1 |
| AC-3 | `tuning_test` :: "ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds - amendment 12 is closed" (rewritten from the amendment-12-open test) | demand, red; `== 480` half probed (P5) |
| AC-4 | `rate_limit_provenance_test` :: "AC-4: the guard checks both live rate constants and the superseded one, by name" | pins `NAMES` / `SUPERSEDED` |
| AC-4 | `rate_limit_provenance_test` :: "AC-4: tuning.md fixes preset_rate_limit_seconds ... at or above the preset guideline's 10 s" | guard, earned by P3 |
| AC-4 | `rate_limit_provenance_test` :: "AC-4: tuning.md fixes ping_rate_limit_seconds ... at or above the preset guideline's 10 s" | guard, earned by P2 |
| AC-4 | `rate_limit_provenance_test` :: "AC-4: tuning.md has no live table row for the superseded signal_rate_limit_seconds ..." | guard, earned by P4 |
| AC-4 | `rate_limit_provenance_test` :: 7 fixture controls: neither row (both names), two rows, `10 s`, ping at 3, floor inclusive (10 / 11 pass, 9.5 reported), longer name, live superseded row vs struck-through | controls, executed |
| AC-5 | the whole suite: 473 passed + 3 failed = 476 today, >= 471 | mechanical |

## Handoff: RED -> GREEN

**Command:** `lune run test` (about 50 s). Gate: `unit`.

**Result at the end of RED:** `473 passed, 3 failed` (was 464 / 7; +5 is the
provenance file going from 6 tests to 11). Verbatim:

```
  FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
        AC-4: tuning.md and src/shared/Tuning.luau disagree:
  round_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 420, module 480
  traversal_reserve_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 60, module 120
  FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
        C:\Users\ryanc\Projects\first-roblox\tests\shared\tuning_test:54: AC-2: Tuning.round disagrees with tuning.md §5:
  round_seconds: expected 420, module has 480
  traversal_reserve_seconds: expected 60, module has 120
  FAIL  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds - amendment 12 is closed
        C:\Users\ryanc\Projects\first-roblox\tests\shared\tuning_test:161: ROUND-006 AC-3: lobby_seconds 60 + round_seconds 480 = 540, which exceeds first_round_within_seconds 480. A5's day-1 promise is broken; amendment 12 was closed by §0d #18 (round_seconds 420).
473 passed, 3 failed
```

Why these are the right failures: exactly the Contract's #1, #8 and rewritten
#9, and every one names the module's 480 / 120 against 420 / 60 (AC-1's
control, satisfied as stated: `round_seconds` with 420 and 480,
`traversal_reserve_seconds` with 60 and 120; AC-3's control: 540 and 480).
No import error: `Tuning.luau` loads and every assertion ran.

**What GREEN does:** the Contract's `src/shared/Tuning.luau` block (values
420 / 60, header rewrite, `per_operation_seconds` comment `(420 - 60) / 8`) and
the `RateLimiter.luau:36-38` comment. Nothing in `tests/` needs anything else.
After that the suite should be 476 / 0.

**Files touched (all tests, RED):**

| File | Change | AC |
|---|---|---|
| `tests/helpers/TuningSpec.luau` | `ACCEPTANCE.round.round_seconds` 420, `traversal_reserve_seconds` 60; header names ROUND-002 A-1 / ROUND-006 | AC-1, AC-2 |
| `tests/shared/tuning_test.luau` | amendment-12-open test rewritten to ROUND-006 AC-3 (`== 480`, then `sum <= within`, message names 60, 480/420, the sum and 480) | AC-3 |
| `tests/shared/tuning_controls_test.luau` | wrong-type control: fake `"420"`, needle `"spec 420"` | AC-2 |
| `tests/helpers/RateLimitSpec.luau` | the pinned shape below | AC-4 |
| `tests/net/rate_limit_provenance_test.luau` | rewritten around AC-4; no longer requires `RateContract` | AC-4 |
| `tests/helpers/RateContract.luau` | header comments only (the ORACLE PARTITION paragraph and the `MIN_INTERVAL_SECONDS` block): 1.5 is a fixture interval; value unchanged | - |

`tests/helpers/RateStubs.luau` was **not** touched: re-read, it makes no
provenance claim for 1.5 (its only mention is `DEFAULT_INTERVAL`, "the one every
declaring remote in the suite uses"), so there was nothing to correct.

**Export shape pinned (fact, tests import it):** all test helpers, no production
export changes. `tests/helpers/RateLimitSpec.luau`:
`SPEC_PATH`, `NAMES = { "preset_rate_limit_seconds", "ping_rate_limit_seconds" }`
(order pinned), `SUPERSEDED = "signal_rate_limit_seconds"`, `FLOOR_SECONDS = 10`
(pinned by the guard), `rowsNaming(text, name) -> { Row }` (unchanged),
`violations(rows, name, floor) -> { string }`, `supersededViolations(text) -> { string }`,
`read()`, `describe()`; `NAME` removed. Messages pinned by needles:
`no table row has \`<name>\` in its first cell`, `the extraction matched nothing`,
`N table rows name \`<name>\` (lines a, b)`, `the value cell for \`<name>\` is "<cell>", which is not a number`,
`\`<name>\` is <v> in the document, below the floor of <floor>`, `preset guideline`,
`<path>:<line> §<n>`, `a live table row has \`signal_rate_limit_seconds\` in its first cell, but it is a superseded constant`.
Production: `Tuning.round.{round_seconds, traversal_reserve_seconds, first_round_within_seconds}`
and `Tuning.session.lobby_seconds` as numbers; the types are not constrained further.
Not constrained: comment wording in `Tuning.luau`, key order, freezing mechanism.

**Green on arrival, and what earns each.** All probes via
`bash scripts/mutate.sh docs/wiki/game/tuning.md '<expr>' -- lune run test`,
restored and `cmp`-verified by the script. The baseline on each run includes the
3 demand failures above; only the deltas are listed.

- **P1** (`158s/^| \`round_seconds\` | 420 |/| \`round_seconds\` | 480 |/`) - **as predicted.** `468 passed, 8 failed`:
  ```
  FAIL  tests/shared/tuning_controls_test.luau :: AC-4 control: a constant that is not a number fails and is named
        ...tuning_controls_test:48: AC-4's wrong-type control: the failure does not mention "spec 420".
  message: ... round_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 480, module string
  FAIL  tests/shared/tuning_controls_test.luau :: AC-4 control: a constant the specification does not name fails and is named
  FAIL  tests/shared/tuning_controls_test.luau :: AC-5 control: vote_seconds = 30 fails and is named
  FAIL  tests/shared/tuning_controls_test.luau :: baseline: a correct module passes every AC-4 and AC-5 check against the real tuning.md
        ... but it failed with: AC-4 spec -> module: round_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 480, module 420
  FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
        AC-4: tuning.md and src/shared/Tuning.luau disagree:
  traversal_reserve_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 60, module 120
  FAIL  tests/shared/tuning_spec_test.luau :: AC-4: tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze
  round_seconds: ROUND-002 freezes it at 420, docs/wiki/game/tuning.md:158 now says 480
  === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T215950Z.1033498.bak) ===
  ```
  #1 no longer lists `round_seconds`, only `traversal_reserve_seconds`, exactly as predicted.
- **P2** (`123s/^| \`ping_rate_limit_seconds\` | 10 |/| \`ping_rate_limit_seconds\` | 3 |/`) - **as predicted.** `472 passed, 4 failed`:
  ```
  FAIL  tests/net/rate_limit_provenance_test.luau :: AC-4: tuning.md fixes ping_rate_limit_seconds in exactly one table row, as a bare number, at or above the preset guideline's 10 s
        ...rate_limit_provenance_test:82: AC-4: docs/wiki/game/tuning.md does not fix `ping_rate_limit_seconds` at or above the preset guideline's floor of 10:
  docs/wiki/game/tuning.md:123 §3: `ping_rate_limit_seconds` is 3 in the document, below the floor of 10 - the preset guideline's "10 seconds per send" (brief §0d #19; #23 for pings) is a compliance requirement, not tuning
  pass  ... AC-4: tuning.md fixes preset_rate_limit_seconds ...
  pass  ... AC-4: tuning.md has no live table row for the superseded signal_rate_limit_seconds ...
  === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T220043Z.1035203.bak) ===
  ```
- **P3** (`119s/^| \`preset_rate_limit_seconds\` |/| \`preset_rate_limit_secs\` |/`) - **as predicted, plus one.** `471 passed, 5 failed`:
  ```
  FAIL  tests/net/rate_limit_provenance_test.luau :: AC-4: tuning.md fixes preset_rate_limit_seconds in exactly one table row, as a bare number, at or above the preset guideline's 10 s
  docs/wiki/game/tuning.md: no table row has `preset_rate_limit_seconds` in its first cell - the extraction matched nothing, and a value compared against nothing would pass
  FAIL  tests/net/rate_limit_provenance_test.luau :: AC-4: tuning.md has no live table row for the superseded signal_rate_limit_seconds - the struck-through §9 record is not one
        ...rate_limit_provenance_test:122: docs/wiki/game/tuning.md read without a preset_rate_limit_seconds row; the superseded check would be vacuous
  === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T220124Z.1036705.bak) ===
  ```
  The extra red is deliberate: the superseded guard carries a non-vacuity step
  (the document it read must hold a live preset row), which the Contract did not
  name. The ping guard stayed green.
- **P4** (not in the Contract; earns the superseded guard) - un-strike §9's row,
  `250s/^| ~~\`signal_rate_limit_seconds\`~~ |/| \`signal_rate_limit_seconds\` |/`. `472 passed, 4 failed`:
  ```
  FAIL  tests/net/rate_limit_provenance_test.luau :: AC-4: tuning.md has no live table row for the superseded signal_rate_limit_seconds - the struck-through §9 record is not one
  docs/wiki/game/tuning.md:250 §9: a live table row has `signal_rate_limit_seconds` in its first cell, but it is a superseded constant (brief §0d #19, tuning.md §9) - replaced by `preset_rate_limit_seconds` and `ping_rate_limit_seconds`
  === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T220214Z.1038310.bak) ===
  ```
- **P5** (not in the Contract; the `== 480` half of AC-3, observable in RED
  because the module is the one being mutated) -
  `bash scripts/mutate.sh src/shared/Tuning.luau 's/first_round_within_seconds = 480/first_round_within_seconds = 540/' -- lune run test`.
  `473 passed, 3 failed`; the AC-3 test now fails on its **first** assertion, where
  the sum half alone (540 <= 540) would have passed:
  ```
  FAIL  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds - amendment 12 is closed
        ...tuning_test:150: ROUND-006 AC-3: first_round_within_seconds is 540, A5 says 480. The day-1 promise is met by shortening the round, not by moving the promise.
  FAIL  tests/shared/tuning_test.luau :: AC-2: ... first_round_within_seconds: expected 480, module has 540
  === mutate: command exited 1; restored (verified byte-for-byte against .../src_shared_Tuning.luau.20260930T220302Z.1039905.bak) ===
  ```
  This is not D-3 (which runs against the GREEN module at 420); it shows the
  assertion exists and fires.

**Negative controls - expected and measured.** Unlike an ordinary RED, nothing
here failed at import: `RateLimitSpec` is a test helper and exists, so every
control below **executed** in this RED run and passed; the measured column is
from `lune run test`, not a side harness. The AC-2 controls (`tuning_controls_test`)
are driven by `TuningFakes`, also executed.

| Control | Threshold / rule | Input | Expected | Measured |
|---|---|---|---|---|
| neither rate row | exactly one row | fixture without either | 1 violation per name, "matched nothing" | 1 each, pass |
| two ping rows | exactly one row | 2 x ping at 10 | 1 violation, "(lines 6, 7)" | pass |
| unit in value | numeric cell | `10 s` | "not a number", §3 | pass |
| ping below floor | `value >= 10` | 3 | names ping, 3, 10, "preset guideline"; preset at 10 not reported | pass |
| floor boundary | `value >= 10` | 10 / 11 / 9.5 | 0 / 0 / 1 violation | pass |
| longer name | first cell exact | `ping_rate_limit_seconds_v2` = 3 + real row | 1 row at line 7 §3, value 10, 0 violations | pass |
| superseded | bare backticked first cell | struck-through only / plus live row | 0 / 1 violation at `:9 §3` | pass |
| AC-3 at module 480 | `60 + rs <= 480` | module as is | fail naming 540, 480 | fails, names 60, 480, 540, 480 |
| AC-3 at 540 promise | `fr == 480` | P5 | fail on `== 480` | fails at `:150` |

**Deferred verifications D-1, D-2, D-3: declined.** They are owned by GATES and
need the GREEN module (420 / 60) to mutate back or corrupt; in RED there is
nothing built to break. I did not run them and make no claim about them. (P5
above is a related but different observation, against today's module.)

**Caller list re-checked** against the tree with
`rg -n "round_seconds|traversal_reserve|per_operation_seconds|first_round_within|shared/Tuning|ACCEPTANCE|RateLimitSpec\.|MIN_INTERVAL_SECONDS" src tests lune`:
it matches the Contract (`RoundConfig.luau:50`, `round_config_test` value-agnostic,
`RingContract.luau:762` for `disconnect_grace_seconds`, `TuningFakes.luau:41-42`,
7 `MIN_INTERVAL_SECONDS` uses in `RateContract` and 8 in `RejectionContract`,
untouched). `RateLimitSpec.NAME` has no remaining caller.

**`gates.sh --fast` at the end of RED:** format PASS (after `stylua` on the three
rewritten files), lint PASS, typecheck PASS, build PASS, **unit FAIL** (the 3
demand failures above, 42 s), **harness FAIL** on one assertion only:
`project-counters` "the working tree carries no stray .luau files" - it lists
`git status --porcelain` under `tests/`, i.e. RED's uncommitted edits. It clears
once RED is committed; it is not a test defect.

**Anything that changes the approach:** none for GREEN. Two things for the
orchestrator: RateStubs needed no edit (above); and `tuning.md`'s header table
row 39 and §8's "two red tests on landing" row describe this transition and go
stale at DONE (Game Designer's, out of scope here).

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-30T22:48:59Z
    commit: 2b1f066
    tree:   ccc7253f3b570d7d00ecff66cc1315c76ce8ee2b
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 92)
    PASS         lint (1s, observed 92, floor 1)
    PASS         typecheck (2s, observed 17)
    PASS         unit (44s, observed 476, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 57906)
    PASS         harness (19s, observed 40)
    UNCONFIGURED mutation

## Notes

- **Resolved 2026-09-30: the operator approved 60 in chat ("approve 60").** ROUND-002
  AC-2's `traversal_reserve_seconds` 120 to 60 is the Game Designer's
  re-derivation. No operator decision in §0d names it; #18 covers only
  `round_seconds`. An amendment to frozen criteria needs an approver by name.
  The operator confirmed 60, so A-1 may be written with the operator as approver for both values.
- **Run the unit gate with a budget.** `lune run test` took several minutes on
  this machine. A full `gates.sh` run exceeds the 600 s foreground cap, so
  background it. `gates.sh --list` is slow on Windows; the gate list was read
  from `project.conf` instead. The required gates are format (optional), lint,
  typecheck, unit, build and harness.
- ~~**Harness gap (not this story's to fix):** the gate tree hash excludes the
  `tuning.md` three test files parse.~~ **Closed by HARNESS-021 and HARNESS-022**,
  which merged after this story was planned: `tuning.md` is in the hash through a
  `covers` line, and every test read goes through `GatedFs`, which refuses a path
  outside the hash.
- **PO decisions at PLANNED → RED (2026-09-30, operator approved in chat: "approve
  A-1 and the 471 floor, go ahead"):**
  1. ROUND-002 A-1 written (AC-2 420 / 60) and NET-003's provenance note written,
     as the Contract assigns.
  2. AC-5's floor is **471**, not 452. The suite was re-measured after
     HARNESS-021/022 merged: `464 passed, 7 failed` in 47 s, the same seven
     failures the Contract's table predicts. A floor of 452 would have let 19
     tests go missing unnoticed. Changed while the story was still PLANNED.
  3. The Contract's gate-hash bullet and this harness-gap note are updated for
     HARNESS-021/022; the RED brief names `GatedFs`.
  4. The caller list was re-run against the tree and matches, except that
     `RoundConfig.luau` maps `round_seconds` at :50 now, not :46.
  5. Epic check: EPIC-01's done-when is already met by its closing table, and the
     clock-ending test takes its duration from the test, so this story opens no
     gap.
- **At DONE**, the Lead PO strikes product-brief §0d's "Consequences for the tree,
  not yet acted on" bullet about the three test files, and cites ROUND-006.

### The orchestrator's RED acceptance (2026-09-30)

1. **Suite, run independently:** `lune run test` gives `473 passed, 3 failed`.
   The three are exactly the predicted demand: `tuning_spec_test` spec -> module
   (`round_seconds ... spec 420, module 480`, `traversal_reserve_seconds ... spec
   60, module 120`), `tuning_test` AC-2 (same two values), and the rewritten
   ROUND-006 AC-3 (`lobby_seconds 60 + round_seconds 480 = 540, which exceeds
   first_round_within_seconds 480`). No import error; every assertion ran.
2. **An independent probe, not a re-run of P2:** the ping row set to **9**, just
   below the floor (the test-developer used 3), through `mutate.sh`:

       FAIL  tests/net/rate_limit_provenance_test.luau :: AC-4: tuning.md fixes ping_rate_limit_seconds in exactly one table row, as a bare number, at or above the preset guideline's 10 s
       docs/wiki/game/tuning.md:123 §3: `ping_rate_limit_seconds` is 9 in the document, below the floor of 10 - ...
       472 passed, 4 failed
       === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T221321Z.1062351.bak) ===

   One extra red, the lone assertion predicted, and the preset and superseded
   guards stayed green. The file was restored.
3. **Frozen:** the game docs, `src/shared/Tuning.luau` and
   `src/net/RateLimiter.luau` were snapshotted before dispatch (the lock does not
   freeze docs in RED). `frozen: OK — 7 path(s) unchanged since the snapshot for
   ROUND-006`, after both the test-developer's probes and mine.
4. **`gates.sh --fast`:** format, lint, typecheck and build PASS; `unit` FAILS
   with exactly the three demand failures above, which is admissible. `harness`
   failed only on the precondition "the working tree carries no stray .luau
   files", because RED's edits were uncommitted. RED is committed, as the house
   practice is, and `harness` is re-run on that commit below.
5. **On the RED commit `15b780a`:** `gates.sh --gate harness` gives `PASS
   harness (15s, observed 40)`. RED is finished.

### The orchestrator's GREEN acceptance (2026-09-30)

1. **Resolved model:** GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5).
   Planned `opus`, dispatched with an explicit `model: opus`.
2. **Diff:** `src/shared/Tuning.luau` (420 / 60, the per-operation comment
   `(420 - 60) / 8`, amendment 12 rewritten as resolved) and the
   `src/net/RateLimiter.luau` comment. Nothing else; types and freezing
   unchanged.
3. **Freeze:** snapshot taken right after `phase.sh set ROUND-006 GREEN`, over the
   six RED test files, `TuningFakes.luau`, `tuning_spec_test.luau` and the five
   game docs. Before leaving GREEN:
   `frozen: OK — 13 path(s) unchanged since the snapshot for ROUND-006`
4. **Suite, run independently:** `476 passed, 0 failed` (AC-5 floor 471).
5. **A discrimination mutation of my own**, not one of D-1 to D-3: `round_seconds`
   420 to **419**. Predicted: the spec guard and AC-2 red, and AC-3 **green**
   (60 + 419 = 479 <= 480, so the day-1 check is `<=`, not `==`). Measured:

       FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
       FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
       round_seconds (docs/wiki/game/tuning.md §5 -> Tuning.round): spec 420, module 419
       pass  tests/shared/tuning_test.luau :: ROUND-006 AC-3: lobby_seconds + round_seconds meets first_round_within_seconds ...
       474 passed, 2 failed
       === mutate: command exited 1; restored (verified byte-for-byte ...) ===

   The count matched the prediction.
6. **`gates.sh --fast` on the GREEN commit `2b1f066`:** format, lint, typecheck,
   unit (`observed 476, floor 443`), build and harness all PASS. "changes: 2
   changed source path(s), all exercised by a required gate." GREEN is finished.
   **For GATES:** the `unit` floor in `project.conf` is 443 and the suite is now
   476. Decide there whether to raise it (Lead PO's file).

### GATES (2026-09-30)

1. **Freeze:** snapshot taken right after `phase.sh set ROUND-006 GATES`, over the
   same 13 paths as GREEN.
2. **D-1, D-2 and D-3 were run before `gates.sh`.** All came out as predicted; the
   results are pasted under `## Deferred verifications`. `git status -- src` was
   clean afterwards.
3. **PO decision: the `unit` floor stays at 443.** Raising it would change a gate
   (`project.conf`), which is outside this story's scope and would owe a
   `## Gate probes` entry. AC-5's ">= 471" is shown by the recorded run's
   `observed` count instead. Raising the floor to the current count is left to
   the next story that adds tests.
4. **Full `gates.sh`:** all required gates PASS (6 ran, 3 unconfigured), recorded
   by the script under `## Gate results`. `unit` observed 476, which meets AC-5's
   floor of 471. The optional gates (coverage, integration, mutation) are
   unconfigured, and no `WARN` was raised. Freeze before leaving GATES:
   `frozen: OK — 13 path(s) unchanged since the snapshot for ROUND-006`

### REVIEW → DONE (2026-09-30)

- PR [ryanczhang7/first-roblox#41](https://github.com/ryanczhang7/first-roblox/pull/41)
  merged at 2026-09-30T22:55:53Z as `7140e26`.
- **CI timings, read from the first run:** `boundaries` pass in 6 s. `gates` pass
  in 2 m 58 s against `timeout-minutes: 45`, with `unit` taking 5 s
  (`476 passed, 0 failed`) and `harness` 14 s. Nothing is near a limit, and no
  gate went through the *pending CI* path.
- Product-brief §0d's "Consequences for the tree, not yet acted on" bullet about
  the three test files is struck through, citing ROUND-006.
