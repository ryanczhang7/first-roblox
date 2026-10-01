---
id: PROC-001
title: A turn commits a live step on the right setting and says why it failed otherwise
slug: a-turn-commits-a-live-step-on-the-right
epic: EPIC-05
type: feature
status: done
phase: DONE
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

**Pinned semantics (PO, at PLANNED → RED, 2026-10-01).** RED may amend any block
below in place, with a dated reason next to it; GREEN builds what the amended
block says.

- **P-1. Tuning lives in the state.** `tuning` is `MechanicsTuning.MechanicsTuning`
  (`src/shared/MechanicsTuning.luau`). `start` stores it as
  `ProcedureState.tuning`, and `turn` and `dial` read every constant from there:
  `instance.turn_range_studs`, `instance.dial_settings`,
  `actuation.actuation_reset_seconds`, `actuation.instability_per_wrong_value`,
  `actuation.instability_per_out_of_order`. Tests pass a tuning built from
  `MechanicsTuning`'s defaults with values *overridden* where a test needs to
  tell two constants apart (e.g. `instability_per_wrong_value = 1`,
  `instability_per_out_of_order = 2`) — the shipped values are both 1, and a
  test that cannot tell which one was charged pins nothing.
- **P-2. Tracks.** An **ordinary** step is `facility.steps.tracks[t][i]` for
  `i < #tracks[t]`; the last entry of each track is its finale step
  (`facility.steps.finale`). A machine in `facility.placement.machines` that is
  in no track is a **decoy**. A machine is found by its `id` field, not by its
  index in `machines`.
- **P-3. Liveness.** `isLive(state, id)` is true iff `id` is
  `tracks[t][k]` where `k` is the smallest index in track `t` whose machine is
  not committed, **and** `k < #tracks[t]`. Finale steps, decoys, committed
  machines and unknown ids are never live in this story.
- **P-4. Reach, inclusive.** In reach iff `positions[playerId]` exists and
  `sqrt((p.x-m.x)^2 + (p.z-m.z)^2) <= turn_range_studs`, where
  `m = Machines.positionOf(facility.layout, machine, tuning)`. `y` is ignored.
- **P-5. Key holder.** `machine.keyClass` is in `assignment.keyClasses[playerId]`.
  A player absent from `keyClasses` is `not_key_holder`.
