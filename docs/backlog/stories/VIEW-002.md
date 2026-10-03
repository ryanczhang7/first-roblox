---
id: VIEW-002
title: A player's turn cues name only their own live and next machines
slug: a-player-s-turn-cues-name-only-their-own
epic: EPIC-07
type: feature
status: in-progress
phase: RED
branch: story/VIEW-002-a-player-s-turn-cues-name-only-their-own
depends_on: [PROC-002]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-07`. **Private turn cues** (`mechanics.md` §3.2; T10 (c); `roles.md`
§6) are the second per-player secret. A turner is shown which of their own
machines is **live**. They are also shown which is **next**: a step of theirs
that is not live and whose position among its track's uncommitted steps is at
most `turn_cue_lookahead`. A turner with steps in both tracks can hold two cues.
A finale step waiting on the other track is "next", never "live". Nobody is
shown anyone else's cues. This is anti-quarterback device 4 (`loop.md` §1.7):
nobody sees the whole order.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given n in `{4, 5, 6}`, at least 200 facilities per n, and every
  reachable Procedure state along a scripted commit order, when
  `Projection.turnCuesFor` is taken for every player, then every cue names a
  machine whose key class is in that player's `keyClasses`.
  *Control:* a view that lists every live machine must fail.
- **AC-2** — Given the same states, when a player's `live` cues are read, then
  they are exactly that player's machines for which `Procedure.isLive` is true.
- **AC-3** — Given the same states, when a player's `next` cues are read, then
  they are exactly that player's uncommitted, not-live step machines whose
  position is at most `turn_cue_lookahead`. A decoy is never a cue.
  *Control:* a lookahead of 2 must produce extra cues on a fixture built for it.
- **AC-4** — Given a finale step whose track is done while the other track is
  not, when its holder's cues are read, then it is in `next`, not `live`.
- **AC-5** — Given a key class transferred by `Ring.withdraw`, when the
  supplier's cues are read, then they include the transferred class's machines.
- **AC-6** — Given the view type, when a cue set is inspected, then it has
  exactly the keys `live` and `next`, each a list of machine ids. There is no
  step index, track number or other player's anything. The order is private,
  and so is its shape.

## Contract

RED may amend any block below in place, with a one-line reason beside it; GREEN
builds what the amended block says.

**Module.** `src/server/seats/Projection.luau`, extended. `forPlayer` and
`lensFor` (VIEW-001) are unchanged.

    export type TurnCues = { live: { number }, ["next"]: { number } }   -- machine ids, ascending
    Projection.turnCuesFor(assignment: Ring.Assignment,
                           procedure: Procedure.ProcedureState,
                           playerId: Ring.PlayerId) -> TurnCues

*Amended in PLANNED (PO-1):* the drafted signature also took `facility` and an
untyped `tuning`. Both are inside the state (`procedure.facility`,
`procedure.tuning`), and Procedure's P-1 reads every constant from
`state.tuning`; VIEW-001 PO-1 made the same cut for `lensFor`.

*The `["next"]` spelling (PO-2) is load-bearing, not style.* SEAT-002's flat
copy-helper ban in `tests/server/projection_test.luau` scans this file, with
comments and strings blanked, for the bare word `next` (the inline-copy
iterator). Its matcher (`SourceScan.hitsIn`) exempts a table-constructor key
(`{ next = ids }`) and a field access (`cues.next`), but **not** a type field
written `next: { number }` — that line would be a hit and the guard would go
red. Written `["next"]: { number }`, the key is a string literal, which the scan
blanks. Measured by the orchestrator on 2026-10-03: `luau-lsp analyze` accepts
the bracketed key and still type-checks it (a value of the wrong shape is
reported), `lune` runs it, and `stylua` leaves it as written. The view's key is
still exactly `next` (AC-6). Never name a local `next`.

**Semantics, every number pinned.**

- **Tracks** are `procedure.facility.steps.tracks`; `tracks[t][i]` is a machine
  id; each track's last entry is a finale step. A machine's key class is the
  `keyClass` of the machine in `procedure.facility.placement.machines` whose
  `id` field equals it.
- **Owned:** a step is the player's when its machine's `keyClass` is in
  `assignment.keyClasses[playerId]` — the list, so a class inherited through
  `Ring.withdraw` counts (AC-5). Never `Ring.lensOf` (that is the class the
  player READS, not the one they turn — the direction error, D-1).
- **Position** (`mechanics.md` §3.2, G12): a step's index among the uncommitted
  steps of its track, from 0, computed from `procedure.committed` on every call
  and never stored. A committed step has no position and is never a cue.
- **live** = the player's machines for which `Procedure.isLive(procedure, id)` is
  true. Liveness is Procedure's, never re-derived here: that is what makes a
  finale step at position 0 `waiting` until every ordinary step of both tracks
  is committed (AC-4), and keeps an armed finale machine live.
- **next** = the player's uncommitted step machines that are **not** live and
  whose position is `<= procedure.tuning.instance.turn_cue_lookahead`
  (inclusive; shipped value 1). A machine is never in both lists.
- **Decoys** (machines in no track) are never a cue.
- Both lists ascending by machine id, without duplicates, fresh tables on every
  call. The view has exactly `live` and `next`.
- **Not constrained:** an unseated `playerId`, and a state whose `outcome` is
  already decided. No test pins either.

**Requires.** `Procedure` (for `isLive` and the state type) is already on
`Projection.luau`'s allowlist from VIEW-001 PO-2 (`./Ring`,
`../procedure/Procedure`, `../facility/Machines`). Nothing new is required, so
the require guard stands unchanged.

**Construction.** Explicit, field by field, under SEAT-002's flat ban
(`table.clone`, `table.move`, `table.pack`, `table.unpack`, `table.freeze`,
`Deep.copy`, `pairs`, `next`, `setmetatable`); generalised iteration only.

**Existing exports: none changed.** No signature changes, so no caller list is
needed. `rg -n "turnCuesFor" src tests` on 2026-10-03 found no call, only
names: `Projection.luau:48`'s header ("`turnCuesFor` (VIEW-002, not built
yet)", which GREEN updates now that it is built) and VIEW-001's AC-6 guard in
`tests/server/lens_view_test.luau`, which requires the header to keep naming
`turnCuesFor` as a whole word. RED's handoff confirms the list against the tree.

**The client** derives the arrow and the tag from public facility data
(`VIEW-003`), so the cue carries only ids.

**Oracle partition.**
- AC-1, AC-2 and AC-6 are **mechanical**. The AC-2 oracle is `Procedure.isLive`
  itself, read in the test, not reimplemented.
- AC-3 to AC-5 are **settled** by `mechanics.md` §3.2 (G12). The AC-3 oracle
  computes position in the test, from `steps.tracks` and `committed`,
  independently of `turnCuesFor`.
- "Every reachable state along a scripted commit order" (AC-1..AC-3): for each
  facility, start from `Procedure.start` and commit steps one at a time in an
  order Procedure allows — any live step, with the two finale steps last —
  checking every player's cues at every state, including the state where only
  the finale remains. Committing by setting `committed` directly on a copy of
  the plain-data state is acceptable. The script must also visit at least one
  state where an armed finale machine is live (`procedure.armed` set), so the
  "Procedure's liveness, not position 0" clause is exercised.
- AC-3's control needs a fixture where a lookahead of 2 sees a step that 1 does
  not, **and** a test that runs the real `turnCuesFor` on a state whose
  `tuning.instance.turn_cue_lookahead` is 2 and expects that extra cue. Without
  the second, a module that reads the shipped constant instead of
  `procedure.tuning` passes every test.
- AC-4 needs states where one track's ordinary steps are all committed and the
  other's are not. An order that alternates tracks reaches few of them, so at
  least part of the script commits one track's ordinary steps entirely before
  touching the other.

## Deferred verifications

**D-1. Ownership is the key, not the lens.** With `turnCuesFor` taking the
player's class from `Ring.lensOf` instead of `assignment.keyClasses[playerId]`,
AC-1 **must** fail. RED cannot run this. Owner: GATES.

**D-2. The lookahead boundary is inclusive — a wrong value.** With `<=` changed
to `<` in the position comparison, AC-3 **must** fail: at the shipped lookahead
of 1, that leaves `next` holding only waiting finale steps at position 0. RED
cannot run this. Owner: GATES.

**D-3. Liveness is Procedure's.** With `live` computed as "position 0" instead
of `Procedure.isLive`, AC-4 **must** fail (a waiting finale step would show as
live) and AC-2 with it. RED cannot run this. Owner: GATES.

**D-4. `next` excludes `live`.** With the not-live clause removed from `next`,
AC-3 **must** fail (every live step would also be `next`). RED cannot run this.
Owner: GATES.

## Out of scope

- The arrow, which points at the machine or at the next doorway; the Game
  Designer answers that as Q-G2 (`HUD-001`).
- Routing (`SLICE-006`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write VIEW-002` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/seats/Projection.luau` (source), `tests/server/lens_view_test.luau` (test), `tests/server/projection_test.luau` (test), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.

## Test plan

All unit level: `turnCuesFor` is a pure function over plain data, and every
criterion is falsifiable from outside it with the merged `Ring`, `Procedure`
and `Generator`. Four new files, following the `LensViewContract` arrangement
(checks in a helper, applied to the real module in one file and to wrong views
in another, so every check is observed to fire in RED while the real module
cannot run).

**`tests/helpers/TurnCuesContract.luau`** — the checks, the oracle, the sample
and the fixture.

- The oracle (`expected`) honours the partition: ownership is
  `assignment.keyClasses[playerId]` (the list; never `Ring.lensOf`), liveness
  is `Procedure.isLive` *called*, and position is counted in the helper from
  `facility.steps.tracks` and `state.committed` - index among the uncommitted
  steps of its track, from 0. `next` = owned, uncommitted, not live, position
  `<= state.tuning.instance.turn_cue_lookahead`. Decoys are in no track and so
  never appear. `turnCuesFor` is never consulted.
- The sample: `Generator.generate` facilities at seeds 1..200 for each n in
  {4, 5, 6} (600), each started with the real `Procedure.start`. Per facility,
  **three scripted commit orders** - track 1's ordinary steps first, track 2's
  first, and a seeded draw among the live steps - commit one ordinary step at
  a time on a fresh shallow copy of the state (`committed` replaced), until
  only the finale pair remains. Before every commit the script asserts
  `Procedure.isLive` is true for the step it picks, so every state is one
  Procedure allows. One start state + 3 × 6 commits + the finale-only state
  with `armed` set on finale machine 1 = **20 states per facility, 12,000
  states, 60,000 (state, player) calls**. The track-first orders are what
  reach AC-4's states.
- `audit` compares every call with the oracle and attributes each
  disagreement: ownership (AC-1), live (AC-2), next and decoy (AC-3), the
  waiting/live finale (AC-4), armed-still-live (AC-2). It also counts what the
  sample reached, and every check refuses a sample under its per-facility
  floor: calls expecting any cue (20/facility), a live cue (15), a next cue
  (10), a cue in each track (1), owned steps at position lookahead + 1 (3),
  calls where the player owns a decoy (10), a finale step expected in next
  (2), (state, holder) pairs with exactly one track done (2), armed states
  (1), and two-cue lists (0.5). Measured values are 2.1x–10x the floors on
  the full sample, except armed states, which sit exactly on the floor by
  construction - one armed state per facility (handoff table).
- AC-5 uses the first 12 facilities per n, closed by the real `Ring.withdraw`
  (seat 2 leaves), on the same 20 states: every expected cue of the
  transferred class must be in the supplier's view (vacuity: at least 10 per
  facility; measured 720 calls), and the full audit must be clean for every
  remaining player on the withdrawn ring.
- AC-6 reads the shape key by key: exactly `live` and `next`, each a list
  whose `pairs` count equals its length, numbers only, strictly ascending
  (so unique), and on every fourth state the view is called again and the view
  table, `live` and `next` must all be different tables.
- A hand-built fixture (p1..p4, class i at seat i, tracks `{6, 8, 5, 9}` /
  `{1, 4, 7, 3}`, finale `{9, 3}`, decoys 2 and 10) with six states, compared
  **exactly** by `Deep.diff` against a hand-written table for each player,
  under a tuning whose `turn_cue_lookahead` is overridden. The table is
  written independently of the oracle and the check first asserts the two
  agree. At lookahead 2 it expects machines 5 and 7 at S0 and 9 and 3 at S5,
  which lookahead 1 excludes (AC-3's second control, run against the real
  view); at the shipped lookahead it pins the waiting finale in `next` at S1
  and S2, live at S3 and S4 (armed), and the two-cue list `[4, 9]` where
  track order gives `[9, 4]`.

**`tests/helpers/TurnCuesStubs.luau`** — a reference view and twelve
one-defect views built by one factory over a defects table.

**`tests/server/turn_cues_test.luau`** — the real module, 9 tests:

| Test | AC |
|---|---|
| Contract: exports `turnCuesFor` beside unchanged `forPlayer` and `lensFor` | shape |
| AC-1: every cue over 60,000 calls is of one of the player's key classes | AC-1 |
| AC-2: `live` is exactly the owned machines with `Procedure.isLive` true, armed included | AC-2 |
| AC-3: `next` is exactly owned, not-live, position `<=` lookahead; decoys never | AC-3 |
| AC-3: fixture under `turn_cue_lookahead = 2` sees the position-2 cues, exactly | AC-3 (control 2) |
| AC-4: one track done, other not → finale in `next`, not `live`; both done → `live`, not `next` | AC-4 |
| AC-4: fixture at the shipped lookahead - waiting finale, armed finale, `[4, 9]` order | AC-4, AC-6 |
| AC-5: supplier after `Ring.withdraw` holds the transferred class's cues; everyone exact | AC-5 |
| AC-6: exactly `{ live, next }`, ascending unique lists, fresh tables per call | AC-6 |

**`tests/server/turn_cues_controls_test.luau`** — 14 tests: two baselines
pinning the sample's measured numbers (control sub-sample and full sample)
with the reference view clean on every check, and one test per stub asserting
it fails *exactly* the named checks and passes the rest, with the violation
counts and message fragments measured in RED.

**`.claude/tests/project-counters.test.sh`** — `BASE_FORMAT`/`BASE_LINT`
149 → 153 (four new test files, no new source), with the customary history
comment; must land in the RED commit.

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain:
       * the exact command that runs the new tests
       * the failure output, and why it is the RIGHT failure
       * every file touched, and which AC each test covers
       * the EXPORT SHAPE the tests already pin: every module they import, the
         exact exported names and signatures, and the types the assertions
         destructure. Not a suggestion - a test already imports them, so a
         wrong guess is a compile error. Say what the tests do NOT constrain
         too, so it stays the implementer's choice.
       * any test that passed on arrival, and the probe or negative control
         that earns it
       * the EXPECTED VALUE of every negative control, as a table: threshold,
         candidate range, and the number the control measured. In RED the
         suite fails at import, so no assertion in it has run - the controls
         are claims until GREEN confirms them against the shipped module
       * anything discovered that changes the approach -->

**Model.** RED was dispatched as Fable 5.1 (`claude-fable-5-1`), matching the
planned `fable` row; no override was reported in the dispatch.

### The command

    lune run test

There is no per-file filter. The runner walks every `tests/**/*_test.luau` in
one process and prints `N passed, M failed`; read the `FAIL` lines for
`tests/server/turn_cues_test.luau`. For a fast loop while implementing, the
ignored scratch runner
`lune run .claude/state/scratch/run_one.luau tests/server/turn_cues_test`
runs one file (not an instrument of record; the gate is `lune run test`).

### The failure output (verbatim, `lune run test`, RED)

    FAIL  tests/server/turn_cues_test.luau :: AC-1: over 200 generated facilities at each n in 4..6 and every state of three scripted commit orders, every live and next cue names a machine whose key class is in that player's keyClasses
          ...tests/server/turn_cues_test:48: Projection.turnCuesFor is nil - VIEW-002's Contract exports turnCuesFor(assignment, procedure, playerId) -> TurnCues
    FAIL  tests/server/turn_cues_test.luau :: AC-2: over the same states, live is exactly the player's machines for which Procedure.isLive is true - an armed finale machine included
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-3: on a state whose procedure.tuning has turn_cue_lookahead = 2 (shipped 1), the cues include the position-2 machines that lookahead 1 excludes, exactly
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-3: over the same states, next is exactly the player's uncommitted, not-live step machines at position <= turn_cue_lookahead (inclusive), and a decoy is never a cue
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-4: a finale step whose track's ordinary steps are done while the other track's are not is in its holder's next and not live; once both are done it is live and not next
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-4: on the hand-built fixture at the shipped lookahead, the waiting finale is next at S1 and S2, live at S3 and when armed at S4, and a two-cue list reads [4, 9] ascending, not [9, 4] by track
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-5: after the real Ring.withdraw, the supplier's cues include the transferred class's machines on every scripted state, and every remaining player's cues are exactly the oracle's
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: AC-6: a cue set has exactly the keys live and next, each a fresh list of machine ids ascending and unique, with no step index, track or other player's anything
          (same message)
    FAIL  tests/server/turn_cues_test.luau :: Contract: Projection exports turnCuesFor as a plain field function beside the unchanged forPlayer and lensFor
          (same message)

    950 passed, 9 failed

(`real 2m37.3s` for the whole suite on this machine; the 950 are every
pre-existing test plus the 14 controls.)

Why it is the right failure: all nine tests fail at the export check with
`Projection.turnCuesFor is nil` - the module loads, `forPlayer` and `lensFor`
are intact, the function this story adds does not exist. Every other test in
the tree still passes, the fourteen controls included. Nothing fails at load.

### Files touched

| File | Status | Covers |
|---|---|---|
| `tests/helpers/TurnCuesContract.luau` | new | the oracle, the scripted sample, the audit, every check, the fixture and its expectation tables |
| `tests/helpers/TurnCuesStubs.luau` | new | the reference view and twelve one-defect views |
| `tests/server/turn_cues_test.luau` | new | AC-1..AC-6 against the real module (9 tests) |
| `tests/server/turn_cues_controls_test.luau` | new | the negative controls (14 tests, all green in RED by design) |
| `.claude/tests/project-counters.test.sh` | amended | `BASE_FORMAT`/`BASE_LINT` 149 → 153 (four new test files, no new source), set to the predicted post-GREEN counts as every prior RED did; must travel in the **RED commit** - `check-boundaries.sh` 3j refuses this file outside RED |
| `docs/backlog/stories/VIEW-002.md` | amended | `## Test plan`, this section |

