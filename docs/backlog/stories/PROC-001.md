---
id: PROC-001
title: A turn commits a live step on the right setting and says why it failed otherwise
slug: a-turn-commits-a-live-step-on-the-right
epic: EPIC-05
type: feature
status: todo
phase: PLANNED
branch: story/PROC-001-a-turn-commits-a-live-step-on-the-right
depends_on: [GEN-004]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. This is the core rule of the objective (`mechanics.md` §1, §3.2,
§5, G12):

- A step is **live** when its position among its track's uncommitted steps is
  0. The finale is the exception: its steps stay `waiting` until every ordinary
  step of both tracks is committed (`finale_live_together`).
- A turn names one setting. A dial starts **unset**.
- A turn is either **refused** or **evaluated**. A refused turn is never
  penalised: it costs no instability, plays no tone and does not reset the
  dial. The refusals are:
  - not the key holder;
  - out of `turn_range_studs`;
  - a committed machine;
  - a dial still resetting;
  - an armed finale machine.
- An evaluated turn **commits** a live step turned to its required setting.
  Anything else it **rejects** diagnostically, as `wrong_setting` or `not_live`
  (T13). A decoy is `not_live`. A rejection costs exactly one instability point,
  and the dial shows the chosen setting as rejected and returns to unset after
  `actuation_reset_seconds`.

This story covers ordinary steps. The finale's window is `PROC-002`, and what
instability *does* is `PROC-003`.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a started Procedure, when `Procedure.isLive` is asked about
  every step, then exactly the first step of each track is live, and neither
  finale step is live. After the first step of track 1 commits, the second step
  of track 1 is live.
  *Control:* a rule that makes every step of track 1 live must fail.
- **AC-2** — Given a live ordinary step, when its key holder, within
  `turn_range_studs`, turns it to its required setting, then the result is
  `committed`, the machine is committed, and the step behind it in that track
  becomes live.
- **AC-3** — Given an evaluated turn, when the machine is live and the setting
  is wrong, then the result is `rejected / wrong_setting`. When the machine is a
  waiting step or a decoy, whatever the setting, then the result is
  `rejected / not_live`. Either way instability rises by exactly
  `instability_per_wrong_value` or `instability_per_out_of_order` (1), and the
  dial shows that setting as rejected until `actuation_reset_seconds` have
  passed, then shows unset.
- **AC-4** — Given each refusal case, when the turn is made, then the result is
  `refused` with the matching reason, instability is unchanged, and the dial is
  unchanged:
  - `unknown_machine` — an id that does not exist;
  - `not_key_holder` — a player not holding the machine's key class;
  - `out_of_reach` — the holder, farther than `turn_range_studs` horizontally,
    or with no accepted position;
  - `committed` — a committed machine;
  - `resetting` — a dial inside its reset window.

  The checks run in the order listed, and the first failure wins.
  *Control:* an implementation that evaluates a turn by a non-holder (and so
  charges instability) must fail.
- **AC-5** — Given a disconnect that transferred a key class to the supplier
  (`Ring.withdraw`), when the supplier turns a machine of the transferred class,
  then it is judged as the key holder.
- **AC-6** — Given any turn, evaluated or refused, when the actuation log is
  read, then it holds one entry `{ playerId, machineId, setting, at, result }`
  per **evaluated** turn and none for a refused one.

## Contract

**Module.** `src/server/procedure/Procedure.luau`, pure.

    export type Vec = { x: number, y: number, z: number }
    export type DialView = { setting: number?, state: "unset" | "committed" | "rejected" }
    export type TurnResult =
          { kind: "committed", machineId: number }
        | { kind: "armed", machineId: number }                                    -- PROC-002
        | { kind: "rejected", machineId: number, reason: "wrong_setting" | "not_live" }
        | { kind: "refused", machineId: number?, reason: "unknown_machine" | "not_key_holder"
                            | "out_of_reach" | "committed" | "resetting" | "armed" }
    export type ActuationLogEntry = { playerId: string, machineId: number, setting: number, at: number,
                                      result: "committed" | "armed" | "wrong_setting" | "not_live" }
    export type ProcedureState = {
        facility: Generator.Facility,
        committed: { [number]: boolean },        -- machine id -> committed
        dials: { [number]: { setting: number?, rejectedUntil: number? } },
        instability: number,
        log: { ActuationLogEntry },
        -- PROC-002 and PROC-003 add fields; no field here is removed by them
    }

    Procedure.start(facility: Generator.Facility, now: number, tuning) -> ProcedureState
    Procedure.isLive(state: ProcedureState, machineId: number) -> boolean
    Procedure.dial(state: ProcedureState, machineId: number, now: number) -> DialView
    Procedure.turn(state: ProcedureState, assignment: Ring.Assignment, playerId: string,
                   machineId: number, setting: number, now: number,
                   positions: { [string]: Vec }) -> (ProcedureState, TurnResult)

- `positions` are the session's **accepted** samples (`VIEW-004`). Reach is
  horizontal distance to `Machines.positionOf` (`architecture.md` §9.8). A
  player with no accepted position is out of reach.
- `setting` has already been range-checked by the `Turn` remote's schema
  (`PROC-005`). Here it is trusted to be in `1..dial_settings`.
- **The finale's machines** are `waiting` in this story. A turn on one is
  evaluated as `not_live` until `PROC-002` makes them live. That is the correct
  behaviour under `finale_live_together`, not a stub.
- State is replaced, never mutated (D3). Every call returns a new state.

**Oracle partition.** AC-1 to AC-5 are **settled** by `mechanics.md` §3.2 and §5
(G12). Name each test after the rule it pins. AC-6 is **mechanical**. Every
facility fixture is hand-built, and no test depends on a generator sample.

## Deferred verifications

**D-1. Refused turns are free.** Use `scripts/mutate.sh` to add an instability
point on the `out_of_reach` path. AC-4 **must** then fail, and AC-3 **must**
still pass. RED cannot run this. Owner: GATES.

**D-2. Liveness is per track, not global.** Use `scripts/mutate.sh` to make
`isLive` return true only for track 1's head. AC-1 **must** then fail. Owner:
GATES.

## Out of scope

- The finale window and partner lamps (`PROC-002`).
- The clock penalty, blackouts and outcomes (`PROC-003`).
- The remote and the reply to the client (`PROC-005`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/procedure/Procedure.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

