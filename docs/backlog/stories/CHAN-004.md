---
id: CHAN-004
title: A preset is filtered and broadcast with its sender and position once per ten seconds
slug: a-preset-is-filtered-and-broadcast-with
epic: EPIC-06
type: feature
status: in-progress
phase: RED
branch: story/CHAN-004-a-preset-is-filtered-and-broadcast-with
depends_on: [CHAN-001, CHAN-002, CHAN-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. `mechanics.md` §4.2 sets the rules for a preset:

- It is broadcast to every player and never addressed. The remote carries no
  recipient (C9).
- It is attributed by name and **positioned**: a bubble over the sender and a
  beacon at their position. This is derived from "each preset must stand alone
  and be complete".
- A player may send one preset per `preset_rate_limit_seconds`, **across the
  whole wheel** (C4).
- It is legal only in the phases its row lists.
- It is filtered with `FilterStringAsync` and **fails closed** (C5).
- It is logged for the trace.

The G9 revision adds that a preset refused by its own phase list, or by its
filter, is **not a send**. The handler declines it and the cooldown is not
consumed. `CHAN-003` built that mechanism.

A rate-limit loose end from ROUND-006 lands here too.
`tests/helpers/RateLimitSpec.luau` already reads `preset_rate_limit_seconds`
from `tuning.md`, and this story's provenance test compares the
**declaration** against that row. The declaration is the `rateLimit` the real
remote is declared with.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `src/net/GameRemotes.luau`, when `SendPreset`'s declaration is
  read from `Remotes.all()`, then its `rateLimit.minIntervalSeconds` equals the
  value `RateLimitSpec` reads for `preset_rate_limit_seconds`, and that value is
  at least `RateLimitSpec.FLOOR_SECONDS`. Its `attemptLimit.minIntervalSeconds`
  equals `MechanicsTuning.channel.channel_attempt_min_interval_seconds`.
  *Control:* a declaration at 9.5 must fail, naming both numbers.
- **AC-2** — Given `SendPreset`'s schema, when it validates a payload, then it
  accepts exactly `{ preset = n }` for integer `n` in `1..preset_count`. It
  rejects any other key with `shape`, including a `to`, `target` or `player`
  field. It also rejects `0`, `preset_count + 1` and `1.5`. The wire therefore
  cannot carry a recipient (C9).
- **AC-3** — Given `SendPreset`'s `legalPhases`, when it is read, then it is
  exactly the union of the phases in `Presets.ALL`. A call made through the
  guarded remote during `Assignment` or `Resolution` is rejected by the
  wrapper for `phase`. That completes B4's adversarial triple (malformed,
  out-of-phase, flooded) in `tests/net/` for this remote, together with AC-2
  and AC-7.
- **AC-4** — Given a preset whose own phases exclude the current phase (for
  example `Well played` during `Round`), when it is sent through the guarded
  handler, then nothing is shown, the log is unchanged, the call is declined,
  and a `PresetFailed` with reason `phase_for_preset` is addressed to the sender
  only. The same player can then send a legal preset once the attempt floor has
  passed.
- **AC-5** — Given a legal preset and a filter port that succeeds, when it is
  sent, then the result is a `PresetShown` carrying exactly
  `{ senderId, presetId, position, text }`, where `text` is the filter's output.
  `{ senderId, presetId, position, at }` is appended to the log.
- **AC-6** — Given a legal preset and a filter port that **fails** (returns
  false, or raises), when it is sent, then nothing is shown, nothing is logged,
  the call is declined, and a `PresetFailed` with reason `filter` goes to the
  sender only (fail closed, C5).
- **AC-7** — Given two players, when each sends a preset within the same 10 s,
  then both are shown. When one player sends two *different* presets 5 s apart,
  both legal and both filtered successfully, then the second is rejected by the
  wrapper's `rate` stage. There is one send limit per player across the wheel,
  not one per preset.
  *Control:* a declaration keyed per preset (ten limiters) must fail this AC.

## Contract

**Modules.**

`src/net/GameRemotes.luau` declares the game's remotes at load, through
`Remotes.define`, and returns their definitions by name. This story declares
`SendPreset`. `CHAN-005` adds `Ping`, and `PROC-005` adds `Turn`.

    GameRemotes.SendPreset: Remotes.RemoteDefinition
    -- args         = Schema.shape({ preset = Schema.integer(1, MechanicsTuning.channel.preset_count) })
    -- legalPhases  = the union of Presets.ALL[*].phases, in Lobby, Round, Post order
    -- rateLimit    = { minIntervalSeconds = MechanicsTuning.channel.preset_rate_limit_seconds }
    -- attemptLimit = { minIntervalSeconds = MechanicsTuning.channel.channel_attempt_min_interval_seconds }

`src/server/channel/PresetSends.luau` is pure:

    export type Position = { x: number, y: number, z: number }
    export type PresetShown = { senderId: string, presetId: number, position: Position, text: string }
    export type PresetFailed = { presetId: number, reason: "phase_for_preset" | "filter" }
    export type PresetLogEntry = { senderId: string, presetId: number, position: Position, at: number }
    export type PresetState = { log: { PresetLogEntry } }
    export type Filter = (senderId: string, text: string) -> (boolean, string?)
    export type SendResult = { kind: "shown", shown: PresetShown } | { kind: "failed", failed: PresetFailed }

    PresetSends.new() -> PresetState
    PresetSends.send(state, senderId: string, presetId: number, phase: string, position: Position,
                     now: number, filter: Filter, call: Wrapper.CallControl) -> (PresetState, SendResult)

- `send` calls `call.decline()` on every `failed` result, and on no other.
- `filter` is called under `pcall`. A raise is a failure, never an error on the
  server thread.
- `position` is the server's accepted sample (`architecture.md` §9.8), passed in
  by the session. This module never reads a client-supplied position.
