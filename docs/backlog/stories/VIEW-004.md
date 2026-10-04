---
id: VIEW-004
title: An implausible position is not trusted for any range check
slug: an-implausible-position-is-not-trusted-f
epic: EPIC-07
type: feature
status: in-review
phase: REVIEW
branch: story/VIEW-004-an-implausible-position-is-not-trusted-f
depends_on: [SLICE-005]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-07`. B4: "Client-supplied position, timing, and target selection are
**claims**, not facts. Re-derive or sanity-check server-side." On Roblox a
character's position is simulated by its own client, so every range rule in M3 —
reading a lens (`lens_read_range_studs`), pinging (`ping_range_studs`), turning,
and the finale's partner lamp — rests on a claim. `architecture.md` §9.8 settles
the check: the server samples positions itself and accepts a sample only if it
is reachable from the last accepted one at the server-set walk speed, with a
tolerance.

`SLICE-005` introduced `PositionsSampled` and stores samples unfiltered; this
story puts the plausibility check in front of that store.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a last accepted sample `p0` at `t0` and a candidate `p1` at
  `t1`, when `|p1 − p0|` (horizontal) `<= walk_speed_studs_per_second × TOLERANCE × (t1 − t0) + SLACK_STUDS`,
  then the candidate is accepted; otherwise the previous sample is kept and a
  rejection is counted for that player.
  *Control:* a candidate 200 studs away 0.1 s later must be refused; one 1.5
  studs away 0.1 s later must be accepted.
- **AC-2** — Given a player the server itself has just moved (a spawn or a
  round-start placement, signalled by a `Placed` event carrying the position),
  when the next sample arrives at that position, then it is accepted, and the
  placement becomes the new baseline.
  *Control:* the same jump without a preceding `Placed` must be refused.
- **AC-3** — Given a player with no accepted sample, when the first sample
  arrives, then it is accepted only if a `Placed` baseline exists for them;
  otherwise it is held as unaccepted and **no range rule treats that player as
  in range of anything**.
- **AC-4** — Given a player in `Round` whose samples have been refused
  continuously for longer than `RESYNC_SECONDS`, when their next sample is
  offered, then `Session` emits a `Placed` effect at their last accepted position
  and that position becomes the new baseline (the recovery path for a legitimate
  desync is a server placement, never a trusted jump). Refused for exactly
  `RESYNC_SECONDS` or less, nothing is placed.
- **AC-5** — Given a `Session` in `Round` with an implausible sample, when the
  turn rule next reads positions, then it reads the last accepted one — shown by
  a turn that is in reach only at the implausible position being refused as
  `out_of_reach`.

## Amendments

Both were made during PLANNED, on 2026-10-04, before RED started and before any
test existed. They are recorded here because the criteria differ from the
version planned onto `main`. The user chose both in this session (PO-1, PO-2 in
`## Notes`).

- **AC-4.** *Was:* "Given a player whose samples have been refused for longer
  than `RESYNC_SECONDS`, when the driver next places them, then the baseline
  resets (the recovery path for a legitimate desync is a server placement, never
  a trusted jump)." *Now:* in `Round`, after refusals unbroken for longer than
  `RESYNC_SECONDS`, the next offered sample makes `Session` emit a `Placed` at
  the last accepted position, which becomes the baseline; at exactly
  `RESYNC_SECONDS` or less nothing is placed. *Why:* every server placement
  already resets the baseline, so as drafted the criterion was true of any
  implementation and `RESYNC_SECONDS` meant nothing. The user chose the
  pull-back over dropping the constant.
- **AC-5.** *Was:* "Given a `Session` with an implausible sample, when a lens,
  ping or turn rule next reads positions, then it reads the last accepted one —
  shown by a ping whose range check passes only at the implausible position
  being rejected as out of range." *Now:* the same, proved with a turn refused
  as `out_of_reach`. *Why:* no ping exists in `Session` (CHAN-005/006 are
  PLANNED), and the lens view is not wired into it until SLICE-006, so the
  drafted proof could not be built. The user chose the turn over waiting for
  pings.

## Contract

RED may amend any block below in place, with a one-line reason beside it; GREEN
builds what the amended block says.

**Module.** `src/server/session/Positions.luau`, pure: no module state, no
Roblox API, no argument mutated, every returned table fresh. Wired into
`Session.step`.

    export type Vec = { x: number, y: number, z: number }
    export type Track = {
        accepted: Vec?,        -- the last accepted sample (or placement); nil = never accepted
        acceptedAt: number?,   -- when it was accepted
        refusedSince: number?, -- start of the current unbroken run of refusals; nil when none
        refusals: number,      -- every refusal ever counted for this player (AC-1)
    }
    Positions.TOLERANCE: number      -- 1.5: physics jitter and network batching
    Positions.SLACK_STUDS: number    -- 2: one sample's worth of rounding
    Positions.RESYNC_SECONDS: number -- 3
    Positions.placed(track: Track?, at: Vec, now: number) -> Track
    Positions.offer(track: Track?, candidate: Vec, now: number, walkSpeed: number) -> (Track, boolean) -- accepted?
    Positions.needsResync(track: Track?, now: number) -> boolean

*Amended in PLANNED (PO-1..PO-4, with the user, 2026-10-04):* `Track` gains
`refusals`, because AC-1 counts a rejection and the drafted type had nowhere to
count it. `offer` takes `walkSpeed`, because the drafted comment read the walk
speed from the `MechanicsTuning` module, while `Session` holds its own
`state.tuning`, and every other rule in M3 reads its constants from the tuning
it is handed (Procedure P-1). `needsResync` is new: it is AC-4's clause, named.

These three constants are **engineering constants**, not game tuning: they bound a
trust check and do not change how the game plays for an honest client. They live
in this module with this justification and are **not** added to `tuning.md`.
If playtesting shows honest players refused (a jumping or falling character
exceeds the bound), raise the tolerance here and record the observation.

**`Positions` semantics, every number pinned.**

- **`placed(track, at, now)`**: `accepted` = a copy of `at`, `acceptedAt = now`,
  `refusedSince = nil`, `refusals` carried over from `track` (0 for `nil`).
- **`offer(track, candidate, now, walkSpeed)`** with no baseline (`track` nil,
  or `track.accepted` nil): returns `(track with refusals carried, false)`.
  The candidate is not stored, and this is **not** counted as a refusal and
  does not start `refusedSince`: there is nothing to be implausible against and
  nothing to resync to (AC-3).
- **`offer`** with a baseline: `d` = horizontal (x, z) Euclidean distance from
  `accepted` to `candidate`, `y` ignored (`architecture.md` §9.8);
  `dt = max(0, now - acceptedAt)`; `bound = walkSpeed * TOLERANCE * dt +
  SLACK_STUDS`. **Accepted iff `d <= bound` (inclusive).** Accepted: `accepted`
  = a copy of `candidate`, `acceptedAt = now`, `refusedSince = nil`. Refused:
  `accepted` and `acceptedAt` unchanged, `refusals + 1`, `refusedSince` = its
  old value or `now` if it was nil.
- The bound is measured from the last **accepted** sample, not the last offered
  one: after refusals it keeps growing at walk speed, so a player who really
  walked is accepted once the walk is plausible from the last trusted point.
- **`needsResync(track, now)`**: `track ~= nil and track.accepted ~= nil and
  track.refusedSince ~= nil and now - track.refusedSince > RESYNC_SECONDS`
  (strict: "longer than").

**`Session` semantics.**

