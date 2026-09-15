---
id: SEAT-001
title: Seats are dealt as a seeded single-cycle derangement
slug: seats-are-dealt-as-a-seeded-single-cycle
epic: EPIC-02
type: feature
status: todo
phase: PLANNED
branch: story/SEAT-001-seats-are-dealt-as-a-seeded-single-cycle
depends_on: [ROUND-001, ROUND-002]
required_gates: []
---

## Context

This is the mechanism the whole co-operative design rests on. `roles.md` §1: three
things must be true at once — nobody can act alone, nobody is redundant, nobody can
be replaced by a spokesperson — and **one** mechanism produces all three: a cyclic
derangement of lens and key.

Each player `p` holds a **key** `k(p)`, the class of actuators only `p` may
operate, and a **lens** `λ(p) = k(σ(p))`, the class whose required values only `p`
can read. Two constraints on `σ`:

- **no fixed point** — you cannot act on what you can see;
- **a single n-cycle, not two 2-cycles** — four players are one ring, not two
  independent pairs sharing a map.

`roles.md` §2 is blunt about why the second one is separate: a derangement of four
players *could* be two disjoint swaps, which would produce two two-player games
that never need each other. That is a one-line generator constraint and a
completely different game if it is missed.

It is one line of generation logic, needs no art, and is exactly checkable by a
test. This story is that line and that test.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `n` seated players for every `n` in 3, 4, 5, 6, when seats are
  assigned, then `σ` is a permutation of the seated players with **no fixed
  point**: `σ(p) ≠ p` for every `p`.
- **AC-2** — Given the same, when the orbit of any player under repeated
  application of `σ` is followed, then it visits all `n` players before returning
  to the start — `σ` is a **single cycle**, not two or more.
  *Control:* a generator that produces a random derangement without the cycle
  constraint passes AC-1 and **must** fail this at `n = 4`, where two disjoint
  2-cycles are 3 of the 9 derangements. Assert this over enough seeds that the
  control cannot pass by luck — at `n = 4` a single sample would miss it two times
  in three.
- **AC-3** — Given the same seed and the same seated list, when seats are assigned
  twice, then the two assignments are identical; and given different seeds, at
  least two different rings appear over a sample of seeds.
  *Control:* a generator that ignores its seed passes the first half and **must**
  fail the second.
- **AC-4** — Given `n` seated players, when seats are assigned, then each player
  holds exactly one key class, the key classes are the integers `1..n` each used
  once, and `λ(p) = k(σ(p))` holds for every player.
- **AC-5** — Given 10,000 seeds at `n = 4`, when the rings produced are tallied,
  then **all six** cyclic derangements of four elements appear, and none accounts
  for more than 25% or fewer than 8% of the sample.
  *Control:* a generator that always returns the canonical cycle
  `p1 → p2 → p3 → p4 → p1` satisfies AC-1, AC-2 and the first half of AC-3, and
  **must** fail this — scoring 100% on one ring and 0% on five. `roles.md` §2
  requires the ring's shape to be variance in itself, so "you do not develop a
  fixed relationship with one person"; a constant generator would quietly remove
  that.
  *Note on the bounds:* uniform is 16.7%; 8–25% is roughly ±50% of uniform, wide
  enough that sampling noise at n = 10,000 cannot fire it and tight enough that a
  generator biased toward one ring will.
