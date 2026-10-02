---
id: PROC-005
title: A turn arrives as a validated remote and is judged against server positions
slug: a-turn-arrives-as-a-validated-remote-and
epic: EPIC-05
type: feature
status: in-progress
phase: RED
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

**Pinned at PLANNED → RED (2026-10-02, lead-po).** RED may amend any block
below in place, with a reason; GREEN builds what the amended block says.

- **`TurnReply.machineId` is `number?`, not `number`.** `Procedure.TurnResult`'s
  `refused` arm types `machineId: number?`. Under `--!strict`, a `number` field
  fed from it cannot typecheck without a cast or an invented value. `reply`
  copies the result's `machineId` as it is, and never fabricates one. Today
  every path in `Procedure.turn` supplies it.
- **The reply's key set is exact.** For `committed` and `armed` it is
  `{ machineId, kind }`, and for `rejected` and `refused` it is
  `{ machineId, kind, reason }`. `reason` is the result's own reason string,
  unchanged. Nothing else appears: no `setting`, no `requiredSetting`, no
  `playerId`, no state.
- **`handle` is a pass-through.** It returns exactly the
  `(ProcedureState, TurnResult)` that `Procedure.turn(procedure, assignment,
  playerId, args.machine, args.setting, now, positions)` returns. It reads only
  `args.machine` and `args.setting`. Any other key in `args` is never read,
  including `position`, `positions`, `x`/`y`/`z` and `player`. The preferred
  oracle for AC-4 is **behavioural**: a real `Procedure.start` state in which
  the accepted position puts the key holder out of reach while a position
  smuggled into `args` would put them in reach, so the result must be
  `refused`/`out_of_reach` (and the mirror case committed). If RED spies on
  `Procedure.turn` by replacing the module field, `handle` must look it up
  through the module table at call time, and RED says so in the handoff.
- **AC-2 and AC-3 are tested through the real `Wrapper.guard`**, over the real
  `GameRemotes.Turn`, with a spy handler that records every call. "The
  Procedure is never consulted" means the spy was not called. An injected
  `GuardContext` supplies `isSeated`, `phase` and `clock`. The existing
  `tests/helpers/*Stubs`/`*Contract` show the pattern. Expected reasons:
  missing `setting` → `shape`; `machine = 0` → `range`;
  `setting = dial_settings + 1` → `range`; `setting = 1.5` → `range` (a
  non-integer is `range` under `Schema.integer`, see `src/net/Schema.luau`);
  an extra `player` key → `shape`; a string payload → `shape`.
- **The AC-3 rate case** makes two well-formed in-phase calls at `t` and at
  `t + turn_rate_limit_seconds − ε`. The second call is `rate` and the spy
  count stays at 1. A third call at `t + turn_rate_limit_seconds` passes, which
  keeps the boundary honest.
- **"Declares no attempt limit and never declines" (AC-1)** is pinned in this
  story as `GameRemotes.Turn.attemptLimit == nil`. The field does not exist
  yet: `CHAN-003` adds it. `CallControl.decline` does not exist either, so no
  handler built here *can* decline. The handler that receives a `Turn` call is
  `SLICE-005`'s. PO decision 1, below.
- **`GameRemotes` is created by this story with `Turn` alone**, because
  `CHAN-004` is still PLANNED. It is a module that calls `Remotes.define` at
  require time and returns `{ Turn = <definition> }`. The registry is
  module-level and Lune caches requires, so the definition is made once per
  test process. A test must not re-`define` `"Turn"`.

**Changed exports, and their callers.** None. `Remotes`, `Schema`, `Wrapper`
and `Procedure` keep their signatures. Both modules are new. Checked
2026-10-02: `rg -n 'GameRemotes|TurnRequests' src tests` returns nothing.
RED's handoff restates this against the tree.

