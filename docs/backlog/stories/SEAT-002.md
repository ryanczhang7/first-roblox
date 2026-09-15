---
id: SEAT-002
title: A replicated seat view contains nothing of anyone else's
slug: a-replicated-seat-view-contains-nothing
epic: EPIC-02
type: feature
status: todo
phase: PLANNED
branch: story/SEAT-002-a-replicated-seat-view-contains-nothing
depends_on: [SEAT-001]
required_gates: []
---

## Context

`roles.md` §6 states the single most important trust-boundary property in the
game: *"a client that can read another player's lens is not cheating at a
scoreboard, it has deleted the game."* The whole puzzle is that information is
split. B4 says the same thing generally — a hidden value must not exist in any
client's replicated state.

Roblox clients are fully hostile and can read any value replicated to them, so
"the UI does not display it" is worth nothing. The only mechanism that works is
never sending it.

This story builds the projection that decides what a client receives, and it makes
one architectural commitment (`architecture.md` §4, D8): **the projection is an
allowlist, built field by field. It is never a copy of server state with private
fields removed.**

The two failure modes are not symmetric. A denylist that forgets a field leaks the
round, silently, to an exploiter who is looking. An allowlist that forgets a field
produces a visibly missing feature within a minute of anyone playing. The
architecture picks the one that fails loudly.

Right now the only private thing is `σ` and the other players' key classes. That is
exactly why this is the cheap moment to make it structural: M3 adds lens pairings
and order fragments to an allowlist that already exists, rather than inventing a
replication path while holding the game's secrets.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given an assignment for `n` players, when `Projection.forPlayer` is
  called for player `p`, then the result contains `p`'s own key class, `p`'s own
  lens key class, the identity of `p`'s supplier and dependent, the seat order, and
  nothing else.
- **AC-2** — Given an assignment, when the projection for `p` is serialised to a
  flat set of scalar values, then **no other player's key class** appears anywhere
  in it.
  *Control:* a projection implemented as "copy the assignment, remove `sigma`"
  passes a test that checks for a `sigma` key and **must** fail this — `keyClass`
  is a table of everyone's classes and a removal-based projection keeps it. Write
  the control as that exact implementation.
- **AC-3** — Given the full set of fields in the private `Assignment` record, when
  each is checked against the projection's declared output type, then every field
  is either **in the allowlist** or provably absent from the projection for every
  player.
  *Control:* adding a new private field to `Assignment` and not to the allowlist
  **must** leave the projection unchanged — this is the property that makes M3's
  additions safe by default. Demonstrate it by adding a field in the test.
- **AC-4** — Given the projection function, when its implementation is examined by
  the guard, then it constructs its result literally, field by field, and does not
  call any generic table-copy, `table.clone`, deep-copy or serialise-then-delete
  helper on the assignment.
  *Semantics:* this is a structural rule, not a style rule. Every leak this section
  exists to prevent arrives through a copy. If a guard over the source is judged
  too brittle, say so in RED and amend this block — but the property must be
  asserted somewhere, because AC-2 and AC-3 can both be satisfied today by a copy
  that happens to be correct today.
- **AC-5** — Given a player not in the assignment, when a projection is requested
  for them, then it fails rather than returning an empty or partial view.
  *Semantics:* an empty view is indistinguishable from a legitimate view of a
  player with nothing, and a spectator quietly receiving `{}` is a bug that hides.
- **AC-6** — Given an assignment and any two distinct players `p` and `q`, when
  both projections are taken, then neither contains a value that would let a reader
  compute the other's lens: specifically, `p`'s view does not contain
  `keyClass[q]` for any `q ≠ p`, and does not contain `sigma` in any form.

## Contract

### `src/server/seats/Projection.luau`

    export type PublicSeatView = {
        playerId:    PlayerId,
        keyClass:    KeyClass,        -- this player's own
        lensClass:   KeyClass,        -- this player's own lens = keyClass of their dependent
        supplierId:  PlayerId,        -- who sends to me
        dependentId: PlayerId,        -- who I send to
        seatOrder:   { PlayerId },    -- public: everyone knows who is in the round
    }

    Projection.forPlayer(assignment: Assignment, playerId: PlayerId) -> PublicSeatView

**The allowlist is the type.** Every field in `PublicSeatView` is written into the
result by name. There is no path from `Assignment` to `PublicSeatView` that does
not pass through an explicit assignment statement.

