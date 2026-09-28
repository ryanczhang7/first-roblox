---
id: SEAT-003
title: A disconnect transfers the key class to the supplier and closes the ring
slug: a-disconnect-transfers-the-key-class-to
epic: EPIC-02
type: feature
status: in-review
phase: REVIEW
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

### `Assignment` changes shape: `keyClass` is replaced, and `lens` is stored

    export type Assignment = {
        players:    { PlayerId },                  -- seat order; a leaver is removed, order otherwise kept
        sigma:      { [PlayerId]: PlayerId },      -- σ over the seated players
        keyClasses: { [PlayerId]: { KeyClass } },  -- replaces `keyClass`; a player may hold more than one
        lens:       { [PlayerId]: KeyClass },      -- NEW (PO-1): λ(p), stored, not derived from σ
    }

Exactly these four fields and nothing else. `keyClass` (singular) is **gone**, not
kept beside the new field.

**Semantics pinned here (PO-1 .. PO-4, see `## Notes`):**

- `Ring.assign` deals `keyClasses[p] = { i }` (seat index, as today) and
  `lens[p] = k(σ(p))` — the dependent's single class at deal time.
- `Ring.lensOf(assignment, p)` returns `assignment.lens[p]`. It **no longer**
  computes `k(σ(p))`: after a withdrawal that formula names the leaver's lost lens
  (PO-1).
- `Ring.withdraw(assignment, q)`: let `s = σ⁻¹(q)` and `d = σ(q)` **in `assignment`
  as passed**. The result has `q` removed from `players` (others keep their
  relative order); `sigma[s] = d`, every other σ entry unchanged, no entry for `q`;
  `keyClasses[s]` = `s`'s existing list followed by **all** of `q`'s classes, in
  order; no entry for `q`; `lens` unchanged except `q`'s entry removed. It returns
  a **fresh** table and never mutates its argument — the caller keeps the argument
  as `Absence.snapshot` (PO-3). Withdrawing an unseated player raises (level 2),
  as `Ring.supplierOf` does. Behaviour when the input has fewer than 3 players is
  not specified by this story; AC-8 fixes only 3 → 2.
  > **Amended in RED (test-developer, 2026-09-28) — "fresh" means fresh at every
  > level.** The result shares **no table** with its argument: not `players`,
  > `sigma`, `keyClasses` or `lens`, and not any `keyClasses[p]` list, including
  > the lists of players the withdrawal did not touch. Reason: a result whose
  > untouched lists are the argument's own passes every AC — the values are all
  > right — and lets the *next* withdrawal's append rewrite `Absence.snapshot`
  > in place, which is PO-3's defect one step later. Pinned by
  > `RingContract.withdrawDoesNotMutateOrAliasItsArgument`; its control is
  > `RingStubs.shareSubTables`, which fails that pin alone. The raise pin is
  > read the same way as `Ring.supplierOf`'s: the message **names the player**
  > (`tostring(playerId)`; `nil` is not required to appear) and the error is
  > attributed to the caller, i.e. the location prefix is not `Ring.luau`
  > itself. The message text is otherwise not constrained.
- `Ring.rejoin(assignment, absence, now)`: if `now - absence.leftAt >=
  absence.graceSeconds` it returns `nil` (too late, inclusive); otherwise it
  returns a deep copy of `absence.snapshot` — the pre-withdrawal ring, with the
  rejoiner's seat, key classes and lens. It never mutates `assignment` or the
  snapshot. Composing a rejoin with a *second* withdrawal that happened during
  the first player's absence is out of scope (see `## Out of scope`).
  > **Amended in RED (test-developer, 2026-09-28) — "deep copy" is pinned at
  > every level, as for `withdraw`.** The returned ring is not
  > `absence.snapshot`, not `assignment`, and shares no table with the snapshot
  > (`players`, `sigma`, `keyClasses`, `lens`, any `keyClasses[p]`). Reason: the
  > driver that owns the `Absence` must not be reachable through the ring it
  > hands out. Pinned by `RingContract.rejoinDoesNotMutateOrAliasItsArguments`;
  > controls `RingStubs.rejoinReturnsSnapshot` and `rejoinMutatesArgument`. Nothing
  > about the refused (`nil`) path is constrained beyond "returns nil and
  > mutates nothing".
- `graceSeconds` is read by the tests from `Tuning.round.disconnect_grace_seconds`
  (PO-2), never written as 30.

**This is a signature change to an existing exported type**, and it has callers.
Grepped (`rg -n 'keyClass|lensOf|seats/(Ring|Projection)' src tests`) before
dispatch — RED cannot find these itself, because during RED the old shape still
exists and its callers still run. The paths originally written here
(`tests/server/seats/…`) did not exist; corrected at PLANNED:

