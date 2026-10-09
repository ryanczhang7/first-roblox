---
id: SLICE-004
title: Four Studio clients see the phase, the countdown and their own seat card
slug: four-studio-clients-see-the-phase-the-co
epic: EPIC-03
type: feature
status: in-progress
phase: RED
branch: story/SLICE-004-four-studio-clients-see-the-phase-the-co
depends_on: [SLICE-002, SLICE-003, THEME-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. This is the first time the game runs in Roblox. `SLICE-002`
built `Transport`, and `SLICE-003` built a pure `Session` whose effects describe
what to send to whom. This story adds the three pieces that make it real:

- a pure **interpreter** that maps each effect to exactly one port call;
- the **driver**, `RoundService.server.luau`, which is impure and logic-free
  (`architecture.md` §9.1, §9.6);
- a **client entry** that listens for `RoundView` and shows the phase and a
  countdown.

The driver builds the real ports: `Clock.real()`, `Players` joins and leaves,
`RunService.Heartbeat` ticks, `RemoteEvent`s under one folder, and
`Sink.noop()`. It feeds events into `Session.step` and hands the effects to the
interpreter.

Only the interpreter and the client's countdown model are headlessly testable.
Everything else is a Studio check the operator runs, pasted here. That is why
the interpreter carries the story's weight: it is the one place a routing
mistake could send a secret to everyone.

**Which required gate would fail if this story's artifact broke:** `unit` for
the interpreter and the model, and `typecheck` and `build` for the two entry
scripts. The runtime behaviour is held by no gate. It is `D-2`, run by the
operator.

## Acceptance criteria

- **AC-1** — Given every `SessionEffect` kind, when `Interpreter.perform` runs
  over a list of them with recording fake ports, then:
  - each `SendTo` becomes exactly one `transport:sendTo(playerId, kind,
    payload)`;
  - each `Broadcast` becomes exactly one `transport:broadcast(kind, payload)`;
  - each `Emit` becomes one sink emission through `Sink.dispatch`;
  - `PromptRematch`, `ComputeTrace` and `Placed` become the port calls named
    in the contract.

  Order is preserved.
  *Control:* an interpreter that turns a `SendTo` into a broadcast must fail,
  because `Transport` raises for a private kind.
- **AC-2** — Given an effect kind the interpreter does not know, when it is
  performed, then it raises, naming the kind. A silently dropped effect is a
  lost replication.
- **AC-3** — Given a `RoundView` payload and a local receive time, when
  `PhaseClockModel.describe(view, receivedAt, now)` runs, then:
  - it returns the phase's display key (`voice.md`'s word for it);
  - it returns `m:ss` (minutes unpadded, seconds two digits: `7:00`, `0:09`)
    for `max(0, secondsLeft − (now − receivedAt))`, rounded up;
  - it returns no countdown when `secondsLeft` is nil.

  Each assertion is written against a named `voice.md` string, not a literal.
- **AC-4** — Given the entry scripts, when the `typecheck` and `build` gates run,
  then both pass with `RoundService.server.luau` and `Main.client.luau` in the
  analysed set. Rojo maps them to a `Script` and a `LocalScript`, as `SLICE-001`
  observed.

## Contract

**Modules.**

    src/server/session/Interpreter.luau     -- pure over ports
        export type Ports = {
            transport: Transport.Bound,
            emit: ({ Event.TelemetryEvent }) -> (),     -- Sink.dispatch(sink, events), bound by the driver
            promptRematch: () -> (),                     -- M3: no-op port; the card is driven by RoundView (architecture.md §9.5)
            computeTrace: (roundId: string) -> (),       -- M3 until TRACE-001: no-op port
            place: (playerId: string, position: { x: number, y: number, z: number }) -> (),
                                                         -- no-op port until SLICE-007 binds the teleport
        }
        Interpreter.perform(effects: { Session.SessionEffect }, ports: Ports) -> ()
    src/server/RoundService.server.luau     -- the driver; untested logic-free glue
    src/client/Main.client.luau             -- the client entry
    src/client/models/PhaseClockModel.luau  -- pure
        PhaseClockModel.describe(view: { phase: string, secondsLeft: number? }, receivedAt: number, now: number)
            -> { phaseKey: string, countdown: string? }
    src/client/views/PhaseClockView.luau    -- a TextLabel on a ScreenGui; Studio-verified

- **The driver is logic-free.** Every `if` in it concerns the runtime, not a
  game rule: guarding a nil character, for example. A game decision found there
  in review goes back to `Session`.
- **Client time** is `os.clock()` in the client, only inside
  `Main.client.luau`. The model takes `now` as an argument. The ROUND-001 guard
  (`tests/shared/source_guard_test.luau`) permits `os.clock` only in
  `Clock.real`, so the client entry must use `Clock.real()` from `@game/ReplicatedStorage/Shared/Clock`. RED
  confirms that the guard's scope includes `src/client/` and that the entry
  complies.
- **RemoteEvents** are created by the driver under
  `ReplicatedStorage.Remotes`, one per declared remote and one per payload kind,
  before any player can join. The client waits for them with `WaitForChild`.
