---
id: SEAT-003
title: A disconnect transfers the key class to the supplier and closes the ring
slug: a-disconnect-transfers-the-key-class-to
epic: EPIC-02
type: feature
status: todo
phase: PLANNED
branch: story/SEAT-003-a-disconnect-transfers-the-key-class-to
depends_on: [SEAT-002, ROUND-005]
required_gates: []
---

## Context

A disconnect breaks the ring, and `roles.md` §6 specifies the only repair that
keeps the instance solvable: **the leaver's key class transfers to their supplier**
— their ring-predecessor, the one player who could already see those required
values. The leaver's **lens is lost**, so their dependent's requirements become
unknowable and those operations must be brute-forced against instability.

The design accepts that the round gets easier and k-essentiality is degraded:
*"That is correct: the group has been harmed enough."*

Two things make this story worth its own cycle rather than a clause in `SEAT-001`.
First, the direction is easy to get backwards and structurally invisible — transfer
to the *dependent* instead of the supplier and every test about ring shape still
passes, while the round becomes unsolvable. Second, the grace window: a rejoin
inside `disconnect_grace_seconds` restores the original seat, and after it the seat
is gone. That is a timing rule, and it needs the injected clock.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a 4-player ring and a player `q` who leaves, when the withdrawal
  is applied, then `q`'s key class is held by `σ⁻¹(q)` — `q`'s **supplier** — and by
  nobody else.
  *Control:* an implementation transferring to `σ(q)`, the dependent, **must** fail
  this. It passes every test that only asserts "somebody has the class", which is
  the natural way to write it.
- **AC-2** — Given that withdrawal, when the resulting ring is inspected, then it is
  a single cycle over the remaining `n − 1` players with no fixed point, and the
  relative order of the remaining players is unchanged.
- **AC-3** — Given that withdrawal, when the supplier's holdings are inspected,
  then they hold **two** key classes, and exactly one player in the ring can now act
  on a class their own lens covers.
  *Semantics:* this is the degradation `roles.md` §6 accepts explicitly — the
  derangement property is deliberately broken for one player. A test asserting "no
  player can act on what they can see" would be asserting the *undegraded*
  invariant and would fail here correctly; assert the degraded shape instead, and
  say in the test that it is deliberate.
- **AC-4** — Given a withdrawal, when the leaver's lens is looked up, then it is
  gone — no remaining player has acquired it.
  *Semantics:* `roles.md` §6 — "the leaver's lens is lost". Handing it on would make
  a dropout a free simplification rather than a harm, and the design is explicit
  that it should be a harm.
- **AC-5** — Given a player who left at `t`, when they rejoin at
  `t + disconnect_grace_seconds − 0.1`, then their original seat, key class and lens
  are restored and the ring returns to its pre-withdrawal shape.
- **AC-6** — Given the same player rejoining at `t + disconnect_grace_seconds`,
  then the seat is **not** restored: the ring stays at `n − 1` and the rejoining
  player is not seated.
  *Semantics:* the comparison is `now - leftAt >= graceSeconds` → too late,
  inclusive, matching the phase machine's boundary convention. `roles.md` §6: "After
  it, the seat is gone and the player spectates until the next round."
- **AC-7** — Given two players leaving in succession from a 5-player ring, when both
  withdrawals are applied, then the ring is a single 3-cycle, each transfer went to
  the correct supplier **in the ring as it stood at the time of that withdrawal**,
  and no key class is held by nobody.
  *Control:* an implementation computing suppliers against the *original* ring
  passes the single-withdrawal cases and **must** fail this.
- **AC-8** — Given a ring that would fall below `min_players_to_continue` (3), when
  a withdrawal is applied, then `Ring.withdraw` still produces a well-formed
  2-player result and does **not** decide the round's fate — ending the round is
  `ROUND-005`'s job, on the phase machine's quorum rule.
  *Semantics:* one decision, one place. A ring module that ends rounds and a phase
  machine that ends rounds is two places to disagree about when a round ended.

## Contract

Extends `src/server/seats/Ring.luau`. `Ring.withdraw` and `Ring.rejoin` were
declared in `architecture.md` §5 and are implemented here.

    Ring.withdraw(assignment: Assignment, playerId: PlayerId) -> Assignment
    Ring.rejoin(assignment: Assignment, absence: Absence, now: number) -> Assignment?

    export type Absence = {
        playerId:     PlayerId,
        leftAt:       number,
        graceSeconds: number,
        snapshot:     Assignment,     -- the ring as it stood before the withdrawal
    }

`Ring.rejoin` returns `nil` when the grace window has passed. `now` is passed in;
nothing here reads a clock.

### `Assignment` gains a field

    keyClasses: { [PlayerId]: { KeyClass } }    -- a player may hold more than one

