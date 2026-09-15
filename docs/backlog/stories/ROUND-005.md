---
id: ROUND-005
title: A round ends on outcome, clock or quorum with a deterministic reason
slug: a-round-ends-on-outcome-clock-or-quorum
epic: EPIC-01
type: feature
status: todo
phase: PLANNED
branch: story/ROUND-005-a-round-ends-on-outcome-clock-or-quorum
depends_on: [ROUND-003, ROUND-004]
required_gates: []
---

## Context

A round can end three ways, and the third is not a loss.

1. **An outcome event.** Something in the round resolved it. M3 decides what; the
   machine routes it (`ROUND-003` AC-3).
2. **The clock.** `round_seconds` elapses — `lost`, reason `clock`.
3. **Quorum.** The seated count falls below `min_players_to_continue` (3). This is
   `no_contest`: `mechanics.md` §8 — *"no loss is recorded and season progress is
   unaffected: the group did not fail, the lobby did."*

The part that needs specifying rather than assuming is what happens when two land
in the same step. `mechanics.md` §8 is explicit that deterministic ordering
matters **because the trace reports the reason**, and a reason that depends on
evaluation order is a bug report nobody can reproduce.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a round in `Round`, when the clock is advanced past
  `round_seconds` with no other event, then the phase becomes `Resolution` with
  outcome `{ result = "lost", reason = "clock" }`, and not before: at
  `round_seconds − 0.1` elapsed the phase is still `Round`.
- **AC-2** — Given a round in `Round` with the minimum seated count, when enough
  players leave that the count falls below `min_players_to_continue`, then the
  phase becomes `Resolution` on that step with outcome
  `{ result = "no_contest", reason = "below_quorum" }`.
- **AC-3** — Given a round that ended `no_contest`, when the resulting state is
  inspected, then it is distinguishable from a loss: `result` is `"no_contest"`,
  never `"lost"`.
  *Control:* an implementation that records a quorum failure as `lost` **must**
  fail this. A test asserting only "the round ended" cannot tell them apart, and
  the difference is whether a group's season progress is harmed by somebody else's
  connection.
- **AC-4** — Given a step in which the clock has expired **and** a `RoundResolved`
  event arrives, then the outcome recorded is the one the event carried, not
  `clock`.
  *Semantics:* the event describes something that happened inside the round; the
  clock describes the round running out around it. The event wins.
- **AC-5** — Given a step in which the clock has expired **and** the seated count
  has fallen below quorum, then the recorded reason is the same on every run, and
  it is `below_quorum`.
  *Semantics:* a round nobody can play did not run out of time. The precedence is
  `RoundResolved` > `below_quorum` > `clock`, stated once, here and in
  `architecture.md` §3.
- **AC-6** — Given any of the three endings, when the effects of the ending step
  are inspected, then exactly one `ComputeTrace` effect is emitted, carrying the
  round id — and the round does **not** continue to accumulate effects after
  ending.
  *Control:* an implementation that keeps ticking a finished round emits a second
  `ComputeTrace` and **must** fail this.
- **AC-7** — Given a `Round` phase, when a `PlayerLeft` reduces the count to
  exactly `min_players_to_continue`, then the round **continues**. Three is a ring
  (`roles.md` §6); the threshold is "below", not "at or below".

## Contract

Extends `src/server/round/PhaseMachine.luau`. No signature change, so no caller
list to grep.

### Outcome vocabulary owned by this story

    { result = "lost",       reason = "clock" }
    { result = "no_contest", reason = "below_quorum" }

Every other `reason` string is M3's and arrives inside a `RoundResolved` event.
This module must not enumerate them.

### Precedence, stated once

Within a single `step`, terminal conditions are evaluated in this fixed order and
the first that holds wins:

    1. RoundResolved  (an event carrying an outcome)
    2. below_quorum   (seated count < minPlayersToContinue)
    3. clock          (now - phaseEnteredAt >= roundSeconds)

This ordering is the contract. It is not an implementation detail and a later
story may not reorder it without an `## Amendments` entry, because
`mechanics.md` §7 reports the reason to players and `TEL-002` emits it as
telemetry.

### The degraded round

`roles.md` §6 notes that a round continuing at `n = 3` after a dropout is
*playable but structurally thinner* — "a degraded round, not a different game" —
and that the trace should say so rather than record it as a clean result. This
story does **not** implement that flag. It is recorded here so the omission is a
decision: the trace is M3, and a flag with no consumer is a field that rots.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-7 | **Settled** | `round_seconds` and `min_players_to_continue` come from `ROUND-002` via `RoundConfig`. Read them out. AC-7's boundary — "below", not "at or below" — is `tuning.md` §1's derivation, not a choice. |
| AC-3, AC-6 | **Mechanical, with controls** | The controls are in the criteria. |
| AC-4, AC-5 | **Mechanical** | The precedence list is written above. Pin it exactly; do not invent a tie-break. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None. Simultaneity is producible in RED by constructing the state directly — that is the payoff of a pure `step` that takes `now` as an argument.
-->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

AC-4 and AC-5 are the criteria to brief carefully. Both describe a *single step*
in which two conditions hold, and the natural test — advance the clock, then send
the event — tests two steps and asserts nothing about precedence. Say so in the
dispatch: **construct the simultaneous state directly.**

## Out of scope

- What resolves a round successfully. M3 supplies `won` and its reasons.
- The degraded-round flag at `n = 3`. Recorded above as a deliberate omission.
- The `disconnect_grace_seconds` window. A player who leaves is gone for quorum
  purposes immediately; the grace window governs whether their **seat** is
  reassigned, which is `SEAT-003`.
- Season progress accounting. The `no_contest` result is recorded; what consumes it
  is M5.
- Telemetry for the ending. `TEL-002`.

## Game design

Implements `mechanics.md` §8's terminal rows and `tuning.md` §1's
`min_players_to_continue` (3, derived: a 3-cycle ring is still a ring).

The decision AC-3 protects is a real one from the design: **a lobby that empties
must not cost the remaining players anything.** Under amendment 9 progression is
shared and seasonal, so recording a disconnection-driven collapse as a group loss
would punish three people for a fourth person's connection — in a game whose
retention thesis is that the same four people keep playing together.

`mechanics.md` §8 also specifies "the round becomes unwinnable → end immediately
with a stated reason, never run out a clock on a group that cannot win." That
requires knowing the remaining operations, which is M3. When it lands it becomes a
fourth `RoundResolved` reason, arriving through the event, and this module does not
change.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Change the quorum comparison from `<` to `<=`. Predicted: AC-7 goes red alone —
   a single assertion, and exactly the off-by-one that would silently end every
   three-player round.
2. Reorder the precedence list so `clock` precedes `below_quorum`. Predicted: AC-5
   goes red.
3. Record the quorum ending as `result = "lost"`. Predicted: AC-3 goes red. If it
   stays green, AC-3 was written as "the round ended".

Run mutation 1 first.

**Raise the `unit` floor** to the new real count.