- **Views** read colours and sizes from `Theme` (`THEME-001`), and words from
  `voice.md` through a small `src/client/Words.luau`. That module is data, and
  AC-3's test reads it.

### Pinned at PLANNED -> RED (lead-po, 2026-10-08)

The contract above was written on 2026-09-30, before `SLICE-005` and `SLICE-006`
grew `Session`. These blocks bring it up to the tree. **RED may amend any block
in this section, in place, with a reason; GREEN builds what the amended block
says.**

**PO decisions (reported to the operator before RED).**
- **P-1. `Placed` gets a port.** `Session` has emitted `Placed { playerId,
  position }` at round start since `SLICE-005`. Without a port, AC-2 would
  make the real driver raise on every round. `SLICE-007` owns "teleports for
  `Placed`", so the port exists now, and the driver binds it to a no-op, the
  same pattern as `promptRematch` and `computeTrace`.
- **P-2. No game remote is bound here.** `SLICE-007` AC-2 owns binding
  `GameRemotes`, along with `Handlers.luau`. The driver here calls
  `Transport.bind({}, context, {}, ports)`. That creates one `RemoteEvent` per
  payload kind under `ReplicatedStorage.Remotes` and binds no `OnServerEvent`.
  "One per declared remote" in the block above is superseded by this.
- **P-3. `lineOfSight` is a stub returning `false`** until `SLICE-007`. No
  positions are sampled. Gameplay is out of scope.
- **P-4. The phase words and the clock form are the operator's** (asked and
  answered 2026-10-08):
  - the label is the phase name verbatim, recorded in `voice.md` §2.1;
  - the countdown is `m:ss`, the `%d:%02d` form;
  - `docs/wiki/design/voice.md` joins the `unit` gate's `covers`, because
    AC-3's test reads it.

**Interpreter, exact semantics.**
- Effect kinds and their single port call:

  | Effect kind | Port call |
  |---|---|
  | `SendTo` | `ports.transport:sendTo(e.playerId, e.payloadKind, e.payload)` |
  | `Broadcast` | `ports.transport:broadcast(e.payloadKind, e.payload)` |
  | `Emit` | `ports.emit({ e.event })`, one call per effect, a fresh one-element list |
  | `PromptRematch` | `ports.promptRematch()` |
  | `ComputeTrace` | `ports.computeTrace(e.roundId)` |
  | `Placed` | `ports.place(e.playerId, e.position)` |

- Effects are performed in list order, and each makes exactly one call.
- **`AssignSeats` raises**, as an unknown kind does. `Session` consumes it, and
  one reaching the interpreter is a bug.
- An unknown kind raises with a message containing the kind string verbatim.
  It raises **at that effect**. The effects before it in the list have
  already been performed, and the ones after it have not. There is no
  pre-validation pass.
- The interpreter neither copies nor inspects payloads: the payload table it
  passes is the one in the effect.

**PhaseClockModel, exact semantics.**
- `Words.luau` is data: `Words.phase = { Lobby = "Lobby", Assignment = …, Post =
  "Post" }`. `describe(...).phaseKey` is `Words.phase[view.phase]`, the
  player-facing word. A phase missing from `Words.phase` raises, naming it.
- AC-3's test checks `Words.phase` against `voice.md` §2.1's table. It reads
  that table from the file and does not restate it. Each `phaseKey` assertion
  compares to `Words.phase[...]`.
- Countdown: `remaining = max(0, secondsLeft - (now - receivedAt))`,
  `whole = math.ceil(remaining)`, and the text is
  `string.format("%d:%02d", whole // 60, whole % 60)`. So `420 → "7:00"`,
  `0.2 → "0:01"`, `0 → "0:00"`, and a negative elapsed result clamps to
  `"0:00"`. When `secondsLeft` is nil, `countdown` is nil.
- `now < receivedAt` (a clock that went backwards) is not specified. RED may
  leave it untested.

**Driver and client glue (no unit test; `typecheck` and `build` read them).**
- `RoundService.server.luau`:
  - builds `Clock.real()`, `Sink.noop()`, a `RoundConfig` from `Tuning`,
    `Session.new`, and the transport with P-2;
  - feeds `PlayerJoined`/`PlayerLeft` from `Players` and a `Tick` per
    `RunService.Heartbeat`;
  - passes every step's effects to `Interpreter.perform`.

  Player ids are `tostring(player.UserId)`.
- `Main.client.luau`:
  - waits for `ReplicatedStorage.Remotes`;
  - `ClientTransport.init` with a `WaitForChild` port, and listens with
    `ClientTransport.on("RoundView", ...)`;
  - stamps `receivedAt = Clock.real().now()` and redraws through
    `PhaseClockView` on each payload and each `RenderStepped`.

  No `os.clock` is called outside `Clock.real`.

**Existing exports: none changed.**

**Oracle partition.**
- AC-1 and AC-2 are **mechanical**, and the fakes record calls.
- AC-3 is **settled** by `voice.md` for the words and **mechanical** for the
  arithmetic.