**Oracle partition.**
- AC-1 is **settled**: read the values from `MechanicsTuning`.
- AC-2 and AC-3 are **mechanical**, and they are B4's adversarial triple.
- AC-4 and AC-5 are **mechanical**. AC-5's control is a hand-written copying
  reply.

## Deferred verifications

RED cannot run any of these, because nothing exists to break. RED declines
them in its handoff.

**D-1. AC-4 reads the accepted positions, not the payload.** Use
`scripts/mutate.sh` on `src/server/procedure/TurnRequests.luau` so that
`handle` passes a positions table built from `args` (or an empty table) in
place of `positions`. AC-4 **must** fail. Owner: GATES.

**D-2. AC-5's exact key set catches a leak.** Mutate `reply` to add one extra
field, such as `setting = 0` or `requiredSetting = 1`. AC-5 **must** fail.
Then mutate it to emit a wrong **value** (`kind` hard-coded to `"committed"`).
AC-5 **must** fail again. Owner: GATES.

**D-3. AC-1 reads the tuning, not a literal.** Mutate `GameRemotes`'s
`minIntervalSeconds` to `turn_rate_limit_seconds + 1`, and separately its
`setting` upper bound to `dial_settings + 1`. AC-1 **must** fail on each, and
AC-2's `dial_settings + 1` case **must** fail on the second. Owner: GATES.

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

Written in RED (2026-10-02, test-developer). Two new modules, so two real
suites that fail at `require` today, each backed by a helper carrying the
checks and a controls suite that EXECUTES every check in RED against a
reference and against one-defect stand-ins - the house `*Contract` /
`*_controls_test` arrangement.

**Level.** Integration for AC-1..AC-3: the real `Wrapper.guard` over the real
`Schema` and `Remotes`, driving the definition under test with an injected
`GuardContext` (`RateContract.world`: seated set, mutable phase, `Clock.manual`
set to each instant) and a spy handler. That is where B4's contract lives.
Unit for AC-4/AC-5: `TurnRequests` is pure, driven over the real `Procedure`
with `TurnContract`'s hand-built facility (machine 11, holder kim, fixture
`turn_range_studs` = 7). No Roblox, no real time, no seed-dependent fixture.

**Oracle partition, honoured.** AC-1 reads `actuator_count`, `dial_settings`
and `turn_rate_limit_seconds` out of `MechanicsTuning`; no literal is
written where a constant is meant. AC-2/AC-3 compare `Rejection.reason` by
exact equality and read the schema kind anchored at the start of the failure
string (`NetContract.kindOf`). AC-4's oracle is behavioural (accepted
positions vs a smuggled payload position disagree about reach; the real
Procedure says which was read) - no spy on `Procedure.turn`, no module field
replaced. AC-5 enumerates the reply's keys with `pairs` and compares the
sorted list exactly.

| File | Level | Covers |
|---|---|---|
| `tests/helpers/TurnRemoteContract.luau` | checks over `(Net, definition)` | AC-1 (5 checks), AC-2, AC-3 (2), positive control |
| `tests/net/turn_remote_test.luau` | real `GameRemotes.Turn` via `Remotes.all()` | 10 tests: Contract shape + the 9 checks |
| `tests/net/turn_remote_controls_test.luau` | reference + 10 one-edit declarations, run in RED | that every AC-1..3 check fires on exactly its defect |
| `tests/helpers/TurnRequestsContract.luau` | checks over a `TurnRequests` module; exact key-set checker | AC-4 (4 checks), AC-5 (3), Contract (2) |
| `tests/server/turn_requests_test.luau` | real `TurnRequests` over real `Procedure` | 9 tests |
| `tests/server/turn_requests_controls_test.luau` | reference + 13 one-defect stand-ins + the checker on hand-written replies, run in RED | that every AC-4/5 check fires on exactly its defect; the story's named control |