- `SessionState` gains `tracks: { [string]: Positions.Track }` (`{}` from
  `new`). `state.positions` keeps its name and type and becomes **the accepted
  positions only**: for every player whose track has `accepted`, a fresh copy
  of it; a player with no accepted sample is **absent**. It is what
  `TurnRequests.handle` and `Procedure.tick` already read, so every range rule
  reads accepted samples, and an absent player is in range of nothing (AC-3;
  `Procedure`'s `within` returns false for a nil position).
- **`PositionsSampled`**, in every phase: each `(playerId, sample)` is offered
  to that player's track, with walk speed
  `state.tuning.instance.walk_speed_studs_per_second`. Players absent from the
  batch keep their tracks. **This is a merge, no longer a replace**: SLICE-005's
  C-3 test ("replaces `state.positions` with a copy of the samples, not merged")
  pinned the unfiltered store this story exists to remove, and RED rewrites it
  to the rule above. Then, **in `Round` only**, every player for whom
  `needsResync` is true is placed back at their accepted position
  (`Positions.placed`) and a `Placed { playerId, position }` effect is emitted,
  one per player, ascending by `playerId`, each position a fresh table. That is
  the only effect a `PositionsSampled` emits. It is never sent to the machine.
- **The deal** (entering `Round`) replaces `tracks` with exactly the dealt
  players, each `Positions.placed(old track, centre, now)`, so refusal counts
  survive, and `positions` is exactly `{ [p] = centre }` as today. Its `Placed`
  effects are unchanged.
- **AC-2's "a spawn or a round-start placement"**: the only server placements
  that exist are the deal's and AC-4's resync. Both go through
  `Positions.placed`. No new inbound event is added. A Lobby spawn is the
  client's, and it is not trusted (AC-3).
- Entering `Lobby` keeps `tracks` and `positions`, as `positions` is kept today.

**Requires.** `Positions.luau` requires nothing from `src/` beyond what it needs
for its types, and never `MechanicsTuning` (walk speed is passed in).

**Existing exports whose shape changes, and every caller (`rg`, 2026-10-04).**
`SessionState` gains `tracks`, and the meaning of `PositionsSampled` changes.
`Session.step`'s signature is unchanged.

- `src/server/session/Session.luau`: the only source.
- `tests/server/session_round_test.luau` (C-3 at line 77, the deal at line 59)
  and `tests/helpers/SessionRoundContract.luau` (the C-3 check at ~1379-1425,
  the deal check at ~1029-1121, the `new` check at ~897, and the state builders
  at ~295-348): they assert today's replace semantics and build `SessionState`
  values.
- `tests/server/session_round_controls_test.luau` (stub sessions that build
  state at ~187-275): they need `tracks` if the checks read it.
- `tests/helpers/ScriptedRound.luau`: `place` (line 223) teleports by sample,
  and the scripts at ~407, ~416 and ~509 call it. Per the user's decision
  (PO-3), it **walks** instead: each moving player advances at most
  `walk_speed_studs_per_second` (read from the tuning in use, never a literal)
  per simulated second along a straight line, one `Tick` and then one
  `PositionsSampled` per second, until it arrives. That costs simulated time
  (**<= 15 s per move**, amended by RED: the longest move on the 3x3, 64-stud
  layout is the grid diagonal, sqrt(2) x 160 = 226 studs, not one room pitch;
  measured 75 s of walking at most over the 150 scripted wins, against a
  420 s round whose earliest penalised deadline is 340 s), so `clockOut` and
  `loseByInstability` budgets are re-read, not assumed - and were found to
  need no re-fitting. *Amended in RED, 2026-10-04: "one PositionsSampled and
  one Tick" became "one Tick and then one PositionsSampled", because a sample
  at the same `now` as the last accepted one has dt = 0 and is rightly
  refused by the check this story adds.*
- `tests/server/session_test.luau`, `tests/helpers/SessionContract.luau`,
  `tests/server/session_controls_test.luau` (SLICE-003): checked, and none pins
  `positions`. `session_test.luau:29` explicitly allows extra keys on
  `SessionState` beyond `round`, so `tracks` does not break them.

RED's handoff states that this list was checked against
`rg -n "PositionsSampled|\.positions|SessionState|ScriptedRound" src tests`.

**Oracle partition.** AC-1 to AC-4 are **mechanical** against the constants
above (read them from the module, do not restate them). AC-1's controls are
settled numbers (200 studs in 0.1 s refused; 1.5 studs in 0.1 s accepted), and
RED adds the exact boundary: a candidate at exactly `bound` is accepted, and
one a hair past it refused. AC-5 is **mechanical** through `Session`, with a
turn. The rewritten SLICE-005 checks are mechanical, and the walking scripts
must still win, lose and clock out.

## Deferred verifications

**D-1. The bound discriminates.** With `scripts/mutate.sh` multiplying
`TOLERANCE` by 100, AC-1's 200-stud control **must** go red. RED cannot run
this; the module does not exist. Owner: GATES.

**D-2. The bound is inclusive — a wrong value.** With `<=` changed to `<` in
`offer`'s comparison, AC-1's exact-boundary case **must** go red. RED cannot
run this. Owner: GATES.

**D-3. Session reads accepted positions, not samples.** With `Session`'s
`PositionsSampled` handling mutated to store the raw sample as the player's
position (bypassing `offer`), AC-5's out-of-reach turn **must** go red, and so
must AC-3's "absent until placed". RED cannot run this; the exact expression
depends on GREEN's code, and the orchestrator writes it in GATES. Owner: GATES.

**D-4. The walking scripts really walk.** With `Positions.offer` mutated to
refuse every candidate, SLICE-005's scripted **win** test **must** go red
(players are then frozen at the spawn centre and can never reach a machine).
This is what earns the rewritten `ScriptedRound`: against today's unfiltered
Session the walking scripts pass on arrival and prove nothing about the check.
RED cannot run this. Owner: GATES.

**D-5. Resync is strict.** With `needsResync`'s `>` changed to `>=`, AC-4's
"refused for exactly `RESYNC_SECONDS`, nothing is placed" case **must** go red.
RED cannot run this. Owner: GATES.

### Results (GATES, orchestrator, 2026-10-04, against `ed0aff4`)

All five run with `bash scripts/mutate.sh <file> '<expr>' -- lune run test`,
one at a time; baseline `1001 passed, 0 failed`. Every one went red where its
entry said it must, and each file was restored and verified. Afterwards
`src` was clean and no `.bak` was left; the full `gates.sh` ran only after
that check.

**D-1 — RAN, PASSED.** `TOLERANCE` × 100. AC-1's settled 200-stud control went
red, as required. The inclusive-bound and `dt` tests stayed green, because they
read the constant (RED's handoff predicted exactly this).

    === mutate: src/server/session/Positions.luau (1 line(s) changed by s/^Positions.TOLERANCE = 1.5$/Positions.TOLERANCE = 1.5 * 100/) ===
      FAIL  tests/server/positions_test.luau :: AC-1: from a placement at the origin, a candidate 200 studs away 0.1 s later is refused ...
      FAIL  tests/server/positions_test.luau :: AC-2: placed(track, at, now) is the new baseline ...
      FAIL  tests/server/positions_test.luau :: AC-4: needsResync(track, now) is true only for an accepted track whose refusal run is STRICTLY longer ...
      FAIL  tests/server/session_positions_test.luau :: AC-2: the deal's placement is the baseline ...
      FAIL  tests/server/session_positions_test.luau :: AC-4: in Round, refused continuously for longer than RESYNC_SECONDS ...
      FAIL  tests/server/session_positions_test.luau :: AC-5: the turner of T1[1], last accepted at the spawn centre, sends an implausible sample AT the machine ...
      FAIL  tests/server/session_positions_test.luau :: Contract: state.tracks is {} from new; the deal replaces it ...
    994 passed, 7 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_session_Positions.luau.20261004T201134Z.71368.bak) ===

**D-2 — RAN, PASSED.** A wrong value (`<=` → `<`), caught by the exact-bound
test and the clamp test, as the control table predicted for `exclusiveBound`.

    === mutate: src/server/session/Positions.luau (1 line(s) changed by s/if d <= bound then/if d < bound then/) ===
      FAIL  tests/server/positions_test.luau :: AC-1: a candidate at EXACTLY walkSpeed x TOLERANCE x dt + SLACK_STUDS is accepted and one a hair past it is refused - the bound is inclusive
      FAIL  tests/server/positions_test.luau :: AC-1: a now before acceptedAt clamps dt to 0 ...
    999 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_session_Positions.luau.20261004T201455Z.80630.bak) ===