No existing test file was changed. `projection_test.luau`'s flat ban and
require allowlist, and `lens_view_test.luau`'s AC-6 header guard, stand as
they are and nothing here conflicts with them.

### The export shape the tests pin (fact, not suggestion)

`tests/server/turn_cues_test.luau` does `pcall(require, "../../src/server/seats/Projection")`
and reads **`Projection.turnCuesFor`** as a plain field, called with a dot:

    Projection.turnCuesFor(assignment, procedure, playerId) -> TurnCues

- `assignment` is a `Ring.Assignment` as `Ring.assign` deals it, as
  `Ring.withdraw` closes it (AC-5: the supplier's `keyClasses` list then has
  two entries, both of which must count), and in the fixture a hand-written
  one with `players`, `sigma`, `keyClasses`, `lens`. Ownership is
  `assignment.keyClasses[playerId]` **as a list**: `table.find`-style
  membership, not `[1]`. The fixture's `lens` differs from `keyClasses` for
  every player, and the `lensNotKey` stub fails AC-1 with 2,316 ownership
  violations on the control sample.
- `procedure` is a `Procedure.start` state, sometimes a shallow copy of one
  with `committed` replaced and `armed` set. The tests read, and `turnCuesFor`
  must read: `procedure.facility.steps.tracks` (and may read `steps.finale`),
  `procedure.facility.placement.machines` (for a step's `keyClass`, matched
  by the `id` **field**, never by list index - the fixture lists machines in
  id order but the generated placement is the one that happens to), 
  `procedure.committed[id]`, `procedure.tuning.instance.turn_cue_lookahead`
  (**not** `MechanicsTuning` - the fixture overrides it to 2 and the
  `shippedLookahead` stub fails that one test), and
  `Procedure.isLive(procedure, id)` for liveness - never position 0. The
  fixture's layout has four rooms and `doors`; nothing here expects it to be
  read.
