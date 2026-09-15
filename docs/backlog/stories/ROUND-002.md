---
id: ROUND-002
title: Session and round-timing constants match their specification
slug: session-and-round-timing-constants-match
epic: EPIC-01
type: feature
status: in-review
phase: REVIEW
branch: story/ROUND-002-session-and-round-timing-constants-match
depends_on: [BOOT-001]
required_gates: []
---

## Context

`docs/wiki/game/tuning.md` opens with a rule: **that file is the specification,
the module is source, and if the two disagree that is a defect** — to be raised
with the Lead PO rather than fixed by editing either to match. This story builds
the module and the check that makes the rule enforceable instead of aspirational.

Scope is `tuning.md` **§1 (session and lobby)** and **§5 (round timing)** only.
Those are the constants the phase machine needs. §2–§4 and §6 describe the
instance, the signal channel, actuation and difficulty bands, which are M3; they
land with the mechanics that use them, so that a placeholder is not frozen into
source a year before anything reads it.

Two constants here carry live disagreements, and the module records the specified
values without resolving either:

- `first_round_within_seconds` is 480, and `lobby_seconds` 60 + `round_seconds`
  480 = 540. A5's day-1 promise is **already violated by the specification**
  (product-brief §0c, amendment 12). That is an open operator decision, not this
  story's to close. The module takes the specified values; the conflict is flagged
  in the brief.
- `players_max` = 6 was open pending Lead PO ratification and is now **ratified**
  (product-brief §0c, R1).

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given the module, when each constant named in `tuning.md` §1 is read,
  then it holds the value the specification gives: `players_min` 4, `players_max`
  6, `min_players_to_continue` 3, `lobby_seconds` 60, `post_round_seconds` 45,
  `season_length_days` 28.
- **AC-2** — Given the module, when each constant named in `tuning.md` §5 is read,
  then it holds the specified value: `round_seconds` 480, `round_seconds_min` 360,
  `round_seconds_max` 600, `per_operation_seconds` 45,
  `traversal_reserve_seconds` 120, `first_round_within_seconds` 480,
  `disconnect_grace_seconds` 30.
- **AC-3** — Given the module, when any consumer attempts to assign to a constant
  or add a key, then the attempt fails rather than succeeding silently.
- **AC-4** — Given the specification file and the module, when the guard runs, then
  every constant named in `tuning.md` §1 and §5 is present in the module with a
  matching value, and any constant present in one and not the other is reported by
  name.
  *Control:* changing one value in the module — `lobby_seconds` from 60 to 61 —
  **must** make this guard fail and **must** name `lobby_seconds` in the failure.
  Removing a row from the guard's parsed set must also fail: a guard that parses
  zero rows and compares them all successfully is the failure mode here, so the
  guard asserts the number of rows it parsed is at least 13.
- **AC-5** — Given the module, when its exported keys are inspected, then none
  matches a constant `tuning.md` §7 records as **deliberately absent**: no
  `hidden_faction_ratio`, no key beginning `vote_`, and no per-player score, rank,
  MMR or ladder constant.
  *Control:* adding `vote_seconds = 30` to the module **must** make this fail.

## Contract

### `src/shared/Tuning.luau`

    export type SessionTuning = {
        players_min:             number,
        players_max:             number,
        min_players_to_continue: number,
        lobby_seconds:           number,
        post_round_seconds:      number,
        season_length_days:      number,
    }

    export type RoundTuning = {
        round_seconds:             number,
        round_seconds_min:         number,
        round_seconds_max:         number,
        per_operation_seconds:     number,
        traversal_reserve_seconds: number,
        first_round_within_seconds: number,
        disconnect_grace_seconds:  number,
    }

    Tuning.session : SessionTuning     -- frozen
    Tuning.round   : RoundTuning       -- frozen

**Names are the specification's names**, verbatim, including the snake_case. This
is deliberate and it is what makes AC-4's guard a string comparison rather than a
translation table. A translation table is a second place for the two documents to
disagree.

