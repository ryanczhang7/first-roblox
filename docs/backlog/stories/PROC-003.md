---
id: PROC-003
title: Instability shortens the clock, darkens rooms and ends the round in a fixed order
slug: instability-shortens-the-clock-darkens-r
epic: EPIC-05
type: feature
status: done
phase: DONE
branch: story/PROC-003-instability-shortens-the-clock-darkens-r
depends_on: [PROC-002]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-05`. What instability does (`mechanics.md` §5; `tuning.md` §4; G7 and
G12):

- **Clock.** Each point removes `instability_clock_penalty_seconds`
  immediately.
- **Blackout.** At each multiple of `instability_blackout_threshold` below
  `instability_max`, the server draws `blackout_rooms_per_threshold` rooms. It
  draws without replacement from rooms not yet dark, with probability
  proportional to each room's weight. A room's weight is the sum over its
  uncommitted steps of `blackout_weight_live_step` (live or armed) and
  `blackout_weight_waiting_step` (waiting). Decoys and committed steps weigh 0.
  If every lit room weighs 0, the draw is uniform among lit rooms. A dark room
  is never drawn again, and blackout is permanent. The draw uses the round
  seed's `rng:derive("blackout")`.
- **Loss** at `instability_max`.
- **Outcomes**, and the order they resolve in within one event: a win
  (`won / procedure_complete`) first, then `lost / instability`, then
  `lost / clock`.

`architecture.md` D11 makes the Procedure the owner of the round's deadline:
`roundStart + round_seconds − penalties`. The phase machine's own clock is a
backstop that can never fire first.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a Procedure started at `t0`, when `Procedure.deadline` is
  read, then it is `t0 + round_seconds`. After k instability points, it is
  `t0 + round_seconds − k × instability_clock_penalty_seconds`.
- **AC-2** — Given instability rising from `threshold − 1` to `threshold`, when
  the turn that caused it returns, then exactly `blackout_rooms_per_threshold`
  lit rooms are dark, and they were drawn by the specified weighting. Rising to
  a non-multiple darkens nothing. Reaching `instability_max` darkens nothing,
  because the round ends first.
- **AC-3** — Given a facility where one lit room holds all the uncommitted
  steps and the other lit rooms hold only decoys or committed steps, when a
  crossing happens, then that room is always the one darkened. Given rooms of
  weights 3 and 1 and 20,000 seeded crossings, the heavier room is chosen with
  frequency 0.75 ± 0.02.
  *Controls:* a uniform draw must fail both. It picks the zero-weight rooms
  and scores about 0.5 on the second.
- **AC-4** — Given every lit room at weight 0, when a crossing happens, then a lit
  room is still darkened (a uniform draw). Given every room already dark, then
  nothing happens and nothing raises. An already-dark room is never drawn.
- **AC-5** — Given one seed, when the same sequence of wrong turns is replayed,
  then the same rooms go dark in the same order. Drawing from the `"blackout"`
  sub-stream moves no generator draw.
- **AC-6** — Given the last finale commit, when it arrives before the deadline,
  then `tick` or `turn` yields `{ result = "won", reason =
  "procedure_complete" }`. When a wrong turn takes instability to
  `instability_max` **and** its penalty takes the clock to 0 or below, then the
  outcome is `lost / instability`. When the deadline passes by time alone, it is
  `lost / clock`.
  *Control:* an implementation that checks the clock before instability must
  fail the second clause.
- **AC-7** — Given the Procedure has produced an outcome, when any later turn
  or tick arrives, then the state and the outcome do not change. A decided round
  stays decided.
- **AC-8** — Given a dark room, when `Procedure.isDark(room)` is read, then it is
  true for the rest of the round. `VIEW-001` reads this to withhold lens
  contents there.

## Contract

**Module.** `src/server/procedure/Procedure.luau`, extended. This story adds
(amended by the PO at PLANNED → RED, 2026-10-02; see I-1 and I-2 for why the
drafted `blackoutRng` field and the four-argument `start` were replaced):

    ProcedureState.startedAt: number                -- the `now` passed to start
    ProcedureState.roundSeconds: number             -- the `roundSeconds` passed to start
    ProcedureState.penaltySeconds: number           -- 0 at start
    ProcedureState.dark: { [number]: boolean }      -- Layout room id -> dark; {} at start
    ProcedureState.outcome: PhaseMachine.Outcome?   -- nil at start
    ProcedureState.roundSeed: number                -- the `roundSeed` passed to start
    ProcedureState.blackoutDraws: number            -- nextInteger calls made on the blackout stream; 0 at start
    Procedure.start(facility, now, tuning, roundSeed: number, roundSeconds: number) -> ProcedureState   -- CHANGED
    Procedure.deadline(state) -> number
    Procedure.isDark(state, room: number) -> boolean
    Procedure.blackoutWeights(state) -> { [number]: number }   -- every LIT room id -> its weight (0 included)
    Procedure.drawRoom(weights: { [number]: number }, rng: Rng.Rng) -> number?   -- one draw (I-5); exported for AC-3
    TurnResult refused reason gains "round_over"                -- CHANGED (additive), I-7

- **Changed signature: `Procedure.start` gains `roundSeed` and `roundSeconds`.**
  Callers, checked against `main` at `66748b6` with
  `rg "\.start\(" src tests lune` (the `P.start` calls) — **tests only**, no
  production caller:

      tests/helpers/TurnContract.luau:247, :1464           (PROC-001)
      tests/helpers/FinaleContract.luau:122                (PROC-002)
      tests/server/procedure_test.luau:67                  (PROC-001)
      tests/server/procedure_finale_test.luau:74           (PROC-002)
      tests/server/procedure_controls_test.luau:73         (PROC-001 stand-in's own start)
      tests/server/procedure_finale_controls_test.luau:99  (PROC-002 stand-in's own start)

  RED updates every one in this RED: these are this epic's own tests, and
  changing the fixture call is test data, not an assertion. RED's handoff states
  the list was re-checked against the tree.
- `Outcome` is the phase machine's type (`PhaseMachine.Outcome`, already required
  by `Procedure` since `PROC-002`).

**Pinned semantics (PO, at PLANNED → RED, 2026-10-02).** These continue P-1..P-11
(`PROC-001`) and F-1..F-12 (`PROC-002`), which all still hold except where I-6
and I-7 extend them. RED may amend any block below in place, with a dated reason
next to it; GREEN builds what the amended block says.

- **I-1. No live `Rng` in the state.** `Rng` streams are closures with mutable
  state (`src/shared/Rng.luau`, `newStream`); a stream stored in the state would
  be shared by every copy, so a draw on a new state would advance the old
  state's stream too, breaking D3, P-11 and determinism. Instead the state holds
  `roundSeed` and `blackoutDraws`. A draw builds
  `Rng.fromSeed(state.roundSeed):derive("blackout")`, advances it by
  `blackoutDraws` calls of `nextNumber()` (each `nextInteger` consumes exactly
  one `nextNumber`), draws, and stores `blackoutDraws + <draws made>`. So the k-th blackout draw
  of a round is the k-th `nextInteger` of that stream, whoever's state it is
  made on.
- **I-2. `roundSeconds` is passed in.** `round_seconds` lives in
  `Tuning.round` (`src/shared/Tuning.luau`), not in `MechanicsTuning`, and
  `start`'s `tuning` is `MechanicsTuning` (P-1). The session passes
  `RoundConfig.fromTuning(Tuning).roundSeconds` (`SLICE-005`). Tests pass their
  own value.
- **I-3. The clock.** `deadline(state) = startedAt + roundSeconds −
  penaltySeconds`. Every instability point charged, by any path (`wrong_setting`,
  `not_live`, a failed pair from expiry), adds `points ×
  actuation.instability_clock_penalty_seconds` to `penaltySeconds` in the same
  event. **The clock is out at `now >= deadline`** (the remaining clock "reaches
  0", §5).
- **I-4. Crossings.** When a charge takes instability from `old` to `new`, every
  `v` in `old+1 .. new` with `v % instability_blackout_threshold == 0` **and**
  `v < instability_max` is one crossing, handled in ascending order. (The shipped
  charges are all 1; tests that override a charge to 2 can cross twice.) Each
  crossing darkens `blackout_rooms_per_threshold` rooms, one draw at a time,
  recomputing the lit set between draws. A crossing with no lit room does
  nothing and consumes no draw.
- **I-5. The weights and the draw.** `blackoutWeights(state)` maps every lit
  room (in `facility.layout.rooms`, not in `dark`) to the sum over the track
  machines in it that are not committed of `blackout_weight_live_step` if
  `isLive` (an armed machine is live, F-3) or `blackout_weight_waiting_step`
  otherwise. Decoys and committed machines add 0; a room with neither is present
  with weight 0. `drawRoom(weights, rng)`: let `rooms` be the keys in ascending
  id. If `rooms` is empty, return nil and draw nothing. If the weights sum to
  `W > 0`: `r = rng:nextInteger(1, W)`, return the first room whose cumulative
  weight is `>= r` (so a zero-weight room is never returned). Otherwise (all
  zero): `i = rng:nextInteger(1, #rooms)`, return `rooms[i]`. Exactly one
  `nextInteger` per non-nil draw. A crossing calls `drawRoom(blackoutWeights(s),
  <the stream of I-1>)`.
- **I-6. One event, in this order** — `turn` and `tick` both:
  1. If `outcome ~= nil`: nothing changes (AC-7). `tick` returns `(state,
     state.outcome)`; `turn` returns `(state, { kind = "refused", machineId =
     machineId, reason = "round_over" })`.
  2. Expire an open window (F-8/F-9), charging through I-3/I-4/I-6.4.
  3. If no outcome yet and `now >= deadline`: `outcome = { result = "lost",
     reason = "clock" }`. A `turn` then returns `refused / round_over` with that
     state (the turn arrived after the round ended).
  4. Otherwise (`turn` only) evaluate the turn as `PROC-001`/`PROC-002` say. Any
     charge it makes runs I-3 and I-4, then: if instability `>= instability_max`
     → `lost / instability` (no blackout at the max, I-4); **else** if `now >=
     deadline` → `lost / clock`. A commit that completes the Procedure
     (`isComplete`) → `won / procedure_complete`.
  Steps 2's charge uses the same post-charge check as step 4 (instability first,
  then clock). So within one event a win is decided before anything else can
  be (a commit charges nothing), instability before clock (§5, "Same-tick
  ordering").
- **I-7. `round_over` (additive to `TurnResult`).** The refusal for a turn on a
  decided round, or one arriving at `now >= deadline`. It is free like every
  refusal and writes no log entry. P-9's "state deep-equal to the one passed"
  holds when the round was already decided before the call.
- **I-8. `tick`'s second value is `state.outcome`** of the returned state — nil
  until decided, then the same outcome on every later tick. `turn` exposes the
  outcome through the returned state's `outcome`.
- **I-9. `isDark(state, room)`** is `state.dark[room] == true`; false for an
  unknown room id. Blackout is permanent: nothing ever clears `dark`.
- **I-10. Non-mutation** (P-11, F-12) extends to `deadline`, `isDark`,
  `blackoutWeights` and `drawRoom`'s `weights` (the `rng` it is handed is
  advanced, by design).