**D-3 — RAN, PASSED.** `Session` stores each raw sample as accepted
(`Positions.offer` replaced by `Positions.placed`). AC-5's out-of-reach turn
and AC-3's "absent until placed" both went red, as required, along with the
rewritten C-3 checks.

    === mutate: src/server/session/Session.luau (1 line(s) changed by s/tracks\[playerId\] = (Positions.offer(tracks\[playerId\], sample, now, walkSpeed))/tracks[playerId] = Positions.placed(tracks[playerId], sample, now)/) ===
      FAIL  tests/server/session_positions_test.luau :: AC-2: the deal's placement is the baseline ...
      FAIL  tests/server/session_positions_test.luau :: AC-3: a player with no accepted sample is absent from state.positions ...
      FAIL  tests/server/session_positions_test.luau :: AC-4: in Round, refused continuously for longer than RESYNC_SECONDS ...
      FAIL  tests/server/session_positions_test.luau :: AC-5: the turner of T1[1], last accepted at the spawn centre, sends an implausible sample AT the machine; their turn is refused out_of_reach ...
      FAIL  tests/server/session_positions_test.luau :: Contract: state.tracks is {} from new; the deal replaces it ...
      FAIL  tests/server/session_positions_test.luau :: Contract: the walk speed is state.tuning.instance.walk_speed_studs_per_second ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3): after every step of a two-round lifecycle ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3, rewritten by VIEW-004): PositionsSampled in Lobby, Round and Resolution merges the batch into the ACCEPTED positions ...
    993 passed, 8 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_session_Session.luau.20261004T201822Z.91669.bak) ===

**D-4 — RAN, PASSED. This is what earns the walking `ScriptedRound`.** With
every candidate refused, SLICE-005's scripted **win** (AC-4) went red, and so
did its instability (AC-5) and penalised-clock (AC-6) scripts and the stored-
positions turn (AC-3). The walking scripts depend on the check accepting real
walks; they no longer pass on arrival.

    === mutate: src/server/session/Positions.luau (1 line(s) changed by s/if d <= bound then/if false then/) ===
      ... 8 positions_test and 5 session_positions_test failures, then:
      FAIL  tests/server/session_round_test.luau :: AC-1: on each of two deals state.facility deep-equals Generator.generate(...) ...
      FAIL  tests/server/session_round_test.luau :: AC-1: the dealing step emits one Placed { playerId, position } per seated player ...
      FAIL  tests/server/session_round_test.luau :: AC-3: a TurnRequested in Round is TurnRequests.handle(procedure, assignment, caller, args, now, STORED positions) ...
      FAIL  tests/server/session_round_test.luau :: AC-4: over 50 seeds at each n in {4, 5, 6} the canonical-order script wins every round ...
      FAIL  tests/server/session_round_test.luau :: AC-5: instability_max wrong turns on the live step ...
      FAIL  tests/server/session_round_test.luau :: AC-6: with k points charged for each k in 0 .. instability_max - 1 ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3): a TurnRequested in Lobby, Resolution, Post ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3): after every step of a two-round lifecycle ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3): the step that enters Lobby clears facility and procedure ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-3, rewritten by VIEW-004): PositionsSampled ... merges the batch into the ACCEPTED positions ...
      FAIL  tests/server/session_round_test.luau :: Contract (C-5): every RoundView in Round carries secondsLeft ...
    977 passed, 24 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_session_Positions.luau.20261004T202043Z.104052.bak) ===

**D-5 — RAN, PASSED.** `>` → `>=` in `needsResync`; both "exactly
`RESYNC_SECONDS`" cases went red and nothing else.

    === mutate: src/server/session/Positions.luau (1 line(s) changed by s/> Positions.RESYNC_SECONDS/>= Positions.RESYNC_SECONDS/) ===
      FAIL  tests/server/positions_test.luau :: AC-4: needsResync(track, now) is true only for an accepted track whose refusal run is STRICTLY longer than RESYNC_SECONDS ...
      FAIL  tests/server/session_positions_test.luau :: AC-4: in Round, refused continuously for longer than RESYNC_SECONDS ...
    999 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/src_server_session_Positions.luau.20261004T202428Z.117570.bak) ===

## Out of scope

- The Studio check that an honest walker is never refused: it needs the real
  driver and is `SLICE-007`'s `D-3`.