| Caller | File | What changes |
|---|---|---|
| `Ring.assign`, header comment | `src/server/seats/Ring.luau` | returns `keyClasses` (one-element list per player) and `lens` |
| `Ring.lensOf` | `src/server/seats/Ring.luau` | reads `lens` |
| `Projection.forPlayer`, `PublicSeatView` | `src/server/seats/Projection.luau` | `keyClass: KeyClass` becomes `keyClasses: {KeyClass}` — **an allowlisted field, built by an explicit append loop, never `table.clone`** (SEAT-002 AC-4's flat ban). `lensClass` stays, from `Ring.lensOf`. *RED pin:* `view.keyClasses` must not **be** `assignment.keyClasses[p]` (the aliasing check in `ProjectionContract.viewIsExactlyTheAllowlist`; control `ProjectionStubs.aliasKeyClasses`) — the behavioural half of "append loop, never a copy". The append loop must use `table.insert`, not indexed assignment: selene's `manual_table_clone` fires on the indexed form (SEAT-002 PO-7). |
| SEAT-001's suite | `tests/server/ring_test.luau` | the "Contract: … carrying players, sigma and keyClass, and nothing the Contract does not name" test (l.62–90); AC-4 keys call (l.123) |
| SEAT-001's controls | `tests/server/ring_controls_test.luau` | l.71 (`keyClassesAreOneToNEachOnce`), l.338 (a pinned message literal containing `keyClass = {…}`) |
| SEAT-001's helpers | `tests/helpers/RingContract.luau` (l.23–24, 303–325, 391–393), `tests/helpers/RingStubs.luau` (l.157–169) | read `keyClasses`/`lens`; stubs build the new shape |
| SEAT-002's suite | `tests/server/projection_test.luau` | AC-1 exact-view test (l.92), naive test (l.188) |
| SEAT-002's controls | `tests/server/projection_controls_test.luau` | l.97–198, pinned messages naming `view.keyClass.*` |
| SEAT-002's helpers | `tests/helpers/ProjectionContract.luau` (l.22, 57, 112–113, 262–315, 337, 556–646, 711), `tests/helpers/ProjectionStubs.luau` (l.59, 129–138) | allowlist, expected view, and the AC-2 leak property's notion of "own" |
| path list only | `tests/net/raw_remote_guard_test.luau` l.49 | nothing — names the file, not the shape |

No other module requires `Ring` or `Projection`.

`SEAT-002`'s leak property must still hold after the change: `p`'s view carries
`p`'s own classes and nobody else's. If the simplest way to represent two classes
tempts an implementation toward a shared table, that is the leak this backlog spent
a story preventing.

**Alternative considered and rejected:** keep `keyClass` singular and represent the
transfer as a separate `inheritedClasses` map. It keeps the signature stable and
splits "which classes may this player operate" across two fields, which is two
places for an actuation check to read one of. Rejected. RED may amend any block
of this Contract in place, with a reason written beside the amendment, and GREEN
builds what the amended block says.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-3, AC-4, AC-6 | **Settled** | `roles.md` §6 and `mechanics.md` §8 decide all of this, including that the round gets easier and that the lens is lost. Read it out. Do not "improve" the repair. |
| AC-2, AC-7 | **Mechanical, with a control** | AC-7's control — suppliers computed against the original ring — is the one a single-withdrawal suite cannot see. |
| AC-5, AC-6 | **Settled** | `disconnect_grace_seconds` is 30, a **placeholder** in `tuning.md` §5 to be replaced by observed reconnect times once telemetry exists. Read it from `Tuning.round.disconnect_grace_seconds` (PO-2 — `RoundConfig` does not carry it); do not hard-code 30 and do not tune it. |
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

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SEAT-003` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `Absence.snapshot` (source), `Projection.forPlayer` (source), `Ring.assign` (source) (+34 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

**Resolved model of every dispatch, by name:**

- PLANNED — `lead-po`: `claude-opus-5-5` (the orchestrating session itself).
- RED — `test-developer`: `fable`, passed as an explicit `model: fable` on the Agent dispatch (the subagent reported seeing no override; the dispatch call carried one, so the override is what resolved).
- GREEN — `feature-developer`: `opus` passed explicitly on the dispatch; the agent reported running on `claude-opus-5-5`.

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
- A rejoin after a *second* withdrawal inside the first leaver's grace window
  (PO-4). Restoring the first snapshot would also restore the second leaver. The
  driver that owns absences decides this when it exists; no AC here reaches it.
- Withdrawal from a ring of fewer than 3. AC-8 fixes 3 → 2 only.

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

**PO decisions made at PLANNED → RED (lead-po, 2026-09-28):**

- **PO-1 — the lens is stored, not derived.** The story as planned kept
  `Ring.lensOf = k(σ(p))`. After `withdraw(q)`, `σ(s) = d` for the supplier `s`, so
  that formula gives `s` the lens `k(d)` — which is `λ(q)`, the leaver's lens.
  That is precisely what AC-4 forbids, and it also breaks AC-3: `roles.md` §6 says
  the supplier "can act on one of their own lens's pairings", which is true only if
  `s`'s lens is still `k(q)`. Reproduced by hand on the 4-ring `A→B→C→D→A`,
  `k = 1..4`: withdraw `C`; derived `λ(B) = k(σ(B)) = k(D) = 4 = λ(C)`, the lost lens.
  So `Assignment` gains `lens`, dealt as `k(σ(p))` and never recomputed. This is a
  contract fix, not an AC change: every AC reads the same.
- **PO-2 — grace comes from `Tuning`, not `RoundConfig`.** `RoundConfig` carries six
  fields and `disconnect_grace_seconds` is not one; adding it would change another
  module's exported type, with a pinned "exactly six fields" test, for a field this
  story has no consumer of (`Absence.graceSeconds` is supplied by the caller). The
  tests read `Tuning.round.disconnect_grace_seconds`. The driver that builds an
  `Absence` will decide where it reads it.
- **PO-3 — `withdraw` is pure.** AC-5 restores from the pre-withdrawal assignment,
  which the caller holds as `Absence.snapshot`; a `withdraw` that mutated its
  argument would silently rewrite the snapshot. Pinned in the Contract.
- **PO-4 — `rejoin` restores the snapshot.** For the single-absence case the ACs
  describe, "the ring returns to its pre-withdrawal shape" is the snapshot. A rejoin
  after a second, intervening withdrawal is not specified by any AC and is recorded
  in `## Out of scope`.

**Epic check.** `EPIC-02`'s last done-when bullet — "a disconnect transfers the
leaver's key class to their supplier and closes the ring, and a rejoin inside the
grace window restores the seat" — is exactly AC-1, AC-2 and AC-5. No gap.

**Required gate.** `unit` (`lune run test`, covers `src/server/**`) is required
and runs every test this story adds. `typecheck`, `lint` and `build` cover
`src/**` and are required. Nothing here is reachable only by an optional gate.

**Mutation the orchestrator should run at acceptance:**

1. Transfer the key class to `σ(q)` — the dependent — instead of `σ⁻¹(q)`.
   Predicted: AC-1 goes red alone. **Run this first**; it is the invisible error.
2. Compute the supplier from the original snapshot rather than the current ring.
   Predicted: AC-7 goes red, AC-1 stays green.
3. Change the grace comparison from `>=` to `>`. Predicted: AC-6's
   exactly-at-the-boundary assertion goes red alone.

**Raise the `unit` floor** to the new real count.

**The orchestrator's acceptance mutations (GATES, lead-po, 2026-09-28).** Run
against the shipped `Ring.luau` through `scripts/mutate.sh`; each restore
verified byte-for-byte.

    # 3. grace `>=` -> `>` (predicted: AC-6 alone, 96 of 288)
    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's/if now - absence.leftAt >= absence.graceSeconds then/if now - absence.leftAt > absence.graceSeconds then/' \
        -- lune run test
      FAIL  tests/server/ring_test.luau :: SEAT-003 AC-6: a rejoin at exactly t + disconnect_grace_seconds returns nil, ...
            ... in 96 of 288 cases
    442 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte ...) ===

    # 1. transfer to σ(q), the dependent (predicted: AC-1 32/32, AC-3, AC-7, list order)
    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's/table.insert(result.keyClasses\[supplier\], class)/table.insert(result.keyClasses[assignment.sigma[playerId]], class)/' \
        -- lune run test
      FAIL  ... SEAT-003 AC-1: ... - never the dependent
            RingContract:943: AC-1: ... in 32 of 32 (seed, leaver) cases at n = 4:
      FAIL  ... SEAT-003 AC-3: ...
      FAIL  ... SEAT-003 AC-7: ...
      FAIL  ... SEAT-003 Contract: the supplier's list is their own classes first, ...
    439 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte ...) ===

