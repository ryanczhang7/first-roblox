---
id: CHAN-005
title: A ping is accepted only at a real target in range and in sight
slug: a-ping-is-accepted-only-at-a-real-target
epic: EPIC-06
type: feature
status: in-progress
phase: GREEN
branch: story/CHAN-005-a-ping-is-accepted-only-at-a-real-target
depends_on: [CHAN-003, PROC-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. The ping is the verb the game is about. It is the only way a
fact crosses from one head to another (`loop.md` §1.1; `mechanics.md` §4.1, G9).

- A ping targets exactly one of three things: a **dial setting** on a machine,
  a **machine**, or a **doorway**. There are no free-position pings.
- The client proposes a target and the server decides, because a target is a
  claim (B4).
- The target must exist, must not be a committed machine or a setting on one,
  must be within `ping_range_studs` of the sender (the server's accepted
  position), and must be in the sender's line of sight.
- The rate is `ping_rate_limit_seconds`: the stricter reading of CA-1, §0d #23.
- A ping refused for its target is **not a send**. It is not shown, the sender
  is told it did not land, and the cooldown is not consumed. Only
  `channel_attempt_min_interval_seconds` applies (G9, `CHAN-003`).

`RateLimitSpec` already reads `ping_rate_limit_seconds`. This story's provenance
test compares the `Ping` **declaration** against it, which was the loose end
ROUND-006 left for M3's channel story.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `GameRemotes.Ping`, when it is read from `Remotes.all()`,
  then:
  - its `rateLimit.minIntervalSeconds` equals the value `RateLimitSpec` reads
    for `ping_rate_limit_seconds` and is at least `FLOOR_SECONDS`;
  - its `attemptLimit` equals `channel_attempt_min_interval_seconds`;
  - its legal phases are exactly `{ "Round" }`.

  *Control:* a declaration at a literal 3 (the superseded placeholder) must
  fail, naming 3 and 10.
- **AC-2** — Given the guarded remote, when malformed (`kind = "floor"`, a
  missing `target`, `target = 0`, a string), out-of-phase (`Lobby`, `Post`) and
  flooded calls arrive, then each is rejected by the wrapper with the matching
  reason. That is B4's triple, in `tests/net/`.
- **AC-3** — Given a facility and accepted positions, when `Pings.validate` is
  called, then it accepts:
  - a machine or a setting on a machine that exists, is not committed, is
    within `ping_range_studs` (horizontal) and is in line of sight;
  - a doorway that exists, is within range of the doorway's midpoint and is in
    sight.

  It refuses with a distinct reason each of: `no_such_target`,
  `committed_machine`, `out_of_range`, `out_of_sight`, `setting_mismatch` (a
  `setting` kind with no setting, or a setting given for another kind) and
  `no_position` (a sender with no accepted sample).
  *Control:* a validator that measures range from a client-supplied position
  must fail a fixture in which the payload is crafted to be in range and the
  server's position is not. The payload's extra field is rejected at `shape`,
  so this fixture drives `validate` directly with a position argument the test
  controls.
- **AC-4** — Given `GameRemotes.Ping` guarded with a handler that passes each
  call to `Pings.request`, when the sender pings a refused target and then a
  valid target after the attempt floor has passed and well inside
  `ping_rate_limit_seconds`, then the second ping is accepted. The refusal
  declined the call, and `Pings.request` returned a `PingRefused` carrying the
  reason, which is the only payload it produces for that call (the caller sends
  it to the sender alone; `SLICE-006` wires that `SendTo`). An accepted ping
  returns `nil` and is not declined.
  *Control:* the same sequence with a handler that does not decline must be
  rejected for `rate`.
- **AC-5** — Given the line-of-sight port, when `validate` runs, then it calls
  the port once, from the sender's accepted position to the target's position,
  and a `false` refuses with `out_of_sight`. The port is never called for a
  target that already failed an earlier check.

## Contract

**Modules.**

`src/net/GameRemotes.luau` gains:

    GameRemotes.Ping: Remotes.RemoteDefinition
    -- args = Schema.shape({
    --     kind    = Schema.literal("setting", "machine", "doorway"),
    --     target  = Schema.integer(1, MechanicsTuning.instance.actuator_count),
    --     setting = Schema.optional(Schema.integer(1, MechanicsTuning.instance.dial_settings)),
    -- })
    -- legalPhases  = { "Round" }
    -- rateLimit    = { minIntervalSeconds = MechanicsTuning.channel.ping_rate_limit_seconds }
    -- attemptLimit = { minIntervalSeconds = MechanicsTuning.channel.channel_attempt_min_interval_seconds }

- `target`'s schema bound is `actuator_count` (16). A 3 × 3 grid has at most 12
  doorways, so every doorway id is inside it too. The handler checks that the
  target exists.

`src/server/channel/Pings.luau` is pure (PO-1, PO-3, 2026-10-04 - amended in
PLANNED from the signature first written here, which took `facility` and
`tuning` beside `procedure`; see `## Notes`):

    export type PingTarget = { kind: "setting" | "machine" | "doorway", target: number, setting: number? }
    export type Refusal = "no_such_target" | "committed_machine" | "out_of_range" | "out_of_sight"
                        | "setting_mismatch" | "no_position"
    export type PingRefused = { reason: Refusal }
    export type CallControl = { decline: () -> () }   -- structural; Wrapper.CallControl satisfies it

    Pings.validate(procedure: Procedure.ProcedureState, senderPosition: Procedure.Vec?,
                   target: PingTarget,
                   lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean)
        -> (boolean, Refusal?)
    Pings.targetPosition(procedure: Procedure.ProcedureState, target: PingTarget) -> Procedure.Vec?
    Pings.request(procedure: Procedure.ProcedureState?, positions: { [string]: Procedure.Vec },
                  senderId: string, target: PingTarget, call: CallControl,
                  lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean)
        -> PingRefused?

- **One source of facility and tuning.** Both are read from `procedure.facility`
  and `procedure.tuning`, as `Projection.lensFor` does. No parameter can
  disagree with the procedure.
- **Check order (`validate`), first failure wins:**
  1. `setting_mismatch`: `kind == "setting"` with `setting == nil`, or
     `kind ~= "setting"` with `setting ~= nil`;
  2. `no_such_target`: a machine/setting whose `target` matches no machine's
     `id` field in `facility.placement.machines` (ids are not dense: a facility
     may have fewer than `actuator_count` machines), or a doorway `target`
     outside `1..#layout.doors`;
  3. `committed_machine`: `procedure.committed[target] == true`, for `machine`
     and `setting` kinds only;
  4. `no_position`: `senderPosition == nil`;
  5. `out_of_range`: horizontal (x, z) distance from `senderPosition` to
     `targetPosition` **greater than** `tuning.channel.ping_range_studs`. The
     bound is inclusive, as `Procedure`'s `within` is: exactly 12 studs is in
     range;
  6. `out_of_sight`: `lineOfSight(senderPosition, targetPosition)` is false.
     Called at most once, and only when 1-5 passed (AC-5).
  Accepted: `(true, nil)`. Refused: `(false, reason)`.
- **Not checked, deliberately.** A dark room (`mechanics.md` §4.1: a helper may
  ping a setting in a blacked-out room) and whether the machine is live
  (`ping_settings_live_only = false`, T20). A test that a dark machine and a
  non-live machine are accepted is part of AC-3. `setting`'s range is the
  schema's (`1..dial_settings`), not `validate`'s.
- **Positions.** A machine or setting ping is at `Machines.positionOf(layout,
  machine, tuning)`. A doorway is the index of its `Door` in `layout.doors`.
  That list is sorted by `(a, b)` ascending; `GEN-001` guarantees the order.
  Its position is the midpoint of its two rooms' centres, where a room's centre
  is `{ x = (column - 1) * room_pitch_studs, y = 0, z = (row - 1) *
  room_pitch_studs }` (the formula `Session`'s spawn centre and
  `Machines.positionOf` use). `targetPosition` returns `nil` for any target
  that fails check 2; it does not look at `setting`.
- **`request` is the handler's core (PO-3).** It reads `positions[senderId]`
  as `senderPosition`. `procedure == nil` refuses `no_such_target`. On a
  refusal it calls `call.decline()` exactly once, before returning, and returns
  `{ reason = reason }` - a fresh table, nothing else in it. On acceptance it
  returns `nil` and never touches `call`. It does not record the ping:
  `CHAN-006` owns the active set and the log, `SLICE-006` wires both into
  `Session` as `PingRequested`, and `SLICE-007` builds the adapter from the
  guarded call. AC-4's handler is therefore the test's own two-line adapter -
  build `PingTarget` from the validated args, call `request` with a fixture
  procedure and positions - which is the shape `SLICE-007` will ship.
- **AC-2's reasons, pinned against `Schema`:** `kind = "floor"` -> `shape`
  (a literal mismatch is structural); a missing `target` -> `shape`;
  `target = 0` -> `range`; `target = 17` -> `range`; `setting = 5` -> `range`;
  the payload the string `"ping"` -> `shape`; `Lobby` and `Post` -> `phase`;
  a second call inside 1 s -> `rate`, and a second accepted call inside 10 s
  -> `rate`.

RED may amend any block in this section in place, with a one-line reason beside
it; GREEN builds what the amended block says.

**Callers of changed signatures.** None: no existing export changes. `Remotes`
and `Wrapper` are used as `CHAN-003` left them. `GameRemotes` gains a key, and
its readers were checked against the tree on 2026-10-04 (`rg -n "GameRemotes"
src tests` plus `ls tests/net tests/helpers`): `tests/net/turn_remote_test.luau`
and `tests/helpers/TurnRemoteContract.luau` find `Turn` **by name**, and every
`#Remotes.all()` count in `NetContract` and `PhaseContract` is relative
(`before + 1`), so a second declaration breaks none of them. No test declares a
remote named `"Ping"` (`rg '"Ping"' src tests`: no hits), so the registry's
duplicate check cannot fire. `src/server/channel/` does not exist yet. No
existing test passes a malformed value into a field this story makes live.
RED's handoff confirms this list against the tree.

**Oracle partition.**
- AC-1 is **settled**: read through `RateLimitSpec` and `MechanicsTuning`.
  The number is 10 (`ping_rate_limit_seconds`) and the attempt floor is 1.
- AC-2 to AC-5 are **mechanical**: exact reasons, exact call counts, exact
  arguments. AC-3's range boundary is pinned at exactly 12 (accepted) and
  12 + epsilon (refused).

## Deferred verifications

**D-1. The provenance test reads the declaration.** Use `scripts/mutate.sh` to
set `Ping`'s rate to a literal `3`. AC-1 **must** then fail. RED cannot run
this. Owner: GATES.

**D-2. Range is the server's and inclusive.** Use `scripts/mutate.sh` to turn
the range comparison strict (`<=` to `<`, or `>` to `>=`, whichever GREEN
wrote). AC-3's exactly-12 case **must** fail. Owner: GATES.

**D-3. The port is asked last.** Use `scripts/mutate.sh` to make `validate`
call `lineOfSight` before the range check. AC-5's call-count assertion **must**
fail. Owner: GATES.

**D-4. The refusal declines.** Use `scripts/mutate.sh` to remove the
`call.decline()` in `request`. AC-4 **must** fail for `rate`. Owner: GATES.

## Amendments

**AC-4, 2026-10-04, in PLANNED (Lead PO, PO-3).** It said: *"Given a refused
target through the guarded handler, ... The refusal declined the call. The
sender alone receives a private `PingRefused` with the reason."* It now names
the handler (`Pings.request` under the guarded `GameRemotes.Ping`) and says the
`PingRefused` is `request`'s return value, the only payload for that call, and
that an accepted ping returns `nil` undeclined. **Why:** no "guarded handler"
or send port existed for the old text to be tested against. `architecture.md`
§9.2/§9.7 route `PingRefused` through `Session` as a `SendTo`, and
`SLICE-006` (AC-3) is the story that wires `PingRequested` into `Session`.
Inventing a `sendTo` port here would build a second route that `SLICE-006`
then discards. The sender-only addressing is still tested, in `SLICE-006`.
Reported to the user before RED, so it can be overruled.

## Out of scope

- Active-ping lifecycle, expiry and the log (`CHAN-006`).
- The real raycast adapter (`SLICE-007`, with a Studio check that a wall blocks
  a ping and a doorway does not).
- Aiming and markers (`HUD-003`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-005` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/net/GameRemotes.luau` (source), `src/server/channel/Pings.luau` (source), `tests/helpers/TurnRemoteContract.luau` (test) (+1 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- PLANNED -> RED review - `lead-po` - `claude-opus-5-5` (orchestrating session's
  own identification). 2026-10-04.
- RED - `test-developer` - `claude-fable-5-1` (dispatched with `model: fable`
  explicitly; the agent identified itself as Fable 5.1). 2026-10-04.
- **RED verified by the orchestrator, 2026-10-04:** `lune run test` ->
  `1076 passed, 23 failed`; the 23 are exactly `tests/net/ping_remote_test.luau`
  x12 (`AC-1: Remotes.all() lists no definition named "Ping"`) and
  `tests/server/pings_test.luau` x11 (`src/server/channel/Pings.luau did not
  load`); no LOAD FAIL; both controls files green. `gates.sh --fast`: format,
  lint, typecheck, build PASS (171/171/28 observed); unit FAIL on those 23;
  harness FAIL only on the counter baselines pinned at GREEN's predicted
  172/172/29 (narrow 29/29/8) and the uncommitted-file precondition, as the
  counters file's history paragraph predicts. `git diff --stat -- src` empty.

## Test plan

RED, 2026-10-04. Every check is written once in a `tests/helpers/*Contract.luau`
over a parameter (a remote definition, or a `Pings` module), applied to the
real modules in a `*_test.luau` and to a reference plus one-defect
implementations in a `*_controls_test.luau` - the repository's pattern, because
in RED the real-module files fail before any assertion runs and the controls
files are where each check is observed to fire.

| File | Level | Covers |
|---|---|---|
| `tests/helpers/PingRemoteContract.luau` | checks over `(net, definition)` | AC-1 (5 checks), AC-2 (5 checks incl. positive control); `declare(net, label, edits)` builds the reference declaration with one edit |
| `tests/helpers/PingsContract.luau` | checks over a `Pings` module; one over `(net, definition, Pings)` | AC-3 (7 checks incl. the named control and `targetPosition`), AC-5 (2), AC-4 (2 on `request`, 1 through the guard); the hand-built fixture |
| `tests/helpers/PingsStubs.luau` | reference `Pings` + 17 one-defect variants | the negative controls, incl. D-2/D-3/D-4's shapes |
| `tests/net/ping_remote_test.luau` | integration: real `GameRemotes.Ping` through real `Wrapper.guard`; AC-4 over real `Pings.request` | 12 tests - AC-1, AC-2, AC-4, the export (red in RED) |
| `tests/net/ping_remote_controls_test.luau` | the AC-1/AC-2 checks against 14 declarations; the AC-4 guarded check against 4 `Pings` variants | 19 tests (green in RED - that is where the checks are observed) |
| `tests/server/pings_test.luau` | unit: real `Pings.validate` / `targetPosition` / `request` | 11 tests - AC-3, AC-4, AC-5 (red in RED) |
| `tests/server/pings_controls_test.luau` | the AC-3/4/5 checks against the reference and 17 defects; the fixture's numbers | 19 tests (green in RED) |

**Oracle partition honoured.** AC-1 reads: the rate is what `RateLimitSpec`
parses out of `tuning.md` for `ping_rate_limit_seconds` (10), compared against
`MechanicsTuning.channel.ping_rate_limit_seconds` and `FLOOR_SECONDS`; the
attempt floor is `channel_attempt_min_interval_seconds`; bounds are
`actuator_count` / `dial_settings`. Nothing in the suite writes 10, 1, 16 or 4
as an expectation (the controls' *fixtures* test pins that the document says
10 and the tuning says 1, so a drift is a fixture finding, not a quiet
re-tune). AC-2..AC-5 are exact: reasons by `==`, rate refusals told apart by
their WHOLE detail string, call counts, positions by value, the range boundary
at exactly 12 (accepted) and 12.01 (refused), with a second tuning (range 20)
to prove the number is read from `procedure.tuning`.

**Fixture** (`PingsContract.facility()`): rooms 1 (1,1), 2 (2,1), 3 (1,2) at
`room_pitch_studs` = 64; doors `{1,2}`, `{1,3}`; machines ids 1, 2, 5, 9 listed
as 2, 5, 1, 9 (non-dense, out of order). Positions, asserted by the controls:
machine 1 (-16,0,-16), 2 (16,0,16), 5 (48,0,-16), 9 (16,0,48); doorway 1
(32,0,0), doorway 2 (0,0,32). Machine 2 is committed by hand, room 3 is dark;
machine 9 is a finale machine (not live) in the dark room and is ACCEPTED (PO-5).
Absent ids 3, 4, 16 (inside the schema); absent doorways 3, 0, 12.

**Edges covered:** empty payload, nil, string payload, extra field, `false`
where optional nil belongs, case of a literal, non-integer, each bound +-1;
all four non-Round phases; attempt floor at 0.9 s (attempt detail) and exactly
1.0 s (send detail - the floor is inclusive); send limit at 1.1 s and 9 s
(refused) and exactly 10 s (accepted); doorway 0 and `#doors + 1`; a setting on
an absent / committed machine; two refusals applying at once for every adjacent
pair in the check order; `procedure == nil`; a sender missing from `positions`
while another player's position is present; `request` writing to neither
`positions` nor the target.

## Handoff: RED -> GREEN

RED, 2026-10-04. Model: dispatched as `test-developer`; the session reports
itself as **Fable 5.1 (`claude-fable-5-1`)** - the planned `fable` row. No
override was reported in the dispatch; the orchestrator records the resolved
name.

### Command

    lune run test

(the `unit` gate's own command; ~9.5 min here plain, 1038 tests before this
story). Run from the repo root with `~/.rokit/bin` on PATH. Never run two
test or gate runs at once (the typecheck gate miscounts on a transient
fixture).

### Current failure, verbatim

Before this story's files: `1038 passed, 0 failed`. With them, on the
uncommitted RED tree: **`1076 passed, 23 failed`** (1099 discovered) - all 23 in the two
real-module files, every pre-existing test and all 38 controls green. The 23,
each the RIGHT failure (no LOAD FAIL anywhere; each criterion fails on its own
line naming what is missing):

    FAIL  tests/net/ping_remote_test.luau :: Contract: GameRemotes exports Ping, ...
        tests/net/ping_remote_test:64: AC-1: Remotes.all() lists no definition named "Ping"
    FAIL  tests/net/ping_remote_test.luau :: AC-1: Ping's schema answers as { kind = literal(...), ... }
        ... AC-1: Remotes.all() lists no definition named "Ping"
    (same line for the other 3 AC-1 tests, the 5 AC-2 tests and the AC-4 test - 12 in the file)

    FAIL  tests/server/pings_test.luau :: AC-3: validate accepts a machine, a setting on it and a doorway ...
        tests/server/pings_test:39: src/server/channel/Pings.luau did not load: error requiring
        module "../../src/server/channel/Pings": could not resolve child component "channel"
    (same line for all 11 tests in the file: 7 AC-3, 2 AC-5, 2 AC-4)

Why these are right: `GameRemotes.luau` LOADS (it exists since PROC-005) but
lists no `"Ping"`, so AC-1/AC-2/AC-4 fail at the by-name lookup - the first
thing GREEN must add; `src/server/channel/` does not exist, so every
`Pings` test fails at the module, named. Not one assertion against a real
module has executed; see the controls table for what HAS been observed.

`bash scripts/gates.sh --fast` on the same tree (test files formatted; stylua,
selene and luau-lsp clean on all seven new files):

    PASS         format (1s, observed 171)
    PASS         lint (1s, observed 171, floor 1)
    PASS         typecheck (4s, observed 28)
    FAIL         unit (202s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 109401)
    FAIL         harness (34s, exit 1) -> .claude/state/gate-logs/harness.log

`unit`: `1076 passed, 23 failed` - the 12 + 11 above and nothing else.
`harness`: `project-counters: 28 passed, 12 failed`, exactly the red the
counters paragraph predicts for RED's uncommitted tree: the "no stray .luau
files" precondition (clears at the RED commit), and the baselines set to
GREEN's values - `expected count: 172 / actual count: 171` for format and
lint (three cases each), `29 / 28` for typecheck and both narrow src cases,
`173 / 172` and `30 / 29` for the untracked-file cases. The one source file
GREEN adds closes all of them. No gate failed on a timeout, a config error or
a lint rule.

### Files touched

- `tests/helpers/PingRemoteContract.luau` (new) - AC-1 and AC-2 checks over
  `(net, definition)`; `declare()`; `CHECKS`/`failures()`.
- `tests/helpers/PingsContract.luau` (new) - AC-3/AC-4/AC-5 checks over a
  `Pings` module; the fixture; the guarded AC-4 check over `(net, definition, Pings)`.
- `tests/helpers/PingsStubs.luau` (new) - reference `Pings` + 17 one-defect variants.
- `tests/net/ping_remote_test.luau` (new) - 12 tests: the export, AC-1 (5), AC-2 (5), AC-4 (1). RED.
- `tests/net/ping_remote_controls_test.luau` (new) - 19 control tests. Green.
- `tests/server/pings_test.luau` (new) - 11 tests: AC-3 (7), AC-5 (2), AC-4 (2). RED.
- `tests/server/pings_controls_test.luau` (new) - 19 control tests. Green.
- `.claude/tests/project-counters.test.sh` - baselines set to the PREDICTED
  post-GREEN values `172/172/29`, narrow `29/29/8` (164 + 7 tests measured on
  this tree = 171; + GREEN's one source file `src/server/channel/Pings.luau`),
  with the history paragraph. **Must land in the RED commit** (check-boundaries
  3j refuses a `.claude/tests/**` change from any other phase). GREEN confirms,
  never edits; a second new source file is a counter failure GREEN cannot fix.
- `docs/backlog/stories/CHAN-005.md` - `## Test plan`, this section. **No
  Contract block was amended** and no acceptance criterion changed.
- No existing test file edited. No source, no config, no manifest.

**Callers paragraph confirmed against the tree** (2026-10-04, before writing):
`rg -n "GameRemotes" src tests` - only `tests/net/turn_remote_test.luau`,
`turn_remote_controls_test.luau` and `tests/helpers/TurnRemoteContract.luau`,
all finding `Turn` by name; `rg '"Ping"' src tests` - no hits (so the
registry's duplicate check cannot fire, and the new tests never declare
`"Ping"` either - `declare()` uses `NetContract.uniqueName`);
`ls tests/net tests/helpers` - no `ping*`/`Pings*` existed; `src/server/channel/`
absent (the load error confirms it). `#Remotes.all()` counts in `NetContract`
and `PhaseContract` are relative, so a second declaration breaks none of them
(the full run confirms: 0 pre-existing failures).

### Export shape the tests already pin (fact, not suggestion)

`src/net/GameRemotes.luau` - the module keeps returning a table; it gains
`Ping` = the value `Remotes.define("Ping", spec)` returns (tests find it in
`Remotes.all()` by `name == "Ping"` and assert `rawequal(GameRemotes.Ping, listed)`).
`spec` must answer, through `args.validate`, exactly as
`Schema.shape({ kind = Schema.literal("setting", "machine", "doorway"),
target = Schema.integer(1, MechanicsTuning.instance.actuator_count),
setting = Schema.optional(Schema.integer(1, MechanicsTuning.instance.dial_settings)) })`
does (the schema is checked by behaviour, 24 cases, never by structure);
`legalPhases` deep-equal `{ "Round" }`; `rateLimit.minIntervalSeconds ==
MechanicsTuning.channel.ping_rate_limit_seconds` (and == the `tuning.md` row,
>= 10); `attemptLimit.minIntervalSeconds ==
MechanicsTuning.channel.channel_attempt_min_interval_seconds`. Rate details
are the strings CHAN-003 fixed (`"<name>" is limited to one attempt per 1 s per
player` / `one call per 10 s per player`) - the wrapper writes them; nothing
to do in `GameRemotes`.

`src/server/channel/Pings.luau` (new) - returns a table with three functions,
called as plain fields (`Pings.validate(...)`, no `self`):

- `Pings.validate(procedure, senderPosition: Vec?, target: PingTarget,
  lineOfSight: (Vec, Vec) -> boolean) -> (boolean, Refusal?)`. Accepted is
  exactly `(true, nil)`; refused `(false, "<reason>")` with the Contract's six
  strings. `target` is `{ kind, target, setting? }`; the tests ALSO hand in a
  target carrying an extra `position` field and require it to be ignored
  (AC-3's control), so do not iterate the target's keys. Check order exactly
  the Contract's 1-6; the tests drive every adjacent pair with both failures
  present. Range: horizontal `(x, z)`, `<=` `procedure.tuning.channel.ping_range_studs`
  (exactly 12 accepted, 12.01 refused, `y` differences of 500 ignored), read
  from `procedure.tuning` (a fixture tuning with 20 is driven). `lineOfSight`
  is called at most once, only after 1-5 pass, as `lineOfSight(senderPosition,
  targetPosition)` - compared by VALUE (`x`, `y`, `z`), so passing the very
  table from `Machines.positionOf` or a copy are both fine. `validate` must
  not raise for doorway id 0, a doorway id > `#layout.doors`, or an absent
  machine id (a raise is a counted violation).
- `Pings.targetPosition(procedure, target) -> Vec?`. Machine/setting: deep-equal
  to `Machines.positionOf(procedure.facility.layout, machine, procedure.tuning)`,
  where `machine` is found by its `id` FIELD (the fixture lists ids 2, 5, 1, 9
  in that order - `machines[target]` indexing is caught). Doorway: `{ x, y = 0, z }`
  = midpoint of the two rooms' centres, centre = `((column - 1) * pitch, 0,
  (row - 1) * pitch)`; `y` must be exactly `0`. Absent anything: `nil`, no raise.
  Ignores `setting` (a `setting` kind with `setting = nil` still answers).
- `Pings.request(procedure?, positions: { [string]: Vec }, senderId: string,
  target, call: { decline: () -> () }, lineOfSight) -> PingRefused?`. Refusal:
  `call.decline()` exactly once, return a table that `Deep.equal`s
  `{ reason = "<reason>" }` - one key, nothing else. `procedure == nil` ->
  `no_such_target` (declined once, no raise). `positions[senderId] == nil` ->
  `no_position`. Acceptance: return `nil`, never call `decline`, and leave
  `positions` and `target` deep-equal to what they were. The tests pass a
  bare `{ decline = function() ... end }` as `call`, so read nothing else off it.

`Procedure.start(facility, now, tuning, roundSeed, roundSeconds)` is used as
PROC-001 left it; `committed` and `dark` are written on the state directly.

**Not constrained** (implementer's choice): the exported Luau types' names
(tests use `any`); how `validate` is decomposed; whether `request` calls
`validate` or re-implements it; what happens for a `kind` outside the three
literals, a negative doorway id, or a non-table `target` (never driven -
the schema stops them on the wire); what `decline()` returns; comments,
`table.freeze`, and the module's header. `GameRemotes`' layout beyond
exporting `Ping` beside `Turn`.

### Tests that passed on arrival, and what earns them

The 38 control tests (both `*_controls_test.luau`) are green in RED by
design: they run the checks against a reference and one-defect stubs that need
no production code. They are earned by the baselines (reference fails 0 of 10
and 0 of 11 checks) plus every control firing EXACTLY its predicted set -
every predicted set matched on the first run, with no expectation adjusted to
a measurement. No real-module test passed on arrival.

### Negative controls - expected and measured (RED, outside the real module)

Measured by running each controls file through the real `Wrapper`/`Remotes`/
`Schema` (declarations) and `PingsStubs` (modules). The sets are pinned exactly
by the controls tests, so the "measured" column IS what the suite asserts.
**GREEN's job: confirm the two real-module files go green with these controls
still green, and that D-1..D-4's mutations against the shipped module fire the
same checks the stub shapes fire here.**

| Control (one defect) | Threshold / what must fire | Measured in RED |
|---|---|---|
| **`rateLiteral3`** (AC-1 named; D-1's shape) | rate check, message names 3 and 10 | fires `rateLimitIsThePingRateLimitTheDocumentFixes` with `Ping.rateLimit is { minIntervalSeconds = 3 }` ... `expected { minIntervalSeconds = 10 }` ... `below RateLimitSpec.FLOOR_SECONDS = 10`; also both rate sequences (details quote 3; the 9 s call is accepted) |
| `rateLimitPlusOne` (11) | rate check without the floor clause; the t + 10 call refused | fires the same 3; message has no "below ... FLOOR" |
| `noRateLimit` | rate check + both sequences | fires the same 3 |
| `noAttemptLimit` | attempt check + attempt sequence (0.9 s call gets the SEND detail) | fires exactly `attemptLimitIsTheChannelAttemptFloorFromTuning`, `secondCallInsideTheAttemptFloorIsRejectedForRate` |
| `attemptPlusOne` (2) | attempt check + both sequences | fires exactly those 3 |
| `legalInLobbyToo` | phases + out-of-phase | exactly 2 |
| `targetUpperBoundPlusOne` (17), `targetIsNumber` (1.5), `kindsIncludeFloor`, `acceptsPosition` | schema + malformed | exactly 2 each |
| `settingRequired` | schema + every check sending a ping without a setting | exactly 6: schema, malformed, out-of-phase, both rate sequences, positive |
| `emptySchema` | everything but phases/rate/attempt/listed | exactly the same 6 |
| `unregisteredCopy` | registry only | exactly `isTheDefinitionRemotesAllLists` |
| reference declaration | nothing | 0 of 10 |
| **`clientPosition`** (AC-3 named) | server-position check: `(true, nil), expected (false, "out_of_range")` | fires exactly `rangeIsMeasuredFromTheServersPositionNotAPayloadField` |
| **`strictRange`** (D-2's shape) | boundary: "exactly 12 along +x" refused | fires exactly `rangeIsHorizontalAndInclusiveAtPingRangeStuds`, `rangeIsReadFromTheProceduresTuning` |
| `verticalRange` | the y = +-500 and y = -64 cases | fires exactly accepts, boundary, tuning-range |
| `moduleRange` | 20-stud tuning: 20 refused, 12.5 refused | fires exactly `rangeIsReadFromTheProceduresTuning` |
| **`sightBeforeRange`** (D-3's shape) | never-asked: `lineOfSight was called 1 time(s)` on out_of_range targets; order: out_of_sight beat out_of_range | fires exactly `firstFailureWinsInTheContractsOrder`, `lineOfSightIsNeverAskedForATargetFailingAnEarlierCheck` |
| `sightFirst` | same two | exactly those 2 |
| `ignoresCommitted`, `settingUnchecked` | refusals, order, never-asked, request-refusal | exactly 4 each |
| `committedBeforeExistence`, `positionBeforeCommitted` | order only | exactly `firstFailureWinsInTheContractsOrder` |
| `denseIds` | everything that touches a machine | all 11 module checks |
| `doorwayZeroIsDoorOne` | refusals, targetPosition ("absent doorway 0"), request-refusal | exactly 3 |
| `doorwayAtRoomA` | `doorway 1 -> { x = 0, y = 0, z = 0 }, expected { x = 32, y = 0, z = 0 }` | exactly 8: accepts, refuses, boundary, server-position, targetPosition, los-once, both request checks |
| **`noDecline`** (AC-4 named; D-4's shape), module level | `call.decline() was called 0 time(s), expected exactly once` | fires exactly `requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal` |
| **`noDecline`**, through the real guard over a reference declaration | second call `rate` | measured: `the refused ping at t -> the guard answered nil, expected { detail = ""<name>" declined the call", reason = "declined" }`; `the valid ping at t + 1.1 ... -> the guard answered { detail = ""<name>" is limited to one call per 10 s per player", reason = "rate" }, expected nil (accepted)`; handler ran 1, expected 2 |
| `declinesOnAccept` | request-acceptance; through the guard the valid ping is `declined` | exactly `requestAcceptsWithoutDeclining`; guard message carries `reason = "declined" }, expected nil (accepted)` |
| `refusalWithDetail` | request-refusal (`expected exactly { reason =`); guard: `request` returned a detail | exactly `requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal`; guard fires on the return value |
| `nilProcedureRaises` | `procedure == nil -> request RAISED` | exactly `requestDeclinesOnceAndReturnsExactlyTheReasonOnARefusal` |
| reference `Pings` | nothing | 0 of 11; AC-4 guarded sequence passes |
| fixture | positions as documented; document 10 == module 10, floor 10, attempt 1, EPSILON 0.1 | all confirmed |

### Deferred verifications - declined by RED, in writing

**D-1, D-2, D-3 and D-4 are each a mutation of the real module, which does
not exist in RED, so RED cannot run them and did not.** They stay with GATES
as the story says. What RED did instead is build each mutation's SHAPE as a
stub (`rateLiteral3`, `strictRange`, `sightBeforeRange`, `noDecline`) and show
the check that will judge the real mutation fires on the shape - the table
above. GATES runs the four through `scripts/mutate.sh` and pastes the red; the
expected failing tests are: D-1 -> `ping_remote_test` AC-1 rate test (message
naming 3 and 10); D-2 -> `pings_test` "range is horizontal and inclusive" (and
the 20-stud tuning test); D-3 -> `pings_test` AC-5 "never called for a target
that fails an earlier check" (and the order test); D-4 -> `ping_remote_test`
AC-4 (`rate` on the second ping) and `pings_test` AC-4 "decline exactly once".

### Discovered along the way

- The `checksRun...` claim "the handler never ran" for AC-2 is a count over a
  recorder that also captures the third argument; the positive control pins
  that `Ping`'s handler receives a `CallControl` (CHAN-003), which is what the
  `SLICE-007` adapter will hand to `request`.
- The attempt floor records a REFUSED-by-send call (CHAN-003 Return 1), so the
  send-limit sequence places its third call a full attempt floor before the
  fourth (9 s, then 10 s). A GREEN that changes nothing in `Wrapper` satisfies
  it; do not touch the wrapper for this story.
- `luau-lsp analyze` over the new test files is clean. The pre-existing
  helpers `NetContract.luau(626)` and `TurnRemoteContract.luau(642)` report
  errors under the same command; they are not this story's.
- Timing: the full suite took ~9.5 min plain on this machine before this
  story (1038 tests) and 191 s under `gates.sh --fast` after it (1099 tests) -
  the difference is machine load, not the suite; the new files add well under
  a second. No test here owns a timeout.
- This worktree arrived without the generated, gitignored `globalTypes.d.luau`
  (`task install` fetches it), so the first `gates.sh --fast` failed
  `typecheck` with no analyzer output and the harness counters' typecheck
  cases matched no evidence. Copied from the main checkout (806997 bytes, the
  size `environment.md` records for luau-lsp 1.69.0); not a code change. A
  fresh worktree for GREEN needs the same, or `bash scripts/task.sh install`.

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

**PLANNED -> RED review, 2026-10-04 (Lead PO).**

- **Gate.** `unit` (required) covers `src/server/**` and `src/net/**`, which is
  everything this story writes. No optional gate is the only witness, so
  `required_gates` stays empty.
- **Epic.** EPIC-06 done-when 5 is exactly AC-1 (declared rate proven against
  `tuning.md`) plus AC-3/AC-5 (exists, kind, range, sight, server position). No
  gap between CHAN-003 and this story.
- **PO-1. One source for facility and tuning.** `validate` and
  `targetPosition` drop their `facility` and `tuning` parameters and read
  `procedure.facility` / `procedure.tuning`, as `Projection.lensFor` does.
  Two parameters that could disagree with the procedure were a trap with no
  use.
- **PO-2. Check order pinned** (Contract). AC-5 ("never called for a target
  that already failed an earlier check") needs an order to mean anything.
- **PO-3. `Pings.request` is the handler core; AC-4 amended** (see
  `## Amendments`).
- **PO-4. AC-2's reason per payload pinned against `Schema`.** "The matching
  reason" left `target = 0` ambiguous between `shape` and `range`; it is
  `range`.
- **PO-5. Dark and non-live targets are accepted** (`mechanics.md` §4.1 edge
  cases; T20). Pinned so that GREEN does not borrow `lensFor`'s dark check.
- **Session.** Nothing in this story's proofs depends on `Session`: AC-4 is
  proven through `Wrapper.guard` with the test's own adapter. `Session` gains
  pings in `SLICE-006`.

**GREEN, 2026-10-05 (Feature Developer, `claude-opus-5-5`, no override reported).**

- **Files.** `src/net/GameRemotes.luau` gains `Ping` beside `Turn`, the
  Contract's block verbatim; every number read from `MechanicsTuning`
  (`instance.actuator_count`, `instance.dial_settings`,
  `channel.ping_rate_limit_seconds`, `channel.channel_attempt_min_interval_seconds`),
  header extended. `src/server/channel/Pings.luau` is the one new source file
  (counters 172/172/29 hold). No test, wrapper or other source touched.
- **Shape.** `validate` runs the Contract's checks 1-6 in order; check 2 is
  `targetPosition(...) == nil`, so existence and position share one lookup.
  Machines are found by their `id` field; doorways by indexing `layout.doors`
  (never searched, so 0 and `> #doors` are `nil` without a raise); a door
  naming a room absent from the layout is also `nil` (not driven). Range is
  `horizontalDistance(...) > range` on its own line (D-2 flips that `>`);
  `lineOfSight` is called on its own line after it (D-3). `request` declines
  through a two-line `refuse` helper whose `call.decline()` is its own line
  (D-4 deletes it; it covers both refusal paths, including `procedure == nil`).
  No dark or live check (PO-5). `Pings` requires `Procedure` for types only
  and imports nothing from `net`.
- **Controls measured against the shipped module** (scratch `lune` script under
  the gitignored `build/`, deleted after): machine 1 at (-16,0,-16), 2 at
  (16,0,16), 5 at (48,0,-16), 9 at (16,0,48); doorway 1 (32,0,0), doorway 2
  (0,0,32); doorways 0, 3, 12 -> `nil`; exactly 12 along +x -> `(true, nil)`,
  12.01 -> `(false, "out_of_range")`, 12 along +z at y + 500 -> accepted;
  `lineOfSight` called once with (sender, machine position) on acceptance, 0
  times on an out-of-range target, `false` -> `out_of_sight`; `request`
  refused -> `{ reason = "out_of_range" }`, declined 1; `procedure == nil` ->
  `{ reason = "no_such_target" }`, declined 1; accepted -> `nil`, declined 0;
  `Ping` rate 10, attempt 1, phases `Round`. All equal RED's table; no divergence.
- **Run.** `lune run test`: `1099 passed, 0 failed`.

**GREEN verified by the orchestrator, 2026-10-05.** `feature-developer`
resolved to `claude-opus-5-5` (dispatched with `model: opus`). `lune run test`
-> `1099 passed, 0 failed`. `bash scripts/frozen.sh verify` -> `frozen: OK — 164
path(s) unchanged since the snapshot for CHAN-005` (every tracked file under
`tests/` and `.claude/tests/`). Source changed: `src/net/GameRemotes.luau`
(in place) and `src/server/channel/Pings.luau` (new), nothing else. The
"suite discriminates" mutations are D-2..D-4, run in GATES against the
predicted fire-sets in the handoff's control table.
