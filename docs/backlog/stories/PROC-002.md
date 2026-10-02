---
id: PROC-002
title: The finale commits only when both machines are turned inside the window
slug: the-finale-commits-only-when-both-machin
epic: EPIC-05
type: feature
status: done
phase: DONE
branch: story/PROC-002-the-finale-commits-only-when-both-machin
depends_on: [PROC-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. **The finale** (`mechanics.md` §3.2 and §5, G5 and G12; the
case list is exact in §5):

- The last step of each track forms one paired operation.
- **Both finale steps go live together**, once every ordinary step of both
  tracks is committed (`finale_live_together`).
- A correct turn on a live finale machine, when neither is armed, **arms** it
  and opens a window of `simultaneous_window_seconds` at that turn's server
  time.
- A correct turn on the other machine at or before the window's end commits
  **both**, together, at that time.
- A **wrong** turn on either machine is rejected like any wrong turn (+1). If a
  window is open, it closes and both machines disarm **with no second
  penalty**.
- A window reaching its end with one machine armed disarms both, at a cost of
  +1.
- In every case, one failed attempt at the finale costs exactly 1.

**The partner lamp.** Machine A's partner lamp is lit while the finale is live
**and** the holder of B's key class is within `partner_lamp_range_studs` of B,
and the same holds the other way round.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a Procedure with one ordinary step left in track 1 and track
  2's ordinary steps all committed, when `isLive` is asked about both finale
  machines, then neither is live. The moment the last ordinary step commits,
  both are live.
  *Control:* a rule that lights track 2's finale as soon as its own track is
  done must fail.
- **AC-2** — Given a live finale with neither machine armed, when machine A is
  turned correctly at `t`, then the result is `armed` and instability is
  unchanged. When B is then turned correctly at any `t' ≤ t +
  simultaneous_window_seconds`, both commit at `t'` and the Procedure is
  complete.
- **AC-3** — Given A armed at `t`, when `tick` runs at `t +
  simultaneous_window_seconds + ε` with B unturned, then both disarm, instability
  rises by exactly `instability_per_failed_pair` (1), and A's dial shows
  rejected until `actuation_reset_seconds` later.
- **AC-4** — Given A armed, when B is turned to a wrong setting inside the
  window, then the result is `rejected / wrong_setting`, both disarm, and
  instability rises by exactly 1 in total, not 2.
  *Control:* an implementation that charges the wrong turn and the closed window
  separately must fail, scoring 2.
- **AC-5** — Given A armed, when A is turned again, then it is `refused / armed`
  at no cost.
- **AC-6** — Given a live finale and accepted positions, when
  `Procedure.partnerLamps` is read, then A's lamp is lit exactly when the holder
  of B's class is within `partner_lamp_range_studs` of B (horizontally), and B's
  lamp the same way round. Both lamps are dark while the finale is not live.
  *Control:* a lamp that reads the holder's distance to *A* must fail a fixture
  where B's holder is standing at A.
- **AC-7** — Given the window's edge, when B is turned at exactly `t +
  simultaneous_window_seconds`, then both commit. The window is inclusive at its
  end, matching the rate limiter's inclusive comparison.

## Contract

**Module.** `src/server/procedure/Procedure.luau`, extended. This story adds:

    ProcedureState.armed: { machineId: number, closesAt: number }?
    Procedure.tick(state, assignment: Ring.Assignment, now: number, positions) -> (ProcedureState, Outcome?)
        -- this story: closes an expired window. PROC-003 adds instability consequences and outcomes.
    Procedure.partnerLamps(state, assignment, positions) -> { [number]: boolean }   -- finale machine id -> lit
    Procedure.isComplete(state) -> boolean

- `TurnResult`'s `armed` variant and the `refused / armed` reason already exist
  in `PROC-001`'s types. This story gives them behaviour.
- A disarmed machine's dial resets after `actuation_reset_seconds`, like any
  rejection (`mechanics.md` §5).
- At n = 3 after a disconnect, the finale's two key classes may belong to ring
  neighbours or to one player. The rules above do not change. One player
  holding both classes can arm A and walk to B inside the window only if the
  rooms are close enough, and that is the degraded round `roles.md` §6
  describes. There is no special case.

**Existing exports: none changed.** `PROC-001`'s signatures are kept. `tick`
is new.

**Oracle partition.** Every criterion is **settled** by `mechanics.md` §5's exact
case list. Each test names the case it pins.

**Pinned semantics (PO, at PLANNED → RED, 2026-10-01).** These continue
`PROC-001`'s P-1..P-11, which all still hold except where F-9 refines P-9. RED
may amend any block below in place, with a dated reason next to it; GREEN builds
what the amended block says.

- **F-1. Types.** `ProcedureState.armed: { machineId: number, closesAt: number }?`
  — absent (nil) from `start` and whenever no window is open. `tick` returns
  `(ProcedureState, PhaseMachine.Outcome?)`, the type imported from
  `src/server/round/PhaseMachine.luau`; in this story the second value is
  **always nil**. `partnerLamps` returns a table with **exactly two keys**, the
  two ids of `facility.steps.finale`, each a real boolean. `isComplete` returns a
  real boolean. `TurnResult`, `DialView` and `ActuationLogEntry` are unchanged.
- **F-2. Constants**, read from `state.tuning` (P-1):
  `instance.simultaneous_window_seconds`, `instance.partner_lamp_range_studs`
  (both in `InstanceTuning`, read from `src/shared/MechanicsTuning.luau` at
  `25d7a74`), `actuation.instability_per_failed_pair`,
  `actuation.instability_per_wrong_value`, `actuation.actuation_reset_seconds`.
  Tests override them so every one is **distinct** from every other and from the
  shipped values — e.g. window 3, lamp range 4 (≠ the fixture's `turn_range_studs`
  7), failed pair 4, wrong value 1, out of order 2, reset 5 — so a test can tell
  which constant was read and which was charged. AC-3 and AC-4 are **also** run
  once under the shipped tuning, where they read out literally (+1, "not 2").
- **F-3. Liveness (replaces P-3's finale clause).** An ordinary step is live as
  P-3 says. A finale step is live iff **every ordinary step of every track** is
  committed and that finale step is not committed. Both finale steps are
  therefore live, or neither. **An armed machine is still live** (`isLive` is
  true for it); armed is a separate fact read from `state.armed`. A committed
  finale machine is not live.
- **F-4. Arming.** A turn that passes every refusal, on a live finale machine, at
  its required setting, with `state.armed == nil`: returns
  `{ kind = "armed", machineId = id }`; sets `armed = { machineId = id, closesAt
  = now + simultaneous_window_seconds }`; sets `dials[id] = { setting = setting }`;
  instability unchanged; appends one log entry with `result = "armed"`.
  `committed` unchanged.
- **F-5. Completing.** With `armed = { machineId = A, closesAt = c }`, a turn
  that passes every refusal on the **other** finale machine B, at B's required
  setting, at `now ≤ c` (inclusive, AC-7): returns `{ kind = "committed",
  machineId = B }`; sets `committed[A]` and `committed[B]` true; `armed = nil`;
  `dials[B] = { setting = setting }` (`dials[A]` keeps A's armed setting, so
  `dial(A)` reads `{ setting = <A's setting>, state = "committed" }`); appends
  **one** log entry, B's, with `result = "committed"`; instability unchanged.
  `isComplete` is then true.
- **F-6. The armed refusal.** A turn on the armed machine itself, any setting,
  is `refused / armed`, free (P-9). Refusal order becomes `unknown_machine`,
  `not_key_holder`, `out_of_reach`, `committed`, `resetting`, **`armed`** — first
  failure wins. (An armed machine can be neither committed nor resetting, so
  only the first three can pre-empt it.)
- **F-7. A wrong turn with a window open.** With A armed, a turn on B that passes
  every refusal at a setting that is not B's required setting: rejected exactly
  as P-6/P-8 say (`rejected / wrong_setting`, `instability_per_wrong_value`
  charged once, B's dial `{ setting, rejectedUntil = now + reset }`, one log
  entry `wrong_setting`) **and** `armed = nil` and `dials[A] = { setting = <A's
  armed setting>, rejectedUntil = now + actuation_reset_seconds }`.
  `instability_per_failed_pair` is **not** charged. A wrong turn on a live
  finale machine with no window open is an ordinary rejection.
- **F-8. Expiry, by `tick`.** `tick(state, assignment, now, positions)`: if
  `armed ~= nil` and `now > armed.closesAt` (strictly — the window is inclusive
  at its end), returns a new state with `armed = nil`, `instability +=
  instability_per_failed_pair`, and `dials[A] = { setting = <A's armed setting>,
  rejectedUntil = now + actuation_reset_seconds }` (the tick's `now`, not
  `closesAt`: a late tick does not shorten the visible rejection). The unturned
  machine's dial is untouched. **No log entry** — expiry is not a turn.
  Otherwise `tick` returns a state deep-equal to the one passed. Either way the
  second value is nil. `assignment` and `positions` are unread in this story.
- **F-9. A turn applies an expired window first (refines P-9).** `turn` at a
  `now > armed.closesAt` first applies exactly F-8 as though `tick(state, …,
  now, …)` had run, then judges the turn against that state. So a correct turn on
  B arriving after the window costs `instability_per_failed_pair` and then
  **arms B**; a turn on A then is `refused / resetting`, and the state returned
  is the **post-expiry** state, not the one passed. P-9's "a refused turn returns
  a state deep-equal to the one passed" therefore holds whenever no window has
  expired at `now`, which covers every `PROC-001` case. Derived from §5 "Server
  events are handled in arrival order" and the edge case "the second turn
  arrives after the window: both disarm, instability +1": the window's end is an
  event that precedes the late turn, and a session that forgot to `tick` must not
  be able to commit a late finale.
- **F-10. `isComplete`.** True iff every machine in every track of
  `facility.steps.tracks` is committed. Decoys are irrelevant.
- **F-11. Partner lamps.** Let the finale be `{ A, B } = facility.steps.finale`.
  If the finale is not live (F-3: an ordinary step remains, or the finale is
  committed), both are false. Otherwise A's lamp is true iff **some** player `p`
  with `B.keyClass ∈ assignment.keyClasses[p]` has a position `positions[p]`
  within `partner_lamp_range_studs` of `Machines.positionOf(layout, B, tuning)`,
  horizontally and inclusively (P-4's rule with the lamp's range), and B's lamp
  the same way round. `armed` does not affect the lamps. A player absent from
  `positions` is out of range. One player holding both classes is not a special
  case.
- **F-12. Non-mutation.** P-11 extends to `tick`, `partnerLamps` and `isComplete`.

**Test files.** `tests/server/procedure_finale_test.luau` (the settled ACs, on the
real module) and `tests/server/procedure_finale_controls_test.luau` (the AC-1,
AC-4 and AC-6 controls, observed to fire against wrong stand-ins), with the
checks and fixture in `tests/helpers/FinaleContract.luau`, following
`PROC-001`'s `TurnContract` pattern. Reuse `TurnContract`'s fixture (tracks
`{11,12,13}` and `{14,15,16,17}`, finale `{13,17}`, decoys 18 and 19) rather than
inventing a second facility.

**A frozen PROC-001 test this story legitimately breaks — RED's to correct.**
`TurnContract.lua`'s AC-1 check near line 381–408 ("Tracks advance
independently, and a finale step is never live in this story") commits 11, 12,
14, 15, 16 and asserts the live set is `{}`. Under F-3 it is `{13, 17}`. That
assertion pinned PROC-001's interim behaviour, and its own message says so
("finale steps are waiting in PROC-001 and go live only in PROC-002"). RED
corrects it to `{13, 17}` — a test change in RED, written against code that does
**not** yet do this, so it will be red for the right reason and needs no probe.
RED must also (a) bring `procedure_controls_test.luau`'s reference stand-in up to
F-3 so the PROC-001 controls stay green against a correct reference, and
(b) **read every other `TurnContract` check against F-3..F-9** and list in the
handoff each one it judged unaffected — notably the ones at ~639–694 (finale
turned while ordinary steps remain: still `not_live`, unchanged) and the
refusal-order check.

**Callers of changed signatures.** No existing export's signature changes.
`ProcedureState` gains an optional field and `turn`'s refusal list gains its
already-declared `armed` member. Checked against the tree on `main` at `25d7a74`:

    rg "Procedure\.(start|turn|dial|isLive|tick)|ProcedureState|\.armed" src tests lune
    -> src/server/procedure/Procedure.luau      (the module)
    -> tests/server/procedure_test.luau         (PROC-001)
    -> tests/server/procedure_controls_test.luau (PROC-001; its reference stand-in)
    -> tests/helpers/TurnContract.luau          (PROC-001; see above)

No production caller exists yet (`SLICE-005` wires it). RED's handoff states this
list was re-checked against the tree.

**Epic check (PO, 2026-10-01).** EPIC-05 done-when #3 is this story's whole:
finale live together (AC-1), both-or-neither inside the window (AC-2, AC-7), one
point per failed attempt (AC-3, AC-4), the partner lamp (AC-6). Done-when #2's
`armed` refusal is AC-5. Nothing in done-when #1–#3 falls between `PROC-001` and
this story. No gap.

**Gate.** `unit` (required) runs `lune run test`, which collects
`tests/server/*_test.luau`. No optional gate is the only one reading this
artifact, so `required_gates` stays `[]`.

## Deferred verifications

**D-1. One failed attempt, one point.** Use `scripts/mutate.sh` to add the
failed-pair penalty on the wrong-turn-with-window-open path. AC-4 **must** then
fail with 2 under the shipped tuning (and with `wrong_value + failed_pair`
under F-2's distinct overrides). RED cannot run this. Owner: GATES.

**D-2. The window's edge is inclusive.** Use `scripts/mutate.sh` to turn the
expiry comparison from `now > closesAt` to `now >= closesAt` (in whichever of
`tick`/`turn` holds it — both, in two runs, if both do). AC-7 **must** then
fail. RED cannot run this. Owner: GATES.

**D-3. The lamp reads the partner's machine.** Use `scripts/mutate.sh` to make
`partnerLamps` measure the holder's distance to their own lamp's machine rather
than the partner's. AC-6 **must** then fail on the fixture where B's holder
stands at A. RED cannot run this. Owner: GATES.

### Results (lead-po, GATES, 2026-10-02, against `d49a07a`)

Every run is `bash scripts/mutate.sh src/server/procedure/Procedure.luau '<EXPR>' -- lune run test`;
each restore was verified byte-for-byte by `mutate.sh`, and `git status` showed
only the story file modified afterwards. Unmutated: `728 passed, 0 failed`.

**D-1 — RESULT: fails as required.** Two runs.

*Run 1, broad:* `/"wrong_setting")$/{n;s/disarm(next_, now)/next_.instability += next_.tuning.actuation.instability_per_failed_pair; disarm(next_, now)/}`.
This charged a failed pair on **every** `wrong_setting` turn, because `disarm`
runs on all of them (it is a no-op with no window), so it hit more than AC-4:

    FAIL  procedure_finale_test :: AC-4 under the SHIPPED tuning: a wrong turn on B with A armed raises instability by exactly 1 in total, not 2 (mechanics.md §5: no second penalty)
    FAIL  procedure_finale_test :: AC-4/F-7: a wrong turn on a live finale machine with NO window open is an ordinary rejection - charged wrong_value, the other machine untouched
    FAIL  procedure_finale_test :: AC-4/F-7: with A armed, a wrong turn on B inside the window is rejected / wrong_setting, charged instability_per_wrong_value ONCE (1, not also failed_pair 4), ...
    FAIL  procedure_finale_test :: F-9: a turn on A after the window is refused / resetting ...; a wrong turn on B after the window is expiry plus an ordinary rejection
    FAIL  procedure_test :: AC-3/P-1: charges accumulate and each reason charges ITS constant ... (wrong_value 1 + out_of_order 2 = 3)
    FAIL  procedure_test :: AC-3: a live step turned to the wrong setting is rejected / wrong_setting, charged exactly instability_per_wrong_value, ...
    FAIL  procedure_test :: AC-6/P-10: the log holds one { playerId, machineId, setting, at, result } per evaluated turn, ...
    721 passed, 7 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T022109Z.376716.bak) ===

*Run 2, narrowed to the D-1 path (window open):* the same with the charge guarded
by `if next_.armed ~= nil then … end`:

    FAIL  procedure_finale_test :: AC-4 under the SHIPPED tuning: a wrong turn on B with A armed raises instability by exactly 1 in total, not 2 (mechanics.md §5: no second penalty)
    FAIL  procedure_finale_test :: AC-4/F-7: with A armed, a wrong turn on B inside the window is rejected / wrong_setting, charged instability_per_wrong_value ONCE (1, not also failed_pair 4), disarms both into reset windows and logs one entry
    726 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T024811Z.412011.bak) ===

Exactly the two AC-4 window checks, and nothing else. The failure messages' detail
lines (the measured instability) were not captured by the filter; the mutation
adds `failed_pair` (1 shipped, 4 overrides) on top of `wrong_value` (1, 1), so the
assertions saw 2 and 5, which is what RED measured on its stand-in.

**D-2 — RESULT: fails as required.** One run: the expiry check is in a single
private `expire`, called by both `tick` and `turn`, so one mutation covers both.
`s/now <= state\.armed\.closesAt/now < state.armed.closesAt/`, which makes expiry
`now >= closesAt`:

    FAIL  procedure_finale_test :: AC-5/F-6: a turn on the armed machine itself - right setting or wrong, inside the window or at its end - is refused / armed at no cost and returns the state passed
    FAIL  procedure_finale_test :: AC-7/F-8: tick at t, mid-window and at exactly closesAt returns a state deep-equal to the one passed, and nil - expiry is strictly now > closesAt
    FAIL  procedure_finale_test :: AC-7: a correct turn on B at EXACTLY t + simultaneous_window_seconds commits both - the window is inclusive at its end
    725 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T022616Z.382547.bak) ===

