---
id: VIEW-001
title: A player's lens view holds only settings their lens may read from where they stand
slug: a-player-s-lens-view-holds-only-settings
epic: EPIC-07
type: feature
status: todo
phase: PLANNED
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

**Module.** `src/server/seats/Projection.luau`, extended. `forPlayer` is
unchanged.

    export type LensReading = { machineId: number, setting: number }
    export type LensView = { readings: { LensReading } }    -- readings in ascending machineId
    Projection.lensFor(assignment: Ring.Assignment, facility: Generator.Facility,
                       procedure: Procedure.ProcedureState, playerId: Ring.PlayerId,
                       position: Procedure.Vec?, lineOfSight: (Procedure.Vec, Procedure.Vec) -> boolean,
                       tuning) -> LensView

- The view is built by explicit construction, one reading at a time, as
  `forPlayer` is (SEAT-002 AC-4). No copy helper is used on a machine record.
  SEAT-002's structural guard is a flat ban on copy helpers in this file, and it
  must keep passing.
- `lineOfSight` is called only for machines that already pass class, range,
  lit room and not-committed. The port is expensive in a real place.
- The lens class comes from `Ring.lensOf`, which is dealt and never recomputed
  (SEAT-003).

**Existing exports: none changed.** `forPlayer`'s callers are untouched.

**Oracle partition.**
- AC-1 and AC-2 are **mechanical properties**, with hand-written wrong views as
  controls.
- AC-3 to AC-5 are **mechanical**.
- AC-6 is a **mechanical** text guard, and its needle is the whole word, per
  the rules on needles in `rules.md`.

## Deferred verifications

**D-1. The class clause discriminates.** Use `scripts/mutate.sh` to make
`lensFor` compare against `keyClasses[p]` (the player's own key) instead of
`lensOf(p)`. AC-1 **must** then fail. This is the direction error `Ring.luau`'s
header warns the ring's structure cannot catch. RED cannot run this. Owner:
GATES.

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

Lock coverage: SUPPRESSED by `src/server/seats/Projection.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

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