### Why `lensClass` is safe to send and `sigma` is not

`lensClass` tells `p` which class of actuator `p` can read the required values of.
`p` will see those values anyway, by pointing their light at the panels — that is
`mechanics.md` §2. What must never be sent is **anyone else's** mapping, because
the whole difficulty is that `p` does not know what the others can see
(`mechanics.md` §4.5: "you are choosing under three ignorances").

`supplierId` and `dependentId` are safe and necessary: `roles.md` §3 makes "get
your dependent right" and "get yourself told" the player's local obligations, and
they cannot act on either without knowing who those two people are.

### What M3 will add, and where

When the instance generator lands, `PublicSeatView` gains `pairings` (this player's
lens contents) and `fragments` (this player's order fragments). Both are per-player
secrets and both go in the allowlist by name. Nothing else about this module
changes. That is the whole point of doing it now.

### Test-only dependencies

None.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-5, AC-6 | **Settled** | `roles.md` §3 and §6 decide what a player knows. Read it out; do not decide what "seems safe" to send. |
| AC-2, AC-3 | **Mechanical, with controls** | The controls are the two wrong implementations that would otherwise ship. Write the copy-and-remove one literally. |
| AC-4 | **Oracle-free** | You are inventing the structural guard, and it is allowed to be amended if it proves unworkable — but the property must be asserted somewhere. Say in the handoff what you asserted and what it cannot catch. |

## Deferred verifications

### A future private field must not leak

**Condition:** with a new private field added to `Assignment` — the shape M3 will
actually add, a per-player table of secrets — every `PublicSeatView` **must** be
byte-identical to what it was before the field existed.

**Why RED can run part of it and not all:** AC-3 covers the synthetic version. What
cannot be run now is the real one, because the real field is the lens pairings and
the generator does not exist.

**Owner: GATES.** Do three mutations, and make one of them a **wrong value**
rather than a missing field: add a private field and check nothing leaks; remove a
field from the allowlist and check a consumer visibly breaks rather than silently
receiving `nil`; and set one player's `keyClass` to another player's value and
confirm the projection for the *other* player is unchanged. A suite that catches an
omission can be blind to a corruption.

**Result:** _(paste: what was mutated, what went red, that the file was restored)_

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

Put `roles.md` §6's sentence in the dispatch verbatim — "a client that can read
another player's lens is not cheating at a scoreboard, it has deleted the game" —
because the natural instinct on a story this small is to test that the function
returns the right fields, and the criterion that matters is that it returns
**nothing else**.

**Success condition:** the AC-2 control — the copy-and-remove-`sigma`
implementation — is demonstrated passing a naive field-presence test and failing
AC-2. If it fails both, the naive test was not naive enough and the control proves
nothing.

## Out of scope

- Actually replicating anything. There is no RemoteEvent here and no client. The
  `ReplicateSeat` effect from `ROUND-003` carries a `PublicSeatView`; nothing
  performs it yet. The half that can leak is the half that decides what to send, and
  that is what this story tests.
- Lens contents and order fragments. M3, added to the allowlist by name.
- Encryption or obfuscation of replicated data. Pointless against a hostile client;
  the answer is not sending it.
- Anti-exploit detection or reporting. `TEL-003` counts rejected calls; reading an
  over-replicated value produces no call to count, which is exactly why this has to
  be structural.

## Game design

Implements `roles.md` §6's replication rule and `mechanics.md` §2's lens rule
("the required value is never replicated to a client that does not hold the lens…
a client that is not the lens-holder must not be able to read it out of its own
memory").

No tuning constant is introduced or changed.

The decision this story protects is the design's foundation: `mechanics.md` §4.5
says the player is choosing "under three ignorances — what others can see, what
they have already inferred, and what the order layer will require". The first of
those three is a property of the replication boundary and nothing else. Lose it and
`loop.md` §1.2's decision — *which single fact is the one the group cannot deduce
without me* — has an answer printed on the client.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Replace the literal construction with `table.clone(assignment)` followed by
   `view.sigma = nil`. Predicted: AC-2 and AC-4 go red; AC-1 stays green. **Run
   this one first.**
2. Change `lensClass` to be read from the supplier instead of the dependent.
   Predicted: AC-1 goes red. If it stays green, AC-1 is asserting field presence
   rather than field value.
3. Return `{}` for an unknown player instead of failing. Predicted: AC-5 goes red
   alone.

**Raise the `unit` floor** to the new real count.