- **Amended from `CHAN-001` (2026-10-05; `architecture.md` §9.5.1).** The
  `Filter` type above stands. `filter` is called **exactly once per `send`
  that reaches it** — never cached per sender or per session: the API reference
  says `FilterStringAsync` "should be called once each time a user submits a
  message". It is not called for a preset refused for its phase (that refusal
  comes first). `PresetShown.text` is the string the filter **returned**, which
  may differ from the table's word (a hashed result is shown as returned);
  `send` never substitutes the table's word. `(false, _)` and a raise are both
  `failed` with reason `"filter"`, shown to no one. The real adapter
  (`src/server/ports/`, built with the session in `SLICE-006`, not here) is
  `TextService:FilterStringAsync(text, UserId, Enum.TextFilterContext.PublicChat)`
  then `:GetNonChatStringForBroadcastAsync()`, both yielding, both under
  `pcall`, never retried; this story tests only the port's contract through a
  stand-in function.
- `Schema.shape` already rejects unknown keys as `shape` (NET-001). Confirm this
  with a test rather than assuming it, and amend this block if it does not.

**Wiring** into `Session` is `SLICE-006`, not this story.

### Pinned at PLANNED -> RED (lead-po, 2026-10-06)

**RED may amend any block in this section, in place, with a reason; GREEN
builds what the amended block says.**

**C-1. `GameRemotes.luau` already exists.** `PROC-005` created it with `Turn`
and `CHAN-005` added `Ping`, both before this story. This story **adds**
`SendPreset` to it and to its returned table, beside `Turn` and `Ping`. It
changes neither of them. The `Ping` declaration is the template: same shape,
same `attemptLimit`, and tuning read through `@shared/MechanicsTuning`, never a
literal.

**C-2. `legalPhases` is `{ "Lobby", "Round", "Post" }`, derived, not written.**
The union of `Presets.ALL[*].phases` today is exactly those three. GREEN may
compute it from `Presets` (`net` may import `@shared`) or write the literal. The
**test** derives the expected list from `Presets.ALL`, ordered by the phase
machine's order (`Lobby`, `Assignment`, `Round`, `Resolution`, `Post`) with
absent phases dropped, so a preset table change re-reds it either way.

**C-3. `CallControl` is structural, like `Pings`.** `src/server/` has no
`@net` alias yet (`architecture.md` §1, D21), and `Pings.luau` declares
`export type CallControl = { decline: () -> () }` locally for that reason.
`PresetSends` does the same, so the Contract signature's `Wrapper.CallControl`
reads as `PresetSends.CallControl`. `Wrapper.CallControl` satisfies it.

**C-4. What `send` filters, in what order.**

1. `local preset = Presets.byId(presetId)`. An unknown id is a precondition
   violation: the schema bounds it to `1..preset_count`. `send` may raise; no
   AC tests it.
2. If `phase` is not in `preset.phases`, decline and return
   `{ kind = "failed", failed = { presetId = presetId, reason = "phase_for_preset" } }`.
   The filter is **not called**.
3. `local ok, okFiltered, text = pcall(filter, senderId, preset.word)`. The
   filter is called **exactly once**, with the sender's id and the table's
   `word`. It is a failure if `ok` is false (a raise), if `okFiltered` is not
   `true`, or if `text` is not a string. Then decline and return
   `failed` with reason `"filter"`.
4. Otherwise return `{ kind = "shown", shown = { senderId, presetId, position, text } }`,
   where `text` is the filter's **returned** string, and append
   `{ senderId, presetId, position, at = now }` to the log.

**C-5. State is immutable, as in `Pings`.** `send` never mutates the `state`
it is given. A `shown` result returns a **new** state whose log is the old log
plus one entry. A `failed` result returns a state whose log equals the old one
by value; identity is unconstrained. `position` in both `PresetShown` and the
log entry is a **fresh** `{ x, y, z }` copy, not the caller's table. That
matches `Pings.accept`, and mutating the caller's position afterwards must not
change either. `PresetShown` and `PresetFailed` carry **exactly** the listed
keys and no others.

**C-6. "Addressed to the sender only" (AC-4, AC-6) means the return value, in
this story.** `PresetSends` is pure and has no transport. A `failed` result is
the value the handler returns to its caller. Nothing about it reaches the log
or the shown set, and there is no broadcast form of it. The transport that
`sendTo`s it to the sender is `SLICE-006`'s. The tests pin: the result is
`failed`, the log is unchanged, and no `shown` exists.

**C-7. AC-4's second half, and AC-7, run through the real guard.** They
compose `Wrapper.guard(GameRemotes.SendPreset, ctx, handler)` with a handler
that calls `PresetSends.send` and passes on the `CallControl`. That is the
arrangement `ping_remote_test.luau`'s AC-4 uses, with
`RateContract.world`-style context and `Clock.manual`, every check on its own
guard. AC-4: after a `phase_for_preset` decline at `t`, a legal preset at
`t + channel_attempt_min_interval_seconds` (inside the 10 s) **reaches the
handler** and is shown. AC-7: two players in the same 10 s are both shown, and
one player's two **different** presets 5 s apart give the second a wrapper
rejection with reason `rate` and the **send** detail
(`DeclineContract.sendDetail`); the handler count stays 1.
*AC-7's control* (ten limiters) is ten definitions, one per preset id, each
with its own guard. A dispatcher that routes preset `n` to guard `n` must fail
AC-7's check, because the 5 s second send then reaches its handler.

**C-8. The filter stand-in.** Tests use plain functions: one that echoes, one
that returns a **different** string (for example `"####"`, to prove `text` is
the returned string, not the word), one returning `(false, nil)`, one
returning `(true, nil)`, and one that raises. Each counts its calls. No
`TextService`.

