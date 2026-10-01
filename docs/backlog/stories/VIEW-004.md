---
id: VIEW-004
title: An implausible position is not trusted for any range check
slug: an-implausible-position-is-not-trusted-f
epic: EPIC-07
type: feature
status: todo
phase: PLANNED
branch: story/VIEW-004-an-implausible-position-is-not-trusted-f
depends_on: [SLICE-005]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-07`. B4: "Client-supplied position, timing, and target selection are
**claims**, not facts. Re-derive or sanity-check server-side." On Roblox a
character's position is simulated by its own client, so every range rule in M3 —
reading a lens (`lens_read_range_studs`), pinging (`ping_range_studs`), turning,
and the finale's partner lamp — rests on a claim. `architecture.md` §9.8 settles
the check: the server samples positions itself and accepts a sample only if it
is reachable from the last accepted one at the server-set walk speed, with a
tolerance.

`SLICE-005` introduced `PositionsSampled` and stores samples unfiltered; this
story puts the plausibility check in front of that store.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a last accepted sample `p0` at `t0` and a candidate `p1` at
  `t1`, when `|p1 − p0|` (horizontal) `<= walk_speed_studs_per_second × TOLERANCE × (t1 − t0) + SLACK_STUDS`,
  then the candidate is accepted; otherwise the previous sample is kept and a
  rejection is counted for that player.
  *Control:* a candidate 200 studs away 0.1 s later must be refused; one 1.5
  studs away 0.1 s later must be accepted.
- **AC-2** — Given a player the server itself has just moved (a spawn or a
  round-start placement, signalled by a `Placed` event carrying the position),
  when the next sample arrives at that position, then it is accepted, and the
  placement becomes the new baseline.
  *Control:* the same jump without a preceding `Placed` must be refused.
- **AC-3** — Given a player with no accepted sample, when the first sample
  arrives, then it is accepted only if a `Placed` baseline exists for them;
  otherwise it is held as unaccepted and **no range rule treats that player as
  in range of anything**.
- **AC-4** — Given a player whose samples have been refused for longer than
  `RESYNC_SECONDS`, when the driver next places them, then the baseline resets
  (the recovery path for a legitimate desync is a server placement, never a
  trusted jump).
- **AC-5** — Given a `Session` with an implausible sample, when a lens, ping or
  turn rule next reads positions, then it reads the last accepted one — shown by
  a ping whose range check passes only at the implausible position being
  rejected as out of range.

## Contract

**Module.** `src/server/session/Positions.luau`, pure. Wired into
`Session.step`'s `PositionsSampled` handling.

    export type Vec = { x: number, y: number, z: number }
    export type Track = { accepted: Vec?, acceptedAt: number?, refusedSince: number? }
    -- walk speed is MechanicsTuning.instance.walk_speed_studs_per_second (derived: the platform
    -- default, which the game does not change); the driver sets it on every character
    Positions.TOLERANCE: number      -- 1.5: physics jitter and network batching
    Positions.SLACK_STUDS: number    -- 2: one sample's worth of rounding
    Positions.RESYNC_SECONDS: number -- 3
    Positions.placed(track: Track?, at: Vec, now: number) -> Track
    Positions.offer(track: Track?, candidate: Vec, now: number) -> (Track, boolean)   -- accepted?

These three are **engineering constants**, not game tuning: they bound a
trust check and do not change how the game plays for an honest client. They live
in this module with this justification and are **not** added to `tuning.md`.
If playtesting shows honest players refused (a jumping or falling character
exceeds the bound), raise the tolerance here and record the observation.

**Oracle partition.** AC-1 to AC-4 are **mechanical** against the constants
above (read them from the module, do not restate them). AC-5 is **mechanical**
through `Session`.

## Deferred verifications

**D-1. The bound discriminates.** With `scripts/mutate.sh` multiplying
`TOLERANCE` by 100, AC-1's 200-stud control **must** go red. RED cannot run
this; the module does not exist. Owner: GATES.

## Out of scope

- The Studio check that an honest walker is never refused: it needs the real
  driver and is `SLICE-007`'s `D-3`.

- Anti-cheat beyond range claims (fly, noclip, speed exploits as such).
- Vertical reach rules. Every M3 range is a horizontal distance (`architecture.md` §9.8).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write VIEW-004` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/session/Positions.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