Edges covered: both bounds of each field at 0/1/max/max+1; non-integer in
each field; missing/extra/non-table payloads; all four illegal phases; rate
at `t`, `t + rate - 0.1`, exactly `t + rate`; every `TurnResult` kind and
every refused reason; a result with a smuggled extra field; purity of
`handle`. Out of scope (Session wiring, Transport, HUD) is not pinned - the
tests never touch `Session` or a transport.

## Handoff: RED -> GREEN

Written 2026-10-02 by test-developer. Dispatched with `model: fable` per the
plan; this agent's own definition says `model: opus`, and the dispatch
override is what the orchestrator should record as resolved.

### The command

    lune run test

There is no per-file filter in the runner; the whole suite is 811 tests and
took 6 m 32 s on this machine (the GEN sweeps, not this story). The new
tests are the lines matching `turn_remote` and `turn_requests`:

    lune run test 2>&1 | grep -E 'turn_remote|turn_requests|passed, '

### The failure, verbatim

    811 tests                         (lune run test -- --list)
    791 passed, 20 failed             (lune run test, before the one control fix below: 791 / 19 after it)

    FAIL  tests/net/turn_remote_test.luau :: Contract: GameRemotes exports Turn, and it is the same table Remotes.all() lists under the name Turn
          ...tests\net\turn_remote_test:48: src/net/GameRemotes.luau did not load: error requiring module "../../src/net/GameRemotes": could not resolve child component "GameRemotes"
    FAIL  tests/net/turn_remote_test.luau :: AC-1: Turn's schema answers as { machine = integer(1, actuator_count), setting = integer(1, dial_settings) } at 0, 1, max and max + 1 for each field, files a non-integer as range, and a missing, extra or non-table payload as shape
          (same message)
    FAIL  tests/net/turn_remote_test.luau :: AC-1: Turn's legalPhases is exactly { Round }
    FAIL  tests/net/turn_remote_test.luau :: AC-1: Turn's rateLimit.minIntervalSeconds equals MechanicsTuning.actuation.turn_rate_limit_seconds
    FAIL  tests/net/turn_remote_test.luau :: AC-1: Turn declares no attempt limit - attemptLimit is nil (PO decision 1)
    FAIL  tests/net/turn_remote_test.luau :: AC-1: Remotes.all() lists exactly one definition named Turn, and it is the registered table itself
    FAIL  tests/net/turn_remote_test.luau :: AC-2: a seated caller in Round sending a missing setting, machine = 0, setting = dial_settings + 1, setting = 1.5, an extra player key, or a string is rejected for shape, range, range, range, shape, shape respectively, and the handler never runs
    FAIL  tests/net/turn_remote_test.luau :: AC-3: a well-formed Turn by a seated caller in Lobby, Assignment, Resolution or Post is rejected for phase and the handler never runs
    FAIL  tests/net/turn_remote_test.luau :: AC-3: two well-formed in-Round Turns at t and t + turn_rate_limit_seconds - 0.1 - the second is rejected for rate and the handler count stays 1; a third at exactly t + turn_rate_limit_seconds runs it (count 2)
    FAIL  tests/net/turn_remote_test.luau :: AC-2/AC-3 positive control: a well-formed in-Round Turn by the seated caller - mid-range and at both maxima - reaches the handler exactly once with the caller's id and exactly { machine, setting }

    FAIL  tests/server/turn_requests_test.luau :: Contract: TurnRequests exports handle and reply as plain field functions, and handle returns the (state, result) pair Procedure.turn returns on the same inputs
          ...tests\server\turn_requests_test:38: src/server/procedure/TurnRequests.luau did not load: error requiring module "../../src/server/procedure/TurnRequests": could not resolve child component "TurnRequests"
    FAIL  tests/server/turn_requests_test.luau :: AC-4: with the accepted positions out of reach and an in-reach position smuggled into args (position, positions, x/y/z) the turn is refused / out_of_reach with the state unchanged; with accepted positions in reach and a far one smuggled, it commits - both equal to a direct Procedure.turn
          (same message)
    FAIL  tests/server/turn_requests_test.luau :: AC-4: args.machine and args.setting are forwarded as given - a wrong setting on machine 11 is rejected / wrong_setting with that setting on the dial, and bob turning machine 14 commits 14
    FAIL  tests/server/turn_requests_test.luau :: AC-4: the turn is judged for the CALLER's id - kim with args.player = zed commits, zed with args.player = kim is refused / not_key_holder
    FAIL  tests/server/turn_requests_test.luau :: AC-4: handle mutates none of its arguments - state, assignment, args and positions deep-equal their snapshots afterwards
    FAIL  tests/server/turn_requests_test.luau :: AC-5: reply maps committed and armed results to exactly { machineId, kind } - key set enumerated with pairs, values equal
    FAIL  tests/server/turn_requests_test.luau :: AC-5: reply maps rejected (wrong_setting, not_live) and refused (every reason) results to exactly { machineId, kind, reason } with the reason unchanged
    FAIL  tests/server/turn_requests_test.luau :: AC-5: the reply to a REAL wrong_setting rejection from Procedure.turn is exactly { machineId, kind, reason } and carries no requiredSetting or setting; a real commit and a real out_of_reach refusal map exactly too
    FAIL  tests/server/turn_requests_test.luau :: Contract (D8): reply is built field by field - an extra field on the result does not reach the reply, and the reply is a fresh table rather than the result itself