- **AC-6** — Given fewer than 3 seated players, when seats are assigned, then it
  fails rather than returning a degenerate ring.
  *Semantics:* `min_players_to_continue` is 3 (`tuning.md` §1, derived: "below 3
  there is no derangement worth the name"). At `n = 2` the only derangement is a
  swap, which is two players each seeing the other's values — not a ring.
- **AC-7** — Given a seated list, when seats are assigned, then the input list is
  not mutated and the seat order in the result matches the input order.

## Contract

### `src/server/seats/Ring.luau`

    export type KeyClass = number          -- 1..n, one per seated player

    export type Assignment = {
        players: { PlayerId },                     -- seat order, as seated
        sigma:   { [PlayerId]: PlayerId },         -- σ: p -> the player whose key class p can read
        keyClass:{ [PlayerId]: KeyClass },
    }

    Ring.assign(players: { PlayerId }, rng: Rng) -> Assignment
    Ring.lensOf(assignment: Assignment, playerId: PlayerId) -> KeyClass
    Ring.supplierOf(assignment: Assignment, playerId: PlayerId) -> PlayerId   -- σ⁻¹(p)
    Ring.dependentOf(assignment: Assignment, playerId: PlayerId) -> PlayerId  -- σ(p)

### The semantics, stated so a sign error is a one-line fix

- `σ(p)` is `p`'s **dependent**: the ring-successor, the one player whose actuators
  only `p` can see. `p` sends facts *to* `σ(p)`.
- `σ⁻¹(p)` is `p`'s **supplier**: the ring-predecessor, the one player who can see
  what `p`'s actuators need. `p` receives facts *from* `σ⁻¹(p)`.
- `λ(p) = k(σ(p))` — `p`'s lens covers `p`'s dependent's key class.
- The ring for four players reads
  `P1 → sees the values for → P2 → P3 → P4 → P1`.

Getting this backwards produces a game that still "works" — every player still has
someone to talk to — and is wrong in a way no structural test catches. AC-4 pins
it, and `SEAT-003`'s key transfer depends on it: the leaver's key goes to their
**supplier**, the player who could already see those values.

### Generating a single cycle

The standard construction: shuffle the players into a random order, then map each
to the next, wrapping the last to the first. Every single cycle is produced exactly
once by `(n−1)!` of the `n!` shuffles, which is what makes AC-5's distribution
uniform if `Rng:shuffle` is unbiased. Use `rng:derive("seats")` — the sub-stream
from `ROUND-001` — so that the M3 instance generator can later draw from
`derive("instance")` without shifting any of this.

### Test-only dependencies

None.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-4, AC-6, AC-7 | **Settled** | `roles.md` §2 and §6 and `tuning.md` §1 fix all of this. Read the properties out; do not invent a seating scheme. |
| AC-3 | **Mechanical, with a control** | |
| AC-5 | **Oracle-free — the statistical one** | The 8–25% band and the 10,000-seed sample are specified above with their reasoning. Implement them as written, and implement the constant-generator control literally: it is the one wrong implementation that passes every structural criterion in this story. If you believe the band or the sample size is wrong, say so before changing it — a widened tolerance is a weakening (`rules.md`). |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None. The AC-2 and AC-5 controls are both hand-writable stubs — a plain derangement generator and a constant generator — and neither needs the real implementation.
-->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

Two things to put in the dispatch verbatim:

1. **AC-5 is the criterion that catches the implementation which passes everything
   else.** A constant ring satisfies no-fixed-point, single-cycle and seed
   reproducibility. Without AC-5, this story could ship a generator with no variance
   at all and the suite would be green.
2. **AC-2's control needs enough samples.** At `n = 4` two-thirds of derangements
   are single cycles, so a plain-derangement generator passes a one-seed test with
   probability 2/3. State the sample size in the test and say why.

**Success condition:** both controls demonstrated failing in the handoff, with the
measured numbers — not described.

## Out of scope

- **Lens contents.** `Assignment` carries `σ` and key classes. The *pairings* a
  lens shows — `(tag → required value)` — come from the instance generator
  (`mechanics.md` §6) and are M3.
- **Replication.** `SEAT-002`. Nothing here is sent anywhere.
- **Disconnect and rejoin.** `SEAT-003`.
- **Order fragments.** The global layer (`mechanics.md` §3.2) is M3.
- **`actuators_per_class`, `pairs_per_lens` and the rest of `tuning.md` §2.** M3,
  with the generator.
- **k-essentiality (`INV_k_essential`).** It is a property of the *instance*, not of
  the ring, and it is brute-forced against the generated lens contents. M3.

## Game design

Implements `roles.md` §2 in full and `mechanics.md` §6.2 invariant 3
(`INV_cyclic_sigma`).

Tuning constants read: `players_min` 4, `players_max` 6, `min_players_to_continue`
3 — all **derived**, all from `ROUND-002`'s module. `key_classes` is specified as
"one per player" (`tuning.md` §2, derived), which is what AC-4 pins. No constant is
introduced or changed by this story.

The decisions the criteria protect:

| AC | Decision |
|---|---|
| AC-1 | "You cannot act on what you can see." Without it a player is self-sufficient for their own actuators and k-essentiality fails (`mechanics.md` §2). |
| AC-2 | One ring, not two pairs. Two 2-cycles is two independent two-player games sharing a map. |
| AC-5 | "There are six possible cyclic derangements of four players and the generator picks one per round, so the ring's shape is itself variance — you do not develop a fixed relationship with one person" (`roles.md` §2). |
| AC-6 | A 3-cycle is still a ring; a 2-swap is not. |

Edge case named and deferred: at `n = 3` after a dropout the ring is playable but
"structurally thinner — a degraded round, not a different game", and the trace
should say so. The trace is M3; `ROUND-005` records the same deferral.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Replace the single-cycle construction with a rejection-sampled plain
   derangement. Predicted: AC-2 goes red; AC-1, AC-3, AC-4, AC-5 stay green.
2. Return a constant canonical ring, ignoring the Rng. Predicted: AC-5 goes red and
   AC-3's second half goes red; AC-1, AC-2, AC-4 stay green. **This is the mutation
   to run first** — it is the one a naive suite is blind to.
3. Swap `supplierOf` and `dependentOf`. Predicted: AC-4's `λ(p) = k(σ(p))`
   assertion goes red. If it stays green, AC-4 is not actually pinning the
   direction, and `SEAT-003` will inherit the error.

**Raise the `unit` floor** to the new real count.