- AC-4 is the gates themselves.

## Deferred verifications

**D-1. The interpreter's routing discriminates.** Use `scripts/mutate.sh` to
swap `sendTo` and `broadcast` in the interpreter. AC-1 **must** then fail. RED
cannot run this. Owner: GATES.

**D-2. Studio (the operator).** The operator runs `bash scripts/task.sh dev`
and Studio's local server with 4 clients, then observes:
1. every client shows `Lobby` and a countdown that holds while fewer than 4 are
   in;
2. with 4 in, the countdown runs and all four agree to within 1 s;
3. the phase goes `Assignment` → `Round`, the round countdown runs from 7:00,
   the round ends at 0:00, and the phase goes `Resolution` → `Post` → `Lobby`;
4. the Output window shows no error on the server or any client.

Paste the Output and one screenshot per client. RED and GREEN cannot run this.
Owner: REVIEW.

## Out of scope

- The lobby panel, the seat card and the relations strip (`HUD-007`).
- Any gameplay, map or channel.
- Telemetry to a real sink (M5).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-004` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/client/Main.client.luau` (source), `src/client/Words.luau` (source), `src/client/models/PhaseClockModel.luau` (source) (+4 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- PLANNED (contract pin) - `lead-po` - `claude-opus-5-5`. 2026-10-08.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1, dispatched with `model: fable` explicitly; self-reported). 2026-10-08.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

Everything headless is a **unit** test under Lune, in the house shape
(`XContract.luau` holds the checks, `XStubs.luau` holds one-defect fakes,
`x_test.luau` applies the checks to the shipped module, `x_controls_test.luau`
applies them to the fakes so every check is observed firing in RED). One
AC-1 case is an **integration** of the interpreter with the real
`Transport.bind` over `TransportStubs`' fake `RemoteEvent`s, because the
criterion's control ("a `SendTo` turned into a broadcast must fail") is a
property of `Transport`, not of a recorder. AC-4 is the `typecheck` and
`build` gates and has no unit test. D-1 and D-2 are declined below.

Oracle partition, honoured as the Contract draws it:

| Criterion | Oracle | Where |
|---|---|---|
| AC-1 | mechanical: one recorded trace compared to the expected sequence; payloads by identity | `tests/helpers/InterpreterContract.luau` -> `tests/server/interpreter_test.luau` |
| AC-1 control | the real `Transport` refusing a private kind on `broadcast`, and `FireClient` reaching one player object | same, `theRealTransportRoutesASendToItsPlayerOnlyAndABroadcastToAll` |
| AC-2 | mechanical: raise naming the kind verbatim; trace shows effects before performed, after not | same |
| AC-3 words | **settled** by `voice.md` §2.1, read off disk through `GatedFs` by `tests/helpers/VoiceSpec.luau`; the five phases come from `PhaseMachine.luau`'s `Phase` union via `PhaseUnion`, never a literal | `tests/helpers/PhaseClockContract.luau` -> `tests/client/phase_clock_model_test.luau` |
| AC-3 countdown | mechanical: an 11-row boundary table pinned exactly | same |
| AC-4 | the gates | none |

| Test (file :: name) | Asserts | AC |
|---|---|---|
| `interpreter_test` :: over a mixed list of every effect kind, each makes exactly one port call, in list order, with the effect's own payload, position and event tables | the 9-call trace equals the expected sequence; `self` is the transport; tables identical | AC-1 |
| `interpreter_test` :: each Emit is one ports.emit call carrying a fresh one-element list holding that effect's event | two Emits -> two `emit` calls, two distinct lists of length 1, `[1]` identical to the event | AC-1 |
| `interpreter_test` :: an empty effect list makes no port call and does not raise | zero calls, no raise | AC-1 (zero edge) |
| `interpreter_test` :: AC-1 control: through the real Transport.bind over fake RemoteEvents ... | `SeatView.FireClient` once with p1's object and the payload table; `RoundView.FireAllClients` once; no other event fires; other ports untouched | AC-1 control |
| `interpreter_test` :: an effect of kind "Frobnicate" raises naming it, after the two effects before it were performed and before the one after it | raise contains `Frobnicate`; trace is exactly `[broadcast, promptRematch]` | AC-2 |
| `interpreter_test` :: an AssignSeats effect raises naming AssignSeats and makes no port call | raise contains `AssignSeats`; zero calls | AC-2 (Contract: AssignSeats raises) |
| `interpreter_controls_test` :: baseline + 16 `control <defect>` cases + 3 named-message cases | each one-defect fake fails exactly its pinned set of checks (table in the handoff) | controls for AC-1, AC-2 |
| `phase_clock_model_test` :: Words.phase is exactly voice.md §2.1's table, read from the file, and names every phase in PhaseMachine's union | row-by-row equality both directions; every machine phase has a row | AC-3 words |
| `phase_clock_model_test` :: describe(view).phaseKey is Words.phase[view.phase] for every phase in PhaseMachine's union, with and without secondsLeft | compared to `Words.phase[...]`, never a literal | AC-3 words |
| `phase_clock_model_test` :: a phase Words.phase does not name ("Limbo") raises naming it rather than echoing it | raise contains `Limbo` | AC-3 (Contract: missing phase raises) |
| `phase_clock_model_test` :: countdown is %d:%02d of ceil(max(0, secondsLeft - (now - receivedAt))) ... | the 11 rows below, all at once; the view is not mutated | AC-3 countdown |
| `phase_clock_model_test` :: with secondsLeft nil the countdown is nil | `countdown == nil` | AC-3 |
| `phase_clock_controls_test` :: baseline + 14 `control <defect>` cases + 6 row-naming cases + 2 words cases + 4 `VoiceSpec` reader cases | each fake fails exactly its pinned set; each named mutant dies on the named row; the reader finds rows only under `### 2.1`, trims, reports vacuity, and the live §2.1 names exactly the machine's phases | controls for AC-3 |
| `client_requires_test` (THEME-001, amended) :: C-8 ... the seven Contract modules of THEME-001 and SLICE-004 are among those scanned | the four new client modules are in the scanned set and obey the layer rule; only `Main.client.luau` may require Net | AC-4's layer discipline |

