---
id: SLICE-004
title: Four Studio clients see the phase, the countdown and their own seat card
slug: four-studio-clients-see-the-phase-the-co
epic: EPIC-03
type: feature
status: todo
phase: PLANNED
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
  - `PromptRematch` and `ComputeTrace` become the port calls named in the
    contract.

  Order is preserved.
  *Control:* an interpreter that turns a `SendTo` into a broadcast must fail,
  because `Transport` raises for a private kind.
- **AC-2** — Given an effect kind the interpreter does not know, when it is
  performed, then it raises, naming the kind. A silently dropped effect is a
  lost replication.
- **AC-3** — Given a `RoundView` payload and a local receive time, when
  `PhaseClockModel.describe(view, receivedAt, now)` runs, then:
  - it returns the phase's display key (`voice.md`'s word for it);
  - it returns `mm:ss` for `max(0, secondsLeft − (now − receivedAt))`, rounded
    up;
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