- Anti-cheat beyond range claims (fly, noclip, speed exploits as such).
- Vertical reach rules. Every M3 range is a horizontal distance (`architecture.md` §9.8).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write VIEW-004` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/session/Positions.luau` (source), `src/server/session/Session.luau` (source), `tests/helpers/ScriptedRound.luau` (test) (+6 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

Three levels, by where each claim can be falsified cheapest:

**Unit, the pure rule** - `tests/server/positions_test.luau` over the real
`src/server/session/Positions.luau`, through the checks in
`tests/helpers/PositionsContract.luau` (`MODULE_CHECKS`). Every constant is
READ from the module; the only literal distances are AC-1's settled controls.

| Test (name starts with) | AC | What it falsifies |
|---|---|---|
| `Contract: Positions exports ...` | Contract | the export shape; `TOLERANCE >= 1`, `SLACK_STUDS >= 0`, `RESYNC_SECONDS > 0` |
| `AC-1: from a placement at the origin, a candidate 200 studs ...` | AC-1 | the settled controls: 200 in 0.1 s refused (previous kept, `refusals` 1, `refusedSince` 0.1); 1.5 in 0.1 s accepted |
| `AC-1: a candidate at EXACTLY ...` | AC-1 | the inclusive bound at dt = 1: exactly `w*T+S` accepted, `+1e-6` refused (D-2's target) |
| `AC-1: y is ignored ...` | AC-1 | 500 studs straight up accepted; a stud inside the horizontal bound with y = 500 accepted |
| `AC-1: dt is measured from the last ACCEPTED sample ...` | AC-1 | `bound(3.5)+1` refused at t = 3 and 3.5 (count 2, run from 3, baseline kept), accepted at t = 4 (run cleared, count kept) |
| `AC-1: a now before acceptedAt clamps dt to 0 ...` | AC-1 | at now < acceptedAt: `SLACK_STUDS` away accepted, `+0.5` refused |
| `AC-2: placed(track, at, now) is the new baseline ...` | AC-2 | a sample at a 300-stud placement accepted; the same jump without it refused; `placed` copies `at`, sets `acceptedAt`, clears the run, carries `refusals` (0 from nil) |
| `AC-3: with no baseline ...` | AC-3 | nil track and never-accepted track: not accepted, not stored, `refusals` 0, no `refusedSince`; after `placed` the next sample accepted |
| `AC-4: needsResync(track, now) ...` | AC-4 | false at exactly `RESYNC_SECONDS` into the run, true `+1e-6` (D-5's target); false for nil, no baseline, no run, after an acceptance |
| `Contract: placed, offer and needsResync mutate no argument ...` | Contract | purity: no argument mutated, fresh track, candidate/`at` never stored by reference |

**Integration, the rule in `Session.step`** -
`tests/server/session_positions_test.luau` over the real `Session` with the
real `Positions` read for its constants (`SESSION_CHECKS`), driven through
`ScriptedRound`.

| Test | AC | What it falsifies |
|---|---|---|
| `AC-2: the deal's placement is the baseline ...` | AC-2 | everyone sampled at the centre 0.1 s after the deal accepted (tracks at that `now`, `{}` effects); a 1,000-stud jump at 0.2 s refused (positions kept, `refusals` 1, run from 0.2); the same jump in a Lobby with no deal not stored and not a refusal |
| `AC-3: a player with no accepted sample is absent ...` | AC-3 | on a post-deal state with the turner of T1[1]'s track removed: a sample AT the machine not stored, not a refusal; their turn refused `out_of_reach` |
| `AC-4: in Round, refused continuously for longer than RESYNC_SECONDS ...` | AC-4 | seat order dan, cat, bob, ann: dan refused at T+1 and T+1+R (`{}` effects, positions kept); at T+1+R+0.5 effects exactly `{ Placed{dan, centre} }` (ann's first refusal not a resync), position fresh, track reset (`acceptedAt` = that now, no run, `refusals` 3); the next sample at the centre accepted. Two players due in one step: `Placed ann, Placed dan` (ascending, not seat order), distinct tables. The next Lobby (tracks kept, a centre sample first): the same run emits nothing, positions kept, run still open |
| `AC-5: the turner of T1[1] ... implausible sample AT the machine ...` | AC-5 | precondition: the machine is beyond `turn_range_studs` and beyond `bound(0.1)`; the sample is not stored, the turn is `out_of_reach`; positive control: after `ScriptedRound.walk` the same turn is `committed` |
| `Contract: state.tracks is {} from new; the deal replaces it ...` | Contract | `tracks == {}` from `new`; after the deal exactly the dealt players, each `{ accepted = centre, acceptedAt = T, refusals = 0 }`; two refusals, a leave, a join, deal 2: the jumper's `refusals` 2 carried, the leaver absent, the newcomer at 0, `positions` exactly the new centre |
| `Contract: a PositionsSampled naming one player merges ...` | Contract | a one-player batch moves that player (`w*0.5` at dt 0.5), every other position and track untouched, `positions[p]` not the event's table, state and event unmutated, `{}` effects |
| `Contract: the walk speed is state.tuning... ` | Contract | under `options.tuning` with walk speed x10 a `bound(1)+w` jump is accepted; under the shipped tuning the same jump is refused |

**Existing SLICE-005 tests, changed** - `tests/server/session_round_test.luau`
through `tests/helpers/SessionRoundContract.luau`:

| Test | What changed |
|---|---|
| `Contract (C-1): Session.new holds ... tracks = {}` | gains the `tracks == {}` pin (red now) |
| `Contract (C-3, rewritten by VIEW-004): PositionsSampled ... merges the batch into the ACCEPTED positions` | the C-3 rewrite: positions deep-equal the oracle's accepted map (merge; no baseline absent; absent-from-batch kept), no entry is the event's table, only `Placed` may be emitted and none is due, other fields unchanged. Preconditions: >= 5 samples, >= 1 unplaced player sampled, >= 2 partial batches |
| `Contract (C-3): after every step ... follow the Contract's own composition` | the oracle applies the baseline rule (red now on the empty-Lobby sample and on every partial batch) |
| AC-3 (`out_of_reach after they walked back`) | the lifecycle's out-of-reach turn is reached by walking back to the centre, not by omission |
| AC-4, AC-5, AC-6 scripted rounds | `ScriptedRound.walk` replaces `place`; green on arrival (see the handoff) |

**Controls** - `tests/server/positions_controls_test.luau` runs both
batteries against `PositionsStubs.reference` / `SessionRoundStubs.reference`
and one-defect stubs, asserts the exact set each fires, and measures the
walking budget; `tests/server/session_round_controls_test.luau` keeps
SLICE-005's controls over the stand-in moved to `SessionRoundStubs.luau`,
with `mergesSamples` replaced by `replacesSamples` and `storesRawSamples`.

## Handoff: RED -> GREEN

**Model.** RED ran as `claude-fable-5-1` (Fable 5.1), the planned `fable`
row; the dispatch named no override.

### The command

    lune run test

The runner has no filter; it walks every `tests/**/*_test.luau` and prints
`N passed, M failed`. The lines that matter are
`grep -E "positions_test|session_positions_test|session_round_test"`.
Measured on this machine, warm: `959 passed, 0 failed` in 3m49s on arrival;
with this story's files `981 passed, 20 failed`, 2m13s to 2m44s on three
runs and 9m33s / 9m51s on two later ones (same files, so load on this
machine, not the suite - there is no per-test timeout in the runner and no
timeout in `gates.sh`, but note it). Never run two suites or a suite and the
gates at once; they collide.

### The failure output, verbatim (first line of each)

Twenty failures. Seventeen fail at the export check - the module does not
exist - which is a counted failure per criterion rather than one LOAD FAIL:

    FAIL  tests/server/positions_test.luau :: AC-1: a candidate at EXACTLY walkSpeed x TOLERANCE x dt + SLACK_STUDS is accepted and one a hair past it is refused - the bound is inclusive
          tests/server/positions_test:40: src/server/session/Positions.luau did not load: error requiring module "../../src/server/session/Positions": could not resolve child component "Positions" - VIEW-004's Contract exports TOLERANCE, SLACK_STUDS, RESYNC_SECONDS, placed(track, at, now), offer(track, candidate, now, walkSpeed) -> (Track, boolean), needsResync(track, now)
    (the same for the other 9 positions_test tests: AC-1 x5, AC-2, AC-3, AC-4, Contract x2)
    FAIL  tests/server/session_positions_test.luau :: AC-2: the deal's placement is the baseline - ...
          tests/server/session_positions_test:44: src/server/session/Positions.luau did not load: ... - VIEW-004's Contract exports TOLERANCE, SLACK_STUDS and RESYNC_SECONDS, which these Session-level checks read
    (the same for the other 6 session_positions_test tests: AC-3, AC-4, AC-5, Contract x3)

Three fail on their own assertion against today's `Session`, which is the
RIGHT failure for each - the store this story replaces:

    FAIL  tests/server/session_round_test.luau :: Contract (C-1): Session.new holds facility = nil, procedure = nil, positions = {} and (VIEW-004) tracks = {}, ...
          Contract: Session.new must hold facility = nil, procedure = nil, positions = {}, tracks = {} and accept options:
          state.tracks is nil from new, expected {} (VIEW-004)
    FAIL  tests/server/session_round_test.luau :: Contract (C-3): after every step of a two-round lifecycle ... follow the Contract's own composition ...
          after "sample in an empty Lobby": state.positions differs from the Contract's composition:
          value.ann: unexpected { x = 5, y = 0, z = 5 }
          (and on every partial batch: the players absent from it are dropped)
    FAIL  tests/server/session_round_test.luau :: Contract (C-3, rewritten by VIEW-004): PositionsSampled in Lobby, Round and Resolution merges the batch into the ACCEPTED positions ...
          "sample in an empty Lobby": state.positions is { ann = { x = 5, y = 0, z = 5 } }, expected the accepted positions {  } (the batch merged into the stored map; a player with no placement absent)
          "the turner of T2[1] sampled back at the spawn centre (walked away), alone in the batch": state.positions is { cat = { x = 0, y = 0, z = 64 } }, expected the accepted positions { ann = ..., bob = ..., cat = { x = 0, y = 0, z = 64 }, dan = { x = 80, y = 0, z = 112 } }
          "sample in Resolution": state.positions is { ann = { x = 7, y = 0, z = 7 } }, expected the accepted positions { ann = { x = 7, y = 0, z = 7 }, bob = ..., cat = ..., dan = ... }

So the rewritten C-3 check FAILS against today's Session for exactly the two
reasons the Contract names: a sample is stored with no baseline, and a batch
replaces rather than merges. Every other test in the repository passes
(`981 passed`), the SLICE-005 scripted rounds included.

### Files touched

New (6, all `test` by `paths.conf`):

- `tests/helpers/PositionsContract.luau` - `MODULE_CHECKS` (AC-1..AC-4, purity) over a Positions module; `SESSION_CHECKS` (AC-2..AC-5, tracks, merge, tuning) over `(Session, Positions)`.
- `tests/helpers/PositionsStubs.luau` - the reference rule and 16 one-defect rules (constants 1.5 / 2 / 3 are the STUB's own).
- `tests/helpers/SessionRoundStubs.luau` - SLICE-005's stand-in session, moved out of `session_round_controls_test.luau`, composing an injectable Positions module (`defects.positions`) plus 13 new wiring defects.
- `tests/server/positions_test.luau` - 10 tests, real `Positions`.
- `tests/server/session_positions_test.luau` - 7 tests, real `Session` + real `Positions`.
- `tests/server/positions_controls_test.luau` - 26 tests: both batteries' controls, D-4's shape on the scripted rounds, the walking budget.

Changed:

- `tests/helpers/ScriptedRound.luau` - `place` is GONE; `walk(d, targets, twin?)` walks at the tuning's walk speed, one Tick then one PositionsSampled (the whole map) per simulated second; `deal` seeds the driver's map from the step's own `Placed` effects; `maxMoveStuds` / `maxMoveSeconds`; runs report `walkSeconds` / `elapsed` / `chargedAt`.
- `tests/helpers/SessionRoundContract.luau` - the oracle carries `baselines` and applies a TOLERANCE-FREE rule (accepted iff a baseline exists and `distance <= walkSpeed x dt`; a plan sample outside that is a precondition failure); `everyoneAt` samples each player where the oracle last accepted them; the lifecycle spaces its moves by `ScriptedRound.maxMoveSeconds` and reaches `out_of_reach` by a walk back to the centre, alone in the batch; the C-1 check pins `tracks = {}`; C-3's `storesPositionSamplesAsAReplacingCopyAndEmitsNothing` is REPLACED by `mergesAcceptedSamplesAndEmitsOnlyResyncPlacements`.
- `tests/server/session_round_test.luau` - the C-1, AC-3 and C-3 names.
- `tests/server/session_round_controls_test.luau` - requires `SessionRoundStubs`; `mergesSamples` control replaced by `replacesSamples` and `storesRawSamples`; every other expected set re-measured unchanged.
- `.claude/tests/project-counters.test.sh` - `BASE_FORMAT`/`BASE_LINT` 153 -> 160, `BASE_TYPECHECK` 27 -> 28, `NARROW_FORMAT`/`NARROW_LINT` 27 -> 28 (post-GREEN prediction: 153 + 6 tests + 1 source), history comment added. Red until GREEN adds the one file.
- `docs/backlog/stories/VIEW-004.md` - this section and `## Test plan`.

Callers re-checked with `rg -n "PositionsSampled|\.positions|SessionState|ScriptedRound" src tests`
on 2026-10-04 (after the rewrite): `src/server/session/Session.luau` (the
only source); `tests/helpers/{ScriptedRound,SessionRoundContract,
SessionRoundStubs,PositionsContract,SessionContract}.luau`;
`tests/server/{session_round_test,session_round_controls_test,
session_positions_test,positions_controls_test,session_test,
turn_requests_controls_test}.luau`; and `FinaleContract`, `LensViewContract`,
`TurnContract` only through their own `case.positions` fixtures. The
Contract's list was right; `rg "\.place\("` finds no caller of the removed
`ScriptedRound.place`. `session_test.luau:29` still allows extra keys on
`SessionState`, so `tracks` breaks nothing in SLICE-003.

### The export shape the tests pin (fact, not suggestion)

`src/server/session/Positions.luau`, required as
`require("../../src/server/session/Positions")` from `tests/server/` and
read as a plain table:

    Positions.TOLERANCE: number       -- >= 1  (floor pinned; value not pinned beyond the settled controls)
    Positions.SLACK_STUDS: number     -- >= 0
    Positions.RESYNC_SECONDS: number  -- > 0
    Positions.placed(track: Track?, at: Vec, now: number) -> Track
    Positions.offer(track: Track?, candidate: Vec, now: number, walkSpeed: number) -> (Track, boolean)
    Positions.needsResync(track: Track?, now: number) -> boolean

`Track` is compared with `Deep.equal`, EXACTLY: a track is a table with the
keys `accepted` (a `{x, y, z}` copy), `acceptedAt`, `refusals`, and
`refusedSince` only while a run is open. **No other key may be present** -
an `offeredAt`, a `lastSample`, anything - or every `expectTrack` fails.
`offer(nil, ...)` returns `{ refusals = 0 }` and `false`;
`offer({ refusals = n }, ...)` (no `accepted`) returns `{ refusals = n }`
and `false`. `placed(nil, at, now)` returns
`{ accepted = copy(at), acceptedAt = now, refusals = 0 }`. A refused offer
returns `accepted`/`acceptedAt` unchanged, `refusals + 1`, `refusedSince`
kept or `= now`. An accepted offer returns `accepted = copy(candidate)`,
`acceptedAt = now`, no `refusedSince`, `refusals` kept. The bound is
`walkSpeed * TOLERANCE * max(0, now - acceptedAt) + SLACK_STUDS` over the
(x, z) distance, inclusive. The returned track is never the one handed in,
and `accepted` is never the candidate / `at` table.

The settled controls (literals, with the shipped walk speed 16): 200 studs at
dt 0.1 refused and 1.5 accepted - so `16 x TOLERANCE x 0.1 + SLACK_STUDS` must
lie in `[1.5, 200)`; a `TOLERANCE x 100` (D-1) puts it at 242 and the control
goes red.

`src/server/session/Session.luau`:

- `SessionState.tracks: { [string]: Positions.Track }`, `{}` from `new`.
  After the deal: exactly the dealt players, each
  `{ accepted = centre, acceptedAt = now, refusals = <carried> }` (compared
  exactly; a player not dealt is absent). The deal's `Placed` effects and
  `positions` are unchanged from SLICE-005.
- `state.positions` is EXACTLY the accepted positions: a fresh `{x, y, z}`
  per player with `track.accepted`; a player with no accepted sample ABSENT.
  A seated player may have NO track at all (AC-3's test strips one) and must
  then be offered as `nil` - do not index `tracks[p].accepted` unguarded.
- `PositionsSampled`, every phase: each `(playerId, sample)` offered with
  `state.tuning.instance.walk_speed_studs_per_second` (never
  `MechanicsTuning`'s); a batch MERGES (players absent from it keep track and
  position); `positions[p]` is never `event.samples[p]` itself; the state
  and the event are not mutated.
- Then, in `Round` only: every player with `needsResync(track, now)` true
  (evaluated AFTER the offer - the refusing sample itself counts) is
  `placed(track, track.accepted, now)` and ONE
  `{ kind = "Placed", playerId = p, position = <fresh copy> }` is emitted per
  such player, in ASCENDING `playerId` (the test's seat order is
  dan, cat, bob, ann, so seat order fails), the position not `rawequal` to
  `state.positions[p]`. That is the whole effect list of a sample: no
  RoundView, nothing else. In Lobby (and every other phase) a sample emits `{}`
  whatever the run, and the run stays open.
- The `Placed` effect's key set is `{ kind, playerId, position }` and the
  position's is `{ x, y, z }` (SLICE-005's `PLACED_KEYS` / `VEC_KEYS` still
  apply to the deal's).

NOT constrained, so it stays the implementer's choice: the VALUES of the
three constants beyond the floors and the settled controls (the Contract says
1.5 / 2 / 3, and the stubs use those - a different value that still meets the
controls passes); whether `tracks[p]` for a player sampled with no baseline
is `nil` or `{ refusals = 0 }` (both session tests accept either); the order
in which a batch is offered; how `Session` iterates `tracks` to find resync
candidates; the text of any error; whether `refusedSince = nil` is written
explicitly (Deep.equal cannot tell).

### Tests that passed on arrival, and what earns them

- SLICE-005's AC-4 (win and spawn control), AC-5 and AC-6 scripted rounds in
  `session_round_test.luau` pass against today's unfiltered Session with the
  WALKING `ScriptedRound`. Expected, and they are NOT claimed as watched to
  fail. What earns the rewrite is **D-4, in GATES**: with `Positions.offer`
  mutated to refuse every candidate, the win must go red. Its SHAPE was
  measured here on the stand-in: `standIn({ positions =
  PositionsStubs.refusesEverything })` fires `winsEveryScriptedRound...`
  with `expected committed` / `out_of_reach`, and also `losesByInstability`,
  `losesByTheClock` (k >= 1 needs a wrong turn in reach), the turn check,
  the oracle follow, and the lifecycle's no-penalty cascade (`clears`,
  `generates`, `ignores`, `secondsLeft`, `samples`, `placed`), while the
  spawn-room control still holds (everyone frozen at the centre still loses
  to the clock). Measured line:
  `positions = refusesEverything fires SLICE-005: { clears..., generates..., handlesATurn..., ignoresATurn..., losesByInstability..., losesByTheClock..., mergesAcceptedSamples..., placesEverySeatedPlayer..., roundFacilityProcedureAndPositionsFollow..., secondsLeft..., winsEveryScriptedRound... }`.
- The other 12 SLICE-005 tests (deal, generation failure, AC-3's turn,
  ignored turns, clearing, order, secondsLeft, purity) pass on arrival with
  the re-timed lifecycle; they are SLICE-005's and unchanged in meaning.
  Their controls in `session_round_controls_test.luau` were re-measured and
  every expected set is unchanged from SLICE-005's except the two sample
  controls, which this story rewrote.

### Negative controls: expected values, measured in RED

Not one assertion in `positions_test.luau` or `session_positions_test.luau`
has run against the module - it does not exist. The numbers below were
measured by `positions_controls_test.luau` against the STUBS (reference
constants 1.5 / 2 / 3, shipped walk speed 16). **Confirming each against the
shipped module is GREEN's job**: after GREEN, `positions_test` and
`session_positions_test` must be green AND the same `[measured]` lines must
still print the same sets.

Thresholds the checks compute (from the reference constants):

| Quantity | Expression | Value measured |
|---|---|---|
| bound at dt 0.1 | `16 x 1.5 x 0.1 + 2` | 4.4 |
| bound at dt 1 | `16 x 1.5 x 1 + 2` | 26 |
| bound at dt 3 / 3.5 / 4 | | 74 / 86 / 98 |
| dt-case distance | `bound(3.5) + 1` | 87: refused at 3 and 3.5, accepted at 4 |
| exact-bound case | `bound(1)` / `+ 1e-6` | 26 accepted / 26.000001 refused |
| clamp case | `SLACK_STUDS` / `+ 0.5` at dt < 0 | 2 accepted / 2.5 refused |
| resync | run of exactly 3 s / 3.000001 s | false / true |
| session jump | 1,000 studs vs `bound(1)` = 26 (AC-2), `bound(5)` = 122 (AC-4), `bound(2)` = 50 (tracks) | refused |
| AC-5 fixture | machine beyond `turn_range` 10 and `bound(0.1)` 4.4 | nearest machine to a spawn centre is 22.63 studs |
| tuning case | jump `bound(1) + 16` = 42 at dt 1 | refused at speed 16, accepted at 160 |

Module checks, exact fire-sets (`[measured]` lines):

| Control (one defect) | Fires exactly |
|---|---|
| reference | nothing (0 of 10) |
| `tolerance100` (D-1's shape) | `settledControls`, `placedResetsTheBaseline`, `needsResync` - and PASSES `boundIsInclusive`, `dt`, `clamp`, which read the constant from the module |
| `exclusiveBound` (D-2's shape) | `boundIsInclusive`, `nowBeforeAcceptedAtClampsDtToZero` |
| `countsY` | `yIsIgnored` |
| `dtFromLastOffer` | `dtIsMeasuredFromTheLastAcceptedSample` |
| `negativeDt` / `absoluteDt` | `nowBeforeAcceptedAtClampsDtToZero` |
| `acceptsWithoutBaseline` / `countsNoBaselineAsRefusal` | `noBaselineMeansNoAcceptanceAndNoRefusal` |
| `placedKeepsRefusedSince` / `placedDropsRefusals` | `placedResetsTheBaseline` |
| `refusedSinceRestartsEachRefusal` | `dt...`, `placedResetsTheBaseline` |
| `acceptanceKeepsRefusedSince` | `dt...`, `needsResync...` |
| `resyncInclusive` (D-5's shape) / `resyncWithoutRefusals` | `needsResyncIsStrictlyAfterResyncSeconds` |
| `mutatesTrack` | `isPure`, `settled`, `boundIsInclusive`, `placed`, `needsResync`, `yIsIgnored`, `clamp` |
| `aliasesCandidate` | `isPure`, `placedResetsTheBaseline` |
| `refusesEverything` (D-4's shape) | all but `exportsTheContractShape` and `isPure` |
| `TOLERANCE = 0.5` exported, 1.5 used | `exportsTheContractShape`, `boundIsInclusive`, `dt...` |

Session checks (stand-in session; `P` for constants = the reference rule):

| Control | Fires exactly |
|---|---|
| reference | nothing (0 of 7; and 0 of 16 SLICE-005 checks) |
| `storesRawSamples` (D-3's shape) | `deal`, `unplaced`, `resync`, `turn`, `tuning` (passes `tracks`, `merge`) |
| `replacesSamples` (SLICE-005's store) | `deal`, `resync`, `merge` |
| `positions = tolerance100` | `resync`, `turn`, `tracks`, `tuning` (passes `deal`: 1,000 > 482) |
| `positions = refusesEverything` | `deal`, `resync`, `turn` (the positive control), `merge`, `tuning` |
| `positions = resyncInclusive` (D-5 in Session) | `resync`, naming "exactly RESYNC_SECONDS" |
| `noResync`, `resyncEverywhere`, `resyncAtTheSample`, `resyncDescending`, `resyncAlsoBroadcasts`, `resyncAliasesPosition` | `resyncPlacesBackInRoundOnly`, each |
| `dealKeepsOldTracks`, `dealDropsRefusals`, `tracksMissingFromNew` | `tracksFromNewAndTheDeal`, each |
| `walkSpeedFromShippedTuning` | `walkSpeedIsReadFromTheSessionsTuning` |
| `storesSamplesByReference` | `samplesMergeIntoFreshAcceptedCopies` |

SLICE-005's controls over the moved stand-in (`session_round_controls_test`):
`replacesSamples` and `storesRawSamples` each fire exactly
`{ mergesAcceptedSamples..., roundFacilityProcedureAndPositionsFollow... }`
(the latter on the empty-Lobby sample alone); `storesSamplesByReference`
fires `{ mergesAcceptedSamples... }`; every other control's set is as
SLICE-005 recorded it.

### The walking budget, re-read (measured, local)

`maxMoveStuds` = sqrt(2) x ((3 - 1) x 64 + 32) = 226.27 studs; at 16 studs/s
`maxMoveSeconds` = 15, NOT the "~8 s" the Contract guessed (that was a
single room pitch; the diagonal of the 3 x 3 grid is what a move can be).
Measured over the reference stand-in: win script, 150 rounds (seeds 1..50 x
n 4, 5, 6): max 75 s walking, max 83 s from the deal to the Tick after the
completing turn; instability script 25 s; clock script's charging 18 s. The
earliest penalised deadline is 420 - 4 x 20 = 340 s into the round. Nothing
needed re-fitting; `clockOut`'s loop and `loseByInstability`'s twin simply
start later. The budget test in `positions_controls_test.luau` pins all four
numbers against 340.

### Deferred verifications - DECLINED in RED, all five

The module does not exist and `Session` does not call it, so none can be run
here. Each names the test that must go red:

- **D-1** (TOLERANCE x 100): `positions_test :: AC-1: from a placement at the origin, a candidate 200 studs ...` (the settled control; shape measured as `tolerance100` above). Note D-1 does NOT redden the inclusive-bound test, which reads the constant - that is by design.
- **D-2** (`<` for `<=`): `positions_test :: AC-1: a candidate at EXACTLY ...` (and the clamp test, as `exclusiveBound` measured).
- **D-3** (raw sample stored): `session_positions_test :: AC-5 ...` and `:: AC-3 ...` (shape measured as `storesRawSamples`: also `deal`, `resync`, `tuning`).
- **D-4** (`offer` refuses everything): `session_round_test :: AC-4: over 50 seeds ... wins every round` (shape measured on the stand-in, see above). Also `session_positions_test :: AC-5` on its positive control.
- **D-5** (`>=` for `>`): `positions_test :: AC-4: needsResync ...` on the exact case, and `session_positions_test :: AC-4 ...` on "dan refused for exactly RESYNC_SECONDS".

### Discovered, and it changes the approach

1. **A sample at the same `now` as the previous accepted one has dt 0.** The
   first draft of `walk` sampled the first 16-stud step at the deal's own
   `now` and every walk's first sample was refused; walks from the spawn
   room still caught up (the bound grows 1.5x faster than the walk), short
   walks between machines did not. `walk` now ticks FIRST, then samples the
   position reached in that second. GREEN's driver (`RoundService`, later)
   should sample AFTER advancing time, never on the placement's own tick.
2. **The driver starts from where the server SAID it placed the player.**
   `ScriptedRound.deal` reads the step's `Placed` effects; computing the
   centre itself made the pre-existing `placesAtTheFirstMachine` control
   look like a walking failure.
3. **The same player can hold both T1[1] and T2[1]**, so the lifecycle
   spaces the two machine samples a whole walk apart.
4. **The lifecycle oracle is tolerance-free on purpose** (bare walk speed,
   no slack): it never reads the constants, so it needs no module in RED and
   accepts under any admissible constants in GREEN. A plan sample outside
   bare walk speed is a precondition failure, not a refusal - the
   implausible cases live in `PositionsContract` where the constants are
   read. Do not "fix" a lifecycle failure by loosening that oracle.
5. `walk_speed_studs_per_second` is read by NOTHING in `src/` today
   (`rg walk_speed src` -> only `MechanicsTuning.luau`); `Session` is its
   first reader, from `state.tuning`.
6. **Contract, unamended but made exact by the tests**: `Track` is compared
   exactly (no extra fields); a seated player may lack a track (AC-3's
   test); `needsResync` is evaluated after the batch is offered, so the
   sample that crosses the threshold is itself refused and counted
   (`refusals` 3 in the AC-4 test), then placed.

### Fast gates on RED's tree (run, 2026-10-04, this machine)

    PASS         format (1s, observed 159)
    PASS         lint (1s, observed 159, floor 1)
    PASS         typecheck (4s, observed 27)
    FAIL         unit (134s, exit 1) -> .claude/state/gate-logs/unit.log     # 981 passed, 20 failed - the twenty above
    PASS         build (1s, observed 103831)
    FAIL         harness (26s, exit 1) -> .claude/state/gate-logs/harness.log # project-counters: 28 passed, 12 failed
    real 8m33s (the whole --fast run; the unit gate itself took 134 s)

The 12 harness failures are exactly the stray-.luau precondition (clears at
the RED commit) and the 11 count assertions only GREEN's one source file
satisfies: `expected count: 160 / actual count: 159` for format and lint,
`28 / 27` for typecheck and both narrow src cases, `161 / 160` and `29 / 28`
for the untracked-file cases, `160 / 159` and `28 / 27` for the ignored-file
cases. `stylua --check tests` and `selene tests` are clean. Nothing failed on
a timeout, a config error or a lint rule.

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

    run:    2026-10-04T20:33:25Z
    commit: ed0aff4
    tree:   61fdf912f60e4af361ad579d0a31767381450015
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 160)
    PASS         lint (1s, observed 160, floor 1)
    PASS         typecheck (4s, observed 28)
    PASS         unit (191s, observed 1001, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 106829)
    PASS         harness (34s, observed 40)
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

### PO decisions at PLANNED → RED (2026-10-04)

The first three were put to the user before RED and answered by them.

- **PO-1. AC-4 now means a pull-back (user decision).** As drafted, AC-4 said
  "when the driver next places them, the baseline resets", which every placement
  already does, so `RESYNC_SECONDS` did nothing. Now: in `Round`, after more than
  `RESYNC_SECONDS` of unbroken refusals, `Session` places the player back at
  their last accepted position with a `Placed` effect. AC-4's text was changed in
  PLANNED.
- **PO-2. AC-5 is proved with a turn (user decision).** No ping exists in
  `Session` (CHAN-005/006 are PLANNED), and the lens view is not wired until
  SLICE-006. Turning is the range rule `Session` runs today. `Procedure.tick`
  ignores positions and `partnerLamps` is not called from `Session`, so the
  partner lamp is not claimed here. Every later rule that reads
  `state.positions` inherits the check. AC-5's text was changed in PLANNED.
- **PO-3. The scripted rounds walk (user decision).** SLICE-005's
  `ScriptedRound.place` teleports by sample, which this story refuses. RED
  rewrites it to walk at the tuning's walk speed. No test bypass goes into
  `SessionOptions`; the user declined a production switch that turns off a
  security check. D-4 earns the rewrite.
- **PO-4. Contract precision** (`## Contract`): `Track.refusals`; `walkSpeed`
  passed to `offer` from `state.tuning`; the inclusive bound measured from the
  last accepted sample; no baseline is not a refusal; resync only in `Round`,
  strict `>`, ascending `playerId`; samples merge rather than replace.
- **PO-5. Gate.** `unit` is `required` and `covers src/server/**`;
  `required_gates` stays empty.
- **PO-6. Epic check.** EPIC-07 done-when 4 ("a position sample that could not
  have been walked to is not used by any range rule") is AC-1, AC-3 and AC-5.
  Today the only range rule in `Session` is the turn, and the rest will read
  the same `state.positions`. Done-when 1 and 2 are DONE (VIEW-001, VIEW-002).
  Done-when 3 is VIEW-003, blocked on CHAN-006. No gap this story should close.
- **PO-7. Size.** This story now also rewrites SLICE-005's scripted-round
  driver and its C-3 check. That is still one RED→GREEN cycle: the source
  changes are one new pure module and one `Session` branch, and the test
  rewrite is what the check makes necessary. If RED finds the scripted budgets
  cannot be re-fitted inside the round, that is an escalation, not a quiet split.

### RED verified by the orchestrator (2026-10-04)

- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), dispatched with
  `model: fable` per the plan row; no override reported.
- `lune run test`, run independently: `981 passed, 20 failed`. Ten in
  `positions_test.luau` and seven in `session_positions_test.luau`, all at
  `src/server/session/Positions.luau did not load`. Three in
  `session_round_test.luau` on their own assertions against today's `Session`:
  the C-1 `tracks = {}` pin, the oracle-follow check, and the rewritten C-3
  merge/accepted-only check. Every other test passes, including the walking
  scripted rounds, which are **not** claimed as watched to fail: D-4 earns them
  in GATES.
- Read `ScriptedRound.walk`: it reads walk speed from the tuning in use, moves
  at most that far per simulated second (inside the bound), and ticks before it
  samples, so no sample shares a `now` with the last.
- `## Amendments` added by the orchestrator for the PLANNED-phase AC-4 and AC-5
  edits. `check-boundaries.sh` requires it whenever the criteria differ from
  `main`, in whatever phase they were edited (SLICE-005 hit this at REVIEW).
- RED committed as `7e572ce` with the story at `phase: RED`. `bash
  scripts/gates.sh --fast` at `7e572ce`: PASS format (159), lint (159),
  typecheck (27), build; FAIL unit (104 s, `981 passed, 20 failed`, the twenty
  above and nothing else); FAIL harness (`project-counters: 29 passed, 11
  failed`). The stray-.luau precondition cleared at the commit. All eleven
  harness failures are the counter baselines set to their post-GREEN values
  (e.g. `expected count: 160 / actual count: 159`; typecheck and narrow 28 vs
  27), which only GREEN's one new source file (`Positions.luau`) can satisfy.
  The "92 files" in their names is stale test wording, not a measurement.
  Admissible: no timeout, config or lint failure.

### GREEN

- GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5, from the session's
  own model identification); the dispatch named no override.
- **Changed.** New `src/server/session/Positions.luau`: pure, requires
  nothing, `Vec`/`Track` types, `TOLERANCE = 1.5`, `SLACK_STUDS = 2`,
  `RESYNC_SECONDS = 3`, `placed`/`offer`/`needsResync` exactly per the
  Contract; header carries the engineering-constant justification.
  `src/server/session/Session.luau`: `SessionState.tracks` (`{}` from `new`);
  `PositionsSampled` clones the tracks map, offers each sample with
  `state.tuning.instance.walk_speed_studs_per_second`, in `Round` only places
  every `needsResync` player back (ascending `playerId`, one `Placed` each,
  fresh position), and derives `positions` from the tracks' `accepted` (fresh
  copies, never-accepted absent); the deal replaces `tracks` with the dealt
  players `Positions.placed(old, centre, now)`; Lobby entry keeps both. Header
  comment updated (the "replaces positions" paragraph). Nothing else touched.
  A track for a player outside the batch is shared by reference with the old
  state - never mutated, since `offer`/`placed` always return fresh tables.
- **Tests.** `lune run test`: `1001 passed, 0 failed` (1m52s).
  `bash scripts/frozen.sh verify`: `frozen: OK — 14 path(s) unchanged since
  the snapshot for VIEW-004`.
- **Fast gates** (`bash scripts/gates.sh --fast`, 7m21s): PASS format
  (observed 160), lint (160), typecheck (28), unit (257 s, observed 1001),
  build; UNCONFIGURED coverage; FAIL harness - `project-counters: 39 passed,
  1 failed`, the one failure being the stray-.luau precondition
  (`actual: M src/server/session/Session.luau / ?? src/server/session/Positions.luau`),
  which clears when the orchestrator commits. The eleven count cases RED set
  (160/160/28, narrow 28) all pass now.
- **Negative controls, RED's expected vs measured against the shipped
  module** (scratch script `.claude/state/scratch/confirm.luau`, ignored):

| Quantity | RED expected | GREEN measured |
|---|---|---|
| bound(0.1) / bound(1) | 4.4 / 26 | 4.4 / 26 |
| bound(2) / (3) / (3.5) / (4) / (5) | 50 / 74 / 86 / 98 / 122 | 50 / 74 / 86 / 98 / 122 |
| settled controls | 200 @ 0.1 refused, 1.5 accepted | refused / accepted |
| exact bound | 26 accepted / 26.000001 refused | accepted / refused |
| dt case (87) | refused @3, @3.5; accepted @4 | refused, refused (refusals 2, run from 3), accepted (run cleared, refusals 2) |
| clamp case | 2 accepted / 2.5 refused | accepted / refused |
| resync | false at 3 s / true at 3.000001 s | false / true |
| tuning case (42 at dt 1) | refused at 16, accepted at 160 | refused / accepted |
| AC-5 fixture | beyond turn range 10 and bound(0.1) 4.4; "nearest machine to a spawn centre is 22.63" | seed 107's T1[1] machine (15) is 93.30 studs away: precondition holds. Benign: 22.63 is the minimum over machines, 93.30 is the fixture's own machine |
| real `Positions`, MODULE_CHECKS | reference stub fires 0 of 10 | 0 of 10 |
| real `Session` + `Positions`, SESSION_CHECKS | reference stand-in fires 0 of 7 | 0 of 7 |
| real `Session`, SLICE-005 CHECKS | reference stand-in fires 0 of 16 | 0 of 16 |

  The stub-control `[measured]` lines in `positions_controls_test` print the
  same sets as RED's table (e.g. `storesRawSamples`, `positions =
  tolerance100`, `refusesEverything`, the walking budget 15 s / 75 s / 83 s /
  25 s / 18 s against 340 s). No divergence other than the AC-5 row above.

### GREEN freeze (orchestrator, 2026-10-04)

Snapshot taken right after `phase.sh set VIEW-004 GREEN` over the eleven files
RED committed (`project-counters.test.sh`, `PositionsContract`,
`PositionsStubs`, `ScriptedRound`, `SessionRoundContract`,
`SessionRoundStubs`, `positions_controls_test`, `positions_test`,
`session_positions_test`, `session_round_controls_test`,
`session_round_test`) plus `turn_requests_test`, `SessionContract` and
`session_test`. Before leaving GREEN:

    frozen: OK — 14 path(s) unchanged since the snapshot for VIEW-004

- GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5), planned `opus`,
  dispatched with `model: opus`; no override reported.
- The orchestrator read `Positions.offer` and `needsResync` against the
  Contract: inclusive bound measured from the last accepted sample, `dt`
  clamped at 0, no baseline is not a refusal, strict `>` for resync.
- `bash scripts/gates.sh --fast` by the orchestrator at `ed0aff4` (GREEN
  committed, tree clean): PASS format (160), lint (160), typecheck (28), unit
  (130 s, `1001 passed, 0 failed`), build (106829), harness (`project-counters:
  40 passed, 0 failed` — RED's eleven post-GREEN count predictions now hold);
  `changes: 2 changed source path(s), all exercised by a required gate`;
  `All required gates passed (6 ran, 1 unconfigured, 0 known).`

### GATES (orchestrator, 2026-10-04)

- Snapshot re-taken right after `phase.sh set VIEW-004 GATES`, same 14 paths.
  Before leaving GATES: `frozen: OK — 14 path(s) unchanged since the snapshot for VIEW-004`.
- D-1..D-5 run before `gates.sh`; results pasted under `## Deferred
  verifications`. All five went red where required. D-4 also earns RED's
  walking `ScriptedRound`.
- Full `bash scripts/gates.sh` at `ed0aff4`, chained after the mutations and
  run only once `src` was clean and no `.bak` remained: all required gates
  passed (6 ran, 3 unconfigured, 0 known; unit 191 s, `observed 1001`); see
  `## Gate results`. No source change was needed in GATES, so no
  feature-developer dispatch. No gate added or changed, so no `## Gate probes`.
- GATES - `lead-po` (orchestrator, no subagent) - `claude-opus-5-5`.
