---
id: SEAT-002
title: A replicated seat view contains nothing of anyone else's
slug: a-replicated-seat-view-contains-nothing
epic: EPIC-02
type: feature
status: in-progress
phase: RED
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
  `keyClass[q]` for any `q ∉ {p, σ(p)}`, and does not contain `sigma` in any form.
  *Amended after the story left PLANNED — see `## Amendments`, A-1. The original
  read `q ≠ p`, which AC-1 contradicts.*

## Amendments

### A-1 — AC-6: `q ≠ p` becomes `q ∉ {p, σ(p)}`

**Raised by:** the test-developer, in RED, as escalation 2.

**What it said:**

> `p`'s view does not contain `keyClass[q]` for any `q ≠ p`, and does not contain
> `sigma` in any form.

**What it says now:**

> `p`'s view does not contain `keyClass[q]` for any `q ∉ {p, σ(p)}`, and does not
> contain `sigma` in any form.

**Why.** AC-6 as written contradicted AC-1. AC-1 requires the view to carry `p`'s
own lens class; the Contract defines that as `keyClass` of `p`'s dependent, and
`Ring.lensOf` computes exactly `assignment.keyClass[assignment.sigma[p]]`. `σ` is
a derangement, so `σ(p) ≠ p` always — which makes `lensClass` *always* a
`keyClass[q]` for some `q ≠ p`. No implementation could satisfy both criteria.

AC-6's own opening clause is the intent and it is unharmed: the excluded value is
`p`'s **own lens**, which by construction tells `p` nothing about anyone else's
lens. `σ(p)`'s lens is `keyClass[σ(σ(p))]`, which is not derivable from it. And
`roles.md` §3 puts actuator key classes in the **public** column — "shared with
anyone in the room" — so the amended clause does not widen what is replicated; it
stops forbidding something the design already publishes.

**Independently reproduced by the orchestrator** before accepting the claim, on
fresh fixtures and without reusing any test the subagent wrote — different names
(`alder`…`larch`), different sizes (n = 3, 4, 5, 6) and different seeds (7,
31337, 90210, 424242), driving `Ring` directly:

    --- n = 5, seed = 90210 ---
      alder: own keyClass=1  sigma(p)=hazel  lensClass=5  == keyClass[hazel]=5  -> lensClass IS another player's keyClass: true
      birch: own keyClass=2  sigma(p)=cedar  lensClass=3  == keyClass[cedar]=3  -> lensClass IS another player's keyClass: true
      cedar: own keyClass=3  sigma(p)=alder  lensClass=1  == keyClass[alder]=1  -> lensClass IS another player's keyClass: true
      elder: own keyClass=4  sigma(p)=birch  lensClass=2  == keyClass[birch]=2  -> lensClass IS another player's keyClass: true
      hazel: own keyClass=5  sigma(p)=elder  lensClass=4  == keyClass[elder]=4  -> lensClass IS another player's keyClass: true

    Counted over all four rings above:
      18 of 18 players have lensClass == keyClass[q] for some q ~= p

**Approved by:** the product owner (the user), 2026-09-18, presented with this
reproduction and with the two alternatives — dropping the specific clause for the
intent alone, and removing `lensClass` from AC-1 instead. The narrowest option was
chosen: it keeps AC-6 sharply testable, and removing `lensClass` was rejected on
the design, since `mechanics.md` §2 has the player seeing those values anyway by
pointing their light at the panels.

**Effect on RED:** none. RED had already implemented the amended reading as "the
only consistent one" and said so rather than quietly widening the test. That is
the escalation working.

## PO decisions taken during RED

### PO-7 — `seatOrder`'s loop is a `table.insert` loop, sharpening PO-2

PO-2 pinned `seatOrder` to an explicit loop so AC-4's guard could be a flat ban on
copy helpers. RED found that the obvious way to write that loop makes the required
`lint` gate fail, and the finding lands against a mechanism the orchestrator named
— exactly the kind of instruction the brief told RED to treat as checkable.

**Reproduced by the orchestrator**, with its own two-function probe under
`build/` and `selene 0.31.0`:

    warning[manual_table_clone]: manual implementation of table.clone
      ┌─ build/lintprobe.luau:4:2
    4 │ ╭     local out = {}
    5 │ │     for i, id in players do
    6 │ │         out[i] = id
    7 │ │     end
      │ ╰───────^
      = try `local out = table.clone(players)`

    Results: 0 errors, 1 warnings

The same probe's `table.insert` variant draws nothing. So the indexed form
(`out[i] = id`) trips `manual_table_clone` and the `table.insert` form does not,
and `selene` exits 1 on a warning — the gate fails.

Worth stating plainly, because it is the whole reason PO-2 exists: **the linter's
suggested fix is `table.clone(players)`, which is the one construct AC-4 forbids.**
A developer following the tool's advice writes the leak this story is about.

**Decision:** `seatOrder` is built with a `table.insert` loop. GREEN takes that
form. A `-- selene: allow(manual_table_clone)` would also pass the gate and is
**not** taken: it puts an override in the file next to the exact call shape AC-4
is trying to keep out, and the next reader has to reconstruct why it is there.

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

### Where the types come from, and how the module is required (PO-1)