**The PROC-001/002 fixtures need room on the clock and below the max — RED's to
fix.** With this story every charge shortens the clock and the round ends at
`instability_max`. The `TurnContract` and `FinaleContract` fixtures charge up to
several points and turn at times up to `NOW + 105` and beyond; under shipped
values (`instability_max` 5, 20 s per point) some existing sequences would now
end the round and turn later calls into `refused / round_over`. RED passes those
fixtures a `roundSeconds` and, where needed, an `instability_max` override large
enough that no PROC-001/002 check ends the round, and lists in the handoff each
check it re-read against I-6. That is fixture data, not a weakened assertion:
those checks pin turn semantics, not round end.

**Test files.** `tests/server/procedure_outcome_test.luau` and
`tests/server/procedure_outcome_controls_test.luau`, checks in
`tests/helpers/OutcomeContract.luau`, following the `TurnContract` /
`FinaleContract` pattern. A facility whose layout has rooms of known weights may
be hand-built for AC-3/AC-4; reuse `TurnContract`'s fixture where it fits.

**Epic check (PO, 2026-10-02).** EPIC-05 done-when #4 is this story's whole:
clock penalty (AC-1), blackout crossings and weighted draw (AC-2..AC-5), loss at
the max and the single-event order win → instability → clock (AC-6, AC-7).
Done-when #5 is `PROC-005`. No gap.

**Gate.** `unit` (required) runs `lune run test`. `required_gates` stays `[]`.

**Oracle partition.** AC-1, AC-2, AC-4 and AC-6 to AC-8 are **settled** by
`mechanics.md` §5 and `tuning.md` §4: read every number from `MechanicsTuning`
or `Tuning`. AC-3's first clause is **settled** (zero weight is never drawn
while a positive weight exists). Its second clause is **oracle-free**, a
frequency with a uniform draw as its control. AC-5 is **mechanical**.

## Deferred verifications

**D-1. The weighting is what separates the rooms.** Use `scripts/mutate.sh` to
make every weight 1. AC-3 **must** then fail on both clauses. RED cannot run
this. Owner: GATES.

**D-2. Order of outcomes.** Use `scripts/mutate.sh` to swap the instability and
clock checks. AC-6's second clause **must** then fail. Owner: GATES.

**D-3. A decided round stays decided.** Use `scripts/mutate.sh` to remove the
`outcome ~= nil` guard (I-6 step 1) from `turn`. AC-7 **must** then fail. RED
cannot run this. Owner: GATES.

**D-4. The draw reads the right stream.** Use `scripts/mutate.sh` to change the
`"blackout"` label in the derive to another string. AC-5's equivalence with an
independently built `Rng.fromSeed(seed):derive("blackout")` stream **must**
then fail. RED cannot run this. Owner: GATES.

### Results (lead-po, GATES, 2026-10-02, against `dab4ac5`)

Every run is `bash scripts/mutate.sh src/server/procedure/Procedure.luau '<EXPR>' -- lune run test`;
each restore was verified byte-for-byte by `mutate.sh`, and `git status`
afterwards showed only the story file modified. Unmutated: `763 passed, 0 failed`.

**D-1 — RESULT: fails as required.** `s/total += w$/total += 1/;s/cumulative += weights\[room\]/cumulative += 1/`
(every weight counts as 1, in both the total and the cumulative walk):

    FAIL  procedure_outcome_test :: AC-3 (oracle-free): over 20,000 draws of drawRoom({ [4] = 3, [7] = 1 }) on one "blackout" stream, room 4 is drawn with frequency 0.75 +/- 0.02
    FAIL  procedure_outcome_test :: AC-3/I-5: drawRoom is exactly one nextInteger(1, W) mapped to the first room in ascending id whose cumulative weight reaches it ...
    FAIL  procedure_outcome_test :: AC-3: with every uncommitted step in one lit room and the other lit rooms at weight 0 (decoys, a committed step), the crossing darkens that room on every one of 40 seeds
    760 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T055411Z.652544.bak) ===

Both AC-3 clauses fail: the zero-weight room is drawn, and the frequency leaves
the band. These are exactly the three checks RED's uniform-draw control fired.

**D-2 — RESULT: fails as required.** Lines 286–289 rewritten to test
`now >= deadline` first (→ `lost / clock`), then `instability >= instability_max`:

    FAIL  procedure_outcome_test :: AC-6/I-6: a wrong turn that reaches instability_max AND whose penalty takes the clock to exactly 0, or below it, records lost / instability - never lost / clock
    762 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T055724Z.654757.bak) ===

**D-3 — RESULT: fails as required.** `502,504d` deletes `turn`'s I-6 step 1
guard (`if state.outcome ~= nil then return … round_over end`). `mutate.sh`
reported 66 lines changed, because every later line shifts up by 3.

    FAIL  procedure_outcome_test :: AC-7/I-7: once won, lost / instability or lost / clock, every later turn - wrong, correct, decoy, finale, unknown id, non-holder - is refused / round_over on a deep-equal state, and every later tick returns t…
    762 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T055953Z.656779.bak) ===

