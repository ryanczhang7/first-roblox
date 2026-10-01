---
id: CHAN-004
title: A preset is filtered and broadcast with its sender and position once per ten seconds
slug: a-preset-is-filtered-and-broadcast-with
epic: EPIC-06
type: feature
status: todo
phase: PLANNED
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
- The filter port's exact shape, and whether filtering is per send, come from
  `CHAN-001`. **Amend this block from its result before RED.**
- `Schema.shape` already rejects unknown keys as `shape` (NET-001). Confirm this
  with a test rather than assuming it, and amend this block if it does not.

**Wiring** into `Session` is `SLICE-006`, not this story.

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

Lock coverage: SUPPRESSED by `src/net/GameRemotes.luau` (source), `src/server/channel/PresetSends.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