`.luaurc` declares exactly one alias, `shared`. There is no `@server`. Siblings are
required relatively — `src/server/round/PhaseMachine.luau:118` is
`require("./RoundConfig")`. So:

    local Ring = require("./Ring")

`PublicSeatView` does **not** redeclare `PlayerId` or `KeyClass`. It uses
`Ring.PlayerId` and `Ring.KeyClass`, and `forPlayer` takes `Ring.Assignment`. A
second declaration of `PlayerId` in this repository is a second answer to the same
question, and `rules.md` is about nothing else.

The ring relations are read through `Ring.supplierOf`, `Ring.dependentOf` and
`Ring.lensOf` — never reimplemented here. `Ring.luau`'s own header says the
direction is the one error the structure cannot catch: a backwards ring still has
no fixed point and still has one orbit. A private `σ⁻¹` in this module would be a
second copy of that direction, free to disagree with the first.

### `seatOrder` is built by an explicit loop, not a clone (PO-2)

This is the block that decides whether AC-4 is assertable at all, so it is pinned
rather than left to taste.

AC-4's guard is worth having only if it can be a **flat ban** on copy helpers
inside `Projection.luau`. That works only if the module has no legitimate use of
one — and there is exactly one place tempted. `Ring.assign` already clones
`players` into the assignment, so handing that same table out would let a consumer
mutate an assignment that was already dealt. Two one-line fixes, identical in
behaviour:

    seatOrder = table.clone(assignment.players)              -- safe, and unguardable
    for _, id in assignment.players do ... end               -- safe, and guardable

Take the second. The guard then bans `table.clone`, `table.move`, `table.pack`,
`table.unpack`, `table.freeze`-style wholesale copies and any `Deep.copy` helper
**anywhere in `Projection.luau`**, with no argument analysis at all. A guard that
has to parse a call's argument to decide whether that call is allowed is a guard
that fails open on the first argument it cannot parse.

### AC-5 is Projection's own refusal, raised before any `Ring` call (PO-3)

`Ring.supplierOf` already raises for an unseated player — *"is that player
seated?"*. If `forPlayer` reaches it, AC-5 passes **for the wrong reason**: the
message names the wrong module, and the refusal is a side effect of a helper
rather than a decision this function made.

So `forPlayer` checks membership of `assignment.players` **first** and raises its
own error, at level 2, naming the module and the player. The test asserts the
message, not merely that something was raised. Otherwise the only mutation AC-5
discriminates is `## Notes` mutation 3, and a refusal that quietly relocated into
`Ring` would still read green.

### AC-4's file list is the harness's, and the guard asserts its own subject is in it (PO-4)

`tests/helpers/SourceScan.luau` already has every piece: `sourceFilesIn(pathspec)`
shells out to `scripts/classify.sh --list`, and `hitsIn` matches symbols on word
boundaries over code with comments and string literals blanked. Use it. Do not
write a glob, a directory walk or a path regex; `rules.md` says why and this
repository has already paid for that lesson once.

Two vacuity requirements, because a guard over an empty list passes:

- assert `src/server/seats/Projection.luau` is **present** in
  `SourceScan.sourceFilesIn("src/server/seats")` before scanning it;
- scan **that path only**. `Ring.luau` uses `table.clone` legitimately
  (`players = table.clone(players)`), so a guard over the whole subtree fails on
  day one against correct code — and the way that gets fixed is by deleting the
  guard.

### AC-2's flattening is the assertion, so it is the thing to get sharp (PO-5)

"Serialised to a flat set of scalar values" must walk the view **recursively** —
every nested table, every key and every value. `seatOrder` is a table, so a
flattener that reads only top-level values already misses the single nested field
the view has. Check `tests/helpers/Deep.luau` before writing a second one.

The known false-negative, stated now rather than discovered: key classes are small
integers `1..n`, and `p`'s own `keyClass` and `lensClass` are two of them. "No
integer belonging to `keyClass[q≠p]` appears anywhere" collides with `p`'s own
legitimate values. Pick the discrimination deliberately, say in the handoff which
you picked and what it cannot catch — and let the AC-2 control be what decides
whether it was sharp enough.

### The AC-2 control is an implementation, not a description of one (PO-6)

Write the copy-and-remove-`sigma` projection as a real function in the test file,
with the same signature as `Projection.forPlayer`, and run **both** tests against
it: the naive field-presence test, which it must **pass**, and AC-2, which it must
**fail**. Both halves are required. If it fails the naive test too, the naive test
was not naive enough and the control proves nothing — sharpen the naive test and
say so, rather than reporting the control green.

### Test-only dependencies

None.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-5, AC-6 | **Settled** | `roles.md` §3 and §6 decide what a player knows. Read it out; do not decide what "seems safe" to send. |
| AC-2, AC-3 | **Mechanical, with controls** | The controls are the two wrong implementations that would otherwise ship. Write the copy-and-remove one literally. |
| AC-4 | **Oracle-free** | You are inventing the structural guard, and it is allowed to be amended if it proves unworkable — but the property must be asserted somewhere. Say in the handoff what you asserted and what it cannot catch. |

## Callers of changed signatures

