---
id: SLICE-005
title: The session runs the facility and the Procedure, and scripted turns win or lose a round
slug: the-session-runs-the-facility-and-the-pr
epic: EPIC-08
type: feature
status: in-progress
phase: RED
branch: story/SLICE-005-the-session-runs-the-facility-and-the-pr
depends_on: [SLICE-003, GEN-004, PROC-003, PROC-005]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-08`. EPIC-04 built the facility generator and EPIC-05 built the
Procedure, each as pure modules tested alone. This story composes them into
`Session` (`architecture.md` §9.2, D22):

- When seats are dealt, the facility is generated. On failure, the round
  resolves `no_contest / generation_failed`.
- Entering `Round` starts the Procedure and places every player in
  `spawn_room`.
- `PositionsSampled` stores samples. They are unfiltered until `VIEW-004`.
- A `TurnRequested` from the guarded `Turn` remote goes through
  `TurnRequests.handle`. The turner gets a private `TurnResult`.
- On every `Tick`, the Procedure is advanced. Its outcome is fed to the phase
  machine as `RoundResolved` **in the same step**.

The evidence is a **headless round**. Four scripted players, teleported by
test code to the right rooms, win a generated facility through `Session.step`
alone. A second script loses it to instability.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given four joined players and the lobby elapsed, when the session
  steps into `Round`, then it holds a facility equal to
  `Generator.generate(assignment, seed)` for the round seed, and a Procedure
  started at that step's `now` with that seed. It also emits one `Placed` per
  player at `spawn_room`'s centre.
- **AC-2** — Given a generator that fails every attempt (an injected
  predicate), when the session steps into `Round`, then in the same step the
  phase machine records `RoundResolved{ no_contest, generation_failed }` and
  moves to `Resolution`.
- **AC-3** — Given a running round, when a `TurnRequested` arrives, then the
  Procedure sees the caller's id, the requested machine and setting, and the
  **stored** positions. The caller alone receives a `SendTo` of kind
  `TurnResult` carrying `TurnRequests.reply(result)`.
- **AC-4** — Given a script that, for each step in canonical order, places the
  step's helper and turner at the machine and turns it to its required setting,
  when it runs through `Session.step` over at least 50 seeds at each n in
  `{4, 5, 6}`, then every round ends `won / procedure_complete`. The phase
  machine records it **in the step that takes the completing `TurnRequested`**
  and moves to `Resolution` there, and the next `Tick` moves it to `Post`.
  *Control:* the same script with turns sent from the spawn room, out of reach,
  must never win. Every turn is refused, and the round ends `lost / clock`.
- **AC-5** — Given a script that turns the live step to a wrong setting
  `instability_max` times, when it runs, then the round ends `lost /
  instability`, recorded by the phase machine **in the step that takes the
  `instability_max`-th wrong `TurnRequested`**. After each of the first
  `instability_max − 1` wrong turns, the `RoundView` broadcast on the next
  `Tick` has a `secondsLeft` lower by `instability_clock_penalty_seconds` per
  point charged than an unpenalised round's at the same `now`.
- **AC-6** — Given a round that only the clock ends, when ticks reach the
  Procedure's deadline, then the session records `lost / clock` on the first
  tick at or after `Procedure.deadline`. With no instability charged, that tick
  is also the phase machine's backstop tick, so the criterion is asserted as
  well with `k` points charged for each `k` in `1 … instability_max − 1` and
  nothing else happening: the round resolves `lost / clock` on the tick at
  `startedAt + roundSeconds − k × instability_clock_penalty_seconds`, the tick
  one second earlier is still `Round`, and the backstop's time is never
  reached.

## Contract

Pinned in PLANNED, 2026-10-02. **RED may amend any block in place, with the
reason written beside it; GREEN builds what the amended block says.**

### C-1. Module and types

`src/server/session/Session.luau`, extended. No new source module.

    export type SessionOptions = {
        tuning: MechanicsTuning.MechanicsTuning?,           -- default: the MechanicsTuning module
        generatorPredicate: ((Generator.Facility) -> string?)?,  -- default: nil (production)
    }

    SessionState gains: facility: Generator.Facility?,
                        procedure: Procedure.ProcedureState?,
                        positions: { [string]: Procedure.Vec },     -- {} from new
                        tuning: MechanicsTuning.MechanicsTuning,
                        generatorPredicate: ((Generator.Facility) -> string?)?
    SessionEvent = PhaseMachine.Event
                 | { kind: "PositionsSampled", samples: { [string]: Procedure.Vec } }
                 | { kind: "TurnRequested", playerId: string, args: { machine: number, setting: number } }
    SessionEffect gains: { kind: "SendTo", playerId: string, payloadKind: "TurnResult", payload: TurnRequests.TurnReply }
                       | { kind: "Placed", playerId: string, position: Procedure.Vec }

    Session.new(config, seed, roundId, sessionId, options: SessionOptions?) -> SessionState
    Session.step(state, event, now) -> (SessionState, { SessionEffect })   -- unchanged

`options` is an **optional fifth parameter** - additive; every existing call
passes four. It is the test seam for AC-2 (the predicate is handed to
`Generator.generate` as its `predicateOverride`, exactly as GEN-004 built that
seam) and for a shortened tuning if RED wants one. `stagesOverride` is never
passed.

### C-2. Entering `Round` (AC-1, AC-2)

On the step that deals (SLICE-003's `AssignSeats` → `Ring.assign` →
`SeatsAssigned`), immediately after `SeatsAssigned` has moved the machine to
`Round`, at the same `now`:

1. `result = Generator.generate(dealt, deal.seed, state.tuning, state.generatorPredicate)`
   - `deal.seed` is **the `AssignSeats` effect's seed**, the same one the ring
   was dealt from, never `round.seed`.
2. On `{ kind = "facility" }`: `facility = result.facility`;
   `procedure = Procedure.start(facility, now, state.tuning, deal.seed, round.config.roundSeconds)`.
   The Procedure's `roundSeconds` is **the injected config's**, so the
   Procedure's deadline and the machine's backstop share one duration (D11).
   Then `positions` is **replaced** by `{ [p] = centre }` for every seated
   player, and one `Placed { playerId = p, position = centre }` is emitted per
   seated player in the ring's seat order (`dealt.players`).
   `centre` is the spawn room's centre per `Machines.luau`'s header:
   `{ x = (column − 1) × room_pitch_studs, y = 0, z = (row − 1) × room_pitch_studs }`
   for the room in `facility.layout.rooms` whose `id == facility.spawnRoom`.
   Each `Placed` gets its own table (no aliasing between effects or with
   `state.positions`).
3. On `{ kind = "failed" }`: `facility` and `procedure` stay nil, no `Placed`
   is emitted, and the machine is stepped a third time, at the same `now`, with
   `RoundResolved{ outcome = { result = "no_contest", reason = "generation_failed" } }`.
   It moves to `Resolution`. Seat views are **still** sent (the ring was dealt;
   SLICE-003's rule is unconditional), and the `RoundView` broadcast reads
   `Resolution`.

### C-3. The within-step order (all events)

1. `PositionsSampled` and `TurnRequested` are **never forwarded** to
   `PhaseMachine.step`. Every other event is, first, exactly as SLICE-003 does
   (including the deal of C-2).
2. `PositionsSampled`: `positions` is **replaced** by a copy of `samples` (not
   merged), in every phase. It emits nothing - no `RoundView` either.
3. `TurnRequested` with `procedure ~= nil` and the machine in `Round`:
   `TurnRequests.handle(procedure, assignment, event.playerId, event.args, now, state.positions)`.
   The new procedure is stored, and one `SendTo { playerId = event.playerId,
   payloadKind = "TurnResult", payload = TurnRequests.reply(result) }` is
   emitted. Otherwise (no procedure, or any other phase) the event is ignored:
   state returned unchanged, effects `{}`.
4. `Tick` with `procedure ~= nil` and `procedure.outcome == nil` - **after**
   the Tick has been applied to the machine: `Procedure.tick(procedure,
   assignment, now, state.positions)`, store the result.
5. **Routing.** If, in this step, `procedure.outcome` went from nil to non-nil
   - by a Tick (4) **or by a turn (3)** - step the machine with
   `RoundResolved{ outcome = procedure.outcome }` at the same `now`, and pass
   its effects through. Outside `Round` the machine ignores it, which is the
   correct result when the backstop or quorum resolved the round first in this
   same step.

The Tick goes to the machine **before** the Procedure. Reversing it would feed
`RoundResolved` and then step the resolved machine with the Tick, moving it on
to `Post` - and SLICE-003's "clock ends the Round" step would fail.

**Clearing.** On entering `Lobby`, `facility` and `procedure` are cleared
together with `assignment`. `positions` is not cleared: it is the driver's last
sample, not round state.

### C-4. Effect order within one step

Pass-through (every machine step's effects, in emission order, `AssignSeats`
removed) → `Placed` in seat order → `SendTo`/`SeatView` in seat order →
`SendTo`/`TurnResult` → at most one `Broadcast`/`RoundView`, last.

`Placed` sits where SLICE-003's order check counts a non-`SendTo`,
non-`Broadcast` effect - before the first `SendTo` - so that check holds
unchanged.

### C-5. `secondsLeft` reads the Procedure's deadline (AC-5)

In `Round` with `procedure ~= nil`, `RoundView.secondsLeft =
math.ceil(Procedure.deadline(procedure) − now)`. Everywhere else, the
SLICE-003 formula is unchanged. With no penalty these are equal on every tick,
because `procedure.startedAt == round.phaseEnteredAt`, so SLICE-003's AC-4
payload check holds unchanged. `VIEW-003` will move this into `RoundView.luau`;
until then this is "whatever `RoundView` exists". The broadcast **trigger** is
unchanged: a `TurnRequested` broadcasts only if the phase changed, so a penalty
shows on the next `Tick`'s `RoundView`, which is what AC-5 reads.

### C-6. SLICE-003's helper changes, once, in RED

`SessionContract.passThroughOf` today returns *every effect that is neither a
`SendTo` nor a `Broadcast`*, and AC-5 of SLICE-003 compares that deep-equal to
the machine's effects. A `Placed` effect would therefore fail SLICE-003's
pass-through check on every dealing step. **RED changes `passThroughOf` to keep
only the phase machine's own effect kinds - `Emit`, `PromptRematch`,
`ComputeTrace` and `AssignSeats`** (the last so the existing control "passes
AssignSeats through as well" still fails). No other SLICE-003 assertion
changes. This supersedes the planning note "SLICE-003's tests must still pass
unchanged": they pass with this one helper change and no other, and the
changed helper is earned by D-4.

### C-7. The script (AC-4, AC-5, AC-6)

`tests/helpers/ScriptedRound.luau`, shared with `SLICE-006`. It is a **test
oracle and may read the secret**: it reads the steps, helpers and turners
through `state.facility`, `state.assignment` and `Ring` (turner = the holder of
the machine's key class; helper = `Ring.supplierOf(assignment, turner)`), and
machine positions through `Machines.positionOf`. It drives the session **only
through `Session.step`**: it "places" a player by stepping a
`PositionsSampled` whose sample puts them at the machine's position, and turns
by stepping a `TurnRequested`. It never writes `state` directly.

- **Canonical order** is `Par`'s: ordinary steps interleaved `T1[1], T2[1],
  T1[2], T2[2], …`, the rest of the longer track in order, then the finale as
  one unit - both finale turners turned at the same `now` (well inside
  `simultaneous_window_seconds`).
- **Time.** The script advances `now` and steps a `Tick` at least once per
  scripted second it spends. A winning script finishes far inside the clock.
  The AC-4 control may tick coarsely to stay inside the unit gate's budget,
  provided a tick lands exactly on the deadline.
- **Wrong turns (AC-5) are spaced.** A rejected machine refuses further turns
  as `resetting` for `actuation_reset_seconds` (3 s) after the rejection. The
  script spaces wrong turns on the same machine at least that far apart, or a
  "wrong turn" is a free refusal and instability never reaches the max. A wrong
  setting is any setting in `1 … dial_settings` other than the required one.
- **Outcome is read from the machine** (`state.round.outcome`,
  `state.round.phase`), not only from `state.procedure`.

### C-8. Baselines RED may read out rather than re-derive

Measured in PLANNED on `main` at `906f3b7`:

- `room_pitch_studs` 64, so every machine sits `16` studs from its room centre
  on each axis, `≈ 22.6` studs horizontally, and `turn_range_studs` is `10`.
  **No machine is in reach from any room's centre, the spawn room's included.**
  This is what makes the AC-4 control's "every turn is refused" hold.
- `Generator.generate` returned a facility for **900 of 900** (seeds 1-300 at
  n = 4, 5, 6, real `MechanicsTuning`, ring from `Rng.fromSeed(seed)`), and for
  SLICE-003's `SEED` 20261002 at n = 6. SLICE-003's lifecycle will not hit a
  generation failure by accident.
- `instability_max` 5, `instability_per_wrong_value` 1,
  `instability_clock_penalty_seconds` 20, `instability_blackout_threshold` 2,
  `actuation_reset_seconds` 3, `dial_settings` 4,
  `simultaneous_window_seconds` 5, `round_seconds` 420.

### C-9. Callers of every changed signature

Checked with `rg -n "Session\.new|S\.new\b|passThroughOf" src tests lune` on
`906f3b7`:

| Changed | Caller | Effect of the change |
|---|---|---|
| `Session.new` (optional 5th param) | `tests/helpers/SessionContract.luau:228`, `:514` (`pcall(S.new, …)` with four args) | none - additive |
| `Session.new` | `tests/server/session_controls_test.luau:87` (the reference stand-in's own `S.new`) | none - a separate implementation |
| `SessionContract.passThroughOf` (C-6) | `tests/helpers/SessionContract.luau:1193` (SLICE-003 AC-5 check) - its only caller | the check now ignores `Placed`/`TurnResult`; D-4 earns it |

No source file requires `Session` today. RED's handoff states this list was
checked against the tree.

### C-10. Oracle partition

- **Mechanical** (exact pinning against the pure modules' own outputs): AC-1,
  AC-2, AC-3, AC-6, and C-3/C-4/C-5.
- **Settled** (a scripted outcome with a control that must fail): AC-4, AC-5.
- No criterion needs an invented metric.

## Deferred verifications

**D-1. The same-step routing on a Tick is real.** With `scripts/mutate.sh`,
make the Tick path skip feeding `RoundResolved` (so the outcome is fed on no
later tick either, and only the backstop resolves the round). AC-6's
penalised cases **must** fail; the unpenalised case is expected to stay green
(it is the backstop's tick too). RED cannot run this. Owner: GATES.

**D-2. The same-step routing on a turn is real.** With `scripts/mutate.sh`,
make the `TurnRequested` path skip feeding `RoundResolved`. AC-4's and AC-5's
"in the step that takes the … `TurnRequested`" assertions **must** fail. RED
cannot run this. Owner: GATES.

**D-3. `secondsLeft` reads the Procedure.** With `scripts/mutate.sh`, make the
`Round` branch of the `RoundView` use the config's `roundSeconds` instead of
`Procedure.deadline`. AC-5's `secondsLeft` assertion **must** fail, and
SLICE-003's AC-4 payload check must stay green. RED cannot run this. Owner:
GATES.

**D-4. The narrowed `passThroughOf` still discriminates.** With
`scripts/mutate.sh`, make `Session` drop the machine's `Emit` effects.
SLICE-003's AC-5 pass-through check **must** still fail. RED cannot run this
(no Session emits `Placed` yet). Owner: GATES.

## Out of scope

- Pings, presets and the per-player views (`SLICE-006`).
- Position plausibility (`VIEW-004`).
- The real teleport and position sampling (`SLICE-007`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-005` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/session/Session.luau` (source), `tests/helpers/ScriptedRound.luau` (test), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- PLANNED → RED orchestration - `lead-po` - `claude-opus-5-5` (session model). 2026-10-02.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1). The orchestrator passed
  `model: fable` explicitly in the Agent dispatch; the agent self-identified as
  Fable 5.1. 2026-10-02.

## Test plan

Written in RED, 2026-10-02 (test-developer). All unit level, over the pure
`Session.step` - the contract lives there and nothing above it exists yet.
Four files, the SLICE-003 arrangement: a contract helper that holds the checks
and an independent oracle, a thin test file that applies them to the real
module through `pcall(require, ...)`, a controls file where every check is
executed in RED against a reference stand-in and stand-ins wrong in exactly
one way, and - new for this story - a scripted-player helper shared with
SLICE-006.

| File | Role |
|---|---|
| `tests/helpers/ScriptedRound.luau` | C-7. A driver (`new/join/deal/start`, `step`, `tick`, `tickAt`, `tickEverySecondTo`, `place`, `turn`) that moves a session ONLY through `Session.step`, readers for the secret (`machineOf`, `turnerOf`, `helperOf`, `machinePosition`, `spawnCentre`, `canonicalOrder`, `wrongSetting`), and three scripts: `win` / `winFromSpawn` (AC-4 and its control), `loseByInstability` (AC-5, with an unpenalised twin ticked in lockstep), `clockOut(k)` (AC-6). No assertions; plain errors on preconditions. |
| `tests/helpers/SessionRoundContract.luau` | The 16 checks, the oracle (`run`: the Contract's C-2/C-3 composition of `PhaseMachine`, `Ring`, `Generator`, `Procedure`, `TurnRequests` stepped beside the subject, plan events may be functions of the oracle's state so they can read the facility), two plans (`lifecycle`, `generationFailure`), `CHECKS`, `failures`. |
| `tests/server/session_round_test.luau` | 16 tests, one per check, against the real `src/server/session/Session.luau`. |
| `tests/server/session_round_controls_test.luau` | Reference stand-in (passes the new battery AND SLICE-003's), two fixtures tests re-measuring C-8's baselines, 22 single-defect controls pinning the exact set of checks each fires, two purity controls, a missing-function control. |
| `tests/helpers/SessionContract.luau` | C-6: `passThroughOf` narrowed to `Emit`, `PromptRematch`, `ComputeTrace`, `AssignSeats`. Nothing else in SLICE-003's files changed. |

Oracle partition honoured as C-10: AC-1, AC-2, AC-3, AC-6, C-3/C-4/C-5 are
compared deep-equal to the pure modules' own outputs on the same inputs
(never hand-copied); AC-4 and AC-5 are scripted outcomes, each with a
control that must fail (`neverWinsFromTheSpawnRoom...`; the `secondsLeftFromConfig`
and `skipsRoutingOnTurn` stand-ins). Every duration, count and penalty is
read from `RoundConfig.fromTuning(Tuning)` and `MechanicsTuning`.

| Check (`SessionRoundContract.*`) | AC | What it falsifies |
|---|---|---|
| `newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions` | C-1 | `new` holds `facility = nil`, `procedure = nil`, `positions = {}`; accepts a 5th `options` without raising and with the same round |
| `roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep` | C-3 | after every step of both plans the five state fields deep-equal the oracle's |
| `generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep` | AC-1 | on both deals: `facility == Generator.generate(dealt, effect.seed, tuning).facility`, `procedure == Procedure.start(facility, now, tuning, effect.seed, config.roundSeconds)`; the two seeds differ |
| `placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder` | AC-1 | one `Placed` per dealt player, seat order, at `((col-1)*pitch, 0, (row-1)*pitch)` of `facility.spawnRoom`, key set `{kind, playerId, position}`, fresh tables (no two Placed share one, none is `state.positions[p]`); `state.positions == {[p] = centre}`; no Placed elsewhere |
| `resolvesAFailedGenerationAsNoContestInTheDealingStep` | AC-2 | predicate refusing all: same step ends Resolution / `{no_contest, generation_failed}`, no facility/procedure/Placed, every SeatView still sent, RoundView reads Resolution / nil, machine effects = three machine steps; later turn ignored; next Tick → Post |
| `handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone` | AC-3 | each of five turns (committed, wrong_setting, not_key_holder, unknown_machine, out_of_reach-after-an-omitting-sample): `procedure == TurnRequests.handle(..., STORED positions)`, exactly one SendTo, to the caller, `payloadKind = "TurnResult"`, key set `{kind, payload, payloadKind, playerId}`, payload `== TurnRequests.reply(result)`, no Placed, Broadcast iff phase changed |
| `storesPositionSamplesAsAReplacingCopyAndEmitsNothing` | C-3 | five samples (Lobby, Round x3, Resolution): `positions` deep-equals the samples, not `rawequal`, effects `{}`, other fields unchanged |
| `ignoresATurnOutsideRoundOrWithoutAProcedure` | C-3 | turns in Lobby, Resolution, Post, new Lobby, Resolution-after-failure: state deep-equal, effects `{}` |
| `clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions` | C-3 | both held before Post → Lobby, nil after; positions kept |
| `ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast` | C-4 | rank order pass-through < Placed < SeatView < TurnResult < Broadcast on every step; Placed in seat order; ≤ 1 Broadcast, last; no other kinds |
| `secondsLeftReadsTheProcedureDeadlineInRound` | C-5 | every Round RoundView: `secondsLeft == ceil(Procedure.deadline(procedure) - now)`; ≥ 2 of them differ from the config formula by the penalty |
| `winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn` | AC-4 | 50 seeds x n ∈ {4,5,6}: every reply committed (first finale machine: armed), completing turn's step is Resolution / won procedure_complete, next Tick Post, that step's effects end `..., TurnResult, Broadcast` |
| `neverWinsFromTheSpawnRoomAndLosesToTheClock` | AC-4 control | same 150 rounds from the spawn centre: every reply refused/out_of_reach, undecided after, Round at deadline-1, Resolution / lost clock at the deadline tick |
| `losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView` | AC-5 | seeds {1,2,3} x n ∈ {4,5,6}: 5 wrong turns 4 s apart; turns 1-4 rejected/wrong_setting, still Round, next Tick's `secondsLeft == twin.secondsLeft - j*20`; 5th: Resolution / lost instability in that step |
| `losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel` | AC-6 | k = 0..4, seeds {1,2}, n = 4: leaves Round exactly at `startedAt + 420 - 20k`, Round a second before, phase at that tick is Resolution (not Post), outcome lost/clock, backstop tick never reached for k ≥ 1 |
| `stepMutatesNeitherStateNorEventOnRoundEvents` | Contract | deep snapshots of state and event before each step deep-equal afterwards |

Edges covered: empty positions map at `new`; a sample before anyone joined; a
stranger's turn; an unknown machine id; a sample that omits a player (replace
vs merge); a fractional tick; a seated leave mid-round (positions untouched);
turns in every non-Round phase; the k = 0 case where the Procedure and the
backstop coincide; `generationFailed` with seat views still sent. Out of
scope (pings, presets, per-player views, plausibility) is not exercised: a
`PositionsSampled` is stored unfiltered, as C-3 says.

## Handoff: RED -> GREEN

RED, 2026-10-02, test-developer. Dispatched model: the dispatch did not state an
override; the agent definition says `opus`, this session identifies as Fable
5.1 (`claude-fable-5-1`) - the planned `fable` row, resolved by whatever the
orchestrator passed. The orchestrator records the resolved name.

### Command

    lune run test

The runner has no per-file filter (`lune/test.luau` is `config`, frozen). The
new files are `tests/server/session_round_test.luau` (the target) and
`tests/server/session_round_controls_test.luau` (must stay green). Wall time,
measured locally: controls 6.5 s (about 25 full battery runs), round_test
0.15 s in RED (every script stops at "no facility"), expected ~0.3 s in GREEN
(one battery run); SLICE-003's two files 0.27 s. The whole suite takes about
5 minutes here; the new files add under 7 s to it.

### The failure, verbatim (trimmed to the first line of each message)

    FAIL  tests/server/session_round_test :: AC-1: on each of two deals state.facility deep-equals Generator.generate(...)...
          AC-1: the dealing step must hold Generator.generate(dealt, effect.seed) and Procedure.start(facility, now, tuning, effect.seed, roundSeconds):
          deal 1 ("DEAL 1"): state.facility is nil after the dealing step
          deal 1 ("DEAL 1"): state.procedure is nil after the dealing step
    FAIL  ... AC-1: the dealing step emits one Placed { playerId, position } per seated player ...
          "DEAL 1": 0 Placed effect(s), expected 4 (one per seated player) at the spawn centre { x = 0, y = 0, z = 64 }
          "DEAL 1": state.positions after the deal is nil, expected every seated player at the centre { x = 0, y = 0, z = 64 }
    FAIL  ... AC-2: with options.generatorPredicate refusing every attempt ...
          after the dealing step the phase is "Round", expected Resolution in the same step
          state.round.outcome is nil, expected { no_contest, generation_failed }
    FAIL  ... AC-3: a TurnRequested in Round is TurnRequests.handle(..., STORED positions) ...
          "correct turn on T1[1] (committed)": state.procedure is not TurnRequests.handle(procedure, assignment, "dan", args, 62, state.positions) - the oracle's result was { kind = "committed", machineId = 14 }
          "correct turn on T1[1] (committed)": 0 SendTo effect(s) (0 TurnResult), expected exactly one TurnResult to the caller dan; effects were {  }
    FAIL  ... AC-4 (control) ...   AC-4: the script could not run the control script (seed 1, n = 4): state.facility is nil after the dealing step at 60 (AC-1: the session must hold the generated facility)
    FAIL  ... AC-4: over 50 seeds ...  (same: state.facility is nil after the dealing step at 60)
    FAIL  ... AC-5 ...               (same)
    FAIL  ... AC-6 ...               (same)
    FAIL  ... Contract (C-1) ...     state.positions is nil from new, expected {} (C-1)
    FAIL  ... Contract (C-3): PositionsSampled ...
          "sample in an empty Lobby": state.positions is nil, expected exactly the samples { ann = { x = 5, y = 0, z = 5 } } (replaced, not merged)
    pass  ... Contract (C-3): a TurnRequested in Lobby, Resolution, Post, the next Lobby, and Resolution after a failed generation returns the same state with {} effects
    FAIL  ... Contract (C-3): after every step ... deep-equal the Contract's own composition ...
          after "DEAL 1": state.facility differs from the Contract's composition: value: expected table { attempt = 1, layout = ... }, got nil nil
    FAIL  ... Contract (C-3): the step that enters Lobby clears facility and procedure ...
          before "Post -> Lobby (clears facility and procedure)" facility is nil and procedure is nil; both must still be held in Post (AC-1)
    FAIL  ... Contract (C-4) ...     Contract precondition: only 0 steps with Placed and 0 with a TurnResult
    FAIL  ... Contract (C-5) ...
          "tick after the penalty": RoundView.secondsLeft is 416, expected ceil(Procedure.deadline - 64) = 396 (the config formula says 416; the Procedure carries 20 s of penalty)
    pass  ... Contract: step mutates neither its state nor its event ...
    2 passed, 14 failed   (session_round_test alone)

Under the gate command itself (`lune run test`, the whole suite, measured
locally 2026-10-02): `887 passed, 14 failed`, exit 1, `real 3m57.961s`, no
`LOAD FAIL`, and every one of the 14 `FAIL` lines is in
`tests/server/session_round_test.luau`. Before this story the suite was 859
tests; the new files add 16 + 26 = 42.

Why it is the right failure: the module LOADS (today's `Session.luau` exists),
so the `pcall(require)` guard never fires and every test reaches its own
assertion. Each message names the missing behaviour - no facility, no
Procedure, no `Placed`, no `TurnResult`, `positions` nil, `secondsLeft` from the
config - rather than a load error, a syntax error or a timeout. The scripted
checks (AC-4/5/6) stop at `ScriptedRound.start`'s precondition because the
facility is what they script against; once AC-1 is in they run in full.

SLICE-003: `session_test.luau` 15/15 and `session_controls_test.luau` 33/33
pass against today's Session with the C-6 change in place (measured). The
only SLICE-003 file touched is `tests/helpers/SessionContract.luau`, the one
function `passThroughOf` (and its comment). C-6's change is earned by **D-4
(GATES)** against the real module, not here; what RED did measure is the
stand-in `dropsEmits` (a session that emits `Placed` AND drops `Emit`s) still
failing exactly SLICE-003's `passesThroughTheMachinesEffects...` through the
narrowed helper, and the reference (which emits `Placed`) passing it.

### Files touched

| File | Status |
|---|---|
| `tests/helpers/ScriptedRound.luau` | new (C-7) |
| `tests/helpers/SessionRoundContract.luau` | new |
| `tests/server/session_round_test.luau` | new |
| `tests/server/session_round_controls_test.luau` | new |
| `tests/helpers/SessionContract.luau` | `passThroughOf` narrowed (C-6) |
| `docs/backlog/stories/SLICE-005.md` | `## Test plan`, this section |

