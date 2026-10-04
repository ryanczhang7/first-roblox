---
id: CHAN-003
title: A call its handler declines costs the attempt floor but not the send cooldown
slug: a-call-its-handler-declines-costs-the-at
epic: EPIC-06
type: feature
status: in-progress
phase: RED
branch: story/CHAN-003-a-call-its-handler-declines-costs-the-at
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. The Game Designer's G9 answer (`tuning.md` §3,
`channel_limiter_consumed_by` and `channel_attempt_min_interval_seconds`;
`mechanics.md` §4.1, §4.2, §8) says **only a send that is broadcast consumes the
10 s cooldown**. Three refusals are not sends: a ping refused for its target, a
preset refused by its own phase list, and a preset whose filtering failed. A
1 s **attempt floor**, consumed by every call that reaches the rate stage, keeps
B4's anti-spam guarantee once refunds exist.

That collides with the M2 pipeline. `Wrapper.guard` runs the rate stage
**before** the handler (`architecture.md` §4), so the limiter has already
recorded the call by the time a handler can find out that it is not a send.
`architecture.md` D18 settles how to reconcile the two. The handler may
**decline** the call, and the wrapper then refunds the send limit. A separate,
non-refundable attempt limit runs first. Nothing may run before identity and
shape, so validation cannot move in front of the wrapper.

This story builds only the mechanism. The remotes that use it are `CHAN-004`
(presets) and `CHAN-005` (pings).

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a guarded remote with a send limit, when its handler calls
  `call.decline()` and the same player calls again after the attempt floor has
  passed but well inside the send limit, then the second call passes the rate
  stage.
  *Control:* the same sequence with a handler that does not decline must be
  rejected for `rate` on the second call.
- **AC-2** — Given a remote declaring an `attemptLimit`, when a player calls
  twice inside it, then the second call is rejected for `rate` whether or not the
  first was declined. The detail names the attempt floor rather than the send
  limit.
  *Control:* an implementation that refunds the attempt limit on decline must
  fail this AC.
- **AC-3** — Given a player whose previous call was accepted at `t0`, when a
  later call at `t1` is accepted and then declined, then the send limiter's
  state for that player and key is exactly what it was after `t0`. A call at
  `t0 + interval − ε` is still refused, and one at `t0 + interval` is allowed.
  *Control:* a refund that clears the key instead of restoring `t0` must fail
  this AC.
- **AC-4** — Given a handler that declines, when the wrapper returns, then the
  result is a `Rejection` with reason `declined` and a detail naming the remote.
  When the context carries telemetry, the `RejectionReporter` records it like
  any other reason.
- **AC-5** — Given every existing remote declaration and handler (none of which
  declines or declares an attempt limit), when the existing `tests/net/` suites
  run, then they pass unchanged. A call reaching stage 5 still reads the clock
  exactly once, which NET-003 pins.

## Contract

**Changed exports, and their callers.**

`Remotes.RemoteSpec` and `Remotes.RemoteDefinition` gain an optional field:

    attemptLimit: RateLimit?   -- non-refundable; checked before rateLimit in stage 5

`Wrapper.guard`'s handler gains a third parameter. Old handlers take two
parameters and remain valid, because a Luau function may ignore extra
arguments:

    export type CallControl = { decline: () -> () }
    Wrapper.guard(definition, context, handler: (playerId: PlayerId, args: any, call: CallControl) -> ())
        -> (playerId: PlayerId, rawArgs: any) -> Rejection?
    Rejection.reason gains "declined"

- Stage 5 reads `context.clock.now()` **once** and uses that value for both
  limiters.
- `decline` may be called after the handler has yielded (a filter call yields),
  and it refunds the acceptance made at that call's `now`. Calling it twice is a
  no-op the second time. A call that is never declined keeps its acceptance.

`RateLimiter` gains a member:

    refund: (self: RateLimiter, playerId: PlayerId, key: string, acceptedAt: number) -> ()
    -- restores the key to its value before the acceptance at `acceptedAt`;
    -- a no-op if the key's last acceptance is not `acceptedAt`

`RejectionReporter.Reason` gains `"declined"`.

RED may amend any block in this section in place, with a one-line reason beside
it; GREEN builds what the amended block says.

**Semantics pinned in PLANNED (PO-1, 2026-10-04).** These are read against the
code as it stands: `Wrapper.guard` builds one `RateLimiter` per `guard()` call
when `rateLimit` is declared, and reads `context.clock.now()` inside stage 5
only when there is a limiter.

- **`RateLimiter.refund` needs one level of history.** Today the limiter
  stores only the last accepted timestamp per `(player, key)`, so "restore the
  value before the acceptance" cannot be computed. GREEN keeps the value each
  acceptance overwrote, internally; the type gains no field. `refund(p, k,
  acceptedAt)`:
  - if the key's last acceptance is `acceptedAt`, the key goes back to the
    timestamp it held before that acceptance;
  - if that earlier value was "never accepted", the key is removed, and if the
    player then holds no key, their whole entry is removed. NET-003's AC-6 says
    `size()` counts the players the limiter holds, and a player whose only
    acceptance was refunded holds nothing;
  - otherwise it is a no-op: a later acceptance has happened, the key never
    existed, or the player is unknown. It never raises.
  - Refund restores **one** acceptance. A second refund of the same
    `acceptedAt` is a no-op, because the key's last acceptance is no longer
    `acceptedAt`.
- **Two limiters, built independently.** `attemptLimit` gets its own
  `RateLimiter` when declared, exactly as `rateLimit` does. A remote may declare
  either, both or neither. A remote declaring neither still reads the clock
  **zero** times (NET-003 AC-4).
- **Stage 5 order.** Read `now = context.clock.now()` **once** if either limiter
  exists. Then:
  1. The attempt limiter: if it refuses, return `rate` with the detail
     `"<name>" is limited to one attempt per <n> s per player`. The send
     limiter is not consulted and nothing is recorded in it.
  2. The send limiter: if it refuses, return `rate` with today's detail
     unchanged, `"<name>" is limited to one call per <n> s per player`. The
     attempt acceptance from step 1 stands, because the floor is never refunded.
  3. The handler.
  The two details differ in "attempt" versus "call", which is AC-2's needle, so
  a test must match the whole detail (anchored), not just one word of it.