**Why this is the right failure.** Both modules are new, so "the module does
not exist" is the first thing the story requires, and each test fails on
its own `assert(loaded, ...)` naming the module rather than as one LOAD FAIL
for the file. Nothing else in the tree is red: the other 791 tests pass. The
20th failure in the first run was one of MY controls (`hardcodesKind`), whose
predicted fired-set was wrong - see the controls table; corrected to the
measured set, so the final count is 19 failed, all in the two real suites.

Because the real suites fail at `require`, **no assertion in them has run**.
Every check they call is therefore executed in RED by the two controls
suites, against a reference that must pass and stand-ins that must fail
exactly the checks named. Those 29 control tests pass today.

### Files touched

| File | Status | Purpose |
|---|---|---|
| `tests/helpers/TurnRemoteContract.luau` | new | AC-1..AC-3 checks over `(Net, definition)`, `CHECKS`, `failures` |
| `tests/net/turn_remote_test.luau` | new | 10 tests on the real `GameRemotes.Turn` (red) |
| `tests/net/turn_remote_controls_test.luau` | new | 12 tests: reference + fixtures + 10 one-edit declarations (green in RED) |
| `tests/helpers/TurnRequestsContract.luau` | new | AC-4/AC-5 checks over a `TurnRequests` module; `replyProblems`, the exact key-set checker |
| `tests/server/turn_requests_test.luau` | new | 9 tests on the real `TurnRequests` (red) |
| `tests/server/turn_requests_controls_test.luau` | new | 17 tests: reference + fixtures + checker-on-hand-written-replies + 13 one-defect stand-ins (green in RED) |
| `docs/backlog/stories/PROC-005.md` | edited | this section, `## Test plan` |
| `.claude/tests/project-counters.test.sh` | edited (harness, RED-only by check 3j) | baselines set to the PREDICTED post-GREEN counts: `BASE_FORMAT`/`BASE_LINT` 129 -> 137, `BASE_TYPECHECK` 24 -> 26, `NARROW_FORMAT`/`NARROW_LINT` 24 -> 26, `NARROW_TYPECHECK` 8 unchanged; derivation logged in the file's header |

No source, config or manifest file was touched. No test dependency was
needed.

One test per row, what it asserts, which AC:

