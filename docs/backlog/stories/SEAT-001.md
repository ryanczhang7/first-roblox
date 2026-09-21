---
id: SEAT-001
title: Seats are dealt as a seeded single-cycle derangement
slug: seats-are-dealt-as-a-seeded-single-cycle
epic: EPIC-02
type: feature
status: done
phase: DONE
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

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SEAT-001` from `.claude/harness/models.conf`.
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
<!-- plan.sh:generated:end -->

_Restored from `bea475b^`: the guidance below was deleted by `plan.sh write` in bea475b, which replaced the whole section instead of the generated block. Fixed in PR #20._

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

**Resolved:**

| Phase | Agent | Planned | **Resolved** |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | **Opus 5**, this session |
| RED | `test-developer` | `fable` | **Fable 5.1** (`claude-fable-5-1`), dispatched with an explicit `model: fable` override so the plan won over the agent definition's `model: opus`. The agent confirmed the resolution from inside the dispatch. |

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

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

---

## PO decisions at PLANNED -> RED

**1. The required gate is `unit`, and it already covers this story's path.**
The artifact is `src/server/seats/Ring.luau`; `.claude/harness/project.conf:490`
carries `covers | unit | src/server/**`. `unit` is `required`. Nothing to add to
`required_gates`, and no optional-gate-only artifact to worry about.

**2. The caller list is empty, and that was checked.**
`grep -rn 'Ring\.' src/ tests/` returns nothing. `Ring` is a new module, so no
existing signature changes and there is no caller for GREEN to break. The
`AssignSeats` effect `PhaseMachine` already emits carries `seed` and `players`
and is consumed by nobody yet - the driver that will call `Ring.assign` is
`RoundService`, which does not exist.

**3. `Rng:shuffle` exists, is non-mutating, and is an unbiased Fisher-Yates.**
The Contract's construction assumes all three and AC-5's uniformity rests on the
last one, so it was verified rather than assumed (`src/shared/Rng.luau:103-110`):

    shuffle = function<T>(self: Rng, list: { T }): { T }
        local out = table.clone(list)
        for i = #out, 2, -1 do
            local j = self:nextInteger(1, i)
            out[i], out[j] = out[j], out[i]
        end
        return out
    end,

Descending `i`, `j` drawn from `[1, i]`, swap - textbook Fisher-Yates, so every
permutation is equally likely if `nextInteger` is. It clones first, so AC-7's
"the input list is not mutated" is inherited rather than re-implemented.
**If AC-5's distribution fails, suspect `nextInteger`'s range, not the shuffle** -
and that would be a `ROUND-001` defect surfacing here, which is a finding to
report, not something to fix inside this story.

**4. The epic's done-when is satisfied by these criteria, with no gap to absorb.**
`EPIC-02` asks that *"`Ring.assign` produces a permutation with no fixed point and
exactly one orbit, for every seated count from 3 to 6, reproducibly from a seed."*
That is AC-1 (no fixed point), AC-2 (one orbit), AC-3 (reproducible from a seed)
and the `n` in 3..6 range AC-1 names. The epic's other bullets belong to
`SEAT-002`, `SEAT-003` and the NET/TEL stories. Checked, not skipped.

**5. The Contract stands unamended, and RED may amend it in place with a reason.**
It already pins the module path, the four exported signatures, the `Assignment`
shape, the direction of `σ` in prose *and* as a worked four-player ring, the
`λ(p) = k(σ(p))` relation, the `derive("seats")` sub-stream, and the oracle
partition. Nothing was left for RED to infer. The one thing worth restating in
the dispatch is the Contract's own warning: **getting the direction of `σ`
backwards produces a game that still works and is wrong in a way no structural
test catches.** AC-4 is the criterion that pins it, and `SEAT-003` depends on it.

**6. Nothing is deferred.** Both controls this story names - a plain derangement
generator for AC-2 and a constant generator for AC-5 - are hand-writable stubs
that need no production code, so RED can run them. That is what the
`## Deferred verifications` block already says, and it remains true.

**7. AC-5 is the criterion to watch, and its band is not negotiable in RED.**
It is the only oracle-free one: 10,000 seeds at `n = 4`, all six cyclic
derangements present, none above 25% or below 8% against a uniform 16.7%. The
Contract records why those bounds. A generator that always returns the canonical
ring passes AC-1, AC-2 and half of AC-3, so AC-5 is the only thing standing
between this story and a constant. **If RED believes the band or the sample is
wrong, it says so and stops** - widening a tolerance to go green is a weakening
(`rules.md`), and this is precisely the shape it takes.

**8. Cost check on AC-5 before RED writes it.** 10,000 seeds x an `n = 4` shuffle
is ~40,000 `nextInteger` draws plus tallying. That is arithmetic over small
tables, and the `unit` gate is currently 13 s locally for 175 tests and 0-1 s on
CI, so there is headroom. RED reports the measured cost of that one test in the
handoff anyway: the `--fast` run at the end of RED is where a test that only just
fits is supposed to be caught, and a 10,000-iteration loop is the first thing in
this project that could plausibly not fit.

**9. Toolchain.** `lune`, `rojo`, `selene`, `stylua`, `luau-lsp` under
`~/.rokit/bin`. Every dispatch carries `export PATH="$HOME/.rokit/bin:$PATH"`.

---


---

## PO ruling at RED -> GREEN

**RED is accepted**, re-run by the orchestrator rather than taken on report.

**The suite.** `lune run test` -> **`185 passed, 12 failed`**, against
`175 passed, 0 failed` at the branch point. All twelve failures are in
`tests/server/ring_test.luau` - one per acceptance criterion plus three Contract
pins - and the ten control tests PASS, which is what makes them evidence:
`ring_controls_test.luau` observed each wrong generator being rejected.
**No pre-existing test went red.**

**RED wrote no production code.** `git diff --stat -- src` is empty;
`git status --short` is the story plus four new test files and nothing else.

**Admissibility.** `bash scripts/gates.sh --fast`:

    PASS         format (0s, observed 42)
    PASS         lint (0s, observed 42, floor 1)
    PASS         typecheck (2s, observed 7)
    FAIL         unit (15s, exit 1)
    UNCONFIGURED coverage
    PASS         build (0s, observed 20721)

42 files observed, up from 38. Only the test gate is red, and it is red with this
story's assertions - no timeout, no lint rule tripped by a new file, no config
error.

**AC-5 is not a timeout risk, which was the open question.** Measured at
**25.7 / 30.7 / 28.5 / 33.6 / 30.8 ms** over five runs for the 10,000-seed tally.
The whole suite is 15.1 s. No `slow` line and no `ci-factor` line is warranted,
and PO decision 8's concern is closed.

### The controls are measurements, not claims

Unusually for this repository, RED's controls **ran**: the stubs need only
`ROUND-001`'s `Rng`, so unlike a suite that fails at import, every control
executed and its number is in the handoff. Two are worth naming:

- The **baseline tally** over the real `Rng`, seeds 1..10000 at `n = 4`:
  `1683 / 1651 / 1666 / 1677 / 1661 / 1662`, 16.5-16.8% against a uniform 16.7%,
  zero non-cyclic. That independently confirms PO decision 3 - `Rng:shuffle` and
  `nextInteger` are unbiased in the range this story depends on.
- The **`plainDerangement` control passes AC-5** at 11.0-11.3% each, and fails
  AC-2 at 22 of 64 seeds. That is the right shape: AC-5 does not catch it, AC-2
  does, and the story's `## Notes` predicted exactly that.

The controls file also asserts each stub **passes** the checks it should pass
(`passesTheStructuralChecks`), so every failure is attributable to one defect
rather than to a stub broken six ways.

### Ruling 1 — RED's five judgement calls are accepted, all five

RED flagged them rather than burying them, which is the behaviour this harness
wants. Taken in turn:

1. **AC-6's observable is "raises".** The Contract said "fails" without pinning
   how. `error` is the right choice and RED's reasoning is sound: the signature
   returns an `Assignment` and nothing else, `Rng.nextInteger` in this same
   codebase raises on an empty range for the same stated reason, and every
   degenerate result - a swap at `n = 2`, a fixed point at `n = 1`, `{}` at
   `n = 0` - is a table that LOOKS like an `Assignment`. A sentinel would move
   the failure somewhere else. **Pinned: `assign` raises below 3, message text
   unconstrained, and `n = 3` must succeed.**
2. **The strict three-field `Assignment` shape.** It reads the Contract's type
   literally and pins the "lens contents are M3" non-goal. Accepted. **If GREEN
   finds it needs a fourth field, that is a PO question, not a test edit.**
3. **One pin beyond the seven ACs** - draws from the parent rng before `assign`
   do not move the seats. That is the observable form of the Contract's
   `derive("seats")` clause, which otherwise has no test at all. Kept, on the
   same reasoning as `HARNESS-006`'s `doctor.sh` guard: a Contract clause with no
   assertion is a comment.
4. **The `inPlace` control fires four checks rather than one**, because
   corrupting a shared fixture list has consequences beyond AC-7. Documented as a
   property of the defect rather than trimmed to look tidy. Fine.
5. **The baseline stub is the Contract's own one-line construction.** Unavoidable
   - the baseline has to be *a* correct generator - and it follows the
   `RoundEndingStubs` precedent. GREEN writes `Ring.luau` from the **Contract**,
   not by copying the stub.

### Ruling 2 — nothing was escalated, and that was checked rather than assumed

RED reported the AC-5 band and sample as sound, the Contract as standing
unamended, and no criterion as ambiguous. The orchestrator's own PLANNED checks
agree: `Rng:shuffle` is a non-mutating Fisher-Yates, the caller list is empty,
and the epic's done-when bullet maps onto AC-1/2/3. There is no claim here that
the contract is wrong, so there is nothing to reproduce independently.

### What GREEN is accountable for

1. Write `src/server/seats/Ring.luau` from the **Contract**. Tests are frozen -
   the lock enforces it here, since these are `src/**` paths, but say it anyway:
   if a test is wrong, stop and report it. That is a return to RED.
2. **Confirm the measured control values against the shipped module**, not just
   that the tests pass. The handoff's table is the reference; the AC-5 baseline
   tally is the one that matters most, because a module that is correct but
   biased passes every structural criterion and fails only that.
3. **Run the `## Notes` mutations** through `bash scripts/mutate.sh` and compare
   against the handoff's 11-row table. Run mutation 2 (constant canonical ring)
   first - the story says so, and it predicts **2** red.
4. Get the direction of σ right. The Contract warns that backwards still "works";
   AC-4 is the only thing that catches it, and `SEAT-003` depends on it.
5. End with `bash scripts/gates.sh --fast` and report it.
6. **Raise the `unit` floor** to the new real count. `project.conf` has 175; the
   green count will be 197. That is a harness write and GREEN may make it.

**Resolved model of the RED dispatch:** `test-developer`, planned `fable` by
`models.conf`, dispatched with an explicit `model: fable` override so the plan
beat the agent definition's `model: opus`. Resolved to **Fable 5.1**
(`claude-fable-5-1`), confirmed by the agent from inside the dispatch. The
policy's premise held: the controls came back with a vacuity guard on the
controls themselves and measured numbers pinned in the assertion text.

---


---

## PO acceptance at GREEN -> GATES

**GREEN is accepted**, re-run by the orchestrator rather than read off the report.

**The suite.** `lune run test` -> **`197 passed, 0 failed`**: 185 from RED's run
plus the twelve that turned. No pre-existing test went red.

**GREEN wrote no test.** `git diff --stat -- tests/` is empty, and the four test
files are still untracked exactly as RED left them.

**Gates.** `bash scripts/gates.sh --fast`:

    PASS         format (1s, observed 43)
    PASS         lint (1s, observed 43, floor 1)
    PASS         typecheck (2s, observed 8)
    PASS         unit (9s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (1s, observed 25103)
    changes: 1 changed source path(s), all exercised by a required gate

`43` files and `8` typechecked, up from 42 and 7 - the one new source module.
The build grew 20,721 -> 25,103 bytes, which is `Ring` arriving in
`ServerScriptService.Server`; `gates.sh` confirms the changed source path is
exercised by a required gate, which is PO decision 1 holding at run time rather
than on paper.

### The mutation table is confirmed, not quoted

Mutation 3 was re-run by the orchestrator - chosen because its predicted catch is
a **single** assertion, which is where a vacuous test hides:

    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's|function Ring.dependentOf|function Ring.__swapped|; s|function Ring.supplierOf|function Ring.dependentOf|; s|function Ring.__swapped|function Ring.supplierOf|' \
        -- lune run test

      FAIL  tests/server/ring_test.luau :: AC-4: λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹
    196 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_seats_Ring.luau.20260917T033326Z.1892133.bak) ===

`196 passed, 1 failed`, the one assertion predicted, nothing else. All three of
GREEN's runs match the handoff's 11-row table with no divergence in any row.

**On the AC-5 tally matching RED's six numbers exactly.** It does -
`1683 / 1651 / 1666 / 1677 / 1661 / 1662`, zero non-cyclic - and that is
**expected rather than corroborating**: RED's baseline stub and GREEN's module
are both the Contract's construction over the same `Rng`, so they land on the
same ring for all 10,000 seeds. It is worth stating plainly so nobody later reads
the identity as two independent measurements agreeing. The evidence that AC-5
*discriminates* is mutation 2, which drove it to `10000 (100.0%)` on one ring
with five absent.

The tally does independently re-confirm PO decision 3: `Rng:shuffle` and
`nextInteger` are unbiased across the range this story uses, 16.5-16.8% against a
uniform 16.7%.

### The implementation, reviewed

Read rather than assumed, and it honours the Contract:

- **The single cycle is structural, not tested-for.** `sigma[p] = order[(i % #order) + 1]`
  over a shuffled order, with the wrap named in a comment as the thing that makes
  it one cycle rather than a chain. There is no rejection sampling and no retry
  loop, so AC-2 cannot fail intermittently.
- **`rng:derive(SEATS_LABEL)`**, so the Contract's sub-stream pin holds and M3 can
  later draw `derive("instance")` without shifting any seat.
- **The minimum is read from `Tuning`**, not written as a literal 3 - the
  `RoundConfig` precedent - so `min_players_to_continue` has one home.
- **Key classes are dealt by seat index**, with the reason recorded: any bijection
  onto `1..n` satisfies AC-4, and dealing by seat keeps the rng's single decision
  the *ring*, so a player's own key class says nothing about where they sit in it.
  That is a design choice made deliberately rather than fallen into.
- **`table.clone(players)`** on the way out, so a caller mutating its own seat
  list cannot reach into an assignment already dealt.
- **`supplierOf` scans rather than storing an inverse**, because a second copy of
  σ could disagree with the first and the Contract names three fields. Correct
  call.

### The `unit` floor is raised, and it is the one gate this story changes

`floor | unit | 175` -> **197**, measured from this story's own run. GREEN made
the change, which is its to make; **the probe is GATES' and is recorded in
`## Gate probes`** - a floor nobody has watched fail is a number, not a gate.

**Resolved model of the GREEN dispatch:** `feature-developer`, planned `opus` by
`models.conf`, dispatched with `model: opus`, resolved to **Opus 5**
(`claude-opus-5`) and confirmed by the agent from inside the dispatch.

---


---

## PO ruling on the return to RED from REVIEW

**The return was correct and the correction is accepted.** PR #10's `gates` job
failed while every local signal was green. The failure was **not** in SEAT-001's
work: `boundaries` passed, `Ring.luau` was untouched, and `lune run test` was
`197 passed, 0 failed` throughout. It was `.claude/tests/project-counters.test.sh`
- `HARNESS-006`'s suite - whose file-count literals SEAT-001 had legitimately
made stale by adding one source file and four test files.

This is the harness's own prescribed path rather than a judgement call: *a gate
failure whose only legal fix is a write the current phase forbids is a return to
RED.* REVIEW may write docs and harness; the fix is a test file.

### The correction, verified rather than accepted

| Constant | Was | Now |
|---|---|---|
| `BASE_FORMAT`, `BASE_LINT` | 38 | **43** |
| `BASE_TYPECHECK` | 7 | **8** |
| `NARROW_FORMAT`, `NARROW_LINT` | 7 | **8** |
| `NARROW_TYPECHECK` | 5 | **5** (unchanged) |

`NARROW_TYPECHECK` not moving is the detail that makes the rest credible: it
counts `src/shared` alone, and SEAT-001 added under `src/server/seats`. A
correction that moved all six would have been a correction applied by pattern
rather than by measurement.

**Orchestrator's own run after the fix:** `project-counters: 40 passed, 0 failed`,
`lune run test` `197 passed, 0 failed`, `gates.sh --fast` all five PASS at
`43 / 43 / 8 / 197`.

### The probe, reproduced independently

A corrected assertion runs for the first time against code that already satisfies
it, so "watched to fail" is replaced rather than waived. RED's probe B was re-run
by the orchestrator:

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's|{n++; next}|{if ($0 !~ /seats/) n++; next}|' \
        -- bash .claude/tests/project-counters.test.sh

        FAIL format reports 43 files on the unmodified tree
        FAIL narrowing the format target to src reports 8, not 43
        FAIL AC-2: format counts the untracked file (43 -> 44)
        FAIL format does not count the ignored file (still 43)
    project-counters: 36 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/.claude_harness_project.conf.20260917T050203Z.2223710.bak) ===

`36 passed, 4 failed` to the test. **The probe is well chosen**: it hides exactly
`seats`, the file SEAT-001 added, so it demonstrates the suite can still see the
change that made it stale - which a probe hiding some unrelated file would not.
Probe A covers the `lint`/`typecheck` family, which shares a different counter;
7 + 4 = 11, the exact set that was red, and the two families are disjoint.

### Ruling — the assertion names were rightly updated too

RED also changed assertion *names* carrying the old numbers
(`format reports 38 files` -> `43`). That is inside the remit, not outside it: a
failure message announcing 38 while asserting 43 is the **lying needle**
`rules.md` warns about, at the level of the string. Accepted. Every tolerance,
case and comparison is untouched; the diff is literals, comments and names.

### GREEN on re-entry was a no-op, verified rather than delegated

`git diff -- src` is empty and the suite is green, so there was nothing for a
feature developer to do. No dispatch was made: an agent given no work finds some.

### The real defect is the detection gap, and it is not this story's to fix

`gates.sh --fast` never invokes `.claude/tests/*`. Only `selftest.sh` and
`ci-local.sh` do, and neither is part of the per-story RED or GREEN procedure. So
a harness suite can go red from an ordinary product story and **every local
signal stays green until CI**. That is exactly what happened here, and it will
happen to the next story that adds a `.luau` file regardless of how those
expectations are computed.

Two candidate fixes, for the follow-up story rather than for this one:

1. **Put the harness suites into the fast loop.** Cheapest, closes the detection
   gap, changes no acceptance criterion. This alone would have caught it in RED.
2. Derive the expectations from `scripts/classify.sh --list` - an *independent*
   enumeration, so not self-referential the way re-deriving from the gate command
   under test would be. This slightly weakens `HARNESS-006` AC-7's claim and
   needs its own story and its own probe.

`HARNESS-006` is DONE with frozen criteria, so neither was done here. **Filed as a
follow-up.**

**Resolved model of the return dispatch:** `test-developer`, dispatched
`model: opus` and resolved to **Opus 5** - deliberately not the planned `fable`,
because a return to RED is a correction to an existing suite rather than writing
a partitioned brief, which is the case `models.conf` measured.

---

## Test plan

Two files apply the SAME checks: the real suite to `src/server/seats/Ring.luau`,
the controls suite to deliberately wrong generators. The checks live in one
helper so that neither copy can drift from the other.

| File | What it is |
|---|---|
| `tests/helpers/RingContract.luau` | AC-1..AC-7 and one Contract pin written once, as checks over a `ring` (anything with the four field functions) |
| `tests/helpers/RingStubs.luau` | a baseline single-cycle generator over the real `Rng` and nine controls, each ONE defect away from it (a factory over a defects table, as `RoundEndingStubs.luau` is) |
| `tests/server/ring_test.luau` | the checks applied to the real module - 12 tests, all 12 RED (the module does not exist) |
| `tests/server/ring_controls_test.luau` | the checks applied to the stubs - 10 tests, all green, every control OBSERVED to fire with its measured number pinned in the assertion |

### Criterion by criterion

| AC | Test (in `tests/server/ring_test.luau`) | Check | Status in RED |
|---|---|---|---|
| Contract | `Ring exports assign, lensOf, supplierOf and dependentOf as plain field functions` | inline | RED |
| Contract | `assign returns an Assignment carrying players, sigma and keyClass, and nothing the Contract does not name` | inline | RED |
| Contract | `assign draws from its own sub-stream - draws taken from the parent rng beforehand do not move the seats` | `assignDrawsFromItsOwnSubStream` | RED |
| AC-1 | `σ is a permutation of exactly the seated players with no fixed point, for every n in 3..6` | `sigmaIsAFixedPointFreePermutation` | RED |
| AC-2 | `the orbit of a player under σ visits all n players before returning - one cycle, never two, for every n in 3..6` | `sigmaIsASingleCycle` | RED |
| AC-3 | `the same seed and the same seated list produce an identical assignment` | `sameSeedSameAssignment` | RED |
| AC-3 | `different seeds produce at least two different rings over a sample of seeds` | `differentSeedsProduceDifferentRings` | RED |
| AC-4 | `each player holds exactly one key class and the key classes are the integers 1..n each used once` | `keyClassesAreOneToNEachOnce` | RED |
| AC-4 | `λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹` | `lensIsTheDependentsKeyClass` | RED |
| AC-5 | `over 10,000 seeds at n = 4 all six cyclic derangements appear and none takes more than 25% or less than 8%` | `ringsOfFourAreUniformlyDistributed` | RED |
| AC-6 | `assign raises for 0, 1 or 2 seated players rather than returning a degenerate ring, and succeeds at exactly 3` | `fewerThanThreeSeatedRaises` | RED |
| AC-7 | `the input list is not mutated and the result keeps the input's seat order, for every n in 3..6` | `inputIsNotMutatedAndSeatOrderIsKept` | RED |

### Level, and why

Unit, everywhere. `assign` is a pure function of `(players, rng)` and every
criterion is a statement about one call of it or a tally over many. There is no
caller to integrate against (`RoundService` does not exist - PO decision 2) and
nothing a user walks through.

### The oracle partition, honoured

- **Settled (AC-1, AC-2, AC-4, AC-6, AC-7):** read out of `roles.md` §2 and §6
  and `tuning.md` §1. No seating scheme is invented: how the cycle is built,
  which player gets which key class and what the `n < 3` error says are all
  left to GREEN.
- **Mechanical with a control (AC-3):** two halves, two checks, and the
  seed-ignoring stub passes the first and fails the second.
- **Oracle-free (AC-5):** 10,000 seeds, 8-25%, exactly as the Contract writes
  them. `RingContract.SAMPLE`, `LOW_SHARE` and `HIGH_SHARE` are exported so the
  controls quote the same constants the check uses. I did not find the band or
  the sample wrong: the baseline's measured shares sit at 16.5-16.8% (the
  standard deviation of a 1/6 share over 10,000 draws is 0.37 pp, so 8% is 23σ
  below uniform) and the constant generator scores 100%/0%.

### Design choices RED made, and where they are recorded

- **Seed sample for the per-seed checks: 64 per n** (`RingContract.SEEDS`,
  1001..1064). AC-2 asks for enough seeds that the plain-derangement control
  cannot pass by luck; at `n = 4` that control is a cycle 2/3 of the time, so
  the chance all 64 land on a cycle is (2/3)^64 ≈ 5e-12. Measured: it produced
  two 2-cycles on 22 of the 64 seeds at `n = 4`. At `n = 3` both derangements
  are cycles, so AC-2 cannot fire there and AC-1 does the work - the check's
  message says so per n.
- **AC-6's observable is RAISING.** Chosen over `nil` or a sentinel because the
  Contract's signature returns an `Assignment` and nothing else, `Rng.nextInteger`
  in the same codebase raises on an empty range for the stated reason
  ("returning nil would move the failure somewhere else"), and every degenerate
  result - a swap at 2, a fixed point at 1, `{}` at 0 - is a table that LOOKS
  like an Assignment. The message text is not constrained. Exactly 3 must
  succeed.
- **Seat names are unsorted and unnumbered** (`kim, zed, amy, bob, eve, raj`),
  so an implementation that sorts its players fails AC-7 rather than passing it
  against `p1..p4`. The six cyclic derangements for AC-5 are built from that
  seat order, not written down.
- **AC-7 compares the result's seat order against the SNAPSHOT of the input**,
  not the live list, so a generator that shuffles in place and hands the same
  table back fails both halves rather than passing the second by aliasing.
- **One Contract pin beyond the seven criteria**: draws taken from the parent
  rng before `assign` do not move the seats. That is the observable form of "use
  `rng:derive("seats")`", and it is what lets M3's instance generator draw from
  `derive("instance")` without shifting a seat. The LABEL is not pinned.
- **Violations are accumulated and asserted once** in every check, so one run
  names every (n, seed) case that broke rather than the first.

### Edges covered

- every `n` in 3, 4, 5, 6 for AC-1, AC-2, AC-3, AC-4, AC-7 and the pin;
- the boundary at 3 from both sides: 0, 1, 2 raise; 3 succeeds (AC-6);
- σ that is not even a function (`nil` image) is reported, not looped on
  (`orbit` is bounded);
- the Out-of-scope "lens contents" non-goal is pinned cheaply: `Assignment`
  carries exactly `players`, `sigma`, `keyClass` and nothing else.

## Handoff: RED -> GREEN

### The command

    export PATH="$HOME/.rokit/bin:$PATH" && cd /c/Users/ryanc/Projects/first-roblox && lune run test

There is no per-file filter in the runner; the whole suite takes ~15 s locally.
Lines for this story: `grep -E "tests/server/ring_"`.

### The verbatim failure output (RED, 2026-09-16)

Before this story: `175 passed, 0 failed`. After:

      FAIL  tests/server/ring_test.luau :: AC-1: σ is a permutation of exactly the seated players with no fixed point, for every n in 3..6
            C:\Users\ryanc\Projects\first-roblox\tests\server\ring_test:40: src/server/seats/Ring.luau did not load: error requiring module "../../src/server/seats/Ring": could not resolve child component "seats"
      FAIL  tests/server/ring_test.luau :: AC-2: the orbit of a player under σ visits all n players before returning - one cycle, never two, for every n in 3..6
      FAIL  tests/server/ring_test.luau :: AC-3: different seeds produce at least two different rings over a sample of seeds
      FAIL  tests/server/ring_test.luau :: AC-3: the same seed and the same seated list produce an identical assignment
      FAIL  tests/server/ring_test.luau :: AC-4: each player holds exactly one key class and the key classes are the integers 1..n each used once
      FAIL  tests/server/ring_test.luau :: AC-4: λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹
      FAIL  tests/server/ring_test.luau :: AC-5: over 10,000 seeds at n = 4 all six cyclic derangements appear and none takes more than 25% or less than 8%
      FAIL  tests/server/ring_test.luau :: AC-6: assign raises for 0, 1 or 2 seated players rather than returning a degenerate ring, and succeeds at exactly 3
      FAIL  tests/server/ring_test.luau :: AC-7: the input list is not mutated and the result keeps the input's seat order, for every n in 3..6
      FAIL  tests/server/ring_test.luau :: Contract: Ring exports assign, lensOf, supplierOf and dependentOf as plain field functions
      FAIL  tests/server/ring_test.luau :: Contract: assign draws from its own sub-stream - draws taken from the parent rng beforehand do not move the seats
      FAIL  tests/server/ring_test.luau :: Contract: assign returns an Assignment carrying players, sigma and keyClass, and nothing the Contract does not name
    185 passed, 12 failed

Every one of the twelve carries the identical second line (elided above after
the first): `ring_test:40: src/server/seats/Ring.luau did not load: ... could
not resolve child component "seats"`. The other 185 - the 175 pre-existing tests
and the 10 new controls - pass. No collision with an existing test.

**Why this is the right failure.** The module is the first thing the story
requires, so its absence is the correct first red. The `pcall` at the top of
`ring_test.luau` and the re-check inside each test turn that absence into one
failure per criterion rather than one LOAD FAIL for the file, which is what
tells GREEN, once the module loads, which behaviours are still missing - at that
point each test fails on its own assertion, whose text names the criterion.

### `bash scripts/gates.sh --fast` at the end of RED

    PASS         format (0s, observed 42)
    PASS         lint (0s, observed 42, floor 1)
    PASS         typecheck (3s, observed 7)
    FAIL         unit (12s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (1s, observed 20721)

The unit gate fails on the twelve assertions above and nothing else: no timeout,
no config error, no lint rule tripped by a test file. The tests are admissible.

### The export shape the tests already pin

Nothing below is a suggestion. Each name is already called by a test, so getting
it wrong is a failing test rather than a debate.

    src/server/seats/Ring.luau            -- required as "../../src/server/seats/Ring" from tests/server/

      Ring.assign(players: { PlayerId }, rng: Rng.Rng) -> Assignment
          -- plain field function, called with a dot: Ring.assign(players, rng)
          -- MUST RAISE (error) when #players < 3; must succeed at 3
          -- must not mutate `players`
          -- must draw from a derived sub-stream (rng:derive("seats") per the
          --   Contract): five nextNumber() draws on the parent before the call
          --   must not change the result
      Ring.lensOf(assignment: Assignment, playerId: PlayerId) -> KeyClass
          -- == assignment.keyClass[assignment.sigma[playerId]]
      Ring.dependentOf(assignment: Assignment, playerId: PlayerId) -> PlayerId
          -- == assignment.sigma[playerId]                      (σ, the successor)
      Ring.supplierOf(assignment: Assignment, playerId: PlayerId) -> PlayerId
          -- the q with assignment.sigma[q] == playerId          (σ⁻¹, the predecessor)

      Assignment = {
          players:  { PlayerId },              -- deep-equal to the input, same order
          sigma:    { [PlayerId]: PlayerId },  -- keys are EXACTLY the seated players
          keyClass: { [PlayerId]: KeyClass },  -- keys are EXACTLY the seated players;
                                               -- values are integers, sorted == {1..n}
      }
      -- and NO other field: the shape test enumerates the keys and fails on an
      -- extra one (lens contents are M3; SEAT-002 replicates this shape as is).

`PlayerId` is a `string` in the tests (as `PhaseMachine.PlayerId` already is).
`Rng.Rng` is `src/shared/Rng.luau`'s exported type; the tests construct it with
`Rng.fromSeed(seed)`, a fresh instance per call.

**Not constrained - the implementer's choice:**

- which player holds which key class (any bijection onto `1..n`; the stub uses
  seat index, and nothing asserts that);
- the text of the error at `n < 3`;
- whether `assignment.players` is a fresh table or the input reference (only
  non-mutation and equal order are pinned; a clone is the obvious safe choice);
- the derive label (the pin observes independence from parent draws, not the
  string `"seats"`);
- the construction, as long as the distribution passes AC-5 - the Contract's
  shuffle-then-link is the one that does.

### Every negative control, with the value it measured

No assertion in `ring_test.luau` has run - the file fails at require. The
controls in `ring_controls_test.luau` DID run, against `RingStubs` over the real
`Rng`, and these are their measurements (also taken independently with a
scratch script outside the runner, now deleted, with identical numbers).
**Confirming the baseline's numbers against the shipped module is GREEN's job**,
in particular the AC-5 tally. The seed for AC-5 is `i` for `i = 1..10000`; the
per-seed checks use `1001..1064`; seat names are `kim, zed, amy, bob(, eve, raj)`.

| Control (stub) | Check | Threshold | Expected | Measured in RED |
|---|---|---|---|---|
| baseline (`correct`) | AC-5 tally over 10,000 | each in [800, 2500] | ~1667 each | 1683 / 1651 / 1666 / 1677 / 1661 / 1662 (16.5-16.8%), 0 non-cyclic |
| `plainDerangement` (mutation 1) | AC-2 | 0 non-cycles | ~1/3 at n=4 | **n = 4: 22 of 64**; n = 5: 24 of 64; n = 6: 31 of 64; n = 3: 0 of 64; 77 of 256 total |
| `plainDerangement` | AC-5 | each in [800, 2500] | ~11.1% each, passes | 1100 / 1129 / 1107 / 1109 / 1119 / 1105 (11.0-11.3%), 3331 non-cyclic - **passes**, as `## Notes` predicts |
| `canonical` (mutation 2) | AC-5 | all 6 present | 1 at 100%, 5 absent | `kim>zed,zed>amy,amy>bob,bob>kim = 10000 (100.0%)`, 5 ABSENT |
| `canonical` | AC-3 second half | >= 2 distinct rings | 1 | 1 distinct ring at every n over 16 seeds |
| `seedIgnoring` | AC-3 second half | >= 2 distinct rings | 1 | 1 distinct ring at every n over 16 seeds |
| `seedIgnoring` | AC-5 | all 6 present | 1 at 100%, 5 absent | `kim>amy,zed>bob,amy>zed,bob>kim = 10000 (100.0%)`, 5 ABSENT |
| `swappedAccessors` (mutation 3) | AC-4 direction | 0 cases | every case | 32 of 32 (n, seed) cases; message names `dependentOf is σ, the ring-successor` |
| `lensFromSupplier` | AC-4 direction | 0 cases | every case | 32 of 32; first line `λ(kim) = 2, but k(σ(kim)) = k(amy) = 3 ... the supplier zed holds 2` |
| `anyPermutation` | AC-1 | 0 cases | ~2/3 with a fixed point | 168 of 256 |
| `anyPermutation` | AC-2 | 0 cases | most | 203 of 256 (n = 3: 43, 4: 49, 5: 54, 6: 57) |
| `anyPermutation` | AC-5 | each >= 800 | ~4.2% each (6 of 24 permutations) | 411-420 each, all 6 below 8% |
| `degenerate` | AC-6 | raises at 0, 1, 2 | returns | n = 2 returned the swap `sigma = { kim = "zed", zed = "kim" }`; n = 1 `sigma = { kim = "kim" }`; n = 0 `{}` |
| `inPlace` | AC-7 | 0 violations | both halves | 6 violations (both halves at 3 of the 4 values of n; the seed-31337 shuffle at one n happened to be the identity) |
| `inPlace` | AC-3 first half, AC-5, sub-stream pin | - | collateral | all three fire: 11 AC-3 cases; AC-5 five absent; pin at 4 values of n. The defect corrupts the shared fixture list between calls |
| `parentDrawing` | sub-stream pin | 0 differences | differs | fires at all 4 values of n; every criterion AC-1..AC-7 passes for it |

Every control was also asserted to PASS the checks it should pass (the
`passesTheStructuralChecks` helper in the controls file), so each failure is
attributable to the one defect.

### Mutation table for acceptance (predicted reds in `ring_test.luau`)

From the measured stub behaviour above; each row is one plausible wrong
implementation of the real module.

| Wrong implementation | Tests red | Which |
|---|---|---|
| 1. rejection-sampled plain derangement (`## Notes` 1) | 1 | AC-2 |
| 2. constant canonical ring, rng ignored (`## Notes` 2 - run first) | 2 | AC-5; AC-3 (different seeds) |
| 3. `supplierOf` / `dependentOf` swapped (`## Notes` 3) | 1 | AC-4 (λ = k(σ(p))) |
| 4. `lensOf` reads the supplier's key class | 1 | AC-4 (λ = k(σ(p))) |
| 5. σ is a plain shuffle, fixed points allowed | 3 | AC-1; AC-2; AC-5 |
| 6. no minimum count | 1 | AC-6 |
| 7. shuffles the input in place | 4 | AC-7; AC-3 (same seed); AC-5; Contract sub-stream pin |
| 8. shuffles with the parent rng, no `derive` | 1 | Contract sub-stream pin |
| 9. a fixed internal seed instead of the rng | 2 | AC-3 (different seeds); AC-5 |
| 10. key classes `0..n-1` or non-integers | 1 | AC-4 (keys) |
| 11. an extra field on `Assignment` | 1 | Contract shape |

Rows 1-9 are measured on the stubs; rows 10-11 are read off the checks and were
not stubbed.

### Cost of AC-5, measured (local only; there is no CI number yet)

- One `ringsOfFourAreUniformlyDistributed` run over the baseline (10,000
  `assign` calls at n = 4, each a `derive` + a 4-element shuffle + tallying):
  **25.7 / 30.7 / 28.5 / 33.6 / 30.8 ms** over five runs, `os.clock()`, plain
  `lune run`, on this Windows desktop.
- The controls file runs that check ten times (once per stub) - roughly 0.3 s in
  total. The real suite will run it once more.
- `unit` gate wall time: 12 s in `--fast` with the 22 new tests, against ~13 s for
  175 before. Whole `lune run test`: 15.1 s (the suite's cost is dominated by
  the tests that spawn `selene`/`luau-lsp`, not by this story).
- The runner has no per-test timeout, so there is no budget to size; the number
  is here so that a later CI log can be compared against it. Nothing in this
  story needs `slow` or a `ci-factor` line.

### Notes for the implementer

- Everything the Contract says stands unamended. I found nothing in it wrong.
- `Rng:shuffle` is non-mutating (PO decision 3), so AC-7's non-mutation half is
  inherited if you shuffle the input and never write into it. The stub returns
  `table.clone(players)` as `assignment.players`; do the same or better.
- AC-5's baseline tally in RED (16.5-16.8%) was produced by exactly the
  Contract's construction over the real `Rng` with seeds `1..10000` and
  `derive("seats")`. If your module lands outside 8-25%, the construction or the
  sub-stream differs from that - do not move the band; report it (PO decisions 3
  and 7).
- The shape test fails on any field beyond `players`, `sigma`, `keyClass`. If
  GREEN needs a fourth field, that is a Contract question for the PO, not a
  reason to edit the test.
- `## Notes` says to **raise the `unit` floor** to the new real count. When
  everything is green that count will be 197 (175 + 10 controls + 12); the floor
  in `.claude/harness/project.conf:444` is 175 today. That file is `harness`,
  writable in GREEN.
- Nothing passed on arrival in `ring_test.luau`; there is no `## Regressions`
  entry because there is no corrected assertion to earn. The controls suite is
  green by design and is itself the observation that each check fires.
- The `## Deferred verifications` block stays as it was: nothing is deferred.
  Both story-named controls ran.

### Files touched in RED

- `tests/helpers/RingContract.luau` (new)
- `tests/helpers/RingStubs.luau` (new)
- `tests/server/ring_test.luau` (new)
- `tests/server/ring_controls_test.luau` (new)
- `docs/backlog/stories/SEAT-001.md` (this section and `## Test plan`)

`git diff -- src` is empty; `.claude/state/mutations/` holds no `.bak`. No
manifest was touched: the story needs no test dependency.

---

## GREEN: control values confirmed

`src/server/seats/Ring.luau` is written from the `## Contract`, not from
`tests/helpers/RingStubs.luau`. Every number below was re-measured **against the
shipped module**, not merely observed green: RED measured its controls against
the stubs, and a control can pass while measuring something else.

The clean baseline: `lune run test` -> **`197 passed, 0 failed`** (175
pre-existing + the 22 this story adds), against `185 passed, 12 failed` at the
end of RED. **No pre-existing test went red**, and all twelve of this story's
assertions are green against the real module.

The failure GREEN started from was reproduced first, not taken on report: all
twelve failed with `ring_test:40: src/server/seats/Ring.luau did not load: ...
could not resolve child component "seats"`, exactly as the handoff records.

Every mutation below went through `bash scripts/mutate.sh`, which restored the
file and verified the restore with `cmp` each time. No `sed -i` was used, and
`.claude/state/mutations/` holds no `.bak`.

### The AC-5 baseline tally, re-measured against the shipped module

This is the row that matters: a module that is correct but BIASED passes every
structural criterion and fails only AC-5. Measured with the check's own
`RingContract.tallyRingsOfFour`, seeds `1..10000`, `n = 4`, seats
`kim, zed, amy, bob`, driven from a throwaway script under the gitignored
`build/` (since deleted):

| Ring | RED (stub baseline) | GREEN (shipped `Ring.luau`) |
|---|---|---|
| `kim>amy,zed>bob,amy>zed,bob>kim` | 1683 | **1683** (16.8%) |
| `kim>amy,zed>kim,amy>bob,bob>zed` | 1651 | **1651** (16.5%) |
| `kim>bob,zed>amy,amy>kim,bob>zed` | 1666 | **1666** (16.7%) |
| `kim>bob,zed>kim,amy>zed,bob>amy` | 1677 | **1677** (16.8%) |
| `kim>zed,zed>amy,amy>bob,bob>kim` | 1661 | **1661** (16.6%) |
| `kim>zed,zed>bob,amy>kim,bob>amy` | 1662 | **1662** (16.6%) |
| not a single cycle at all | 0 | **0** |

**Identical, ring for ring, with no divergence to explain.** That is stronger
than "within the band": the shipped module consumes `derive("seats")` exactly as
the Contract's construction does, so it draws the same stream as RED's baseline
and lands on the same ring for every one of the 10,000 seeds. 16.5-16.8% against
a uniform 16.7%, comfortably inside the untouched 8-25% band.

Cost: **25.0 ms** for the 10,000-seed tally, against RED's `25.7 / 30.7 / 28.5 /
33.6 / 30.8 ms`. No `slow` line is warranted.

Direction, spot-checked on three seeds so the sign is read rather than inferred
(`k` is the seat index, so `kim, zed, amy, bob` hold `1, 2, 3, 4`):

    seed 1: kim>amy,zed>bob,amy>zed,bob>kim | k(kim)=1 λ(kim)=3 dependentOf(kim)=amy supplierOf(kim)=bob
    seed 2: kim>zed,zed>amy,amy>bob,bob>kim | k(kim)=1 λ(kim)=2 dependentOf(kim)=zed supplierOf(kim)=bob
    seed 3: kim>bob,zed>amy,amy>kim,bob>zed | k(kim)=1 λ(kim)=4 dependentOf(kim)=bob supplierOf(kim)=amy

`λ(kim) = k(σ(kim))` in each: σ(kim) is `amy`/`zed`/`bob` and k of those is
3/2/4. `p` sends facts TO `dependentOf(p)`.

### The other fifteen control rows

They are measurements over `RingStubs`, not over the shipped module, so the
shipped module cannot move them - and they are **not** unverified claims: every
one is pinned as a literal in the assertion text of
`tests/server/ring_controls_test.luau` (`22 of 64`, `168 of 256`, `203 of 256`,
`32 of 32`, `10000 (100.0%)`, the verbatim degenerate rings), and all ten of
those tests are green within the 197. Two were additionally reproduced against a
mutated **real** module below - mutation 1 reproduces `plainDerangement`'s per-n
counts exactly, and mutation 2 reproduces `canonical`'s 100%/0% split - which is
the part RED could not do.

### The `## Notes` mutations, measured

**Mutation 2 - a constant canonical ring, the rng ignored.** Run first, as
`## Notes` asks: it is the one a naive suite is blind to.

    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's|local order = rng:derive(SEATS_LABEL):shuffle(players)|local order = table.clone(players)|' \
        -- lune run test
      FAIL  tests/server/ring_test.luau :: AC-3: different seeds produce at least two different rings over a sample of seeds
            ...\tests\helpers\RingContract:292: AC-3: different seeds did not produce different rings, so the seed is not being used, at 4 value(s) of n:
      FAIL  tests/server/ring_test.luau :: AC-5: over 10,000 seeds at n = 4 all six cyclic derangements appear and none takes more than 25% or less than 8%
            ...\tests\helpers\RingContract:542: AC-5: over 10000 seeds at n = 4, 5 of the 6 cyclic derangements never appeared and 1 fell outside the 8.0%-25.0% band (uniform is 16.7%). roles.md §2: the ring's shape is itself variance:
      kim>amy,zed>bob,amy>zed,bob>kim = 0 (0.0%)  <- ABSENT
      kim>amy,zed>kim,amy>bob,bob>zed = 0 (0.0%)  <- ABSENT
      kim>bob,zed>amy,amy>kim,bob>zed = 0 (0.0%)  <- ABSENT
      kim>bob,zed>kim,amy>zed,bob>amy = 0 (0.0%)  <- ABSENT
      kim>zed,zed>amy,amy>bob,bob>kim = 10000 (100.0%)  <- above 25.0%
    195 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_seats_Ring.luau.20260917T032553Z.1861638.bak) ===

**2 red, exactly the two the table predicts** (AC-5; AC-3 different seeds), and
AC-1, AC-2, AC-4, AC-6, AC-7 and all three Contract pins stay green - which is
the point of the row. The tally is `canonical`'s RED measurement reproduced
against the real module: `kim>zed,zed>amy,amy>bob,bob>kim = 10000 (100.0%)`,
five ABSENT.

**Mutation 1 - a rejection-sampled plain derangement, no cycle constraint.** Two
substitutions in one expression: the first samples a derangement of the seat
order, the second makes the link step write it instead of the ring.

    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's|local order = rng:derive(SEATS_LABEL):shuffle(players)|local sub = rng:derive(SEATS_LABEL) local order = sub:shuffle(players) local images = order while true do local bad = false for i, p in players do if images[i] == p then bad = true end end if not bad then break end images = sub:shuffle(players) end|; s|sigma\[p\] = order\[(i % #order) + 1\]|sigma[players[i]] = images[i] local _ = p|' \
        -- lune run test
      FAIL  tests/server/ring_test.luau :: AC-2: the orbit of a player under σ visits all n players before returning - one cycle, never two, for every n in 3..6
            ...\tests\helpers\RingContract:229: AC-2: σ is not a single n-cycle in 77 of 256 (n, seed) cases [n = 3: 0 of 64 seeds; n = 4: 22 of 64 seeds; n = 5: 24 of 64 seeds; n = 6: 31 of 64 seeds]. Two disjoint cycles are two independent games sharing a map (roles.md §2):
      n = 4, seed 1006: the orbit of kim is kim → zed (length 2 of 4); σ = kim>zed,zed>kim,amy>bob,bob>amy
    196 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_seats_Ring.luau.20260917T032629Z.1864709.bak) ===

**1 red, AC-2, as predicted** - and the per-n breakdown `0 / 22 / 24 / 31`,
`77 of 256`, is `plainDerangement`'s RED measurement to the case. AC-5 stays
green for it (~11% per ring), which is the row's other half: AC-5 does not catch
this defect and AC-2 does.

**Mutation 3 - `supplierOf` and `dependentOf` swapped.** Expressed as a
three-step rename through a temporary name, so the two bodies exchange places.

    $ bash scripts/mutate.sh src/server/seats/Ring.luau \
        's|function Ring.dependentOf|function Ring.__swapped|; s|function Ring.supplierOf|function Ring.dependentOf|; s|function Ring.__swapped|function Ring.supplierOf|' \
        -- lune run test
      FAIL  tests/server/ring_test.luau :: AC-4: λ(p) = k(σ(p)) - the lens reads the dependent's key class, dependentOf is σ and supplierOf is σ⁻¹
            ...\tests\helpers\RingContract:443: AC-4: λ(p) = k(σ(p)) does not hold, or supplierOf/dependentOf do not read σ⁻¹/σ, in 32 case(s):
      n = 3, seed 1001 (σ = kim>amy,zed>kim,amy>zed):
        dependentOf(kim) = "zed", but σ(kim) = "amy" - dependentOf is σ, the ring-successor
        supplierOf(kim) = "amy", but σ⁻¹(kim) = "zed" - supplierOf is σ⁻¹, the ring-predecessor
        supplierOf(dependentOf(kim)) = "zed", not kim
    196 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_seats_Ring.luau.20260917T032701Z.1867585.bak) ===

**1 red, AC-4's direction assertion, as predicted**, in 32 of 32 (n, seed)
cases - `swappedAccessors`' RED number exactly. The story's worry is answered
against the shipped module: AC-4 *does* pin the direction, so `SEAT-003` cannot
inherit a silent sign error.

**Reality against the 11-row table: no divergence in any of the three rows run.**
Predicted 1 / 2 / 1 red; measured 1 / 2 / 1, and in each case the named tests and
no others. Rows 4-11 were not run - `## Notes` names three, and rows 4-9 are
already exercised as stubs by the ten green control tests.

### Implementation notes worth the next reader's attention

- **The minimum seated count is READ from `Tuning.session.min_players_to_continue`
  (3), not written as a literal.** `RoundConfig.luau` declines the same
  temptation with the same reasoning: a literal here would be a second place for
  a `tuning.md` constant to live. `assign`'s Contract signature is
  `(players, rng)`, so there is no injection point; it is read at load.
- **Key classes are dealt by SEAT index, not by ring position.** `tuning.md` §2
  specifies only "one class per player", so any bijection onto `1..n` satisfies
  AC-4 and nothing asserts which. Seat index keeps the rng's single decision the
  RING and nothing else, so a player's own key class says nothing about where
  they sit in it.
- **`supplierOf` searches `assignment.players` rather than storing an inverse
  map.** A second copy of σ could disagree with the first, and the Contract names
  three fields. The scan is bounded by `players_max` = 6. It raises for a player
  with no supplier - unreachable for an assignment this module dealt - which is
  the same choice `Rng.nextInteger` makes on an empty range.
- **`assignment.players` is `table.clone(players)`**, so AC-7's non-mutation is
  structural rather than incidental, and a later caller mutating its own seat
  list cannot reach inside an assignment already dealt.
- Nothing was escalated. The Contract stands unamended, no fourth field on
  `Assignment` was needed, no criterion was found unsatisfiable, and no test was
  touched: `git diff -- tests` is empty.

### `bash scripts/gates.sh --fast` at the end of GREEN

    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (2s, observed 8)
    PASS         unit (12s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (0s, observed 25103)

    changes: 1 changed source path(s), all exercised by a required gate
    All required gates passed (5 ran, 1 unconfigured, 0 known).

43 files observed, up from 42; the build grew from 20,721 to 25,103 bytes, which
is the new module arriving in `ServerScriptService.Server`. A partial run is not
a record, and the full `gates.sh` belongs to GATES.

**The `unit` floor is raised 175 -> 197** in `.claude/harness/project.conf`, with
the reason recorded beside it, as `## Notes` asks.

### Files touched in GREEN

- `src/server/seats/Ring.luau` (new - the only source file)
- `.claude/harness/project.conf` (the `unit` floor, 175 -> 197)
- `docs/backlog/stories/SEAT-001.md` (this section)

**Resolved model of the GREEN dispatch:** `feature-developer`, planned `opus` by
`models.conf`, dispatched with no model override, so the agent definition's
`model: opus` and the plan agreed. Resolved to **Opus 5** (`claude-opus-5`),
confirmed from inside the dispatch.

---

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-17T05:27:26Z
    commit: 03bd458
    tree:   d6d2554b37cccd1252949ddb9876007f3748cc8c
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (2s, observed 43)
    PASS         lint (3s, observed 43, floor 1)
    PASS         typecheck (12s, observed 8)
    PASS         unit (63s, observed 197, floor 197)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (2s, observed 25103)
    UNCONFIGURED mutation

## Gate probes

This story changes exactly one gate: the `unit` floor, `175` -> `197`. Nothing
else - no gate is added, no command changes, no `evidence` line moves. So there
is one probe, and it is the floor.

**A floor nobody has watched fail is a number, not a gate.** It was therefore set
one ABOVE the real count first, and the gate run:

    $ sed -i-style edit via awk: floor | unit | 197  ->  198
    $ bash scripts/gates.sh --gate unit

    FAIL         unit (12s, did 197 units of work, below the floor of 198 in project.conf) -> .claude/state/gate-logs/unit.log
    changes: 1 changed source path(s), all exercised by a required gate
    1 required gate(s) failed.

The failure names the measured count, the floor and the file, which is what makes
it actionable rather than merely red. Then set back to 197 and re-audited:

    $ bash scripts/gates.sh --audit
    Manifest audit passed.

**Why the floor is the only gate probe this story needs.** `format`, `lint`,
`typecheck` and `build` are unchanged in command and in evidence line; their
probes belong to `BOOT-001`, which broke each one on purpose and recorded it, and
to `HARNESS-006`, which re-probed all three counters after rewriting them. The
`unit` gate's *command* is likewise unchanged - only its floor moved.

**What the floor is for on this stack, restated because it is load-bearing here.**
`coverage` is UNCONFIGURED (`stack.md` section 4 records why), so the floor is the
only thing that notices a suite quietly shrinking. This story adds 22 tests; if a
later story deletes twelve of them the suite still passes, the evidence regex
still matches, and only the floor complains. That is why it moves in the story
that adds the tests rather than later.

## Regressions

### GATES -> RED: `.claude/tests/project-counters.test.sh` pinned a tree that no longer exists

**What was wrong.** HARNESS-006's counter suite asserts the project's `.luau`
file counts against the **live tree**, and holds the expected values as
module-level literals (`BASE_FORMAT`, `BASE_LINT`, `BASE_TYPECHECK`,
`NARROW_FORMAT`, `NARROW_LINT`, `NARROW_TYPECHECK`). SEAT-001 legitimately added
`src/server/seats/Ring.luau` and four test files, so every literal derived from
`src tests lune` or from `src` went stale and **11 of the suite's 40 assertions
failed**. The counters were reporting correctly; the numbers beside them were a
description of the tree as it stood at HARNESS-006.

This is not a weakening papered over. It is the same class of act as this story
already performed on the `unit` floor (197): a settled literal that describes the
tree has to move in the story that changes the tree.

**How it was found, and why nothing local caught it.** CI's `gates` job failed on
PR #10 while every local gate and `lune run test` passed. `scripts/gates.sh
--fast` does not run the harness suites at all - only `scripts/selftest.sh` and
`scripts/ci-local.sh` do, and neither is part of the RED/GREEN inner loop. So the
whole story could go green locally with this suite red. That is a gap in the
loop, not a property of this story; see "Opinion" at the end of this section.

**What it asserts now.** The same assertions, against re-measured literals. Each
value was read out of the gate command's **own evidence line**, by running the
command from `.claude/harness/project.conf` verbatim (and, for the narrowing
cases, with the one path substitution the suite itself makes):

| Constant | Was | Now | Command it was measured with | Evidence line |
|---|---|---|---|---|
| `BASE_FORMAT` | 38 | **43** | `gate \| format` unmodified (`stylua --check -v src tests lune \| awk ...`) | `stylua over 43 files` |
| `BASE_LINT` | 38 | **43** | `gate \| lint` unmodified (`selene src tests lune && ...`) | `selene over 43 files` |
| `BASE_TYPECHECK` | 7 | **8** | `gate \| typecheck` unmodified (`luau-lsp analyze ... src && ...`) | `analyze over 8 files` |
| `NARROW_FORMAT` | 7 | **8** | format with `src tests lune` -> `src` | `stylua over 8 files` |
| `NARROW_LINT` | 7 | **8** | lint with `src tests lune` -> `src` | `selene over 8 files` |
| `NARROW_TYPECHECK` | 5 | **5** (unchanged) | typecheck with `src` -> `src/shared` | `analyze over 5 files` |

The arithmetic is consistent and was cross-checked against the file list: `src`
holds 8 `.luau` files (the 7 of HARNESS-006 plus `src/server/seats/Ring.luau`),
`tests` + `lune` hold 35, and 8 + 35 = 43. `src/shared` is untouched by this
story, which is why `NARROW_TYPECHECK` is the one literal that did not move - and
both probes below confirm it by leaving that assertion green.

Nothing else in the suite changed: no assertion was removed, relaxed or skipped,
no tolerance widened, and the derived cases (`BASE_* + 1` for the untracked
scratch file, `BASE_*` unchanged for the ignored one) still derive from the
literals rather than being written out. Assertion *names* carrying the old
numbers were updated with them - a name reading "format reports 38 files" beside
an assertion demanding 43 is a failure message that lies - and the comment above
the constants now says explicitly that these track the tree, that they move when
it grows, and how to re-measure them.

**Before the fix:**

    $ bash .claude/tests/project-counters.test.sh
    project-counters: 29 passed, 11 failed

**After the fix:**

    $ bash .claude/tests/project-counters.test.sh
    project-counters: 40 passed, 0 failed

### Earning the corrected assertions: two mutation probes

"Watch it fail" cannot apply - these assertions run for the first time against a
tree that already satisfies them, so they are green on arrival and would be green
if they asserted nothing. Both probes therefore break the *specific* behaviour the
corrected literals pin: **the reported count is the number of `.luau` files the
tool was actually handed for its target**. Each removes exactly one file from a
counter - `src/server/seats/Ring.luau`, the file SEAT-001 added and the reason the
literals moved - so a probe that stayed green would prove the suite cannot see the
very change that made it stale.

Two probes rather than one because no single `sed` expression reaches all three
counters: `format` counts from **stylua's own `-v` output** through `awk`, while
`lint` and `typecheck` share a `git ls-files` counter. Probe A reaches the shared
one (7 assertions, both the `BASE_*` and `NARROW_*` families); probe B reaches
stylua's (4 assertions, both families). 7 + 4 = 11, which is exactly the set that
was red before the fix.

#### Probe A - the shared `git ls-files` counter (lint + typecheck)

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's|\*\.luau) if|*seats/*.luau) ;; *.luau) if|g' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (2 line(s) changed by s|\*\.luau) if|*seats/*.luau) ;; *.luau) if|g) ===
      350 - ... | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"
      350 + ... | while IFS= read -r f; do case "$f" in *seats/*.luau) ;; *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"
      376 - ... | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "analyze over $n files"
      376 + ... | while IFS= read -r f; do case "$f" in *seats/*.luau) ;; *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "analyze over $n files"

    === mutate: running bash .claude/tests/project-counters.test.sh ===

      preconditions

      AC-7: the three gates report the settled counts for this tree
        FAIL lint reports 43 files on the unmodified tree
             expected count: 43
             actual count:   42
             evidence regex: selene over [1-9][0-9]* files
             gate output (last 6 lines):
             Results:
             0 errors
             0 warnings
             0 parse errors
             selene over 42 files
        FAIL typecheck reports 8 files on the unmodified tree
             expected count: 8
             actual count:   7
             evidence regex: analyze over [1-9][0-9]* files
             gate output (last 6 lines):
             Created sourcemap at sourcemap.json
             [INFO] Loading definitions file: @roblox - globalTypes.d.luau
             [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
             [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
             analyze over 7 files

      a gate names its target once, so the tool and the counter cannot disagree

      every gate command starts with a real executable, so doctor.sh can find the tool

      AC-1: the format count is the number of files stylua read

      AC-1, empty boundary: a format target with no .luau files claims no work

      AC-3: the lint count moves with the target selene was handed
        FAIL narrowing the lint target to src reports 8, not 43
             expected count: 8
             actual count:   7
             evidence regex: selene over [1-9][0-9]* files
             gate output (last 6 lines):
             Results:
             0 errors
             0 warnings
             0 parse errors
             selene over 7 files

      AC-5: the typecheck count moves with the target luau-lsp was handed

      AC-2/AC-4: a .luau file on disk but not yet tracked by git is counted
        FAIL AC-4: lint counts the untracked file (43 -> 44)
             expected count: 44
             actual count:   43
             evidence regex: selene over [1-9][0-9]* files
             gate output (last 6 lines):
             Results:
             0 errors
             0 warnings
             0 parse errors
             selene over 43 files
        FAIL typecheck counts the untracked file (8 -> 9)
             expected count: 9
             actual count:   8
             evidence regex: analyze over [1-9][0-9]* files
             gate output (last 6 lines):
             Created sourcemap at sourcemap.json
             [INFO] Loading definitions file: @roblox - globalTypes.d.luau
             [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
             [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
             analyze over 8 files

      AC-6: a .luau file .gitignore covers is not counted
        FAIL lint does not count the ignored file (still 43)
             expected count: 43
             actual count:   42
             evidence regex: selene over [1-9][0-9]* files
             gate output (last 6 lines):
             Results:
             0 errors
             0 warnings
             0 parse errors
             selene over 42 files
        FAIL typecheck does not count the ignored file (still 8)
             expected count: 8
             actual count:   7
             evidence regex: analyze over [1-9][0-9]* files
             gate output (last 6 lines):
             Created sourcemap at sourcemap.json
             [INFO] Loading definitions file: @roblox - globalTypes.d.luau
             [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
             [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
             analyze over 7 files

      the format gate FAILS on a badly formatted file, however it counts

    project-counters: 33 passed, 7 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T040958Z.2066476.bak) ===

Seven failures, all of them corrected assertions, every message naming the right
number. `NARROW_TYPECHECK` (5, over `src/shared`) stayed green, correctly: the
file the mutation hid is under `src/server/seats`, not `src/shared`, which is why
that one literal did not move either.

#### Probe B - stylua's own counter (format)

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's|{n++; next}|{if ($0 !~ /seats/) n++; next}|' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s|{n++; next}|{if ($0 !~ /seats/) n++; next}|) ===
      334 - gate | format    | optional | . | stylua --check -v src tests lune 2>&1 | awk '/^debug: formatted /{n++; next} skip{if ($0 == "}") skip=0; next} /^debug: .*\{$/{skip=1; next} /^debug: /{next} {print} END{print "stylua over " n+0 " files"}'; test "${PIPESTATUS[0]}" -eq 0
      334 + gate | format    | optional | . | stylua --check -v src tests lune 2>&1 | awk '/^debug: formatted /{if ($0 !~ /seats/) n++; next} skip{if ($0 == "}") skip=0; next} /^debug: .*\{$/{skip=1; next} /^debug: /{next} {print} END{print "stylua over " n+0 " files"}'; test "${PIPESTATUS[0]}" -eq 0

    === mutate: running bash .claude/tests/project-counters.test.sh ===

      preconditions

      AC-7: the three gates report the settled counts for this tree
        FAIL format reports 43 files on the unmodified tree
             expected count: 43
             actual count:   42
             evidence regex: stylua over [1-9][0-9]* files
             gate output (last 6 lines):
             stylua over 42 files

      a gate names its target once, so the tool and the counter cannot disagree

      every gate command starts with a real executable, so doctor.sh can find the tool

      AC-1: the format count is the number of files stylua read
        FAIL narrowing the format target to src reports 8, not 43
             expected count: 8
             actual count:   7
             evidence regex: stylua over [1-9][0-9]* files
             gate output (last 6 lines):
             stylua over 7 files

      AC-1, empty boundary: a format target with no .luau files claims no work

      AC-3: the lint count moves with the target selene was handed

      AC-5: the typecheck count moves with the target luau-lsp was handed

      AC-2/AC-4: a .luau file on disk but not yet tracked by git is counted
        FAIL AC-2: format counts the untracked file (43 -> 44)
             expected count: 44
             actual count:   43
             evidence regex: stylua over [1-9][0-9]* files
             gate output (last 6 lines):
             stylua over 43 files

      AC-6: a .luau file .gitignore covers is not counted
        FAIL format does not count the ignored file (still 43)
             expected count: 43
             actual count:   42
             evidence regex: stylua over [1-9][0-9]* files
             gate output (last 6 lines):
             stylua over 42 files

      the format gate FAILS on a badly formatted file, however it counts

    project-counters: 36 passed, 4 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T041026Z.2067959.bak) ===

Four failures, all corrected assertions, and the lint/typecheck family stayed
green - the two probes are independent, which is what makes the pair evidence
rather than one probe counted twice.

Both restores were verified byte-for-byte by `mutate.sh`;
`.claude/state/mutations/` holds no `.bak`,
`git diff -- .claude/harness/project.conf` is empty, and `git diff -- src tests`
is empty.

### What did NOT change

- No source file. `git diff -- src` is empty; `src/server/seats/Ring.luau` is
  untouched.
- No test of this story's own behaviour. `git diff -- tests` is empty; the twelve
  SEAT-001 tests and the `unit` floor of 197 are unchanged.
- `.claude/harness/project.conf` - restored by both probes, unchanged on disk.
- HARNESS-006's acceptance criteria and the *design* of its suite. See below.

### Opinion, recorded and deliberately not acted on

The suite's design makes every story that adds or deletes a `.luau` file pay this
tax, and the gap that let it reach CI is that `gates.sh --fast` never runs the
harness suites. Both are real, and both are out of scope here: deriving the
expectations from the tool instead of hard-coding them would change what
HARNESS-006's AC-7 asserts, and HARNESS-006 is DONE with frozen criteria. A
separate harness story should decide between (a) deriving the counts from an
**independent** enumeration - `scripts/classify.sh --list`, which is not the
counter under test and so is not self-referential - and (b) leaving them settled
but putting the harness suites into the fast loop so a stale literal is caught in
RED rather than in CI. Recorded here so the next planner has it; nothing in this
story acts on it.

---

## REVIEW: the PR, and its CI

**PR:** https://github.com/ryanczhang7/first-roblox/pull/10
**Commit:** `0bce924`. Both required checks pass.

    boundaries   pass   5s      actions/runs/35184630897
    gates        pass   1m12s   actions/runs/35184630842

From the CI log, the part that matters - the suite that failed the first run:

    project-counters: 40 passed, 0 failed
    16 harness suite(s) passed.
    197 passed, 0 failed
    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (2s, observed 8)
    PASS         unit (1s, observed 197, floor 197)
    PASS         build (0s, observed 25103)

The first run of this PR (`actions/runs/35179368944`) failed with
`project-counters: 29 passed, 11 failed`, and that run is the evidence for the
return to RED recorded above. It is left in the PR's history rather than
force-pushed away: it is the only artefact showing that the detection gap is
real rather than argued.

### Timings

`gates` 1m12s, `boundaries` 5s, no `timeout-minutes` declared. `unit` is **1 s**
on CI against 16 s locally, and the whole harness self-test is well inside the
job. AC-5's 10,000-seed tally - the one plausible timeout risk in this story -
does not register at CI's resolution. No `slow` line and no `ci-factor` line is
warranted.