- `position` is the index among the **uncommitted** steps of the machine's
  track, from 0; `next` is owned, uncommitted, **not live**, position
  `<= turn_cue_lookahead` (inclusive - the `strictLookahead` stub fails AC-3
  on 845 of 3,600 calls). A finale step at position 0 whose other track is not
  done is not live (`Procedure.isLive` says so) and so is `next` (AC-4). A
  finale step at position 1 is also `next` at the shipped lookahead. An armed
  finale machine is live (`Procedure.isLive` says so) and must be in `live`.
- `TurnCues` is a table whose **only** keys are `live` and `next` (keys are
  enumerated and compared as a sorted list). Each is a list of numbers
  (machine ids) with no holes or stray keys (`pairs` count equals `#`),
  **strictly ascending** - the fixture's S1 gives p1 `[4, 9]` where track order
  is `[9, 4]`, and 30 generated calls on the control sample have track 1's id
  above track 2's. A **fresh** view table **and** fresh `live` and `next` lists
  on every call: a cached list fails AC-6 (`again.live == result.live` is a
  violation). An empty list is `{}`; `nil` is a malformed view.
- `forPlayer` and `lensFor` are still required to be functions; nothing about
  them changed.
- `tests/server/projection_test.luau` still pins: every `require(` in
  `Projection.luau` is one of `require("./Ring")`,
  `require("../procedure/Procedure")`, `require("../facility/Machines")`, and
  the SEAT-002 flat ban holds: no `table.clone`, `table.move`, `table.pack`,
  `table.unpack`, `table.freeze`, `Deep.copy`, `pairs`, `next`, `setmetatable`
  as code anywhere in the file. **Spell the type key `["next"]`** (PO-2) and
  never name a local `next`; `table.find`, `table.insert`, `table.sort` and
  `ipairs` are fine.