- **`CallControl` and `declined`.** The wrapper passes the handler a fresh
  `call = { decline = function }` on every call.
  - **`decline()` during the handler**, including after the handler yielded,
    because the wrapper is still waiting on it: refund the **send** limiter's
    acceptance at this call's `now`, if it made one. Never refund the attempt
    limiter. When the handler returns, the wrapper returns
    `{ reason = "declined", detail = '"<name>" declined the call' }`. That goes
    through the same telemetry path as every rejection (`RejectionReporter`
    records `declined` once per call, `count = 1`, uncoalesced like every
    reason but `rate`).
  - **`decline()` after the wrapper has returned** (a handler that kept `call`):
    the refund still applies. Nothing is returned or emitted, because the
    result has already gone.
  - **Twice:** the second call is a no-op.
  - **Never:** the result is `nil`, and the acceptance stands.
  - With no send limiter, `decline()` still makes the result `declined`, and
    there is nothing to refund.
- **`Rejection.reason`** (the `Wrapper` type and its private `Reason`) and
  `RejectionReporter.Reason` all gain `"declined"`. `Event` does not enumerate
  reasons, so no telemetry schema changes. `Remotes.define` copies
  `attemptLimit` field by field, as it copies `rateLimit` today.

**Callers, re-grep-listed 2026-10-04** (`rg -l "Wrapper.guard|\.guard\(|RateLimiter|Remotes.define|RejectionReporter" src tests`).
The 2026-09-30 list was missing the PROC-005 Turn remote's files, and it named
a `rate_controls_test.luau` that the re-grep does not list. *(RED amendment,
2026-10-04: that file EXISTS - `tests/net/rate_controls_test.luau` - and runs
NET-003's checks over `RateStubs`; it is absent from the list only because none
of the pattern's five strings occurs in it. It drives no production module, so
nothing this story changes can break it; AC-5's "unchanged" run covers it like
every other `tests/net/` file.)* RED confirmed this list against the tree
(same command, 2026-10-04): 6 source files and 17 test files, exactly as below.