Both counts match RED's table exactly. Mutation 2 (suppliers from the original
ring) is not a one-line substitution against this code, which never has the
original ring in scope; it is pinned by the `supplierFromOriginal` control (AC-7
fails 40 of 80, AC-1 passes), which runs on every `lune run test`.

## Test plan

Written in RED (test-developer, 2026-09-28). Every check lives in a `*Contract`
helper and is applied twice: to the real module in `ring_test.luau` /
`projection_test.luau`, and to one-defect stubs in the `*_controls_test.luau`
files, where it is **observed to fire**. Where the story partitions the criteria
by oracle, the check reads the settled answer out of `roles.md` §6 and does not
re-derive it; AC-3 asserts the *degraded* invariant on purpose and says so in its
message.

| AC | Test (`tests/server/ring_test.luau` unless noted) | Check (`tests/helpers/RingContract.luau`) | Control(s) that fire it (`ring_controls_test.luau`) |
|---|---|---|---|
| AC-1 | `SEAT-003 AC-1: after q leaves a 4-ring, q's key class is held by the supplier σ⁻¹(q) and by nobody else - never the dependent` | `withdrawTransfersTheKeyClassToTheSupplier` | `transferToDependent` (32/32, **passes the naive test**), `dropLeaversClasses` |
| AC-1 (naive) | `SEAT-003 naive: every key class is held by somebody after a withdrawal - the test the dependent-transfer control passes` | `naiveEveryClassIsHeldBySomebody` | `dropLeaversClasses` (32/32); the dependent stub passes it |
| AC-2 | `SEAT-003 AC-2: the withdrawn ring is a single (n − 1)-cycle … relative order, in players and in σ` | `withdrawnRingIsOneCycleInTheOriginalOrder` (n = 4, 5, 6) | `sortRemainingSeats` (120/120), `closeOneStepTooFar` (120/120) |
| AC-3 | `SEAT-003 AC-3: the supplier holds two key classes and is the only player who can act on a class their own lens covers (deliberately degraded, roles.md §6)` | `supplierHoldsTwoAndIsTheOnlyPlayerWhoCanActOnTheirOwnLens` | `transferToDependent` (0 actors), `deriveLensAfterClose` (0 actors), `dropLeaversClasses` |
| AC-4 | `SEAT-003 AC-4: the leaver's lens is lost … and lensOf reads the stored lens` | `leaversLensIsLost` (n = 4, 5) | `deriveLensAfterClose` (72/72, PO-1's trap in the field), `lensOfDerives` (72/72, PO-1's trap in the accessor) |
| AC-5 | `SEAT-003 AC-5: a rejoin at t + disconnect_grace_seconds − 0.1 restores the pre-withdrawal ring exactly` | `rejoinInsideTheGraceWindowRestoresTheSeat` (also at `t` itself; leftAt ∈ {0, 12.5, 1e6}) | `rejoinAlwaysNil` (192/192) |
| AC-6 | `SEAT-003 AC-6: a rejoin at exactly t + disconnect_grace_seconds returns nil, the ring stays at n − 1 and the rejoiner is not seated` | `rejoinAtOrAfterTheGraceBoundaryIsRefused` (at grace, grace + 1, 10 × grace) | `graceExclusive` (**96/288 — exactly the boundary cases**) |
| AC-7 | `SEAT-003 AC-7: two withdrawals from a 5-ring … each transfer to the supplier in the ring as it stood at the time` | `twoWithdrawalsEachTransferToTheSupplierAtTheTime` (second leaver = first's dependent AND first's supplier, 80 cases) | `supplierFromOriginal` (**40/80 — exactly the dependent-second cases; passes AC-1**) |
| AC-8 | `SEAT-003 AC-8: a withdrawal from a 3-ring does not raise, yields a well-formed 2-ring, and carries exactly the four Assignment fields` | `withdrawalFromThreeYieldsAWellFormedTwoRingAndDecidesNothing` | `dropLeaversClasses`, `closeOneStepTooFar`, `deriveLensAfterClose`, `sortRemainingSeats` |
| Contract PO-3 | `SEAT-003 Contract: withdraw returns a fresh table at every level and never mutates its argument (PO-3)` | `withdrawDoesNotMutateOrAliasItsArgument` | `mutateArgument` (32/32), `shareSubTables` (32/32, alone) |
| Contract raise | `SEAT-003 Contract: withdrawing an unseated player raises, naming the player and blaming the caller; a seated one does not` | `withdrawOfAnUnseatedPlayerRaises` | `ignoreUnseated` (3 cases, alone) |
| Contract PO-4 | `SEAT-003 Contract: rejoin never mutates its arguments and returns a deep copy of the snapshot (PO-4)` | `rejoinDoesNotMutateOrAliasItsArguments` | `rejoinReturnsSnapshot` (32/64), `rejoinMutatesArgument` (32/64) |
| Contract list order | `SEAT-003 Contract: the supplier's list is their own classes first, then all of the leaver's in order, through two withdrawals` | `supplierListIsOwnClassesThenTheLeaversInOrder` | `leaverClassesFirst` (40/40, alone) |
| Shape | `Contract: assign returns an Assignment carrying players, sigma, keyClasses and lens, and nothing the Contract does not name`; `Contract: Ring exports withdraw and rejoin as plain field functions (SEAT-003)` | inline; `RingContract.ASSIGNMENT_FIELDS` | — (fails on the real module now: `keyClasses` nil, `withdraw`/`rejoin` nil) |
| SEAT-001 AC-4 (migrated) | `AC-4: each player holds exactly one key class …`; `AC-4: λ(p) = k(σ(p)) …` | `keyClassesAreOneToNEachOnce` (one-element list per player), `lensIsTheDependentsKeyClass` (now also `lens[p] == lensOf(p) == k(σ(p))`) | SEAT-001's `lensFromSupplier`, `swappedAccessors` (unchanged) |
| SEAT-002 (migrated, `projection_test.luau`) | AC-1, AC-2, AC-3, AC-5, AC-6, naive — now over 144 dealt views **plus 24 withdrawn views** (n = 4, 5, 6 × 2 seeds, `players[2]` leaves) | `ProjectionContract.*`: allowlist `keyClasses`; oracle `lensClass = lens[p]`; "own" = `keyClasses[p]` ∪ `{lens[p]}`; integer-leaf count = `#keyClasses[p] + 1`; new aliasing pin on `view.keyClasses` | all nine SEAT-002 stubs re-measured at 168 views, plus `aliasKeyClasses` (168/168, AC-1 alone) |