- `tests/server/lens_view_test.luau` still pins that `Projection.luau`'s
  comments name `turnCuesFor` as a whole word (and `lensFor`), and never say
  `fragments` or `pairings`. Line 48's "(VIEW-002, not built yet)" is for
  GREEN to update.

**Not constrained** (implementer's choice): what `turnCuesFor` does for an
unseated `playerId` or a state whose `outcome` is decided; whether it errors
on anything; iteration style beyond the flat ban; type annotations; whether
it walks tracks or machines first; any new local helpers; whether an id in
both lists would be de-duplicated (the oracle never produces one, and a
machine in both fails AC-3 as "extra next cue, which is live").

### Tests that passed on arrival, and what earns them

None in `turn_cues_test.luau`: all nine fail at the export check. The
fourteen tests in `turn_cues_controls_test.luau` are green in RED **by
design** - they run against the stubs, not the module - and each is earned
by the control it holds: every one asserts that a specific check *refuses* a
specific wrong view (`refuses` fails if the check passes, "so the check is
vacuous") and *accepts* the rest, with the violation counts and message
fragments measured. No `scripts/mutate.sh` probe was needed: no test here
touches existing production behaviour, and the counters change is a
baseline move, not an assertion.

### Negative controls: expected values, as measured in RED

All numbers are from the **control sub-sample** (first 12 facilities per n:
36 facilities, 720 states, 3,600 calls) unless marked FULL, measured by
`turn_cues_controls_test.luau` and by a scratch script
(`.claude/state/scratch/measure_cues.luau`) that calls the checks directly.
"Fails exactly" is asserted by `failsExactly`: those checks refuse the view
and every other check accepts it. Fixtures = `AC-3/lookahead-2` (24 cases)
and `AC-4/fixture` (24 cases).

| Control (stub) | Fails exactly | Measured |
|---|---|---|
| `reference` | nothing | clean audit; 2,130 calls expecting a cue (live 1,137, next 1,103), both tracks 186, excluded-by-one 615, owned-decoy calls 3,600, finale-in-next 537, AC-4 states 276, armed 36; 76 two-cue lists of 7,200 |
| `reference` FULL | nothing | 600 facilities, 12,000 states, 60,000 calls; 34,988 / 18,727 / 18,234 / 3,487 / 10,275 / 60,000 / 8,925 / 4,725 / 600; 1,514 two-cue lists of 120,000 |
| `everyLive` (AC-1's control) | AC-1, AC-2, AC-5, both fixtures | ownership 4,656, live 3,297, next 0; "live cue 9 is of class 3, not one of p1's key classes [1]" |
| `lensNotKey` (D-1) | AC-1, AC-2, AC-3, AC-4, AC-5, both fixtures (passes AC-6 only) | ownership 2,316, live 2,140, next 1,967, AC-4 564, armed 36 |
| `strictLookahead` `<` (D-2) | AC-3, AC-5, both fixtures | next 845 (every position-1 cue missing), live 0; AC-5 177 of 720 supplier calls; fixtures 6 of 24 |
| `shippedLookahead` (reads `MechanicsTuning`) | **`AC-3/lookahead-2` only** | fixture 6 of 24 (p2 missing 5 at S0/S2, p4 missing 7 at S0/S1, p1 missing 9 and p3 missing 3 at S5); passes all six sample checks and the shipped-lookahead fixture |
| `positionZeroAsLive` (D-3) | AC-2, AC-3, AC-4, AC-5, both fixtures | live 276, next 276, AC-4 276 - one of each per (state, holder) with exactly one track done; AC-5 56 of 720; fixtures 2 of 24 |
| `nextIncludesLive` (D-4) | AC-3, AC-4, AC-5, both fixtures | next 1,137 (one per non-empty live), AC-4 288 (a live finale also next); fixtures 10 of 24 |
| `decoyIncluded` | AC-3, AC-5, both fixtures | next 3,600 (every call), decoy cues 5,760; fixtures 12 of 24 |
| `descending` | AC-6, both fixtures | 76 of 3,600 calls (every two-cue list); fixture 1 of 24, lookahead-2 2 of 24 |
| `trackOrder` (unsorted) | AC-6, both fixtures | 30 of 3,600 calls; fixture 1 of 24 (`[9, 4]`) |
| `extraKey` (`playerId` on the view) | AC-6, both fixtures | 3,600 of 3,600; "keys are [live,next,playerId]" |
| `sharedLists` | AC-6 only | 900 of 3,600 (one call in four is called twice) |
| `duplicateCue` | AC-6, both fixtures | 1,137 of 3,600 (one per non-empty live); fixtures 10 of 24 |

Two things the measurement surfaced that the brief's expected sets did not
say: `strictLookahead` also fails **AC-5**, because the supplier's inherited
position-1 cues are exactly what `<` drops; and `nextIncludesLive` also fails
**AC-4**, because at the finale-only state the live finale is then also
`next`, which the "both done → live, not next" clause refuses. Both are
correct behaviour of the checks and are pinned as measured.

These numbers were measured against the **reference stub**, not the shipped
module. Confirming them against `Projection.turnCuesFor` is GREEN's job:
after GREEN, `turn_cues_test.luau`'s six sample checks must pass the same
full-sample floors, and the two `baseline:` controls still pin the sample's
own numbers (they do not call the module).

### Sample statistics for GREEN to reproduce

Full sample (`Contract.audit(Projection.turnCuesFor)` after GREEN should
report these in `describeAudit`, since the counts are properties of the
sample and the oracle, not of the view): 600 facilities, 60,000 calls;
expected non-empty 34,988 (live 18,727, next 18,234); both tracks 3,487;
excluded by one 10,275; owned-decoy calls 60,000; waiting finale 8,925; AC-4
states 4,725; armed states 600; violations all 0. Vacuity floors (per
facility × 600): 12,000 / 9,000 / 6,000 / 600 / 1,800 / 6,000 / 1,200 / 1,200
/ 600, and 300 two-cue lists (measured 1,514).

### Timing (local, this machine)

- Sample construction: 0.17 s for all 600 facilities and 12,000 states
  (`Generator.generate` is fast; the states are shallow copies).
- Each full-sample check against the reference: AC-1 0.38 s, AC-2 0.39 s,
  AC-3 0.39 s, AC-4 0.38 s, AC-5 0.02 s, AC-6 0.24 s, both fixtures ~0 s -
  **~1.8 s** expected for `turn_cues_test.luau` in GREEN.
- `turn_cues_controls_test.luau`: 2.47 s for 14 tests (scratch runner).
- `turn_cues_test.luau` in RED: 0.00 s (nine export-check failures).
- Full suite: `real 2m37.3s` for this RED run (`lune run test`, 950 passed,
  9 failed). No test here owns a timeout; the runner has none,
  so there is no budget to size. The numbers above are from the plain runner
  on this machine; CI numbers will come from the `unit` gate's own log.

### Deferred verifications D-1..D-4: declined in RED, in these words

RED cannot run any of them: each mutates `turnCuesFor`, which does not exist.
Owner stays GATES. The test each one must turn red, with the stub that
showed the shape of the red:

- **D-1** (own by `Ring.lensOf`, not `keyClasses[p]`): `turn_cues_test` AC-1
  ("cue N is of class c, not one of p's key classes [..]"), and with it AC-2,
  AC-3, AC-4, AC-5 and both fixture tests - `lensNotKey` fails everything but
  AC-6.
- **D-2** (`<=` to `<`): AC-3 ("missing next cue N" on every position-1
  step: 845 of 3,600 on the control sample, so thousands on the full one),
  AC-5, and both fixture tests. The sample DOES see it, unlike VIEW-001's
  boundary.
- **D-3** (`live` = position 0 instead of `Procedure.isLive`): AC-4 ("finale
  machine N's track t is done and the other is not, so it must be in next and
  not live"), AC-2 ("extra live cue N (Procedure.isLive is false)"), AC-3,
  AC-5 and both fixtures.
- **D-4** (drop the not-live clause from `next`): AC-3 ("extra next cue N,
  which is live", one per non-empty live), AC-4 at the finale-only states,
  AC-5 and both fixtures.

### Discovered, and worth knowing before implementing

- A finale step at **position 1** (its track has one ordinary step left) is
  `next` at the shipped lookahead by G12's rule, not only the position-0
  waiting case AC-4 names. The oracle counts both (8,925 "waiting finale"
  calls on the full sample against 4,725 AC-4 states). Nothing in the
  Contract contradicts this; it is the inclusive window applied to a finale
  step.
- Track order is ascending by machine id on all but 30 of 3,600 control
  calls, because `Machines.generate` numbers machines in placement order and
  `Steps.draw` picks per class; a view that never sorted would pass most of
  the sample. The fixture's `[9, 4]` and those 30 calls are what pin sorting.
- The sample reaches 4,725 (state, holder) pairs with exactly one track done
  on the full sample - the track-first orders are what provide them; the
  drawn order alone reaches far fewer.
- `rg -n turnCuesFor src tests` re-checked on 2026-10-03 after writing the
  tests: outside the four new files, the name appears only at
  `src/server/seats/Projection.luau:48` (the header) and in
  `tests/server/lens_view_test.luau` (the AC-6 header guard, lines 62, 136,
  171). The Contract's list is confirmed; nothing calls `turnCuesFor`.

### Fast gates at the end of RED

`bash scripts/gates.sh --fast` on the uncommitted RED tree (not recorded - a
partial run is not evidence):

    --- gate summary ---
    PASS         format (0s, observed 153)
    PASS         lint (0s, observed 153, floor 1)
    PASS         typecheck (3s, observed 27)
    FAIL         unit (191s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 102288)
    FAIL         harness (23s, exit 1) -> .claude/state/gate-logs/harness.log
    --fast skipped: integration mutation
    2 required gate(s) failed.

- `unit`: `950 passed, 9 failed`, the nine `turn_cues_test.luau` failures
  above and nothing else; 191 s under the gate against 157 s plain. The right
  shape: red on the assertions.
- `harness`: `project-counters: 39 passed, 1 failed`, the one being "the
  working tree carries no stray .luau files" (`actual: ?? tests/helpers/TurnCuesContract.luau`),
  which is red on every uncommitted RED tree and clears at the **RED commit**
  that carries the four test files and the counters file together. The
  baselines were moved first (149 → 153) and the format/lint gates observe
  153, so no counter case is red.
- format, lint, typecheck, build: green over the new files (`stylua --check
  tests` and `selene tests` clean), so the tests are admissible to the gates
  that will judge them.

### Contract amendments

None. Every mechanism the Contract names held when measured: the `["next"]`
spelling is only a constraint on the module and nothing here needs a bare
`next` in it; `Procedure.isLive` makes an armed finale machine live and a
waiting one not; `Ring.withdraw` appends the leaver's class to the
supplier's list; the position-2 step and the track-done states the brief
asked the sample to reach are reached (10,275 and 4,725 on the full sample).
No acceptance criterion was touched.

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A test that is wrong is never edited into passing, and the
     return is not a footnote - it is the story failing to be one clean cycle,
     and the next person needs to know why. One block per return:
       * which test, what it asserted, and what was wrong with it
       * how the defect was found
       * what it asserts now
       * what earns it, since "watched it fail" cannot apply once the
         implementation exists - the corrected assertion passes on its first
         run and every run after, whether or not it asserts anything: either a
         PROBE (mutate the specific behaviour the test pins, paste the red,
         confirm the revert) or, where the defect was cost rather than
         correctness, a BEFORE/AFTER measurement taken under the gate command -
         not the plain test command, which is the faster one.
         PASTE THE OUTPUT. check-boundaries.sh refuses a PR whose Regressions
         or Gate probes section describes a failure without showing one
       * whether GREEN was a no-op, and the command output proving the source
         was untouched and still passes -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Scaffold inventory

<!-- REQUIRED for a bootstrap or chore story that writes production code under
     SCAFFOLD, where nothing forces a test to exist first, and for a spike that
     commits its throwaway code. Omit otherwise.
     One line per production file written, and for anything with behaviour
     rather than configuration, the test that covers it:
       src/core/palette.ts        - src/core/palette.test.ts
       vite.config.ts             - configuration, no behaviour
     check-boundaries.sh refuses the PR if any changed source file is not
     named here. -->

## Notes

### PO decisions at PLANNED → RED (2026-10-03)

- **PO-1. `turnCuesFor` drops its `facility` and `tuning` parameters**, as
  VIEW-001 PO-1 did for `lensFor`: both live in the `ProcedureState`. No AC text
  changes; every criterion names `Projection.turnCuesFor`, not its arity.
- **PO-2. The type spells its key `["next"]`.** SEAT-002's flat ban would match
  a bare `next:` type field. The alternatives were narrowing the shared
  `SourceScan.hitsIn` matcher, which every source guard in the repo uses, or
  renaming the key away from the design's own word ("next", `mechanics.md`
  §3.2), which would have meant amending AC-6. The bracketed key changes
  neither. It was measured, not assumed (see `## Contract`).
- **PO-3. Gate.** `unit` is `required` and `covers src/server/**`;
  `required_gates` stays empty.
- **PO-4. Epic check.** EPIC-07 done-when 2 ("turn cues name only machines of
  their own key classes, and only the live step and the next within
  `turn_cue_lookahead`") is AC-1..AC-3 here. Done-when 1 was VIEW-001 (DONE);
  3 and 4 are VIEW-003 and VIEW-004. No gap.
- **PO-5. Semantics made explicit, not added** (`## Contract`, D-1..D-4): the
  inclusive lookahead, liveness read from `Procedure.isLive`, `next` excluding
  `live`, ascending unique ids, and the lookahead read from `procedure.tuning`.
  Each is either G12's own text or the existing "compute it from the Procedure's
  state" bullet.

### RED verified by the orchestrator (2026-10-03)

- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), dispatched with
  `model: fable` per the plan row; no override reported.
- `lune run test`, run independently: `950 passed, 9 failed`; all nine in
  `tests/server/turn_cues_test.luau`, each `Projection.turnCuesFor is nil`.
  The 14 controls and every pre-existing test pass.
- Oracle read: position is counted per track from `committed` in
  `TurnCuesContract.luau`, liveness is `Procedure.isLive`, ownership is
  `keyClasses` — none of it reads `turnCuesFor`. ACs unchanged against `main`.
- One handoff finding accepted as settled, not new scope: a finale step at
  position 1 is `next` at the shipped lookahead. G12 says "not live and position
  <= `turn_cue_lookahead`" with no exception for finale steps.
