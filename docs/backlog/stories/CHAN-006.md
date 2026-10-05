---
id: CHAN-006
title: Each player has at most one live ping and it clears when it should
slug: each-player-has-at-most-one-live-ping-an
epic: EPIC-06
type: feature
status: in-progress
phase: RED
branch: story/CHAN-006-each-player-has-at-most-one-live-ping-an
depends_on: [CHAN-005, PROC-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. The lifecycle of an accepted ping (`mechanics.md` §4.1, §8):

- **One active ping per player** (`active_pings_per_player`). A new ping
  replaces the old one, so nobody can lay out a pattern, the drawing surface a
  cipher would need.
- A ping lasts `ping_display_seconds`, or until the machine it targets commits,
  or until it is replaced.
- Two players pinging the same target both show.
- The server logs every ping (sender, target, position, time) for the trace.
  The trace's "read helper ping" also needs to know whether the target's room
  was lit when the ping was made (`mechanics.md` §7, G12).

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a player with an active ping, when they make another accepted
  ping, then the active set holds only the new one for that player. The old one
  is gone, not expired later.
  *Control:* an implementation that appends must fail, holding 2.
- **AC-2** — Given a ping made at `t`, when `Pings.tick` runs at `t +
  ping_display_seconds − ε`, then it is active. At `t +
  ping_display_seconds`, it is gone.
- **AC-3** — Given an active ping of kind `setting` or `machine` on machine `m`,
  when `m` commits (`Pings.onCommitted(m)`), then that ping is cleared, and
  pings on other machines and on doorways are untouched.
- **AC-4** — Given two players pinging the same target, when the active set is
  read, then both pings are present, each with its sender.
- **AC-5** — Given any sequence of accepted pings, replacements, expiries and
  clears, when the log is read, then it holds exactly one entry per accepted
  ping, in order, with `{ senderId, kind, target, setting?, position, at,
  roomLit }`. Nothing is ever removed from it, and a refused ping is never
  logged.
- **AC-6** — Given the active set, when `Pings.shown(state)` builds the public
  payload, then each entry is exactly `{ senderId, kind, target, setting? }`:
  there is no position of the sender and no expiry time.

## Contract

**Module.** `src/server/channel/Pings.luau`, extended:

    export type ActivePing = { senderId: string, kind: string, target: number, setting: number?, at: number }
    export type PingLogEntry = { senderId: string, kind: string, target: number, setting: number?,
                                 position: Procedure.Vec, at: number, roomLit: boolean }
    export type PingState = { active: { [string]: ActivePing }, log: { PingLogEntry } }
    export type PingShown = { senderId: string, kind: string, target: number, setting: number? }

    Pings.new() -> PingState
    Pings.accept(state, senderId: string, target: PingTarget, position: Procedure.Vec, now: number,
                 roomLit: boolean) -> PingState
    Pings.tick(state, now: number, tuning) -> PingState
    Pings.onCommitted(state, machineId: number) -> PingState
    Pings.shown(state) -> { PingShown }

- `position` is the target's position (`Pings.targetPosition`), which is the
  thing the trace needs. It is never the sender's.
- `roomLit` is supplied by the caller from `Procedure.isDark` for the target's
  room. A doorway is always logged as lit.

**Semantics, pinned at PLANNED → RED (lead-po, 2026-10-05).** RED may amend
any block below in place, with a dated reason beside it; GREEN builds what the
amended block says.

- **C-1. Types.** `Procedure.Vec` is `{ x, y, z }` (already exported).
  `target: PingTarget` is the existing CHAN-005 type. `tuning` in `tick` is the
  full `MechanicsTuning.MechanicsTuning`; the duration is read from
  `tuning.channel.ping_display_seconds` (15 today) and nowhere else. A test
  passes a tuning with a different value (e.g. 4) to prove it is read, not
  hard-coded.
- **C-2. Purity.** Every function is pure: no clock, no transport, no
  `os.clock`. Each of `accept`, `tick`, `onCommitted` returns a **new**
  `PingState` and never mutates the state, its `active` map or its `log` list
  that it was given (the `Procedure` `copy` idiom). A test holds the old state
  and checks it is unchanged after each call.
- **C-3. `new()`** returns `{ active = {}, log = {} }`, both empty.
- **C-4. `accept`** sets `active[senderId] = { senderId, kind, target, setting,
  at = now }` (replacing any entry for that sender, at most one per sender;
  `active_pings_per_player` = 1 is derived and the module need not read it),
  and appends one `PingLogEntry` to the end of `log` with `at = now`,
  `position` = the argument (copied as given) and `roomLit` = the argument,
  **except that a `doorway` ping always logs `roomLit = true`**, whatever was
  passed. `setting` is present for a `setting` ping and absent (nil) for the
  others. `accept` does not validate; it trusts its caller (CHAN-005's
  `request` already has).
- **C-5. Expiry, half-open.** `tick(state, now, tuning)` removes every active
  ping with `now >= at + ping_display_seconds` and keeps every one with
  `now < at + ping_display_seconds`. AC-2's ε is `1e-6`; test `at` values are
  chosen so the sums are exact in binary (e.g. `at = 10`, `d = 15`, so the
  boundary is exactly `25`). `tick` never touches `log`.
- **C-6. Commit clears.** `onCommitted(state, m)` removes every active ping with
  `kind == "setting"` or `kind == "machine"` and `target == m`. A `doorway`
  ping whose `target` is numerically `m` is **untouched** — doorway ids index
  `layout.doors` and machine ids are machine `id` fields, so the same number
  can name one of each. `onCommitted` never touches `log`.
- **C-7. `shown(state)`** returns a fresh list, one entry per active ping,
  **sorted ascending by `senderId`** (string order), each with exactly the keys
  `senderId`, `kind`, `target` and — for a `setting` ping only — `setting`. No
  `at`, no `position`, no expiry, no other key. An empty state shows `{}`.
- **C-8. The log.** Append-only: it grows by exactly one entry per `accept`
  and by nothing else; `tick`, `onCommitted` and `shown` leave it equal,
  entry by entry, to what it was. "A refused ping is never logged" holds
  structurally: the only writer is `accept`, and CHAN-005's `request` takes no
  `PingState`. AC-5's refusal clause is tested by driving `Pings.request` to a
  refusal next to a state and asserting the state's log is unchanged, plus a
  sequence in which only the accepted calls reach `accept`.
- **C-9. What stays.** `targetPosition`, `validate` and `request` keep their
  CHAN-005 signatures and behaviour. The CHAN-005 suites must stay green.

**Callers of changed signatures.** None. Every export this story adds is new
(`new`, `accept`, `tick`, `onCommitted`, `shown`, and the four types); no
existing export's signature changes. Checked against the tree at `f637de1`:
`rg "Pings\.(new|accept|tick|onCommitted|shown)" src tests` returns nothing.
RED's handoff must state that it re-ran that check.

**Oracle partition.**
- AC-2 is **settled** by `ping_display_seconds` (read out from
  `tuning.channel`, 15; and a substituted tuning value, to prove it is read).
- AC-1, AC-3, AC-4, AC-5 and AC-6 are **mechanical**: exact pinning of sets,
  keys, order and counts. There is no invented metric in this story.

## Deferred verifications

**D-1. Replacement, not append.** Use `scripts/mutate.sh` on `Pings.luau` so
that `accept` stores a second ping for the same sender under a distinct key
(or otherwise keeps the old entry). AC-1 **must** fail, holding 2. RED cannot
run this. Owner: GATES.

**D-2. The expiry boundary is half-open.** Use `scripts/mutate.sh` to turn the
expiry comparison the other way at the boundary (`>=` to `>`, or `<` to `<=`,
whichever GREEN wrote). AC-2's "gone at exactly `t + d`" case **must** fail.
Owner: GATES.

**D-3. A commit spares doorways.** Use `scripts/mutate.sh` to drop the kind
check in `onCommitted`. AC-3's doorway-with-the-same-number case **must** fail.
Owner: GATES.

**D-4. `shown` leaks nothing.** Use `scripts/mutate.sh` to make `shown` include
`at` (or return the active entry itself). AC-6 **must** fail. Owner: GATES.

## Out of scope

- Validation (`CHAN-005`) and session wiring (`SLICE-006`).
- The HUD's distinction between your helper's ping and anyone else's, a client
  model in `HUD-003`, computed from the seat view the client already has.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-006` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/channel/Pings.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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
- PLANNED → RED orchestration - `lead-po` - `claude-opus-5-5` (this session's
  own model). 2026-10-05.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), from an **explicit
  `model: fable` in the dispatch**, per the plan's `fable` row; the agent
  reported the same id. 2026-10-05.

## Test plan

**Level: unit**, on `src/server/channel/Pings.luau` alone. Every function this
story adds is pure (C-2), so there is no contract to integrate and nothing a
user walks end-to-end; `Session` wiring is `SLICE-006`'s.

**Layout** (the house pattern from CHAN-005):

| File | Role |
|---|---|
| `tests/helpers/PingLifecycleContract.luau` | the checks, written once over a `Pings` module handed in as a parameter; `CHECKS` table + `failures(P)` |
| `tests/helpers/PingLifecycleStubs.luau` | `reference` (the Contract written out) and 21 implementations with exactly one defect each; `request`/`targetPosition` borrowed from `PingsStubs.reference` |
| `tests/server/ping_lifecycle_test.luau` | the checks applied to the real module (pcall-guarded require, per-criterion failures) - **red in RED** |
| `tests/server/ping_lifecycle_controls_test.luau` | the checks applied to the stubs: the settled number read out, the reference accepted, each defect's fire set pinned exactly - **green in RED**, this is where every check is OBSERVED to fire |

**Checks and the criterion each pins** (one test per row in `ping_lifecycle_test.luau`):

| Check | AC | Oracle | What it pins |
|---|---|---|---|
| `newReturnsAnEmptyStateFreshEachCall` | C-3 | mechanical | `new()` is exactly `{ active = {}, log = {} }`; a fresh table with fresh maps per call |
| `aSecondPingBySameSenderReplacesTheFirstAtOnce` | AC-1 | mechanical | after each of kim's three pings `active` is exactly `{ kim = { senderId, kind, target, setting?, at = now } }`; a tick at 24 (before the first ping's own expiry at 25) still shows only the newest; lee's ping is untouched by kim's replacements |
| `aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade` | AC-2 | **settled**: `d = tuning.channel.ping_display_seconds` read out (15; substituted 4) | at `10`, `10 + d - 1e-6` present; at `10 + d`, `10 + d + 1` gone; two pings expire independently; `tick` leaves the log equal; empty ticks to empty |
| `aCommitClearsSettingAndMachinePingsOnThatMachineOnly` | AC-3 | mechanical | five pings (setting+machine on 1, machine+setting on 2, **doorway 1**); `onCommitted(1)` leaves exactly `{ pat, ann, bob }`, `onCommitted(2)` exactly `{ kim, lee, ann }`, `onCommitted(7)` all five; log equal |
| `twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender` | AC-4 | mechanical | kim+lee on machine 1 and pat+zoe on setting 2 of machine 1 are all four present under their own senderId; `shown` has four entries |
| `theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved` | AC-5 | mechanical | after every step of accept / accept / replace / tick(40) / accept / commit(2) / accept the log deep-equals the accepted pings so far, in order, each exactly `{ senderId, kind, target, setting?, position, at, roomLit }`; `shown` leaves it alone |
| `aDoorwayPingAlwaysLogsRoomLitTrue` | AC-5 (C-4) | mechanical | doorway with `false` -> `true`; machine/setting log the value given |
| `aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog` | AC-5 (C-8) | mechanical | seven `Pings.request` calls on CHAN-005's fixture, four refused (`committed_machine`, `no_such_target`, `no_position`, `setting_mismatch`); a refused call leaves the state deep-equal to its snapshot; only the three accepted reach `accept`; the log is exactly those three with the target's position per the fixture's independent oracle |
| `shownIsExactlySenderKindTargetAndSettingSortedBySender` | AC-6 (C-7) | mechanical | `shown(new()) == {}`; four pings -> exactly `{ {ann, machine, 1}, {kim, doorway, 2}, {lee, setting, 1, setting = 1}, {zoe, setting, 2, setting = 3} }` (deep-equal: no `at`, no position, no extra key); not the active map, not the same list twice, adding to it leaves the state unchanged |
| `acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput` | C-2 | mechanical | six calls (accept new / accept replace / tick expiring all / tick expiring none / commit clearing two / commit clearing none): result is not `rawequal` to the input; input, target and position deep-equal their snapshots |

**Edges covered:** empty state (`new`, `shown`, `tick`); one ping; many (five
senders); the exact boundary `at + d` from both sides with `ε = 1e-6`; a commit
on a machine nobody pinged; a doorway whose id equals the committed machine's
(C-6); a replacement across kinds (machine -> doorway -> setting); `setting`
present only on setting pings in both `active` and `shown`.

**Out of scope, deliberately not pinned:** validation (CHAN-005's suites are
untouched and still green, 61/61); `Session` wiring; HUD distinctions.

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

**Written by the Test Developer, 2026-10-05.** The model that actually ran this
phase identifies as Claude Fable 5.1 (`claude-fable-5-1`) - the plan's `fable`
row, not the agent file's `opus`. I cannot see whether that came from an
explicit dispatch override or a session setting; the orchestrator records
which, below `## Model guidance`.

### Command

    lune run test

(from the repo root; ~2 min 15 s wall on this machine). Only the four new
files are filtered below; the whole suite is what the `unit` gate runs.

### The failure, verbatim, and why it is the right one

    FAIL  tests/server/ping_lifecycle_test.luau :: C-3: Pings.new() returns exactly { active = {}, log = {} }, ...
          C-3: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-1: a second accepted ping by the same sender replaces the first at once ...
          AC-1: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-2: a ping made at 10 is active at 10 + ping_display_seconds - 1e-6 and gone at exactly ...
          AC-2: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-3: onCommitted(state, m) clears the setting and machine pings on m and nothing else ...
          AC-3: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-4: two senders pinging one target ...
          AC-4: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-5: over accepts, a replacement, an expiry and a commit the log holds exactly one ... per accepted ping ...
          AC-5: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-5: a doorway ping always logs roomLit = true whatever was passed ...
          AC-5: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-5: a refused request leaves the state unchanged, and in a mixed sequence only the accepted pings reach the log ...
          AC-5: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: AC-6: shown(state) is exactly { senderId, kind, target, setting? } per active ping ...
          AC-6: Pings.new is nil, expected a function
    FAIL  tests/server/ping_lifecycle_test.luau :: C-2: accept, tick and onCommitted each return a new state and never mutate ...
          C-2: Pings.new is nil, expected a function
    1123 passed, 10 failed

CHAN-005's `Pings.luau` exists and loads (the pcall-guarded require succeeds),
so the failure is not a load error: each check stops at the contract's
`need()` because the export this story adds is absent from the frozen module
table. `new` is the first function every check needs (it builds the state), so
it is the one named; `accept`, `tick`, `onCommitted` and `shown` are checked
next and are equally absent. That is exactly "the module lacks the functions",
which is what RED is for. **No assertion past `need()` has executed against
the real module** - see the controls table for where each one was observed.

Everything else is green: **1123 passed, 10 failed**, the 10 being the rows
above. `tests/server/ping_lifecycle_controls_test.luau` is **24/24 green**
(1 settled-number test, 2 baselines, 21 controls). CHAN-005's suites
(`pings_test`, `pings_controls_test`, `ping_remote_test`,
`ping_remote_controls_test`) are **61/61 green**, untouched.

### Files touched

| File | Status | Covers |
|---|---|---|
| `tests/helpers/PingLifecycleContract.luau` | new | the ten checks (AC-1..AC-6, C-2, C-3), `CHECKS`, `failures` |
| `tests/helpers/PingLifecycleStubs.luau` | new | `reference` + 21 single-defect implementations |
| `tests/server/ping_lifecycle_test.luau` | new | the ten checks against the real module - one test per row of the Test plan table |
| `tests/server/ping_lifecycle_controls_test.luau` | new | settled number, two baselines, 21 controls (fire sets pinned exactly) |
| `.claude/tests/project-counters.test.sh` | edited | `BASE_FORMAT`/`BASE_LINT` 172 -> 176 (four test files, no source), with the usual note; typecheck and narrow counters unchanged. Set in RED and to be committed in the RED commit, per the house rule (check-boundaries 3j refuses a `.claude/tests/**` change from any other phase) |
| `docs/backlog/stories/CHAN-006.md` | edited | `## Test plan`, this section |

No `## Contract` block was amended. No manifest change; no test dependency
was needed.

### The export shape the tests already pin

All imports: `../../src/server/channel/Pings` (via pcall), and from the
existing tree only `src/shared/MechanicsTuning`, `src/server/facility/Machines`
and `src/server/procedure/Procedure` through `tests/helpers/PingsContract.luau`
(unchanged). Nothing new is required from any other module.

Exported functions, called with exactly these positional arguments:

    Pings.new() -> PingState
    Pings.accept(state, senderId: string, target: PingTarget, position: Vec, now: number, roomLit: boolean) -> PingState
    Pings.tick(state, now: number, tuning) -> PingState          -- tuning is the full MechanicsTuning table;
                                                                  -- only tuning.channel.ping_display_seconds is read
    Pings.onCommitted(state, machineId: number) -> PingState
    Pings.shown(state) -> { PingShown }

Shapes the assertions deep-compare (`Deep.equal`, so an extra key or a missing
key fails by name):

- `PingState` has exactly the keys `active` and `log` (`new()` is compared
  against `{ active = {}, log = {} }` exactly - a third key fails C-3).
- `state.active` is a map **keyed by `senderId`**; each value is exactly
  `{ senderId, kind, target, setting?, at }` with `at = now` of the accept.
  `setting` is present only when the target was a `setting` ping.
- `state.log` is a list; each entry is exactly `{ senderId, kind, target,
  setting?, position = { x, y, z }, at, roomLit }` in accept order. `position`
  is value-equal to the argument. `roomLit` is the argument except `true` for
  every `doorway` ping.
- `shown(state)` is a list of exactly `{ senderId, kind, target, setting? }`
  sorted ascending by `senderId` (all test senderIds are lowercase ASCII, so
  `<` on strings is what is pinned). `shown(new()) == {}`.
- `tick` removes `now >= at + d`, keeps `now < at + d`, `d =
  tuning.channel.ping_display_seconds`.
- `onCommitted(state, m)` removes entries with `(kind == "setting" or kind ==
  "machine") and target == m`; doorway entries survive even when `target == m`.
- `accept`, `tick`, `onCommitted` return a table that is **not** `rawequal` to
  the input, and the input state (deep), the target and the position are
  unchanged afterwards. `shown` returns a list not `rawequal` to `state.active`
  and a different list on each call.
- `targetPosition`, `validate`, `request` keep their CHAN-005 signatures (C-9);
  the refusal check calls `request` and `targetPosition` as CHAN-005 defined
  them.

**Not constrained** (the implementer's choice): whether `accept` aliases or
copies the `target`/`position` tables (only non-mutation and value-equality of
the logged position are pinned); whether `tick`/`onCommitted` that change
nothing share `active`/`log` with the input (only "a new outer table" and
"input unchanged" are pinned); the sort of `shown` for mixed-case or non-ASCII
senderIds; what `tick` does with a tuning lacking `channel` (never driven);
internal helpers and the type names (the four `export type`s in the Contract
are not referenced by any test - Luau types are erased, so a test cannot pin
them; GREEN should still export them as the Contract says).

### Tests that passed on arrival, and what earns them

The controls file is green on arrival by design - it runs the checks against
stubs. What earns each check is the **negative control** that makes it fire
(table below) plus the **reference** it accepts, and the "empty module" baseline
that shows every check stops at `need()` naming the missing export. No test
against the real module passed on arrival.

### Negative controls - expected values, MEASURED in RED against the stubs

Every row is **measured** (`lune run test`, the `[measured]` lines printed by
`ping_lifecycle_controls_test.luau`), not predicted: the stubs need only
merged code. What is NOT yet measured is any of these checks against the
shipped module, because the real-module file stops at `need()`. **GREEN's job**
is to confirm that the shipped module (a) passes all ten checks and (b) under
D-1..D-4's mutations fails exactly the check named - the stub rows show the
checks can see those shapes; the mutation shows the real module has them.

| Control (stub defect) | Threshold / candidate range | Measured fire set (exactly) | Named case in the message |
|---|---|---|---|
| `reference` (positive control) | 0 of 10 checks fail | **0 of 10** | - |
| empty module `{ request }` | 10 of 10 fail at `need()` | **10 of 10**, every message contains `is nil, expected a function` | - |
| `appendsUnderDistinctKey` (AC-1's required control; **D-1's shape**) | AC-1 fails holding 2 | AC-1, AC-2, AC-3, AC-4 (every check that reads `active` by senderId); **not** C-2, it is pure | `the active set holds 2 ping(s), expected exactly 1` |
| `keyedByTarget` | AC-4 fails (two senders merged to 1) | AC-1, AC-2, AC-3, AC-4 | AC-4: `expected exactly 2` |
| `strictExpiry` (**D-2's shape**, `>=` -> `>`) | only AC-2, on the boundary | AC-2 only | `gone at exactly 10 + 15 = 25` and `gone at exactly 10 + 4 = 14` |
| `hardCodedDuration` (15 from `MechanicsTuning`, not the tuning passed) | only AC-2, only the substituted tuning | AC-2 only | `a substituted tuning (d = 4), gone at exactly 10 + 4 = 14`; the `d = 15` case does NOT appear |
| `tickTrimsTheLog` | AC-2 (log changed) + AC-5 | AC-2, AC-5 (log) | AC-5: `after a tick at 40 expired everything` |
| `commitIgnoresKind` (**D-3's shape**) | only AC-3, on the doorway | AC-3 only | `ann's doorway 1 (the same number, a doorway)`, `value.ann: expected` |
| `commitClearsOnlySettings` | only AC-3 | AC-3 only | `value.lee: unexpected` |
| `commitTrimsTheLog` | AC-3 (log changed) + AC-5 | AC-3, AC-5 (log) | AC-5: `after machine 2 commits` |
| `replacementTrimsTheLog` | AC-5 at the replacement step | AC-5 (log), AC-5 (refused; kim is accepted twice there) | `after kim REPLACES with a doorway ping`; `the log holds 2 entries, expected exactly 3` |
| `logsEveryAcceptTwice` | AC-5 on the count | AC-5 (log), AC-5 (refused) | `the log holds 2 entries, expected exactly 1`; `the log holds 6 entries, expected exactly 3` |
| `logOmitsRoomLit` | every log-shape check | AC-5 (log), AC-5 (doorway), AC-5 (refused) | `logged roomLit = nil` |
| `doorwayLogsRoomLitAsGiven` | AC-5 doorway + the sequence (it has a doorway with `false`) | AC-5 (doorway), AC-5 (log) | `a doorway ping accepted with roomLit = false logged roomLit = false, expected true` |
| `shownLeaksAt` (**D-4's shape**) | only AC-6 | AC-6 only | `value.1.at: unexpected 11` |
| `shownReturnsActiveEntries` | only AC-6 | AC-6 only | `.at: unexpected` |
| `shownUnsorted` (descending) | only AC-6 | AC-6 only | `value.1.senderId: expected "ann", got "zoe"` |
| `shownDropsSetting` | only AC-6 | AC-6 only | `value.3.setting: expected 1, got nil` |
| `acceptMutatesInPlace` | C-2 | C-2 only | `accept (a new sender) returned the state it was given`; `... mutated the state it was given` |
| `tickMutatesInput` | C-2 | C-2 only (AC-2 re-ticks an already-emptied state and expects empty anyway) | `tick (expiring everything) mutated the state it was given` |
| `commitMutatesInput` | C-2 (+ AC-3, which reuses one state for three commits) | C-2, AC-3 | `onCommitted (clearing two) mutated the state it was given` |
| `newIsASingleton` | only C-3 | C-3 only | `returned the same table twice` |
| `newCarriesACounter` | only C-3 | C-3 only | `value.count: unexpected 0` |

Five of these sets were first predicted wrongly and corrected to the
measurement in RED (the appends/keyed controls do not fire purity; the
replacement-trims control also fires the refused-request check; the two
mutating-accept/tick controls fire purity alone) - each correction is a
narrower, explicable set, and the test titles say why.

Settled number, read out: `MechanicsTuning.channel.ping_display_seconds = 15`;
`PingsContract.tuningWith({ ping_display_seconds = 4 })` reads 4 and leaves
`ping_range_studs` alone; `10 + 15 = 25` and `10 + 4 = 14` exact; `ε = 1e-6`
strictly inside both.

### `bash scripts/gates.sh --fast` - the shape of the red

Run on the uncommitted RED tree, 2026-10-05 (not recorded: a `--fast` run never is):

    --- gate summary ---
    PASS         format (0s, observed 176)
    PASS         lint (0s, observed 176, floor 1)
    PASS         typecheck (3s, observed 29)
    FAIL         unit (115s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 113649)
    FAIL         harness (14s, exit 1) -> .claude/state/gate-logs/harness.log

- `unit`: `1123 passed, 10 failed` - the ten rows above and nothing else. No
  timeout (the runner has none; the whole suite is 115 s under the gate, and
  the four new files add well under a second). No config error, no lint rule
  tripped.
- `harness`: `project-counters: 39 passed, 1 failed` - the one red line is the
  precondition "the working tree carries no stray .luau files", listing the
  four untracked test files. It clears at the RED commit; AC-7's counts
  (176/176/29, narrow 29/29/8) already pass on this tree, so the baselines set
  above are the measured values, not a prediction.
- format, lint, typecheck, build: green. The lint gate runs selene over the
  test files too (`selene over 176 files`), so the new files are admissible.

### Deferred verifications - declined in RED

**D-1, D-2, D-3 and D-4 are mutations of the real implementation, which in
RED does not exist. I did not run them and do not claim them.** They stay with
GATES as the story says. What RED did instead is show, per the table above,
that the check each one names is the one that fires on an implementation of
exactly that shape (`appendsUnderDistinctKey`, `strictExpiry`,
`commitIgnoresKind`, `shownLeaksAt`) - so when GATES runs
`bash scripts/mutate.sh src/server/channel/Pings.luau '...' -- lune run test`
the expected red is, respectively, the AC-1, AC-2, AC-3 and AC-6 tests of
`tests/server/ping_lifecycle_test.luau`, with the named case in the message.

### Callers of changed signatures - re-checked

    rg "Pings\.(new|accept|tick|onCommitted|shown)" src tests

re-run before writing a test: **no hits** (exit 1). After writing, the only
hits are the four new test files. No existing export's signature changes.

### Discovered along the way

- **The runner hangs when its stdout pipe closes early.** `lune run test | ...
  | head -N` left two idle `lune.exe` processes (0.3 s CPU after 15 min) that
  had to be killed; a second run started beside them was presumably contending
  with them. Run the suite into a file and grep the file. Not a story defect;
  noted so GREEN does not lose twenty minutes the same way.
- `need()` names `new` for every check because every check builds a state
  first. If GREEN adds the functions one at a time, the failure messages will
  walk through `accept`, `tick`, `onCommitted`, `shown` in that order.
- `Pings` is `table.freeze`d (CHAN-005). The new functions must be added to the
  table before the freeze, which is just "define them in the module" - but a
  test helper cannot monkey-patch the module, which is why nothing here tries.

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

**PO decisions at PLANNED → RED (lead-po, 2026-10-05).**

1. **Gate.** The artifact is `src/server/channel/Pings.luau`, read by the
   `unit` gate (`lune run test`), which is `required`. No optional gate is the
   only one exercising it, so `required_gates` stays empty.
2. **Epic done-when #6** ("at most one active ping; expires after
   `ping_display_seconds`; clears when its machine commits; replaced by the
   sender's next; every ping is logged") is covered by AC-1 – AC-5. No gap.
3. **Doorway `roomLit`** is enforced inside `accept` (C-4), not left to the
   caller, so the rule is testable here rather than only in `SLICE-006`.
4. **`shown` order** is by `senderId` (C-7) so the public payload is
   deterministic; the story said nothing and the map has no order.
5. **Dependency.** `phase.sh` first refused because local `main` was behind
   `origin/main`; CHAN-005 had already been merged (PR #57) and closed
   (`f637de1`). Fast-forwarded `main`; no `--force`.