No manifest, config or source file was touched. `selene` on the five test
files: 0 errors, 0 warnings; `stylua --check tests` clean.

### Export shape the tests pin (facts, not suggestions)

Module: `src/server/session/Session.luau`, required as a plain table with
field functions `new` and `step` (called with a dot).

    Session.new(config, seed, roundId, sessionId)             -- four args: must still work
    Session.new(config, seed, roundId, sessionId, options)    -- five: options = { generatorPredicate = fn? }
      -- the fifth argument is only ever a table or absent; `options.tuning` is
      -- never passed by these tests (the reference stand-in honours it, but
      -- nothing asserts on it). Default tuning MUST be the `MechanicsTuning`
      -- module: the oracle generates and starts the Procedure with it.
    Session.step(state, event, now) -> (state, effects)

State fields read: `round`, `assignment`, `facility`, `procedure`, `positions`.
`positions` must be `{}` from `new` (not nil - the C-1 check reads it).
Extra fields (`tuning`, `generatorPredicate`, anything else) are not
constrained: the state-follows check compares those five fields only, the
ignored-turn check compares the whole state to ITSELF before the step.

Events constructed by the tests:

    { kind = "PositionsSampled", samples = { [playerId] = { x, y, z } } }
    { kind = "TurnRequested", playerId = "...", args = { machine = n, setting = n } }

