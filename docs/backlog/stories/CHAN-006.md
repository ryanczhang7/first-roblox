---
id: CHAN-006
title: Each player has at most one live ping and it clears when it should
slug: each-player-has-at-most-one-live-ping-an
epic: EPIC-06
type: feature
status: todo
phase: PLANNED
branch: story/CHAN-006-each-player-has-at-most-one-live-ping-an
depends_on: [CHAN-005, PROC-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. The lifecycle of an accepted ping (`mechanics.md` §4.1, §8):

- **One active ping per player** (`active_pings_per_player`). A new ping
  replaces the old one, so nobody can lay out a pattern, the drawing surface a
  cipher would need.
- A ping lasts `ping_display_seconds`, or until the machine it targets commits,
  or until it is replaced.
- Two players pinging the same target both show.
- The server logs every ping (sender, target, position, time) for the trace.
  The trace's "read helper ping" also needs to know whether the target's room
  was lit when the ping was made (`mechanics.md` §7, G12).

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a player with an active ping, when they make another accepted
  ping, then the active set holds only the new one for that player. The old one
  is gone, not expired later.
  *Control:* an implementation that appends must fail, holding 2.
- **AC-2** — Given a ping made at `t`, when `Pings.tick` runs at `t +
  ping_display_seconds − ε`, then it is active. At `t +
  ping_display_seconds`, it is gone.
- **AC-3** — Given an active ping of kind `setting` or `machine` on machine `m`,
  when `m` commits (`Pings.onCommitted(m)`), then that ping is cleared, and
  pings on other machines and on doorways are untouched.
- **AC-4** — Given two players pinging the same target, when the active set is
  read, then both pings are present, each with its sender.
- **AC-5** — Given any sequence of accepted pings, replacements, expiries and
  clears, when the log is read, then it holds exactly one entry per accepted
  ping, in order, with `{ senderId, kind, target, setting?, position, at,
  roomLit }`. Nothing is ever removed from it, and a refused ping is never
  logged.
- **AC-6** — Given the active set, when `Pings.shown(state)` builds the public
  payload, then each entry is exactly `{ senderId, kind, target, setting? }`:
  there is no position of the sender and no expiry time.

## Contract

**Module.** `src/server/channel/Pings.luau`, extended:

    export type ActivePing = { senderId: string, kind: string, target: number, setting: number?, at: number }
    export type PingLogEntry = { senderId: string, kind: string, target: number, setting: number?,
                                 position: Procedure.Vec, at: number, roomLit: boolean }
    export type PingState = { active: { [string]: ActivePing }, log: { PingLogEntry } }
    export type PingShown = { senderId: string, kind: string, target: number, setting: number? }

    Pings.new() -> PingState
    Pings.accept(state, senderId: string, target: PingTarget, position: Procedure.Vec, now: number,
                 roomLit: boolean) -> PingState
    Pings.tick(state, now: number, tuning) -> PingState
    Pings.onCommitted(state, machineId: number) -> PingState
    Pings.shown(state) -> { PingShown }

- `position` is the target's position (`Pings.targetPosition`), which is the
  thing the trace needs. It is never the sender's.
- `roomLit` is supplied by the caller from `Procedure.isDark` for the target's
  room. A doorway is always logged as lit.

**Oracle partition.**
- AC-2 is **settled** by `ping_display_seconds`.
- All other criteria are **mechanical**.

## Out of scope

- Validation (`CHAN-005`) and session wiring (`SLICE-006`).
- The HUD's distinction between your helper's ping and anyone else's, a client
  model in `HUD-003`, computed from the seat view the client already has.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-006` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/channel/Pings.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

