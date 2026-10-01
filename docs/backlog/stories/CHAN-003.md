---
id: CHAN-003
title: A call its handler declines costs the attempt floor but not the send cooldown
slug: a-call-its-handler-declines-costs-the-at
epic: EPIC-06
type: feature
status: todo
phase: PLANNED
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

Callers, grep-listed 2026-09-30 (`rg -l "Wrapper.guard|\.guard\(" src tests`,
`rg -l RateLimiter src tests`, `rg -l "Remotes.define" src tests`). RED confirms
the list against the tree:

- source: `src/net/Wrapper.luau`, `src/net/RateLimiter.luau`,
  `src/net/RejectionReporter.luau`, `src/net/Remotes.luau`
- tests: `tests/helpers/NetContract.luau`, `NetStubs.luau`, `PhaseContract.luau`,
  `PhaseStubs.luau`, `RateContract.luau`, `RateStubs.luau`,
  `RejectionContract.luau`, `RejectionStubs.luau`;
  `tests/net/wrapper_test.luau`, `remotes_test.luau`, `rate_test.luau`,
  `rate_controls_test.luau`, `rejection_test.luau`, `rejection_controls_test.luau`
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

Lock coverage: SUPPRESSED by `src/net/RateLimiter.luau` (source), `src/net/RejectionReporter.luau` (source), `src/net/Remotes.luau` (source) (+3 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