Effects asserted, by key set (enumerated with `pairs`, so no extra keys):

    { kind = "Placed", playerId = p, position = { x, y, z } }        -- fresh table each; x/y/z exactly
    { kind = "SendTo", playerId = caller, payloadKind = "TurnResult", payload = TurnRequests.reply(result) }
    { kind = "Broadcast", payloadKind = "RoundView", payload = { phase, secondsLeft?, players, playersMin, playersMax } }  -- unchanged from SLICE-003

Values pinned exactly (deep-equal to the pure modules' output):

- `facility` = `Generator.generate(dealt, deal.seed, tuning, options.generatorPredicate).facility`,
  `dealt` = `Ring.assign(deal.players, Rng.fromSeed(deal.seed))`, `deal` = the
  `AssignSeats` effect. `stagesOverride` is never passed.
- `procedure` = `Procedure.start(facility, now, tuning, deal.seed, round.config.roundSeconds)`
  on the dealing step; thereafter `TurnRequests.handle(procedure, assignment,
  event.playerId, event.args, now, state.positions)` on a Round turn and
  `Procedure.tick(procedure, assignment, now, state.positions)` on a Round Tick
  with `procedure.outcome == nil`, applied AFTER the machine took the Tick.
- routing: an outcome that appears this step (turn OR tick) is fed as
  `RoundResolved{ outcome = procedure.outcome }` at the same `now`; its
  machine effects pass through. AC-6's clock check asserts the phase at the
  resolving tick is `Resolution`, which is only true with machine-before-Procedure.
- `positions` after a deal = `{ [p] = centre }` for `dealt.players`; after a
  sample = a copy of `samples` (replace, not merge; `rawequal` to the event's
  table fails); untouched on every other step, including entering Lobby.
- `secondsLeft` in Round with a procedure = `math.ceil(Procedure.deadline(procedure) - now)`.
- generation failure: a third machine step with
  `RoundResolved{ { result = "no_contest", reason = "generation_failed" } }`,
  seat views still sent, no `Placed`, facility and procedure nil.
- `TurnRequested` with no procedure or outside Round: the SAME state back
  (deep-equal) and `{}`. `PositionsSampled`: `{}` effects in every phase.
- effect order on a step: machine pass-through, `Placed` (seat order),
  `SendTo/SeatView` (seat order), `SendTo/TurnResult`, ≤ 1 `Broadcast` last.

Not constrained: where the centre is computed, whether the RoundView is built
here or in a helper, how `Session` requires the pure modules, error wording,
whether `Placed`'s `position` is built from the room record or copied from a
shared constant (as long as each effect gets its own table), and what the
Session does with `options.tuning`.

### Passed on arrival, and what earns them

Two of the 16 pass against today's Session:

1. `ignoresATurnOutsideRoundOrWithoutAProcedure` - today's Session forwards
   an unknown event kind to `PhaseMachine.step`, which returns the state
   unchanged with `{}`. Earned by (a) the controls `ignoresThePredicate`,
   `routesTickOutcomeOnNextTickOnly`, `skipsRoutingOnTick`, `turnsWith*` all
   making it fire, and (b) a `mutate.sh` probe on the real module:

       bash scripts/mutate.sh src/server/session/Session.luau 's/local effects: { SessionEffect } = {}/local effects: { SessionEffect } = { { kind = "PromptRematch" } :: any }/' -- <run session_round_test>
       FAIL  ... Contract (C-3): a TurnRequested in Lobby, Resolution, Post, the next Lobby, and Resolution after a failed generation returns the same state with {} effects
             Contract: a TurnRequested with no procedure or outside Round must return the same state with {} effects:
       1 passed, 15 failed
       === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T221442Z.1490926.bak) ===