**C-9. Callers of changed signatures.** None. No existing export changes
signature. `GameRemotes` gains one key. `rg 'GameRemotes|Remotes.all\(\)'
src tests` (2026-10-06): the only uses of `Remotes.all()` with a count are
relative (`before + 1`, in `NetContract.luau` and `PhaseContract.luau`) or
by-name (`PingRemoteContract`, `TurnRemoteContract`). Adding a declaration
breaks neither. RED's handoff confirms this against the tree.

**C-10. Test placement.** Follow the Ping precedent: a contract helper,
`tests/helpers/PresetRemoteContract.luau`, takes the definition as a parameter.
It is applied to the real `GameRemotes.SendPreset` in
`tests/net/preset_remote_test.luau`, and to one-defect declarations in
`tests/net/preset_remote_controls_test.luau`. The controls are: the rate at
9.5 (AC-1's required control), a missing attempt floor, an extra legal phase
(`Assignment`), a missing phase (`Post`), a `preset_count + 1` bound,
`number()` rather than `integer()`, a schema admitting an optional `to`, and
ten per-preset limiters (AC-7). `PresetSends` unit tests go in
`tests/server/preset_sends_test.luau`, with controls in
`tests/server/preset_sends_controls_test.luau`. The controls are a send that
shows the unfiltered word on failure, one that does not decline on a filter
failure, one that calls the filter for an out-of-phase preset, one that
consumes nothing and shows nothing, and one that mutates the given state. The
existing `*Stubs.luau` / `*Contract.luau` pairs show the shape.

**Oracle partition.** AC-1 is **settled** by `tuning.md`: read it through
`RateLimitSpec` and `MechanicsTuning`, never from a literal. AC-2 to AC-7 are
**mechanical**.

## Deferred verifications

**D-1. The provenance test reads the declaration.** Use `scripts/mutate.sh` to
set `GameRemotes.luau`'s `SendPreset` rate to a literal `9`. AC-1's test
**must** then fail. RED cannot run this, because the module does not exist.
Owner: GATES.

**D-2. Fail-closed is real.** Use `scripts/mutate.sh` to make `send` show the
unfiltered word when the filter fails. AC-6 **must** then fail. Owner: GATES.

**D-3. A filter failure declines.** Use `scripts/mutate.sh` to remove the
`call.decline()` on the filter-failure path in `PresetSends.luau`. AC-6's
"the call is declined" assertion **must** fail, and AC-4's must stay green.
RED cannot run this. Owner: GATES.

**D-4. The per-preset phase check is load-bearing.** Use `scripts/mutate.sh`
to make `send` skip its own phase check, for example by making the phase test
always true. AC-4 **must** fail: `Well played` in `Round` is then shown. RED
cannot run this. Owner: GATES.

**D-5. One limiter spans the wheel, measured against the real remote.** Use
`scripts/mutate.sh` to set `SendPreset`'s `rateLimit` to
`channel_attempt_min_interval_seconds` instead. AC-7's 5 s second send **must**
then reach the handler, and AC-7 fail. RED's ten-limiter control proves the
check discriminates in principle; this proves it reads the real declaration.
Owner: GATES.

## Out of scope

- The real `TextService` adapter. It belongs to `SLICE-007`'s driver, with a
  Studio check.
- Displaying the preset, the chat system message and expiry after
  `preset_display_seconds` (`HUD-004`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-004` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/net/GameRemotes.luau` (source), `src/server/channel/PresetSends.luau` (source), `tests/helpers/PresetRemoteContract.luau` (test) (+4 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`. RED starts only after `CHAN-001` has amended the
filter port.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.

- PLANNED -> RED contract pinning - orchestrator (`lead-po` role, main session) -
  `claude-opus-5-5`. 2026-10-06.
- RED - `test-developer` - dispatched with explicit `model: fable`; resolved
  `claude-fable-5-1` (Fable 5.1) per the agent. Matches the plan. Orchestrator
  verified `lune run test` -> `1216 passed, 18 failed`; the 18 are the two
  real-module files only (12x `Remotes.all() lists no definition named
  "SendPreset"`, 6x `PresetSends.luau did not load`), and all 44 controls pass.

## Test plan

Two levels, following the `Ping` precedent (CHAN-005): the remote's declaration
and B4's triple at the **contract** level through the real `Wrapper.guard`
(`tests/net/`), and the pure module at the **unit** level (`tests/server/`). The
two guarded criteria that need both (AC-4's second half, AC-7) compose the real
guard with a handler that calls `PresetSends.send` (C-7). Every check is written
once in a helper, applied to the real module in a `*_test.luau`, and
**executed in RED** against a reference and one-defect stand-ins in a
`*_controls_test.luau`, so the measured set of checks each defect fires is in
the handoff rather than claimed.

| AC | Test (file :: name, abridged) | Level | Oracle |
|---|---|---|---|
| AC-1 | `preset_remote_test` :: rateLimit equals the value `RateLimitSpec` reads for `preset_rate_limit_seconds`, equals `MechanicsTuning.channel.preset_rate_limit_seconds`, >= `FLOOR_SECONDS` | contract | settled: read, never a literal |
| AC-1 | `preset_remote_test` :: attemptLimit equals `channel_attempt_min_interval_seconds` | contract | settled |
| AC-1 | `preset_remote_test` :: `Remotes.all()` lists exactly one `SendPreset`, the registered table itself; `GameRemotes.SendPreset` is that table | contract | mechanical |
| AC-1 | `preset_remote_test` :: a second call inside the attempt floor is `rate` with the attempt detail; one at exactly the floor is `rate` with the send detail | contract | mechanical (the floor enforced, so a missing floor is seen) |
| AC-1 control | `preset_remote_controls_test` :: `rate9point5` fails the rate check naming 9.5 and 10 (and the attempt-floor sequence, whose send detail quotes 9.5) | control | required by AC-1 |
| AC-2 | `preset_remote_test` :: the schema accepts exactly `{ preset = n }`, n integer in 1..preset_count; 0, count+1, 1.5 are `range`; `to`, `target`, `player`, `position`, a string, a missing field, a non-table are `shape` | contract | mechanical |
| AC-2 | `preset_remote_test` :: the same payloads through the guard are rejected for their kind and the handler never runs | contract | mechanical |
| AC-2 controls | `preset_remote_controls_test` :: bound `preset_count + 1`, `number()` for `integer()`, an optional `to` each fail exactly the schema check and the guarded malformed check | control | C-10 |
| AC-3 | `preset_remote_test` :: `legalPhases` is exactly the union of `Presets.ALL[*].phases` in `PhaseUnion.KNOWN` order (derived in the test, C-2) | contract | mechanical |
| AC-3 | `preset_remote_test` :: a well-formed call in each phase outside the union (Assignment, Resolution) is `phase`; the handler never runs | contract | mechanical |
| AC-3 positive | `preset_remote_test` :: a well-formed call in each phase of the union, at 1 and at `preset_count`, reaches the handler once with the payload and a `CallControl` | contract | mechanical |
| AC-3 controls | `preset_remote_controls_test` :: `Assignment` added fails the phases check + the refusal half; `Post` missing fails the phases check + the positive control; wrong order fails the phases check only | control | C-10 |
| AC-4 (pure) | `preset_sends_test` :: every preset in every phase its row excludes (37 cases, `Well played` in `Round` among them) is `failed`/`phase_for_preset`, declined once, filter never called, log unchanged, input untouched | unit | mechanical |
| AC-4 (guarded) | `preset_remote_test` :: through the real guard in Round, `Well played` is `declined` with `send` returning `phase_for_preset` and the filter uncalled; the same player's legal preset at exactly `t + channel_attempt_min_interval_seconds` reaches the handler and is `shown` | contract+unit | mechanical (C-7) |
| AC-4 controls | `preset_sends_controls_test` :: `filtersOutOfPhase`, `noDeclineOnPhase`, `skipsPhaseCheck` (D-4's shape); `preset_remote_controls_test` :: the guarded sequence over `noDeclineOnPhase` is `rate` on the legal preset, over `skipsPhaseCheck` shows `Well played` | control | C-10 |
| AC-5 | `preset_sends_test` :: every preset in every phase its row lists (13 cases) through a filter returning `####` is `shown` exactly `{ senderId, presetId, position, text = "####" }`, logged exactly `{ senderId, presetId, position, at = now }`, filter called once with `(senderId, word)`, never declined, input untouched; an echo filter shows the word | unit | mechanical |
| AC-5 (C-5) | `preset_sends_test` :: positions in the result and the log are fresh copies, unmoved by a later write to the caller's table | unit | mechanical |
| AC-5 (many) | `preset_sends_test` :: from `new()`, three shown sends with two refusals between them leave exactly three entries in order; no earlier state is written to | unit | mechanical |
| AC-5 controls | `preset_sends_controls_test` :: `showsWordNotFilterText`, `mutatesState`, `showsNothing`, `sharesPosition`, `declinesOnShown`, `logOmitsAt`, `filterTwice`, `sharesLog` (passes: identity unconstrained) | control | C-10 |
| AC-6 | `preset_sends_test` :: `(false, nil)`, `(true, nil)`, `(false, word)`, `(true, 42)` and a raise (50 cases) never escape `send`; `failed`/`filter`, declined once, filter called once, nothing shown or logged | unit | mechanical |
| AC-6 controls | `preset_sends_controls_test` :: `showsWordOnFilterFailure` (D-2's shape), `noDeclineOnFilterFailure` (D-3's shape), `acceptsTrueNil`, `raiseEscapes`, `logsOnFailure`, `declinesTwiceOnFailure`, `failedCarriesWord` | control | C-10 |
| AC-7 | `preset_remote_test` :: through the real guard in Round, two players at the same instant are both `shown`; one player's second, *different* preset at `t + rate/2` (5 s) is `rate` with `DeclineContract.sendDetail`; handler count stays 2; the log holds the two first sends | contract+unit | mechanical (C-7) |
| AC-7 control | `preset_remote_controls_test` :: ten per-preset declarations behind a dispatcher (`declarePerPreset`) fail the AC-7 check on the accepted second preset and the handler count; D-5's shape (`rateLimit = attempt floor`) fails it too | control | required by AC-7 |

Edges covered: empty log, one entry, many (AC-5 many); both schema bounds and
both just outside; every phase for every preset; every filter failure mode the
Contract lists; `## Out of scope` is pinned by omission (no `TextService`, no
display, no expiry: the stand-in filter and the pure result are all the tests
touch).

## Handoff: RED -> GREEN

**Resolved model for RED:** `claude-fable-5-1` (Fable 5.1, from the session's
own model identification). The dispatch did not state an override; the plan's
`fable` row and the resolved model agree.

### The command

    lune run test

(`~/.rokit/bin` on `PATH`; `lune/test.luau` has no per-file filter, so this is
the whole suite, about 100 s locally.) Baseline before this story: `1172 passed,
0 failed`. After: `1216 passed, 18 failed` - the 44 new passes are the two
controls files and the 18 reds are exactly the two real-module files. No
existing test regressed.

### The failure, verbatim (trimmed to one line per test; the message is the same for every test in a file)

    FAIL  tests/net/preset_remote_test.luau :: Contract: GameRemotes exports SendPreset, and it is the same table Remotes.all() lists under the name SendPreset
          tests\net\preset_remote_test:65: AC-1: Remotes.all() lists no definition named "SendPreset"
    FAIL  tests/net/preset_remote_test.luau :: AC-1: SendPreset's rateLimit.minIntervalSeconds equals the value RateLimitSpec reads for preset_rate_limit_seconds from tuning.md, ...
    FAIL  tests/net/preset_remote_test.luau :: AC-1: SendPreset's attemptLimit.minIntervalSeconds equals MechanicsTuning.channel.channel_attempt_min_interval_seconds
    FAIL  tests/net/preset_remote_test.luau :: AC-1: Remotes.all() lists exactly one definition named SendPreset, and it is the registered table itself
    FAIL  tests/net/preset_remote_test.luau :: AC-1: a second well-formed SendPreset inside channel_attempt_min_interval_seconds is rejected for rate with the attempt detail; ...
    FAIL  tests/net/preset_remote_test.luau :: AC-2: SendPreset's schema accepts exactly { preset = n } for integer n in 1..preset_count; ...
    FAIL  tests/net/preset_remote_test.luau :: AC-2: a seated caller in Round sending a missing preset, a string preset, 0, preset_count + 1, 1.5, a to, a target, a player, ...
    FAIL  tests/net/preset_remote_test.luau :: AC-3: SendPreset's legalPhases is exactly the union of Presets.ALL[*].phases in phase-machine order
    FAIL  tests/net/preset_remote_test.luau :: AC-3: a well-formed SendPreset by a seated caller in a phase outside the union (Assignment, Resolution) is rejected for phase ...
    FAIL  tests/net/preset_remote_test.luau :: AC-3 positive control: a well-formed SendPreset in each phase of the union, at 1 and at preset_count, reaches the handler ...
    FAIL  tests/net/preset_remote_test.luau :: AC-4: through the guarded SendPreset in Round, a preset whose row excludes Round is declined ...
    FAIL  tests/net/preset_remote_test.luau :: AC-7: through the guarded SendPreset in Round, two players sending at the same instant are both shown; ...
          (all twelve) tests\net\preset_remote_test:65: AC-1: Remotes.all() lists no definition named "SendPreset"

    FAIL  tests/server/preset_sends_test.luau :: Contract (C-5): PresetSends.new() is exactly { log = {} }, fresh on every call
    FAIL  tests/server/preset_sends_test.luau :: AC-4: every preset sent in a phase its row excludes (Well played in Round among them) is failed with reason phase_for_preset, ...
    FAIL  tests/server/preset_sends_test.luau :: AC-5: every preset sent in a phase its row lists through a filter returning #### is shown as exactly ...
    FAIL  tests/server/preset_sends_test.luau :: Contract (C-5): the position in PresetShown and in the log entry is a fresh copy ...
    FAIL  tests/server/preset_sends_test.luau :: AC-6: a filter returning (false, nil), (true, nil), (false, word) or (true, 42), or raising, never escapes send; ...
    FAIL  tests/server/preset_sends_test.luau :: AC-5: from new(), three shown sends by two senders with a phase refusal and a filter refusal between them ...
          (all six) tests\server\preset_sends_test:39: src/server/channel/PresetSends.luau did not load: error requiring module "../../src/server/channel/PresetSends": could not resolve child component "PresetSends"

**Why it is the right failure.** `GameRemotes.luau` loads (it exists, with
`Turn` and `Ping`) and `Remotes.all()` lists no `SendPreset`: the first thing
the story requires is that declaration, and every `net` test stops at the
by-name lookup rather than at an import. `PresetSends.luau` does not exist, so
every `server` test stops at the module require. Both real files `pcall` their
requires at the top (the precedent), so the failures are per test, not a
wholesale LOAD FAIL. Because of that, **no assertion in either real file has
executed**; what makes the checks trustworthy is the controls files, where every
check was executed against a reference and one-defect stand-ins (tables below).

### Files touched (all new, all `test` under `paths.conf`; nothing under `src/`)

| File | Role |
|---|---|
| `tests/helpers/PresetRemoteContract.luau` | AC-1, AC-2, AC-3 checks over a definition; AC-4 (guarded) and AC-7 checks over a definition + a `PresetSends` module; `declare` (one-defect declarations), `declarePerPreset` (AC-7's control), `guardFor` |
| `tests/helpers/PresetSendsContract.luau` | AC-4 (pure), AC-5, AC-6, C-5 checks over a `PresetSends` module; the filter stand-ins (C-8); the input domain read from `Presets.ALL` |
| `tests/helpers/PresetSendsStubs.luau` | the reference `PresetSends` and 18 one-defect implementations (`PresetSendsStubs.with(defect)`) |
| `tests/net/preset_remote_test.luau` | the real `GameRemotes.SendPreset` through the real `Wrapper`, plus AC-4/AC-7 over the real `PresetSends` - 12 tests, all red |
| `tests/net/preset_remote_controls_test.luau` | reference + controls for the remote checks, and the guarded AC-4/AC-7 checks over the stubs - 23 tests, all green in RED |
| `tests/server/preset_sends_test.luau` | the real `PresetSends` - 6 tests, all red |
| `tests/server/preset_sends_controls_test.luau` | reference + controls for the pure checks - 21 tests, all green in RED |
| `docs/backlog/stories/CHAN-004.md` | `## Test plan`, this section |
| `.claude/tests/project-counters.test.sh` | the `harness` gate's file-count baselines, set to the **predicted post-GREEN** values (190/190/31, narrow 31/31/9) in RED, as CHAN-002/CHAN-005 did: `check-boundaries.sh` 3j refuses a `.claude/tests/**` change from any other phase. GREEN confirms, never edits. |

### `bash scripts/gates.sh --fast` on this tree (2026-10-06, local)

    PASS         format (0s, observed 189)
    PASS         lint (1s, observed 189, floor 1)
    PASS         typecheck (2s, observed 30)
    FAIL         unit (130s, exit 1) -> .claude/state/gate-logs/unit.log      1216 passed, 18 failed
    UNCONFIGURED coverage
    PASS         build (1s, observed 117327)
    FAIL         harness (18s, exit 1) -> .claude/state/gate-logs/harness.log  project-counters: 29 passed, 12 failed

The shape is the right one: format, lint and typecheck green, `unit` red on
exactly the 18 real-module tests above, no timeout or config error (the runner
has no per-test timeout; the unit gate is the same `lune run test`). `harness`
is red for the reason the counter file's own comment predicts, measured after
the baselines were set (`--gate harness`, 13 s): the "no stray .luau files"
precondition until the RED commit lands, and every counter off by **exactly
one** - `expected count: 190 / actual count: 189` for format and lint, `31 /
30` for typecheck and both narrow src cases, `191 / 190` and `32 / 31` for the
untracked-file cases - which is the single `src/server/channel/PresetSends.luau`
GREEN adds. The narrow src/shared typecheck (9) does not fail. Before the
baselines were set the same gate reported `182 / 189`, i.e. this story's seven
test files. **The orchestrator makes the RED commit** carrying the seven test
files, the counter baselines and this story file (frontmatter `phase: RED`);
GEN-001 skipped that commit and needed a return to RED to make it.

A second source file in GREEN, or one under `src/shared/`, is a counter failure
GREEN cannot fix: `SendPreset` goes into the **existing** `GameRemotes.luau`.

### The export shape the tests already pin (fact, not suggestion)

**`src/net/GameRemotes.luau`** - the returned table gains `SendPreset`, which
must be `rawequal` to the entry `Remotes.all()` lists under `name == "SendPreset"`
(declared once, through `Remotes.define`, at require time). The tests read it
**by name out of `Remotes.all()`** first, so a declaration under any other name
fails before anything else. Pinned on the definition:

- `args.validate` answers `(true, nil)` for `{ preset = n }`, n an integer in
  `1..MechanicsTuning.channel.preset_count`; `"range: ..."` for 0,
  `preset_count + 1`, 1.5; `"shape: ..."` for `{ preset = "1" }`, `{ preset = true }`,
  `{}`, `nil`, a string, a number, and **any** extra key (`to`, `target`,
  `player`, `position`, an array key). `{ preset = preset_count + 1, to = ... }`
  is `shape` (structural pass first). All of this is exactly what
  `Schema.shape({ preset = Schema.integer(1, preset_count) })` does - confirmed
  in RED by the reference declaration passing the schema check (the Contract's
  "confirm `Schema.shape` rejects unknown keys as `shape`" is confirmed; no
  amendment needed).
- `legalPhases` `Deep.equal` to `{ "Lobby", "Round", "Post" }` **in that
  order** (derived in the test from `Presets.ALL` and `PhaseUnion.KNOWN`; a
  control with `{ "Round", "Lobby", "Post" }` fails the phases check).
- `rateLimit.minIntervalSeconds == MechanicsTuning.channel.preset_rate_limit_seconds`
  (10, and equal to what `RateLimitSpec` reads from `tuning.md`, and >= 10).
- `attemptLimit.minIntervalSeconds == MechanicsTuning.channel.channel_attempt_min_interval_seconds` (1).
- Through `Wrapper.guard`: the rate details are the wrapper's own
  (`DeclineContract.attemptDetail` / `sendDetail` with the remote's `name`, so
  the name must be exactly `"SendPreset"` for the details the tests compare).

**`src/server/channel/PresetSends.luau`** - a module table with:

    PresetSends.new() -> PresetState                -- exactly { log = {} }, a fresh table per call
    PresetSends.send(state, senderId: string, presetId: number, phase: string,
                     position: { x, y, z }, now: number,
                     filter: (senderId, text) -> (boolean, string?),
                     call: { decline: () -> () })
        -> (PresetState, SendResult)                -- returns TWO values in this order

Pinned by `Deep.equal` (exact keys, no extras):

- `SendResult` is `{ kind = "shown", shown = { senderId, presetId, position, text } }`
  or `{ kind = "failed", failed = { presetId, reason } }` with `reason` one of
  `"phase_for_preset"`, `"filter"`. No other key on any of those tables.
- `PresetState` is `{ log = { PresetLogEntry } }`; an entry is exactly
  `{ senderId, presetId, position, at }` with `at == now`.
- Order (C-4): phase check first - `phase` not in `Presets.byId(presetId).phases`
  -> `call.decline()` exactly once, `failed`/`phase_for_preset`, **filter not
  called**. Then `pcall(filter, senderId, preset.word)` exactly once; success is
  `ok == true and okFiltered == true and typeof(text) == "string"`; anything
  else (a raise, `(false, _)`, `(true, nil)`, `(true, 42)`) -> `call.decline()`
  exactly once, `failed`/`filter`, nothing logged, and the raise never escapes.
  Success -> `shown` with `text` = the filter's **returned** string (the tests
  use `"####"`, never the word), the log gains one entry, `decline` **not**
  called.
- Immutability (C-5): the given `state` is deep-equal to its snapshot after
  every call; on `shown` the returned state's `log` is the old log plus one
  entry and the old state's log length is unchanged (so `table.clone` the log,
  do not append in place); on `failed` the returned state's log is deep-equal
  to the old one. `shown.position` and the entry's `position` are each **not
  `rawequal`** to the caller's table and do not move when the caller's table is
  written to afterwards.

**Not constrained** (the implementer's choice): whether `legalPhases` is
computed from `Presets` or written as the literal (C-2); whether `shown.position`
and the log entry's position are one copy or two; the identity of the state a
`failed` result returns (a control that returns the given table itself passes
every check); what `send` does with an unknown preset id (never driven); the
text of any rejection detail beyond the three CHAN-003 fixed; `GameRemotes`'
header comment and the order of `Remotes.all()`; whether `PresetSends` is
frozen; the local `CallControl` type (C-3: structural, `{ decline: () -> () }`).

### Tests green on arrival

Only the two controls files, by design: every one of their 44 tests runs a
check against a stand-in and asserts the exact set of checks that fire, so
each one is itself the probe that earns the corresponding check. No test in
the two real-module files passed. Nothing else to earn.

### The controls, as measured in RED (the numbers, not the claim)

Measured under `lune run test` on this machine, 2026-10-06. "fires" lists the
checks that raised, sorted; every control is the reference with one change and
the expected set is pinned **exactly**. GREEN's job is to confirm the real
module passes every check these controls fire - and that the sets below are
unchanged (they are printed as `[measured]` lines in the run).

Fixture values read, not written: `tuning.md` `preset_rate_limit_seconds` = 10,
`MechanicsTuning.channel.preset_rate_limit_seconds` = 10, `FLOOR_SECONDS` = 10,
`preset_count` = 10 (= `#Presets.ALL`), `channel_attempt_min_interval_seconds`
= 1, `EPSILON` = 0.1, derived union `{ Lobby, Round, Post }`, outside it
`{ Assignment, Resolution }`; 37 (preset, excluded phase) cases, 13 (preset,
listed phase) cases, 9 presets legal in Round, 5 failing filters.

**`PresetRemoteContract` battery (9 checks). The reference fails 0 of 9.**

| Control (one edit) | Fires (measured) | Needle asserted |
|---|---|---|
| `rate9point5` (AC-1's required control; D-1's shape) | `rateLimitIsThePresetRateLimitTheDocumentFixes`, `secondCallInsideTheAttemptFloorIsRejectedForRate` | message carries `SendPreset.rateLimit is { minIntervalSeconds = 9.5 }`, `expected { minIntervalSeconds = 10 }`, `below RateLimitSpec.FLOOR_SECONDS = 10`; the send detail quotes `one call per 9.5 s` |
| `rateLimitPlusOne` (11) | same two | `minIntervalSeconds = 11`; **not** "below the floor" |
| `noRateLimit` | same two | `SendPreset.rateLimit is nil` |
| `noAttemptLimit` (C-10) | `attemptLimitIsTheChannelAttemptFloorFromTuning`, `secondCallInsideTheAttemptFloorIsRejectedForRate` | `SendPreset.attemptLimit is nil`; the 0.9 s call carries the SEND detail |
| `attemptPlusOne` (2) | same two | - |
| `legalInAssignmentToo` (C-10) | `legalPhasesAreTheUnionOfThePresetTablesPhases`, `wellFormedCallOutsideTheUnionIsRejectedForPhase` | `phase is Assignment -> ACCEPTED` |
| `missingPost` (C-10) | `legalPhasesAreTheUnionOfThePresetTablesPhases`, `wellFormedCallInEachLegalPhaseReachesTheHandler` | `in Post -> REJECTED` |
| `unorderedPhases` (`{ Round, Lobby, Post }`) | `legalPhasesAreTheUnionOfThePresetTablesPhases` only | - |
| `presetUpperBoundPlusOne` (C-10) | `schemaIsExactlyPresetIntegerOneToPresetCount`, `malformedCallsAreRejectedBeforeTheHandler` | `preset = 11 (preset_count + 1) -> ACCEPTED` |
| `presetIsNumber` (C-10) | same two | `preset = 1.5 -> ACCEPTED` |
| `acceptsTo` (C-10, C9) | same two | `to = "lee" } (a recipient) -> accepted` (schema) and through the guard |
| `unregisteredCopy` | `isTheDefinitionRemotesAllLists` only | - |

**Guarded AC-4 and AC-7 (over `PresetSendsStubs`).** Reference passes both.

| Control | Result (measured) |
|---|---|
| AC-4 over `noDeclineOnPhase` | fails: the out-of-phase preset at t is accepted (`nil`) instead of `declined`; the legal preset at t + 1 is `rate` with the send detail; handler ran 1, expected 2 |
| AC-4 over `skipsPhaseCheck` (D-4's shape) | fails: the guard answers `nil` at t and `send` returned `{ kind = "shown", ... presetId = 10 ... }` |
| AC-4 over `filtersOutOfPhase` | fails: `the filter was called 1 time(s) for the out-of-phase preset; expected never` |
| AC-7 over ten per-preset limiters behind a dispatcher (**AC-7's required control**) | fails: `kim sends a DIFFERENT preset 2 at t + 5 ... -> ACCEPTED (returned nil); expected a "rate" rejection`; `the handler ran 3 time(s) in total; expected 2`; the log has a third entry at 15. Each of the ten definitions passes the per-definition battery on its own |
| AC-7 over `rateLimit = 1` (D-5's shape) | fails on the accepted second preset; the rate check names `minIntervalSeconds = 1` against the document's 10 |
| AC-7 over `declinesOnShown` | fails: the first send is `REJECTED: reason = "declined"` |

**`PresetSendsContract` battery (6 checks). The reference fails 0 of 6.**

| Control (one edit) | Fires (measured) | Needle asserted |
|---|---|---|
| `showsWordOnFilterFailure` (C-10; D-2's shape) | `filterFailure...`, `theLogAccumulates...` | `value.kind: expected "failed", got "shown"`; `call.decline() was called 0 time(s)` |
| `noDeclineOnFilterFailure` (C-10; D-3's shape) | `filterFailure...` only | `call.decline() was called 0 time(s), expected exactly once` |
| `filtersOutOfPhase` (C-10) | `outOfPhasePreset...` only | `the filter was called 1 time(s) for a preset refused by its own phase list` |
| `showsNothing` (C-10) | `legalPresetIsShown...`, `positions...FreshCopies`, `filterFailure...`, `theLogAccumulates...` | `reason = "filter"` where a send was expected; `the filter was called 0 time(s)` |
| `mutatesState` (C-10) | `legalPresetIsShown...`, `theLogAccumulates...` | `send wrote into the state it was given (C-5)`; `the state new() returned was written to by later sends` |
| `skipsPhaseCheck` (D-4's shape) | `outOfPhasePreset...`, `theLogAccumulates...` | names `Well played`; `got "shown"` |
| `noDeclineOnPhase` | `outOfPhasePreset...` only | decline count 0 |
| `showsWordNotFilterText` | `legalPresetIsShown...` only | `expected "####"` |
| `filterTwice` | `legalPresetIsShown...`, `filterFailure...` | `called 2 time(s), expected exactly once` |
| `acceptsTrueNil` | `filterFailure...` only | the `(true, nil)` case; `got "shown"` |
| `raiseEscapes` | `filterFailure...` only | `send RAISED:`; `a filter failure never escapes send` |
| `logsOnFailure` | `filterFailure...`, `theLogAccumulates...` | `something was logged` |
| `declinesTwiceOnFailure` | `filterFailure...` only | `called 2 time(s), expected exactly once` |
| `declinesOnShown` | `legalPresetIsShown...` only | `on a SHOWN preset; expected never` |
| `sharesPosition` | `positions...FreshCopies` only | `shown.position IS the caller's table`; the later write moved it |
| `logOmitsAt` | `legalPresetIsShown...`, `theLogAccumulates...` | `at: expected 100, got nil` |
| `failedCarriesWord` | `outOfPhasePreset...`, `filterFailure...` | `word: unexpected` |
| `sharesLog` (a failed result returns the given table) | **none** - passes, by design (C-5: identity unconstrained) | - |
| a `new()` returning `{ log = { 1 } }` | `newIsAnEmptyLog` (+ two downstream) | - |
| a `new()` returning one shared table | `newIsAnEmptyLog` only | - |

### Deferred verifications (D-1..D-5): declined in RED, in these words

I cannot run any of D-1..D-5: each mutates `GameRemotes.luau`'s `SendPreset` or
`PresetSends.luau`, and neither exists yet. They stay with GATES. What RED can
say is which assertion each mutation should turn red, from the stand-in with
the same shape:

| DV | Mutation (GATES, via `scripts/mutate.sh`) | Expect red | Expect green |
|---|---|---|---|
| D-1 | `SendPreset` rate -> literal `9` | `preset_remote_test` AC-1 rate test (naming 9 and 10), the attempt-floor test (its exact-floor call quotes 9 in the send detail), and AC-7 (the second preset is still `rate` at 5 < 9, but its detail quotes 9 where the test compares the whole string against 10) | AC-2, AC-3, AC-4, every `preset_sends_test` |
| D-2 | `send` shows the word on filter failure | `preset_sends_test` AC-6 (`got "shown"`, decline count 0) and the AC-5 "many" test (an extra entry) | AC-4, C-5, `new` |
| D-3 | remove `call.decline()` on the filter-failure path | `preset_sends_test` AC-6 on the decline count **only**; AC-4 (pure and guarded) stays green, as the AC says | AC-4, AC-5, AC-7 |
| D-4 | phase test always true | `preset_sends_test` AC-4 (`Well played` in `Round` shown) and the AC-5 "many" test; `preset_remote_test` AC-4 guarded (guard answers `nil` at t) | AC-5, AC-6 |
| D-5 | `SendPreset` rate -> `channel_attempt_min_interval_seconds` | `preset_remote_test` AC-7 (second preset at t + 5 accepted, handler 3) and the AC-1 rate test (1 vs 10) and the attempt-floor test | AC-2, AC-3 |

### Checked against the tree

- **C-9**: `rg 'GameRemotes|Remotes\.all\(\)' src tests` on 2026-10-06, this
  worktree: every count over `Remotes.all()` is relative (`before + 1` in
  `NetContract.luau`, `PhaseContract.luau`) or by name (`PingRemoteContract`,
  `TurnRemoteContract`, and now `PresetRemoteContract`). Adding `SendPreset`
  breaks none. No existing export changes signature.
- **`RateLimitSpec.NAMES[1] == "preset_rate_limit_seconds"`** holds, and the
  document row is a bare `10` (the `fixtures` control reads it).
- **Contract amendments**: none needed. The Contract's "confirm `Schema.shape`
  rejects unknown keys as `shape`" is confirmed by the reference declaration
  passing the schema check, which drives `to`, `target`, `player`, `position`
  and an array key.

### Discovered, for the implementer

- Two `send` results per guarded call are read through the handler: the test
  handler threads `state` through an upvalue and reads `world.phase` and
  `clock.now()` the way `SLICE-006`'s handler will. `send` takes **eight**
  positional arguments in the Contract's order; the tests do not accept a
  table of options.
- `(true, nil)` from the filter is a **failure** (C-4 step 3, "text is not a
  string") - do not default to the word.
- The AC-7 test sends two *different* presets; a limiter keyed per
  `(player, preset)` or per remote-name-per-preset passes the attempt-floor
  test and fails only AC-7, which is the point of the control.
- Timing: the whole suite runs in ~100 s locally and ~1 s of that is these 62
  tests; no test here sets or needs a timeout (the runner has none).

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
  - *Gate.* `unit` (required) covers `src/net/**` and `src/server/**`, the two
    files this story builds. No optional gate is the only one reading them, so
    `required_gates` stays empty.
  - *Epic.* EPIC-06's done-when items 3 and 4 (the `CHAN-004` halves) are
    exactly AC-1, AC-2, AC-3/AC-4, AC-6 and AC-7. There is no gap.
  - *Decisions.* C-1 to C-10 were pinned under `## Contract`. The two that
    interpret an AC are C-6 (what "addressed to the sender only" means in a pure
    module) and C-5 (immutability and position copies, following `Pings`). D-3
    to D-5 were added to `## Deferred verifications`, owned by GATES.