**D-4 — RESULT: fails as required.** `258s/derive("blackout")/derive("blackouts")/`:

    FAIL  procedure_outcome_test :: AC-2/AC-6: reaching instability_max (6, ...) is lost / instability with no blackout at the max - still two rooms dark, still two draws ...
    FAIL  procedure_outcome_test :: AC-2/I-4: a 2-point charge from 2 to 4 skips the value 3 but still crosses it once (two rooms dark), and 4 -> 5 darkens nothing more
    FAIL  procedure_outcome_test :: AC-2/I-5: rising from 2 to 3 darkens EXACTLY blackout_rooms_per_threshold (2) rooms - the two drawRoom(blackoutWeights(s), stream) returns on an independent Rng.fromSeed(seed):derive("blackout") stream ...
    FAIL  procedure_outcome_test :: AC-5/I-1: one seed replays four crossings as the same four rooms in the same order, and that order is what drawRoom predicts on an independent "blackout" stream - for two seeds
    759 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../src_server_procedure_Procedure.luau.20261002T060155Z.658939.bak) ===

AC-5's equivalence check fails, as required. RED's `derive("instance")` control
fired five checks; this label fires four. The AC-4 all-zero-weight check does not
fire. The likely cause, not checked: its uniform draw over the lit rooms lands
on the same room from both streams, which a single draw can do by chance. Either
way the four checks that predict rooms from more than one draw all catch the
change, and AC-5's equivalence, which is what D-4 requires, fails.

## Out of scope

- Telling players (`VIEW-003` carries instability, the deadline and dark rooms,
  and `HUD-001` shows them).
- Feeding the outcome to the phase machine (`SLICE-005`).
- `unwinnable`, which has no M3 trigger (`mechanics.md` §8).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write PROC-003` from `.claude/harness/models.conf`.
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
- PLANNED → RED contract pinning - `lead-po` - `claude-opus-5-5`. 2026-10-02.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1). The dispatch passed
  `model: fable` explicitly; the agent self-reports Fable 5.1. 2026-10-02.
- GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5). The dispatch passed
  `model: opus` explicitly; the agent self-reports Opus 5.5. 2026-10-02.

## Test plan

All unit level, on the pure module, through `lune run test`. The checks live
once in `tests/helpers/OutcomeContract.luau`, are applied to the real module in
`tests/server/procedure_outcome_test.luau`, and are observed to accept a
reference stand-in and to fire against one-defect stand-ins in
`tests/server/procedure_outcome_controls_test.luau` - the `TurnContract` /
`FinaleContract` pattern.

**Fixtures.** `TurnContract`'s facility (rooms: 11, 12, 19 in 1; 13, 14 in 2;
15, 16 in 3; 17, 18 in 4) under the shipped tuning with eleven overrides:
clock penalty **7** (not 20), blackout threshold **3** (not 2), rooms per
threshold **2** (not 1), `instability_max` **6** (not 5; a multiple of the
threshold so a blackout fired at the max is visible), live weight **5**,
waiting weight **2** (not equal, not 1), plus PROC-001/002's turn range 7,
window 3, reset 5, wrong value 1, out of order 2, failed pair 1. Start weights
are therefore `{ 1 = 7, 2 = 7, 3 = 4, 4 = 2 }` (recomputed independently in
the controls file). `start` is given `roundSeed = 9001`, `roundSeconds = 200`
(deadline 300), or a scenario's own value. An "every point" variant (threshold
1, one room per crossing, max 10) and a hand-built three-room facility (every
track step in room 1, a decoy in room 2, step 31 + a decoy in room 3; with 31
committed room 1 weighs 14 and rooms 2, 3 weigh 0) serve AC-3's first clause,
AC-4 and AC-5. Two "shipped" rows use `MechanicsTuning` unmodified and
`Tuning.round.round_seconds`.

**`procedure_outcome_test.luau` - the real module (23 tests, all red in RED)**

| Test (OutcomeContract check) | Asserts | AC / I |
|---|---|---|
| exports (inline) | `deadline`, `isDark`, `blackoutWeights`, `drawRoom` are functions, alongside the seven existing | Contract |
| `startCarriesTheRoundFieldsAndTheNewExportsAnswerInShape` | `startedAt = 100`, `roundSeconds = 200`, `penaltySeconds = 0`, `dark = {}`, `outcome = nil`, `roundSeed = 9001`, `blackoutDraws = 0` (deep-equal); `deadline = 300`; `isDark` false for 1..4 and 99; `blackoutWeights = { 7, 7, 4, 2 }`; `tick` at start returns a deep-equal state and nil, `state.outcome` nil | Contract, I-1, I-2, I-8 |
| start stores what it is handed (inline) | two starts with seeds 11/12 and 300/400 s differ in `roundSeed`, `roundSeconds`, `deadline` | I-1, I-2 |
| `deadlineIsStartPlusRoundSecondsLessThePenaltyPerPoint` | 300; 293 after a wrong setting; 279 after a not_live decoy (+2 at once); 300 with every ordinary step committed; 300 with A armed; 293 after the window expires by tick. `penaltySeconds` = points x 7 throughout | AC-1, I-3 |
| `underTheShippedTuningTheDeadlineReadsLiterally` | 520, 500, 480 | AC-1 |
| `risingToJustBelowTheThresholdDarkensNothing` | at 1 and 2: `dark = {}`, `blackoutDraws = 0`, outcome nil | AC-2 |
| `crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw` | weights at 2 are start's; 2 -> 3 darkens exactly the two rooms `drawRoom(weights, Rng.fromSeed(9001):derive("blackout"))` returns (first removed before the second), `blackoutDraws = 2`, `isDark` agrees, outcome nil, `blackoutWeights` has exactly the lit rooms as keys | AC-2, AC-3 (weighting), I-1, I-4, I-5 |
| `aChargeThatJumpsOverTheMultipleStillCrossesIt` | 2 -> 4 by one not_live charge darkens the same two rooms (crossing 3 handled); 4 -> 5 adds none | AC-2, I-4 |
| `reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout` | at 5 outcome nil; the sixth point's turn is `rejected / wrong_setting`, instability 6, `outcome = lost / instability`, still two rooms dark, still two draws | AC-2 (third sentence), AC-6 |
| `oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened` | three-room facility, 40 seeds: weights `{ 14, 0, 0 }`; the crossing darkens exactly room 1 every time | AC-3 first clause (settled) |
| `theHeavierOfTwoRoomsIsDrawnThreeTimesInFour` | 20,000 `drawRoom({ [4] = 3, [7] = 1 }, stream)` on seed 9001's "blackout" stream: frequency of 4 in [0.73, 0.77]; only 4 or 7 ever returned | AC-3 second clause (oracle-free) |
| `drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt` | scripted rng: `{1=3,2=1}` r=1,3 -> 1, r=4 -> 2 with one `nextInteger(1, 4)`; `{1=0,2=3,3=0,4=1}` r=1,3 -> 2, r=4 -> 4 (zero rooms skipped); `{9=1,2=2}` r=2 -> 2, r=3 -> 9 (ascending id, `(1, 3)`); all-zero `{2,5,9}` i=1 -> 2, i=3 -> 9 with `(1, 3)`; `{6=0}` -> 6 with `(1, 1)`; `{}` -> nil, no call; weights never mutated; never `nextNumber`/`shuffle`/`derive` | I-5, I-10 |
| `everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing` | three-room facility, threshold 1: crossing 1 -> room 1; crossing 2 (both lit rooms at 0) -> the room `drawRoom` predicts, `blackoutWeights` then one key at 0; crossing 3 -> the last; crossing 4 (none lit) -> nothing dark added, `blackoutDraws` stays 3, `blackoutWeights = {}`, no raise, instability 4, outcome nil | AC-4, I-4 |
| `theSameSeedReplaysTheSameRoomsInTheSameOrder` | every-point tuning: four crossings twice on seed 9001 give the same four rooms in order, equal to `predictDraws` on the independent stream; seed 9002 likewise | AC-5, I-1 |
| `drawingFromTheBlackoutStreamMovesNoGeneratorDraw` | `Generator.generate(assignment, 9001, MechanicsTuning)` deep-equal before/after four blackouts on roundSeed 9001; `Rng.fromSeed(9001):derive("instance")` first 8 draws unchanged | AC-5 |
| `theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver` | 50 s round: A armed at 149, B at 149.999 -> `committed`, `outcome = won / procedure_complete`, `isComplete` true, tick at 250 returns `won` twice; B at exactly 150 -> `refused / round_over`, `outcome = lost / clock`, nothing committed, no log entry | AC-6 first clause, I-3, I-6 step 3, I-7, I-8 |
| `instabilityMaxAndTheClockInOneTurnRecordInstability` | 50 s round, sixth point at 108 (deadline 115 -> 108, clock exactly 0) and 49 s round, sixth point at 110 (114 -> 107, below 0): both `lost / instability`; the round was undecided before; the turn is the ordinary rejection; `deadline` moved | AC-6 second clause, I-6 step 4 |
| `theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline` | tick at 299.999 no-op; at 300 `lost / clock` as second value AND `state.outcome`, nothing else changed; at 1300 the same; after one point tick at 292.999 no-op and at 293 lost; a correct turn at 300 -> `refused / round_over` on input + `lost / clock` | AC-6 third clause, I-3, I-6 step 3, I-7, I-8 |
| `underTheShippedTuningFiveWrongTurnsLoseByInstabilityWithTwoRoomsDark` | shipped tuning, 420 s: turns 11, 14, 18, 19, 11 at 100..104: dark count 0, 1, 1, 2, 2; outcome nil until the fifth, then `lost / instability`; deadline 420 (clock not out) | AC-6 shipped, AC-2 shipped |
| `tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound` | with the finale live: weights `{ 0, 5, 0, 5 }`; two wrong finale turns then an expired window -> instability 3, deadline 279, two rooms dark via `tick`, second return nil; two more wrong turns and another expiry -> `tick` returns `lost / instability` twice, instability 6, `armed` nil, still two dark | I-6 step 2, I-3, I-4, I-8 |
| `aDecidedRoundStaysDecided` | won, lost / instability, lost / clock (A still armed): six kinds of later turn (wrong, correct, decoy, finale, unknown id, non-holder) at two later times -> `refused / round_over` echoing the id, state deep-equal; ticks at three times -> same outcome, same state; the decided state never mutated | AC-7, I-6 step 1, I-7 |
| `isDarkIsTrueForTheRestOfTheRound` | after the crossing the two dark rooms read true, lit rooms and 99 false, through five commits, a tick, arming, completing and the win; `dark` never shrinks | AC-8, I-9 |
| `noOutcomeCallMutatesItsArguments` | `deadline`, `isDark`, `blackoutWeights`, `drawRoom`'s weights, a crossing turn, a clock-ending tick, a round_over turn: arguments deep-equal; a crossing downstream does not reach back | I-10 |

**`procedure_outcome_controls_test.luau` - stand-ins (12 tests, all green in RED)**

| Test | Stand-in defect | Fires exactly / measures |
|---|---|---|
| baseline | none (the reference) | 0 of 21 outcome checks |
| audit | none | 0 of 20 `TurnContract` checks, 0 of 22 `FinaleContract` checks (the mechanical half of the I-6 audit) |
| fixtures: overrides distinct | - | every override differs from shipped and from what it must be told from; max is a multiple of the threshold; shipped 420 / 20 / 5 / 2 / 1 / 1 / 1 as the literal checks assume |
| fixtures: weights recomputed | - | `{ 7, 7, 4, 2 }` from the placement and tracks, without the module |
| fixtures: three-room facility | - | every step in room 1 except 31 (room 3); decoys one each in rooms 2, 3; ids not indices; positions distinct |
| AC-3 control | uniform draw | frequency **0.50355** (reference **0.7527**); fires zero-weight, frequency, drawRoom mapping |
| AC-6 control | clock checked before instability | sixth point on a 49 s round: **lost / clock** (reference lost / instability); fires the ordering check |
| AC-7 control | no outcome guard | fires the decided-round check |
| AC-2 control | blackout at the max | **4** dark rooms at the max (reference **2**); fires max-darkens-nothing and expiry-to-the-max |
| I-1 control | `derive("instance")` | fires the five checks that predict WHICH rooms (crossing, jump, max, AC-4, replay) |
| I-1 control | ignores `blackoutDraws` | fires the four-crossing replay check only (measured: every two-draw check coincides on seed 9001) |
| I-3 control | out at `now > deadline` | fires the finale-at-deadline and tick-at-deadline checks |

**PROC-001/002 updated.** `start` gains two arguments in every fixture call
(`TurnContract.ROUND_SEED = 4242`, `ROUND_SECONDS = 1000`);
`FinaleContract.OVERRIDES` gains `instability_max = 100`; both controls'
reference stand-ins accept and ignore the new arguments. No assertion changed.

## Handoff: RED -> GREEN

**Model this RED resolved to:** Fable 5.1 (`claude-fable-5-1`), the `fable` row
of `## Model guidance`. The dispatch message named no `model:` override; the
agent definition's own `model:` is what I ran on. 2026-10-02.