**Freezing** is `table.freeze`, applied to each table and to the module table. AC-3
is about a consumer *mutating* tuning at run time, which would make a round's
behaviour depend on load order.

**Units.** Every `*_seconds` is seconds; `season_length_days` is days;
`players_*` and `min_players_to_continue` are counts of seated players.
`per_operation_seconds` is `(round_seconds − traversal_reserve_seconds) /
procedure_length` — stated in `tuning.md` so that changing `procedure_length`
changes `round_seconds` rather than silently compressing the game. It is carried
here as a specified value, **not** computed, because `procedure_length` is an M3
constant that does not exist yet; when it arrives, the relation becomes a test.

### The guard — `tests/shared/tuning_spec_test.luau`

Parses the markdown tables in `docs/wiki/game/tuning.md` §1 and §5 and compares
them to the module. Two properties the guard must have, both learned expensively
elsewhere:

- **It asserts how much it parsed.** A parser that silently matches nothing
  compares nothing and passes. AC-4's floor of 13 rows is that assertion.
- **It reports by name.** "Tuning mismatch" is a failure nobody can act on;
  "`lobby_seconds`: spec 60, module 61" is one anybody can.

Parsing a document in a test is unusual and worth justifying: the alternative is a
duplicated list of values in the test, which is a third copy for the two documents
to disagree with. The specification file *is* the oracle here, by its own first
paragraph.

### Test-only dependencies

None. Reading a file is `@lune/fs`.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2 | **Settled** | **Read the numbers out of `tuning.md`. Do not derive, tune or "calibrate" them**, and do not resolve the `first_round_within_seconds` conflict — it is an open operator decision recorded in the brief. |
| AC-3, AC-5 | **Mechanical** | Pin exactly. |
| AC-4 | **Oracle-free** | You are inventing the parser and its self-check. The row-count floor is the control that matters. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None.
-->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch; do not write
"default".)_

AC-1 and AC-2 are the clearest **settled** criteria in the backlog and the brief
should say so loudly. A Test Developer told "design the metric" across all five
criteria would re-derive values the Game Designer already derived and the operator
already ratified — the audit problem arriving from the other direction.

## Out of scope

- `tuning.md` §2, §3, §4, §6 — the instance, the signal channel, actuation and
  instability, difficulty bands. M3, with the mechanics that read them.
- Resolving amendment 12's day-1 conflict. Operator's, per product-brief §0c.
- Any consumer of these constants. `ROUND-003` builds the first one.
- A difficulty-band lookup. `difficulty_band` is `taste-pending` on T5 and the
  module must not pre-empt the operator by shipping a band structure.

## Game design

This story implements no mechanic. It implements the **specification-to-source
link** that `tuning.md`'s opening paragraph asserts, for the constants in §1 and
§5 only.

The constants it carries and their labels (`tuning.md`):

| Constant | Label | Note for the implementer |
|---|---|---|
| `players_min` 4 | derived | brief §0b amendment 1, §0c R1 |
| `players_max` 6 | derived | channel contention, not preference. Supersedes A4's cap of 16. |
| `min_players_to_continue` 3 | derived | a 3-cycle is still a ring |
| `lobby_seconds` 60 | taste | UX pacing; the Lead Designer owns it once a screen exists |
| `post_round_seconds` 45 | **placeholder** | raised from A4's 30 because the trace is four items of reading |
| `round_seconds` 480 | **placeholder** | moves together with `procedure_length`; tune as a pair |
| `traversal_reserve_seconds` 120 | **placeholder** | a guess with no observation behind it at all |
| `disconnect_grace_seconds` 30 | **placeholder** | replace with observed reconnect times once telemetry exists |

Four placeholders. That is fine and it is the point of the label: the module is
where they live so that changing one is a one-line change with a guard behind it,
not a search through the codebase.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. `sed` `lobby_seconds = 60` to `61` in the module. Predicted: AC-1 and AC-4 both
   go red, and AC-4's message names `lobby_seconds`. If AC-4 stays green, the
   parser is matching nothing.
