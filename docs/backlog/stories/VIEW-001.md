---
id: VIEW-001
title: A player's lens view holds only settings their lens may read from where they stand
slug: a-player-s-lens-view-holds-only-settings
epic: EPIC-07
type: feature
status: in-progress
phase: RED
branch: story/VIEW-001-a-player-s-lens-view-holds-only-settings
depends_on: [PROC-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-07`. `roles.md` §6 describes the most important trust property in
the game: a required setting must not exist in any client's replicated state
unless that client holds the lens for it. The rule is "only for the machine they
are reading". `mechanics.md` §2 defines reading: the player's lens class, within
`lens_read_range_studs`, with their light on the machine. `mechanics.md` §5
adds that nothing can be read in a dark room.

`architecture.md` D14 splits this rule between server and client:

- **The server** gates on class, range (horizontal, from the accepted
  position), line of sight and a lit room.
- **Light direction** is presentation. The client shows the glow only when its
  light is on the machine (`docs/wiki/design/components.md` C-01, C-02).

D16 makes the lens view a **separate allowlisted view** beside
`PublicSeatView`, not a widened one.

This story also clears two stale comments. `src/server/seats/Projection.luau`
lines 44–47 promise `pairings` and `fragments` fields "M3 adds". Fragments are
superseded, and pairings became this view. `src/server/seats/Ring.luau` line 54
also mentions pairings.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given n in `{4, 5, 6}`, at least 200 generated facilities per n,
  and for each at least 50 random accepted positions per player, when
  `Projection.lensFor` is taken for every player, then every reading is of a
  machine whose key class equals `Ring.lensOf(assignment, p)`, within
  `lens_read_range_studs` horizontally, with line of sight, in a room that is
  not dark, and not committed. Every machine meeting all five conditions is
  read. No reading is missing and none is extra.
  *Controls:* a view that gates on range only (any class) must fail the class
  clause. One that gates on class only (any range) must fail the range clause.
- **AC-2** — Given any two distinct players `p` and `q`, when both lens views are
  taken from the same position, then they share no machine. Lenses are disjoint
  because σ is a derangement and one lens is one class.
- **AC-3** — Given a player with no accepted position, when `lensFor` is taken,
  then it is empty.
- **AC-4** — Given the lens view type, when a reading is inspected, then it has
  exactly the keys `machineId` and `setting`. The view has exactly the key
  `readings`. There is no room, class, tag or player field, because the client
  already has those from public state.
- **AC-5** — Given a room that goes dark (`Procedure.isDark`), when `lensFor` is
  next taken for a helper standing at a machine in it, then that reading is
  gone.
- **AC-6** — Given `Projection.luau` and `Ring.luau`, when their source is read,
  then neither mentions `fragments` or `pairings`. A guard over the two files'
  text enforces this, anchored on whole words. The header's "what M3 adds"
  paragraph names `lensFor` and `turnCuesFor` instead.

## Contract

RED may amend any block below in place, with a one-line reason beside it; GREEN
builds what the amended block says.

**Module.** `src/server/seats/Projection.luau`, extended. `forPlayer` is
unchanged.

    export type LensReading = { machineId: number, setting: number }
    export type LensView = { readings: { LensReading } }    -- readings in ascending machineId
    Projection.lensFor(assignment: Ring.Assignment,
                       procedure: Procedure.ProcedureState,
                       playerId: Ring.PlayerId,
                       position: Procedure.Vec?,
                       lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean) -> LensView

*Amended in PLANNED (PO-1):* the drafted signature also took `facility` and an
untyped `tuning`. Both are already inside the state — `procedure.facility` and
`procedure.tuning` — and Procedure's own P-1 says every constant is read from
`state.tuning`. Two sources for one value is a test that can pass a facility
the Procedure is not running. They are dropped.

**Semantics, every number pinned.**

- **Candidates** are `procedure.facility.placement.machines`, every one of them,
  decoys included (every machine has a `requiredSetting`; a decoy is still a
  machine of a class, and AC-1 says every machine meeting the five conditions is
  read).
- **Class:** `machine.keyClass == Ring.lensOf(assignment, playerId)`. Never
  `assignment.keyClasses[playerId]` (that is the player's KEY — the direction
  error, D-1), never recomputed from `sigma`.
- **Range:** horizontal (x, z) Euclidean distance from `position` to
  `Machines.positionOf(procedure.facility.layout, machine, procedure.tuning)`,
  **inclusive**: `<= procedure.tuning.instance.lens_read_range_studs`. The `y`
  of either point is ignored (`architecture.md` §9.8). Same rule as
  Procedure's private `within`, with the lens constant.
- **Lit:** `not Procedure.isDark(procedure, machine.room)`.
- **Not committed:** `procedure.committed[machine.id] ~= true`.
- **Line of sight:** `lineOfSight(position, machinePosition)` returns true, where
  `machinePosition` is the `Machines.positionOf` value above. It is called
  **only** for machines that already pass class, range, lit and not-committed —
  the port is a raycast in a real place — and at most once per machine per call.
- **No position** (`nil`): `{ readings = {} }`, and `lineOfSight` is never called.
- **Reading:** `{ machineId = machine.id, setting = machine.requiredSetting }`,
  built literally. `readings` is ascending by `machineId`; a fresh table on every
  call.
- **Unseated `playerId`:** not constrained by this story. Whatever `Ring.lensOf`
  does is acceptable; no test pins it.

**Construction.** The view is built by explicit construction, one reading at a
time, as `forPlayer` is (SEAT-002 AC-4). No copy helper is used on a machine
record. SEAT-002's flat ban (`table.clone`, `table.move`, `table.pack`,
`table.unpack`, `table.freeze`, `Deep.copy`, `pairs`, `next`, `setmetatable` —
whole-file, comments and strings blanked) must keep passing: iterate with
generalised iteration, and do not name a local `next`.

**Requires (PO-2).** `Projection.luau` may require exactly `./Ring`,
`../procedure/Procedure` and `../facility/Machines`, and nothing else.
`tests/server/projection_test.luau`'s third AC-4 test currently asserts that
`./Ring` is the *only* require; that is SEAT-002 RED's instrument (its PO-1),
not SEAT-002's acceptance criterion, which bans copy helpers and says nothing
about requires. RED widens that test's allowlist to these three, **by name** —
not to "any relative require" — and earns the widened assertion with
`scripts/mutate.sh` (add a `require` of a fourth module to `Projection.luau`;
the widened test must go red; restore), pasting the output in the handoff. None
of the three exports a copy helper. No require cycle results: `Procedure`
requires `Ring` and `Machines`, not `Projection`.

**Existing exports: none changed.** `forPlayer`'s signature is untouched.
Callers checked against the tree on 2026-10-03 for completeness:
`src/server/session/Session.luau:85` (requires `Projection`, calls
`forPlayer`), `tests/server/projection_test.luau`,
`tests/server/projection_controls_test.luau`,
`tests/helpers/ProjectionContract.luau`, `tests/helpers/ProjectionStubs.luau`.
*Amended in RED (2026-10-03):* four more callers of `forPlayer`, found by
`rg -n '\.forPlayer\(' src tests` — `tests/server/session_controls_test.luau`,
`tests/server/session_round_controls_test.luau`,
`tests/helpers/SessionContract.luau`, `tests/helpers/SessionRoundContract.luau`
(all `require` the module; `session_test.luau` names it in a test title only).
Harmless, since `forPlayer` is untouched; listed so the record is complete.
No caller of `lensFor` exists. RED's handoff states it re-checked this list
against `rg -l Projection src tests`.

**Oracle partition.**
- AC-1 and AC-2 are **mechanical properties**, with hand-written wrong views as
  controls. The oracle is an independent five-clause filter written in the
  test, reading `Ring.lensOf`, `Machines.positionOf`, `Procedure.isDark` and
  `procedure.committed` — never `lensFor` itself. Generated states must include
  committed machines and dark rooms, and the injected `lineOfSight` must answer
  both ways (a deterministic function of the two points), or three of the five
  clauses are never exercised. The call-order clause (`lineOfSight` only after
  the other four) is pinned with a counting spy under AC-1.
- AC-3 to AC-5 are **mechanical**.
- AC-6 is a **mechanical** text guard, and its needle is the whole word, per
  the rules on needles in `rules.md`.

## Deferred verifications

**D-1. The class clause discriminates.** Use `scripts/mutate.sh` to make
`lensFor` compare against `keyClasses[p]` (the player's own key) instead of
`lensOf(p)`. AC-1 **must** then fail. This is the direction error `Ring.luau`'s
header warns the ring's structure cannot catch. RED cannot run this. Owner:
GATES.

**D-2. The lit clause discriminates.** With the `Procedure.isDark` check removed
from `lensFor`, AC-5 **must** fail, and so must AC-1 (its generated states
include dark rooms). RED cannot run this. Owner: GATES.

**D-3. The range boundary is inclusive — a wrong value, not a missing clause.**
With `<=` changed to `<` in `lensFor`'s range comparison, at least one test
**must** fail: RED pins a machine at exactly `lens_read_range_studs`
horizontally (and one at that distance plus a large `y` offset, which must still
be read). Random positions alone will never land on the boundary. RED cannot
run this. Owner: GATES.

**D-4. Line of sight is consulted last.** With `lensFor` changed to call
`lineOfSight` before the class check, the call-count assertion **must** fail.
RED cannot run this. Owner: GATES.

## Out of scope

- Routing the view to its player only (`SLICE-002` built `sendTo`; `SLICE-006`
  wires it).
- The glow and the light cone (`HUD-002`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write VIEW-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `scripts/mutate.sh` (tooling), `src/server/seats/Projection.luau` (source), `src/server/session/Session.luau` (source) (+4 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- PLANNED → RED orchestration (contract pinning, PO-1..PO-5) - `lead-po` -
  `claude-opus-5-5`. 2026-10-03.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), dispatched with
  `model: fable` explicitly per the plan row; the agent reported that ID and no
  override. 2026-10-03.

## Test plan

All unit level: `lensFor` is a pure function over plain data, and every
criterion is falsifiable from outside it with the merged `Ring`, `Machines`,
`Procedure` and `Generator`. Three new files, one amended, following the
`ProjectionContract` arrangement (checks in a helper, applied to the real
module in one file and to wrong views in another, so every check is observed
to fire in RED while the real module cannot run).

**`tests/helpers/LensViewContract.luau`** — the checks, and the oracle.

- The five clauses are re-derived from `Ring.lensOf`, `Machines.positionOf`,
  `Procedure.isDark` and `procedure.committed`, with the horizontal, inclusive
  range arithmetic written in the helper. `lensFor` is never consulted.
- The AC-1 sample: `Generator.generate` facilities at seeds 1..200 for each n
  in {4, 5, 6}, `Procedure.start` states with rooms darkened (p = 1/3) and
  machines committed (p = 1/4) by a draw from `Rng.fromSeed(seed):derive("lens-view-sample")`,
  50 positions per facility sampled within ±1.25 × `lens_read_range_studs` of
  a uniformly chosen machine with y in ±20, every player evaluated at every
  position (150,000 calls). `lineOfSight` is a deterministic hash of the two
  points, false about one time in three.
- Vacuity: the AC-1 check refuses the sample unless every clause excluded at
  least one machine *alone* per facility and at least three calls per facility
  expect a non-empty view (measured: 2,526 / 1,562 / 2,458 sole exclusions for
  lit / committed / sight, 5,392 non-empty, over 600 facilities).
- Two hand-built fixtures with `lens_read_range_studs` overridden 12 → 9 (so a
  constant read from `MechanicsTuning` rather than `procedure.tuning` is told
  apart): a 2 × 2 block for the boundary and AC-5, and a one-room "crowded"
  fixture at `room_pitch_studs` = 24 where four class-2 machines are all 8.49
  studs from the centre, because **no generated view ever holds two readings**
  (measured: max 1 over 150,000 calls) and the ascending-order clause needs one.
- Checks accept an optional `cases` list; the controls use the first 12
  facilities per n (36 facilities, 9,000 calls) so nineteen views × eight
  checks stays under 10 s.

**`tests/helpers/LensViewStubs.luau`** — a reference five-clause view and
eighteen one-defect views built by one factory over a defects table.

**`tests/server/lens_view_test.luau`** — the real module, 11 tests:

| Test | AC |
|---|---|
| Contract: exports `lensFor` beside unchanged `forPlayer` | shape |
| AC-1: five-clause filter over the generated sample, none missing none extra | AC-1 |
| AC-1: `lineOfSight` consulted last, at most once, with the right points (spy) | AC-1, D-4 |
| AC-1: inclusive at exactly the range from `procedure.tuning`, y ignored | AC-1, D-3 |
| AC-2: two players at one position share no machine | AC-2 |
| AC-3: nil position → exactly `{ readings = {} }`, `lineOfSight` never called | AC-3 |
| AC-4: exact reading and view keys, setting = `requiredSetting`, fresh per call | AC-4 |
| AC-4: crowded room → exactly three readings ascending by machineId | AC-4 |
| AC-5: reading present lit, gone after `Procedure.isDark` is true, other room untouched | AC-5 |
| AC-6: both files in the classifier's list and non-empty (vacuity) | AC-6 |
| AC-6: whole-word guard on `fragments`/`pairings`, header names `lensFor`, `turnCuesFor` | AC-6 |

**`tests/server/lens_view_controls_test.luau`** — 23 tests: the baseline passes
every check on both samples with the measured audit numbers pinned; each
one-defect view fails *exactly* the checks named for it and passes the rest;
AC-6's needle probed both ways and against SEAT-002's header text verbatim.

**`tests/server/projection_test.luau`** — the third AC-4 test's require
allowlist widened to `./Ring`, `../procedure/Procedure`, `../facility/Machines`
by name (PO-2); earned by a `mutate.sh` probe, pasted in the handoff.

## Handoff: RED -> GREEN

**Model.** RED was dispatched as Fable 5.1 (`claude-fable-5-1`), matching the
planned `fable` row; no override was reported in the dispatch.

### The command

    lune run test

There is no per-file filter. The runner walks every `tests/**/*_test.luau` in
one process and prints `N passed, M failed`; read the `FAIL` lines for
`tests/server/lens_view_test.luau`. Full suite on this machine: ~6 min (it was
5 m 54 s before this story). For a fast loop while implementing, the ignored
scratch runner `lune run .claude/state/scratch/run_one.luau tests/server/lens_view_test`
runs one file (not an instrument of record; the gate is `lune run test`).

### The failure output (verbatim, `lune run test`, RED)

    FAIL  tests/server/lens_view_test.luau :: AC-1: lineOfSight is consulted only for machines that already pass class, range, lit and not-committed, at most once per machine, with the accepted position and the machine's position (D-4)
          ...tests/server/lens_view_test:50: Projection.lensFor is nil - VIEW-001's Contract exports lensFor(assignment, procedure, playerId, position, lineOfSight) -> LensView
    FAIL  tests/server/lens_view_test.luau :: AC-1: over 200 generated facilities at each n in 4..6 and 50 positions per player, every reading is of a machine of Ring.lensOf's class, within lens_read_range_studs horizontally, in sight, lit and not committed - and every such machine is read
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-1: the range is inclusive at exactly lens_read_range_studs from procedure.tuning (the fixture's 9, not the shipped 12), horizontal, and a 500-stud y offset does not matter (D-3)
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-2: two distinct players' lens views taken from the same position share no machine
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-3: a player with no accepted position gets exactly { readings = {} } and lineOfSight is never called
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-4: a reading has exactly the keys machineId and setting with the machine's requiredSetting, the view has exactly the key readings, and the view is a fresh table on every call
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-4: a room holding four machines of the lens class, one committed, reads as exactly three readings ascending by machineId
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-5: a helper at a machine of their lens class in a lit room reads it, and once Procedure.isDark says the room is dark the next view no longer has that reading
          (same message)
    FAIL  tests/server/lens_view_test.luau :: AC-6: neither Projection.luau nor Ring.luau mentions fragments or pairings as a whole word, comments included, and Projection.luau's header names lensFor and turnCuesFor
          ...tests/server/lens_view_test:168: AC-6: the two files' text is stale - fragments are superseded and pairings became this view, and the "what M3 adds" paragraph must name lensFor and turnCuesFor instead:
            src/server/seats/Projection.luau mentions "fragments" on line(s) 46
            src/server/seats/Projection.luau mentions "pairings" on line(s) 45
            src/server/seats/Ring.luau mentions "pairings" on line(s) 54
            src/server/seats/Projection.luau's comments never name lensFor
            src/server/seats/Projection.luau's comments never name turnCuesFor
    FAIL  tests/server/lens_view_test.luau :: Contract: Projection exports lensFor as a plain field function beside the unchanged forPlayer
          (same message)
    pass  tests/server/lens_view_test.luau :: AC-6: the harness's source list for src/server/seats contains both Projection.luau and Ring.luau, and both read non-empty, so the guard has its subjects

    926 passed, 10 failed

Why it is the right failure: nine tests fail at the export check with
`Projection.lensFor is nil` - the module loads, `forPlayer` is intact, the
function this story adds does not exist. AC-6 fails on its own assertion,
naming the three stale lines and the two names the header lacks. Every other
test in the tree still passes (the only other red in the probe run was the
mutated require test, which is the point of that run). Nothing fails at load.

### Files touched

| File | Status | Covers |
|---|---|---|
| `tests/helpers/LensViewContract.luau` | new | the oracle, the sample, the fixtures, every check, AC-6's matcher |
| `tests/helpers/LensViewStubs.luau` | new | the reference view and nineteen one-defect views |
| `tests/server/lens_view_test.luau` | new | AC-1..AC-6 against the real module (11 tests) |
| `tests/server/lens_view_controls_test.luau` | new | the negative controls (24 tests, all green in RED by design) |
| `tests/server/projection_test.luau` | amended | third AC-4 test: require allowlist widened by name (PO-2); `ALLOWED_REQUIRES` local added |
| `.claude/tests/project-counters.test.sh` | amended | `BASE_FORMAT`/`BASE_LINT` 145 → 149 (four new test files, no new source), set to the predicted post-GREEN counts as every prior RED did; must travel in the **RED commit** - `check-boundaries.sh` 3j refuses this file outside RED |
| `docs/backlog/stories/VIEW-001.md` | amended | `## Contract` callers list, `## Test plan`, this section |

### The export shape the tests pin (fact, not suggestion)

`tests/server/lens_view_test.luau` does `pcall(require, "../../src/server/seats/Projection")`
and reads **`Projection.lensFor`** as a plain field, called with a dot:

    Projection.lensFor(assignment, procedure, playerId, position, lineOfSight) -> LensView

- `assignment` is a `Ring.Assignment` as `Ring.assign` deals it (and, in the
  fixtures, a hand-written one with `players`, `sigma`, `keyClasses`, `lens`).
  The class is read through `Ring.lensOf(assignment, playerId)` in the oracle;
  the fixture's `lens` differs from `keyClasses` for every player, and the
  D-1 stub (`keyClasses[p][1]`) fails AC-1 on 363 of 363 non-empty views.
- `procedure` is a `Procedure.start` state. The tests read, and `lensFor` must
  read: `procedure.facility.placement.machines` (every machine; decoys
  included), `procedure.facility.layout` (through `Machines.positionOf`),
  `procedure.tuning.instance.lens_read_range_studs` (**not**
  `MechanicsTuning` - the fixtures override it to 9 and the `shippedRange`
  stub fails the boundary), `Procedure.isDark(procedure, machine.room)` and
  `procedure.committed[machine.id] ~= true`. The crowded fixture's layout has
  one room and `doors = {}`; only `Machines.positionOf` is expected to read it.
- `position` is `{ x, y, z }` or `nil`. With `nil` the result must deep-equal
  `{ readings = {} }` and `lineOfSight` must not be called.
- `lineOfSight(from, to)` is called with `from` **field-equal** to `position`
  (identity is not required) and `to` whose `x` and `z` equal
  `Machines.positionOf(layout, machine, procedure.tuning)`'s exactly - the spy
  keys calls by `` `{to.x}|{to.z}` ``, so pass the `positionOf` result itself.
  Only for machines that already pass class, range, lit, not-committed; at most
  once per machine per call; at least once somewhere in the sample (a view that
  never asks fails the call-order check).
- Range: horizontal Euclidean, `<=` the constant, `y` ignored. Pinned at
  exactly 9 along +x, +z and -x with y offsets of 0, +500 and -500 (read), and
  at 9.001 (not read).
- `LensView` is a table whose **only** key is `readings` (keys are enumerated
  and compared as a sorted list). Each reading is a table whose **only** keys
  are `machineId` (number, the machine's `id`) and `setting` (number, equal to
  `machine.requiredSetting`). `readings` is ascending by `machineId` - the
  crowded fixture lists its machines 3, 1, 4, 2, so walking placement order
  without sorting fails (`listOrder` stub). A **fresh** view table **and** a
  fresh `readings` list on every call: a cached list fails AC-4
  (`again.readings == result.readings` is a violation).
- `forPlayer` is still required to be a function; nothing about it changed.
- `tests/server/projection_test.luau` pins: every `require(` in
  `Projection.luau`'s code is one of `require("./Ring")`,
  `require("../procedure/Procedure")`, `require("../facility/Machines")`
  (either quote style, optional whitespace inside the parentheses; that exact
  spelling, so `.luau` suffixes or `@` aliases for these fail), and the
  SEAT-002 flat ban still holds: no `table.clone`, `table.move`, `table.pack`,
  `table.unpack`, `table.freeze`, `Deep.copy`, `pairs`, `next`, `setmetatable`
  as code anywhere in the file. `ipairs` and `table.sort` are not banned;
  `table.insert` is fine. Do not name a local `next`.
- AC-6 pins the **text** of both files: no whole word `fragments` or
  `pairings` anywhere in `Projection.luau` or `Ring.luau` (comments and strings
  included - `%f[%w_]word%f[^%w_]`), and `Projection.luau`'s comments must
  contain the whole words `lensFor` and `turnCuesFor` (`turnCuesFor` is only
  named, not exported; it is VIEW-002's). Lines to fix: `Projection.luau`
  45-47, `Ring.luau` 54.

**Not constrained** (implementer's choice): what `lensFor` does for an
unseated `playerId`; whether it errors on anything; iteration style beyond the
flat ban; type annotations; the order in which the four cheap clauses are
evaluated among themselves (only that sight is last); whether `to`'s `y` is
`positionOf`'s; any new local helpers.

### Tests that passed on arrival, and what earns them

- **`projection_test.luau` :: "AC-4: Projection.luau requires nothing but
  ./Ring, ../procedure/Procedure and ../facility/Machines, by name"** - green
  on arrival because the module still requires only `./Ring`. Earned with
  `scripts/mutate.sh` adding a fourth require, under the real gate command:

      bash scripts/mutate.sh src/server/seats/Projection.luau \
        's|^local Ring = require("./Ring")$|&\nlocal Rng = require("@shared/Rng")|' -- lune run test

      === mutate: src/server/seats/Projection.luau (95 line(s) changed by s|^local Ring = require("./Ring")$|&\nlocal Rng = require("@shared/Rng")|) ===
        58 -
        58 + local Rng = require("@shared/Rng")
        ...
      FAIL  tests/server/projection_test.luau :: AC-4: Projection.luau requires nothing but ./Ring, ../procedure/Procedure and ../facility/Machines, by name, so no copy helper arrives under another name
            ...tests/server/projection_test:190: src/server/seats/Projection.luau has 2 require(s) but only 1 of them name one of ./Ring, ../procedure/Procedure, ../facility/Machines. The types and ring relations come from Ring, the position and the dark check from Machines and Procedure (VIEW-001 PO-2); nothing else is needed, and a helper required here is a copy helper the flat ban cannot see:
      src/server/seats/Projection.luau:57 references require
      ...
      924 passed, 11 failed

      === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_seats_Projection.luau.20261003T165649Z.506458.bak) ===

  The 11 are the 10 RED failures above plus this one; `git status --short src`
  is empty afterwards. (The "95 lines changed" is the line-shift of a one-line
  insertion as the diff renders it.) Logged in `.claude/state/mutations/log`.
- **`lens_view_test.luau` :: "AC-6: the harness's source list ... contains
  both ... and both read non-empty"** - the vacuity precondition for the
  guard, the same shape as SEAT-002's PO-4 test. It asserts nothing about the
  module; the guard it protects is red on arrival on its own assertion.
- **All 24 tests in `lens_view_controls_test.luau`** - negative controls,
  green by construction and MEASURED in RED (they need only merged modules).
  Each wrong view is asserted to fail *exactly* its named checks and pass the
  rest; a control that passed everything would fail its own `refuses`.

### The negative controls, measured in RED

Over the control sample (first 12 facilities per n: 36 facilities, 9,000
calls), unless marked FULL. "Fails exactly" is asserted; the audit numbers are
asserted where shown.

| Control (stub) | Fails exactly | Measured |
|---|---|---|
| `reference` | nothing | extra 0, missing 0; sole exclusions class 1452 / range 9306 / lit 147 / committed 102 / sight 141; 363 non-empty of 9000 |
| `reference` FULL | nothing | 600 facilities, 150,000 calls; sole exclusions class 21573 / range 158214 / lit 2526 / committed 1562 / sight 2458; 5,392 non-empty; floors 600 and 1,800 |
| `rangeOnly` (any class) | AC-1, AC-1/sight-order, AC-2 | extras by clause: class 1452, every other 0 |
| `classOnly` (any range) | AC-1, AC-1/sight-order, AC-1/boundary, AC-5 | extras: range 9306, every other 0 |
| `ignoreDark` (D-2) | AC-1, AC-1/sight-order, AC-5 | extras: lit 147, every other 0 |
| `ignoreCommitted` | AC-1, AC-1/sight-order, AC-4/many | extras: committed 102, every other 0 |
| `ignoreSight` | AC-1, AC-1/sight-order | extras: sight 141, every other 0; "never consulted" |
| `keyNotLens` (D-1) | AC-1, AC-1/sight-order, AC-1/boundary, AC-4/many, AC-5 | missing 363, extra 363 |
| `strictRange` `<` (D-3) | AC-1/boundary only | passes the 9,000-call random sample; fails at exactly 9 |
| `shippedRange` 12 not 9 (D-3) | AC-1/boundary only | fails at 9.001 |
| `threeDRange` | AC-1, AC-1/boundary | missing 234, extra 0; fails the y+500 stand |
| `sightFirst` (D-4) | AC-1/sight-order only | names a machine "which already fails: class" |
| `sightTwice` | AC-1/sight-order only | "consulted 2 times for machine" |
| `nilPositionNotEmpty` `{}` | AC-3 only | |
| `nilPositionConsultsSight` | AC-3 only | |
| `extraKeyOnReading` | AC-1/boundary, AC-4, AC-4/many, AC-5 | keys `[machineId,room,setting]` |
| `extraKeyOnView` | AC-1/boundary, AC-4, AC-4/many, AC-5 | keys `[playerId,readings]` |
| `settingIsTag` | AC-1/boundary, AC-4, AC-4/many, AC-5 | |
| `descending` | AC-4/many only | passes every sample-based check: no generated view has 2 readings |
| `listOrder` (unsorted) | AC-4/many only | same; fails on the 3, 1, 4, 2 room |
| `sharedList` | AC-4 only | "the same readings list was returned twice" |

AC-6's needle: `%f[%w_]pairings%f[^%w_]` matches `pairings`, `` `pairings` ``,
`(pairings)`, `pairings.`; does not match `pairingsX`, `subpairings`,
`my_pairings`, `pairings_`, `pairings2`, `repairings`, `_pairings`
(measured in a plain `lune run` script and asserted by two controls); and
finds the words on SEAT-002's header lines 45-46 verbatim.

These numbers were measured against the **reference stub**, not the shipped
module. Confirming them against `Projection.lensFor` is GREEN's job: after
GREEN, `lens_view_test.luau`'s AC-1 must pass the same full-sample floors, and
the two `baseline:` controls still pin the sample's own numbers.

### Timing (local, this machine, plain `lune run test` / scratch runner)

- `lens_view_test.luau` in RED: 6.1 s, of which ~5.4 s is AC-6's one
  `classify.sh` shell-out (cached for the process afterwards). Against the
  reference view, the behavioural checks cost: AC-1 1.17 s, sight-order 1.15 s,
  AC-2 0.91 s, AC-4 1.22 s, the fixtures ~0 s - **~4.5 s** expected in GREEN.
- `lens_view_controls_test.luau`: 8.9 s for 24 tests (20 views × 8 checks on
  the 36-facility sub-sample, plus one full-sample baseline at 1.5 s).
- Full suite: `real 8m15.9s` for this RED run against `5m54.0s` measured on
  the untouched tree at the start of the phase. The files added here cost
  ~15 s of that (measured per file above); the rest of the gap is machine
  variance between two runs twenty minutes apart - a third data point is the
  `unit` gate's own log from the `--fast` run below. No test here owns a
  timeout; the runner has none, so there is no budget to size.

### Deferred verifications D-1..D-4: declined in RED, in these words

RED cannot run any of them: each mutates `lensFor`, which does not exist.
Owner stays GATES. The test each one must turn red:

- **D-1** (compare `keyClasses[p]` not `lensOf`): `lens_view_test` AC-1
  (five-clause filter; expect every non-empty view both missing and extra, as
  the `keyNotLens` stub shows: 363/363 on the sub-sample), and with it the
  sight-order, boundary, crowded-room and AC-5 tests.
- **D-2** (drop the `isDark` check): AC-5, and AC-1 (extras attributed to
  `lit`; 2,526 sole exclusions in the full sample).
- **D-3** (`<=` to `<`): the AC-1 boundary test, "exactly the range (9 studs)"
  and the two y-offset stands. AC-1's random sample will NOT see it
  (`strictRange` passed it) - that is the fixture's job.
- **D-4** (`lineOfSight` before the class check): the AC-1 sight-order test,
  "consulted for machine N, which already fails: class".

### Discovered, and worth knowing before implementing

- **No generated view ever holds two readings** (max 1 over 150,000 calls):
  machines of one class are ≥ 32 studs apart and the range is 12. Ordering is
  therefore pinned on the crowded fixture only. If a later story shrinks
  `room_pitch_studs` or widens the lens range, the sample will start producing
  multi-reading views by itself.
- The widened require test counts `require(` tokens in CODE (comments blanked)
  against literal allowed strings; a require of one of the three under a
  different spelling fails it.
- `Ring.luau` line 54 is the one Ring edit this story needs; nothing in
  `Ring.luau`'s code is touched by any test here.
- Callers re-checked against `rg -l Projection src tests` on 2026-10-03;
  the Contract's list was short by four `forPlayer` callers (amended there).
  Nothing calls `lensFor`.

### Fast gates at the end of RED

`bash scripts/gates.sh --fast` on the uncommitted RED tree (not recorded - a
partial run is not evidence):

    --- gate summary ---
    PASS         format (2s, observed 149)
    PASS         lint (1s, observed 149, floor 1)
    PASS         typecheck (6s, observed 27)
    FAIL         unit (306s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 100345)
    FAIL         harness (26s, exit 1) -> .claude/state/gate-logs/harness.log
    --fast skipped: integration mutation
    2 required gate(s) failed.

- `unit`: `926 passed, 10 failed`, the ten `lens_view_test.luau` failures
  above and nothing else; 306 s under the gate (so the 8 m 16 s plain run was
  the slow outlier, not the suite). The right shape: red on the assertions.
- `harness`: `project-counters: 33 passed, 7 failed` - the file-count
  baselines (`expected 145 / actual 149`, four new test files). Set to
  149/149/27 in `.claude/tests/project-counters.test.sh` as every prior RED
  did, and re-run alone: `project-counters: 39 passed, 1 failed`, the one
  being "the working tree carries no stray .luau files", which is red on every
  uncommitted RED tree and clears at the **RED commit** that carries the four
  test files, `projection_test.luau` and the counters file together.
- format, lint, typecheck, build: green over the new files (`stylua --check
  tests` and `selene tests` clean), so the tests are admissible to the gates
  that will judge them.

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

- **PO-1. `lensFor` drops its `facility` and `tuning` parameters.** Both live in
  the `ProcedureState` already (P-1). Recorded in `## Contract`. No AC text
  changes: every criterion names `Projection.lensFor`, not its arity.
- **PO-2. `Projection.luau` may require `./Ring`, `../procedure/Procedure` and
  `../facility/Machines`.** SEAT-002's third AC-4 test pins `./Ring` as the only
  require; `lensFor` cannot gate on range or darkness without the other two
  short of reimplementing `Machines.positionOf` and `Procedure.isDark` here —
  the second-implementation hazard `Projection.luau`'s own header names. That
  test is RED's instrument, not SEAT-002's criterion (SEAT-002 AC-4 bans copy
  helpers; it is silent on requires), so RED widens it to the three names and
  earns the widening with a mutation. Found by reading the guard before
  dispatch; GREEN would otherwise have met it as a frozen red test.
- **PO-3. Gate.** `unit` is `required` and `covers src/server/**`
  (`project.conf`); it runs `lune run test`, which walks every `*_test.luau`.
  `required_gates` stays empty: no optional gate is the only one that reads
  `Projection.luau`.
- **PO-4. Epic check.** EPIC-07 done-when 1 is this story's AC-1 verbatim in
  substance (class, range, sight, dark), over a seeded sample. Done-when 2–4
  belong to VIEW-002..004. No gap between PROC-003 and this story.
- **PO-5. Boundary and call-order semantics added** (`## Contract`, D-3, D-4):
  inclusive range at exactly `lens_read_range_studs`, `y` ignored, and
  `lineOfSight` consulted last and at most once per machine. These are contract
  precision, not new scope: AC-1's "within … horizontally" and the existing
  "called only for machines that already pass" bullet already said so.
