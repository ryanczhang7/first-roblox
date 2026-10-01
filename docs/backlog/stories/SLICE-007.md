---
id: SLICE-007
title: Four humans complete a full round in Studio
slug: four-humans-complete-a-full-round-in-stu
epic: EPIC-08
type: feature
status: todo
phase: PLANNED
branch: story/SLICE-007-four-humans-complete-a-full-round-in-stu
depends_on: [HUD-001, HUD-002, HUD-003, HUD-004, HUD-007, VIEW-004, MAP-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-08`. **This is M3's definition of done** (brief §0c R2): *four humans
complete a full round end-to-end in Studio.*

Every rule is built and headlessly proven by the stories before this one:
`SLICE-005` and `SLICE-006` win and lose a generated facility through
`Session.step` alone. What remains is the real runtime. This story gives the
driver its real ports (`architecture.md` §9.6):

- position sampling from each character's root part, and teleports for
  `Placed`;
- `workspace:Raycast` against the blockout for line of sight;
- the `TextService` filter, in the shape `CHAN-001` confirmed;
- the four remotes bound through `Transport`, with each handler building its
  session event;
- the blockout built on entry to `Round` (`MAP-001`).

Then the operator plays.

The only headlessly testable pieces are the handler adapters. Each is a small
pure function that turns a guarded call into a `SessionEvent`, and those are
the story's unit tests. The rest is Studio. That is why the Studio checks here
are specific, and why each one is pasted rather than summarised.

**Which required gate would fail if this story's artifact broke:** `unit` for
the handler adapters, and `typecheck` and `build` for the driver. The definition
of done itself is held by no gate: it is `D-1`, run by the operator, and the
story cannot reach DONE without it.

## Acceptance criteria

- **AC-1** — Given each of `SendPreset`, `Ping`, `Turn` and `AcceptRematch`,
  when its handler adapter receives a guarded call, then it builds exactly the
  `SessionEvent` its story specified, with the caller's id and the validated
  args. The preset and ping adapters pass the `CallControl` through.
- **AC-2** — Given the driver's `Transport.bind` call, when it is inspected
  through a test seam (`RoundService.remotes()` returns the definitions and
  handler names it binds), then every definition in `GameRemotes` is bound and
  nothing else.
- **AC-3** — Given the filter adapter over a fake `TextService` that raises,
  when a preset is sent, then the session sees a failure and the call is
  declined (fail closed, C5).

## Contract

- `src/server/session/Handlers.luau` is pure. It has one function per remote,
  `(playerId, args, call) -> SessionEvent`.
- `src/server/RoundService.server.luau` is extended with the real ports. It
  stays logic-free.
- `src/server/ports/*.luau` holds the real adapters (`Positions`,
  `LineOfSight`, `Filter`). They are impure, with one Studio check each, below.

**Oracle partition.** AC-1 to AC-3 are **mechanical**.

## Deferred verifications

Every item here is the operator's, in Studio's local server with four clients,
or a Team Test with four people (see open question 3 in the planning report). It
is pasted into this story. **Owner: REVIEW.**

**D-1. Four humans complete a round.** Four people, each on their own client,
play from the lobby to `Post`.
- Record the seed, n, the outcome and reason, the finishing time against par,
  and the trace headline.
- Record whether anyone was confused and about what. This is not a gate. It
  is the first data for `playtest.md: P-D`, `P-K`, `P-Q` and `P-S`.

**D-2. Studio checks the earlier stories deferred here:**
- positions match where avatars stand;
- a wall blocks a ping and a doorway does not;
- a filtered preset is delivered;
- a forced filter failure is not delivered, and costs no cooldown;
- each client receives only its own lens and cues. Check this by logging each
  client's received `LensView` machine ids and comparing them against the
  server's ring.

**D-3. `VIEW-004`'s honest walker.** A player sprints, jumps and falls off a
ledge for 60 s, and the plausibility check refuses zero samples. The driver
logs the count.

**D-4. SC-A3 (muted playthrough) and SC-K1–K3** (keyboard-only, gamepad-only
and touch-only), across the whole round.

## Out of scope

- Publishing (M6, operator-gated).
- The feel of the round (M4).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-007` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/RoundService.server.luau` (source), `src/server/session/Handlers.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

