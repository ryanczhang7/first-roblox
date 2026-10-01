---
id: VIEW-003
title: The public round view carries public facts and a progress bar of exactly two numbers
slug: the-public-round-view-carries-public-fac
epic: EPIC-07
type: feature
status: todo
phase: PLANNED
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

**Oracle partition.**
- AC-1 and AC-5 are **settled** by `mechanics.md` §3.2's "must never show"
  table. Name each assertion after its row.
- AC-2 to AC-4 and AC-6 are **mechanical**.

## Deferred verifications

**D-1. The bar holds its shape.** Use `scripts/mutate.sh` to add a
`byTrack` field to the progress record. AC-1 **must** then fail, naming it. RED
cannot run this. Owner: GATES.

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

Lock coverage: SUPPRESSED by `src/server/round/RoundView.luau` (source), `src/server/session/Session.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