**This is a signature change to an existing exported type**, and it has callers.
Grepped before dispatch — RED cannot find these itself, because during RED the old
shape still exists and its callers still type-check:

| Caller | File | What changes |
|---|---|---|
| `Ring.assign` | `src/server/seats/Ring.luau` | returns a one-element list per player |
| `Ring.lensOf` | `src/server/seats/Ring.luau` | reads the list |
| `Projection.forPlayer` | `src/server/seats/Projection.luau` | `PublicSeatView.keyClass` becomes `keyClasses: {KeyClass}` — **and stays an allowlisted field, built literally** |
| SEAT-001's suite | `tests/server/seats/ring_test.luau` | assertions on `keyClass` |
| SEAT-002's suite | `tests/server/seats/projection_test.luau` | assertions on the view shape, including the AC-2 leak property |

`SEAT-002`'s leak property must still hold after the change: `p`'s view carries
`p`'s own classes and nobody else's. If the simplest way to represent two classes
tempts an implementation toward a shared table, that is the leak this backlog spent
a story preventing.

**Alternative considered and rejected:** keep `keyClass` singular and represent the
transfer as a separate `inheritedClasses` map. It keeps the signature stable and
splits "which classes may this player operate" across two fields, which is two
places for an actuation check to read one of. Rejected. RED may amend this block
with a reason if a third option is better.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-3, AC-4, AC-6 | **Settled** | `roles.md` §6 and `mechanics.md` §8 decide all of this, including that the round gets easier and that the lens is lost. Read it out. Do not "improve" the repair. |
| AC-2, AC-7 | **Mechanical, with a control** | AC-7's control — suppliers computed against the original ring — is the one a single-withdrawal suite cannot see. |
| AC-5, AC-6 | **Settled** | `disconnect_grace_seconds` is 30, a **placeholder** in `tuning.md` §5 to be replaced by observed reconnect times once telemetry exists. Read it through `RoundConfig`; do not hard-code 30 and do not tune it. |
| AC-8 | **Mechanical** | Pin the boundary of responsibility exactly. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None. The clock is injected and the ring is pure, so every case here is constructible in RED.
-->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

Two lines to put in the dispatch verbatim:

- **Supplier, not dependent.** `σ⁻¹(q)`, the ring-predecessor, the player who could
  already see those required values. The wrong direction is structurally invisible
  and makes the instance unsolvable.
- **AC-3 asserts a deliberately degraded invariant.** The derangement property is
  broken for exactly one player after a withdrawal, on purpose. A test that asserts
  the undegraded invariant here is asserting the wrong thing, and an implementer who
  "fixes" the degradation to make it pass has changed the design.

## Out of scope

- Ending the round. `ROUND-005` owns quorum; AC-8 pins the boundary.
- Budget restoration on rejoin. `roles.md` §6 says a rejoin inside the window
  restores "the original seat and the remaining budget" — the budget is
  `signal_budget_per_player`, M3. This story restores the seat; the budget clause is
  recorded here so M3 adds it rather than rediscovering it.
- The degraded-round flag in the trace. M3, and also deferred by `ROUND-005` and
  `SEAT-001`.
- Detecting a disconnect. That is a Roblox `Players.PlayerRemoving` signal in the
  driver; this module is fed a `PlayerLeft` event.
- Re-generating the instance after a withdrawal. The design does not re-generate;
  it degrades.

## Game design

Implements `roles.md` §6 (assignment, disconnect, rejoin) and `mechanics.md` §8's
disconnect and rejoin rows.

Tuning constants read: `disconnect_grace_seconds` 30 (**placeholder** — "long
enough for a reconnect, short enough that the ring is not broken for a quarter of
the round"; replace with observed reconnect times once telemetry exists, which is
`TEL-002`) and `min_players_to_continue` 3 (**derived**). None introduced or
changed.

The design position the criteria protect, stated plainly so nobody softens it:
**a dropout should hurt.** The key transfer keeps the round solvable; the lost lens
keeps it costly. An implementation that also hands on the lens would make losing a
player a net simplification, which would make the most frustrating thing that can
happen to a group into a strategy.

Edge case named in `roles.md` §6 and deferred: a round continuing at `n = 3` is
"a degraded round, not a different game, and the trace should say so rather than
record it as a clean result". The trace is M3.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Transfer the key class to `σ(q)` — the dependent — instead of `σ⁻¹(q)`.
   Predicted: AC-1 goes red alone. **Run this first**; it is the invisible error.
2. Compute the supplier from the original snapshot rather than the current ring.
   Predicted: AC-7 goes red, AC-1 stays green.
3. Change the grace comparison from `>=` to `>`. Predicted: AC-6's
   exactly-at-the-boundary assertion goes red alone.

**Raise the `unit` floor** to the new real count.