Edges covered: the boundary at exactly `t + grace` from three departure times
(0, 12.5, 1 000 000); every leaver at every n; both orders of a double
withdrawal; the 3 → 2 case (AC-8) separately from 4..6 → 3..5 (AC-2); strangers
`"sam"`, `"KIM"` and `nil`; n = 4 withdrawn rings in the projection's AC-3
second-half control (38 pinned views: 32 dealt + 6 withdrawn). Out of scope and
deliberately **not** pinned: rings of fewer than 3, a rejoin after a second
withdrawal, budget restoration, the degraded-round trace flag.

## Handoff: RED -> GREEN

**Dispatch:** RED ran on `fable`, passed explicitly on the dispatch (the subagent could
not see the override and first wrote that none was passed; corrected by the
orchestrator — see `## Model guidance`).

### The command

    lune run test

(the `unit` gate, verbatim from `project.conf`). There is no per-file filter in
this runner; the story's tests are the ones whose names start `SEAT-003` in
`tests/server/ring_test.luau`, plus every test in `ring_controls_test.luau`,
`projection_test.luau` and `projection_controls_test.luau`.

### The failure, verbatim (trimmed to the story's files; 33 red, 410 green)

    FAIL  tests/server/ring_test.luau :: Contract: assign returns an Assignment carrying players, sigma, keyClasses and lens, and nothing the Contract does not name
          tests/server/ring_test:68: assignment.keyClasses is nil: nil
    FAIL  tests/server/ring_test.luau :: Contract: Ring exports withdraw and rejoin as plain field functions (SEAT-003)
          tests/server/ring_test:101: SEAT-003's two exports are not both functions: Ring.withdraw is nil, Ring.rejoin is nil
    FAIL  tests/server/ring_test.luau :: AC-4: each player holds exactly one key class and the key classes are the integers 1..n each used once
          tests/helpers/RingContract:391: AC-4: the key classes are not the integers 1..n each used once, in 32 case(s):
    FAIL  tests/server/ring_test.luau :: AC-4: λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹
          tests/helpers/RingContract:512: AC-4: λ(p) = k(σ(p)) does not hold, or supplierOf/dependentOf do not read σ⁻¹/σ, in 32 case(s):
    FAIL  tests/server/ring_test.luau :: SEAT-003 AC-1: after q leaves a 4-ring, q's key class is held by the supplier σ⁻¹(q) and by nobody else - never the dependent
          tests/helpers/RingContract:839: Ring.withdraw is nil - SEAT-003 exports withdraw(assignment, playerId) and rejoin(assignment, absence, now) as plain field functions
    ... the same line for SEAT-003 AC-2 .. AC-8, naive, and the four Contract pins (13 in all)
    FAIL  tests/server/projection_test.luau :: AC-1: the view for p is exactly p's own keyClasses (a fresh list), own lensClass, ... on dealt and withdrawn rings
          tests/helpers/ProjectionContract:285: Ring.withdraw is nil - the withdrawn fixtures need SEAT-003's Ring.withdraw(assignment, playerId)
    ... the same for projection AC-2, AC-3, AC-6
    FAIL  tests/server/projection_test.luau :: naive: the view has no sigma key and has a keyClasses key
          tests/helpers/ProjectionContract:841: naive: the view carries a sigma key or no keyClasses key:
    FAIL  tests/server/projection_controls_test.luau :: baseline: an allowlist projection over the real Ring passes every SEAT-002 check
          tests/server/projection_controls_test:57: AC-1 on the baseline projection
    ... and the other 9 projection controls, each at its first fixture (Ring.withdraw is nil / keyClasses is nil)
    410 passed, 33 failed

