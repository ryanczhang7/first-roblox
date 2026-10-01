---
id: SEAT-004
title: A player who returns within the grace window gets their seat back, and a late one spectates
slug: a-player-who-returns-within-the-grace-wi
epic: EPIC-10
type: feature
status: todo
phase: PLANNED
branch: story/SEAT-004-a-player-who-returns-within-the-grace-wi
depends_on: [SLICE-007]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-10`. SEAT-003 built the pure rules for disconnects
(`mechanics.md` §8; `roles.md` §6):

- the leaver's key class transfers to their supplier (`Ring.withdraw`);
- a rejoin inside `disconnect_grace_seconds` restores the seat (`Ring.rejoin`
  with an `Absence`);
- after the grace window, the player spectates until the next round.

`SLICE-003` wired `withdraw` into `Session`. **Nothing wires rejoin or
spectating.**

This story does, so that a dropped connection is not a dropped round. It is not
needed for M3's definition of done, which is a round completed by four humans,
so it follows `SLICE-007`.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a seated player who leaves during `Round`, when they rejoin
  within `disconnect_grace_seconds`, then the session restores the seat from the
  stored `Absence`. Every player whose seat view changed receives a fresh
  `SeatView`, and the returning player receives their lens view and turn cues.
- **AC-2** — Given the same player rejoining after the grace window, when they
  join, then they are a spectator:
  - they receive `RoundView`, `FacilityView` and a `SpectatorView`;
  - they receive no seat, lens or cue payload;
  - every remote call they make is rejected for `identity`.

  In the next `Lobby`, they are an ordinary player.
- **AC-3** — Given a player who leaves during `Lobby`, `Assignment`,
  `Resolution` or `Post`, when they return, then no `Absence` applies. They are
  a new join, and M1's rules hold.
- **AC-4** — Given a rejoin, when telemetry is read, then
  `bounce_before_resolution` was emitted at most once for that player in the
  round (TEL-002's rule is unchanged).

## Contract

`Session` gains:

    SessionState.absences: { [string]: Ring.Absence }
    SessionState.spectators: { [string]: boolean }
    SessionEffect gains: { kind: "SendTo", payloadKind: "SpectatorView", payload: { nextRound: true } }

`Transport.PRIVATE_KINDS` gains `SpectatorView`. That is a change to
`SLICE-002`'s set: list its callers with `rg PRIVATE_KINDS src tests`. The
wrapper's `isSeated` already refuses a spectator.

**Oracle partition.**
- AC-1 to AC-4 are **settled** by `mechanics.md` §8 and SEAT-003's built rules.
  Assert against `Ring`'s own outputs.

## Out of scope

- The notices a player sees (`HUD-006`).
- A rejoin after the server restarts (M5).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SEAT-004` from `.claude/harness/models.conf`.
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

Lock coverage: NOT CONSIDERED — this contract names no paths.
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

