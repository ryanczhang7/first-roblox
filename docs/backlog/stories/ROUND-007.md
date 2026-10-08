---
id: ROUND-007
title: A seated player can accept a rematch once during Post
slug: a-seated-player-can-accept-a-rematch-onc
epic: EPIC-09
type: feature
status: todo
phase: PLANNED
branch: story/ROUND-007-a-seated-player-can-accept-a-rematch-onc
depends_on: [SLICE-006]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-09`. Brief A4 calls the post-round rematch prompt "a co-play
retention mechanic" and "the highest-value thirty seconds in the product". The
M1 phase machine already records `RematchAccepted` once per seated player, only
in `Post`, as telemetry (`rematch_accepted`, TEL-002). **Nothing lets a client
send it.**

This story adds the `AcceptRematch` remote (`architecture.md` §9.5). It also
adds the public list of who has accepted, which the rematch card shows
(`components.md` C-25). Accepting does not move anyone. `Post → Lobby` is the
clock's (M1), and players stay in the server either way.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `GameRemotes.AcceptRematch`, when it is read, then its schema
  accepts only an empty table, its legal phases are exactly `{ "Post" }`, and it
  declares a rate limit. That completes B4's triple with AC-2.
- **AC-2** — Given the guarded remote, when malformed (`{ x = 1 }`),
  out-of-phase (`Round`) and flooded calls arrive, then each is rejected by the
  wrapper with the matching reason.
- **AC-3** — Given a seated player in `Post`, when their accepted call reaches
  the session, then the phase machine receives `RematchAccepted` and emits
  `rematch_accepted` once. A second acceptance by the same player emits nothing
  (M1's guard).
- **AC-4** — Given acceptances, when the next `RoundView` is built in `Post`,
  then it carries `rematched: { playerId }`, in acceptance order. Outside
  `Post`, the field is absent.

## Contract

`src/ReplicatedStorage/Net/GameRemotes.luau` gains:

    GameRemotes.AcceptRematch: Remotes.RemoteDefinition
    -- args        = Schema.shape({})
    -- legalPhases = { "Post" }
    -- rateLimit   = { minIntervalSeconds = 1 }   -- engineering flood bound; the phase machine already
    --                                               counts one acceptance per player per round

`Session` gains the event `{ kind = "RematchRequested", playerId }`. It forwards
the event to the phase machine as `RematchAccepted`. `RoundView` gains
`rematched: { string }?`.

- Confirm that `Schema.shape({})` rejects a non-empty table. If `Schema` has no
  way to say "no keys", RED amends this block: add the smallest `Schema` change
  that does, and list `Schema.shape`'s callers.

**Oracle partition.**
- AC-1 and AC-2 are **mechanical**.
- AC-3 is **settled** by M1's existing behaviour: assert against the phase
  machine's own effects.
- AC-4 is **mechanical**.

## Out of scope

- The card (`HUD-005`).
- Keeping a group together across servers (M5/M6).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write ROUND-007` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/ReplicatedStorage/Net/GameRemotes.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