Scanned by the orchestrator **before dispatch**, against the tree at `29d0259`:

    rg -n "Ring\.|require.*seats" src tests lune --glob '!*Ring.luau'

Every hit is under `tests/` — `ring_test.luau`, `ring_controls_test.luau`,
`RingContract.luau`, `RingStubs.luau`. **No production module requires `Ring`
today.** `Projection.luau` is its first consumer.

So **this story changes no existing export's signature.** It adds one module and
touches nothing in `Ring.luau`. The list of callers to update is empty, and it is
empty for a checkable reason rather than because nobody looked.

Why this is the orchestrator's job and not RED's: during RED the old signature
still exists, so its callers still compile and never appear in RED's typecheck. A
missed file once compiled happily through a 221-error RED and turned 25 tests into
silent skips the moment GREEN deleted the old signature.

**RED's handoff must state that this list was re-checked against the tree at the
end of RED.** If RED finds itself wanting to change a `Ring` export, that is a
contract amendment and an escalation — not a quiet edit.

## Orchestrator checks at PLANNED

**Gate coverage.** `bash scripts/gates.sh --list` was read against this story's
artifact, `src/server/seats/Projection.luau`:

- `unit` — **required**, `covers: src/server/**`. This is the gate named in
  `## Context` and it genuinely reads the artifact.
- `lint`, `typecheck`, `build` — all **required**, all `covers: src/**`.

Nothing about this story's artifact is reachable only by an optional gate, so
`required_gates` stays empty. The failure this check exists to prevent — a
renderer whose every test ran where nothing could block on it, under a printed
`All required gates passed` — does not apply here.

`unit`'s floor is **197** today. Raising it to the new real count is a
`project.conf` edit, which belongs to the Lead PO at GATES, once that count
exists. Noted here so it is not discovered as a surprise.

**Epic done-when.** `EPIC-02` carries one clause for this story: *"For every player
`p`, nothing private to any other player appears anywhere in
`Projection.forPlayer(assignment, p)`."* AC-2 and AC-6 assert exactly that. The
clause for the preceding story — `Ring.assign` produces a permutation with no
fixed point and exactly one orbit for every seated count 3 to 6 — is delivered by
SEAT-001, DONE and merged in PR #10.

**No gap between SEAT-001 and SEAT-002 for the orchestrator to close.** No numbered
PO decision is needed on the epic's behalf.

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

**Plan, from `.claude/harness/models.conf`** (`bash scripts/plan.sh SEAT-002`):

| Phase | Agent | Planned |
|---|---|---|
| PLANNED | lead-po | opus |
| RED | test-developer | **fable** — the measured case: with a partitioned contract to work from, the brief carries the judgement |
| GREEN | feature-developer | opus |
| GATES | feature-developer | opus |
| REVIEW | lead-po | opus |

RED takes the weaker model here because the precondition the measurement depends
on is met: `## Contract` carries an oracle partition **and** six pinned PO blocks,
so the judgement is in the brief rather than in the model.

**Resolved model of every dispatch, by name:**

- PLANNED — lead-po — **claude-opus-5** (this session).
- RED — test-developer — **fable**, passed as an explicit per-dispatch override,
  because the agent definition's own `model:` field says `opus` and would
  otherwise win. Recorded by name because neither `models.conf` nor the agent file
  can see which one did.


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

## Test plan

Two test files and two helpers, in the split SEAT-001 established: the checks
live in a contract helper, one file applies them to the real module (red until
GREEN), and one file applies them to deliberately wrong projections that need
only the merged `Ring` (green in RED, and the place every check is *observed*
to fire).