2. `stepMutatesNeitherStateNorEventOnRoundEvents` - today's Session is pure.
   Earned by the controls `mutatesStateOnSample` and `mutatesTurnEvent` (each
   fires exactly this check) and a probe:

       bash scripts/mutate.sh src/server/session/Session.luau 's/return { round = round, assignment = assignment }, effects/state.round = round; return { round = round, assignment = assignment }, effects/' -- <run session_round_test>
       FAIL  ... Contract: step mutates neither its state nor its event on PositionsSampled, TurnRequested and every other step of both plans
             "join ann": step mutated its state argument:  (and 9 more)
       1 passed, 15 failed
       === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T221450Z.1491184.bak) ===

### Negative controls: expected and measured

Everything below EXECUTED in RED against the stand-ins (they need no source
from this story); the "GREEN confirms" column is what to re-read in the
`[measured]` lines once the real module runs the same battery.

Baselines the scripts depend on (fixtures tests, re-measured in RED rather
than read from C-8):

| Quantity | Threshold | Measured in RED | GREEN confirms |
|---|---|---|---|
| Generation success, seeds 1..50, n = 4, 5, 6 | 150/150, all on attempt 1 | 150/150, max attempt 1, 0.35 ms each | the fixtures test stays green |
| Nearest machine to any spawn centre | > `turn_range_studs` = 10 | 22.627 studs | same |
| Lifecycle oracle: turn results, in order | committed, rejected/wrong_setting, refused/not_key_holder, refused/unknown_machine, refused/out_of_reach | exactly that | the `[measured] lifecycle turns:` line |
| Lifecycle oracle: penalty carried / routed clock-out tick | 20 s / 460 (= 60 + 420 - 20, before the backstop at 480) | 20 s / 460 | same line |