The same three checks RED's control fired: turn at the edge, tick at the edge,
and the armed refusal at the edge.

**D-3 — RESULT: fails as required.** `s/finale\[3 - i\]/finale[i]/`, so each lamp
measures against its own machine:

    FAIL  procedure_finale_test :: AC-6/F-11: any holder of the partner's class in range lights the lamp, and one player holding both classes lights the lamp of the machine they are NOT standing at
    FAIL  procedure_finale_test :: AC-6/F-11: with the finale live, A's lamp is lit exactly when the holder of B's class is within partner_lamp_range_studs (4, not turn range 7) of B, ... B's the same way round; ...
    726 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T023109Z.389066.bak) ===

The second test contains the "B's holder at A, A's holder at B → both dark"
fixture. RED's table listed a third check, `lamps-dark`, for its own-machine
stand-in; it does not fire here. This mutation leaves liveness alone, so the lamps
are dark whenever the finale is not live, which is all `lamps-dark` checks.
RED's stand-in evidently differed from this mutation in that respect. AC-6's
required failure is present.

## Out of scope

- What the lamps look like (`HUD-002`).
- Outcomes (`PROC-003`). `isComplete` is the fact `PROC-003` turns into
  `won / procedure_complete`.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-002` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/procedure/Procedure.luau` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
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
- PLANNED → RED contract pinning - `lead-po` - `claude-opus-5-5`. 2026-10-01.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1). The dispatch passed
  `model: fable` explicitly; the agent self-reports Fable 5.1. 2026-10-02.
- GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5). The dispatch passed
  `model: opus` explicitly; the agent self-reports Opus 5.5. 2026-10-02.

## Test plan

All unit level, on the pure module, through `lune run test`. The checks live
once in `tests/helpers/FinaleContract.luau` (reusing `TurnContract`'s fixture:
tracks `{11,12,13}` / `{14,15,16,17}`, finale A = 13 (amy, class 3), B = 17
(bob, class 4), decoys 18, 19), are applied to the real module in
`tests/server/procedure_finale_test.luau`, and are observed to fire against
wrong stand-ins in `tests/server/procedure_finale_controls_test.luau`. Every
scenario starts from `liveFinale` (11, 12, 14, 15, 16 committed at NOW+1..5)
and arms at `T_ARM = NOW + 10 = 110`. Tuning per F-2: window 3, lamp range 4,
turn range 7, reset 5, wrong value 1, out of order 2, failed pair 4; the two
"shipped" rows use `MechanicsTuning` unmodified (window 5, lamp 10, reset 3,
all charges 1).

**`procedure_finale_test.luau` — the real module (24 tests)**

| Test (FinaleContract check) | Asserts | AC / F |
|---|---|---|
| exports tick, partnerLamps, isComplete (inline) | all seven exports are functions | F-1 |
| `startHasNoWindowAndTheNewExportsAnswerInShape` | `start().armed == nil`; `isComplete` is the boolean `false`; `tick` with no window returns a deep-equal state and nil; `partnerLamps` has exactly keys `{13, 17}`, real booleans, both false at start | F-1 |
| tick returns two values (inline) | first a table, second nil | F-1 |
| `neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre` | commit 11, 14, 15, 16: live set is exactly `{12}`; commit 12: live set is exactly `{13, 17}` | AC-1, F-3 |
| `anArmedMachineIsStillLiveAndACommittedFinaleIsNot` | A armed: live set still `{13, 17}`; after B commits: `{}` | AC-1, F-3 |
| `correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt` | result `{kind="armed", machineId}`; `armed == {machineId, closesAt = now + 3}`; `dials[id] == {setting}`; instability and `committed` unchanged; log grows by exactly one `armed` entry. Both A-first and B-first | AC-2, F-4 |
| `correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth` | at t'−t ∈ {0, 1.5, 2.999}: result committed B; `committed[A] == committed[B] == true`; `armed == nil`; `dials[B] == {setting}`; `dial(A)` and `dial(B)` read committed with their settings; one new log entry (B's); instability unchanged; `isComplete == true`. Also B-arms-then-A-completes | AC-2, F-5, F-10 |
| `turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth` | same at t' = t + 3 exactly | AC-7, F-5 |
| `tickAtOrBeforeTheWindowsEndChangesNothing` | tick at t, t+1.5, t+3 (= closesAt) returns a deep-equal state and nil | AC-7, F-8 |
| `tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair` | tick at t+3.001 and t+13: `armed == nil`; instability +4 exactly; `dials[A] == {setting, rejectedUntil = tickNow + 5}` (not closesAt-based); `dials[B]`, `committed`, `log` untouched; second return nil; `dial(A)` rejected until `tickNow + 5` then unset; `dial(B)` unset; both live again | AC-3, F-8 |
| `afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain` | after the expiry tick, A at tick+4.999 is `refused / resetting` with the state returned deep-equal (P-9 holds: no window expired at that now); A at tick+5 is `armed` with `closesAt = tick+5+3` | AC-3, F-8, F-6 |
| `underTheShippedTuningAnExpiredWindowCostsExactlyOne` | the expiry check under `MechanicsTuning` as shipped; instability is literally 1 | AC-3 |
| `wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth` | A armed, B wrong at t+1: `rejected / wrong_setting`; instability +1 exactly (not +5); `armed == nil`; `dials[B] == {wrong, rejectedUntil = now+5}`; `dials[A] == {A's setting, rejectedUntil = now+5}`; `committed` unchanged; one new log entry (`wrong_setting`); both dials read rejected | AC-4, F-7 |
| `underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo` | the same under shipped tuning; instability is literally 1, not 2 | AC-4 |
| `wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection` | no window: B wrong is an ordinary rejection (+1), `armed` nil, `dials[A]` nil | AC-4, F-7 |
| `turnOnTheArmedMachineIsRefusedArmedAtNoCost` | A again at t+1 (right setting), t+1 (wrong), t+3 (closesAt): `refused / armed`, state deep-equal, log and dial unchanged | AC-5, F-6 |
| `armedIsTheLastRefusalChecked` | on armed A: zed with no position → `not_key_holder`; stranger in reach → `not_key_holder`; amy out of reach / no position → `out_of_reach` | AC-5, F-6 |
| `aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt` | B correct at t+4: result `armed` B; nothing committed; instability +4; `armed == {B, closesAt = now+3}`; `dials[A] == {A's setting, rejectedUntil = now+5}`; `dials[B] == {setting}`; one new log entry (B `armed`) | F-9, F-8 |
| `aTurnAfterTheWindowReturnsThePostExpiryState` | A at t+4: `refused / resetting`, `armed` nil, instability +4, and the whole state deep-equal to `tick(armed, …, t+4)`'s; B WRONG at t+4: `rejected / wrong_setting`, instability +4+1 = +5, `armed` nil | F-9 |
| `bothLampsAreDarkWhileTheFinaleIsNotLive` | both holders at the partner machines: lamps `{false,false}` at start, with 12 left, and after the finale committed; `{true,true}` the moment it went live | AC-6, F-11 |
| `aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine` | live finale, neither armed AND A armed, 11 position cases each: bob at B → `{13=true,17=false}`; amy at A → `{false,true}`; nobody → both false; bob at exactly 4 along x / 4 along −z and 1000 up → true; 4.001 → false; (4,4) → false; 7 along x (in turn reach, out of lamp range) → false; bob at A and amy at B → both false; non-holder kim at B → no effect; only kim at B → both false | AC-6, F-11, F-2 |
| `anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase` | kim handed class 4 and at B → `{true,false}`; bob holding `{4,3}` at B → `{true,false}`, at A → `{false,true}`, at 11 → both false | AC-6, F-11 |
| `isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted` | false at start, with every ordinary step committed, with A armed; true after both commit with decoys never turned | F-10 |
| `noFinaleCallMutatesItsArguments` | tick (idle, expiring), partnerLamps (live, armed), isComplete, arming, completing, wrong-with-window, armed refusal, late turn: arguments deep-equal before and after; completing from `armed` then ticking the result leaves `armed` and `live` untouched | F-12 |