2. Break the guard's section-header match so it parses zero rows. Predicted: the
   row-count floor fires. If the test goes green, AC-4 is vacuous and the story is
   not done.

**Raise the `unit` floor** to the new real count.

## Test plan

| AC | Level | Where |
|---|---|---|
| AC-1, AC-2 | unit, against `src/shared/Tuning.luau` | `tests/shared/tuning_test.luau` |
| AC-3 | unit — a real write attempt through `pcall`, both an existing key and a new one | `tests/shared/tuning_test.luau` |
| AC-4 | integration with the repository — it reads `docs/wiki/game/tuning.md` off disk and compares it to the module | `tests/shared/tuning_spec_test.luau` |
| AC-5 | unit, over the module's exported keys | `tests/shared/tuning_test.luau`, anchored to §7 in `tests/shared/tuning_spec_test.luau` |
| AC-4, AC-5 controls | unit, over deliberately wrong modules, **requiring no production code** | `tests/shared/tuning_controls_test.luau` |

The criteria are written **once**, as checks over a module-shaped table
(`tests/helpers/TuningSpec.luau`), and applied twice: to the real module, and to
the wrong ones in `tests/helpers/TuningFakes.luau`. That is ROUND-001's shape and
it exists for the hazard `rules.md` names — in RED the module does not exist, the
files that require it die at `require`, and **not one assertion in them has run**,
so every control in them would be unverified for the whole phase. The controls
file requires nothing from `src/`, so all fifteen of its checks executed during
RED and every number in the handoff below is measured rather than predicted.

**The oracle is the specification file, parsed.** The Contract's reasoning holds:
a duplicated list of thirteen values in the test would be a third copy for the
two documents to disagree with. There is exactly one deliberate copy —
`TuningSpec.ACCEPTANCE`, which is AC-1 and AC-2 **as frozen by this story** — and
it is the third point of a triangle rather than a convenience:

