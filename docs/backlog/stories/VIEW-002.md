---
id: VIEW-002
title: A player's turn cues name only their own live and next machines
slug: a-player-s-turn-cues-name-only-their-own
epic: EPIC-07
type: feature
status: todo
phase: PLANNED
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

**Module.** `src/server/seats/Projection.luau`, extended:

    export type TurnCues = { live: { number }, next: { number } }   -- machine ids, ascending
    Projection.turnCuesFor(assignment: Ring.Assignment, facility: Generator.Facility,
                           procedure: Procedure.ProcedureState, playerId: Ring.PlayerId, tuning) -> TurnCues

- Built by explicit construction, under the same copy-helper ban as the rest of
  this file.
- "Position" is defined in `mechanics.md` §3.2 (G12): a step's index among the
  uncommitted steps of its track, from 0. Compute it from the Procedure's state.
  Never store it.
- The client derives the arrow and the tag from public facility data
  (`VIEW-003`), so the cue carries only ids.

**Oracle partition.**
- AC-1, AC-2 and AC-6 are **mechanical**.
- AC-3 to AC-5 are **settled** by `mechanics.md` §3.2 (G12).

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