**`procedure_finale_controls_test.luau` — stand-ins (14 tests, all green in RED)**

| Test | Stand-in defect | Fires exactly |
|---|---|---|
| baseline | none (the reference) | 0 of 22 finale checks |
| audit | none | 0 of 20 `TurnContract` checks (the mechanical half of the F-3..F-9 audit) |
| fixtures: overrides distinct | — | every F-2 override ≠ shipped and ≠ each constant it must be told from; shipped failed-pair and wrong-value both 1 |
| fixtures: A and B far apart | — | d(13, 17) = 64 > max(turn range, lamp range) under both tunings |
| AC-1 control | finale live when ITS OWN track's ordinary steps are done | `neitherFinaleMachineIsLive…` (live set `{12, 17}`), plus TurnContract's corrected AC-1 check and `waitingStepIsNotLiveWhateverTheSetting` |
| AC-4 control | charges failed pair AND wrong value on F-7 | scores 2 shipped / 5 overrides; fires the two AC-4 window checks |
| AC-6 control | lamp measures the partner's holder against ITS OWN machine | lamp-geometry, both-classes, lamps-dark (moment-of-going-live case) |
| AC-7 control | expiry at `now >= closesAt` | turn-at-edge, tick-at-edge, armed-refusal-at-edge |
| F-9 control | turn does not apply an expired window first | both F-9 checks |
| F-3 control | armed machine not live | armed-still-live, lamp-geometry |
| F-11 control | lamps ignore liveness | F-1 shape, lamps-dark |
| F-2 control | lamp reads `turn_range_studs` | lamp-geometry |
| F-8 control | rejection dated from `closesAt` | expiry, shipped expiry, reset-then-rearm, F-9 arm-after-expiry |
| F-8 control | tick logs the expiry | expiry, shipped expiry, F-9 arm-after-expiry |

**Corrected PROC-001 test.** `TurnContract.tracksAdvanceIndependentlyAndFinaleStepsStayWaiting`'s
second assertion now expects `{13, 17}` (was `{}`); its `procedure_test.luau`
name was reworded to match. `procedure_controls_test.luau`'s reference stand-in
reads F-3 for finale steps so PROC-001's seven controls stay green with the same
fired sets as before.