### The command

    lune run test

runs the whole suite (`tests/**/*_test.luau`); there is no per-file switch. The
`unit` gate is the same command. Snapshot the test files before GREEN starts:

    bash scripts/frozen.sh snapshot tests/helpers/OutcomeContract.luau tests/helpers/TurnContract.luau \
      tests/helpers/FinaleContract.luau tests/server/procedure_outcome_test.luau \
      tests/server/procedure_outcome_controls_test.luau tests/server/procedure_test.luau \
      tests/server/procedure_finale_test.luau tests/server/procedure_controls_test.luau \
      tests/server/procedure_finale_controls_test.luau

### The failure, verbatim

From `bash scripts/gates.sh --fast` on the uncommitted RED tree, 2026-10-02
(unit gate log `.claude/state/gate-logs/unit.log`):

    740 passed, 23 failed

All 23 are `tests/server/procedure_outcome_test.luau` (every test in it); the
12 new control tests pass, and the 728 that passed before this RED still pass.
Every failure block, abridged to its first line where the lines repeat:

    FAIL  tests/server/procedure_outcome_test.luau :: Contract: Procedure exports deadline, isDark, blackoutWeights and drawRoom as plain field functions, alongside PROC-001/002's seven
          ...procedure_outcome_test:80: the Contract's exports are not all functions: Procedure.deadline is nil, Procedure.isDark is nil, Procedure.blackoutWeights is nil, Procedure.drawRoom is nil

    FAIL  tests/server/procedure_outcome_test.luau :: Contract: start stores the roundSeed and roundSeconds it was handed, not constants - two starts with different values differ in exactly those fields and in deadline
          ...procedure_outcome_test:95: roundSeed is nil / nil, expected 11 / 12

    FAIL  tests/server/procedure_outcome_test.luau :: AC-7/I-7: once won, lost / instability or lost / clock, every later turn - wrong, correct, decoy, finale, unknown id, non-holder - is refused / round_over on a deep-equal state, and every later tick returns the same outcome and the same state
          AC-7/I-7: once decided, every later turn is refused / round_over on a deep-equal state and every later tick returns the same outcome:
    won: precondition - state.outcome is nil, expected { reason = "procedure_complete", result = "won" }
    lost / instability: precondition - state.outcome is nil, expected { reason = "instability", result = "lost" }
    lost / clock (with A still armed): precondition - state.outcome is nil, expected { reason = "clock", result = "lost" }

    FAIL  tests/server/procedure_outcome_test.luau :: Contract/I-1/I-2: start(facility, now, tuning, roundSeed, roundSeconds) carries startedAt, ... tick at start returns the state and nil
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-1/I-3: deadline is startedAt + roundSeconds minus instability_clock_penalty_seconds (the fixture's 7, not 20) per point, ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-1 under the SHIPPED tuning: with round_seconds 420 the deadline is t0 + 420, then 500 after one point and 480 after two ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-6: the last finale commit at deadline - 0.001 is won / procedure_complete ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-6/I-6: a wrong turn that reaches instability_max AND whose penalty takes the clock to exactly 0, or below it, records lost / instability ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-6/I-3/I-8: tick at deadline - 0.001 changes nothing; at exactly the deadline it is lost / clock ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-6 under the SHIPPED tuning: five wrong turns lose by instability (max 5) ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: I-6 step 2: an expired finale window charges through the clock (7 s), crosses the threshold ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: I-10: deadline, isDark, blackoutWeights, drawRoom's weights, a crossing turn, ...
          I-2: Procedure.deadline is nil, expected a function
    FAIL  ... :: AC-2: rising to 1 and to 2 (threshold 3) darkens nothing and draws nothing
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-2/I-5: rising from 2 to 3 darkens EXACTLY blackout_rooms_per_threshold (2) rooms ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-2/I-4: a 2-point charge from 2 to 4 skips the value 3 but still crosses it once ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-2/AC-6: reaching instability_max (6, a multiple of threshold 3) is lost / instability with no blackout at the max ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-3: with every uncommitted step in one lit room and the other lit rooms at weight 0 ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-4/I-4: with every lit room at weight 0 a crossing still darkens one lit room ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-5/I-1: one seed replays four crossings as the same four rooms in the same order ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-5: Generator.generate with seed s deep-equals itself before and after a Procedure on roundSeed s drew four blackouts ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-8/I-9: a dark room reads isDark true through commits, a tick, arming, completing and the win ...
          I-2: Procedure.isDark is nil, expected a function
    FAIL  ... :: AC-3 (oracle-free): over 20,000 draws of drawRoom({ [4] = 3, [7] = 1 }) on one "blackout" stream, room 4 is drawn with frequency 0.75 +/- 0.02
          I-2: Procedure.drawRoom is nil, expected a function
    FAIL  ... :: AC-3/I-5: drawRoom is exactly one nextInteger(1, W) mapped to the first room in ascending id whose cumulative weight reaches it ...
          I-2: Procedure.drawRoom is nil, expected a function

**Gate shape (`gates.sh --fast`, 2026-10-02, local Windows):**

    PASS         format (1s, observed 129)
    PASS         lint (2s, observed 129, floor 1)
    PASS         typecheck (5s, observed 24)
    FAIL         unit (193s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (1s, observed 88474)
    FAIL         harness (31s, exit 1) -> .claude/state/gate-logs/harness.log

`harness` is `project-counters: 39 passed, 1 failed`, the one being "the working
tree carries no stray .luau files", the uncommitted-tree precondition, which
goes green at the RED commit (the baselines themselves, 129/129/24, already
match: AC-7 passed). `stylua --check src tests lune` and `selene src tests lune`
are clean (0 errors, 0 warnings). No test in the suite owns a timeout; Lune's
runner has none, so there is nothing to budget. The three new files run in
under a second in isolation (the 20,000-draw frequency check included: 0.8 s
for the whole controls file); the suite's 193 s is the existing sweeps.

**Why it is the right failure.** The module loads (PROC-001/002 wrote it), so
no test fails at import. All 23 tests in `procedure_outcome_test.luau` are red,
each on its own first assertion, in one of three ways: (a) 19 tests fail on a
`need()` guard that names the missing export (`I-2: Procedure.deadline is nil,
expected a function`, or `isDark` / `drawRoom`) - the guard exists so a missing
export reads as a named absence rather than "attempt to call a nil value";
(b) the exports test lists all four missing by name; (c) two tests that use
only PROC-001/002's exports fail on behaviour: `start` ignores the new
arguments (`roundSeed is nil / nil, expected 11 / 12`), and no decided state
can be built (`won: precondition - state.outcome is nil, expected { reason =
"procedure_complete", result = "won" }`, and the same for both losses). None is
a timeout, config or lint error. Nothing else in the suite moved: the 728 that
passed before this RED still pass, the 12 new control tests pass, and the 46
PROC-001/002 tests stay green against the existing module - it ignores the two
extra `start` arguments and their fixtures were given room on the clock and
below the max (see the audit below).

### Files touched

| File | Change |
|---|---|
| `tests/helpers/OutcomeContract.luau` | NEW. Fixtures (TurnContract's with the overrides, the every-point variant, the three-room facility), scenario helpers, the 21 checks, `CHECKS`, `failures`, `heavierRoomFrequency`, `predictDraws`, `darkRooms`, `blackoutStream` |
| `tests/server/procedure_outcome_test.luau` | NEW. The 23 tests on the real module (`pcall(require)` + per-test re-check) |
| `tests/server/procedure_outcome_controls_test.luau` | NEW. Reference stand-in (P-1..P-11, F-1..F-12, I-1..I-10) + seven one-defect stand-ins + fixture assertions; 12 tests |
| `tests/helpers/TurnContract.luau` | `ROUND_SEED`, `ROUND_SECONDS`; `started` and the P-11 `start` guard pass them; header documents the new signature. No assertion changed |
| `tests/helpers/FinaleContract.luau` | `started` passes them; `OVERRIDES.actuation.instability_max = 100`; header says why. No assertion changed |
| `tests/server/procedure_test.luau` | the inline `start` call passes them |
| `tests/server/procedure_finale_test.luau` | the inline `start` call passes them (`Turn` required at the top) |
| `tests/server/procedure_controls_test.luau` | reference stand-in's `start` accepts and ignores `_roundSeed, _roundSeconds` |
| `tests/server/procedure_finale_controls_test.luau` | same; the F-2 fixtures test also requires `instability_max > 5` |
| `.claude/tests/project-counters.test.sh` | `BASE_FORMAT`/`BASE_LINT` 126 -> 129 (three new `.luau` under `tests/`), provenance comment; `BASE_TYPECHECK` and the narrow counts unchanged. GREEN adds no `.luau` file, so these are the post-GREEN counts too. Commit it in the RED commit (check-boundaries 3j freezes `.claude/tests/**` outside RED) |
| `docs/backlog/stories/PROC-003.md` | `## Test plan`, this section |

No manifest, no config, no source. `.claude/state/red/` holds my scratch
runner and probe; it is ignored and not for commit.

### Callers of `start` re-checked against the tree (2026-10-02)

    rg "\.start\(" src tests lune

finds, besides the definition, exactly the Contract's six sites - now updated -
plus the three new files: `TurnContract.luau:259` (`started`) and `:1482` (the
P-11 guard), `FinaleContract.luau:132`, `procedure_test.luau:68`,
`procedure_finale_test.luau:75`, `procedure_controls_test.luau:75` and
`procedure_finale_controls_test.luau:101` (the stand-ins' own `start`),
`OutcomeContract.luau:223`, `procedure_outcome_test.luau:93-94`,
`procedure_outcome_controls_test.luau:101, :571, :595`. `rg
"require\(.*procedure/Procedure"` finds only the three `*_test.luau` files that
test the real module. No production caller; the Contract's list holds.

### The export shape the tests pin (facts - a test already imports them)

Module: `src/server/procedure/Procedure.luau`, required as
`require("../../src/server/procedure/Procedure")` from `tests/server/`. Every
export is a plain field on the returned table, called with a dot.

- `Procedure.start(facility, now, tuning, roundSeed: number, roundSeconds: number) -> ProcedureState`.
  The returned state carries, **deep-equal**: `startedAt = now`, `roundSeconds`,
  `penaltySeconds = 0`, `dark = {}`, `outcome = nil` (absent or nil - `Deep`
  treats them alike), `roundSeed`, `blackoutDraws = 0`, alongside PROC-001/002's
  fields. `TurnContract.startReturnsTheContractState` checks six named fields
  only, so the new ones do not disturb it.
- `Procedure.deadline(state) -> number`, compared with `==` against
  `startedAt + roundSeconds - penaltySeconds`. `state.penaltySeconds` is read
  directly too (`== points x instability_clock_penalty_seconds`).
- `Procedure.isDark(state, room: number) -> boolean`, compared with `~= false`
  / `~= true` - a real boolean, `false` for an unknown id (99).
- `Procedure.blackoutWeights(state) -> { [number]: number }`, compared by
  `Deep.equal` against a map with **every lit room as a key, zero-weight rooms
  included, dark rooms absent**: `{ [1] = 7, [2] = 7, [3] = 4, [4] = 2 }` at
  start under the overrides; `{}` when every room is dark. Weight = sum over the
  room's track machines that are not committed of `blackout_weight_live_step`
  if `isLive` else `blackout_weight_waiting_step`; decoys 0.
- `Procedure.drawRoom(weights, rng) -> number?`, pinned by a scripted rng:
  **exactly one** `rng:nextInteger(1, W)` when the weights sum to `W > 0`,
  returning the first room in ascending id whose cumulative weight `>= r`;
  exactly one `rng:nextInteger(1, #rooms)` returning `rooms[i]` (ascending id)
  when every weight is 0; `nil` and **no call** for `{}`. It must not call
  `nextNumber`, `shuffle` or `derive` on the rng it is handed (the scripted rng
  raises on those). `weights` is not mutated.
- The blackout stream: the k-th draw of a round equals the k-th `nextInteger`
  of an independent `Rng.fromSeed(state.roundSeed):derive("blackout")`. The
  tests predict rooms with `drawRoom(weights, thatStream)` and compare against
  `state.dark`; `state.blackoutDraws` must count every non-nil draw (2 after a
  crossing of 2 rooms; unchanged by a crossing with no lit room).
- `state.dark` is read as `dark[room] == true`; `darkRooms` lists keys whose
  value is `true`. A room darkened is `dark[room] = true`.
- `state.outcome` is compared by `Deep.equal` against **exactly**
  `{ result = "won", reason = "procedure_complete" }`,
  `{ result = "lost", reason = "instability" }` or
  `{ result = "lost", reason = "clock" }` - no extra field.
- `tick(state, assignment, now, positions) -> (state, state.outcome)`: the
  second value is compared by `Deep.equal` to the first value's `.outcome`,
  nil until decided. `positions` is `{}` in every tick here.
- `turn` on a decided round, or arriving at `now >= deadline`, returns
  `{ kind = "refused", machineId = <the id passed>, reason = "round_over" }`
  **before** `unknown_machine` (an unknown id on a decided round is
  `round_over`). The state returned is deep-equal to the input when the round
  was decided before the call; when the call itself decides it by the clock, it
  is the input plus `outcome = lost / clock` and nothing else (no log entry, no
  dial, no commit).
- The turn that reaches `instability_max` returns the **ordinary** result
  (`rejected / wrong_setting`) with the outcome on the state. A completing
  finale turn returns `committed` with `outcome = won / procedure_complete`.
- Order within one event, as I-6: a charge checks instability first (`>=
  instability_max`), then the clock (`now >= deadline`), **the clock being read
  after the penalty is applied**. Expiry by `tick` or inside `turn` charges
  through the same path (penalty, crossings, outcome).
- Crossings: every `v` in `old+1 .. new` with `v % threshold == 0 and v <
  instability_max`, ascending; each draws `blackout_rooms_per_threshold` rooms
  one at a time, recomputing the weights between draws; nothing at the max.
- Constants are read from `state.tuning.actuation`: `instability_clock_penalty_seconds`,
  `instability_blackout_threshold`, `blackout_rooms_per_threshold`,
  `instability_max`, `blackout_weight_live_step`, `blackout_weight_waiting_step`
  (plus PROC-001/002's). Every one is overridden to a distinct value, so reading
  the module-level `MechanicsTuning` or the wrong constant fails a named check.
- `Tuning.round.round_seconds` is **not** read by the module; the shipped-row
  tests pass it as `roundSeconds`.

**Not constrained** (your choice): how the stream is advanced internally
(`nextNumber` x `blackoutDraws` per draw, or once per crossing, or any scheme
with the same k-th-draw property); whether `dark` also carries explicit
`false`s; how `blackoutWeights` walks the placement; whether `copy` clones
`dark` and `outcome` (I-10 only requires arguments left deep-equal and the new
state independent); what `dial` answers in a dark room; whether `tick`'s
`assignment` or `positions` are read; the text of any error; the `TurnResult`
type's exact union shape beyond the `round_over` literal.

### Tests that passed on arrival, and what earns them

All 12 tests in `procedure_outcome_controls_test.luau` pass in RED by design:
they run the `OutcomeContract` checks against stand-ins, not the module. What
earns each: the reference stand-in is accepted by all 21 outcome checks, all 20
`TurnContract` checks and all 22 `FinaleContract` checks (positive control),
and every defective stand-in was **observed** to fire the exact set of checks
its test names (the `[measured]` lines in the unit log). Nothing in
`procedure_outcome_test.luau` passes.

The 46 PROC-001/002 tests pass on arrival against the existing module because
only their fixture calls changed (two extra `start` arguments the module
ignores; a larger `instability_max` for the finale fixture). No assertion in
them changed, so nothing new needs earning; their controls fire the same sets
they did before (unchanged `[measured]` lines).

### Negative controls: expected values, measured in RED

Unlike an import-failing RED, these controls **did execute**: the stand-ins
need only merged modules. GREEN's job is to confirm the real module is
*accepted* by the same checks (the 23 red tests going green) and to read the
same numbers off the shipped module where a row names one.

| Control (one defect on the reference) | Threshold / expected (reference) | Measured on the control | Checks that fired (exactly) |
|---|---|---|---|
| AC-3: uniform draw | heavier-room frequency in [0.73, 0.77]; reference **0.7527** on seed 9001 (deterministic - GREEN's `drawRoom` must read exactly 0.7527 on that stream if it implements I-5) | **0.50355**; picks a zero-weight room on some of the 40 seeds (uniform over three rooms hits room 1 about one time in three) | `oneLitRoom…`, `theHeavierOfTwoRooms…`, `drawRoomMaps…` |
| AC-6: clock before instability | sixth point on a 49 s round: `lost / instability` | **`lost / clock`** | `instabilityMaxAndTheClockInOneTurn…` |
| AC-7: no outcome guard | later turns `refused / round_over`, state deep-equal | turns evaluated and charged; the armed window on the lost / clock state expires | `aDecidedRoundStaysDecided` |
| AC-2: blackout at the max | **2** dark rooms at instability 6 | **4** | `reachingInstabilityMax…`, `tickExpiryCharges…` |
| I-1: `derive("instance")` | rooms as predicted on the "blackout" stream | different rooms (e.g. `{ 2, 3 }` for `{ 1, 2 }` at the crossing) | the five checks that predict which rooms: crossing, jump, max, AC-4, replay |
| I-1: ignores `blackoutDraws` | replay order `{ 1, 2, 4, 3 }` on seed 9001 | **`{ 1, 2, 3, 4 }`** | `theSameSeedReplays…` only - the two-draw checks coincide on this seed (see the comment in the controls file) |
| I-3: out at `now > deadline` | B at exactly 150 `round_over`; tick at 300 `lost / clock` | B at 150 **commits and wins**; tick at 300 returns **nil** | `theLastFinaleCommit…`, `theDeadlinePassing…` |
| reference | - | 0 of 21 / 0 of 20 / 0 of 22 fail | - |

Three predictions were wrong on first run and corrected in the controls file
*to what was measured*, with the reason beside each: the wrong-stream control
does not fire the expiry check (the two finale rooms are the only weighted
ones, so two draws take both whatever the stream says) nor the AC-8 check (it
pins persistence, not which rooms); the ignores-`blackoutDraws` control fires
only the four-crossing replay check (on seed 9001 the first value maps to the
same room as the reference's second draw in every two-draw scenario); and the
`>` control also fired AC-7's precondition because that check built its lost /
clock state by a tick AT the deadline - the check now ticks at deadline + 0.5,
so the exact instant stays I-3's own check's business and each control pins one
thing.

### Deferred verifications I cannot run

D-1..D-4 all mutate the real implementation, which does not exist in RED.
**I did not run them.** They stay with GATES. The controls table says what each
must show: D-1 (every weight 1) -> `oneLitRoom…` fails (a zero-weight room is
drawn) and `theHeavierOfTwoRooms…` reads about 0.5; D-2 (swap the checks) ->
`instabilityMaxAndTheClockInOneTurn…` records `lost / clock`; D-3 (remove the
guard) -> `aDecidedRoundStaysDecided`; D-4 (change the label) -> the five
room-predicting checks, `theSameSeedReplays…` among them.

### PROC-001/002 audit against I-6 (every check, one line each)

Mechanical form: the outcome reference stand-in passes all 20 `TurnContract`
and all 22 `FinaleContract` checks (the `audit:` test). By hand, what I-6 adds
is: every charge moves the deadline (1100 - 20 x points under the fixtures'
shipped penalty), the round ends at `now >= deadline` or at `instability_max`
(5 shipped, 100 under the finale overrides), and a charge crossing a multiple of
2 darkens a room. The latest `now` in either fixture is 123; the largest charge
in `TurnContract` is 3 points, in `FinaleContract` 5.

`TurnContract` (shipped max 5, every check at most 3 points, deadline >= 1040):
1. `startReturnsTheContractState` - six named fields; the new ones are not forbidden. Unaffected.
2. `liveSetAtStartIsExactlyTheTrackHeads` - no charge. Unaffected.
3. `committingTheHeadOfTrackOneMakesItsSecondStepLive` - commits only. Unaffected.
4. `tracksAdvanceIndependentlyAndFinaleStepsStayWaiting` - commits only. Unaffected.
5. `holderInReachOnTheRequiredSettingCommits` - one commit; `dial` at NOW + 1000 is a view, not an event. Unaffected.
6. `reachIsInclusiveAtTurnRangeStudsAndIgnoresY` - commits. Unaffected.
7. `wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue` - 1 point; `expectRejection` compares result, instability, `committed[id]`, `dials[id]`, the view and the live set, not the whole state, so `dark`/`penaltySeconds` moving is invisible to it. Unaffected.
8. `waitingStepIsNotLiveWhateverTheSetting` - 2 points each from fresh starts (0 -> 2 crosses 2: one room darkens); field-wise comparison as above. Unaffected.
9. `decoyIsNotLiveWhateverTheSetting` - 2 points, as above. Unaffected.
10. `chargesAccumulateByReason` - 1 + 2 = 3 points, a crossing at 2; compares instability and the result. Unaffected.
11. `rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset` - 1 point; refusal `resetting` compares `Deep.equal(inside, state)` - a refusal with no expiry and no clock-out returns the state itself. Unaffected.
12. `unknownMachineIsRefused` - P-9 deep-equal: no expiry, no clock-out. Unaffected.
13. `nonHolderIsRefusedAndNotCharged` - as 12. Unaffected.
14. `holderOutOfHorizontalReachOrWithoutAPositionIsRefused` - as 12. Unaffected.
15. `committedMachineIsRefused` - as 12. Unaffected.
16. `resettingDialIsRefused` - 1 point then refusals, as 12. Unaffected.
17. `refusalChecksRunInOrderAndTheFirstFailureWins` - `round_over` precedes `unknown_machine` in I-6 step 1, but no case here is on a decided round or at the deadline, so the order pinned is a suffix of the new one. Unaffected.
18. `supplierIsJudgedKeyHolderAfterWithdraw` - commits and refusals. Unaffected.
19. `logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals` - 1 + 2 = 3 points (a crossing at 2); compares log and instability. Unaffected.
20. `noCallMutatesItsArguments` - `start` guard passes the new arguments; a crossing turn must leave its input deep-equal, which I-10 requires anyway. Unaffected.

`FinaleContract` (overrides: max 100, failed pair 4; shipped rows: max 5, failed pair 1):
1. `startHasNoWindowAndTheNewExportsAnswerInShape` - `tick` at NOW + 1 with no window must return a deep-equal state and nil: deadline 1100, so no clock-out. Unaffected.
2. `neitherFinaleMachineIsLive…` - commits only. Unaffected.
3. `anArmedMachineIsStillLive…` - arm and complete, no charge. (A completing turn now also sets `outcome = won`; the check reads the live set only.) Unaffected.
4. `correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt` - compares `armed`, `dials[id]`, instability, `committed`, the log. Unaffected.
5. `correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth` - compares named fields and `isComplete`; `outcome = won` is an extra field it does not read. Unaffected.
6. `turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth` - as 5. Unaffected.
7. `tickAtOrBeforeTheWindowsEndChangesNothing` - deep-equal, no charge, deadline 1100. Unaffected.
8. `tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair` - 4 points (0 -> 4 crosses 2 and 4: two rooms darken by tick); compares `armed`, instability, dials, `committed`, log, views, live set - not `dark`. Unaffected.
9. `afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain` - 4 points; refusal deep-equal against the post-expiry state passed in (no new expiry at that now). Unaffected.
10. `underTheShippedTuningAnExpiredWindowCostsExactlyOne` - 1 point, shipped max 5. Unaffected.
11. `wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth` - 1 point. Unaffected.
12. `underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo` - 1 point. Unaffected.
13. `wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection` - 1 point. Unaffected.
14. `turnOnTheArmedMachineIsRefusedArmedAtNoCost` - refusals at or before `closesAt`, no expiry, deep-equal. Unaffected.
15. `armedIsTheLastRefusalChecked` - as 14. Unaffected.
16. `aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt` - 4 points then an arm; compares named fields. Unaffected.
17. `aTurnAfterTheWindowReturnsThePostExpiryState` - **the 5-point check** (4 + 1): under the shipped max 5 this would now be `lost / instability` and the wrong turn on B `refused / round_over`; with `instability_max = 100` it is unchanged. Its `Deep.equal(state, expired)` between turn and tick still holds: both apply the same expiry, the same crossing draws (same seed, same `blackoutDraws`), the same penalty. **This is the one check that needed the fixture change.**
18. `bothLampsAreDarkWhileTheFinaleIsNotLive` - commits and lamps. Unaffected.
19. `aLampIsLitExactlyWhen…` - lamps. Unaffected.
20. `anyHolderOfThePartnersClassInRange…` - lamps. Unaffected.
21. `isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted` - `isComplete` only. Unaffected.
22. `noFinaleCallMutatesItsArguments` - adds nothing I-10 does not already require. Unaffected.

Also `TurnContract.refusalProblems`' P-9 deep-equal: every caller passes a state
with no expired window and a `now` far below the deadline, so neither F-9's nor
I-6 step 3's departure from P-9 applies.

### Doubts and discoveries

- **No `## Contract` block needed amending.** Every mechanism held when
  exercised: `Rng.fromSeed(seed):derive("blackout")` rebuilt per draw and
  advanced by `blackoutDraws` `nextNumber()` calls reproduces the k-th draw
  (the reference does exactly that and the independent-stream checks accept
  it); `Generator.generate(TurnContract.assignment(), 9001, MechanicsTuning)`
  produces a facility at attempt 1; `Deep.equal` treats an absent `outcome`
  and `nil` alike.
- **A derived pin, flagged:** I-6 step 1 puts `round_over` before
  `unknown_machine`, so `aDecidedRoundStaysDecided` expects `round_over` for
  id 99 on a decided round. It follows from the step order as written; if the
  PO would rather an unknown id always read `unknown_machine`, that is an I-6
  amendment and one case in that check changes.
- **The clock is read after the penalty.** `instabilityMaxAndTheClockInOneTurn…`
  arranges the sixth point so the clock is out only *after* its own penalty
  (deadline 115 -> 108 at now 108). An implementation that reads the clock
  before applying the penalty would still record `lost / instability` here
  (instability is checked first), but would miss `lost / clock` on a turn
  whose penalty alone zeroes the clock below the max. No AC states that case
  and no test pins it; I-3 ("in the same event") and I-6 step 4 imply it.
  Flagging so GREEN builds penalty-then-clock deliberately.
- **`ignores-blackoutDraws` is a weak control on this seed** (one check
  fires). The four-crossing replay check is what catches it; the two-draw
  checks happen to coincide. Not a defect in the checks - the equivalence they
  pin is correct - but D-4's label mutation is the stronger GATES probe for
  the stream, and a `blackoutDraws`-ignoring implementation would be caught
  by `theSameSeedReplays…`.
- The harness gate's one red assertion is the uncommitted-tree precondition
  ("no stray .luau files"); the baselines themselves (129/129/24) already
  match. Commit `.claude/tests/project-counters.test.sh` in the RED commit.
- The `tick` scenarios pass `positions = {}`; `assignment` is the fixture's.
  Neither is read by anything I-1..I-10 names.

### GREEN notes

**Model:** `feature-developer` resolved to Opus 5.5 (`claude-opus-5-5`), the
`opus` row; the dispatch named no override. 2026-10-02.

**Files changed:** `src/server/procedure/Procedure.luau` only (the new state
fields, `start`'s two parameters, `deadline`, `isDark`, `blackoutWeights`,
`drawRoom`, a private `blackoutStream` and `charge`, `settle`, the
`round_over` refusal, and the win check after a completing commit). No test,
config, manifest or `.claude/tests/**` touched.

**Seen red first:** the outcome test file alone, before any edit: `0 passed,
23 failed`, the same 23 as the handoff.

**Built as the Contract says, with no mechanism found wanting.** Every charge
(`wrong_setting`, `not_live`, expiry) goes through one `charge`: instability,
then penalty, then crossings `old+1 .. new` below the max (each drawing
`blackout_rooms_per_threshold` rooms, weights recomputed per draw, `break` on
nil), then instability `>= max` before `now >= deadline`, read after the
penalty (PO ruling 2). `turn` checks `outcome` before anything else (ruling 1),
then expiry and the clock (`settle`), and refuses `round_over` if either
decided the round. `copy` now clones `dark`; `outcome` tables are always
fresh, never mutated, so they are shared. The stream is rebuilt per draw and
advanced by `blackoutDraws` `nextNumber()` calls (I-1).

**Final `lune run test`:** `763 passed, 0 failed`. `selene src tests lune`: 0
errors, 0 warnings. `stylua --check src tests lune`: clean.

**`bash scripts/gates.sh --fast`** (uncommitted tree, 2026-10-02):

    PASS         format (1s, observed 129)
    PASS         lint (0s, observed 129, floor 1)
    PASS         typecheck (3s, observed 24)
    PASS         unit (111s, observed 763, floor 507)
    UNCONFIGURED coverage
    PASS         build (0s, observed 91349)
    FAIL         harness (16s, exit 1)

`harness` is `project-counters: 39 passed, 1 failed`, the one being "the
working tree carries no stray .luau files" with `actual: M
src/server/procedure/Procedure.luau` - the uncommitted-tree precondition,
which clears at the GREEN commit. The counter baselines (129/129/24) match:
GREEN added no `.luau` file.

**Controls, measured on the shipped module** (scratch script
`.claude/state/green/measure3.luau`, ignored):

| Control | RED's number | Measured on the module |
|---|---|---|
| AC-3: `heavierRoomFrequency` (`drawRoom({[4]=3,[7]=1})` x 20,000, seed 9001 "blackout") | reference 0.7527 | **0.7527** (exact) |
| AC-3: uniform control | 0.50355 | **0.50355** - `drawRoom({[4]=1,[7]=1})` on the same stream, i.e. D-1's every-weight-1 mutation, reads the uniform control's number exactly |
| AC-6: sixth point on a 49 s round at t0+10 | reference `lost / instability` | **`rejected / wrong_setting`**, instability 5 -> 6, deadline 114 -> 107 (clock below 0), outcome **`lost / instability`** |
| AC-2: dark rooms at the max (threshold 3, 2 per crossing) | reference 2 (control 4) | **2** (rooms 1, 2), `blackoutDraws` 2, outcome `lost / instability` |

The controls file's own `[measured]` lines are unchanged on this run (they
measure stand-ins, not the module): reference 0 of 21 / 0 of 20 / 0 of 22,
each one-defect stand-in firing the set the table above names. No divergence
from RED to report. D-1..D-4 remain GATES's.

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

    run:    2026-10-02T06:09:10Z
    commit: dab4ac5
    tree:   483436d6273c42b317af57701fab544205b06250
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 129)
    PASS         lint (1s, observed 129, floor 1)
    PASS         typecheck (3s, observed 24)
    PASS         unit (116s, observed 763, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 91349)
    PASS         harness (24s, observed 40)
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

1. **A turn naming an unknown machine on a decided round is `round_over`, not
   `unknown_machine`.** Kept: I-6 step 1 runs before every refusal, and a decided
   round answers nothing else.
2. **The clock is read after the penalty within the same charge.** Kept: that
   is I-3 ("in the same event") and I-6 step 4, and it is what makes AC-6's
   second clause reachable at all.
3. **The `ignores-blackoutDraws` control is weak on this seed (one check).**
   Accepted; D-4 (the label mutation) is the stronger probe, and GATES runs it.

**PO verification of RED (lead-po, 2026-10-02).** `lune run test`, run
independently: `740 passed, 23 failed`, all 23 in `procedure_outcome_test.luau`
(19 on the `need()` guards for `deadline`, `isDark` and `drawRoom`, 1 on the
exports check, 1 on `roundSeed` not stored, 1 on AC-7's decided states not being
buildable, 1 more guard). No PROC-001/002 test went red. Their diff is fixture
data only (`start`'s two new arguments, a 1000 s round, and `FinaleContract`'s
`instability_max` 5 → 100 with its reason beside it). No assertion changed. I
also read the AC-6 ordering check: it asserts as preconditions that the clock is
still running at five points and out after six, so it cannot pass vacuously.

`bash scripts/gates.sh --fast` on the uncommitted RED tree:

    PASS         format (1s, observed 129)
    PASS         lint (1s, observed 129, floor 1)
    PASS         typecheck (3s, observed 24)
    FAIL         unit (149s, exit 1)      -- exactly the 23 above
    UNCONFIGURED coverage
    PASS         build (0s, observed 88474)
    FAIL         harness (21s, exit 1)    -- 39/40: "no stray .luau" (uncommitted tree)

Admissible. The RED commit (tests and counter baselines, `phase: RED`) clears
the harness precondition.

**PO verification of GREEN (lead-po, 2026-10-02).**

- Freeze: `bash scripts/frozen.sh verify` → `frozen: OK — 12 path(s) unchanged since the snapshot for PROC-003`
  (OutcomeContract, FinaleContract, TurnContract, Deep, Contract, the six
  procedure test files, `.claude/tests/project-counters.test.sh`).
- `lune run test` (independent run): `763 passed, 0 failed`.
- Discrimination, two mutations of the shipped module via `scripts/mutate.sh`,
  each restored and verified byte-for-byte, counts predicted by RED's controls
  table:

  | Mutation | Predicted | Measured |
  |---|---|---|
  | crossing guard `v < instability_max` → `v <= instability_max` (blackout at the max) | 2 (`reachingInstabilityMax…`, `tickExpiryCharges…`) | `761 passed, 2 failed` — exactly those two |
  | blackout stream not advanced by `blackoutDraws` (`for _ = 1, 0 do`) | 1 (`theSameSeedReplays…`) | `762 passed, 1 failed` — `AC-5/I-1: one seed replays four crossings as the same four rooms in the same order…` |

- `bash scripts/gates.sh --fast` on the uncommitted GREEN tree:

      PASS         format (1s, observed 129)
      PASS         lint (1s, observed 129, floor 1)
      PASS         typecheck (2s, observed 24)
      PASS         unit (119s, observed 763, floor 507)
      UNCONFIGURED coverage
      PASS         build (0s, observed 91349)
      FAIL         harness (18s, exit 1)   -- 39/40: "no stray .luau" (Procedure.luau uncommitted)

  The GREEN commit clears that one; re-checked after it below.

After the GREEN commit `dab4ac5`: `bash .claude/tests/project-counters.test.sh` →
`project-counters: 40 passed, 0 failed`. Every `--fast` gate is green.

**GATES (lead-po, 2026-10-02).** D-1 to D-4 ran before `gates.sh`; results are
under `## Deferred verifications`. Then `bash scripts/gates.sh` (the full run,
which records itself in `## Gate results`): `All required gates passed (6 ran, 3
unconfigured, 0 known).` No source change was needed in GATES. No gate was added
or changed, so `## Gate probes` is not required.

**REVIEW → DONE (lead-po, 2026-10-02).** PR
https://github.com/ryanczhang7/first-roblox/pull/49 merged at
2026-10-02T14:19:36Z as `e70b1a2`. CI on the PR head `750bedc`: `boundaries` pass
(6s), `gates` pass (3m13s,
https://github.com/ryanczhang7/first-roblox/actions/runs/37013535235). Timings
read from that log:
- Harness self-test: 1m53s.
- `Run gates`: 62s, of which format 0s, lint 0s, typecheck 3s, unit 44s (763
  tests), build 0s, harness 12s.

The job sets no `timeout-minutes`, so the runner default applies and nothing is
near a limit. No gate was pending CI.