| AC | Test (file :: name) | Check | Observed firing on |
|---|---|---|---|
| AC-1 | `projection_test` :: *AC-1: the view for p is exactly p's own keyClass, own lensClass, supplierId, dependentId, playerId and a fresh seatOrder - and nothing else* | `ProjectionContract.viewIsExactlyTheAllowlist` — `Deep.diff` against an expected view read off the assignment's own `sigma`/`keyClass`, over 144 (n, seed, p) cases, plus PO-2's identity pin on `seatOrder` | `lensFromSupplier`, `aliasSeatOrder`, `seatOrderFromRing`, `leakSupplierClass`, `swapNeighbours` (AC-1 alone), the copy control |
| AC-2 | `projection_test` :: *AC-2: flattened to scalars at every depth, the view carries exactly two integers and neither is another player's key class* | `noForeignKeyClassAppears` — recursive flatten (PO-5); integer-typed leaves only; no `keyClass[q]` for q ∉ {p, σ(p)}; exactly 2 integer leaves | `copyAndRemoveSigma` (both halves, PO-6), `lensFromSupplier`, `leakSupplierClass` |
| AC-3 | `projection_test` :: *AC-3: every field of the private Assignment is allowlisted or absent, and adding a new private field leaves every view unchanged* | `privateFieldsAreAllowlistedOrAbsent` — walks the assignment's own keys (by name and by reference); then adds `pairings`, the M3 shape, with sentinels, and re-takes 32 views at n = 4 | `copyAndRemoveSigma`, `aliasSeatOrder` (by reference) |
| AC-4 | `projection_test` :: three tests: *the harness's source list … contains Projection.luau*; *builds its result field by field - no table.clone … anywhere in it*; *the only module Projection.luau requires is ./Ring* | `SourceScan.sourceFilesIn("src/server/seats")` + presence assertion (PO-4); `SourceScan.scanFor({Projection.luau}, BANNED)` over that path only; `require` count == count of `require("./Ring")` | `projection_controls_test` :: the three *AC-4 control* tests — every banned symbol fires as code; quiet in comments, strings, look-alikes and PO-2's loop; `Ring.luau:136` found on disk through the classifier |
| AC-5 | `projection_test` :: *AC-5: a player not in the assignment is refused by Projection itself - the error names the module and the player, is not Ring's, and blames the caller* | `unknownPlayerIsRefusedByProjectionItself` — three strangers (`"sam"`, `"KIM"`, `nil`); must raise; message names `Projection` and the player; does not begin `Ring.`; location is not `seats/Projection` (level 2, PO-3); every seated player still succeeds | `emptyForUnknown` (AC-5 alone), `refuseViaRing` (AC-5 alone) |
| AC-6 | `projection_test` :: *AC-6: for every pair of players, neither view carries the other's key class or σ in any form - as a map, a string, or the ring order* | `pairwiseViewsRevealNothingOfEachOther` — pairwise foreign-class check; no string-keyed table below the root; every string leaf is a seated id; `seatOrder` is not a rotation of the ring order, in the 123 of 144 cases where the seat order is not one (vacuity floor: ≥ 100) | `seatOrderFromRing`, `lensFromSupplier`, `leakSupplierClass` |
| PO-6 | `projection_test` :: *naive: the view has no sigma key and has a keyClass key* | `naiveFieldPresence` | **passes** on `copyAndRemoveSigma` — the required first half |
| PO-5 | `projection_controls_test` :: *PO-5 control: the flattener reaches a value three tables down …* | `flatten` returns `view.a.b.c = 7`, array leaves, and 6 key leaves separately | — |
| Contract | `projection_test` :: *Contract: Projection exports forPlayer as a plain field function …* | `typeof(Projection.forPlayer) == "function"` | — |

Every check accumulates its violations and asserts once (`tdd-cycle`), and every
failure message names its criterion and the path each leak was found at.

## Handoff: RED -> GREEN

**Dispatch.** RED ran on **claude-fable-5-1** (`fable`), passed as an explicit
per-dispatch override of the agent file's `model: opus`, as `## Model guidance`
records.

### Files written

| File | What it is |
|---|---|
| `tests/helpers/ProjectionContract.luau` | AC-1, AC-2, AC-3, AC-5, AC-6 and the naive check as functions over any `projection` with `forPlayer`; the recursive flattener (PO-5); the expected-view oracle read off the assignment's raw `sigma`/`keyClass` |
| `tests/helpers/ProjectionStubs.luau` | a factory over one-field defect tables: the baseline and eight wrong projections, over the real merged `Ring` |
| `tests/server/projection_test.luau` | the ten tests against the real `src/server/seats/Projection.luau`, including the three AC-4 source-guard tests. **All red.** |
| `tests/server/projection_controls_test.luau` | fourteen control tests. **All green in RED**, because they need only `Ring`. |
| `.claude/tests/project-counters.test.sh` | `BASE_FORMAT`/`BASE_LINT` 43 → 47 and the matching labels, per that file's own header. See `## Regressions`. |
| `docs/backlog/stories/SEAT-002.md` | this section, `## Test plan`, `## Regressions` |

No production file was written. No dependency was added.

### The command, and the verbatim failure

    lune run test

Ten failures, all in `projection_test.luau`; every other file green, controls
included:

      FAIL  tests/server/projection_test.luau :: AC-1: the view for p is exactly p's own keyClass, own lensClass, supplierId, dependentId, playerId and a fresh seatOrder - and nothing else
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: AC-2: flattened to scalars at every depth, the view carries exactly two integers and neither is another player's key class
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: AC-3: every field of the private Assignment is allowlisted or absent, and adding a new private field leaves every view unchanged
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: AC-4: Projection.luau builds its result field by field - no table.clone, table.move, table.pack, table.unpack, table.freeze, Deep.copy, pairs, next or setmetatable anywhere in it
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:127: this assertion would pass over the 1 file(s) the classifier returned for src/server/seats, and src/server/seats/Projection.luau is not among them: src/server/seats/Ring.luau
      FAIL  tests/server/projection_test.luau :: AC-4: the harness's source list for src/server/seats contains Projection.luau, so the guard has a subject
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:115: src/server/seats/Projection.luau is not in the scanned set; a guard over nothing passes. classify.sh --list source src/server/seats said: src/server/seats/Ring.luau
      FAIL  tests/server/projection_test.luau :: AC-4: the only module Projection.luau requires is ./Ring, so no copy helper arrives under another name
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:147: this assertion would pass over the 1 file(s) the classifier returned for src/server/seats, and src/server/seats/Projection.luau is not among them: src/server/seats/Ring.luau
      FAIL  tests/server/projection_test.luau :: AC-5: a player not in the assignment is refused by Projection itself - the error names the module and the player, is not Ring's, and blames the caller
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: AC-6: for every pair of players, neither view carries the other's key class or σ in any form - as a map, a string, or the ring order
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: Contract: Projection exports forPlayer as a plain field function and nothing else the Contract does not name
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
      FAIL  tests/server/projection_test.luau :: naive: the view has no sigma key and has a keyClass key
            C:\Users\ryanc\Projects\first-roblox\tests\server\projection_test:42: src/server/seats/Projection.luau did not load: error requiring module "../../src/server/seats/Projection": could not resolve child component "Projection"
    211 passed, 10 failed