Scripted outcomes on the reference stand-in (the positive control):

| Script | Expected | Measured in RED | GREEN confirms (against the real Session) |
|---|---|---|---|
| AC-4 win | 150/150 won, 150/150 resolved in the completing turn's step | 150/150, 150/150 | `[measured] AC-4:` line |
| AC-4 control (from spawn) | 150/150 every turn refused, 150/150 lost/clock on the deadline tick | 150/150, 150/150 | `[measured] AC-4 control:` line |
| AC-5 | 9/9 lost/instability in the 5th wrong turn's step, 9/9 every 20 s drop | 9/9, 9/9 | `[measured] AC-5:` line |
| AC-6 | 10/10 (k, seed) resolved exactly on the Procedure's deadline tick | 10/10 | `[measured] AC-6:` line |

Single-defect stand-ins, and the exact set of checks each fires (measured;
every set pinned in the controls file with `expectFires`):

| Stand-in (one defect) | Fires exactly | Note |
|---|---|---|
| `routesTickOutcomeOnNextTickOnly` (the story's) | CLOCK, FOLLOWS, SECONDS, CLEARS, GEN, IGNORES, ORDER, PLACED | AC-6 message names k = 1..4 and NOT k = 0 (asserted); AC-6 measured 2/10 (the two k = 0 cases). The extra checks are the lifecycle's second half cascading from an unrouted clock-out |
| `skipsRoutingOnTick` (D-1's shape) | same set | same k = 0 assertion |
| `skipsRoutingOnTurn` (D-2's shape) | WIN, INSTAB | both messages say "IN THAT STEP"; AC-4 0/150 same-step, AC-5 0/9 same-step; nothing about the clock |
| `procedureBeforeMachine` | FOLLOWS, CLOCK, SPAWN | CLOCK message "expected Resolution"; SLICE-003's `roundStateFollows...` also fires |
| `secondsLeftFromConfig` (D-3's shape) | INSTAB, SECONDS | AC-5 0/9 drops; SLICE-003's payload check does NOT fire (0 SLICE-003 failures) |
| `turnsWithEmptyPositions` (the story's) | TURN, FOLLOWS, SECONDS, WIN, INSTAB, CLOCK, CLEARS, GEN, IGNORES, ORDER, PLACED | TURN says out_of_reach; WIN says "expected committed"; no penalty is ever charged so the clock-out cascade follows |
| `turnsWithPlacedPositions` | same set | TURN says out_of_reach |
| `sendsTurnResultToEveryone` | TURN | |
| `broadcastsOnEveryTurn` | TURN | |
| `mergesSamples` | SAMPLES, FOLLOWS, TURN | TURN says out_of_reach (the omitted turner stayed in reach) |
| `storesSamplesByReference` | SAMPLES | |
| `generatesFromTheSessionSeed` (the story's) | GEN, FOLLOWS, PLACED | GEN names deal 2 only - `round.seed == deal.seed` on every deal today, so "generates from round.seed" cannot be told apart; the reused-initial-seed shape is the one that discriminates, on the second round |
| `generatesFromAFixedSeed` | GEN, FOLLOWS, PLACED, TURN, SECONDS, CLEARS, IGNORES, ORDER | GEN names deal 1 |
| `placesAtTheFirstMachine` (the story's) | PLACED, FOLLOWS | PLACED says "spawn room's centre" |
| `aliasesPlacedPositions` | PLACED | "SAME table" |
| `startsTheProcedureAtTimeZero` | GEN, FOLLOWS, SECONDS, CLOCK, SPAWN, TURN | |
| `ignoresThePredicate` | GENFAIL, FOLLOWS, IGNORES | GENFAIL "expected Resolution in the same step" |
| `staysInRoundOnGenerationFailure` | GENFAIL, FOLLOWS | |
| `keepsFacilityAndProcedureInLobby` | CLEARS, FOLLOWS | |
| `dropsEmits` (D-4's shape, stand-in) | GENFAIL | and exactly SLICE-003's `passesThrough...` through the narrowed helper |
| `mutatesStateOnSample`, `mutatesTurnEvent` | PURE | |
| `{ new }` only / `{ step }` only | all 16 | "Session.step is nil" / "Session.new is nil" |

### C-9 re-check

`rg -n "Session\.new|S\.new\b|passThroughOf" src tests lune` on this tree:
the table in C-9 matches, with SessionContract's line numbers shifted by the
C-6 comment (`:228 → :236`, `:514 → :522`, `:1193 → :1201`) and the new
callers this story adds (`ScriptedRound.luau:108/110`, `SessionRoundContract.luau`
x4, the stand-in's own `S.new` in `session_round_controls_test.luau:92`). No
source file requires `Session`.

### Deferred verifications D-1..D-4: DECLINED in RED

All four mutate the real `Session.luau` to break a behaviour it does not yet
have, so none can be run here; they stay with GATES as written. What RED did
instead is the stand-in shapes above: D-1 → `skipsRoutingOnTick` (CLOCK fires
on k ≥ 1, k = 0 green, as D-1 predicts); D-2 → `skipsRoutingOnTurn` (WIN and
INSTAB fire); D-3 → `secondsLeftFromConfig` (INSTAB and SECONDS fire, SLICE-003
payload green); D-4 → `dropsEmits` (SLICE-003 pass-through fires). Those are
claims about the checks, not about the shipped module.

### Discoveries that affect the implementation

- **AC-6 pins the phase at the resolving tick.** C-3's order (machine Tick
  first, then `Procedure.tick`, then route) is what makes the clock-out land in
  `Resolution`; the reversed order lands in `Post` and the `procedureBeforeMachine`
  control shows AC-6, the spawn control and SLICE-003's follows check all
  firing. Keep the order.
- **`round.seed == deal.seed` today**, so the control the brief asked for
  ("generates from round.seed") is indistinguishable from a correct session;
  the two shapes that discriminate are a reused initial seed (second round)
  and a fixed seed. GREEN should still read the effect's seed, as C-2 says.
- **`TurnRequested` from a non-seated player in Round is handled, not
  ignored**: `Procedure.turn` refuses it `not_key_holder` and the stranger gets
  a `TurnResult`. That is C-3 step 3 read literally (the guard upstream owns
  identity); the plan pins it.
- **Positions are not cleared on a seated leave**, nor on entering Lobby; the
  leaver's entry stays until the next sample. The oracle does this because C-3
  says positions are the driver's last sample, not round state.
- `secondsLeft` on the dealing step's RoundView is `roundSeconds` from both
  formulas, so SLICE-003's payload check is unaffected (measured).
- No story text contradicted a measurement; no Contract block was amended.

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


### PO decisions at PLANNED → RED (2026-10-02, lead-po)

1. **AC-6 was rewritten before the criteria froze, with the user's approval.**
   As planned it could not discriminate: with no instability charged the
   Procedure's deadline (`startedAt + roundSeconds`) and the phase machine's
   backstop (`phaseEnteredAt + roundSeconds`) fall on the same tick with the
   same `lost / clock`, and the Tick reaches the machine first, so D-1's
   mutation would have left AC-6 green. Reproduced by reading
   `PhaseMachine.step`'s `Round` clock branch and `Procedure.settle`: there is
   no observable difference between the two paths at zero penalty. AC-6 now
   also asserts the penalised clock, where only the Procedure can be first.
   The user chose this option over waiving D-1.
2. **A turn that ends the round resolves it in the same step.** AC-4 and AC-5
   now say so, and C-3 step 5 routes an outcome from `TurnRequested` as well as
   from `Tick`. `architecture.md` §9.2 names only the Tick ("the Procedure is
   advanced on `Tick`; if it produced an outcome…") because that was the only
   path it described; a winning commit or the fifth wrong turn should not wait
   up to a second for the next Tick to end the round. D-2 verifies the routing.
3. **`Placed` forced one change to SLICE-003's helper (C-6).** Its
   `passThroughOf` treats every unknown effect kind as pass-through, so the
   contract's "SLICE-003's tests must still pass unchanged" was unsatisfiable
   as written. RED narrows that one helper to the machine's effect kinds; D-4
   earns it.
4. **`secondsLeft` in `Round` reads `Procedure.deadline` now (C-5).** VIEW-003,
   which was to make that move, is blocked behind this story, and AC-5 asserts
   the drop "through whatever `RoundView` exists". Equal to SLICE-003's formula
   at zero penalty, so SLICE-003's payload check is unaffected.
5. **Epic check.** EPIC-08 done-when #1 (a headless scripted win and a loss by
   instability through `Session.step` alone) is AC-4 and AC-5 here, with
   SLICE-006 extending it. No gap between the last story and this one.
6. **Gate.** The artifact is `src/server/session/Session.luau`, read by `unit`
   (`covers | unit | src/server/**`), which is `required`. No optional gate is
   the only one exercising it, so `required_gates` stays empty.