| Test (short) | Asserts | AC |
|---|---|---|
| `Contract: GameRemotes exports Turn ...` | `GameRemotes.Turn` is a table and `rawequal` to the `Remotes.all()` entry named `"Turn"` | Contract |
| `AC-1: Turn's schema answers ...` | via `args.validate`: both minima ok, `(actuator_count, dial_settings)` ok, 0 / max+1 in each field `range`, 1.5 in each field `range`, missing field / extra `position` / extra `player` / string-typed field / `{}` / nil / string payload `shape` | AC-1 |
| `AC-1: Turn's legalPhases is exactly { Round }` | `Deep.equal(legalPhases, { "Round" })` | AC-1 |
| `AC-1: rateLimit.minIntervalSeconds equals ...` | `== MechanicsTuning.actuation.turn_rate_limit_seconds` | AC-1 |
| `AC-1: Turn declares no attempt limit` | `definition.attemptLimit == nil` | AC-1 (PO-1) |
| `AC-1: Remotes.all() lists exactly one ...` | exactly one entry with that name, `rawequal` to the definition | AC-1 |
| `AC-2: ... rejected for shape, range, range, range, shape, shape` | six B4 cases through the real guard, seated kim, phase Round; spy count 0 | AC-2 |
| `AC-3: ... Lobby, Assignment, Resolution or Post ... phase` | four phases, each `reason == "phase"`, spy count 0 | AC-3 |
| `AC-3: two well-formed ... rate ...` | accept at `t`, `rate` at `t + rate - 0.1` (count stays 1), accept at exactly `t + rate` (count 2) | AC-3 |
| `AC-2/AC-3 positive control` | mid payload and `{ actuator_count, dial_settings }` each reach the spy once with `playerId == "kim"` and args deep-equal to the payload | AC-2/3 |
| `Contract: TurnRequests exports handle and reply ...` | two functions; `handle` returns `(table, { kind = string })` deep-equal to `Procedure.turn` on identical inputs | Contract |
| `AC-4: accepted positions out of reach, in-reach position smuggled ...` | case A `refused/out_of_reach`, state unchanged; case B `committed`, `committed[11] == true`; both deep-equal to a direct `Procedure.turn` | AC-4 |
| `AC-4: args.machine and args.setting are forwarded ...` | wrong setting -> `rejected/wrong_setting`, `dials[11].setting == wrong`; bob on 14 -> `committed` 14 | AC-4 |
| `AC-4: judged for the CALLER's id` | kim + `player="zed"` commits; zed + `player="kim"` -> `refused/not_key_holder` | AC-4 |
| `AC-4: handle mutates none of its arguments` | state, assignment, args, positions deep-equal snapshots | AC-4 |
| `AC-5: committed and armed -> exactly { machineId, kind }` | key set via `pairs` sorted == `{ "kind", "machineId" }`, values equal | AC-5 |
| `AC-5: rejected and refused -> exactly { machineId, kind, reason }` | 2 rejected + 7 refused reasons, exact key set and values | AC-5 |
| `AC-5: REAL wrong_setting rejection ...` | reply to a real `Procedure.turn` rejection, commit and refusal; exact key set; `requiredSetting`/`setting` absent | AC-5 |
| `Contract (D8): reply is built field by field` | a result with an extra `requiredSetting` field maps to a reply without it; the reply is not `rawequal` to the result and writing to it leaves the result untouched | Contract |

### The export shape the tests already pin