**Why this is the right failure.** Seven tests fail at the `pcall`'d require —
the module does not exist, which is the first thing the story requires — and the
three AC-4 tests fail at PO-4's vacuity assertion, naming the file the classifier
did not return, rather than passing over a list that lacks their subject. Not one
of the ten fails on a helper, a syntax error or a timeout. The suite was
`197 passed, 0 failed` on arrival and is `211 passed, 10 failed` now: 24 new
cases, 14 green (controls) and 10 red.

`bash scripts/gates.sh --fast`: **format PASS (47), lint PASS (47), typecheck
PASS (8), build PASS; unit FAIL (the ten above); harness FAIL on one assertion
only** — "the working tree carries no stray .luau files", which is the four
untracked test files and clears on commit. See `## Regressions`.

### The export shape the tests already pin

Nothing below is a suggestion. Each name is imported or asserted by a test, so
getting it wrong is a red test rather than a debate.

    src/server/seats/Projection.luau
      Projection.forPlayer(assignment: Ring.Assignment, playerId: Ring.PlayerId) -> PublicSeatView
        -- a PLAIN FIELD FUNCTION, called with a dot: `Projection.forPlayer(a, p)`

      PublicSeatView = {
        playerId:    Ring.PlayerId,     -- == p
        keyClass:    Ring.KeyClass,     -- == assignment.keyClass[p]
        lensClass:   Ring.KeyClass,     -- == assignment.keyClass[assignment.sigma[p]]
        supplierId:  Ring.PlayerId,     -- the q with assignment.sigma[q] == p
        dependentId: Ring.PlayerId,     -- == assignment.sigma[p]
        seatOrder:   { Ring.PlayerId }, -- deep-equal to assignment.players, and NOT the same table
      }
      -- and NO other key, at any depth, for any player. Deep.diff reports an
      -- extra key as "value.<key>: unexpected".

What the tests **pin about the failure for a stranger** (AC-5, PO-3): raised, not
returned; the message, after Lune's `path:line: ` prefix, contains the substring
`Projection` and `tostring(playerId)` (so `nil` must render as `nil`); does not
begin with `Ring.`; and the location prefix does not end in `seats/Projection` —
i.e. `error(..., 2)`. The exact wording is otherwise yours; `Projection.forPlayer:
{tostring(playerId)} is not seated in this assignment` satisfies every needle.

What the tests **pin about the source text** (AC-4): the file `src/server/seats/
Projection.luau` must be returned by `bash scripts/classify.sh --list source
src/server/seats` (write it there, under that name, tracked or not); no code
reference to `table.clone`, `table.move`, `table.pack`, `table.unpack`,
`table.freeze`, `Deep.copy`, `pairs`, `next` or `setmetatable` anywhere in it
(comments and strings are blanked first, so the doc comment may name them); and
every `require(` in it is `require("./Ring")` — at least one, and no other
module. `table.find`, `table.insert`, `table.create`, `ipairs` and generalised
`for _, id in assignment.players do` are all outside the ban.

What is **not** constrained: the order of fields in the constructor; whether
membership is checked with `table.find` or a loop; the name of any local; whether
you export the `PublicSeatView` type (the Contract says to, the tests do not
read it); the wording of the error beyond the needles above.

### Three things GREEN needs to know before writing the loop

1. **selene's `manual_table_clone` rule fires on PO-2's loop in one shape.**
   Measured in RED against a probe file: `local out = {}` immediately followed by
   `for i, id in players do out[i] = id end` is flagged (and the `lint` gate is
   required, and exits 1 on a warning). Not flagged: the same loop with
   `table.insert(out, id)`; `local out = table.create(#players)` then the index
   loop; or `-- selene: allow(manual_table_clone)` on the line above the
   declaration. Any of the three keeps PO-2 and passes lint. The allow comment
   is invisible to AC-4's guard (comments are blanked).
2. **`.claude/tests/project-counters.test.sh` will need 48 / 48 / 9, narrow 9 / 9 / 5**
   once `Projection.luau` exists — its header says so, and the file is `harness`,
   which GREEN may write. Read the numbers out of the gates' own evidence lines
   rather than counting; record it in `## Regressions` as SEAT-001 and this RED
   did. `NARROW_TYPECHECK` stays 5 (`src/shared` alone).