- the module is checked against it (AC-1, AC-2);
- `tuning.md` is checked against it (AC-4's drift check);
- the module is checked against `tuning.md` directly (AC-4).

A value edited in the specification under a frozen story therefore surfaces as
"the specification has moved under frozen acceptance criteria" rather than being
absorbed silently by a guard that only ever compares two things to each other.

**Two things about the parser are load-bearing.** It reads `## <n>.` headings, so
§2's `### Generator invariants` subsection cannot reopen a target section; and
§5's `` `round_seconds_min` / `_max` | 360 / 600 `` row is two constants on one
markdown row, handled by a general suffix-shorthand rule rather than by
special-casing that row or editing the Game Designer's file. Thirteen constants
come out of six §1 rows and six §5 rows.

**AC-4's floor is asserted twice, because a count alone is not enough.** §2 of
`tuning.md` has *exactly thirteen* constant rows of its own, so a parser pointed
at the wrong section would satisfy a count-only floor and prove nothing. The
guard asserts the count **and** that the constants it found include every one the
frozen criteria name. `tuning_controls_test.luau` demonstrates the gap: thirteen
filler rows pass the count and fail the names.

## Regressions

Four assertions in `tuning_spec_test.luau` are green the moment they are written,
because `docs/wiki/game/tuning.md` already exists — the row floor, the expected
names, the unread-row check and the drift check. `rules.md` says an assertion
that has never been observed failing is not a test, so each was earned by a
`scripts/mutate.sh` run against the specification file. The file is **not**
edited by this story: `mutate.sh` restores it and verifies the restore with `cmp`,
and both restores are shown below.

**Probe 1 — break the §1 heading so the parser matches nothing there.** This is
mutation 2 from `## Notes`, and the row floor is what has to fire.

    $ bash scripts/mutate.sh docs/wiki/game/tuning.md \
        's/^## 1\. Session and lobby$/## Session and lobby/' -- lune run test

    === mutate: docs/wiki/game/tuning.md (1 line(s) changed by s/^## 1\. Session and lobby$/## Session and lobby/) ===
    === mutate: running lune run test ===
      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: the guard parses at least thirteen constants from tuning.md §1 and §5
            tests/helpers/TuningSpec:275: AC-4: the guard parsed 7 constants from docs/wiki/game/tuning.md §1 and §5, expected at least 13. A parser that matches nothing compares nothing and passes.
      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: the constants the guard parsed include every one §1 and §5 name
            AC-4: the guard parsed 7 constants from docs/wiki/game/tuning.md but not these:
              lobby_seconds (expected in the rows for Tuning.session)
              min_players_to_continue (expected in the rows for Tuning.session)
              players_max (expected in the rows for Tuning.session)
              players_min (expected in the rows for Tuning.session)
              post_round_seconds (expected in the rows for Tuning.session)
              season_length_days (expected in the rows for Tuning.session)
      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze
            lobby_seconds: ROUND-002 freezes it at 60, docs/wiki/game/tuning.md no longer names it
            ...
    63 passed, 20 failed

    === mutate: command exited 1; restored (verified byte-for-byte against
        .claude/state/mutations/docs_wiki_game_tuning.md.20260915T202750Z.1746386.bak) ===
      24: ## 1. Session and lobby

Seven additional failures against the 13 of the unmutated run. Worth knowing for
GREEN: the four controls that compare against rows parsed from the **real**
specification also went red, which is correct — they are coupled to the real
oracle on purpose — but it means a genuine spec break is noisy.

**Probe 2 — move a value in the specification.** `lobby_seconds` 60 → 61, the
same mutation AC-4 names, applied to the side of the comparison that exists in
RED.

    $ bash scripts/mutate.sh docs/wiki/game/tuning.md 's/| 60 | taste |/| 61 | taste |/' \
        -- lune run test

    === mutate: docs/wiki/game/tuning.md (1 line(s) changed by s/| 60 | taste |/| 61 | taste |/) ===
      31 - | `lobby_seconds` | 60 | taste | inherited from A4. ...
      31 + | `lobby_seconds` | 61 | taste | inherited from A4. ...
      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze
            AC-4: the specification has moved under frozen acceptance criteria. This is not a test to edit: rules.md says an acceptance criterion changes only through an `## Amendments` entry, and tuning.md says a disagreement goes to the Lead PO:
              lobby_seconds: ROUND-002 freezes it at 60, docs/wiki/game/tuning.md:31 now says 61
      FAIL  tests/shared/tuning_controls_test.luau :: baseline: a correct module passes every AC-4 and AC-5 check against the real tuning.md
            AC-4 spec -> module:
              lobby_seconds (docs/wiki/game/tuning.md §1 -> Tuning.session): spec 61, module 60
      FAIL  tests/shared/tuning_controls_test.luau :: AC-4 control: lobby_seconds 61 fails the guard and the failure names lobby_seconds
            a module whose lobby_seconds is 61 must fail AC-4
            but the check passed, so the check is vacuous
    65 passed, 18 failed

    === mutate: command exited 1; restored (verified byte-for-byte against
        .claude/state/mutations/docs_wiki_game_tuning.md.20260915T202806Z.1746840.bak) ===
      31: | `lobby_seconds` | 60 | taste | inherited from A4. ...

The third failure is the AC-4 control reporting itself vacuous — with the
specification moved to 61, a module holding 61 agrees with it, and the control
says so rather than passing quietly. `git status` reported no change to
`docs/wiki/game/tuning.md` after either run.

## Handoff: RED -> GREEN

### The command

    bash scripts/task.sh test          # lune run test
    bash scripts/gates.sh --gate unit  # the same suite, as the gate runs it

A shell started before the toolchain install needs `export
PATH="$HOME/.rokit/bin:$PATH"` first. Do **not** set `MSYS_NO_PATHCONV`; it
breaks `git -C` inside `gates.sh`.

### The failure, verbatim

`70 passed, 13 failed`, from `lune run test`. All thirteen are the module that
does not exist yet; every one of them names its criterion rather than arriving as
a single `LOAD FAIL` for a whole file, which is what the `pcall`-at-the-top
pattern buys:

      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant the module exposes is named in tuning.md §1 or §5
            tests/shared/tuning_spec_test:38: src/shared/Tuning.luau did not load: error requiring module "../../src/shared/Tuning": could not resolve child component "Tuning"
      FAIL  tests/shared/tuning_spec_test.luau :: AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value
            tests/shared/tuning_spec_test:38: src/shared/Tuning.luau did not load: ...
      FAIL  tests/shared/tuning_test.luau :: AC-1: Tuning.session exposes no constant tuning.md §1 does not name
      FAIL  tests/shared/tuning_test.luau :: AC-1: every session constant tuning.md §1 names holds its specified value
      FAIL  tests/shared/tuning_test.luau :: AC-2: Tuning.round exposes no constant tuning.md §5 does not name
      FAIL  tests/shared/tuning_test.luau :: AC-2: every round constant tuning.md §5 names holds its specified value
      FAIL  tests/shared/tuning_test.luau :: AC-2: the day-1 conflict amendment 12 records is carried, not resolved
      FAIL  tests/shared/tuning_test.luau :: AC-3: adding a new key to Tuning.round fails
      FAIL  tests/shared/tuning_test.luau :: AC-3: adding a new key to Tuning.session fails
      FAIL  tests/shared/tuning_test.luau :: AC-3: assigning to an existing round constant fails
      FAIL  tests/shared/tuning_test.luau :: AC-3: assigning to an existing session constant fails
      FAIL  tests/shared/tuning_test.luau :: AC-3: the module table itself rejects assignment and new keys
      FAIL  tests/shared/tuning_test.luau :: AC-5: no exported key names a constant tuning.md §7 records as deliberately absent
            tests/shared/tuning_test:27: src/shared/Tuning.luau did not load: error requiring module "../../src/shared/Tuning": could not resolve child component "Tuning"
    70 passed, 13 failed

`bash scripts/gates.sh --fast` gives the shape RED wants: `format` PASS,
`lint` PASS, `typecheck` PASS, `build` PASS, `unit` FAIL (exit 1). The `observed`
counts on `format` and `lint` are 15 because they come from `git ls-files` and
the five new files are uncommitted; that is expected and not a failure.

### The export shape these tests already pin

Stated as fact, not suggestion — a test already imports it and a wrong guess is a
failing run.

- **Module path** `src/shared/Tuning.luau`, resolving as `require("../../src/shared/Tuning")`
  from `tests/shared/`. It returns a **table**.
- **`Tuning.session`** — a table whose keys are **exactly** these six, all
  `number`: `players_min` 4, `players_max` 6, `min_players_to_continue` 3,
  `lobby_seconds` 60, `post_round_seconds` 45, `season_length_days` 28.
- **`Tuning.round`** — a table whose keys are **exactly** these seven, all
  `number`: `round_seconds` 480, `round_seconds_min` 360, `round_seconds_max` 600,
  `per_operation_seconds` 45, `traversal_reserve_seconds` 120,
  `first_round_within_seconds` 480, `disconnect_grace_seconds` 30.
- Names are snake_case verbatim, as the Contract requires: AC-4's guard is a
  string comparison against the specification's own names.
- **`Tuning.session`, `Tuning.round` and the module table are all frozen.** The
  tests attempt a real write through `pcall` and require it to **raise** — an
  assignment that is silently ignored fails the test just as a successful one
  does.
- `first_round_within_seconds` is **480**, and a test fails if
  `lobby_seconds + round_seconds` stops exceeding it. Amendment 12's day-1
  conflict is transcribed, not resolved; "fixing" it here is a test failure.

**Not constrained, and deliberately left to you:** key order; whether `Tuning`
carries anything besides `session` and `round` (subject to AC-5's rules, which
also scan the top-level keys); whether AC-3 comes from `table.freeze` or a
`__newindex` metatable; the wording of any error the module raises — nothing
asserts on it. The Contract's `export type SessionTuning` / `RoundTuning` are
**not** pinned by any test (the `typecheck` gate covers `src/` only, and types
erase at run time); write them because the Contract asks, not because a test
will catch their absence.

### One line per test

`tests/shared/tuning_test.luau` — 11 tests, all red, all on the missing module:

| Test | Asserts | AC |
|---|---|---|
| every session constant … holds its specified value | all six §1 values and that each is a number; accumulates and reports every mismatch at once | AC-1 |
| Tuning.session exposes no constant … §1 does not name | no extra keys in `session` | AC-1, AC-4 |
| every round constant … holds its specified value | all seven §5 values | AC-2 |
| Tuning.round exposes no constant … §5 does not name | no extra keys in `round` | AC-2, AC-4 |
| the day-1 conflict amendment 12 records is carried, not resolved | `first_round_within_seconds == 480` and `lobby + round > it` | AC-2 |
| assigning to an existing session constant fails | `session.lobby_seconds = 999` raises and does not change | AC-3 |
| assigning to an existing round constant fails | `round.round_seconds = 999` raises and does not change | AC-3 |
| adding a new key to Tuning.session fails | `session.warmup_seconds = 15` raises, key stays `nil` | AC-3 |
| adding a new key to Tuning.round fails | `round.overtime_seconds = 15` raises, key stays `nil` | AC-3 |
| the module table itself rejects assignment and new keys | `Tuning.session = {}` and `Tuning.instance = {}` both raise | AC-3 |
| no exported key names a constant … §7 records as deliberately absent | the absence rules, after asserting the module is non-empty | AC-5 |

`tests/shared/tuning_spec_test.luau` — 7 tests, 2 red, 5 green on arrival:

| Test | Asserts | AC | State |
|---|---|---|---|
| the guard parses at least thirteen constants … | `#rows >= 13` | AC-4 | green; earned by probe 1 |
| the constants the guard parsed include every one §1 and §5 name | all thirteen names present | AC-4 | green; earned by probe 1 |
| no row of tuning.md §1 or §5 was left unread | `#problems == 0` | AC-4 | green; earned by the unread-row control |
| tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze | spec == frozen AC values | AC-4 | green; earned by probe 2 |
| every constant … is in the module with a matching value | spec → module, by name | AC-4 | **red** |
| every constant the module exposes is named in tuning.md §1 or §5 | module → spec, by name | AC-4 | **red** |
| tuning.md §7 still records the absences the guard's rules encode | §7 still mentions `hidden_faction_ratio`, `vote_`, score, rank, MMR, ladder | AC-5 | green; anchors the transcription |

`tests/shared/tuning_controls_test.luau` — 15 tests, **all green, all executed in
RED**, none of them touching `src/`. They are the story's evidence that the
checks discriminate before the module exists. See the table below.

### Negative controls: expected and measured

Every number here was **measured during RED**, not predicted: the controls file
requires no production code, so it ran. The module-facing files did not run, so
GREEN should still confirm the two marked ⇒.

| Control | Check it drives | Expected | Measured in RED |
|---|---|---|---|
| the real `tuning.md`, parsed | `TuningSpec.parse` | ≥ 13 rows, 0 unread | **13 rows** (6 from §1 at lines 28–33, 7 from §5 at lines 117–122), **0 problems** |
| `TuningFakes.correct()` vs the 13 real rows | baseline | 0 findings each direction | **0**, **0**; absence check passes; `constantCount` **13** |
| `lobby_seconds = 61` | `missingOrMismatched` | fails, names `lobby_seconds` | `lobby_seconds (docs/wiki/game/tuning.md §1 -> Tuning.session): spec 60, module 61` |
| `season_length_days` removed | `missingOrMismatched` | fails, names it | `season_length_days (… §1 -> Tuning.session): spec 28, absent from the module` |
| `round.warmup_seconds = 15` | `unspecified` | fails, names it | `warmup_seconds (Tuning.round): in the module, named nowhere in docs/wiki/game/tuning.md §1 or §5` |
| `round_seconds = "480"` (string) | `missingOrMismatched` | fails on type | `round_seconds (… §5 -> Tuning.round): spec 480, module string` |
| **zero parsed rows** vs the 61 module | `missingOrMismatched` | **0 findings — the vacuous pass, demonstrated** | **0 findings** |
| **zero parsed rows** | `assertEnoughRows` | fails | `AC-4: the guard parsed 0 constants from docs/wiki/game/tuning.md §1 and §5, expected at least 13.` |
| 13 filler rows (`filler_1..13`) | `assertEnoughRows` / `assertExpectedNames` | passes / fails | passes the count; names all 13 expected constants as missing |
| a value cell with no number | `parse` / `assertNoParseProblems` | reported, not skipped | exactly **1** problem, naming `delta_seconds` and `soon` |
| `vote_seconds = 30` | `assertNoAbsentConstants` | fails, names it | `vote_seconds (Tuning.session) is deliberately absent - tuning.md §7: there is no vote …` |
| `hidden_faction_ratio = 0.25` | same | fails, cites amendment 8 | measured, message contains both |
| `player_score_weight`, `rank_decay_days`, `mmr_k_factor`, `ladder_tiers` | same | each fails, cites amendment 9 | all four measured |
| `vote_deadline_seconds` at the **top level** | same | fails, scope `(Tuning)` | measured |
| **the empty module** | `absenceFindings` / `assertNoAbsentConstants` | 0 findings / **fails** | **0 findings**, then `AC-5: the absence check ran over a module exposing 0 constants, expected at least 13. "No key matches" is true of an empty table.` |

⇒ **GREEN must confirm two things the controls could not reach**: that
`missingOrMismatched(realRows, Tuning)` and `assertNoAbsentConstants(Tuning)`
return **0 findings** against the *shipped* module, and that `constantCount` of
the shipped module is **13**. RED measured those against a fake built from the
frozen criteria; the fake is not the module.

**Timing.** All numbers above are from a **local** run on Windows; nothing here
came from CI. The whole suite is 8 s under the `unit` gate locally, the runner has
no per-test timeout, and no test in this story loops, sleeps or allocates — there
is no budget to blow and none is set.

### Files written

- `tests/helpers/TuningSpec.luau` — new. The parser, the comparison in both
  directions, the drift check, the absence rules, the row floor.
- `tests/helpers/TuningFakes.luau` — new. The baseline and the one-change-each
  wrong modules.
- `tests/shared/tuning_test.luau` — new. AC-1, AC-2, AC-3, AC-5.
- `tests/shared/tuning_spec_test.luau` — new. AC-4, the guard the Contract names.
- `tests/shared/tuning_controls_test.luau` — new. The controls, executable in RED.
- `docs/backlog/stories/ROUND-002.md` — this section, `## Test plan` and
  `## Regressions`.

No production source, no configuration and no manifest was touched; this story
needs no test-only dependency (reading a file is `@lune/fs`, as the Contract
says). `docs/wiki/game/tuning.md` was mutated twice by `scripts/mutate.sh` and
restored byte-for-byte both times.

### For the implementer

- **The suite goes to 83 tests** (70 passing now). `floor | unit | 50` in
  `.claude/harness/project.conf` must be raised at GATES to the count of the
  green suite.
- **Do not resolve amendment 12.** Two tests fail if you do.
- The thirteen values are settled and the guard reads them out of `tuning.md`;
  there is nothing to derive, calibrate or round.
- `tests/helpers/TuningSpec.luau` is where a wrong test would be fixed, not in a
  test file — five of the seven AC-4 assertions are one call each into it.
- A verification this phase could not run: nothing in `## Deferred verifications`
  belongs to RED (the section says "None"), so nothing is declined here.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-15T20:58:41Z
    commit: 1ec1f9f
    tree:   44bd36482df9ad06a586af0441736b5d750dc9f3
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 21)
    PASS         lint (1s, observed 21, floor 1)
    PASS         typecheck (3s, observed 5)
    PASS         unit (16s, observed 83, floor 83)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 8883)
    UNCONFIGURED mutation