## Handoff: RED -> GREEN

**Model this RED resolved to:** Fable 5.1 (`claude-fable-5-1`), the `fable` row
of `## Model guidance`. The dispatch did not say whether it passed `model:`
explicitly; the resolved model matches the plan either way. 2026-10-02.

### The command

    lune run test

runs the whole suite (`tests/**/*_test.luau`); there is no per-file switch. The
unit gate is the same command. Snapshot the test files before GREEN starts:

    bash scripts/frozen.sh snapshot tests/helpers/FinaleContract.luau tests/helpers/TurnContract.luau \
      tests/server/procedure_finale_test.luau tests/server/procedure_finale_controls_test.luau \
      tests/server/procedure_test.luau tests/server/procedure_controls_test.luau

### The failure, verbatim (from `bash scripts/gates.sh --fast`, unit gate log, 2026-10-02)

    703 passed, 25 failed

24 of the 25 are `tests/server/procedure_finale_test.luau` (every test in it);
the 25th is PROC-001's corrected AC-1 check. Nothing else in the suite moved:
690 passed before this RED; the 14 new control tests all pass. Representative
blocks:

    FAIL  tests/server/procedure_finale_test.luau :: F-1: Procedure exports tick, partnerLamps and isComplete as plain field functions, alongside start, isLive, dial and turn
          ...procedure_finale_test:57: the Contract's exports are not all functions: Procedure.tick is nil, Procedure.partnerLamps is nil, Procedure.isComplete is nil

    FAIL  tests/server/procedure_finale_test.luau :: AC-1: with track 2's ordinary steps committed and one ordinary step left in track 1 neither finale machine is live; the moment it commits, both are (finale_live_together, F-3)
          AC-1: the moment the last ordinary step committed the live set is {  }, expected exactly both finale machines { 1 = 13, 2 = 17 } (finale_live_together)

    FAIL  tests/server/procedure_finale_test.luau :: AC-2/F-4: a correct turn on a live finale machine with neither armed returns armed, opens a window closing at now + simultaneous_window_seconds, sets the dial, charges nothing, commits nothing and logs one armed entry - whichever machine goes first
          AC-2/F-4: amy turning finale machine 13 correctly first:
    result is { kind = "rejected", machineId = 13, reason = "not_live" }, expected { kind = "armed", machineId = 13 }
    state.armed is nil, expected { machineId = 13, closesAt = 110 + simultaneous_window_seconds 3 = 113 }
    state.dials[13] is { rejectedUntil = 115, setting = 1 }, expected { setting = 1 }
    instability went 0 -> 2 on an arming turn; arming costs nothing
    the log went from 5 to 6 entries, last { at = 110, machineId = 13, playerId = "amy", result = "not_live", setting = 1 }; expected exactly one new entry { at = 110, machineId = 13, playerId = "amy", result = "armed", setting = 1 }

    FAIL  tests/server/procedure_finale_test.luau :: AC-3/F-8: tick at t + simultaneous_window_seconds + epsilon with B unturned disarms both, charges exactly instability_per_failed_pair (the fixture's 4), ...
          F-1: Procedure.tick is nil, expected a function

    FAIL  tests/server/procedure_test.luau :: AC-1: tracks advance independently and the finale steps go live together - only once every ordinary step of BOTH tracks is committed (finale_live_together; corrected in PROC-002 RED to the live set { 13, 17 })
          AC-1: with every ordinary step of both tracks committed the live set is {  }, expected exactly the two finale steps { 1 = 13, 2 = 17 } - they go live together once every ordinary step of both tracks is committed (finale_live_together, PROC-002 F-3)

**Why it is the right failure.** The module loads (PROC-001 wrote it), so no
test fails at import. Each fails on its own first assertion against today's
behaviour, in one of three ways: (a) the export-shape tests and every test that
needs `tick`/`partnerLamps`/`isComplete` fail on `F-1: Procedure.<name> is nil,
expected a function` - a `need()` guard in `FinaleContract` that names the
missing export rather than letting Luau say "attempt to call a nil value"
(15 tests: F-1 x3, AC-2/F-5, AC-7 x2, AC-3 x3, AC-6 x3, F-10, F-12, the second F-9);
(b) tests that only use PROC-001's exports fail on liveness - the finale machine
is `not_live` today, so the live set is `{}` where `{13, 17}` is expected, or
the scenario's arming turn is `rejected / not_live` instead of `armed`
(9 tests: AC-1 x2, AC-2/F-4, AC-4 x3, AC-5 x2, the first F-9); (c) PROC-001's corrected check,
`{}` vs `{13, 17}`. None is a timeout, config or lint error.

**Gate shape (`gates.sh --fast`, 2026-10-02):** format PASS (observed 126),
lint PASS (126), typecheck PASS (24), unit FAIL (237 s, the 25 above), build
PASS, harness FAIL - `project-counters: 39 passed, 1 failed`, the one being
"the working tree carries no stray .luau files", which is the uncommitted-tree
precondition and goes green at the RED commit (the baselines themselves,
126/126/24, already match: AC-7 passed). `stylua --check src tests lune` and
`selene src tests lune` are clean on every file touched. No test in the suite
owns a timeout; Lune's runner has none, so there is nothing to budget. Timing
is local (Windows): the whole suite took 237 s under the gate, of which the
two new files are a few hundred milliseconds in isolation.

### Files touched

| File | Change |
|---|---|
| `tests/helpers/FinaleContract.luau` | NEW. Fixture (TurnContract's, plus F-2 overrides), scenario helpers (`liveFinale`, `arm`), the 22 checks, `CHECKS`, `failures` |
| `tests/server/procedure_finale_test.luau` | NEW. The 24 tests on the real module (`pcall(require)` + per-test re-check) |
| `tests/server/procedure_finale_controls_test.luau` | NEW. Reference stand-in (F-3..F-12) + ten defective stand-ins + fixture assertions; 14 tests |
| `tests/helpers/TurnContract.luau` | `tracksAdvanceIndependentlyAndFinaleStepsStayWaiting`: second assertion `{}` -> `TurnContract.FINALE` (`{13, 17}`), comment and message updated |
| `tests/server/procedure_test.luau` | that test's name reworded to say what it now asserts |
| `tests/server/procedure_controls_test.luau` | reference stand-in's `isLive` reads F-3 for finale steps; header note |
| `.claude/tests/project-counters.test.sh` | `BASE_FORMAT`/`BASE_LINT` 123 -> 126 (three new `.luau` files under `tests/`), with the provenance comment; `BASE_TYPECHECK` and the narrow counts unchanged. GREEN adds no `.luau` file, so these are the post-GREEN counts too |
| `docs/backlog/stories/PROC-002.md` | `## Test plan`, this section |

No manifest, no config, no source. `.claude/state/red/` holds my scratch
runner and logs; it is ignored and not for commit.

### The export shape the tests pin (facts - a test already imports them)

Module: `src/server/procedure/Procedure.luau`, required as
`require("../../src/server/procedure/Procedure")` from `tests/server/`. Every
export is a plain field on the returned table, called with a dot.

- `Procedure.tick(state, assignment, now: number, positions) -> (ProcedureState, nil)`.
  The second return is asserted `== nil` in this story. `assignment` and
  `positions` are passed (both finale holders at their machines, or `{}`) and
  may be ignored.
- `Procedure.partnerLamps(state, assignment, positions) -> { [number]: boolean }`
  with **exactly** two keys, `13` and `17` (the ids in `facility.steps.finale`),
  each a real boolean (`typeof == "boolean"`); compared by `Deep.equal` against
  `{ [13] = b1, [17] = b2 }`, so no extra key.
- `Procedure.isComplete(state) -> boolean`, compared with `== true` / `== false`.
- `state.armed` is `nil` from `start` and whenever no window is open, and
  otherwise **exactly** `{ machineId = <id>, closesAt = now + simultaneous_window_seconds }`
  by `Deep.equal` - **no extra field** (a `setting` or `playerId` in there fails
  AC-2/F-4). `Deep.equal` treats an absent key and `nil` alike, so `start` may
  omit the key or set it `nil`.
- `turn` results: `{ kind = "armed", machineId = id }` and
  `{ kind = "refused", machineId = id, reason = "armed" }` exactly (already in
  PROC-001's `TurnResult`).
- `dials[id]` after arming is **exactly** `{ setting = <required> }`; after a
  disarm (tick expiry, F-7, F-9) **exactly** `{ setting = <the armed setting>, rejectedUntil = now + actuation_reset_seconds }`
  where `now` is the tick's or the turn's `now`. `dials[B]` is untouched by an
  expiry (`nil` in the scenarios).
- Log entry on arming is **exactly** `{ playerId, machineId, setting, at = now, result = "armed" }`;
  completing appends exactly one entry (B's, `"committed"`); expiry appends none;
  F-7 appends exactly one (`"wrong_setting"`, B's).
- Constants are read from `state.tuning`: `instance.simultaneous_window_seconds`,
  `instance.partner_lamp_range_studs`, `actuation.instability_per_failed_pair`
  (plus PROC-001's). The fixture makes each distinct, so reading the wrong one
  or the module-level `MechanicsTuning` fails a named check.
- Refusal order with `armed` last: a non-holder or out-of-reach holder on the
  armed machine gets `not_key_holder` / `out_of_reach`, not `armed`.
- F-9 as written: a `turn` at `now > armed.closesAt` returns the post-expiry
  state (deep-equal to `tick(state, assignment, now, positions)`'s first return)
  even when the turn itself is refused. A late correct turn on B arms B; a late
  wrong turn on B is charged `failed_pair + wrong_value` (4 + 1 = 5 under the
  overrides) - this last case is **derived** from F-8 + F-9 + F-7's final
  sentence rather than stated in any AC; flagging it so you can object before
  building it (see "Doubts").

**Not constrained** (your choice): what `dial(id, now)` answers for an ARMED
machine (F-4 fixes `dials[id]`, not the view; the existing code would say
`unset`); how `isLive` walks the tracks; how `tick`, `partnerLamps` and
`isComplete` are structured internally; whether `tick`'s `positions` or
`assignment` are read; the text of any error; whether `copy` clones `armed`
(F-12 only requires the argument to be left deep-equal and the new state to be
independent); and any field PROC-003 adds.

### Tests that passed on arrival, and what earns them

All 14 tests in `procedure_finale_controls_test.luau` pass in RED by design:
they run the `FinaleContract` checks against stand-ins, not the module. What
earns each: the reference stand-in is accepted by all 22 finale checks and all
20 `TurnContract` checks (positive control), and every defective stand-in was
**observed** to fire the exact set of checks its test names (the `[measured]`
lines in the unit log). Nothing in `procedure_finale_test.luau` passes.

The one corrected PROC-001 check (`TurnContract` AC-1) is red against today's
module, so it needs no probe. The PROC-001 controls reference was brought to
F-3 and PROC-001's seven controls still fire the same sets they did before
(`[measured]` lines unchanged from PROC-001's handoff).

### Negative controls: expected values, measured in RED

Unlike an import-failing RED, these controls **did execute**: the stand-ins
need only merged modules. What remains for GREEN is confirming the real module
is *accepted* by the same checks (the 24 red tests going green) and that D-1..D-3
against the shipped module reproduce the rows below.

| Control (one defect on the reference) | Threshold / expected (reference) | Candidate / measured on the control | Checks that fired (exactly) |
|---|---|---|---|
| AC-1: finale live when its OWN track's ordinary steps are done | live set `{12}` with 12 left | `{12, 17}` | `neitherFinaleMachineIsLive…`; in TurnContract: corrected AC-1 check + `waitingStepIsNotLiveWhateverTheSetting` |
| AC-4: charge wrong value AND failed pair on F-7 | instability 1 (shipped), 1 (overrides) | **2** (shipped), **5** (overrides) | the two AC-4 window checks |
| AC-6: lamp measures partner's holder against its OWN machine | bob at A, amy at B -> `{13=false, 17=false}` | `{13=true, 17=true}` | lamp-geometry, both-classes, lamps-dark |
| AC-7: expiry at `now >= closesAt` | B at t+3 commits; tick at t+3 no-op; A at t+3 `refused/armed` | B at t+3 `armed` (after +4 expiry); tick at t+3 expires; A at t+3 `refused/resetting` | turn-at-edge, tick-at-edge, armed-refusal |
| F-9: turn ignores an expired window | late B `armed`, +4 | late B `committed`, +0 | both F-9 checks |
| F-3: armed machine not live | live set `{13, 17}` with A armed | `{17}` | armed-still-live, lamp-geometry |
| F-11: lamps ignore liveness | both false at start | `{true, true}` with holders at machines | F-1 shape, lamps-dark |
| F-2: lamp reads `turn_range_studs` (7) | bob 7 along x from B -> `{false,false}` | `{13=true, 17=false}` | lamp-geometry |
| F-8: rejection dated from `closesAt` | `rejectedUntil = tickNow + 5` | `closesAt + 5` (118 vs 118.001 / 123) | expiry, shipped expiry, reset-then-rearm, F-9 arm-after-expiry |
| F-8: tick logs the expiry | log unchanged by tick | log +1 | expiry, shipped expiry, F-9 arm-after-expiry |
| reference | — | 0 of 22 finale checks, 0 of 20 PROC-001 checks fail | — |

Three predictions were wrong on first run and corrected in the controls file
*to what was measured*, with the reason beside each: the per-track stand-in's
lamps still require both machines live, so the lamps-dark check does not fire on
it; the own-machine lamp also darkens the "moment it went live" case; and when
tick and turn share the same mis-dated expiry they agree, so the deep-equal F-9
check cannot see that defect (the four checks that compare against `now` do).

### Deferred verifications I cannot run

D-1, D-2, D-3 all mutate the real implementation, which does not exist in RED.
**I did not run them.** They stay with GATES. The controls table above says what
each must show: D-1 -> 2 (shipped) / 5 (overrides); D-2 -> the three AC-7 rows
go red (`turn` and `tick` separately if the comparison lives in both); D-3 ->
the lamp-geometry check fails on "bob standing at A and amy standing at B".

### Callers re-checked against the tree (2026-10-02)

    rg "Procedure\.(start|turn|dial|isLive|tick)|ProcedureState|\.armed" src tests lune -l
    -> src/server/procedure/Procedure.luau
       tests/helpers/TurnContract.luau
       tests/helpers/FinaleContract.luau          (new)
       tests/server/procedure_test.luau
       tests/server/procedure_finale_test.luau    (new)
       tests/server/procedure_finale_controls_test.luau (new)

`rg "require\(.*procedure/Procedure"` finds only `procedure_test.luau` and
`procedure_finale_test.luau`. No production caller exists; the story's list
holds.

### TurnContract audit against F-3..F-9 (every check, one line each)

Mechanical form: the finale reference stand-in passes all 20 (the `audit:` test).
By hand:

1. `startReturnsTheContractState` - checks six named fields, not the absence of others; `armed = nil` is fine. Unaffected.
2. `liveSetAtStartIsExactlyTheTrackHeads` - ordinary steps remain, finale not live under F-3 either. Unaffected.
3. `committingTheHeadOfTrackOneMakesItsSecondStepLive` - ordinary only. Unaffected.
4. `tracksAdvanceIndependentlyAndFinaleStepsStayWaiting` - **CORRECTED**: first assertion (`{14}` after 11, 12) still right under F-3; second now `{13, 17}`.
5. `holderInReachOnTheRequiredSettingCommits` - machine 11. Unaffected.
6. `reachIsInclusiveAtTurnRangeStudsAndIgnoresY` - machine 11. Unaffected.
7. `wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue` - machine 11. Unaffected.
8. `waitingStepIsNotLiveWhateverTheSetting` (~639-694) - finale 13 at start, and with track 1 done but track 2 not: `not_live` under F-3 too (every track must be done). Unaffected, and it is the PROC-001 check that catches the per-track control (measured).
9. `decoyIsNotLiveWhateverTheSetting` - decoys. Unaffected.
10. `chargesAccumulateByReason` - 11 then 18. Unaffected.
11. `rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset` - machine 11. Unaffected.
12. `unknownMachineIsRefused` - Unaffected.
13. `nonHolderIsRefusedAndNotCharged` - Unaffected.
14. `holderOutOfHorizontalReachOrWithoutAPositionIsRefused` - Unaffected.
15. `committedMachineIsRefused` - Unaffected.
16. `resettingDialIsRefused` - Unaffected.
17. `refusalChecksRunInOrderAndTheFirstFailureWins` - F-6 appends `armed` LAST; no case here has an armed state, so the order it pins is a prefix of F-6's. Unaffected; `armedIsTheLastRefusalChecked` covers the new member.
18. `supplierIsJudgedKeyHolderAfterWithdraw` - machines 11 and 14. Unaffected.
19. `logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals` - no finale, no window; P-9's deep-equal on refusals holds because F-9 only departs from it when a window has expired. Unaffected.
20. `noCallMutatesItsArguments` - F-12 extends it. Unaffected.

Also `refusalProblems`' P-9 deep-equal: every TurnContract caller passes a state
with no window, so F-9's refinement never applies there.

### Doubts and discoveries

- **Derived pin, not an AC:** a WRONG turn on B *after* the window is charged
  `failed_pair + wrong_value` (F-8 applied first, then F-7's "no window open is
  an ordinary rejection"). It follows from the F-blocks as written and from
  §5's "server events are handled in arrival order", but no AC states it. If the
  PO reads §5's "one failed attempt costs exactly 1" as covering this case too,
  that is an F-9 amendment and the second half of
  `aTurnAfterTheWindowReturnsThePostExpiryState` changes - raise it before GREEN
  builds it.
- `Deep.equal` on `state.armed` and on `dials[id]` forbids extra fields. That is
  the Contract's "exactly"; if GREEN wants to carry the armed setting inside
  `armed` rather than in `dials`, that is a Contract amendment, not a test tweak.
- The harness gate's one red assertion is the uncommitted-tree precondition;
  commit the `.claude/tests/project-counters.test.sh` change in the RED commit
  (check-boundaries 3j freezes `.claude/tests/**` outside RED).
- No `## Contract` block needed amending.

### GREEN notes

**Model this GREEN resolved to:** Opus 5.5 (`claude-opus-5-5`), the `opus` row;
the dispatch named no override. 2026-10-02.

**Files changed:** `src/server/procedure/Procedure.luau` only. No test, config,
manifest or harness file touched; no `.luau` file added, so RED's counter
baselines (126/126/24) stand.

**What was built.** `ProcedureState.armed`; F-3 liveness (a finale step is live
iff it is its track's first uncommitted step and every ordinary step of every
track is committed); `isComplete`; `armed` as the last refusal; arming (F-4) and
completing (F-5) on a correct finale turn; F-7 as the ordinary `wrong_setting`
rejection plus a disarm that charges nothing; `tick` = one private `expire`
(strictly `now > closesAt`, `rejectedUntil` from the tick's `now`, no log);
`turn` calls the same `expire` first (F-9), so the comparison lives in **one**
place - D-2 needs one mutation, not two; `partnerLamps` reusing P-4's
horizontal-distance rule with the lamp range, measured against the PARTNER
machine. `tick`'s second return is typed `PhaseMachine.Outcome?`;
`PhaseMachine` requires only `Event`, `Rng` and `RoundConfig`, so the import
creates no cycle. A wrong-setting turn's disarm is applied to any open window;
the only machine that can reach that branch with a window open is the partner
(the armed one is refused `armed`, every ordinary step is committed). A
`not_live` turn on a decoy leaves the window open - no test or F-block says
otherwise.

**Unit:** `lune run test` -> `728 passed, 0 failed` (703 + the 25 red).
`stylua --check src tests lune` clean; `selene src tests lune` 0 errors,
0 warnings.

**Controls, measured on the shipped module** (scratch script, ignored, under
`.claude/state/green/`; same fixture, `FinaleContract.world()` /
`shippedWorld()`):

| Row | RED expected (reference) | Shipped module |
|---|---|---|
| AC-4, shipped tuning | instability 1 (control: 2) | `rejected/wrong_setting`, 0 -> **1**, `armed` nil |
| AC-4, overrides | 1 (control: 5) | 0 -> **1** |
| AC-7, B at exactly closesAt | commits | shipped: B at 115 `committed 17`, `isComplete` true; overrides: at 113, same |
| AC-7, tick at closesAt | no-op | `armed` still set (both tunings) |
| AC-3, tick at closesAt + 0.001 | +failed pair, `rejectedUntil = tickNow + reset` | shipped **+1**, overrides **+4**; `rejectedUntil` 118.001 in both (115.001 + 3, 113.001 + 5) |
| F-9, late correct B | `armed`, +4, nothing committed (control: committed, +0) | overrides: B at 114 `armed 17`, **+4**, `committed[B]` nil; shipped: at 116, +1, same shape |
| AC-6, B's holder at A and A's at B | `{13=false, 17=false}` (control: both true) | `{13=false, 17=false}` (both tunings) |

No divergence from RED's numbers. D-1..D-3 (mutations of the shipped module)
remain GATES' and were not run here.

**`bash scripts/gates.sh --fast` on the uncommitted GREEN tree (2026-10-02):**

    PASS         format (1s, observed 126)
    PASS         lint (1s, observed 126, floor 1)
    PASS         typecheck (4s, observed 24)
    PASS         unit (246s, observed 728, floor 507)
    UNCONFIGURED coverage
    PASS         build (0s, observed 88474)
    FAIL         harness (33s, exit 1)   -- project-counters: 39 passed, 1 failed:
                 "the working tree carries no stray .luau files" (actual:
                 ` M src/server/procedure/Procedure.luau`)

The one `harness` failure is the same uncommitted-tree precondition RED met; it
clears at the GREEN commit. Nothing else in `harness.log` failed. The full
`gates.sh` run was not made here - it belongs after the commit, in GATES.

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

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-10-02T02:47:45Z
    commit: d49a07a
    tree:   3ccc4ad37a808ddf968b7e192d5aa308548dc04c
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 126)
    PASS         lint (1s, observed 126, floor 1)
    PASS         typecheck (5s, observed 24)
    PASS         unit (220s, observed 728, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 88474)
    PASS         harness (39s, observed 40)
    UNCONFIGURED mutation

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

**PO rulings on RED's doubts (lead-po, 2026-10-02).**

1. **A wrong turn on B after the window has expired costs `failed_pair +
   wrong_value` (2 under shipped tuning). Kept.** It is two failed attempts, not
   one: the window ended unanswered (an event in its own right, §5 "handled in
   arrival order"), and the late wrong turn is then a fresh wrong turn on a live
   finale with no window open (F-7's last sentence). §5's "a failed attempt at
   the finale costs exactly 1" holds per attempt. No ACs touched; F-9 stands as
   written.
2. **`armed` and `dials[id]` deep-equal with no extra fields. Kept** — the
   Contract says "exactly". GREEN keeps the armed setting in `dials[A].setting`
   (F-4), not inside `armed`.
3. **`dial()` of an armed machine is unconstrained.** How an armed dial looks is
   `HUD-002`'s; this story pins state, not view.

**PO verification of RED (lead-po, 2026-10-02).** `lune run test` run
independently: `703 passed, 25 failed` in 2m37s — 24 in
`procedure_finale_test.luau` (15 on the missing `tick`/`partnerLamps`/`isComplete`
guards, 9 on the finale being `not_live` today) and 1 in `procedure_test.luau`
(the corrected AC-1 check, live set `{}` vs `{13, 17}`). Read the AC-4
(`wrongWithWindowProblems`) and AC-6 checks: exact deep-equals on result, dials,
log and lamps, inclusive edges at exactly the lamp range, and the "B's holder
at A" case asserting both lamps dark.

`bash scripts/gates.sh --fast` on the uncommitted RED tree (lead-po, 2026-10-02):

    PASS         format (0s, observed 126)
    PASS         lint (1s, observed 126, floor 1)
    PASS         typecheck (3s, observed 24)
    FAIL         unit (141s, exit 1)       -- 703 passed, 25 failed: exactly the 25 above
    PASS         build (1s, observed 86200)
    FAIL         harness (26s, exit 1)     -- project-counters: 39 passed, 1 failed:
                 "the working tree carries no stray .luau files" (RED's files uncommitted)

Admissible: the only `unit` failures are the story's assertions, and the one
`harness` failure is the uncommitted-tree precondition. The RED commit (test
files + counter baselines, frontmatter `phase: RED`, per check-boundaries 3j)
clears it; the baselines themselves (126/126/24) already pass.


**PO verification of GREEN (lead-po, 2026-10-02).**

- Freeze: `bash scripts/frozen.sh verify` → `frozen: OK — 9 path(s) unchanged since the snapshot for PROC-002`
  (FinaleContract, TurnContract, Deep, Contract, the four procedure test files,
  `.claude/tests/project-counters.test.sh`).
- `lune run test` (independent run): `728 passed, 0 failed`.
- Discrimination, two mutations of the shipped module via `scripts/mutate.sh`,
  each restored and verified byte-for-byte; counts predicted by RED's controls
  table:

  | Mutation | Predicted | Measured |
  |---|---|---|
  | `partnerLamps` reads `instance.turn_range_studs` instead of `partner_lamp_range_studs` | 1 (lamp-geometry) | `727 passed, 1 failed` — `AC-6/F-11: with the finale live, A's lamp is lit exactly when…` |
  | `expire` dates the disarm from `armed.closesAt` instead of `now` | 4 (expiry, shipped expiry, reset-then-rearm, F-9 arm-after-expiry) | `724 passed, 4 failed` — exactly those four |

- `bash scripts/gates.sh --fast` on the uncommitted GREEN tree:

      PASS         format (0s, observed 126)
      PASS         lint (1s, observed 126, floor 1)
      PASS         typecheck (3s, observed 24)
      PASS         unit (116s, observed 728, floor 507)
      UNCONFIGURED coverage
      PASS         build (2s, observed 88474)
      FAIL         harness (30s, exit 1)   -- 39 passed, 1 failed: "no stray .luau"
                                              (the modified Procedure.luau, uncommitted)

  The GREEN commit clears the one harness failure; re-checked after it below.

**PO rulings on GREEN's findings (lead-po, 2026-10-02).**

4. **A `not_live` turn on a decoy (or any non-finale machine) with a window open
   leaves the window open.** Kept. §5 closes the window on "a wrong turn on
   either finale machine"; a decoy turn is not an attempt at the finale. It is
   charged as any `not_live` turn. Unpinned by a test; noted for `PROC-003`.
5. **F-9 applies expiry before every refusal, `unknown_machine` included.** Kept;
   F-9 says "a `turn` at `now > armed.closesAt` first applies exactly F-8", with
   no exception, and the window's end is an event that precedes the turn in
   arrival order.

After the GREEN commit `d49a07a`: `bash .claude/tests/project-counters.test.sh` →
`project-counters: 40 passed, 0 failed`. Every `--fast` gate is green.

**GATES (lead-po, 2026-10-02).** D-1, D-2 and D-3 run before `gates.sh`, results
under `## Deferred verifications`. Then `bash scripts/gates.sh` (full run, recorded
by itself in `## Gate results`): `All required gates passed (6 ran, 3 unconfigured,
0 known).` No source change was needed in GATES, so no feature-developer dispatch.
No gate was added or changed, so `## Gate probes` is not required.

**REVIEW → DONE (lead-po, 2026-10-02).** PR
https://github.com/ryanczhang7/first-roblox/pull/48 merged at
2026-10-02T03:17:36Z as `f6232d5`. CI on the PR head `f3f36c8`: `boundaries` pass
(7s), `gates` pass (2m45s,
https://github.com/ryanczhang7/first-roblox/actions/runs/36958367546). Timings
read from that log: harness self-test 1m34s, `Run gates` 53s — format 0s, lint
0s, typecheck 2s, unit 40s (728 tests), build 0s, harness 9s. The job sets no
`timeout-minutes`, so the runner default applies; nothing is near a limit. No gate
was pending CI.