The countdown rows (`PhaseClockContract.ROWS`), `secondsLeft / receivedAt / now -> text`:
`420/0/0 -> 7:00`, `0.2/0/0 -> 0:01`, `60/0/0 -> 1:00`, `59.5/0/0 -> 1:00`,
`61/0/0.5 -> 1:01`, `9/0/0 -> 0:09`, `600/0/0 -> 10:00`, `420/0/500 -> 0:00`,
`0/0/0 -> 0:00`, `420/100/130.5 -> 6:30`, `420/100/100 -> 7:00`.
`now < receivedAt` is untested, as the Contract allows.

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

**Dispatched model.** This RED ran on `claude-fable-5-1` (Fable 5.1, the
model's own identification), which is the planned `fable` row; no override
was reported in the dispatch.

### The command

    lune run test

from `.claude/harness/project.conf` (`gate | unit`). The runner has no filter:
it walks `tests/**/*_test.luau`. This story's four suites are
`tests/server/interpreter_test.luau`, `tests/server/interpreter_controls_test.luau`,
`tests/client/phase_clock_model_test.luau`, `tests/client/phase_clock_controls_test.luau`,
plus the amended `tests/client/client_requires_test.luau`. A full run takes
about 5 min on this machine (306 s measured, 1581 tests).

**Do not pipe `lune run test` through `grep | head` from an agent shell and
let the harness background it**: the first run here blocked for 22 minutes at
0.4 s CPU once the pipe's reader went away. Redirect to a file and tail it.

### The failure, verbatim (run 2, after the three control corrections below)

`lune run test > run2.log 2>&1`, 2026-10-08, this machine (Windows, Lune
0.10.5), 304 s. Every `pass` line omitted; the `FAIL` lines and their first
message line are verbatim:

      FAIL  tests/client/client_requires_test.luau :: C-8: every module under src/client/ requires only its own layer or @game/ReplicatedStorage/Shared/… (the entry alone may also require Net), and the seven Contract modules of THEME-001 and SLICE-004 are among those scanned
            D:\first-roblox\tests\client\client_requires_test:118: 4 Contract module(s) are not in the scanned set (classify.sh --list source src/client returned 3 file(s)):
      src/client/Main.client.luau
      src/client/Words.luau
      src/client/models/PhaseClockModel.luau
      src/client/views/PhaseClockView.luau
      FAIL  tests/client/phase_clock_model_test.luau :: AC-3: Words.phase is exactly voice.md §2.1's table, read from the file, and names every phase in PhaseMachine's union
            D:\first-roblox\tests\client\phase_clock_model_test:35: src/client/models/PhaseClockModel.luau did not load: error requiring module "@game/client/models/PhaseClockModel": could not resolve child component "PhaseClockModel"
      FAIL  tests/client/phase_clock_model_test.luau :: AC-3: a phase Words.phase does not name ("Limbo") raises naming it rather than echoing it
            D:\first-roblox\tests\client\phase_clock_model_test:35: src/client/models/PhaseClockModel.luau did not load: error requiring module "@game/client/models/PhaseClockModel": could not resolve child component "PhaseClockModel"
      FAIL  tests/client/phase_clock_model_test.luau :: AC-3: countdown is %d:%02d of ceil(max(0, secondsLeft - (now - receivedAt))): 420 -> 7:00, 0.2 -> 0:01, 59.5 -> 1:00, 9 -> 0:09, past the end -> 0:00, received at 100 and read at 130.5 -> 6:30
            D:\first-roblox\tests\client\phase_clock_model_test:35: src/client/models/PhaseClockModel.luau did not load: error requiring module "@game/client/models/PhaseClockModel": could not resolve child component "PhaseClockModel"
      FAIL  tests/client/phase_clock_model_test.luau :: AC-3: describe(view).phaseKey is Words.phase[view.phase] for every phase in PhaseMachine's union, with and without secondsLeft
            D:\first-roblox\tests\client\phase_clock_model_test:35: src/client/models/PhaseClockModel.luau did not load: error requiring module "@game/client/models/PhaseClockModel": could not resolve child component "PhaseClockModel"
      FAIL  tests/client/phase_clock_model_test.luau :: AC-3: with secondsLeft nil the countdown is nil
            D:\first-roblox\tests\client\phase_clock_model_test:35: src/client/models/PhaseClockModel.luau did not load: error requiring module "@game/client/models/PhaseClockModel": could not resolve child component "PhaseClockModel"
      FAIL  tests/server/interpreter_test.luau :: AC-1 control: through the real Transport.bind over fake RemoteEvents, a SendTo of SeatView fires FireClient once on the SeatView event to that player's object, a Broadcast of RoundView fires FireAllClients once on its event, and no other event fires
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
      FAIL  tests/server/interpreter_test.luau :: AC-1: an empty effect list makes no port call and does not raise
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
      FAIL  tests/server/interpreter_test.luau :: AC-1: each Emit is one ports.emit call carrying a fresh one-element list holding that effect's event
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
      FAIL  tests/server/interpreter_test.luau :: AC-1: over a mixed list of every effect kind, each makes exactly one port call, in list order, with the effect's own payload, position and event tables
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
      FAIL  tests/server/interpreter_test.luau :: AC-2: an AssignSeats effect raises naming AssignSeats and makes no port call
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
      FAIL  tests/server/interpreter_test.luau :: AC-2: an effect of kind "Frobnicate" raises naming it, after the two effects before it were performed and before the one after it
            D:\first-roblox\tests\server\interpreter_test:35: src/server/session/Interpreter.luau did not load: error requiring module "@game/server/session/Interpreter": could not resolve child component "Interpreter"
    1570 passed, 12 failed

Run 1 (306 s, `1567 passed, 14 failed`) had the same eleven real-module
failures plus three control mismatches, all stub-side and all corrected
before run 2 - recorded in the controls table below so the correction is
visible: `emitsAllAtOnce` (over-predicted), `extraWord` (the stub's extra
key collided with the probe phase) and `phaseKeyBypassesWords` (the stub
skipped the lookup instead of bypassing only the returned value).

**Why this is the right failure.** The two real-module suites fail inside
their `bundle()`/`perform()` helpers at `require` - `could not resolve child
component "Interpreter"` and `"PhaseClockModel"` - because the modules are
the first thing the story requires, and the amended C-8 guard fails naming
the four client modules that do not exist yet. Every other assertion in the
tree is green, including the 50 control cases, so the checks that will judge
the shipped modules have each been observed refusing the fake written to
break them. No assertion in the two real-module suites has executed: the
bridge is the controls table below.

### Files touched

| File | Role | AC |
|---|---|---|
| `tests/helpers/VoiceSpec.luau` | new: reads `voice.md` §2.1 through `GatedFs`; pure `parsePhaseTable`, `vacuity` | AC-3 words |
| `tests/helpers/InterpreterContract.luau` | new: the six AC-1/AC-2 checks, one-trace recorder, the real-Transport control | AC-1, AC-2 |
| `tests/helpers/InterpreterStubs.luau` | new: baseline + 16 one-defect interpreters | controls |
| `tests/helpers/PhaseClockContract.luau` | new: the five AC-3 checks, `ROWS`, `machinePhases()` via `PhaseUnion`, `voiceRows()` | AC-3 |
| `tests/helpers/PhaseClockStubs.luau` | new: baseline + 14 one-defect models | controls |
| `tests/server/interpreter_test.luau` | new: AC-1, AC-2 against the shipped module | AC-1, AC-2 |
| `tests/server/interpreter_controls_test.luau` | new: every control pinned to its exact failing set | controls |
| `tests/client/phase_clock_model_test.luau` | new: AC-3 against the shipped modules | AC-3 |
| `tests/client/phase_clock_controls_test.luau` | new: controls, row-naming, `VoiceSpec` discrimination | controls |
| `tests/client/client_requires_test.luau` | **amended** (THEME-001's C-8 guard): four new modules in `EXPECTED`; Net permitted from `Main.client.luau` only; a second control | AC-4 discipline |
| `.claude/tests/project-counters.test.sh` | baselines moved to the predicted post-GREEN tree (below) | harness gate |
| `docs/backlog/stories/SLICE-004.md` | `## Test plan`, this section | - |

No source file, no config, no manifest. `## Contract` was not amended: every
pinned block held against the tree. **No existing export changes** - checked:
the tests call `Transport.bind(definitions, context, handlers, ports)` and
`Bound:sendTo/broadcast` exactly as `src/ReplicatedStorage/Net/Transport.luau`
declares them, build effects exactly as `Session.SessionEffect` and
`PhaseMachine.Effect` declare them, and read `PhaseMachine.Phase` and
`voice.md` as they stand; `TransportStubs.ports`, `PhaseUnion.read`,
`GatedFs`, `Contract.fail`/`firstFew` and `Deep.show` are used unmodified.

### The export shape the tests already pin

Nothing below is a suggestion. Each name and signature is already imported or
called by a test, so getting it wrong is a load failure or a nil call.

    src/server/session/Interpreter.luau            -- required as "@game/server/session/Interpreter"
        Interpreter.perform(effects: { Session.SessionEffect }, ports: Ports) -> ()
        -- `Ports` is the Contract's table, by these field names:
        --   transport: Transport.Bound         called as METHODS: ports.transport:sendTo(playerId, payloadKind, payload)
        --                                                         ports.transport:broadcast(payloadKind, payload)
        --   emit: ({ TelemetryEvent }) -> ()   ports.emit({ e.event }) - a fresh one-element list per Emit
        --   promptRematch: () -> ()            ports.promptRematch()
        --   computeTrace: (roundId) -> ()      ports.computeTrace(e.roundId)
        --   place: (playerId, position) -> ()  ports.place(e.playerId, e.position) - the effect's own table
        -- raises on any other kind (AssignSeats included) with the kind verbatim in the message,
        -- at that effect, with no pre-validation pass; the payload/position/event tables are
        -- passed by identity, never cloned.

    src/client/models/PhaseClockModel.luau         -- required as "@game/client/models/PhaseClockModel"
        PhaseClockModel.describe(view: { phase: string, secondsLeft: number? }, receivedAt: number, now: number)
            -> { phaseKey: string, countdown: string? }
        -- phaseKey = Words.phase[view.phase]; raises with view.phase in the message when that is nil
        -- countdown = string.format("%d:%02d", whole // 60, whole % 60),
        --   whole = math.ceil(math.max(0, secondsLeft - (now - receivedAt))); nil when secondsLeft is nil
        -- must not mutate `view`

    src/client/Words.luau                          -- required as "@game/client/Words"
        Words.phase: { [string]: string }          -- exactly voice.md §2.1's rows: Lobby, Assignment, Round, Resolution, Post,
                                                   -- each mapped to the word in that table (the identity today); no other keys

The effect shapes the tests build are exactly `Session.SessionEffect` and
`PhaseMachine.Effect` as they stand in the tree: `{ kind = "SendTo", playerId,
payloadKind, payload }`, `{ kind = "Broadcast", payloadKind, payload }`,
`{ kind = "Emit", event }`, `{ kind = "PromptRematch" }`, `{ kind =
"ComputeTrace", roundId }`, `{ kind = "Placed", playerId, position }`,
`{ kind = "AssignSeats", seed, players }`.

**Not constrained** (the implementer's choice): the module's internal
structure, whether `perform` returns anything (the tests ignore its result),
the exact wording of the raise beyond containing the kind / the phase, whether
`describe` returns extra fields beyond `phaseKey` and `countdown`, whether
`Words` is frozen, everything in `RoundService.server.luau`,
`Main.client.luau` and `PhaseClockView.luau` (no unit test touches them; the
`typecheck`, `build`, source-guard and layer-guard suites do - see below).

### Tests that passed on arrival

The two `*_controls_test.luau` files and the `VoiceSpec` reader cases are
green in RED **by design**: they are the negative controls, driven through
`InterpreterStubs`/`PhaseClockStubs` and the merged `Transport`, so that
each check is observed firing before GREEN. They are not regression guards
and need no probe; their value is the table below.

One amended case did pass on arrival: `client_requires_test` :: "C-8 as
amended control". It is a test of the guard's own rule function (test-side,
no production import) and it is a paired control - the same `Net` require
permitted at the entry's path and refused at a model's path, with the
`ServerScriptService` require refused at both - so it earns its place as the
negative-control pair `tdd-cycle` asks for. The guard's main case is red
(the four missing modules), which is the right failure.

### Negative controls - expected and measured

All measured in RED under `lune run test` (run 2 above), against the fakes and
the merged `Transport`, **not** against the shipped modules. Confirming each
row against `src/server/session/Interpreter.luau` and
`src/client/models/PhaseClockModel.luau` is GREEN's job: the real-module
suites going green is that confirmation for the baseline rows, and D-1 in
GATES is it for `sendToBroadcasts`.

**Interpreter** (`interpreter_controls_test`, checks: `AC-1 trace`, `AC-1 emit`,
`AC-1 empty`, `AC-1 transport`, `AC-2 unknown`, `AC-2 AssignSeats`):

| Control | Must fail exactly | Predicted | Measured in RED |
|---|---|---|---|
| baseline | nothing | 0 of 6 | 0 of 6 |
| `sendToBroadcasts` (AC-1's named control, D-1) | AC-1 trace, AC-1 transport - the latter with Transport's own `"SeatView" is not a public payload kind` | as pinned | as pinned, message confirmed |
| `sendToDotCall` | AC-1 trace, AC-1 transport | as pinned | as pinned |
| `sendsTwice` | AC-1 trace, AC-1 transport | as pinned | as pinned |
| `dropsEmit` | AC-1 trace, AC-1 emit | as pinned | as pinned |
| `emitsTheEventNotAList` | AC-1 trace, AC-1 emit | as pinned | as pinned |
| `emitsAllAtOnce` | AC-1 trace, AC-1 emit | **predicted also AC-2 unknown** | AC-1 trace, AC-1 emit only: the raise aborts the list before the deferred batch - pinned to the measured set |
| `emitSharesOneList` | AC-1 trace, AC-1 emit | as pinned | as pinned |
| `copiesPayload` | AC-1 trace, AC-1 transport | as pinned | as pinned |
| `prevalidates` | AC-2 unknown, reported with `the trace was []` | as pinned | as pinned |
| `swallowsUnknown` | AC-2 unknown, AC-2 AssignSeats | as pinned | as pinned |
| `raiseOmitsKind` | both AC-2, reported `does not name the kind "Frobnicate"` | as pinned | as pinned |
| `continuesAfterRaise` | AC-2 unknown | as pinned | as pinned |
| `acceptsAssignSeats` | AC-2 AssignSeats | as pinned | as pinned |
| `reversesOrder` | AC-1 trace, AC-1 emit, AC-2 unknown | as pinned | as pinned |
| `placeDropsPosition` | AC-1 trace | as pinned | as pinned |
| `computeTraceDropsRoundId` | AC-1 trace | as pinned | as pinned |

**PhaseClockModel** (`phase_clock_controls_test`, checks: `words`, `phaseKey`,
`unknown phase`, `countdown`, `nil seconds`), with the rows that kill each
countdown mutant (row numbers into `PhaseClockContract.ROWS`):

| Control | Must fail exactly | Killed by | Predicted | Measured in RED |
|---|---|---|---|---|
| baseline | nothing | - | 0 of 5 | 0 of 5 (which also shows `VoiceSpec` read the live §2.1 correctly) |
| `floorsInsteadOfCeil` | countdown | rows 2, 4, 5, 10: `0.2 -> "0:00"`, `59.5 -> "0:59"`, `60.5 -> "1:00"`, `389.5 -> "6:29"` (4 wrong rows) | as pinned | as pinned |
| `roundsInsteadOfCeil` | countdown | row 2 alone: `0.2 -> "0:00"` (59.5 and 60.5 round up correctly) (1 wrong row) | as pinned | as pinned |
| `noClamp` | countdown | row 8: `420, now 500 -> "-2:40"` (1 wrong row) | as pinned | as pinned |
| `paddedMinutes` (`%02d:%02d`) | countdown | every row but `600 -> "10:00"` (10 wrong rows) | as pinned | as pinned |
| `unpaddedSeconds` (`%d:%d`) | countdown | rows with seconds < 10 | as pinned | as pinned |
| `ignoresReceivedAt` | countdown | rows 10, 11: `-> "4:50"`, `-> "5:20"` (2 wrong rows) | as pinned | as pinned |
| `ignoresElapsed` | countdown | rows 8, 10: both `-> "7:00"` (2 wrong rows) | as pinned | as pinned |
| `nilSecondsLeftReadsZero` | nil seconds | - | as pinned | as pinned |
| `mutatesTheView` | countdown | the "mutated the view" line on every row with elapsed > 0 | as pinned | as pinned |
| `echoesUnknownPhase` | unknown phase | - | as pinned | as pinned |
| `wordDrift` (`Post = "Done"`) | words, naming the voice.md line | - | as pinned | as pinned |
| `extraWord` | words | - | **first measured [words, unknown phase]**: the stub's extra key was `Limbo`, the probe phase; renamed to `Intermission` | words only after the rename |
| `missingWord` (`Resolution` absent) | words, phaseKey | - | as pinned | as pinned |
| `phaseKeyBypassesWords` (validates through `Words`, returns `view.phase`) | **nothing** - pinned as an empty set | - | first stub version skipped the lookup too and so stopped raising; corrected to the realistic mutant | [] : NOT CAUGHT, on record |

**The documented blind spot.** Because §2.1 is the identity map today, no
observation can separate "returns `Words.phase[view.phase]`" from "returns
`view.phase`". The controls file pins the mutant as uncaught (an empty
expected set), so the day a HUD story changes a word in `voice.md`, that
line goes red and the blind spot closes deliberately. GREEN should still
implement the lookup as the Contract says; nothing can check it yet.

### Deferred verifications

- **D-1 (the interpreter's routing discriminates) - declined; owner GATES.**
  RED cannot run it: there is no `src/server/session/Interpreter.luau` to
  mutate. What RED can say: the `sendToBroadcasts` control fails `AC-1
  trace` and `AC-1 transport`, the latter with `Transport.broadcast:
  "SeatView" is not a public payload kind`, so a `mutate.sh` swap of `sendTo`
  and `broadcast` in the shipped module is expected to turn exactly the two
  `interpreter_test` cases "over a mixed list ..." and "AC-1 control: through
  the real Transport.bind ..." red with those messages, and leave the other
  four green.
- **D-2 (Studio, four clients) - declined; owner REVIEW.** No test here
  touches `RoundService.server.luau`, `Main.client.luau` or `PhaseClockView.luau`.

### What the tree's existing guards will do to the new files (checked)

- **`tests/shared/source_guard_test.luau` scans `src/client/` and `src/server/`.**
  Confirmed: `SourceScan.sourceFiles()` asks `classify.sh --list source src`,
  and `bash scripts/classify.sh --list source src/client` returns
  `Theme.luau`, `models/ColourMath.luau`, `models/ScreenScale.luau` today;
  `classify.sh src/client/Main.client.luau` and `src/server/RoundService.server.luau`
  both answer `source`. So in **every** new file: no `os.clock`, `os.time`,
  `tick`, `DateTime.now`, **`task.wait`**, `math.random`, `math.randomseed`,
  `Random.new`. `Main.client.luau` takes `now` from `Clock.real().now()`
  (`@game/ReplicatedStorage/Shared/Clock`); so does the driver. Two
  consequences the Contract does not spell out: the driver may not
  `task.wait` (drive from `RunService.Heartbeat`), and **`Rng` has no
  real-random source** (`Rng.fromSeed` only), so the round seed must come
  through `Clock.real().now()` or be a constant - anything else is a
  source-guard failure.
- **`tests/client/client_requires_test.luau` (C-8), amended here:** the four
  new client modules are judged; `Main.client.luau` may require
  `@game/ReplicatedStorage/Net/ClientTransport` and `.../Shared/...`;
  `Words.luau`, `models/PhaseClockModel.luau`, `views/PhaseClockView.luau`
  may require only `./...`, `../...`, `@self...`, `@game/ReplicatedStorage/Shared/...`.
  `PhaseClockView` reaching `Theme` is `../Theme` or `@game/...` - note
  `@game/client/...` is NOT permitted by the rule; use a relative require.
- **`tests/shared/layer_requires_test.luau`:** the driver in `src/server/` may
  require `./session/...`, `./round/...` and `@game/ReplicatedStorage/{Shared,Net}/...`;
  nothing else.
- **`tests/net/raw_remote_guard_test.luau`:** neither entry script may contain
  `OnServerEvent`, `OnServerInvoke` or `.OnClientEvent`; the driver creates
  `RemoteEvent` instances and lets `Transport.bind` connect, the client lets
  `ClientTransport.on` connect.
- **`tests/server/roblox_runtime_guard_test.luau`:** scans `src/server/round`
  only; the driver at `src/server/RoundService.server.luau` is outside it.
- **`typecheck`:** `luau-lsp analyze` over `src` with `globalTypes.d.luau`
  reads both entry scripts (AC-4). Test files are not analysed by the gate.

### Harness counters (`.claude/tests/project-counters.test.sh`)

THEME-001's predictions were confirmed on the tree before this story's files
were added: 228 `.luau` under `src tests lune`, 40 under `src`, 9 under
`src/ReplicatedStorage/Shared`. The RED tree measures 237 (228 + 9 tests).
Set now to the **predicted post-GREEN** values for six new source files:

| Literal | Was | Now | Why |
|---|---|---|---|
| `BASE_FORMAT` | 228 | 243 | + 9 tests + 6 source |
| `BASE_LINT` | 228 | 243 | same |
| `BASE_TYPECHECK` | 40 | 46 | + 6 source under `src` |
| `NARROW_FORMAT` | 40 | 46 | same |
| `NARROW_LINT` | 40 | 46 | same |
| `NARROW_TYPECHECK` | 9 | 9 | nothing new under `Shared` |

Expected under `gates.sh --fast` on the RED tree: `expected count: 243 /
actual count: 237` for format and lint, `244 / 238` for the untracked-file
cases, `46 / 40` for typecheck and the narrow src cases. GREEN must add
exactly six `.luau` files under `src` and no more; a seventh is a counter
failure GREEN cannot fix.

### `bash scripts/gates.sh --fast` on the RED tree

2026-10-08, 455 s, not recorded (a `--fast` run never is):

    --- gate summary ---
    PASS         format (1s, observed 237)
    PASS         lint (0s, observed 237, floor 1)
    PASS         typecheck (2s, observed 40)
    FAIL         unit (316s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (1s, observed 146888)
    FAIL         harness (18s, exit 1) -> .claude/state/gate-logs/harness.log

    --fast skipped: integration mutation
    2 required gate(s) failed.

The shape is the RED shape. `unit` carries exactly the twelve failures of
run 2 (`1570 passed, 12 failed` in its log), no timeout, no load failure, no
lint rule tripped by a test file (`selene over 237 files`, `0 errors`;
`stylua --check` clean over the same). `harness` carries exactly the twelve
counter cases this section predicts - `expected count: 243 / actual count:
237` (format, lint, and the two "ignored file" cases), `244 / 238`
(untracked-file cases), `46 / 40` (typecheck and both narrow src cases), `47
/ 41` (typecheck untracked) - and the "no stray .luau files" precondition,
which is red because `tests/client/client_requires_test.luau` is modified
and the nine new files are untracked; it clears at the RED commit. The unit
gate at 316 s instrumented-equivalent is within CI's 45 min budget (SLICE-006
measured 235 s for 1344 tests on CI); this story adds no loop, no seed
sweep and spawns one `classify.sh --gated` that `GatedFs` already cached for
`TokenSpec`.

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

