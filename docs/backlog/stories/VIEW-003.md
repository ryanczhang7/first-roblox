---
id: VIEW-003
title: The public round view carries public facts and a progress bar of exactly two numbers
slug: the-public-round-view-carries-public-fac
epic: EPIC-07
type: feature
status: in-progress
phase: RED
branch: story/VIEW-003-the-public-round-view-carries-public-fac
depends_on: [PROC-003, CHAN-006, SLICE-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-07`. Everything every player may know goes to every client
(`architecture.md` D15, §9.7). There are two payloads.

**`FacilityView`**, sent once per round: the layout and each machine's static
public facts. Those facts are room, slot, tag and key class, which is public
world state (`roles.md` §3).

**`RoundView`**, sent on change and at least once a second while a clock runs:
- the phase and the seconds left, computed from `Procedure.deadline` during
  `Round` (D11);
- the lobby counts;
- instability;
- dark rooms;
- the active pings;
- each machine's dial, live lamp, committed state and partner lamp;
- **the progress bar, exactly `{ committed, total }`** (`mechanics.md` §3.2
  and §9, T10 (c)).

`SLICE-003` introduced `RoundView` with four fields. This story moves it to its
own module and widens it.

`mechanics.md` §3.2's "never show" table is the specification of what must be
absent. `roles.md` §6 forbids putting the bar in the per-player view.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given any Procedure state, when `RoundView.public` builds the
  progress field, then it has exactly the keys `committed` and `total`.
  `total` is `procedure_length`, and `committed` is the number of committed
  **steps**, since a decoy never commits.
  *Control:* a bar that adds a `track` or `next` field must fail, naming the
  key.
- **AC-2** — Given a machine whose dial is unset, rejected or armed, when its
  public record is built, then `dial.setting` is nil or the setting last
  **turned** on it (from the actuation log), never read from
  `requiredSetting`. For a committed machine, it is the committed setting.
  *Control:* a record that fills `dial.setting` from `requiredSetting` for live
  machines must fail on a fixture whose last rejected turn differs from the
  required setting.
- **AC-3** — Given `FacilityView.public`, when a machine record is inspected,
  then it has exactly the keys `id`, `room`, `slot`, `tag` and `keyClass`, and
  no `requiredSetting`, step, track or finale marker. The layout carries rooms
  (id, column, row), doors (sorted) and the spawn room, and nothing else.
- **AC-4** — Given the Round phase, when `secondsLeft` is read, then it is the
  ceiling of `Procedure.deadline − now`, clamped at 0. It is therefore reduced
  by clock penalties, where the phase machine's own clock would not be.
- **AC-5** — Given a `RoundView`, when its top-level keys are read, then they are
  exactly:
  - `phase`, `secondsLeft`, `players`, `playersMin`, `playersMax` (as in `SLICE-003`);
  - `progress`, `instability`, `dark`, `pings`, `machines`.

  No `σ`, seat relation, turn cue, lens reading, par or outcome appears. The
  outcome travels in `TraceView` (`TRACE-002`).
- **AC-6** — Given `SLICE-003`'s callers of `Session.RoundView`, when this story
  moves the type to `src/server/round/RoundView.luau`, then every caller
  compiles against the new module, and `Session` re-exports nothing stale.

## Contract

**Module.** `src/server/round/RoundView.luau`, pure.

    export type MachinePublic = { id: number, dial: { setting: number?, state: "unset" | "rejected" | "armed" | "committed" },
                                  live: boolean, partnerLamp: boolean? }   -- partnerLamp only on the two finale machines
    export type RoundView = {
        phase: string, secondsLeft: number?, players: { string }, playersMin: number, playersMax: number,
        progress: { committed: number, total: number },
        instability: number,
        dark: { number },                  -- room ids, ascending
        pings: { Pings.PingShown },
        machines: { MachinePublic },       -- ascending id; empty outside Round
    }
    export type FacilityView = {
        rooms: { { id: number, column: number, row: number } },
        doors: { { a: number, b: number } },
        spawnRoom: number,
        machines: { { id: number, room: number, slot: number, tag: number, keyClass: number } },
    }
    RoundView.public(session: Session.SessionState, now: number) -> RoundView
    RoundView.facility(facility: Generator.Facility) -> FacilityView

**The partner-lamp exception.** A partner lamp marks the finale's two machines,
so publishing `partnerLamp` identifies the finale machines to everyone. This is
accepted. The finale is always the last commits (`progress_bar_marks_finale` is
derived for the same reason), and the lamps are world objects anyone in the room
can see (`mechanics.md` §3.2). Only the lamp's **state** is dynamic.
`partnerLamp` is nil on every other machine. **This is a Lead PO reading, and
the Game Designer should confirm it** (report question). Until then, AC-3 does
not forbid it.

**Changed exports, and their callers.** `SLICE-003`'s `Session.RoundView` type
moves here. Callers are `src/server/session/Session.luau` and the `SLICE-003`
tests under `tests/server/`. RED lists them from the tree with
`rg "RoundView" src tests`. `SLICE-004`'s client model reads the payload by
shape, not by this type.

### Pinned at PLANNED -> RED (lead-po, 2026-10-06)

**RED may amend any block in this section, in place, with a reason; GREEN
builds what the amended block says.**

**C-1. PO decision 1 (the user, 2026-10-06): Session is wired in this story.**
`Session.step`'s one `Broadcast` of kind `RoundView` now carries
`RoundView.public(...)`, the widened ten-key view, in place of SLICE-003's
five-field payload. Its cadence does not change: it is still sent where
SLICE-003 sends it, at most once per step and built from the END state.
`pings` is `{}` until `SLICE-006` adds channel state. `FacilityView` is
**built** here (`RoundView.facility`) but not **emitted**; emitting it is
`SLICE-006` AC-5. Change detection is also `SLICE-006`'s.

**C-2. The signature takes an input record, not `Session.SessionState`.**
Amended from the block above. `Session` must require `RoundView` to build its
payload, so `RoundView` requiring `Session`, even for a type, is a runtime
require cycle. `RoundView.luau` therefore requires neither `Session` nor
anything that requires it:

    export type Input = {
        round: PhaseMachine.RoundState,
        procedure: Procedure.ProcedureState?,
        assignment: Ring.Assignment?,
        positions: { [string]: Procedure.Vec },   -- the ACCEPTED positions
        pings: { Pings.PingShown },               -- already shown; Session passes {} until SLICE-006
        tuning: MechanicsTuning.MechanicsTuning,
    }
    RoundView.public(input: Input, now: number) -> RoundView
    RoundView.facility(facility: Generator.Facility) -> FacilityView

`Session` builds `Input` from its own state. `SessionState` already has
`round`, `procedure`, `assignment`, `positions` and `tuning`.

**C-3. Procedure-derived fields exist only in `Round` with a Procedure.**
They are `instability`, `dark`, `machines` and `progress.committed`. When
`input.round.phase == "Round"` and `input.procedure ~= nil`, they are read from
the procedure. Otherwise `instability = 0`, `dark = {}`, `machines = {}` and
`progress = { committed = 0, total = tuning.instance.procedure_length }`.
`pings` is `input.pings` as given (a copy), in every phase. `total` is always
`tuning.instance.procedure_length`, never `#steps`.

**C-4. `progress.committed`** is the number of `true` entries in
`procedure.committed`. A decoy never commits, so that number is steps
committed. It is never `#procedure.log`, and never per track.

**C-5. A machine's public record** (`machines`, ascending `id`, one per
`facility.placement.machines` entry):
- `dial.state`, by precedence:
  1. `committed` if `procedure.committed[id]`;
  2. else `armed` if `procedure.armed ~= nil and procedure.armed.machineId == id`
     (expiry is `Procedure.tick`'s job; the view reads the state as given);
  3. else `rejected` if `Procedure.dial(procedure, id, now).state == "rejected"`
     (inside its reset window);
  4. else `unset`.
- `dial.setting`:
  - `unset`: nil;
  - otherwise the `setting` of the **last** `procedure.log` entry for `id`,
    whatever its `result` (`committed`, `armed`, `wrong_setting` **or
    `not_live`**). That is the setting last turned onto it.
    **Amended in RED (test-developer, 2026-10-06):** the block listed three
    results and omitted `not_live`. A `not_live` rejection is an evaluated
    turn that moved the dial - `Procedure.dial` reports its setting as
    `rejected` for the reset window (PROC-001 P-6/P-8), and AC-2 says "the
    setting last **turned**". Excluding it would show a turned decoy as
    `{ state = "rejected" }` with no setting, contradicting the dial the
    world shows. Every log entry is a turn, so the rule is simply "the last
    entry for `id`". Pinned by the decoy snapshot in
    `tests/helpers/RoundViewContract.luau` and the
    `settingIgnoresNotLiveTurns` control.
  - It is **never** read from `Machines.Machine.requiredSetting`. For a
    committed machine the last turned setting is the committed setting.
- `live`: `Procedure.isLive(procedure, id)`.
- `partnerLamp`: present only on the two `facility.steps.finale` machines. It is
  `Procedure.partnerLamps(procedure, assignment, positions)[id] == true` when
  `assignment ~= nil`, and `false` when it is nil. It is **absent** (nil) on
  every other machine.
- The record's keys are exactly `id`, `dial`, `live` and, on the finale
  machines, `partnerLamp`. `dial`'s keys are exactly `setting` (when non-nil)
  and `state`.

**C-6. `dark`** is the ascending list of layout room ids `r` with
`procedure.dark[r] == true`.

**C-7. `secondsLeft`** moves here from `Session.secondsLeftIn`, unchanged except
for the clamp. `Round` with a Procedure gives `ceil(Procedure.deadline - now)`.
Otherwise it is SLICE-003's config-duration rule, with `nil` where no clock
runs. Every non-nil value is clamped at `0` (`math.max(0, ...)`).

**C-8. `FacilityView`** is a fresh structure, sharing no table with
`facility`:
- `rooms`: `{ id, column, row }` per `layout.rooms` entry, ascending `id`;
- `doors`: `{ a, b }` per `layout.doors` entry, with `a < b`, sorted by `a` then
  `b`;
- `spawnRoom`: `layout.spawnRoom`;
- `machines`: `{ id, room, slot, tag, keyClass }` per placement machine,
  ascending `id`.

Nothing else is carried. The machines carry no `requiredSetting`, and there are
no steps, tracks, finale marker, `par` or `attempt`. The keys are exact.

**C-9. Every list and record in a view is fresh.** Mutating the view must not
touch session state, and the reverse.

**C-10. Callers, from `rg "RoundView|secondsLeft|roundView" src tests`,
2026-10-06.** RED updates every test caller in this RED and names each file in
`## Test plan`. These are SLICE-003's (EPIC-08) DONE tests, changed under PO
decision 1. Each change must be a widening that keeps what SLICE-003's AC
asserted (cadence, the five original fields' values, players as a copy), never
a deletion. The handoff states the list was checked against the tree.
- `src/server/session/Session.luau`: `export type RoundView` (removed, re-typed
  from `RoundView.RoundView`), `secondsLeftIn` and `roundView` (moved), and the
  `SessionEffect` payload type. Removing the type is a changed export, so
  `Session` must not keep a stale `RoundView` alias (AC-6).
- `tests/helpers/SessionContract.luau`: `ROUND_VIEW_KEYS` (the five-key exact
  set) and `expectedRoundView` (five fields, secondsLeft unclamped), plus the
  key-set comparison around line 1120. These become the ten-key set, with the
  five original fields still checked by value.
- `tests/helpers/ScriptedRound.luau`, `SessionRoundContract.luau` and
  `SessionRoundStubs.luau`; `tests/server/session_test.luau`,
  `session_controls_test.luau`, `session_round_test.luau` and
  `session_round_controls_test.luau`. They read `secondsLeft` or the payload.
  RED confirms each still holds, or changes it with a reason.

**C-11. The partner-lamp reading** (block above) is backed by `architecture.md`
D15 and §9.7 ("each machine's ... partner lamp" listed under public world
facts) and by `roles.md` §3, where partner lamps are "Public world". The Game
Designer confirmation stays open as a report question. It is not a blocker.

**C-12. Test placement.** `tests/server/round_view_test.luau` and
`tests/server/round_view_controls_test.luau`, with a contract or stubs pair in
`tests/helpers/` (`RoundViewContract.luau`, `RoundViewStubs.luau`) in the house
pattern. The controls are executed in RED against stub builders:
- a bar with `track`, `next` or `byTrack` (AC-1, naming the key);
- `dial.setting` from `requiredSetting` on a fixture whose last rejected turn
  differs from it (AC-2);
- a facility machine carrying `requiredSetting` (AC-3);
- an unclamped `secondsLeft`, and one from the phase-machine clock that ignores
  penalties (AC-4);
- a view carrying an extra top-level key such as `outcome`, `par` or `seats`
  (AC-5);
- `committed` counted from `#log` (C-4);
- `partnerLamp` on a non-finale machine (C-5);
- a view sharing a table with the input (C-9).

**Oracle partition.**
- AC-1 and AC-5 are **settled** by `mechanics.md` §3.2's "must never show"
  table. Name each assertion after its row.
- AC-2 to AC-4 and AC-6 are **mechanical**.

## Deferred verifications

**D-1. The bar holds its shape.** Use `scripts/mutate.sh` to add a
`byTrack` field to the progress record. AC-1 **must** then fail, naming it. RED
cannot run this. Owner: GATES.

**D-2. The dial never reads the secret.** Use `scripts/mutate.sh` to make
`RoundView.luau` fill `dial.setting` from the machine's `requiredSetting` for
non-committed machines. AC-2 **must** fail. RED cannot run this. Owner: GATES.

**D-3. The clamp is real.** Use `scripts/mutate.sh` to remove the `math.max(0,
...)` clamp. AC-4's past-deadline case **must** fail. Owner: GATES.

**D-4. Session really broadcasts the widened view.** Use `scripts/mutate.sh` so
that Session's broadcast payload drops one of the five new keys, for example
`progress`. The widened SessionContract key-set check **must** fail. This
proves the SLICE-003 suite now pins the ten keys and was not just loosened.
Owner: GATES.

## Out of scope

- Rendering (`HUD-001`), and routing, which is `broadcast` (`SLICE-006`).
- Delta encoding. The whole view is sent each time in M3 (§9.7).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write VIEW-003` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/round/RoundView.luau` (source), `src/server/session/Session.luau` (source), `tests/helpers/ScriptedRound.luau` (test) (+4 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

- PLANNED -> RED contract pinning - orchestrator (`lead-po` role, main session) -
  `claude-opus-5-5`. 2026-10-06. PO decision 1 was put to the user, who chose to
  wire Session now.
- RED - `test-developer` - dispatched with explicit `model: fable`; resolved
  `claude-fable-5-1` (Fable 5.1) per the agent. Matches the plan. Orchestrator
  verified `lune run test` -> `1290 passed, 16 failed`: 15 in `round_view_test`
  (the module is missing, and Session still has its own type) plus session_test's
  widened AC-4 (Session still sends five keys). It independently confirmed the
  C-5 `not_live` amendment against `Procedure.luau`'s `rejected()`, which writes
  `dials[id].setting` and logs `result = reason` for both rejection reasons.

## Test plan

All unit level: `RoundView` is a pure function of plain data, and the one
contract this story changes (Session's broadcast) is pinned by driving the
real `Session.step` with `ScriptedRound` and deep-comparing its payload to
`RoundView.public` of the END state.

**The house pattern.** `tests/helpers/RoundViewContract.luau` holds every
check as a function over a view module `V` (`V.public(input, now)`,
`V.facility(facility)`); `tests/server/round_view_test.luau` applies them to
the real module (red in RED: the file does not exist); `tests/helpers/RoundViewStubs.luau`
is a reference builder plus 31 one-defect builders; `tests/server/round_view_controls_test.luau`
runs every check against every builder and pins the exact set each defect
fires (all executed and measured in RED).

**The fixture is played, not written.** `TurnContract`'s hand-built facility
(7 steps on two tracks, decoys 18 and 19, under a tuning with
`actuation_reset_seconds` 5 and `instability_per_out_of_order` 2) goes
through the real `Procedure.start` / `Procedure.turn`: wrong turn on the
live head (REJECTED, turned 1 vs required 2 - AC-2's named fixture); the same
state past the reset (UNSET, turn still in the log); a decoy turn (`not_live`,
+2, so instability crosses 2 and a room goes DARK); track 1's ordinary steps
only (finale 13 waits at position 0, NOT live); every ordinary step; the
finale ARMED; a wrong turn on the other finale machine (both REJECTED,
instability 4 crosses the second threshold, two rooms dark); re-armed and
COMMITTED (won). Plus the live-finale state with four partner-lamp position
variants, 12 generated 16-machine facilities at their start, one with
`dark` written out of order, nine phase fixtures (Lobby timed / short / past,
Assignment, Round without a Procedure / past, Resolution and Post with the
won Procedure still held, Post past), and a Round whose Procedure is 90 s
past its deadline. 35 snapshots.

| Test (round_view_test.luau) | Level | Covers |
|---|---|---|
| C-2: module loads, exports `public` and `facility` | unit | export shape |
| C-2: RoundView.luau's string literals name no session module | unit (text) | C-2 |
| AC-5 (3.2 "must never show"): top-level keys exactly the ten, each extra attributed to its row | unit | AC-5 |
| AC-1 (3.2 "steps committed, out of procedure_length"): progress exactly `{ committed, total }`, total = procedure_length (8, fixture has 7 steps), committed = count of true | unit | AC-1, C-4 |
| AC-2: dial by C-5 precedence; setting from the log, never requiredSetting; rejected fixture differs from required | unit | AC-2, C-5 |
| C-5: one record per machine ascending, exact keys, live = Procedure.isLive, partnerLamp only on the finale (both/one/none lit, false with no assignment) | unit | C-5, C-11 |
| AC-3: FacilityView exact shape, doors normalised and sorted, no requiredSetting/par/attempt/steps, fresh | unit | AC-3, C-8 |
| AC-4: secondsLeft = max(0, ceil(deadline - now)), penalty visible against the unpenalised clock, -90 -> 0, config rule elsewhere | unit | AC-4, C-7 |
| C-3: procedure fields defaulted in Resolution/Post with the Procedure held and in Round without one; instability pinned in Round | unit | C-3 |
| C-6: dark ascending | unit | C-6 |
| C-1/C-3: pings copied as given in every phase | unit | C-1, C-3 |
| C-9: no aliasing either way, for RoundView and FacilityView | unit | C-9 |
| oracle: whole view deep-equals the Contract's composition on every snapshot | unit | all |
| AC-6 (C-1): every Session broadcast deep-equals RoundView.public of the END state (joins, deal, ticks, wrong turn, reset) | integration | AC-6, C-1, C-10 |
| AC-6 (C-10): Session.luau declares no `export type RoundView` and requires `../round/RoundView` | unit (text) | AC-6 |
| AC-6 (C-10): the text guard has its subject (classifier + non-empty) | unit | AC-6 |

**C-10: SLICE-003's DONE tests, widened (never deleted).** Checked against the
tree with `rg "RoundView|secondsLeft|roundView" src tests` on 2026-10-06;
the list in C-10 matched it exactly.

| File | Change | Why |
|---|---|---|
| `tests/helpers/SessionContract.luau` | `ROUND_VIEW_KEYS` is the ten-key set (`SLICE3_ROUND_VIEW_KEYS` keeps the five); `expectedRoundView` clamps at 0 (no plan step reaches a negative, so no expected number moved); the payload check renamed `roundViewCarriesExactlyTheTenKeys...`, compares the key set against the ten (secondsLeft absent when nil), still checks the five values and `players` as a copy, and additionally requires the five new keys to carry their type (`progress`/`dark`/`pings`/`machines` tables, `instability` number). Contents of the five are `round_view_test`'s. | C-1, C-10, D-4 |
| `tests/server/session_test.luau` | the AC-4 payload test renamed and its name says ten keys | C-10 |
| `tests/server/session_controls_test.luau` | the SLICE-003 stand-in's payload gains the five keys at C-3's defaults (no Procedure there); `RV_PAYLOAD` renamed; requires `MechanicsTuning` for `procedure_length` | the reference must still pass the widened check |
| `tests/helpers/SessionRoundStubs.luau` | the stand-in's `roundView` builds the ten-key payload through `RoundViewStubs.reference.public` from the END-state pieces (assignment and positions now passed at the three call sites), then applies its own `secondsLeft` so the `secondsLeftFromConfig` defect still reaches the payload | the SLICE-005 reference must pass SLICE-003's widened battery |
| `tests/helpers/SessionRoundContract.luau` | `secondsLeftOf` and the C-5 `want` clamp at 0 (never reached on the plan) | C-7 consistency |
| `tests/server/session_round_controls_test.luau` | `SLICE3_PAYLOAD` renamed | C-10 |
| `tests/helpers/ScriptedRound.luau` | **unchanged**: reads only `view.secondsLeft`, which keeps its value | C-10 confirmed |

**Counters.** `.claude/tests/project-counters.test.sh` baselines set to the
predicted post-GREEN values 195/195/32, narrow 32/32/9, with the history
comment (measured RED tree: 194/31/9).

## Handoff: RED -> GREEN

**Resolved model for this RED dispatch:** `claude-fable-5-1` (Fable 5.1), the
planned `fable` row; dispatched with `model: fable` as the dispatch note asks.

### The command

    export PATH="$HOME/.rokit/bin:$PATH"
    lune run test            # the runner has no per-file filter

Baseline on arrival: `1234 passed, 0 failed`. Now: `1290 passed, 16 failed`
(72 tests added: 16 in `round_view_test.luau`, 56 in
`round_view_controls_test.luau`). The 16 failures are exactly this story's:
15 in `round_view_test.luau` and the widened SLICE-003 payload check in
`session_test.luau`. No unrelated test moved; every control passes.

### The failure, verbatim (trimmed to one of each shape)

    FAIL  tests/server/round_view_test.luau :: Contract (C-2): src/server/round/RoundView.luau loads and exports public and facility as plain field functions
          tests/server/round_view_test:50: src/server/round/RoundView.luau did not load: error requiring module "../../src/server/round/RoundView": could not resolve child component "RoundView"
    FAIL  tests/server/round_view_test.luau :: Contract (C-2): RoundView.luau requires neither Session nor anything under session/ - its string literals name no session module
          tests/server/round_view_test:99: src/server/round/RoundView.luau does not exist
    FAIL  tests/server/round_view_test.luau :: AC-6 (C-10): Session.luau declares no RoundView type of its own - no `export type RoundView` in its code - and requires ../round/RoundView
          tests/server/round_view_test:281: AC-6: src/server/session/Session.luau must take RoundView from src/server/round/RoundView.luau and keep no stale alias:
            line 129 declares a RoundView type: export type RoundView = {
            no require of "../round/RoundView" among the string literals
    FAIL  tests/server/session_test.luau :: AC-4 (widened by VIEW-003 C-10): every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax, progress, instability, dark, pings, machines } by pairs; ...
          AC-4: "join ann (below min)": the RoundView key set is { 1 = "phase", 2 = "players", 3 = "playersMax", 4 = "playersMin" }, expected exactly { 1 = "dark", 2 = "instability", 3 = "machines", 4 = "phase", 5 = "pings", 6 = "players", 7 = "playersMax", 8 = "playersMin", 9 = "progress" } (secondsLeft nil in Lobby; VIEW-003 widened SLICE-003's five keys to ten)
          AC-4: "join ann (below min)": RoundView.instability is nil, expected a number (VIEW-003)
          ...

The other 12 `round_view_test` failures all read `did not load ... could not
resolve child component "RoundView"` from the load check at line 50. **Why
this is the right failure:** the module the story adds does not exist, so
every behavioural test fails at the export check - one counted failure per
criterion, not one LOAD FAIL - and the two Session-side tests fail on their
own assertions: Session still declares its own `RoundView` type and still
sends the five-key payload. Nothing fails on a timeout, a lint rule or a
config error (`bash scripts/gates.sh --fast` below).

### Files

New: `tests/helpers/RoundViewContract.luau`, `tests/helpers/RoundViewStubs.luau`,
`tests/server/round_view_test.luau`, `tests/server/round_view_controls_test.luau`.
Changed (C-10 widenings, see `## Test plan`): `tests/helpers/SessionContract.luau`,
`tests/helpers/SessionRoundContract.luau`, `tests/helpers/SessionRoundStubs.luau`,
`tests/server/session_test.luau`, `tests/server/session_controls_test.luau`,
`tests/server/session_round_controls_test.luau`. Harness:
`.claude/tests/project-counters.test.sh` (baselines 195/195/32, narrow
32/32/9, predicted post-GREEN). Story: `## Contract` C-5 amended (not_live),
`## Test plan`, this section.

### The export shape the tests already pin

Nothing below is a suggestion. Each name is already called by a test, so
getting it wrong is a failing assertion rather than a debate.

    src/server/round/RoundView.luau                    -- NEW, pure, under src/server/round
      RoundView.public(input: Input, now: number) -> RoundView
      RoundView.facility(facility: Generator.Facility) -> FacilityView
      -- plain field functions on the returned table (called with a dot)
      -- MUST NOT require Session or anything under session/ (C-2): the test
      -- scans the file's string literals for "session/" and "/Session"

    Input (C-2):   { round: PhaseMachine.RoundState, procedure: Procedure.ProcedureState?,
                     assignment: Ring.Assignment?, positions: { [string]: Procedure.Vec },
                     pings: { Pings.PingShown }, tuning: MechanicsTuning.MechanicsTuning }
    RoundView:     { phase, secondsLeft?, players, playersMin, playersMax,
                     progress = { committed, total }, instability, dark = { number },
                     pings = { PingShown }, machines = { MachinePublic } }      -- exactly these keys
    MachinePublic: { id, dial = { setting?, state }, live, partnerLamp? }      -- partnerLamp key present
                                                                               -- (true/false) ONLY on the two
                                                                               -- finale machines, absent elsewhere
    FacilityView:  { rooms = { { id, column, row } }, doors = { { a, b } }, spawnRoom,
                     machines = { { id, room, slot, tag, keyClass } } }        -- exactly these keys

    src/server/session/Session.luau                    -- EDITED
      - no `export type RoundView =` anywhere in its CODE (comments are blanked by
        the scan; a comment may still mention the name)
      - a string literal exactly "../round/RoundView" (or "./RoundView") - i.e.
        `require("../round/RoundView")`
      - the Broadcast/RoundView payload deep-equals
        RoundView.public({ round, procedure, assignment, positions, pings = {}, tuning }, now)
        built from the END state of the step, with SLICE-003's cadence unchanged
        (the SLICE-003 suites still run and pin it)

Values the assertions pin exactly (all derived in the helper from the merged
modules, never from the view):

- `secondsLeft`: Round with a Procedure -> `math.max(0, math.ceil(Procedure.deadline(p) - now))`;
  else SLICE-003's config rule, clamped; nil in Assignment, Resolution, a Lobby
  below playersMin. `round.config` is read for the durations.
- `progress.total` = `input.tuning.instance.procedure_length` in EVERY phase
  (the fixture has 7 steps and total must read 8). `progress.committed` =
  number of `true` entries in `procedure.committed`, 0 outside Round-with-Procedure.
- `instability` = `procedure.instability` in Round-with-Procedure, else 0.
- `dark` = ascending room ids with `procedure.dark[id] == true`, `{}` otherwise.
- `machines`: one record per `facility.placement.machines` entry, ascending
  `id`, `{}` outside Round-with-Procedure. `dial.state` by C-5's precedence:
  committed > armed (`procedure.armed.machineId == id`, before asking
  `Procedure.dial`, which reports an armed machine as unset) > rejected
  (`Procedure.dial(p, id, now).state == "rejected"`) > unset. `dial.setting`
  nil when unset, else the `setting` of the LAST `procedure.log` entry for the
  id (any result, `not_live` included - C-5 as amended). `live` =
  `Procedure.isLive(p, id)`. `partnerLamp` =
  `Procedure.partnerLamps(p, assignment, positions)[id] == true`, `false` when
  `assignment == nil`, present only for `facility.steps.finale` ids.
- `pings` = a copy of `input.pings` (list and entries) in every phase.
- Every table in either view is fresh: no table reachable from a view is
  `rawequal` to one reachable from the input/facility, and mutation in either
  direction does not cross.
- `FacilityView.doors` are normalised (`a < b`) and sorted by `a` then `b`
  (one fixture lists them out of order with one reversed); rooms ascending by
  id with exactly `id, column, row`.

**Not constrained** (the implementer's choice): whether `dial.setting` is read
from the log or from `procedure.dials[id].setting` - they agree on every
reachable state and the `settingFromDials` control measures that the suite
accepts either; how `Session` builds `Input` (a local helper or inline); where
`secondsLeftIn` goes (it may move into the module per C-7 or stay private, as
long as the payload matches); error wording; any extra private function; how
`FacilityView` is reached from Session (it is built, not emitted - SLICE-006).

### Tests green on arrival

One: `AC-6 (C-10): the guard above has its subject` - a vacuity check that the
classifier returns `Session.luau` and the file is non-empty. It earns its
place as the negative control for the text guard beside it: without it a
guard scanning an empty or unclassified file would pass over nothing. It
guards an invariant of the harness (ROUND-001 AC-6), not of this story.

### Expected value of every negative control

All 31 builders in `RoundViewStubs.luau` were EXECUTED in RED against the
11 checks in `RoundViewContract.luau` (nothing in them needs the missing
module) and each pins the EXACT set of checks it fires. The reference fails 0
of 11 over 35 snapshots. The table is the `EXPECTED` map in
`round_view_controls_test.luau`; measured in RED, every row passes:

| Control (one defect) | Threshold | Fires exactly (measured) |
|---|---|---|
| progressTrack / progressNext / progressByTrack | AC-1 names the key and the 3.2 row | AC-1, oracle |
| committedFromLog | AC-1 says "that is #procedure.log" | AC-1, oracle |
| totalFromSteps (7 vs 8) | AC-1 names 7 and 8; C-3 keeps total at 8 outside Round | AC-1, C-3, oracle |
| settingFromRequired (live rejected/armed read the secret) | AC-2 names machine 11, required 2, turned 1, state rejected; start and armed snapshots pass | AC-2, oracle |
| settingFromRequiredWhenUnset | AC-2 on "start: nothing turned" | AC-2, oracle |
| armedReadAsUnset (Procedure.dial alone) | AC-2 wants `{ setting = 1, state = "armed" }` | AC-2, oracle |
| settingIgnoresNotLiveTurns | AC-2 on the decoy (`{ setting = 2, state = "rejected" }`) | AC-2, oracle |
| settingFromDials | indistinguishable today | none (measured, stated) |
| partnerLampEverywhere / IgnoresPositions / WithoutAssignmentIsNil | C-5 names the non-finale machine / the one-holder snapshot / the no-assignment snapshot | C-5, oracle |
| machinesDescending | C-5 "machines[1].id is 19, expected 11" | C-5, oracle |
| liveFromPosition | C-5 only on "one track done" | C-5, oracle |
| facilityWithRequiredSetting / facilityWithPar | AC-3 names the key (and the secret) | AC-3 |
| facilityDoorsAsGiven | AC-3 on the shuffled fixture only, `doors.1.a: expected 1, got 3` | AC-3 |
| facilityAliasesRooms | AC-3 shared tables; C-9 mutation crosses | AC-3, C-9 |
| unclampedSecondsLeft | AC-4 `-90 -> 0`, Lobby/Round/Post past-duration cases; every in-clock snapshot passes | AC-4, oracle |
| secondsLeftIgnoresPenalties | AC-4 on every penalised snapshot (8), "the view ignores the penalty"; start passes | AC-4, oracle |
| secondsLeftFromConfigDuration | AC-4 "expected ceil(Procedure.deadline -" | AC-4, oracle |
| extraOutcome / extraPar / extraSeats | AC-5 names the key and its row | AC-5, oracle |
| readsProcedureOutsideRound | C-3 Resolution and Post with the Procedure held; AC-1 committed 7 vs 0 | AC-1, C-3, oracle |
| pingsOnlyInRound | pings check on Lobby/Post | pings, oracle |
| darkDescending | C-6 on two-dark and `4, 1, 3` -> `{1, 3, 4}` | C-6, oracle |
| sharesPlayers / sharesPings / sharesPingEntries | C-9 names the field; pings check sees the alias | C-9 (+ pings for the two ping ones) |

Measured scenario numbers GREEN should see again: instability 1 / 3 / 4 across
the rejected / decoy / disarmed snapshots; `penaltySeconds` = instability x 20;
secondsLeft on the rejected snapshot (now 102) = 978 against an unpenalised
998; one dark room after the decoy, two after the disarm; 8 penalised
snapshots; 2 lit partner lamps on the both-holders snapshot, 1 on the
one-holder snapshot. Confirming these against the shipped module is GREEN's
job: `round_view_test.luau` runs the identical checks, so they must pass with
no edit to any test.

### Deferred verifications declined here

D-1..D-4 need the real module and are **declined in RED**, owner GATES as the
story says. Expected outcomes: D-1 (`byTrack` on the bar) -> `AC-1` red naming
`"byTrack"` and the per-track row, `oracle` red, all else green; D-2
(`requiredSetting` for non-committed machines) -> `AC-2` red on the rejected
and reset snapshots, `oracle` red; D-3 (clamp removed) -> `AC-4` red on the
past-deadline case (`-90`), `oracle` red; D-4 (Session drops `progress`) ->
`session_test.luau`'s widened payload check red on every step ("missing
progress" in the key set), and `round_view_test.luau`'s AC-6 deep-compare
red; nothing in the controls files moves. The measured control sets above are
the same mechanism observed on stubs.

### Discovered, and what it changes

- **C-5 amended** (in `## Contract`): the dial-setting rule now reads "the
  last log entry for the id", `not_live` included. The fixture's decoy turn
  pins it. Reason recorded beside the amendment.
- `Procedure.dial` reports an ARMED machine as `unset` (its dial carries no
  `rejectedUntil`), so the armed check must come before it - exactly C-5's
  precedence; the `armedReadAsUnset` control shows the cost of getting it
  wrong.
- The real `Session` keeps `procedure` through Resolution and Post, so C-3's
  "only in Round with a Procedure" is live behaviour, not a corner: the
  phase fixtures hold the won Procedure in both and expect the defaults.
- `TurnContract`'s fixture has 7 steps against `procedure_length` 8, which is
  what makes "total is never #steps" a real assertion.
- `bash scripts/gates.sh --fast` shape is recorded below.

### `bash scripts/gates.sh --fast` on the uncommitted RED tree (2026-10-06, local)

    PASS         format (1s, observed 194)
    PASS         lint (1s, observed 194, floor 1)
    PASS         typecheck (2s, observed 31)
    FAIL         unit (128s, exit 1) -> .claude/state/gate-logs/unit.log      1290 passed, 16 failed
    UNCONFIGURED coverage
    PASS         build (0s, observed 119695)
    FAIL         harness (16s, exit 1) -> .claude/state/gate-logs/harness.log  project-counters: 29 passed, 12 failed

`unit` fails only on this story's 16 assertions (15 `round_view_test`, 1
`session_test` widened payload). `harness` fails on the stray-file
precondition (clears at the RED commit) and the 11 predicted off-by-one
counters: `expected count: 195 / actual count: 194` for format and lint,
`32 / 31` for typecheck and both narrow src cases, `196 / 195` and `33 / 32`
for the untracked-file cases, `195 / 194` and `32 / 31` for the ignored-file
cases; the narrow typecheck (9) does not fail. Timings are local; the unit
gate's 128 s is the whole suite under `lune run test`, no per-test timeout
exists in this runner, and the new files add about a second.

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


- **PO, PLANNED -> RED (2026-10-06).**
  - *Gate.* `unit` (required) covers `src/server/**`. `RoundView.luau` and the
    `Session.luau` edit are both read by it, so `required_gates` stays empty.
  - *PO decision 1 (the user chose it, 2026-10-06).* Session's RoundView
    broadcast is widened in this story rather than in SLICE-006 (C-1). The cost
    is accepted: SLICE-003's DONE tests that pin the five-key payload are
    updated in this RED, as widenings, under C-10. D-4 proves the widened check
    is not a loosened one.
  - *PO decision 2.* The Contract's `RoundView.public(session, now)` would be a
    require cycle, so it takes an `Input` record instead (C-2).
  - *Epic.* EPIC-07 done-when item 3 maps to AC-1, AC-2, AC-3 and AC-5. One
    reading is recorded here. An **armed** finale machine's `dial.setting` is
    the setting last turned onto it, which is necessarily its required one.
    Publishing it is not publishing the secret: it is the dial's physical
    position, which `roles.md` §3 lists as public world, and AC-2 names
    `armed` explicitly. The view never **reads** `requiredSetting` (D-2). This
    is the same kind of exception as the partner lamp (C-11), and it goes to
    the same Game Designer report question.
  - *Counters.* GREEN adds exactly one source file,
    `src/server/round/RoundView.luau`, under `src/server`. RED sets the
    `project-counters` baselines to the predicted post-GREEN values and commits
    them under `phase: RED`.