**Why this is the right failure.** 13 of the ring tests stop at `Ring.withdraw
is nil` — the export the story adds — and the two shape tests stop at
`assignment.keyClasses is nil`, the field that replaces `keyClass`. The
projection suite and its controls stop at the same two facts one layer down
(the fixture asks the real `Ring` for a withdrawn ring). Nothing fails on a
syntax error, a require error, a lint rule or a timeout: `stylua --check`,
`selene tests` and the `format`/`lint`/`typecheck`/`build` gates are all green
on these files (`gates.sh --fast` below).

### The 26 ring controls all PASS now, in the runner, against the stubs

`ring_controls_test.luau` needs no production code (`Rng` and `Deep` only), so
every SEAT-003 check has been **executed and observed to fire** in RED, with the
counts in the table above measured in the runner, not predicted. The
`SEAT-003 baseline` test holds the correct stub to all 10 SEAT-001 checks and
all 13 SEAT-003 checks; each control is held to everything but what it is built
to fail, and `refuses(...)` pins the message.

### The export shape the tests already pin

Nothing below is a suggestion; each name is already called by a test.

    src/server/seats/Ring.luau

      export type PlayerId = string
      export type KeyClass = number
      export type Assignment = {
        players:    { PlayerId },
        sigma:      { [PlayerId]: PlayerId },
        keyClasses: { [PlayerId]: { KeyClass } },   -- keyClass (singular) must be ABSENT
        lens:       { [PlayerId]: KeyClass },
      }
      export type Absence = { playerId: PlayerId, leftAt: number, graceSeconds: number, snapshot: Assignment }

      Ring.assign(players, rng)          -> Assignment   -- keyClasses[p] = { seatIndex }, lens[p] = k(σ(p)); exactly four fields
      Ring.lensOf(assignment, p)         -> KeyClass     -- returns assignment.lens[p] (pinned after a withdrawal, AC-4)
      Ring.supplierOf / dependentOf      -- unchanged
      Ring.withdraw(assignment, q)       -> Assignment   -- plain field function; raises (level 2, names q) for an unseated q
      Ring.rejoin(assignment, absence, now) -> Assignment?  -- nil iff now - leftAt >= graceSeconds

    src/server/seats/Projection.luau

      export type PublicSeatView = { playerId, keyClasses: { KeyClass }, lensClass, supplierId, dependentId, seatOrder }
      Projection.forPlayer(assignment, p) -> PublicSeatView
        -- keyClasses is p's OWN list, a FRESH table (not assignment.keyClasses[p]), built with table.insert
        -- lensClass = Ring.lensOf(assignment, p)
        -- AC-4's flat ban on copy helpers in this file still applies (that guard is green today and stays)

What the tests do **not** constrain: how `withdraw` finds σ⁻¹ (a scan over
`players` as `supplierOf` does is fine); the exact wording of any error; whether
`rejoin`'s deep copy is hand-rolled or a loop (no copy helper is banned in
`Ring.luau`); the internal representation of `Absence` beyond its four fields.
`RingContract.ASSIGNMENT_FIELDS` is the exact field list, and AC-8 fails on any
fifth field on a withdrawal result.

### Negative controls and their expected values

**Ring side — measured in RED, in the runner** (the stubs need no production
code). GREEN does not need to re-measure these; they run on every `lune run test`.

