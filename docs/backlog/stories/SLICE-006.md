---
id: SLICE-006
title: The session carries pings, presets and every view, and a scripted round is won by showing
slug: the-session-carries-pings-presets-and-ev
epic: EPIC-08
type: feature
status: todo
phase: PLANNED
branch: story/SLICE-006-the-session-carries-pings-presets-and-ev
depends_on: [SLICE-005, CHAN-004, CHAN-006, VIEW-001, VIEW-002, VIEW-003]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-08`. This story wires the rest of M3's server into `Session`:

- the channel: `PresetSends` (`CHAN-004`) and `Pings` (`CHAN-005`,
  `CHAN-006`);
- the per-player views: `lensFor` (`VIEW-001`) and `turnCuesFor` (`VIEW-002`);
- the public views: `RoundView` and `FacilityView` (`VIEW-003`).

After it, every payload `architecture.md` §9.7 lists is emitted by
`Session.step`, to the right audience, when it changes.

The evidence extends `SLICE-005`'s headless round. The scripted players now play
**as players**. A turner sets a dial only to a setting it has seen pinged by
its helper, and the helper learns the setting only from its own `LensView`. If
the lens, the ping or the routing is broken, the script cannot win.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a running round, when any step changes a player's lens
  contents or turn cues, then that player alone receives a `SendTo` of the
  changed view. A player whose view did not change receives nothing. No
  `Broadcast` ever carries a `LensView` or `TurnCues`.
  *Control:* a session that broadcasts lens views must fail.
- **AC-2** — Given a scripted round in which each turner's only source of a
  setting is a `PingShown` entry from its helper in a broadcast `RoundView`,
  and each helper's only source is its own `LensView`, when the script runs over
  at least 50 seeds at each n in `{4, 5, 6}`, then every round is won.
  *Control:* the same script with pings suppressed (the helper never pings)
  must not win by the script's rules. The turner has no setting to use and does
  not guess, so the round ends `lost / clock`.
- **AC-3** — Given an accepted `PingRequested`, when the step returns, then the
  next `RoundView` broadcast contains it. After `ping_display_seconds`, or after
  its machine commits, it does not. A refused ping sends a `PingRefused` to its
  sender only, and the call is declined.
- **AC-4** — Given a `PresetSent` with a succeeding filter port, when the step
  returns, then one `Broadcast` of kind `PresetShown` carries the sender's
  **stored** position. With a failing filter, only the sender receives
  `PresetFailed`.
- **AC-5** — Given entry into `Round`, when effects are read, then exactly one
  `Broadcast` of kind `FacilityView` is emitted, before any `RoundView` with
  machines.
- **AC-6** — Given any session effect list across a full scripted round, when
  every private payload is inspected, then no `SendTo` addressed to `p` carries
  a required setting of a machine outside `λ(p)`. This is the end-to-end form of
  `VIEW-001`'s property.

## Contract

`src/server/session/Session.luau`, extended.

    SessionState gains: channel: { presets: PresetSends.PresetState, pings: Pings.PingState }
    SessionEvent gains: { kind: "PresetSent", playerId: string, presetId: number, call: Wrapper.CallControl }
                      | { kind: "PingRequested", playerId: string, target: Pings.PingTarget, call: Wrapper.CallControl }
    Session.new gains ports: { filter: PresetSends.Filter, lineOfSight: (Procedure.Vec, Procedure.Vec) -> boolean }
        -- CHANGED signature: Session.new(config, seed, roundId, sessionId, ports)

- **Changed signature: `Session.new` gains `ports`.** Callers are
  `SLICE-003`'s and `SLICE-005`'s tests and `RoundService.server.luau`. RED lists
  them with `rg "Session.new" src tests` and updates them in this RED. They are
  this epic's own tests, not a DONE story from another epic, but each changed
  file is still named in `## Test plan`.
- **Change detection.** A view is sent when it is not deep-equal to the last
  one sent to that audience. `SessionState` keeps the last-sent values. The
  `RoundView` is also sent at least once per whole second while a clock runs.
- **The filter port may yield** in production (`CHAN-001`). `Session.step`
  stays pure because the driver resolves the filter **before** building
  `PresetSent`, and passes the result in. **Amend this block from `CHAN-001`'s
  result:** if filtering must be inside the handler, the event carries the
  filtered text or the failure instead of the port.

**Oracle partition.**
- AC-1 and AC-3 to AC-6 are **mechanical**.
- AC-2 is a **settled** outcome with a control. The script's rules are the
  oracle, and they must be written so that a broken lens makes the script
  unable to act, **not** able to cheat. Review the script against that rule.

## Deferred verifications

**D-1. AC-2 depends on the ping.** Use `scripts/mutate.sh` to make `Pings.shown`
return an empty list. AC-2 **must** then fail. RED cannot run this. Owner:
GATES.

**D-2. AC-2 depends on the lens.** Use `scripts/mutate.sh` to make `lensFor`
return the dependent's class (the direction error). AC-2 **must** then fail,
and AC-6 **must** fail. Owner: GATES.

## Out of scope

- The client (`HUD-*`), and the driver's real ports (`SLICE-007`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-006` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/session/Session.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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