- source: `src/net/Wrapper.luau`, `src/net/RateLimiter.luau`,
  `src/net/RejectionReporter.luau`, `src/net/Remotes.luau`,
  `src/net/GameRemotes.luau` (declares `Turn` with `rateLimit` only, and
  unchanged by this story), `src/server/procedure/TurnRequests.luau` (named in
  a comment about `guard`'s checks; it does not call it).
- tests: `tests/helpers/NetContract.luau`, `NetStubs.luau`, `PhaseContract.luau`,
  `PhaseStubs.luau`, `RateContract.luau`, `RateStubs.luau`,
  `RejectionContract.luau`, `RejectionStubs.luau`, `TurnRemoteContract.luau`;
  `tests/net/wrapper_test.luau`, `remotes_test.luau`, `rate_test.luau`,
  `rejection_test.luau`, `rejection_controls_test.luau`,
  `net_controls_test.luau`, `turn_remote_test.luau`,
  `turn_remote_controls_test.luau`.
- Two reason lists exist: `NetContract.REASONS` (identity, shape, range) and
  `RejectionContract.REASONS` (all five). Both are iterated, and neither is
  asserted as the complete set, from what PLANNED read. RED checks that,
  together with `remotes_test.luau:39`'s "define returns the declaration with
  name, args, legalPhases and optional rateLimit as given", which may pin the
  definition's field set exactly.
- **If an existing test pins the reason set or the definition's field set as
  exhaustive**, adding `declined` or `attemptLimit` turns it red. That is a
  corrective RED on a DONE story's test. It goes in `## Regressions` with a
  probe, and the test is not edited into passing.

**Oracle partition.** Every criterion is **mechanical**. The controls in AC-1
to AC-3 are hand-written wrong implementations.

## Deferred verifications

**D-1. The refund restores, it does not clear.** Use `scripts/mutate.sh` to make
`refund` set the key to `nil`. AC-3 **must** then fail, and AC-1 **must** still
pass. RED cannot run this. Owner: GATES.

**D-2. The attempt floor is not refunded.** Use `scripts/mutate.sh` to make
`decline` refund the attempt limiter too. AC-2 **must** then fail. Owner: GATES.

**D-3. The refund is guarded by `acceptedAt`.** With `refund`'s check that the
key's last acceptance equals `acceptedAt` removed, so that it unwinds whatever
the last acceptance was, RED's case "a refund naming an acceptance that is no
longer the last one is a no-op" **must** fail. RED cannot run this. Owner:
GATES.

**D-4. Stage 5 reads the clock once.** With the wrapper changed to read
`context.clock.now()` separately for each limiter, AC-5's clock-once assertion,
run on a remote declaring both limits, **must** fail. RED cannot run this.
Owner: GATES.

## Out of scope

- Any game remote. `CHAN-004` declares `SendPreset` and `CHAN-005` declares
  `Ping`, each with both limits.
- `Turn`, which has no attempt floor and never declines (`PROC-005`). A refused
  turn is refused inside the Procedure and still consumes `turn_rate_limit_seconds`,
  which is not a channel limit (`tuning.md` §4).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-003` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/net/GameRemotes.luau` (source), `src/net/RateLimiter.luau` (source), `src/net/RejectionReporter.luau` (source) (+5 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`. Brief RED with the caller list. Any change to an
existing test here is a corrective RED and needs a probe.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.
- RED (Return 1) - `test-developer` - `claude-fable-5-1` (Fable 5.1, the
  agent's own identification; the dispatch named no override). 2026-10-04.

## Test plan

Written in RED, 2026-10-04. Four new files, no existing test edited.

**Level.** Everything is at the level the contract lives: the real
`Wrapper.guard` driving the real `Schema`, `Remotes`, `RateLimiter` and
`RejectionReporter` through an injected `GuardContext` with a counted
`Clock.manual` (`RateContract.world`). The refund semantics are ALSO pinned
as unit checks on `RateLimiter` directly, where `now` is a plain parameter.
No test sleeps or reads real time.

**Oracle partition honoured.** Every criterion is mechanical. The two stage-5
details, the `declined` Rejection and the refund clauses are copied out of
`## Contract` and compared whole (`==` on the full string, `Deep.diff` on the
Rejection), never by substring - the Contract says AC-2's needle is
"attempt" versus "call" inside otherwise identical sentences. The intervals
on the test remote (`SEND_SECONDS = 10`, `ATTEMPT_SECONDS = 1`) are fixtures
declared on the remote, the shape `architecture.md` §9.5 describes; the
mechanism is value-agnostic and nothing is read from `src/shared/`.

**Files.**

| File | Role |
|---|---|
| `tests/helpers/DeclineContract.luau` | the 15 checks, as functions over a bundle `{ Schema, Remotes, Wrapper, RateLimiter, RejectionReporter }` |
| `tests/helpers/DeclineStubs.luau` | the baseline (a stage-5 layer over `PhaseStubs.correct()` with two limiters, a `CallControl`, a refunding stub limiter and the telemetry step) and 20 one-defect controls |
| `tests/net/decline_test.luau` | the 15 checks over the real modules - RED |
| `tests/net/decline_controls_test.luau` | 22 tests: the baseline passes all 15 plus 15 earlier-suite checks; each control fails EXACTLY its measured set |

**Checks and the criteria they cover.**

| Check (`DeclineContract.`) | AC | What it pins |
|---|---|---|
| `declinedCallDoesNotCostTheSendLimit` | AC-1 | send-limited remote, handler declines at t, same player at t + 1.1 is accepted and the handler ran twice; the criterion's control (nothing declined) is `rate` with the send sentence |
| `attemptFloorIsNeverRefunded` | AC-2 | both limits; second call at t + 0.9 is `rate` with EXACTLY the attempt sentence after a declined AND after a kept first call; at t + 1 the send sentence; at t + 1.1 the attempt sentence again (the attempt acceptance of the send-refused call stands); at t + 2 the send sentence |
| `sendLimiterIsNotConsultedWhenTheAttemptFloorRefuses` | Contract step 1 | decline at t, floor refusal at t + 0.5, acceptance at t + 1.5 - a send limiter consulted at t + 0.5 would refuse it |
| `refundRestoresThePreviousAcceptance` | AC-3 | accepted t0, accepted+declined t1 = t0 + 10, then t0 + 9.9 refused and t0 + 10 allowed (clock SET backwards; see the helper header) |
| `refundRestoresTheAcceptanceBeforeItOnTheLimiter` | AC-3 (unit) | same on `RateLimiter.refund`; plus a second refund of t1 and a refund of a never-accepted instant are no-ops leaving t0 in place, `size()` still 1 |
| `refundOfAStaleAcceptanceIsANoOp` | Contract / D-3 | accept t0, t1, t2; refund(t1) leaves t2 (t2 + 9.9 refused, t2 + 10 allowed) |
| `refundOfAPlayersOnlyAcceptanceRemovesThePlayer` | Contract (AC-6 of NET-003) | `size()` 1 -> 0 after refunding the only acceptance; same instant allowed again; a second key or a second player keeps the entry |
| `refundOfAnUnknownPlayerOrKeyNeverRaises` | Contract | stranger, unused key, wrong instant: no raise, no change |
| `declinedCallReturnsADeclinedRejection` | AC-4 | exact `{ reason = "declined", detail = '"<name>" declined the call' }` with send limit, both, attempt-only, neither; handler's third argument is `{ decline = function }` |
| `declinedIsRecordedLikeAnyOtherReason` | AC-4 | spy: `record(playerId, name, "declined", now)` once then `emit({ event })` once; real reporter: five declines at one instant are five `remote_rejected` events with `count = 1`, `flush` empty |
| `callControlIsFreshPerCallAndAnUndeclinedCallKeepsItsAcceptance` | Contract | two calls get two different controls; never declined -> nil and the next call inside the limit is `rate` |
| `decliningTwiceIsANoOpTheSecondTime` | Contract | declined twice at t1, key holds t0 (t0 + 9.9 refused) |
| `declineAfterTheWrapperReturnedStillRefundsAndEmitsNothing` | Contract | handler keeps `call`; late decline records/emits nothing and a call 5 s after t1 is accepted |
| `stageFiveReadsTheClockExactlyOnce` | AC-5 / D-4 | exactly ONE `clock.now()` read per call reaching stage 5 on both-limits, send-only and attempt-only remotes (accepted, attempt-refused, send-refused, declined); ZERO across `guard()` and 50 calls on a remote with neither |
| `defineCopiesTheAttemptLimit` | Contract | `Remotes.define` copies `attemptLimit` field by field; nil when absent; `rateLimit` unaffected |

AC-5's first half (every existing `tests/net/` suite unchanged) is the rest of
the suite under the same `lune run test`: 1023 passed with only this story's
15 red, and no existing file was edited.

**Existing-test exhaustiveness check (Contract asked for it).** None is
exhaustive, so no corrective RED on a DONE story's test:
- `NetContract.REASONS = { identity, shape, range }` is iterated by the checks
  that drive those three rejections; `KNOWN_REASON` (line 68) is consulted
  only at `rejectionNamesTheCheckThatFired` over calls that ARE identity,
  shape or range rejections. No assertion says "no other reason exists".
- `RejectionContract.REASONS` (five) is iterated at lines 371 and 1392; the
  latter asserts every one of the five WAS seen, not that nothing else is.
- `remotes_test.luau:39` -> `NetContract.defineReturnsTheDeclarationAndAllListsIt`
  compares `name`, `args`, `legalPhases` and `rateLimit` one field at a time
  (lines 785-808) and never diffs the whole definition, so a new
  `attemptLimit` field leaves it green. The `attemptLimit` copy is pinned as a
  NEW check in `decline_test.luau` ("Contract (define)") rather than an edit
  to `remotes_test.luau`.
- `Wrapper.Rejection.reason` and `RejectionReporter.Reason` are type unions
  the runtime never enumerates; the only runtime branch on a reason is
  `reason ~= "rate"` in the reporter, which already treats `declined` as
  uncoalesced.

## Handoff: RED -> GREEN

RED, 2026-10-04. Model: dispatched as `test-developer`; the session reports
itself as **Fable 5.1 (`claude-fable-5-1`)** - the planned `fable` row, so the
dispatch override was honoured. The orchestrator records the resolved name.

### Command

    lune run test

(the `unit` gate's own command; ~127 s here under `gates.sh --fast`, ~2 min
plain). Run from the repo root with `~/.rokit/bin` on PATH. Never run two
test or gate runs at once.

### Current failure, verbatim

`bash scripts/gates.sh --fast` on the uncommitted RED tree (tests formatted,
`stylua --check tests` and `selene tests` clean):

    PASS         format (0s, observed 164)
    PASS         lint (1s, observed 164, floor 1)
    PASS         typecheck (3s, observed 28)
    FAIL         unit (127s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 106829)
    FAIL         harness (16s, exit 1) -> .claude/state/gate-logs/harness.log

`unit`: `1023 passed, 15 failed`, all 15 in `tests/net/decline_test.luau`;
every pre-existing test and all 22 of `decline_controls_test.luau` pass.
`harness`: `project-counters: 39 passed, 1 failed`, the one being the "no
stray .luau files" precondition, which clears at the RED commit; AC-7 PASSED
at the new baselines (164/164/28). The 15, each the right failure:

    FAIL decline_test :: AC-1 ...
        AC-1: 4 violation(s) for a declined call against the send limit:
      AC-1: the handler was asked to decline but received call = nil as its third argument; expected a CallControl with a decline function
      AC-1: the first call at t, which the handler declines -> ACCEPTED (returned nil); expected a "declined" rejection
    FAIL decline_test :: AC-2 ...
        AC-2: 5 violation(s) for the attempt floor:
      AC-2: the handler was asked to decline but received call = nil as its third argument; ...
      AC-2: the same player at t + 0.9, inside the attempt floor, after a DECLINED call -> ACCEPTED (returned nil); expected a "rate" rejection
    FAIL decline_test :: AC-3 (limiter) ...
        AC-3 (limiter): RateLimiter.refund is nil; the Contract adds refund(self, playerId, key, acceptedAt) to the limiter and this check is a unit criterion on it
    FAIL decline_test :: AC-3 ...
        AC-3: 4 violation(s) for the send limiter's state after a decline:
      AC-3: the call at t1 = t0 + 10, accepted by the limiter and then declined -> ACCEPTED (returned nil); expected a "declined" rejection
    FAIL decline_test :: AC-4 (telemetry) ...
        AC-4 (telemetry): 16 violation(s) for a declined call's telemetry:
      AC-4 (telemetry): the declined call -> ACCEPTED (returned nil); expected a "declined" rejection
    FAIL decline_test :: AC-4 ...
        AC-4: 12 violation(s) for the declined Rejection:
      AC-4: a remote with a send limit only, declined -> the result is not the Contract's Rejection:
        value: expected table { detail = ""NetTest_ac4_..." declined the call", reason = "declined" }, got nil nil
    FAIL decline_test :: AC-5 ...
        AC-5: 61 violation(s) for the clock reads of stage 5:
      AC-5: both limits, declined at t + SEND -> ACCEPTED (returned nil); expected a "declined" rejection
      AC-5: attempt floor only, accepted at t -> context.clock.now() was read 0 time(s) during the call; ...
    FAIL decline_test :: Contract (decline twice) ...        (call = nil; ACCEPTED, expected "declined")
    FAIL decline_test :: Contract (define) ...
        Contract (define): definition.attemptLimit differs from what was declared:
          value: expected table { minIntervalSeconds = 1 }, got nil nil
    FAIL decline_test :: Contract (empty entry) ...          RateLimiter.refund is nil; ...
    FAIL decline_test :: Contract (fresh call) ...
        Contract (fresh call): call 1's CallControl is nil; expected { decline = function }
    FAIL decline_test :: Contract (late decline) ...
        Contract (late decline): the handler kept {  }; expected two CallControls with a decline function
    FAIL decline_test :: Contract (stale refund) ...         RateLimiter.refund is nil; ...
    FAIL decline_test :: Contract (step 1) ...               (call = nil; ACCEPTED, expected "declined")
    FAIL decline_test :: Contract (unknown refund) ...       RateLimiter.refund is nil; ...

Why these are the right failures: no LOAD FAIL - all five modules exist and
load; the wrapper half fails on "received call = nil as its third argument"
and on the `declined` result never appearing; the limiter half fails on
`RateLimiter.refund is nil`, named by field; the registry half on
`attemptLimit` being nil; AC-5 on an attempt-only remote reading the clock 0
times (no attempt limiter exists today). The failure messages are the
story's to-do list.

### Files touched

- `tests/helpers/DeclineContract.luau` (new) - the checks; AC-1..AC-5 and
  the Contract clauses, mapped in `## Test plan`.
- `tests/helpers/DeclineStubs.luau` (new) - baseline and 20 controls.
- `tests/net/decline_test.luau` (new) - the 15 checks over the real modules.
- `tests/net/decline_controls_test.luau` (new) - 22 control tests.
- `.claude/tests/project-counters.test.sh` - `BASE_FORMAT`/`BASE_LINT`
  160 -> 164 (four test files, no source file; typecheck and both narrow
  counts unchanged at 28/28/8), with the history paragraph. MEASURED by the
  gates: `observed 164`, `observed 164`, `observed 28`. These are also the
  post-GREEN counts: **GREEN adds no file**. Must land in the RED commit.
- `docs/backlog/stories/CHAN-003.md` - `## Contract` callers paragraph
  amended in place (`rate_controls_test.luau` exists; it is simply not a
  caller), `## Test plan`, this section. No acceptance criterion changed.
- No existing test file was edited. No source, no config, no manifest.

### Export shape the tests already pin (fact, not suggestion)

`src/net/Remotes.luau`
- `Remotes.define(name, spec)` accepts `spec.attemptLimit: { minIntervalSeconds: number }?`
  and the returned definition carries `definition.attemptLimit` deep-equal to
  it, `nil` when absent. `rateLimit` unchanged.

`src/net/RateLimiter.luau`
- `limiter:refund(playerId: string, key: string, acceptedAt: number) -> ()`
  as a METHOD (called with `:`), on the table `RateLimiter.new(seconds)`
  returns, beside `allow`, `forget`, `size`. Never raises. Semantics exactly
  the Contract's: restores the key to the value before the acceptance at
  `acceptedAt` when that is the key's LAST acceptance, otherwise no-op;
  "before" = never -> key removed, and an emptied player removed so `size()`
  drops; one level of history (a second refund of the same instant is a
  no-op).

`src/net/Wrapper.luau`
- `Wrapper.guard(definition, context, handler)` calls
  `handler(playerId, args, call)` with `call` a FRESH table per call,
  `typeof(call.decline) == "function"`, called as `call.decline()` (a plain
  field function, NO `self` - the tests call `kept[2].decline()` bare).
- A declined call returns exactly
  `{ reason = "declined", detail = '"<name>" declined the call' }` - two keys,
  no more (`Deep.diff` is exact).
- Stage-5 details, exact: attempt refusal
  `"<name>" is limited to one attempt per <n> s per player`; send refusal
  `"<name>" is limited to one call per <n> s per player` (unchanged). `<n>`
  is the declared `minIntervalSeconds` interpolated as Luau prints it
  (`10`, `1` for the fixtures).
- Order: attempt limiter, then send limiter, then handler; the attempt
  acceptance stands when the send limiter refuses; the send limiter is not
  consulted when the attempt limiter refuses.
- `context.clock.now()` read EXACTLY once per call reaching stage 5 when
  either limiter exists (and that value used for both and for the refund),
  zero times when neither; never at `guard()`. TEL-003's stamp read on a
  rejection is unchanged (the clock-count tests carry no `telemetry`).
- Telemetry on `declined`: `reporter:record(playerId, definition.name,
  "declined", now)` once, then `emit({ event })` once, before returning -
  the same path as every reason. `decline()` after the wrapper has returned
  refunds and records/emits nothing. `decline()` on a remote with no send
  limiter still yields `declined`.

`src/net/RejectionReporter.luau`
- `record` with reason `"declined"` returns an event with `count = 1`,
  uncoalesced - the runtime already does this; GREEN's change is the
  `Reason` union. Session/at/bucket/fields shape as TEL-003 (`bucket = "D1"`).

**Not constrained** (implementer's choice): where the refund history lives
inside the limiter (any representation that satisfies the clauses); how the
wrapper remembers each call's `now` for its control (closure, table, …); the
name of the private type for the per-call control; whether `CallControl` is
exported as a type (tests use `any`); what `decline()` returns (ignored);
what happens on a non-string `playerId` reaching `refund` (never driven);
`describeCaller`/other details. Old two-argument handlers (`Turn`) must
keep working - AC-5's "unchanged" run is the check.

### Passed on arrival

After the fix described below, **nothing** in `decline_test.luau` passes on
arrival (15/15 red). One sub-assertion inside AC-5 is green on arrival for
a wrong reason - the clock count on the both-limits remote reads 1 today
because the attempt floor is ignored - and is earned by the
`readsClockPerLimiter` control, which fails AC-5 and NOTHING ELSE (measured,
pinned in `decline_controls_test.luau`).

A defect found and fixed in RED, recorded here because it is the exact
vacuous-needle case `rules.md` warns about: the first run showed
"Contract (fresh call)" GREEN on arrival. Its loop was
`for i, control in { first, second }` with both values nil - a list literal
of two nils is empty, so the loop ran zero times and the "CallControl is nil"
needle could not fire. Rewritten to index `calls[1..2]`; the test now fails
on arrival with `call 1's CallControl is nil; expected { decline = function }`,
and `neverPassesCall` measurably fails it too (added to its pinned set).

### Negative controls - measured, not claimed

Unlike an import-failing RED, the controls here EXECUTED: `DeclineStubs`
needs no unmerged module. Measured first outside the runner
(`.claude/state/scratch/measure.luau`, a plain `lune run` over the helper),
then pinned as EXACT sets in `decline_controls_test.luau`, then observed
passing under `lune run test` (22/22). Baseline: 0 failures across the 15
CHAN-003 checks + NET-003's 8 + TEL-003's wiring/AC-2/no-telemetry/AC-1-AC-3
+ NET-002 AC-2 + NET-001 order and define/all.

| Control (`DeclineStubs.with`) | Named by | Fails exactly | Primary needle |
|---|---|---|---|
| `neverPassesCall` (today's wrapper) | arrival | AC-1, AC-2, step 1, AC-3, AC-4, AC-4 telemetry, fresh call, decline twice, late decline, AC-5 (10) | `received call = nil as its third argument` |
| `declineNotRefunded` | AC-1 | AC-1, step 1, AC-3, late decline, AC-5 (5) | `with the first call declined -> REJECTED: reason = "rate"` |
| `refundsAttemptToo` | AC-2 / **D-2** | AC-2, step 1 | `inside the attempt floor, after a DECLINED call -> ACCEPTED` |
| `sendBeforeAttempt` | Contract order | AC-2, step 1 | expected attempt sentence |
| `attemptDetailSaysCall` | AC-2 needle | AC-2, step 1 | got `one call per 1 s`, expected `one attempt per 1 s` |
| `consultsSendWhenAttemptRefuses` | Contract step 1 | step 1 | `must not have recorded the refused attempt` |
| `attemptRefundedOnSendRefusal` | Contract step 2 | AC-2 | `that attempt acceptance stands` |
| `readsClockPerLimiter` | AC-5 / **D-4** | AC-5 only | `read 3 time(s) during the call` |
| `declineReturnsNil` | AC-4 | AC-1, AC-2, step 1, AC-3, AC-4, AC-4 telemetry, decline twice, AC-5 (8) | `expected a "declined" rejection` |
| `declinedDetailOmitsName` | AC-4 | AC-4 | exact detail diff |
| `declineWithoutSendLimitIgnored` | Contract | AC-4, AC-5 | attempt-only remote returns nil |
| `sharedCallControl` | Contract | fresh call | `received the SAME CallControl table` |
| `declineAfterReturnIgnored` | Contract | late decline | call at t1 + 5 is rate |
| `declineAfterReturnEmits` | Contract | late decline | `record 1 time(s) and emit 1 time(s)` |
| `declineSkipsTelemetry` | AC-4 | AC-4 telemetry | `record was called 0 time(s)` |
| `defineDropsAttemptLimit` | Contract | AC-2, step 1, AC-5, define (4) | `attemptLimit differs ... got nil` |
| `refundClearsKey` | AC-3 / **D-1** | AC-3, AC-3 limiter, decline twice (3); **AC-1 passes**, as D-1 requires | `a refund that CLEARED the key would accept this -> ACCEPTED` |
| `refundIgnoresAcceptedAt` | **D-3** | AC-3 limiter, stale refund, unknown refund (3) | `a refund of t1 is a no-op` |
| `refundLeavesEmptyPlayer` | Contract | empty entry | `size() is 1; expected 0` |
| `refundRaisesOnUnknown` | Contract | unknown refund | `refund never raises` |

Thresholds here are counts and exact strings, so "candidate range" is the
pinned set itself. GREEN's confirmation: the controls are over stubs and do
not move with the shipped module; what GREEN confirms is that
`decline_test.luau` goes 15/15 green with no edit to any test, and then
GATES runs D-1..D-4 against the real source.

### Deferred verifications - DECLINED in RED, in those words

D-1, D-2, D-3 and D-4 each mutate the real implementation, which does not
exist in RED. I did not run them and do not claim them. The stub analogues
above show the checks discriminate; the real probes are GATES's. Which test
must go red under each (`scripts/mutate.sh` on the file named, run
`lune run test`):
- **D-1** (`refund` sets the key to nil, `src/net/RateLimiter.luau`): red -
  `decline_test :: AC-3: after an acceptance at t0 ...` and
  `AC-3 (limiter)` and `Contract (decline twice)`; `AC-1` MUST stay green.
- **D-2** (`decline` refunds the attempt limiter too, `src/net/Wrapper.luau`):
  red - `AC-2: on a remote declaring attemptLimit ...` and `Contract (step 1)`.
- **D-3** (the `acceptedAt == last` guard removed in `refund`): red -
  `Contract (stale refund)`, plus `AC-3 (limiter)` and `Contract (unknown refund)`.
- **D-4** (`context.clock.now()` read per limiter in stage 5): red -
  `AC-5: a call reaching stage 5 reads context.clock.now() exactly once ...`
  with `read 2 time(s)` (or 3 if the refund reads it again), and nothing else.

### Timings

All local, this machine, 2026-10-04: `lune run test` 1038 tests in ~2 min
plain and 127 s under the `unit` gate; the new files add no measurable time
(the controls run 20 bundles x 15 checks in well under a second - the
scratch measurement runs in ~1 s). No test here carries a timeout: the runner
has none, and nothing sleeps. No CI measurement exists for this story yet.

### Discoveries that bear on GREEN

1. **AC-3 through the wrapper sets the clock BACKWARDS.** With a 10 s send
   limit, t1 must be >= t0 + 10 to be accepted, so "a call at t0 + 10 - eps
   is still refused" can only be observed by setting `Clock.manual` back to
   109.9 after the decline at 110. The limiter compares numbers and
   `Clock.set` is documented as free to move backwards for test setup; the
   same property is pinned on `RateLimiter.refund` directly with plain
   numbers. If the PO would rather the wrapper-level AC-3 stay monotonic,
   the only monotonic observable is "the refund happened at all" (AC-1 /
   the late-decline check), and clear-vs-restore is then the limiter-level
   test's alone. I kept the AC's literal reading. Flagged, not amended.
2. The `decline()` field is a plain function (`call.decline()`), per the
   Contract's `CallControl = { decline: () -> () }`. A method (`call:decline()`)
   would also work with these tests only if it ignores `self`; do not rely
   on that.
3. `RejectionReporter` needs only its `Reason` union widened; the runtime
   path already counts `declined` once and never coalesces it.
4. The handler is NOT pcall-wrapped by the wrapper (NET-001); the tests'
   declining handler guards against a nil control itself so that today's
   failure is a readable violation rather than a raise. A GREEN that passes
   `call` makes that guard inert.
5. Counters: GREEN adds **no** file. If GREEN finds it needs one, the
   counters are a RED change (`.claude/tests/**`), so stop and say so.

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

### Return 1: GREEN → RED (2026-10-04)

**Which test.** `tests/net/turn_remote_controls_test.luau`, *"control: a
definition carrying attemptLimit = 3 fails exactly the attempt-limit check"*
(PROC-005, DONE). It sets `definition.attemptLimit = 3` after
`Remotes.define`, then asserts that the Turn contract fires exactly
`declaresNoAttemptLimit` and nothing else.

**What is wrong with it.** It held only while the wrapper ignored the field:

- `3` is a bare number, not the `RateLimit` (`{ minIntervalSeconds }`) that
  this story's Contract and `Remotes.RateLimit` type give `attemptLimit`. Now
  that the wrapper reads the field, `guard()` raises on it, and every check
  that guards the definition fires.
- Even a well-formed floor can change Turn's own rate checks, so "exactly the
  attempt-limit check" depends on the floor sitting below every call gap those
  checks use.

The control's intent is that a Turn definition carrying an attempt limit is
caught by the attempt-limit check alone, and that intent is still right. Only
its input is malformed. RED's existing-test review missed it because, in RED,
the field had no effect and the control passed.

**How it was found.** GREEN's `lune run test`: `1037 passed, 1 failed`:

    FAIL tests/net/turn_remote_controls_test.luau :: control: a definition carrying attemptLimit = 3 fails exactly the attempt-limit check
      declaresAttemptLimit fires { declaresNoAttemptLimit, malformedCallsAreRejectedBeforeTheHandler, secondCallInsideTheTurnRateLimitIsRejectedForRate, wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting, wellFormedCallOutOfRoundIsRejectedForPhase }, expected exactly { declaresNoAttemptLimit }
      ...src\net\Wrapper:148: attempt to index number with 'minIntervalSeconds'

**Reproduced independently by the orchestrator** with a probe of its own
(`.claude/state/scratch/po_attempt_probe.luau`, different values, written
without the feature-developer's script) against GREEN's uncommitted source:

    number attemptLimit: false C:\Users\ryanc\Projects\first-roblox\src\net\Wrapper:148: attempt to index number with 'minIntervalSeconds'
    well-formed 2 s floor: first accepted | second at +1 s rate / "poProbeTable" is limited to one attempt per 2 s per player

The first line shows a bare-number `attemptLimit` raising. The second shows a
well-formed floor really refusing a call the send limit alone would allow.
That is the Contract's stage-5 rule working, and it is why the control's input
must be chosen against Turn's call gaps. The source is right, and "make the
wrapper ignore a non-table `attemptLimit`" would shape production code around
a malformed test input. GREEN declined that, correctly.

**What it should assert now.** The test-developer's remit is this one control,
and nothing else:

- a **well-formed** `attemptLimit` (`{ minIntervalSeconds = <n> }`);
- the expected fired set **re-measured** against GREEN's real wrapper: either
  exactly `declaresNoAttemptLimit`, with `n` below every call gap in Turn's
  checks, or a wider set with each extra check named and justified;
- a name that no longer says `= 3`.

**What earns it.** Owed by RED, pasted below this line: a `scripts/mutate.sh`
probe of the specific behaviour the corrected control pins. The corrected
assertion will pass on arrival, because the implementation exists.

*RED (return), 2026-10-04, `test-developer` resolved to `claude-fable-5-1`
(Fable 5.1, the planned `fable` row; the dispatch named no override).*

**The one change.** `tests/net/turn_remote_controls_test.luau`: the `Edits`
field `attemptLimit` is typed `{ minIntervalSeconds: number }?` instead of
`number?`, and the control is now

    ["control: a definition carrying a well-formed attemptLimit below every call gap fails exactly the attempt-limit check"]
        declare("declaresAttemptLimit", { attemptLimit = { minIntervalSeconds = Contract.EPSILON / 2 } })
        expected exactly { declaresNoAttemptLimit }

`declare` still assigns the field after `Remotes.define`, as before. No other
test file changed.

**Why `n = EPSILON / 2` (= 0.05 s).** The only Turn check that makes more than
one call reaching stage 5 through a single guard is the AC-3 rate check:
calls at `t`, `t + rate - EPSILON`, `t + rate` (rate = `turn_rate_limit_seconds`
= 1, EPSILON = 0.1). Under the Contract's stage-5 order the attempt floor runs
first and is never refunded, so the second call is RECORDED by the attempt
limiter even though the send limiter refuses it, and the third call is only
EPSILON after the floor's last acceptance. The floor therefore has to sit
strictly below EPSILON; `EPSILON` itself fails on the float `11 - 10.9 <
0.1`. Every other check makes one call per guard (positive control, one guard
per payload) or is rejected before stage 5 (malformed, out of phase), so no
other gap exists. Expressed as `Contract.EPSILON / 2` so it follows the fixture
rather than a literal.

**Measured fired sets against GREEN's uncommitted wrapper** (probe
`.claude/state/scratch/chan003_red2_measure_attempt_floor.luau`, the real
`Remotes.define` + `TurnRemoteContract.failures`, outside the runner):

    rate = 1 EPSILON = 0.1
    n = 3      fires: { declaresNoAttemptLimit, secondCallInsideTheTurnRateLimitIsRejectedForRate }
    n = 1      fires: { declaresNoAttemptLimit }
    n = 0.5    fires: { declaresNoAttemptLimit, secondCallInsideTheTurnRateLimitIsRejectedForRate }
    n = 0.2    fires: { declaresNoAttemptLimit, secondCallInsideTheTurnRateLimitIsRejectedForRate }
    n = 0.1    fires: { declaresNoAttemptLimit, secondCallInsideTheTurnRateLimitIsRejectedForRate }
    n = 0.05   fires: { declaresNoAttemptLimit }
    n = 0.01   fires: { declaresNoAttemptLimit }

`n = 1` is quiet only by coincidence - the floor equals the send limit, so
the floor refuses the second call (reason `rate`, which the check accepts
without reading the detail) and records nothing, leaving the third call
exactly one floor after the first. That is not "below every call gap", so it
was not chosen. Before the fix, the bare `3` fired all five definition-guarding
checks because `guard()` raised (GREEN's output above); after it, the set is
exactly `{ declaresNoAttemptLimit }`.

**The probe.** One mutation of `src/net/Wrapper.luau`: the attempt limiter is
built with ten times its declared floor (0.05 -> 0.5 s), which puts the floor
the wrapper enforces above the EPSILON gap the control was sized against. The
corrected control goes red with exactly the AC-3 rate check added, and the
message names the attempt sentence - the floor, not the send limit, refused the
third call. Verbatim (`.claude/state/scratch/chan003_red2_mutate.log`):

    === mutate: src/net/Wrapper.luau (1 line(s) changed by s/RateLimiter.new(attemptLimit.minIntervalSeconds)/RateLimiter.new(attemptLimit.minIntervalSeconds * 10)/) ===
      148 - 		then RateLimiter.new(attemptLimit.minIntervalSeconds)
      148 + 		then RateLimiter.new(attemptLimit.minIntervalSeconds * 10)

    === mutate: running lune run test ===
    ...
            [measured] declaresAttemptLimit fires: { 1 = "declaresNoAttemptLimit", 2 = "secondCallInsideTheTurnRateLimitIsRejectedForRate" }
      FAIL  tests/net/turn_remote_controls_test.luau :: control: a definition carrying a well-formed attemptLimit below every call gap fails exactly the attempt-limit check
            declaresAttemptLimit fires { 1 = "declaresNoAttemptLimit", 2 = "secondCallInsideTheTurnRateLimitIsRejectedForRate" }, expected exactly { 1 = "declaresNoAttemptLimit" }:
    declaresNoAttemptLimit: AC-1: Turn.attemptLimit is { minIntervalSeconds = 0.05 }; the Turn remote declares no attempt limit (PO decision 1: attemptLimit == nil)
    secondCallInsideTheTurnRateLimitIsRejectedForRate: AC-3 (rate, turn_rate_limit_seconds = 1) failed in 2 step(s):
      AC-3: the third call at exactly t + 1 -> REJECTED: reason = "rate", detail = ""NetTest_declaresAttemptLimit_2495" is limited to one attempt per 0.05 s per player"
      AC-3: after the third call the handler ran 1 time(s) in total, expected 2
    ...
    1034 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_net_Wrapper.luau.20261004T222209Z.11863.bak) ===

The other three failures under the mutant are this story's own
`tests/net/decline_test.luau` (AC-2, AC-5, Contract step 1), which pin the
declared floor directly; they are listed in the log and are not this control's
evidence.

**Unmutated, with GREEN's source restored** (`lune run test`,
`.claude/state/scratch/chan003_red2_test.log`):

    [measured] declaresAttemptLimit fires: { 1 = "declaresNoAttemptLimit" }
    1038 passed, 0 failed

`stylua --check tests`: exit 0. `selene tests`: 0 errors, 0 warnings, 0 parse
errors. GREEN's source was not touched by this return (the mutation was
restored and verified by `cmp`); GREEN resumes with no source change owed.

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

### PO decisions at PLANNED → RED (2026-10-04)

- **PO-1. Contract precision, not new scope** (`## Contract`, "Semantics pinned
  in PLANNED"):
  - one level of refund history inside `RateLimiter`, with an empty entry
    removed so `size()` stays honest;
  - the stage-5 order and the two exact rate details;
  - `declined` as the result of a decline during the handler;
  - a decline after the wrapper returned still refunds and emits nothing.

  Each follows from the drafted contract's own sentences ("restores the key to
  its value before the acceptance", "may be called after the handler has
  yielded", "reads the clock once") read against the code.
- **PO-2. The caller list was re-run against today's tree.** PROC-005 added the
  `Turn` remote (`GameRemotes.luau`, `TurnRequests.luau`, the turn-remote
  tests) after the list was drafted. `Turn` declares `rateLimit` only, never
  declines, and is out of scope here. AC-5 keeps it unchanged.
- **PO-3. Gate.** `unit` is `required` and `covers src/net/**`;
  `required_gates` stays empty.
- **PO-4. Epic check.** EPIC-06 done-when 4 ("a call its handler declines costs
  the one-second attempt floor but not the ten-second send cooldown") is this
  story's AC-1..AC-3. Its second half (a failed filter is not sent) is
  CHAN-004's. Done-when 1 and 2 are CHAN-001/002, which need no code from this
  story. No gap.
- **PO-5. Deferred verifications D-3 and D-4 added**, the first a wrong
  *guard* rather than a wrong value.

### RED verified by the orchestrator (2026-10-04)

- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), dispatched with
  `model: fable` per the plan row; no override reported.
- `lune run test`, run independently: `1023 passed, 15 failed`, all fifteen in
  `tests/net/decline_test.luau`, each on a missing piece of the contract
  (`RateLimiter.refund is nil`, a handler receiving `call = nil`, no `declined`
  result, `definition.attemptLimit` nil, no attempt-floor clock read). The 22
  controls and every pre-existing test pass.
- **Escalation 1 (the PLANNED callers list was wrong): accepted.**
  `ls tests/net/` shows `rate_controls_test.luau`. PO-2's claim that it "does
  not exist" was the orchestrator's error: the re-grep pattern does not match
  that file, and nothing was checked beyond the grep. RED's in-place amendment
  stands.
- **Escalation 2 (AC-3 through the wrapper needs the clock set backwards):
  reproduced independently and accepted, with no amendment.** If `t1` was
  accepted, then `t1 − t0 ≥ interval`. After the refund, any call at
  `t ≥ t1` has `t − t0 ≥ interval` whether the key was restored to `t0` or
  cleared, so both answers allow it. Under monotonic time the two are
  indistinguishable through the wrapper. `src/shared/Clock.luau:15` documents
  `set` as test-setup-only and allowed to move backwards, so RED's literal
  reading of AC-3 uses the clock as documented. The limiter-level test pins the
  same property with plain numbers. D-1 must turn red in at least one of the
  two.
- RED committed as `b14a88d` with the story at `phase: RED` (counter baselines
  160 → 164). `bash scripts/gates.sh --fast` at `b14a88d`: PASS format (164),
  lint (164), typecheck (28), build, harness (`project-counters: 40 passed, 0
  failed`); FAIL unit (115 s, `1023 passed, 15 failed`, the fifteen above and
  nothing else). Admissible.

### GREEN (2026-10-04) - BLOCKED on a stale PROC-005 control; escalated, not worked around

Model: dispatched as `feature-developer`, resolved to **Opus 5.5
(`claude-opus-5-5`)**, from the session's own model identification. No override
was reported.

**What changed** (the four files the brief named, and no others; no test file
touched; `bash scripts/frozen.sh verify` reports `frozen: OK - 23 path(s)
unchanged`):
- `src/net/RateLimiter.luau`: each key now holds `{ at, before }`, so each
  acceptance keeps the timestamp it overwrote (`NEVER` = `false` when there was
  none). The new `refund(p, k, acceptedAt)` acts only when `last.at ==
  acceptedAt`. It restores `before`, or removes the key, and removes the player
  too if that leaves them with no key. A restored acceptance has `before = nil`
  (history unknown), so refunding it again is a no-op rather than a guess. The
  type gains only `refund`. `allow`, `forget` and `size` behave as before, and
  the timestamp still moves on acceptance alone. The header has a new refund
  paragraph.
- `src/net/Remotes.luau`: `attemptLimit: RateLimit?` on `RemoteSpec` and
  `RemoteDefinition`, copied field by field in `define`.
- `src/net/Wrapper.luau`: `CallControl` is exported, and `Rejection.reason`
  and the private `Reason` gain `"declined"`. A second limiter is built only
  when `attemptLimit` is declared. Stage 5 reads `now` once when either limiter
  exists and zero times when neither does. The attempt limiter runs first, with
  the attempt sentence, and when it refuses the send limiter is not consulted.
  Then the send limiter runs, with its detail unchanged. The handler gets a
  fresh `{ decline }` per call. `decline` is idempotent and refunds only the
  send limiter, at this call's `now`, and only if it accepted. The result is
  `declined` when the handler returns having declined, and it goes through the
  existing telemetry path. The header's check-order entry and a new D18
  paragraph are updated.
- `src/net/RejectionReporter.luau`: `Reason` gains `"declined"`, and the header
  lists it among the uncoalesced reasons.

**`lune run test`, verbatim:** `1037 passed, 1 failed`. All 15 of
`decline_test.luau` pass, and so do all 22 of `decline_controls_test.luau`. The
one failure is in an EXISTING suite:

    FAIL  tests/net/turn_remote_controls_test.luau :: control: a definition carrying attemptLimit = 3 fails exactly the attempt-limit check
        declaresAttemptLimit fires { 1 = "declaresNoAttemptLimit", 2 = "malformedCallsAreRejectedBeforeTheHandler", 3 = "secondCallInsideTheTurnRateLimitIsRejectedForRate", 4 = "wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting", 5 = "wellFormedCallOutOfRoundIsRejectedForPhase" }, expected exactly { 1 = "declaresNoAttemptLimit" }:
    declaresNoAttemptLimit: AC-1: Turn.attemptLimit is 3; the Turn remote declares no attempt limit (PO decision 1: attemptLimit == nil)
    malformedCallsAreRejectedBeforeTheHandler: ...\src\net\Wrapper:148: attempt to index number with 'minIntervalSeconds'
    (the same raise for the other three)

**Why this is a stale test, not a code defect.** PROC-005 wrote this control
before `attemptLimit` meant anything. It assigns `definition.attemptLimit = 3`
after `define`, which is a bare number, not a `RateLimit`. It then pins that
ONLY `declaresNoAttemptLimit` fires. That was true while the wrapper ignored the
field. CHAN-003 makes the field live, so the claim cannot hold:
- with the number `3`, `guard()` indexes `3.minIntervalSeconds` and raises
  (5 checks fire);
- with a well-formed limit it still fails. Measured in
  `.claude/state/scratch/chan003_turn_attempt.luau`, `{ minIntervalSeconds = 3 }`
  and `{ minIntervalSeconds = 0.5 }` each fire 2 checks:
  `declaresNoAttemptLimit` and `secondCallInsideTheTurnRateLimitIsRejectedForRate`.
  The third call at t + 1 is refused by the floor, because the t + 0.9
  attempt's acceptance stands. That is exactly the Contract's step-2
  semantics: a live floor changes Turn's AC-3 behaviour.

Neither result is a defect in this story's code. The only source change that
would turn the control green is to make the wrapper silently ignore a
non-table `attemptLimit`. That would shape production code to fit a malformed
fixture, and it would leave a declared floor silently dead. I did not make that
change. The Contract foresaw this case ("If an existing test pins ... that is a
corrective RED on a DONE story's test ... in `## Regressions` with a probe").
RED's exhaustiveness check covered reason lists and `remotes_test.luau:39`, but
missed this file, which passed in RED only because the field was inert. The
fix belongs to RED (Test Developer). A corrected control needs a well-formed
`attemptLimit`, and its expected set must include the AC-3 rate check, or it
must use a floor that does not bite at t + 1. The correction then needs a
probe.

**Negative controls confirmed against the shipped modules.** The scratch
script `.claude/state/scratch/chan003_confirm.luau` runs the
`decline_controls_test.luau` `DECLINE_CHECKS` (15) and `EARLIER_CHECKS` (15:
NET-003's eight, TEL-003 wiring, AC-2, no-telemetry and AC-1/AC-3, NET-002
AC-2, and NET-001 order and define/all) over the real `src/net` bundle. It
copies the lists from the test's text without editing them. Expected (RED's
baseline row): 0 failures. Measured: `real bundle: 0 of 30 checks failed`. No
divergence. The 20 one-defect controls are stubs and do not move with the
shipped module. All 22 pass under `lune run test`.

**Gates.** `bash scripts/gates.sh --fast` was NOT run: `unit` is known red on
the stale control above, so I ran the static gates directly instead. They were
`stylua --check src` (exit 0), `selene src/net` (0 errors, 0 warnings) and
`luau-lsp analyze` over `src` (no errors). Run `--fast` once the corrective RED
lands. GREEN adds no file, so the counter baselines (164/164/28) are unaffected.