| Control (`RingStubs.*`) | Check | Threshold | Expected | Measured in RED |
|---|---|---|---|---|
| `transferToDependent` | AC-1 | 0 violations | all 32 cases, holder named as the dependent | **32 of 32**; passes naive; also fails AC-3 (0 actors), AC-7 (80/80), list order |
| `dropLeaversClasses` | naive | 0 | all 32 | **32 of 32**; also AC-1, AC-3, AC-7, AC-8 (24/24), list order |
| `supplierFromOriginal` | AC-7 | 0 | exactly the dependent-second half | **40 of 80**; passes AC-1 and every other check |
| `deriveLensAfterClose` | AC-4 | 0 | all | **72 of 72**; also AC-3 (0 actors), AC-8 (24/24 wrong lenses) |
| `lensOfDerives` | AC-4 (lensOf half) | 0 | all | **72 of 72**, alone |
| `sortRemainingSeats` | AC-2 | 0 | all | **120 of 120**; also AC-7 (76/80), AC-8 (16/24) |
| `closeOneStepTooFar` | AC-2 | 0 | all | **120 of 120**; also AC-7 (80/80, via the check's own "σ⁻¹ cannot be found" report), AC-8 (24/24, fixed point) |
| `graceExclusive` | AC-6 | 0 | exactly the boundary cases | **96 of 288** (32 × 3 departure times); passes AC-5 |
| `rejoinAlwaysNil` | AC-5 | 0 | all | **192 of 192**; passes AC-6 |
| `mutateArgument` | PO-3 pin | 0 | all | **32 of 32**; also AC-3 and list order (supplier "cannot be found"); **passes AC-5** (the snapshot was rewritten too — why PO-3 has its own pin) |
| `shareSubTables` | PO-3 pin | 0 | all, by aliasing | **32 of 32**, alone |
| `leaverClassesFirst` | list order | 0 | all | **40 of 40**, alone |
| `ignoreUnseated` | raise pin | 0 | 3 strangers | **3 of 3**, alone |
| `rejoinReturnsSnapshot` | PO-4 pin | 0 | inside-window cases | **32 of 64**, alone |
| `rejoinMutatesArgument` | PO-4 pin | 0 | inside-window cases | **32 of 64**, alone |

**Projection side — a claim until GREEN.** In RED the real `Ring` has no
`withdraw` and deals `keyClass`, so `projection_controls_test.luau` fails at its
fixture and **not one of its assertions ran in the runner**. I measured them
outside the runner through a *candidate ring*: `Contract.assignmentFor` replaced
by the real `Ring.assign` converted to the new shape, and
`Contract.withdrawnAssignmentFor` by a 12-line reference withdraw (scratchpad
only, not in the tree). Through that shim the migrated controls file reports
`15 passed, 0 failed`. **GREEN confirms these against the shipped module**; a
divergence is a finding, not a number to edit.

| Control (`ProjectionStubs.*`) | Check | Expected | Measured through the candidate ring |
|---|---|---|---|
| `copyAndRemoveSigma` | AC-2 | all views; 6 integers at n = 3, 8 at n = 4 | **168 of 168**; passes naive; n = 4 kim: `keyClasses.{amy,bob,kim,zed}[1]` + `lens.{amy,bob,kim,zed}` |
| `copyAndRemoveSigma` | AC-3 | all views both halves | first half **168 of 168** (`players`, `lens` present; `keyClasses` is the map); second half **38 of 38** at n = 4 (32 dealt + 6 withdrawn) |
| `lensFromSupplier` | AC-1, AC-2, AC-6 | all | **168 of 168** each; `value.lensClass: expected` |
| `emptyForUnknown`, `refuseViaRing` | AC-5 | 3 strangers | **3 of 3**, alone |
| `aliasSeatOrder` | AC-1, AC-3 | all | **168 of 168**, by reference |
| `seatOrderFromRing` | AC-6 (and AC-1) | discriminating cases | **147 of 168 (147 discriminating)**; AC-1 162 of 168 |
| `leakSupplierClass` | AC-1, AC-2, AC-6 | all | **168 of 168**; "3 integer-valued scalar(s) …; kim holds 1 class(es), so the allowlist has exactly 2" |
| `swapNeighbours` | AC-1 | all | **168 of 168**, alone |
| `aliasKeyClasses` (new) | AC-1 | all, by aliasing | **168 of 168**, alone |
| `correct` | everything | passes | passes all six |

The counts moved from SEAT-002's 144 / 123 / 32 to 168 / 147 / 38 because 24
withdrawn views were added (n = 4, 5, 6 → 3, 4, 5 seated, two seeds each), all
of them discriminating for AC-6's ring-order check.

### Mutation table (what `## Notes` asks the orchestrator to run)

Predicted from the controls above; GREEN/orchestrator runs them through
`scripts/mutate.sh` against the shipped `Ring.luau`.

| Mutation of `Ring.luau` | Predicted red | Predicted green |
|---|---|---|
| 1. transfer to `σ(q)` instead of `σ⁻¹(q)` | SEAT-003 AC-1 (32/32, message names the dependent); AC-3 (0 actors); AC-7 (80/80); list order | AC-2, AC-4, AC-5, AC-6, AC-8, naive, PO-3, PO-4, raise; every projection test |
| 2. supplier from the snapshot / ring as dealt instead of the ring as passed | AC-7 only, **40 of 80** (the dependent-second cases) | AC-1 and every other test — this is why AC-7 exists |
| 3. grace `>` instead of `>=` | AC-6 only, **96 of 288** (exactly `t + grace`) | AC-5 and everything else |

Two more worth a run: recompute `lens` after closing (PO-1's trap) → AC-4 72/72,
AC-3, AC-8; and hand `Projection.forPlayer` the list itself
(`keyClasses = assignment.keyClasses[playerId]`) → projection AC-1 168/168 alone.

### Caller table

Checked every row of the Contract's caller table against the tree with
`rg -n 'keyClass|lensOf|seats/(Ring|Projection)' src tests` at the start of RED:
the only files matching are the eight test files migrated here, the two source
files GREEN owns, and `tests/net/raw_remote_guard_test.luau:49`, which names the
path and nothing else and was left alone. No other module requires `Ring` or
`Projection`. The `unit` gate's `covers | unit | src/server/**` line already reads
both source files.

### Files touched (all `test`, per `paths.conf`; nothing under `src/`)

- `tests/helpers/RingStubs.luau` — new shape; `withdraw`/`rejoin` with 15 one-defect controls
- `tests/helpers/RingContract.luau` — migrated AC-4 checks; SEAT-003 checks; `check` (error, level 2) replaces `assert` for the AC-6 message, which the wider shape pushed past Lune's 512-char `assert` cut
- `tests/server/ring_test.luau` — shape test → four fields; exports test; 13 SEAT-003 tests (12 → 26 tests)
- `tests/server/ring_controls_test.luau` — degenerate-ring needle in the new shape; 16 SEAT-003 control tests (10 → 26)
- `tests/helpers/ProjectionContract.luau` — allowlist, oracle, "own"/"foreign", withdrawn cases, `keyClasses` aliasing pin, AC-3 snapshot key includes the leaver
- `tests/helpers/ProjectionStubs.luau` — reads `lens[p]`/`keyClasses[p]` off the field (shape-agnostic); `aliasKeyClasses`
- `tests/server/projection_test.luau` — names; 10 tests unchanged in count
- `tests/server/projection_controls_test.luau` — needles at 168/147/38; `aliasKeyClasses` control (14 → 15)
- `docs/backlog/stories/SEAT-003.md` — `## Contract` amendments (two, in place, marked), `## Test plan`, this section

Test count: **412 → 443** (`lune run test -- --list`: 443 tests). **Raise the
`unit` floor to 443** in GATES, per `## Notes`.

### `gates.sh --fast` in RED (shape of the failure)

    PASS         format (0s, observed 88)
    PASS         lint (1s, observed 88, floor 1)
    PASS         typecheck (4s, observed 17)
    FAIL         unit (32s, exit 1)          <- 410 passed, 33 failed, the story's assertions
    UNCONFIGURED coverage
    PASS         build (0s, observed 54902)
    FAIL         harness (22s, exit 1)       <- project-counters precondition: the eight modified
                                                test files make `git status --porcelain -- src tests lune`
                                                non-empty ("the working tree carries no stray .luau files").
                                                Clears when the RED commit lands; not a test defect.

Timing: the whole suite runs in ~12–13 s standalone on this machine (local, not
CI); the new checks add well under a second (8 seeds × small n). The `unit` gate
wall time above includes the runner's process start. No test here has its own
timeout; the runner has none.

### Notes for the implementer

- **PO-1 has two places to get wrong, and both are pinned.** The stored `lens`
  must not be recomputed after `σ(s) = d` (control `deriveLensAfterClose`), and
  `lensOf` must read the field rather than `k(σ(p))` (control `lensOfDerives`).
  Either mistake hands the supplier the lost lens and makes AC-3 read 0 actors.
- **AC-3 is degraded on purpose.** After a withdrawal exactly one player — the
  supplier — has `lens[p] ∈ keyClasses[p]`. Do not "fix" that.
- **Fresh at every level** (the Contract amendment): clone each `keyClasses[p]`
  list, including untouched players'. `shareSubTables` is the control.
- The AC-7 oracle is captured before the second withdrawal it judges; it does
  not depend on the implementation being pure, so an in-place `withdraw` fails
  PO-3 without confusing AC-7.
- `withdrawOfAnUnseatedPlayerRaises` checks the error's location prefix is not
  `…/Ring` — use `error(msg, 2)` as `supplierOf` does.
- `Projection.forPlayer`: build `keyClasses` with `table.insert` in a loop over
  `assignment.keyClasses[playerId]`. The indexed form trips selene's
  `manual_table_clone`, whose suggested fix is the banned `table.clone` (SEAT-002
  PO-7); AC-4's textual guard is green today and must stay so.
- The projection stubs read `assignment.lens[p]` directly rather than through
  `Ring.lensOf`. That is deliberate (it is what made a RED measurement possible)
  and says nothing about the real module, which must go through `Ring.lensOf`
  (the AC-4 require guard allows `./Ring` only).
- Nothing was deferred: `## Deferred verifications` stays empty. The one
  verification RED could not perform in the runner — the projection controls —
  is the candidate-ring measurement above, declined in writing here and left to
  GREEN to confirm.

### Doubts

- The projection numbers (168 / 147 / 38 and the n = 4 leaf listing) were
  measured through a candidate ring whose `withdraw` is mine, not GREEN's. If
  GREEN's `Ring.assign` deals classes other than by seat index, or its
  `withdraw` orders `players` differently, those needles will diverge — which
  would be the tests doing their job, and the story says the seat-index deal is
  kept.
- `closeOneStepTooFar` makes AC-7 fail through the check's own "σ⁻¹ cannot be
  found after the first withdrawal" report rather than an assertion about
  holders. That is a property of the defect (a ring closed wrongly cannot be
  withdrawn from twice); it is listed, not hidden.

## Handoff: GREEN -> GATES

**Dispatch:** GREEN ran as `feature-developer`, on `claude-opus-5-5`; the agent saw
no model override on its own dispatch.

### What changed (source only; `frozen.sh verify`: 8 paths unchanged)

- `src/server/seats/Ring.luau` — `Assignment` is exactly `{players, sigma,
  keyClasses, lens}`; `assign` deals `keyClasses[p] = {seatIndex}` and
  `lens[p] = k(σ(p))`; `lensOf` reads `lens[p]`; `export type Absence`;
  `Ring.withdraw` (supplier σ⁻¹(q) found by its own scan over `players` of the ring
  as passed, so an unseated q raises at level 2 from `withdraw` itself; the leaver's
  classes appended to the supplier's list; the leaver's `lens` entry dropped, no lens
  recomputed); `Ring.rejoin` (`now - leftAt >= graceSeconds` → nil, else a deep
  copy of the snapshot). One private helper, `copyWithout`, builds every level fresh
  by walking `players` and appending, never `table.clone`. That is not style:
  `projection_controls_test` pins **exactly one** `table.clone` in `Ring.luau`
  (SEAT-001's), and selene's `manual_table_clone` would fire on a map-to-map copy
  loop. `rejoin`'s first parameter is `_assignment`, unused (PO-4 / Out of scope).
  Header comment updated (four fields, stored lens, no clock).
- `src/server/seats/Projection.luau` — `PublicSeatView.keyClasses: {KeyClass}`,
  a fresh list built with `table.insert` over `assignment.keyClasses[playerId]`;
  `lensClass` still from `Ring.lensOf`. Header field list updated.

### Tests

    lune run test
    ...
    443 passed, 0 failed

### Projection controls, measured against the shipped Ring

Measured by a scratchpad script (outside the tree) that drives every
`ProjectionContract` check against every `ProjectionStubs` control and prints the
counts from each failure message, not just pass/fail. **No divergence from RED's
candidate-ring numbers.**

| Control | Check | RED (candidate ring) | GREEN (shipped Ring) |
|---|---|---|---|
| `copyAndRemoveSigma` | AC-2 | 168 of 168; passes naive | 168 of 168; passes naive; n = 3 kim: 6 integers, "allowlist has exactly 2" |
| `copyAndRemoveSigma` | AC-3 | 168 of 168 / 38 of 38 at n = 4 | 168 of 168 / 38 of 38 at n = 4 |
| `lensFromSupplier` | AC-1, AC-2, AC-6 | 168 of 168 each | 168 of 168 each (AC-6: 147 discriminating) |
| `emptyForUnknown`, `refuseViaRing` | AC-5 | 3 of 3, alone | 3 case(s) each, alone |
| `aliasSeatOrder` | AC-1, AC-3 | 168 of 168 | AC-1 168 of 168; AC-3 first half 168 of 168 (second half 0 of 38 — it passes the n = 4 half, as expected: the order is right, only the table is shared) |
| `seatOrderFromRing` | AC-6 (AC-1) | 147 of 168; AC-1 162 of 168 | 147 of 168; AC-1 162 of 168 |
| `leakSupplierClass` | AC-1, AC-2, AC-6 | 168 of 168 | 168 of 168 each |
| `swapNeighbours` | AC-1 | 168 of 168, alone | 168 of 168, alone |
| `aliasKeyClasses` | AC-1 | 168 of 168, alone | 168 of 168, alone |
| `correct` | all six | passes | passes all six |

### Mutations run against the shipped `Ring.luau` (`scripts/mutate.sh`, restored and verified)

    # 1. transfer to the dependent: keyClasses[supplier] -> keyClasses[assignment.sigma[playerId]]
      FAIL  SEAT-003 AC-1 ... never the dependent
      FAIL  SEAT-003 AC-3 ... (deliberately degraded, roles.md §6)
      FAIL  SEAT-003 AC-7 ... in the ring as it stood at the time
      FAIL  SEAT-003 Contract: the supplier's list is their own classes first ...
    439 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte ...) ===

    # 3. grace `>=` -> `>`
      FAIL  SEAT-003 AC-6: a rejoin at exactly t + disconnect_grace_seconds returns nil ...
            RingContract:1295: AC-6: ... was not refused, or the seat came back, in 96 of 288 cases:
    442 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte ...) ===

Both match the predicted red sets exactly. Mutation 2 (supplier computed from
the original ring) is not a one-line `sed` against this implementation, which has
no original ring in scope, so it was not run; its control `supplierFromOriginal`
(40 of 80) runs on every `lune run test`.

### `gates.sh --fast`

    PASS         format (0s, observed 88)
    PASS         lint (1s, observed 88, floor 1)
    PASS         typecheck (2s, observed 17)
    PASS         unit (15s, observed 443, floor 412)
    UNCONFIGURED coverage
    PASS         build (1s, observed 57746)
    FAIL         harness (14s, exit 1)   <- project-counters precondition "the working tree
                                            carries no stray .luau files": the 2 source + 8 test
                                            files are uncommitted. 39 passed, 1 failed. Clears on commit.

### For GATES

- Raise the `unit` floor from 412 to 443 (`## Notes`).
- The `harness` failure above is the uncommitted tree, not code; re-check it after
  the GREEN commit lands.

### Orchestrator verification at GREEN → GATES (lead-po, 2026-09-28)

    $ lune run test | tail -1
    443 passed, 0 failed
    $ bash scripts/frozen.sh verify
    frozen: OK — 8 path(s) unchanged since the snapshot for SEAT-003

`gates.sh --fast`: format, lint, typecheck, build PASS; unit PASS (observed 443,
floor 412); `changes: 2 changed source path(s), all exercised by a required gate`;
harness FAIL on the stray-file precondition only (uncommitted tree), which the
GATES commit clears, as for TEL-002 and TEL-003. GREEN's projection-control
confirmation matches RED's recorded values in every row (168 / 147 / 38, 3 of 3).

## Gate probes

### The `unit` gate's floor, raised 412 -> 443 and watched to fail (GATES, Lead PO)

443 is this story's own run (`443 passed, 0 failed`). Probed by setting the floor
one above the measured count through `scripts/mutate.sh` and running the gate it
governs (a partial run; `gates.sh` does not record it):

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's/^floor    | unit      | 443$/floor    | unit      | 444/' \
        -- bash scripts/gates.sh --gate unit
    FAIL         unit (14s, did 443 units of work, below the floor of 444 in project.conf) -> .claude/state/gate-logs/unit.log
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_harness_project.conf.20260928T173525Z.1826.bak) ===
      546: floor    | unit      | 443

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-28T17:39:14Z
    commit: be91cd4
    tree:   7159982f9af836f5b883f86607a30df72ea79be9
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 88)
    PASS         lint (0s, observed 88, floor 1)
    PASS         typecheck (2s, observed 17)
    PASS         unit (13s, observed 443, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 57746)
    PASS         harness (14s, observed 40)
    UNCONFIGURED mutation