- **P-6. The reset window, half-open.** A rejection at `now` stores
  `dials[id] = { setting = setting, rejectedUntil = now + actuation_reset_seconds }`.
  At time `t`: `t < rejectedUntil` → `dial` is `{ setting = setting, state =
  "rejected" }` and a turn is `refused / resetting`; `t >= rejectedUntil` →
  `{ setting = nil, state = "unset" }` and a turn is evaluated. (The phase
  machine's convention: the boundary instant is *after*.)
- **P-7. Dial views.** Never turned: `{ setting = nil, state = "unset" }`.
  Committed: `{ setting = <the committing setting>, state = "committed" }`.
- **P-8. Which constant a rejection charges.** `wrong_setting` adds
  `instability_per_wrong_value`; `not_live` adds `instability_per_out_of_order`.
  `not_live` wins when both are true (a waiting step or decoy, any setting).
- **P-9. Results.** `committed`/`rejected`/`refused` all carry `machineId` =
  the id that was passed, `unknown_machine` included. A refused turn returns a
  state deep-equal to the one passed.
- **P-10. Log.** Appended in call order. `at = now`; `result` is `"committed"`,
  `"wrong_setting"` or `"not_live"`.
- **P-11. Non-mutation.** The `state`, `assignment` and `positions` passed to
  any function are deep-equal before and after the call.

**Test files.** `tests/server/procedure_test.luau` (settled and mechanical ACs)
and `tests/server/procedure_controls_test.luau` (the AC-1 and AC-4 controls),
following the repo's `<module>_test` / `<module>_controls_test` convention.

**Callers of changed signatures.** None. `Procedure` is a new module, and no
existing export's signature changes: `Generator.Facility`, `Ring.Assignment`,
`Ring.withdraw` and `Machines.positionOf` are consumed as they stand on `main`
at `a50ee46`. Checked with `ls src/server/procedure` (absent) and the
signatures read from `src/server/facility/{Generator,Machines,Steps}.luau` and
`src/server/seats/Ring.luau`.

**Epic check (PO, 2026-10-01).** EPIC-05 done-when #1 and #2 are this story's,
with three exceptions owned elsewhere and already written into those stories:
the `armed` refusal (`PROC-002` AC-5), phase legality and the rate limit
(`PROC-005`). No gap.

**Oracle partition.** AC-1 to AC-5 are **settled** by `mechanics.md` §3.2 and §5
(G12). Name each test after the rule it pins. AC-6 is **mechanical**. Every
facility fixture is hand-built, and no test depends on a generator sample.

## Deferred verifications

**D-1. Refused turns are free.** Use `scripts/mutate.sh` to add an instability
point on the `out_of_reach` path. AC-4 **must** then fail, and AC-3 **must**
still pass. RED cannot run this. Owner: GATES.

*Result (GATES, 2026-10-01, lead-po): HOLDS.* The refused-turn return was
mutated to hand back a copy charged one point when the reason is
`out_of_reach`. Three AC-4/AC-6 tests went red, **no AC-3 test did**, and the
file was restored byte-for-byte. Matches the handoff's D-1 stand-in (3 checks).

    === mutate: src/server/procedure/Procedure.luau (1 line(s) changed by s#return state, { kind = "refused", machineId = machineId, reason = reason }#local c = copy(state); if reason == "out_of_reach" then c.instability += 1 end; return c, { kind = "refused", machineId = machineId, reason = reason }#) ===
      228 - 		return state, { kind = "refused", machineId = machineId, reason = reason }
      228 + 		local c = copy(state); if reason == "out_of_reach" then c.instability += 1 end; return c, { kind = "refused", machineId = machineId, reason = reason }

    === mutate: running sh -c lune run test 2>&1 | grep -E "^  FAIL |passed, [0-9]+ failed" ===
      FAIL  tests/server/procedure_test.luau :: AC-4/P-4: the holder just past turn_range_studs horizontally, or with no accepted position, is refused / out_of_reach
      FAIL  tests/server/procedure_test.luau :: AC-4: the refusal checks run unknown_machine, not_key_holder, out_of_reach, committed, resetting in that order and the first failure wins
      FAIL  tests/server/procedure_test.luau :: AC-6/P-10: the log holds one { playerId, machineId, setting, at, result } per evaluated turn, in call order, and none for a refused one
    687 passed, 3 failed

    === mutate: command exited 0; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_procedure_Procedure.luau.20261001T224324Z.3034020.bak) ===
      228: 		return state, { kind = "refused", machineId = machineId, reason = reason }

**D-2. Liveness is per track, not global.** Use `scripts/mutate.sh` to make
`isLive` return true only for track 1's head. AC-1 **must** then fail. Owner:
GATES.

*Result (GATES, 2026-10-01, lead-po): HOLDS.* `isLive`'s track loop was cut
to track 1 alone. All three AC-1 tests went red, plus AC-5, whose supplier
commits a track-2 head. The file was restored byte-for-byte. Matches the
handoff's D-2 stand-in (4 checks).

    === mutate: src/server/procedure/Procedure.luau (1 line(s) changed by s#for _, track in state.facility.steps.tracks do#for _, track in { state.facility.steps.tracks[1] } do#) ===
      98 - 	for _, track in state.facility.steps.tracks do
      98 + 	for _, track in { state.facility.steps.tracks[1] } do

    === mutate: running sh -c lune run test 2>&1 | grep -E "^  FAIL |passed, [0-9]+ failed" ===
      FAIL  tests/server/procedure_test.luau :: AC-1: after the first step of track 1 commits, the second step of track 1 is live and track 2's head is unchanged
      FAIL  tests/server/procedure_test.luau :: AC-1: at start exactly the first step of each track is live - not the finale steps, not a decoy, not an unknown id (P-3)
      FAIL  tests/server/procedure_test.luau :: AC-1: tracks advance independently and a finale step is never live in this story, even with every ordinary step committed (finale_live_together)
      FAIL  tests/server/procedure_test.luau :: AC-5: after Ring.withdraw moves the leaver's class to their supplier, the supplier is judged the key holder of that class - and was not before, and the leaver no longer is
    686 passed, 4 failed

    === mutate: command exited 0; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_procedure_Procedure.luau.20261001T224555Z.3041846.bak) ===
      98: 	for _, track in state.facility.steps.tracks do

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
- PLANNED -> RED orchestration - `lead-po` - `claude-opus-5-5` (this /advance-story
  session). 2026-10-01.
- RED - `test-developer` - `claude-fable-5-1` (dispatched with `model: fable` explicitly,
  per the dispatch note; the agent reported the resolved id). 2026-10-01.
- GREEN - `feature-developer` - `claude-opus-5-5` (dispatched with `model: opus`, the
  planned row; the agent reported the resolved id). 2026-10-01.

## Test plan

All unit level: `Procedure` is pure, so every criterion is falsifiable by calling
it on a hand-built facility. Nothing is mocked; `Machines.positionOf` and
`Ring.withdraw` are the real modules.

**Layout.** The checks live once in `tests/helpers/TurnContract.luau` (the
house `<Module>Contract` pattern; `ProcedureContract.luau` was already taken by
GEN-003's Steps helper, hence the name), applied to the real module by
`tests/server/procedure_test.luau` and to a reference stand-in plus six
one-defect stand-ins by `tests/server/procedure_controls_test.luau`. The
stand-ins are inside the controls file, as the brief asked.

**Fixture** (`TurnContract.facility()`, `.assignment()`, `.tuning()`), all
hand-built, no generator, no seed:

- four rooms on a 2 x 2 block (ids 1..4), doors in a square, `spawnRoom = 1`;
- nine machines with ids 11..19 in a list order where `machines[i].id ~= i` for
  every `i` (P-2: found by `id`); each carries `id, room, slot, keyClass, tag,
  requiredSetting`;
- `tracks = { {11, 12, 13}, {14, 15, 16, 17} }`, `finale = {13, 17}` - two
  tracks of UNEQUAL length; decoys 18 (class 3) and 19 (class 1). `Steps.check`
  would reject this; `Procedure` must not care;
- ring kim -> zed -> amy -> bob -> kim, class `i` at seat `i`, lens `k(σ(p))`;
  kim's supplier is bob (AC-5);
- tuning = shipped `MechanicsTuning` with `turn_range_studs 10 -> 7`,
  `actuation_reset_seconds 3 -> 5`, `instability_per_out_of_order 1 -> 2`
  (`instability_per_wrong_value` stays 1), so a constant read from the module
  instead of `state.tuning` (P-1) or two charges that cannot be told apart (P-8)
  fail. A fixtures test asserts each override still differs from the shipped
  value it exists to be told apart from.

**Tests, by criterion** (names are the rules they pin; see the handoff table):

| AC | Tests |
|---|---|
| Contract | export shape; `start` returns `{facility, committed = {}, dials = {}, instability = 0, log = {}, tuning}`; `turn` returns `(state, result)` |
| AC-1 | live set at start is exactly `{11, 14}` over all ids + unknown; after 11 commits it is `{12, 14}`; after 11, 12 it is `{14}` (finale 13 waiting); after 14, 15, 16 too it is `{}` |
| AC-2 | holder in reach on the required setting -> `committed`, `committed[11] == true`, `dial` = `{setting, "committed"}` now and 1000 s later, 12 live, instability 0; reach inclusive at exactly 7 along x and -z, and with y +/-1000 |
| AC-3 | live + wrong -> `rejected/wrong_setting` +1, `dials[11] = {setting, rejectedUntil = now + 5}`, dial rejected, live set unchanged; waiting step (12) on the right AND wrong setting -> `not_live` +2; finale 13 -> `not_live` +2 both before and after its own track's ordinary steps commit; decoys 18, 19 -> `not_live` +2; 1 + 2 accumulate to 3; dial at now, now + 2.5, now + 4.999 rejected, at now + 5 and now + 105 unset; turn at now + 4.999 `refused/resetting`, at now + 5 `committed` |
| AC-4 | `unknown_machine` (id 99, echoed); `not_key_holder` for zed, for a stranger absent from `keyClasses`, and on a wrong setting; `out_of_reach` at 7.001 along x, (7, 7) diagonal, (0.5, 7), no position, only others positioned, rooms away; `committed` on right and wrong setting; `resetting` at +0, +2.5, +4.999; ordering: unknown > not_key_holder > out_of_reach over six two- and three-way conflicts. Every refusal: result exact, state deep-equal to the one passed, instability, log length and dial view unchanged |
| AC-5 | bob refused before `Ring.withdraw(kim)`; after it (`keyClasses.bob == {4, 1}`) bob commits 11; kim refused; bob still commits his own 14 |
| AC-6 | eight-call sequence (3 evaluated, 5 refused, interleaved) -> log deep-equals exactly three `{playerId, machineId, setting, at, result}` entries in call order; `start` log is `{}`; final instability 3 |
| P-11 | `start`, `isLive`, `dial`, and every turn kind leave state, assignment, positions, facility deep-equal to their snapshots; a turn on a new state does not write through to the old |

**Controls** (`procedure_controls_test.luau`): the reference stand-in passes all
20 checks; six one-defect stand-ins each fire an EXACT, measured set of checks
(table in the handoff). Plus four fixture-assumption tests.

**Not pinned, deliberately:** the key set of `ProcedureState` beyond the six
Contract fields (PROC-002/003 add fields); `dials[id]` after a COMMIT (only the
`dial` view); `dial` on an unknown id; `committed`-before-`resetting` ordering
(no correct module can hold a commit inside a reset window, so no test can
observe it); error text.

## Handoff: RED -> GREEN

**RED run on `fable` (the planned row).** The dispatch passed `model: fable`
explicitly; this agent identifies as `claude-fable-5-1`. 2026-10-01.

### The command

    lune run test                      # the `unit` gate, whole suite
    lune run test -- --list            # 690 tests; 33 under tests/server/procedure*

There is no per-file filter in the runner; the new tests are the only red ones,
so `lune run test 2>&1 | grep -E "procedure|passed, .* failed"` is the quick view.

### The failure, verbatim (2026-10-01, local)

    FAIL  tests/server/procedure_test.luau :: AC-1: at start exactly the first step of each track is live - not the finale steps, not a decoy, not an unknown id (P-3)
          C:\Users\ryanc\Projects\first-roblox\tests\server\procedure_test:38: src/server/procedure/Procedure.luau did not load: error requiring module "../../src/server/procedure/Procedure": could not resolve child component "procedure"
    ... (the same line under each of the 22 tests in procedure_test.luau) ...
    668 passed, 22 failed

**Why it is the right failure.** The story's first requirement is the module
`src/server/procedure/Procedure.luau`, which does not exist; every one of the 22
tests in `procedure_test.luau` fails at that `require` and nothing else in the
suite moved (657 pre-existing tests still pass; the 11 new controls pass). The
`pcall(require)` pattern gives one red line per criterion rather than one LOAD
FAIL for the file. Because the module is missing, **no assertion in
`procedure_test.luau` has executed** - which is why the controls file exists and
why its numbers below are the evidence that the checks discriminate.

### `bash scripts/gates.sh --fast` (2026-10-01, local)

See `## Notes` for the pasted summary. Shape: `format`, `lint`, `typecheck` and
`build` green; `unit` red with the 22 load failures above; `harness` red on the
counter baselines pre-set to GREEN's predicted values (see "Counters" below).

### Files touched

| File | What |
|---|---|
| `tests/helpers/TurnContract.luau` | NEW. The fixture and all 20 checks, each `(P) -> ()` raising via `Contract.fail` with the AC in the message. `TurnContract.CHECKS` lists them; `TurnContract.failures(P)` runs them all |
| `tests/server/procedure_test.luau` | NEW. 22 tests applying the checks to the real module |
| `tests/server/procedure_controls_test.luau` | NEW. 11 tests: baseline, 4 fixture-assumption tests, 6 one-defect controls. Contains the reference stand-in |
| `.claude/tests/project-counters.test.sh` | baselines moved to GREEN's predicted values (below) |
| `docs/backlog/stories/PROC-001.md` | this section and `## Test plan` |

No `src/**` file was touched. No manifest change. `.gitignore` untouched.

### One row per test (procedure_test.luau)

| Test | Asserts | Covers |
|---|---|---|
| Contract: exports start, isLive, dial, turn | all four are functions | Contract |
| Contract: start returns the ProcedureState | `facility` deep-equals input, `committed = {}`, `dials = {}`, `instability = 0`, `log = {}`, `tuning` deep-equals the tuning passed | Contract, P-1 |
| Contract: turn returns two values | first a table, second a table with a string `kind` | Contract |
| AC-1: at start exactly the track heads are live | live set over 11..19 and 99 is exactly `{11, 14}` | AC-1, P-3 |
| AC-1: after track 1's head commits its second step is live | live set is `{12, 14}` after kim commits 11 | AC-1 |
| AC-1: tracks advance independently, finale stays waiting | after 11, 12: `{14}`; after 14, 15, 16 too: `{}` | AC-1, P-3, G12 |
| AC-2: holder in reach on the required setting commits | result `{kind="committed", machineId=11}`; `committed[11]==true`; `dial` = `{setting=2, state="committed"}` at now and now+1000; 11 not live, 12 live; instability 0 | AC-2, P-7, P-9 |
| AC-2/P-4: reach inclusive, ignores y | commits at offsets (7,0,0), (0,0,-7), (0,1000,0), (7,-1000,0) with the fixture's range 7 | AC-2, P-4, P-1 |
| AC-3: wrong setting on a live step | `rejected/wrong_setting`; +1 (`instability_per_wrong_value`); `dials[11] = {setting, rejectedUntil = now+5}`; dial `{setting, "rejected"}`; not committed; live set unchanged | AC-3, P-6, P-8 |
| AC-3: waiting step is not_live whatever the setting | 12 on right and wrong setting, 13 before and after track 1's ordinary steps commit: `rejected/not_live`, +2 each | AC-3, P-8 |
| AC-3: decoy is not_live whatever the setting | 18 on right, 19 on wrong: `not_live`, +2 | AC-3, P-8 |
| AC-3/P-1: charges accumulate by reason | wrong (1) then decoy (2) = 3 | AC-3, P-1, P-8 |
| AC-3/P-6: half-open reset window | dial rejected at +0, +2.5, +4.999; unset at +5, +105; turn at +4.999 `refused/resetting` with state deep-equal; turn at +5 `committed` | AC-3, AC-4, P-6 |
| AC-4: unknown_machine | id 99 -> `refused/unknown_machine`, `machineId = 99`, state deep-equal | AC-4, P-9 |
| AC-4/P-5: not_key_holder | zed on 11, stranger on 11, zed on wrong setting: refused, state deep-equal, no charge, no log entry, dial unchanged | AC-4, P-5 |
| AC-4/P-4: out_of_reach | six cases: 7.001 along x; (7,7); (0.5,7); no position; only zed positioned; at machine 17 | AC-4, P-4 |
| AC-4: committed | right and wrong setting on committed 11 -> `refused/committed` | AC-4 |
| AC-4: resetting | +0, +2.5, +4.999 after rejection -> `refused/resetting` | AC-4, P-6 |
| AC-4: order, first failure wins | 6 conflicts (see Test plan) | AC-4 |
| AC-5: supplier judged holder after withdraw | bob refused before; `Ring.withdraw(kim)` -> bob commits 11; kim refused; bob commits 14 | AC-5 |
| AC-6/P-10: the log | 8-call sequence -> exactly 3 entries, exact fields and order; `start` log `{}`; instability 3 | AC-6, P-10 |
| P-11: no call mutates its arguments | start/isLive/dial/every turn kind; downstream turn does not write through | P-11 |

### The export shape the tests pin

Nothing below is a suggestion. Each name and signature is already called by a
test, so getting it wrong is a red test rather than a debate.

    src/server/procedure/Procedure.luau          -- required as "../../src/server/procedure/Procedure"
                                                 -- from tests/server; returns a table

    Procedure.start(facility, now: number, tuning) -> ProcedureState
        -- facility: a Generator.Facility-shaped table { layout, placement, steps, spawnRoom, par, attempt }
        -- tuning:   MechanicsTuning.MechanicsTuning (the test passes a frozen deep copy with overrides)
        -- returns { facility = <the same, deep-equal>, committed = {}, dials = {}, instability = 0,
        --           log = {}, tuning = <the tuning passed> }   -- extra fields are NOT forbidden
    Procedure.isLive(state, machineId: number) -> boolean   -- a real boolean; truthy is not enough
    Procedure.dial(state, machineId: number, now: number) -> { setting: number?, state: "unset" | "committed" | "rejected" }
        -- deep-equal is used: no other keys. unset => setting nil (absent)
    Procedure.turn(state, assignment, playerId: string, machineId: number, setting: number,
                   now: number, positions: { [string]: { x, y, z } }) -> (ProcedureState, TurnResult)

    TurnResult, compared with Deep.equal, so EXACTLY these keys:
        { kind = "committed", machineId = id }
        { kind = "rejected",  machineId = id, reason = "wrong_setting" | "not_live" }
        { kind = "refused",   machineId = id, reason = "unknown_machine" | "not_key_holder"
                                                     | "out_of_reach" | "committed" | "resetting" }
        -- machineId is ALWAYS the id passed, unknown_machine included (P-9)

    ProcedureState fields the tests read:
        state.committed[id] == true after a commit; not truthy otherwise
        state.dials[id] == { setting = <setting>, rejectedUntil = now + actuation_reset_seconds }
                           immediately after a rejection (P-6; deep-equal, so no extra keys THERE)
        state.instability: number
        state.log: { { playerId, machineId, setting, at = now, result = "committed" | "wrong_setting" | "not_live" } }
                   deep-equal, so exactly those five keys per entry
        state.tuning: the tuning passed to start; turn/dial read
                   tuning.instance.turn_range_studs, tuning.actuation.actuation_reset_seconds,
                   tuning.actuation.instability_per_wrong_value, tuning.actuation.instability_per_out_of_order
                   FROM HERE (the fixture overrides them; the shipped values fail P-1/P-4/P-6/P-8 tests)

    Dependencies the tests imply: Machines.positionOf(facility.layout, machine, tuning) for reach
    (the tests compute positions with it, offsets included), and assignment.keyClasses[playerId]
    as a LIST searched for machine.keyClass (Ring.Assignment as it stands; AC-5 uses the real
    Ring.withdraw). A refused turn must return a state deep-equal to the one passed - returning
    the same table is fine.

**Not constrained** (implementer's choice): how a new state is copied (sharing
the immutable `facility` is fine; the P-11 test checks that a turn on a new
state does not write through to the old `committed`/`dials`/`log`); what
`dials[id]` holds after a COMMIT (only `dial()`'s view is pinned); `dial()` on
an unknown id; any `committed`-before-`resetting` ordering; extra state fields;
error messages; whether `isLive` is used internally by `turn`.

### Tests that passed on arrival

None in `procedure_test.luau` (all 22 red at `require`). The 11 tests in
`procedure_controls_test.luau` are green by design: they run the checks against
stand-ins and are the negative controls themselves. What earns them is the table
below - six defective stand-ins each fire a measured, exactly-pinned set of
checks, and the reference fires none.

### Negative controls - expected and measured (RED, 2026-10-01, local, `lune run test`)

Every value below was MEASURED in RED by running the checks in
`TurnContract.luau` against the stand-ins in the controls file (no production
module involved). The controls file asserts these sets EXACTLY; confirming that
the same checks accept the shipped module is GREEN's job (all 22 tests green),
and D-1/D-2 below are GATES's.

| Control (stand-in with one defect) | Must fail | Checks that fired (measured) | Checks that stayed green |
|---|---|---|---|
| reference (no defect) | nothing | **0 of 20** | all 20 |
| AC-1's named control: `isLive` true for every step of track 1 | AC-1 | 5: `liveSetAtStartIsExactlyTheTrackHeads`, `committingTheHeadOfTrackOneMakesItsSecondStepLive`, `tracksAdvanceIndependentlyAndFinaleStepsStayWaiting`, `holderInReachOnTheRequiredSettingCommits` (11 still live after its commit), `waitingStepIsNotLiveWhateverTheSetting` (12 commits instead of not_live) | 15 |
| D-2's shape: liveness global - only track 1's head, never track 2's | AC-1 | 4: the three AC-1 checks, `supplierIsJudgedKeyHolderAfterWithdraw` (bob's own 14 heads track 2 and read not_live) | 16 |
| AC-4's named control: the key-holder check skipped, non-holders evaluated | AC-4 | 4: `nonHolderIsRefusedAndNotCharged`, `refusalChecksRunInOrderAndTheFirstFailureWins`, `supplierIsJudgedKeyHolderAfterWithdraw` (bob commits BEFORE the transfer), `logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals` (amy's "refused" turn commits 12) | 16 - AC-3 all green |
| D-1's shape: `out_of_reach` refusal adds 1 instability | AC-4, AC-3 green | 3: `holderOutOfHorizontalReachOrWithoutAPositionIsRefused`, `refusalChecksRunInOrderAndTheFirstFailureWins`, `logHolds...` (instability 4, not 3) | 17 - **AC-3 all green, as D-1 requires** |
| P-8: `not_live` charged `instability_per_wrong_value` | AC-3 | 4: `waitingStepIsNotLiveWhateverTheSetting`, `decoyIsNotLiveWhateverTheSetting`, `chargesAccumulateByReason`, `logHolds...` | 16 |
| P-6: closed window (`t <= rejectedUntil` still resetting) | AC-3 boundary | 1: `rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset` | 19 |

The one correction made while measuring: the reference's first draft returned
early from track 1 and never looked at track 2 (fired the two AC-1 live-set
checks and two downstream). Fixed in the stand-in, not in a check; the checks
were right.

### Deferred verifications - declined here

- **D-1** (mutate the real `out_of_reach` path to add a point; AC-4 must fail,
  AC-3 must pass) - **not run; cannot be run in RED**: the module does not
  exist. Owner GATES. The D-1-shaped stand-in above shows the checks WOULD see
  it with AC-3 green, which is evidence about the tests, not about the module.
- **D-2** (mutate the real `isLive` to track 1's head only; AC-1 must fail) -
  **not run; cannot be run in RED**. Owner GATES. Same remark.

### Callers of changed signatures

Checked against the tree at `a50ee46` + this branch: `src/server/procedure/`
does not exist (the runner's own error says so: "could not resolve child
component procedure"); `Generator.Facility`, `Ring.Assignment`, `Ring.withdraw`
and `Machines.positionOf` are consumed unchanged. The Contract's "None" stands.

### Counters (`.claude/tests/project-counters.test.sh`)

RED added three `.luau` files under `tests/` (119 -> 122). GREEN adds exactly
one under `src/` (`src/server/procedure/Procedure.luau`). The baselines are set
NOW to GREEN's predicted values, per the memory rule and GEN-001..GEN-004's
practice: `BASE_FORMAT=123 BASE_LINT=123 BASE_TYPECHECK=24 NARROW_FORMAT=24
NARROW_LINT=24 NARROW_TYPECHECK=8`. The `harness` gate is red in RED by design
(`expected 123 / actual 122`, `24 / 23`) and must go green in GREEN without any
edit to that file - `.claude/tests/**` is frozen for GREEN by
`check-boundaries.sh` 3j. **The RED commit must carry the counters file and the
three test files with the story at `phase: RED`** (GEN-001 needed a return to
RED to make exactly that commit).

### Notes for the implementer

- Read every constant from `state.tuning`, never from `MechanicsTuning` at
  module load. The fixture's range is 7 and reset is 5; the shipped 10 and 3
  fail four tests.
- Find the machine by its `id` field. The fixture's list order is scrambled so
  that `machines[id]` is nil or the wrong machine.
- An ordinary step is `tracks[t][i]` for `i < #tracks[t]`, per track; the
  fixture's tracks are 3 and 4 long. Do not read `steps_per_track`.
- The refusal order is tested where two checks fail at once: unknown >
  not_key_holder > out_of_reach > committed/resetting. Evaluate reach as
  `sqrt(dx^2 + dz^2) <= turn_range_studs` with `y` ignored; the inclusive case
  is tested at exactly the range along one axis.
- The boundary is half-open: `now < rejectedUntil` is resetting; `now >=
  rejectedUntil` is evaluated.
- `dial` for a committed machine shows the committing setting regardless of
  `now`.
- The log entry has exactly five keys. `at = now`.
- No `## Contract` block was amended. Nothing in P-1..P-11 contradicted what was
  measured.

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

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-10-01T22:56:06Z
    commit: 507de3a
    tree:   a47983b2bc792f7b1b6e65ba814b51d4e42da651
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 123)
    PASS         lint (1s, observed 123, floor 1)
    PASS         typecheck (3s, observed 24)
    PASS         unit (148s, observed 690, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 86200)
    PASS         harness (33s, observed 40)
    UNCONFIGURED mutation

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

**RED `bash scripts/gates.sh --fast`, 2026-10-01, local (not a recorded run;
pasted here by the Test Developer for the shape of the failure only).**

    --- gate summary ---
    PASS         format (0s, observed 122)
    PASS         lint (0s, observed 122, floor 1)
    PASS         typecheck (4s, observed 23)
    FAIL         unit (123s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 82855)
    FAIL         harness (26s, exit 1) -> .claude/state/gate-logs/harness.log

    --fast skipped: integration mutation

- `unit`: `668 passed, 22 failed` - the 22 are every test in
  `tests/server/procedure_test.luau`, each at the missing `require`. The right
  failure. The unit gate took 123 s locally; the new tests add well under a
  second of that (the Steps/Facility sweeps are the cost).
- `harness`: `project-counters: 28 passed, 12 failed` - 11 are the counter
  baselines pre-set to GREEN's predicted values (`expected 123 / actual 122`,
  `24 / 23`, and the untracked/ignored/narrow variants), and 1 is the
  "no stray .luau files" precondition, which the RED commit of the three test
  files clears. Both are the design working (see the handoff's "Counters");
  neither is to be fixed by editing the suite in GREEN.
- `format`, `lint`, `typecheck`, `build` green: the three new test files are
  stylua-clean and selene-clean (0 errors, 0 warnings). The typecheck gate
  analyses `src` only and did not read them.


**PO verification of RED, 2026-10-01 (lead-po, independent of the Test
Developer's own runs).**

- Read `tests/server/procedure_test.luau` in full and
  `TurnContract.refusalChecksRunInOrderAndTheFirstFailureWins`: six two-way
  ordering cases, each pitting an earlier check against a later one, on a
  resetting state created at `NOW` and turned at `NOW + 1` (inside the fixture's
  5 s window). The 22 tests map one-to-one onto AC-1..AC-6, P-4, P-6, P-8, P-11.
- `lune run test`: `668 passed, 22 failed`. Every one of the 22 failures, grouped
  by message:
  `22 src/server/procedure/Procedure.luau did not load: error requiring module
  "../../src/server/procedure/Procedure": could not resolve child component
  "procedure"`. The right failure, and every pre-existing test passes.
- `bash scripts/gates.sh --fast`: format PASS (observed 122), lint PASS (122),
  typecheck PASS (23), build PASS, unit FAIL (the 22 above), harness FAIL (the
  `expected count: 123/24/124/25` lines only — the baselines pre-set to GREEN's
  predicted values). Admissible.
- The extra helper `tests/helpers/TurnContract.luau` is accepted: it is the house
  pattern (`ProcedureContract.luau`, `FacilityContract.luau`), and it is what lets
  the controls run the identical checks.
- RED commit made with the story at `phase: RED`, carrying the tests and the
  counter baselines, so check-boundaries 3j sees the `.claude/tests/**` change in
  a RED commit (memory: counter baselines move in RED).

### GREEN notes

Feature Developer, 2026-10-01. Dispatched with no model override; the agent
definition's `model: opus` applies, and this session identifies as
`claude-opus-5-5`.

**Files changed.** One new file, `src/server/procedure/Procedure.luau` (pure,
`table.freeze`d, no module state). No config change: `default.project.json`
maps `src/server` recursively, so rojo picks up `src/server/procedure/` on its
own, and the typecheck gate regenerates `sourcemap.json` (git-ignored) on every
run. No test file and nothing under `.claude/tests/**` was touched.

**`lune run test`:** `690 passed, 0 failed` - all 22 in
`tests/server/procedure_test.luau` and all 11 in
`tests/server/procedure_controls_test.luau` pass.

**`bash scripts/gates.sh --fast`** (not a recorded run):

    PASS         format (1s, observed 123)
    PASS         lint (1s, observed 123, floor 1)
    PASS         typecheck (4s, observed 24)
    PASS         unit (165s, observed 690, floor 507)
    UNCONFIGURED coverage
    PASS         build (1s, observed 86200)
    PASS         harness (19s, observed 40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).

`harness` is `project-counters: 40 passed, 0 failed`: RED's pre-set baselines
(123 / 24) match with the one new file present, untracked.

**Controls confirmed against the shipped module.** `TurnContract.failures`
run against the real `Procedure` (from a scratch script outside the repo, no
test file added): `real Procedure fails 0 of 20 checks` - matches the
reference row (0 of 20). The six one-defect stand-ins re-measured in this run
fire exactly the sets RED recorded (5 / 4 / 4 / 3 / 4 / 1); the controls file
asserts them exactly and passes. No divergence.

**Contract findings.** Nothing contradicted. The named mechanisms hold as
written: `Machines.positionOf(layout, machine, tuning)` exists with that
signature; `Ring.Assignment.keyClasses[p]` is a list (`Ring.withdraw` appends
the leaver's classes to the supplier's); every constant P-1 names exists in
`MechanicsTuning`. Two small notes, neither a change of meaning:
- The Contract's `ProcedureState` type block lists five fields but P-1 adds
  `tuning`; the module's exported type carries all six.
- The first `--fast` run failed `typecheck` (and `harness`, through it):
  luau-lsp widened a refined `reason ~= nil` local to `string` inside the
  `refused` result literal. Fixed by annotating the local's singleton union
  type; no behaviour change, tests re-run green.

D-1 and D-2 not run (owner GATES). Full `gates.sh` not run (GATES).

**PO verification of GREEN, 2026-10-01 (lead-po).**

- Freeze: `bash scripts/frozen.sh snapshot` taken right after `phase.sh set
  PROC-001 GREEN`, over the three test files and
  `.claude/tests/project-counters.test.sh`. Before leaving GREEN:
  `frozen: OK — 4 path(s) unchanged since the snapshot for PROC-001`.
- Read `src/server/procedure/Procedure.luau` in full against P-1..P-11. One
  observation, not a defect: a refused turn returns the *same* state table it
  was handed rather than a copy. P-9 asks only for deep-equality and states are
  never mutated (D3), so this is within the contract; the Contract's sentence
  "Every call returns a new state" is to be read as "never a mutated one".
- The handoff's controls table, checked against the real module by mutation
  (`scripts/mutate.sh`, full `lune run test` each, restores verified by `cmp`):

  | Mutation | Handoff predicted | Observed |
  |---|---|---|
  | P-6 closed window: `now < d.rejectedUntil` -> `now <= d.rejectedUntil` | 1 check: `rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset` | `689 passed, 1 failed` — exactly `AC-3/P-6: a rejected dial shows the setting as rejected …` |
  | P-8 flat charge: `not_live` charged `instability_per_wrong_value` | 4: waiting, decoy, accumulate, log | `686 passed, 4 failed` — `AC-3/P-1 charges accumulate…`, `AC-3: a decoy…`, `AC-3: a waiting step…`, `AC-6/P-10: the log…` |

  Both counts match; the table is evidence, not a claim. The file was restored
  byte-for-byte after each.
- `bash scripts/gates.sh --fast` on the unmutated tree: format PASS (123), lint
  PASS (123), typecheck PASS (24), unit PASS (`690 passed, 0 failed`, 183 s),
  build PASS, harness PASS (`project-counters: 40 passed, 0 failed`). `All
  required gates passed (6 ran, 1 unconfigured, 0 known).`
- D-1 and D-2 not yet run: owner GATES.

**PO record of GATES, 2026-10-01 (lead-po).**

- Freeze snapshot retaken right after `phase.sh set PROC-001 GATES` (same four
  paths). After D-1, D-2 and the full run: `frozen: OK — 4 path(s) unchanged since the snapshot for PROC-001`.
- D-1 and D-2 run before `gates.sh`, both HOLD; output pasted under
  `## Deferred verifications`.
- Full `bash scripts/gates.sh`: `All required gates passed (6 ran, 3
  unconfigured, 0 known)`, recorded by the script under `## Gate results`.
  The three UNCONFIGURED gates (coverage, integration, mutation) are optional
  and unconfigured repo-wide; `unit` is the one this story names, and it ran
  690 tests (floor 507) in 148 s. This story adds no gate, so there is no
  `## Gate probes` entry.

**PO (2026-10-01, DONE). Merged.** PR https://github.com/ryanczhang7/first-roblox/pull/47
was merged at 2026-10-01T23:54:29Z as `1a7c9d2`. Both CI checks passed.
`boundaries` took 6 s. `gates` took 4m08s against `timeout-minutes: 45`
(https://github.com/ryanczhang7/first-roblox/actions/runs/36938342854). The CI
gate timings were format 1s, lint 0s, typecheck 3s, unit 63s (690 passed),
build 0s and harness 15s. Nothing is near a limit, and no gate was pending CI.
**Trend:** CI unit went from 40 s (GEN-004) to 63 s. PROC-001's 33 tests run on
hand-built fixtures with no sweeps, so they are unlikely to account for 23 s.
Local unit times varied between 123 s and 183 s over identical trees this
session, which points to runner variance. Watch it on PROC-002 rather than act
on one sample. EPIC-05's done-when #1 and #2 are delivered for ordinary steps.
The armed refusal, phase legality and the rate limit remain with PROC-002 and
PROC-005, as planned.
