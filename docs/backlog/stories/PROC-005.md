---
id: PROC-005
title: A turn arrives as a validated remote and is judged against server positions
slug: a-turn-arrives-as-a-validated-remote-and
epic: EPIC-05
type: feature
status: todo
phase: PLANNED
branch: story/PROC-005-a-turn-arrives-as-a-validated-remote-and
depends_on: [PROC-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. A turn is a client's request, so it arrives as a remote. B4
makes three demands on it:

- It is validated for identity, shape, range, phase and rate by the wrapper.
- Every remote handler has a test in `tests/net/` asserting that malformed,
  out-of-phase and flooded calls are rejected.
- The machine and setting are **claims**. The server decides reach against its
  own accepted positions (`architecture.md` §9.8), never the client's.

`mechanics.md` §5 (G12) and `tuning.md` §4 add two rules. The `Turn` remote is
limited to one call per `turn_rate_limit_seconds`. A turn refused for rate is
not evaluated and costs nothing.

This story declares `Turn`, and builds the pure handler that turns a guarded
call into a `Procedure.turn` and a private reply. `SLICE-005` wires it into
`Session`.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `GameRemotes.Turn`, when it is read from `Remotes.all()`, then
  its schema is `{ machine = integer(1, actuator_count), setting = integer(1,
  dial_settings) }`, its legal phases are exactly `{ "Round" }`, and its
  `rateLimit.minIntervalSeconds` equals
  `MechanicsTuning.actuation.turn_rate_limit_seconds`. It declares no attempt
  limit and never declines.
- **AC-2** — Given the guarded `Turn` remote, when it receives malformed calls
  (missing `setting`, `machine = 0`, `setting = dial_settings + 1`, `setting =
  1.5`, an extra `player` key, a string), then each is rejected for `shape` or
  `range` as appropriate, and the Procedure is never consulted.
- **AC-3** — Given the guarded remote, when a well-formed turn arrives in
  `Lobby`, `Assignment`, `Resolution` or `Post`, then it is rejected for
  `phase`. When two arrive inside `turn_rate_limit_seconds`, then the second is
  rejected for `rate` and does not reach the Procedure.
- **AC-4** — Given a well-formed, in-phase call, when `TurnRequests.handle` runs,
  then it calls `Procedure.turn` with the caller's id, the requested machine and
  setting, and the session's **accepted** positions. A position supplied
  anywhere in the payload is ignored, because the schema has no field for one.
- **AC-5** — Given each `TurnResult` kind, when `TurnRequests.reply` maps it,
  then the turner receives exactly `{ machineId, kind, reason? }` as a private
  `TurnResult` payload, carrying no required setting. The reply to a
  `wrong_setting` rejection does not include the correct setting.
  *Control:* a reply that copies the machine record must fail, because it would
  carry `requiredSetting`.

## Contract

**Modules.**

`src/net/GameRemotes.luau` gains:

    GameRemotes.Turn: Remotes.RemoteDefinition
    -- args        = Schema.shape({ machine = Schema.integer(1, MechanicsTuning.instance.actuator_count),
    --                              setting = Schema.integer(1, MechanicsTuning.instance.dial_settings) })
    -- legalPhases = { "Round" }
    -- rateLimit   = { minIntervalSeconds = MechanicsTuning.actuation.turn_rate_limit_seconds }

`src/server/procedure/TurnRequests.luau` is pure:

    export type TurnReply = { machineId: number, kind: "committed" | "armed" | "rejected" | "refused", reason: string? }
    TurnRequests.handle(procedure: Procedure.ProcedureState, assignment: Ring.Assignment, playerId: string,
                        args: { machine: number, setting: number }, now: number,
                        positions: { [string]: Procedure.Vec }) -> (Procedure.ProcedureState, Procedure.TurnResult)
    TurnRequests.reply(result: Procedure.TurnResult) -> TurnReply

- `reply` builds the reply field by field (D8), never by copying a record.
- `GameRemotes` is created by `CHAN-004`. If this story runs first, it creates
  the module with `Turn` alone. The two stories touch disjoint declarations.

**Oracle partition.**
- AC-1 is **settled**: read the values from `MechanicsTuning`.
- AC-2 and AC-3 are **mechanical**, and they are B4's adversarial triple.
- AC-4 and AC-5 are **mechanical**. AC-5's control is a hand-written copying
  reply.

## Out of scope

- Session wiring, and routing the reply through `Transport` (`SLICE-005`).
- The dial UI (`HUD-002`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-005` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/net/GameRemotes.luau` (source), `src/server/procedure/TurnRequests.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

