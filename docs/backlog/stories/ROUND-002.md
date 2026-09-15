---
id: ROUND-002
title: Session and round-timing constants match their specification
slug: session-and-round-timing-constants-match
epic: EPIC-01
type: feature
status: todo
phase: PLANNED
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

None.

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