Nothing below is a suggestion. Each name and signature is already imported
or called by a test, so getting it wrong is a red test rather than a debate.

    src/net/GameRemotes.luau                       -- NEW, required as "../../src/net/GameRemotes"
      return { Turn = <RemoteDefinition> }         -- the table Remotes.define("Turn", ...) returned
      -- Turn.name        == "Turn"                (read out of Remotes.all() by name)
      -- Turn.args        answers as Schema.shape({ machine = Schema.integer(1, MechanicsTuning.instance.actuator_count),
      --                                            setting = Schema.integer(1, MechanicsTuning.instance.dial_settings) })
      -- Turn.legalPhases == { "Round" }           (exactly, length 1)
      -- Turn.rateLimit   == { minIntervalSeconds = MechanicsTuning.actuation.turn_rate_limit_seconds }
      -- Turn.attemptLimit == nil
      -- Remotes.define is called ONCE, at require time; Lune caches the module, the tests never redeclare "Turn".

    src/server/procedure/TurnRequests.luau         -- NEW, required as "../../src/server/procedure/TurnRequests"
      TurnRequests.handle(procedure, assignment, playerId, args, now, positions)
          -> (Procedure.ProcedureState, Procedure.TurnResult)
          -- exactly what Procedure.turn(procedure, assignment, playerId, args.machine, args.setting, now, positions) returns
          -- reads ONLY args.machine and args.setting; the tests pass args carrying position, positions, x, y, z, player
          -- mutates nothing it is handed
      TurnRequests.reply(result: Procedure.TurnResult) -> TurnReply
          -- { machineId = result.machineId, kind = result.kind }               for committed / armed
          -- { machineId = result.machineId, kind = result.kind, reason = result.reason }  for rejected / refused
          -- a FRESH table built field by field; no other key, whatever the result carries
      export type TurnReply = { machineId: number?, kind: "committed" | "armed" | "rejected" | "refused", reason: string? }
          -- (the Contract's, as pinned at PLANNED -> RED; the tests cannot see types, only the key set)

    Modules the tests import and do not change:
      src/net/Schema, src/net/Remotes, src/net/Wrapper, src/shared/MechanicsTuning, src/shared/Clock,
      src/server/procedure/Procedure, src/server/facility/Machines, src/server/seats/Ring

**Not constrained** (the implementer's choice): how `handle` reaches
`Procedure.turn` (a plain `require` is fine - nothing replaces a module
field); whether `GameRemotes` reads tuning through `@shared/MechanicsTuning`
or a relative path; the wording of any `error`; whether `reply` branches on
`kind` or copies a `nil` reason; where `TurnReply` is declared; the order of
`Remotes.all()`; anything about `Session`, `Transport` or the HUD.

### Tests that passed on arrival

The 29 control tests (two `*_controls_test` files) are green in RED by
design: they run the checks against stand-ins, not the missing modules.
Each is earned by the reference/one-defect structure - the reference passes
all 9 checks in each helper, and every defect fires an exactly pinned set,
measured, printed as `[measured]` lines. None of the 19 real-suite tests
passed on arrival.

### Negative controls: expected and measured in RED

All measured by `lune run test` on 2026-10-02 (local run). "Fires" is the
exact set of checks that raised; a control firing one more or one fewer is a
test failure in the controls file.

**`TurnRemoteContract` (declarations through the real `Remotes.define`, real `Wrapper.guard`)**

| Control (one edit to the reference) | Expected to fire | Measured in RED |
|---|---|---|
| reference (Contract's spec, unique name) | nothing | 0 of 9 |
| `settingUpperBoundPlusOne` (D-3's second edit) | schema, AC-2 | schema, AC-2 |
| `machineLowerBoundZero` | schema, AC-2 | schema, AC-2 |
| `settingIsNumber` (number() not integer()) | schema, AC-2 | schema, AC-2 |
| `acceptsPlayer` (optional player field) | schema, AC-2 | schema, AC-2 |
| `legalInLobbyToo` | phases, AC-3 phase | phases, AC-3 phase |
| `rateLimitPlusOne` (D-3's first edit) | rateLimit, AC-3 rate | rateLimit, AC-3 rate |
| `noRateLimit` | rateLimit, AC-3 rate | rateLimit, AC-3 rate |
| `declaresAttemptLimit = 3` | attemptLimit | attemptLimit |
| `unregisteredCopy` (table.clone of the reference) | registry | registry |
| `emptySchema` (rejects everything) | schema, AC-2, AC-3 phase, AC-3 rate, positive | schema, AC-2, AC-3 phase, AC-3 rate, positive |

**`TurnRequestsContract` (stand-ins over the real `Procedure`)**

| Control | Expected to fire | Measured in RED |
|---|---|---|
| reference | nothing | 0 of 9 |
| `readsPositionFromArgs` (D-1's shape) | reach | reach |
| `readsPositionsFromArgs` (D-1's other shape) | reach | reach |
| `swapsMachineAndSetting` | pass-through, reach, forwards, caller | as expected |
| `hardcodesSettingOne` | pass-through, reach, forwards, caller | as expected |
| `hardcodesTheMachine` (always 11) | forwards | forwards |
| `readsPlayerFromArgs` | caller | caller |
| `returnsOnlyTheResult` | pass-through, reach, forwards, caller | as expected |
| `mutatesItsArguments` | purity | purity |
| `copiesTheMachineRecord` (the story's AC-5 control) | all 4 reply checks | all 4 |
| `leaksRequiredSetting` (D-2's extra field) | all 4 reply checks | all 4 |
| `hardcodesKind` (D-2's wrong value) | predicted 3 (not committed/armed) | **all 4** - the hand-built `armed` result comes back `committed`; prediction corrected to the measurement |
| `dropsReason` | rejected/refused, real results, field-by-field | as expected |
| `passesTheResultThrough` | field-by-field only | field-by-field only |

**The exact key-set checker, run directly on hand-written replies** (oracle-free, so observed in RED as the brief requires):

| Hand-written reply | Expected | Measured in RED |
|---|---|---|
| copied machine record + kind + reason (`id, keyClass, kind, machineId, reason, requiredSetting, room, slot, tag`) | rejected, naming `requiredSetting` | 1 problem: `AC-5: ... key set is { id, keyClass, kind, machineId, reason, requiredSetting, room, slot, tag }, expected exactly { kind, machineId, reason }` |
| right keys, `kind = "committed"` where `"rejected"` expected | rejected, naming `kind` | 1 problem: `AC-5: wrong kind: reply.kind is "committed", expected "rejected"` |
| right keys, wrong `machineId` | 1 problem | 1 |
| missing `reason` | key-set problem + value problem | 2 |
| a string | 1 problem | 1 |
| the correct reply | 0 problems | 0 |

These numbers were measured against stand-ins and my own checker. **Confirming
them against the shipped modules is GREEN's job**: after GREEN, the 19 real
tests must pass and the 29 control tests must still pass unchanged.

### Deferred verifications D-1..D-3: DECLINED in RED

I cannot run D-1, D-2 or D-3: each mutates a module that does not exist in
this phase. They are owned by GATES, as the story says. What RED did instead
is show that the checks WOULD see each one: D-1's two shapes are
`readsPositionFromArgs` / `readsPositionsFromArgs` (fire AC-4's reach
check), D-2's two edits are `leaksRequiredSetting` / `hardcodesKind` (fire
every AC-5 check), and D-3's two edits are `rateLimitPlusOne` /
`settingUpperBoundPlusOne` (fire AC-1's rate-limit check + AC-3's rate half,
and AC-1's schema check + AC-2 respectively). GATES runs the real mutations
with `bash scripts/mutate.sh` and pastes the red.

### Callers list, restated against the tree

`rg -n 'GameRemotes|TurnRequests' src tests` returned nothing before these
tests were written (exit 1, 2026-10-02). After them the only hits are the six
new test files. `Remotes`, `Schema`, `Wrapper` and `Procedure` keep their
signatures; the tests call them exactly as the existing suites do.

### Notes for the implementer

- `Remotes.define` copies exactly `name, args, legalPhases, rateLimit` into
  the definition it returns, so an `attemptLimit` in the spec would be
  dropped silently today; the AC-1 check reads the field off the returned
  definition. Nothing to do here - just do not expect a spec field to appear.
- `Schema.integer` already files a non-integer as `range` and `Schema.shape`
  already refuses an extra key as `shape`, so AC-2 needs nothing beyond the
  Contract's two-field schema.
- `TurnRemoteContract.wellFormed()` is `{ machine = min(3, actuator_count),
  setting = min(2, dial_settings) }` - off both lower bounds on purpose, so
  a bound that is one off still accepts it and the positive control stays
  positive. `EPSILON` is 0.1 against `turn_rate_limit_seconds` = 1; the
  controls file asserts `0 < EPSILON < rate`.
- The Contract (D8) check requires `reply` to return a NEW table: `return
  result` passes every key-set assertion and fails only that one. This is
  the Contract's "field by field, never by copying a record" clause, pinned
  as written, not an AC - say so in `## Amendments` if the PO wants it loosened.
- Timings: the whole suite is 6 m 32 s locally, dominated by the GEN sweeps.
  The 48 new tests run in well under a second together (no sweeps, no
  sleeps). No test here owns a timeout; the runner has none.
### `bash scripts/gates.sh --fast` at the end of RED (2026-10-02, local)

    PASS         format (1s, observed 135)
    PASS         lint (2s, observed 135, floor 1)
    PASS         typecheck (5s, observed 24)
    FAIL         unit (314s, exit 1) -> .claude/state/gate-logs/unit.log      792 passed, 19 failed
    UNCONFIGURED coverage
    PASS         build (2s, observed 91349)
    FAIL         harness (61s, exit 1) -> .claude/state/gate-logs/harness.log  project-counters: 33 passed, 7 failed
    --fast skipped: integration mutation

The shape is the one RED wants: format, lint, typecheck and build green;
`unit` red with exactly the 19 real-suite assertions above and nothing else
(the floor 507 is far below the observed 811 cases). `harness` is red for
the documented RED reason, in two parts, and GREEN must not touch it:

1. **The "no stray .luau files" precondition** fails while the six new test
   files are untracked. It clears at the RED commit. **The orchestrator must
   make a `phase: RED` commit carrying the six test files, the story and
   `.claude/tests/project-counters.test.sh` before setting GREEN** -
   `check-boundaries.sh` 3j refuses a `.claude/tests/**` change in any
   commit whose story says GREEN or later, and GEN-001/TUNE-001 each needed a
   return to RED for skipping this. I did not commit: the brief did not ask
   me to.
2. **AC-7's counts** read `expected 137 / actual 135` (format, lint),
   `expected 26 / actual 24` (typecheck over `src`, and both narrow counts):
   every count is exactly 2 short, which is `src/net/GameRemotes.luau` and
   `src/server/procedure/TurnRequests.luau`. The baselines are the predicted
   post-GREEN values, as the counters file's header prescribes; GREEN
   confirms them by writing exactly those two modules and nothing else under
   `src/`. A third source file, or a module placed under `src/shared/`
   (which would move `NARROW_TYPECHECK`), is a counter failure GREEN cannot
   fix - it would be a return to RED.

Timings above are from this machine; CI's per-test factor is not in
`project.conf` for `unit`, and nothing in this story's tests is timing-bound
(no sweeps, no sleeps, no timeouts).

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


**PO decisions (PLANNED → RED, 2026-10-02, lead-po).**

1. **AC-1's "never declines" is pinned here as `attemptLimit == nil`.** No
   handler in this story can decline, because `CallControl` does not exist until
   `CHAN-003`. That clause stays a property of the `Turn` handler `SLICE-005`
   builds. The criterion's text is unchanged.
2. **`TurnReply.machineId` is `number?`** so that it mirrors
   `Procedure.TurnResult`. A contract fix, not an AC change: AC-5's key set
   `{ machineId, kind, reason? }` is unaffected.
3. **Epic done-when check.** EPIC-05 done-when 1 (judged only against server
   state) is delivered by `PROC-001` together with this story's AC-4. Nothing
   between `PROC-003` and here is promised and undelivered. Routing the reply
   through `Transport` is `SLICE-005`, as `## Out of scope` already says.
4. **Required gate:** `unit` (required), which covers `src/net/**` and
   `src/server/**`. No optional-only gate is involved, so `required_gates`
   stays empty.