3. **The `unit` floor is 197 and the real count after GREEN is 221.** That is the
   Lead PO's `project.conf` edit at GATES, noted in `## Orchestrator checks at
   PLANNED`.

### The negative controls, with the numbers they measured

Every control below **ran in RED** — the controls file needs only SEAT-001's
merged `Ring` — so these are measurements, asserted verbatim in
`projection_controls_test.luau`, not predictions. GREEN's job is to confirm the
baseline column against the shipped module: `projection_test.luau` runs the same
checks, and the one number that depends on the fixture rather than the stub —
AC-6's 123 discriminating cases — must come out identical, because it is a
property of how `Ring` deals seeds 2001–2008.

| Control (one defect each) | Passes | Fails | Measured |
|---|---|---|---|
| baseline allowlist over the real `Ring` | AC-1, AC-2, AC-3, AC-5, AC-6, naive | — | 144/144 views clean; AC-6 discriminating cases = **123 of 144** |
| `copyAndRemoveSigma` — `table.clone(assignment)`, `sigma = nil` (**AC-2's control; mutation 1**) | **naive** | AC-2, and AC-1, AC-3, AC-5, AC-6 | AC-2: 144/144 views; n = 3 seed 2001 kim: `keyClass[zed] = 2 at view.keyClass.zed; 3 integer-valued scalar(s)`; n = 4 seed 2001 kim: **4** integer leaves = `keyClass.amy = 3, bob = 4, kim = 1, zed = 2` |
| same, as **AC-3's control** | naive | AC-3 both halves | first half 144/144 (`private field players is present`, `keyClass … carries a table`, `view.players IS the assignment's own players table`); second half **32/32** views at n = 4 changed; `secret "SECRET:kim" leaked at view.pairings.kim[1]`, `secret 9001 leaked at view.pairings.kim[2]` |
| `lensFromSupplier` (**mutation 2**) | AC-3, AC-5, naive | AC-1, **and AC-2 and AC-6** | AC-1 144/144 on `value.lensClass`; AC-2 144/144 (the supplier's class is foreign); AC-6 fires |
| `emptyForUnknown` (**mutation 3**) | AC-1, AC-2, AC-3, AC-6, naive | **AC-5 alone** | 3 cases; `forPlayer(assignment, "sam") returned {  } instead of raising` |
| `refuseViaRing` — no membership check; Ring raises (PO-3) | AC-1, AC-2, AC-3, AC-6, naive | **AC-5 alone** | `is Ring's own refusal, not the projection's (PO-3)`; `does not name the module (Projection)`; quotes `Ring.supplierOf: sam has no supplier` |
| `aliasSeatOrder` — `seatOrder = assignment.players` (PO-2) | AC-2, AC-5, AC-6, naive | AC-1, AC-3 | AC-1 144/144 `aliased, not built by a loop - PO-2`; AC-3 `view.seatOrder IS the assignment's own players table` |
| `seatOrderFromRing` — the ring walked from p | AC-2, AC-3, AC-5, naive | AC-6, AC-1 | AC-6: **123 of 144** views (every discriminating case); `is the RING order, which is σ written out as a list` |
| `leakSupplierClass` — one extra integer field | AC-3, AC-5, naive | AC-2, AC-1, AC-6 | AC-2: `3 integer-valued scalar(s)`, `at view.supplierClass`; AC-1 `value.supplierClass: unexpected` |
| `swapNeighbours` | AC-2, AC-3, AC-5, AC-6, naive | **AC-1 alone** | 144/144, `value.supplierId: expected`, `value.dependentId: expected` |
| AC-4 matcher on text | — | — | all 9 banned symbols hit as code (`table.clone` on line 2, named with path); 0 hits on comments, strings, `tableclone`, `repairs.next`, or PO-2's loop |
| AC-4 on disk | — | — | `src/server/seats/Ring.luau:136 references table.clone` — exactly 1 — via `sourceFilesIn("src/server/seats")` |
| PO-5 flattener | — | — | `view.a.b.c = 7` reached; 3 value leaves, 6 key leaves |

**The AC-2 control, both halves (PO-6, and the story's success condition):** the
copy-and-remove-`sigma` projection **passes** the naive sigma-key test and
**fails** AC-2 on 144 of 144 views. Measured, not expected. The naive test did not
need sharpening: it asks only "no `sigma` key, a `keyClass` key", which a copy
satisfies and the real module must also satisfy (`projection_test` holds it to
the same check).

### The AC-2 discrimination, and what it cannot catch

Chosen (PO-5): flatten the view recursively to leaves with paths; consider
**integer-typed leaf values only**; assert (1) none equals `keyClass[q]` for any
`q ∉ {p, σ(p)}`, and (2) the view holds **exactly two** integer leaves. Keys are
flattened too but reported separately, because `seatOrder`'s indices are the
same small integers as key classes.

Known false negatives: a leak of the **dependent's** class under a second name
is invisible to (1) — that value is legitimately present as `lensClass` — but
(2) and AC-1's extra-key diff both see it. A class smuggled out **as a string**
(`"3"`) is invisible to both, and AC-6's every-string-leaf-is-a-seated-id check
sees it. A class hidden inside a **string key** is caught by AC-6's no-nested-
string-keys check. What nothing here sees: a leak encoded in the *order* of
`seatOrder` other than the ring order, or in a float (`3.0` is an integer to
`math.floor`; `3.5` is not counted). Neither is a shape a copy produces.

### AC-4: what was asserted, and what the guard cannot catch

**The block was not amended.** The guard is a flat ban, exactly as PO-2 and PO-4
pin it, plus one addition and one extension:

- the ban list is `table.clone`, `table.move`, `table.pack`, `table.unpack`,
  `table.freeze`, `Deep.copy`, **`pairs`, `next`, `setmetatable`** — the last
  three because the inline copy `for k, v in pairs(assignment) do view[k] = v
  end` and the copy-by-reference `setmetatable(view, { __index = assignment })`
  are copies no helper ban sees;
- the file's `require`s must all be `require("./Ring")`, so no copy helper can
  arrive under another name — this also pins PO-1.

`SourceScan.hitsIn` was verified to match every one of those symbols with its
word-boundary rules (it was built for `os.clock`; `table.clone` behaves the
same), and `sourceFilesIn("src/server/seats")` was verified to return
`Ring.luau` today and find its line-136 clone on disk.

What it cannot catch, stated in the test file too: `table["clone"]`, a local
alias built from a table lookup, a generalised-iteration copy written `for k, v
in assignment do` with no `pairs`, and anything behind `getfenv`. The scan is
textual and matches the way a call is written. AC-2, AC-3 and AC-6 are the
behavioural backstop for all of those today; the field M3 adds is the one none
of them can see yet, which is why the guard exists.

### The callers list, re-checked at the end of RED

    rg -n "Ring\.|require.*seats" src tests lune --glob '!*Ring.luau'

against the working tree at the end of RED: every hit is under `tests/`
(`ring_test`, `ring_controls_test`, `RingContract`, `RingStubs`, and the four new
files). **No production module requires `Ring`**; this story changes no existing
export. I did not want to change a `Ring` export and did not touch `Ring.luau`.

### Deferred verification: declined

`## Deferred verifications` — *A future private field must not leak* — is owned
by **GATES**. RED did not run it and could not: two of its three mutations
require an implementation to break, and the third requires the real M3 field.
AC-3's synthetic version (a `pairings` table of sentinels added after the fact)
**did** run in RED, against the copy control, and fired on 32 of 32 views. The
real one is left to GATES, in those words.

### Mutation table

What each test pins once the module exists, and how many **tests** in
`projection_test.luau` I predict go red for each. The orchestrator will run two
of these against the committed implementation and compare counts. The stub
controls above are the same defects measured against the baseline stub; the
predictions for the real module differ where the stub is a bare copy and the
real mutation keeps the named fields.

| # | Mutation of `Projection.luau` | Predicted red | Basis |
|---|---|---|---|
| 1 | replace the literal constructor with `table.clone(assignment)` + `view.sigma = nil` (`## Notes` 1) | **5**: AC-2, AC-4 (ban), AC-1 (extra keys `players`, `keyClass`-as-table, missing `lensClass`…), AC-3 (`players` present by name, `keyClass` a table), AC-6 (a nested string-keyed table) — the story predicts AC-1 stays green; it will not, because `Deep.diff` reports extra keys. AC-5 and naive stay green if the membership check survives the mutation | copy control: measured AC-1, AC-2, AC-3, AC-6 (+ AC-4 is the ban, not runnable on a stub) |
| 2 | `lensClass` read from the supplier (`## Notes` 2) | **3**: AC-1 (`value.lensClass`), AC-2, AC-6 — the story predicts AC-1 only; the supplier's class is foreign so the two leak checks fire too | `lensFromSupplier` control: measured 3 |
| 3 | return `{}` for an unknown player (`## Notes` 3) | **1**: AC-5 | `emptyForUnknown` control: measured 1 |
| 4 | drop the membership check and let `Ring.supplierOf` raise | **1**: AC-5 (`is Ring's own refusal`) | `refuseViaRing` control: measured 1 |
| 5 | `error(..., 2)` → `error(..., 1)` | **1**: AC-5 (`attributed to Projection.luau itself`) — **unverifiable by stub**, since no stub lives at that path; this is the one row only a mutation of the real file can confirm | Lune attributes level-2 errors to the caller's file, measured in RED |
| 6 | `seatOrder = assignment.players` (no loop) | **2**: AC-1 (aliased), AC-3 (by reference) | `aliasSeatOrder` control: measured 2 |
| 7 | `seatOrder = table.clone(assignment.players)` | **1**: AC-4 (ban) — behaviourally identical, which is the whole point of PO-2 | on-disk `table.clone` matched at `Ring.luau:136` |
| 8 | swap `supplierId` and `dependentId` | **1**: AC-1 | `swapNeighbours` control: measured 1 |
| 9 | add `supplierClass = assignment.keyClass[supplierId]` | **3**: AC-2, AC-1, AC-6 | `leakSupplierClass` control: measured 3 |
| 10 | `seatOrder` built by walking σ from `p` | **2**: AC-6 (123 views), AC-1 | `seatOrderFromRing` control: measured 2 |
| 11 | add a `require("@shared/Tuning")` and never use it | **1**: AC-4 (require count) | — |

Rows 3, 4, 5, 7, 8 and 11 predict a **single** assertion. Rows 3 and 5 are the
ones I would run first: 5 is the only prediction no control could measure.

### Discoveries worth GREEN's attention

- **AC-6's wording versus the Contract.** AC-6 says "p's view does not contain
  `keyClass[q]` for any q ≠ p". `lensClass` *is* `keyClass[σ(p)]` by definition
  (`λ(p) = k(σ(p))`, and the Contract's "why `lensClass` is safe" block), so the
  only reading under which AC-1 and AC-6 are both satisfiable is the one the
  tests take: no `keyClass[q]` for q ∉ {p, σ(p)}. Likewise "neither lets a reader
  compute the other's lens": the *supplier's* lens class is `keyClass[p]` by the
  ring's definition (`roles.md` §2), so `p` can always name it from their own key;
  the tests do not and cannot treat that as a leak. Neither point changed a test's
  design — there is no fork — so this is a note, not a stop; the PO may want the
  AC-6 sentence tightened to "for any q outside {p, σ(p)}" under `## Amendments`
  for the record.
- **Lune's `assert` truncates messages at 512 characters; `error` does not**
  (measured: 571 vs 6060 characters for a 6000-character string). Every check in
  `ProjectionContract` raises through a `check()` helper that calls `error(msg,
  2)` for that reason. The other contract helpers in `tests/helpers/` use bare
  `assert`; their control needles happen to sit inside the first 512 characters.
  Not this story's to change, but a needle added past that point in any of them
  can never match.
- **The phase guard mis-read one command.** `f=.claude/tests/x.sh && sed -i -e
  's/…/…/' "$f"` was refused as a write to path `s`, category `source` — it took
  the `-e` expression as the target. The real target was a harness file the phase
  permits; I used the Edit tool instead, which the guard judges by the real path.
  Reported so it can become a case in `.claude/tests/phase-guard.test.sh`; not
  routed around.
- **Test files are not type-checked by any gate** (`typecheck` covers `src`).
  `luau-lsp analyze` over the four new files reports only `@lune/*` requires it
  cannot resolve (pre-existing in `SourceScan.luau`) and the `pcall(check, x)`
  two-value pattern `ring_controls_test.luau` already uses.
- **Timing.** This runner has no per-test timeout; the `unit` gate ran the 221
  cases in 7 s locally, of which the `classify.sh` shell-out is ~1 s, cached per
  pathspec across both files. Local measurement only; no CI number exists yet
  for this suite size. The `coverage` gate is unconfigured, so there is no
  instrumented run to budget against.

## Regressions

### `.claude/tests/project-counters.test.sh`: literals moved 43 → 47 (RED)

The `harness` gate (required) counts `.luau` files through the gates' own
evidence lines and pins the count as literals. This RED added four test files
and no source, so `BASE_FORMAT`/`BASE_LINT` moved 43 → 47; `BASE_TYPECHECK` (8),
`NARROW_*` (8 / 8 / 5) are untouched because nothing under `src/` changed. The
file's own header prescribes this in RED, and SEAT-001 did the same
(`## PO ruling on the return to RED from REVIEW` there). The numbers were read
from the gates' evidence lines in `gates.sh --fast` — `stylua over 47 files`,
`selene over 47 files` — not counted by hand.

**Before**, under the gate command, with the four files present:

    $ bash .claude/tests/project-counters.test.sh
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
        FAIL format reports 43 files on the unmodified tree
             expected count: 43
             actual count:   47
        FAIL lint reports 43 files on the unmodified tree
             expected count: 43
             actual count:   47
        FAIL AC-2: format counts the untracked file (43 -> 44)
             expected count: 44
             actual count:   48
        FAIL AC-4: lint counts the untracked file (43 -> 44)
             expected count: 44
             actual count:   48
        FAIL format does not count the ignored file (still 43)
             expected count: 43
             actual count:   47
        FAIL lint does not count the ignored file (still 43)
             expected count: 43
             actual count:   47
    project-counters: 33 passed, 7 failed

**After** the literals and labels moved:

    $ bash .claude/tests/project-counters.test.sh
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
    project-counters: 39 passed, 1 failed

The one remaining failure is the stray-file precondition: the four test files
are untracked until the RED commit, and `git status --porcelain` lists them. It
clears on a clean tree; the orchestrator should see `40 passed, 0 failed` after
committing. RED cannot commit, so that run is the orchestrator's.

**The probe**, because a corrected literal is green the moment it is written:
hide the four `*rojection*` files from the format gate's count, through
`mutate.sh`, and watch exactly the corrected assertion go red:

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's|{n++; next}|{if ($0 !~ /rojection/) n++; next}|' \
        -- bash .claude/tests/project-counters.test.sh
    === mutate: .claude/harness/project.conf (1 line(s) changed by s|{n++; next}|{if ($0 !~ /rojection/) n++; next}|) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
        FAIL format reports 43 files on the unmodified tree
             expected count: 47
             actual count:   43
        FAIL AC-2: format counts the untracked file (43 -> 44)
             expected count: 48
             actual count:   44
        FAIL format does not count the ignored file (still 43)
             expected count: 47
             actual count:   43
    project-counters: 36 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260918T193618Z.224.bak) ===

(The labels still read "43" in that run; they were renamed to 47 immediately
after, and the final plain run above is with the renamed labels.) The `lint`
assertions stay green under the probe because the mutation touches only the
format gate's awk — the probe hides files from one counter and only that
counter's literal fires, which is what makes the literal a measurement rather
than a pattern.
