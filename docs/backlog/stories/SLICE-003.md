---
id: SLICE-003
title: The session deals seats and sends each player only their own seat view
slug: the-session-deals-seats-and-sends-each-p
epic: EPIC-03
type: feature
status: in-review
phase: REVIEW
branch: story/SLICE-003-the-session-deals-seats-and-sends-each-p
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`, the M3 walking skeleton. M1 built a phase machine that emits
`AssignSeats` and waits for `SeatsAssigned`; M2 built `Ring.assign` and the
allowlisted `Projection.forPlayer`. **Nothing connects them.** `architecture.md`
§9.2 (D22) puts that connection in a pure composition root, `Session`, so that
"the pieces compose" is something a required gate can check rather than
something only a Studio session shows.

This story is the thinnest `Session` that does real work: it carries out
`AssignSeats`, feeds `SeatsAssigned` back in the same step, sends each seated
player **their own** seat view and nobody else's, and broadcasts a minimal
public `RoundView` (phase and seconds left). Every later M3 piece (facility,
Procedure, channel, views) is added to this module by its own story.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a session with `players_min` joined players and the lobby
  timer elapsed, when a `Tick` is stepped, then in that one step the phase
  reaches `Round`, `Ring.assign` has been applied with the round's seed, and the
  resulting assignment equals `Ring.assign(players, Rng.fromSeed(seed))` for the
  seed the phase machine's `AssignSeats` effect carried.
  *Control:* a session that assigns with a fixed seed (not the effect's) must
  fail this AC across two consecutive rounds, whose seeds differ.
- **AC-2** — Given AC-1's step, when its effects are read, then there is exactly
  one `SendTo` effect of kind `SeatView` per seated player, addressed to that
  player, whose payload equals `Projection.forPlayer(assignment, thatPlayer)`,
  and **no `Broadcast` effect carries a seat view**.
  *Control:* a session that broadcasts the list of all seat views must fail.
- **AC-3** — Given a seated round, when a seated player leaves, then the session
  applies `Ring.withdraw` and sends a fresh `SeatView` to every remaining player
  whose view changed (at least the leaver's supplier, whose `keyClasses` grew),
  and to no one whose view is unchanged.
- **AC-4** — Given any step that changes the phase or the player count, and
  every `Tick` while the phase has a duration, when effects are read, then there
  is one `Broadcast` of kind `RoundView` whose payload is exactly
  `{ phase, secondsLeft, players, playersMin, playersMax }`: `secondsLeft` is the
  whole-second ceiling of the time left in `Lobby`, `Round` or `Post`, and `nil`
  in `Assignment` and `Resolution`, and in a `Lobby` below `players_min` (the
  timer holds, `architecture.md` §3).
- **AC-5** — Given the phase machine's own effects (`Emit`, `PromptRematch`,
  `ComputeTrace`), when a step produces them, then the session passes them
  through unchanged and in order; `AssignSeats` is the only one it consumes.

## Contract

**Module.** `src/server/session/Session.luau`, pure.

    export type SessionState = {
        round: PhaseMachine.RoundState,
        assignment: Ring.Assignment?,
    }
    -- Later M3 stories add facility, procedure, channel, positions (architecture.md §9.2).

    export type SessionEvent = PhaseMachine.Event   -- PlayerJoined, PlayerLeft, Tick, RematchAccepted
    -- SeatsAssigned is produced inside Session, never accepted from outside:
    -- a SessionEvent of kind SeatsAssigned is ignored like any unknown event (D5).

    export type RoundView = { phase: PhaseMachine.Phase, secondsLeft: number?, players: { string }, playersMin: number, playersMax: number }
    -- players: the round state's `players`, in join order (= seat order once dealt); public

    export type SessionEffect =
          { kind: "SendTo", playerId: string, payloadKind: "SeatView", payload: Projection.PublicSeatView }
        | { kind: "Broadcast", payloadKind: "RoundView", payload: RoundView }
        | PhaseMachine.Effect   -- minus AssignSeats, passed through

    Session.new(config: RoundConfig.RoundConfig, seed: number, roundId: string, sessionId: string) -> SessionState
    Session.step(state: SessionState, event: SessionEvent, now: number) -> (SessionState, { SessionEffect })

- `RoundView` lives here for now; `VIEW-003` moves it to
  `src/server/round/RoundView.luau` and widens it. Its field names are fixed by
  this story.
- `payloadKind` strings are exactly `Transport`'s kinds (`SLICE-002`), so the
  interpreter in `SLICE-004` maps effects one to one.
- `secondsLeft` is computed from `now − round.phaseEnteredAt` against the config
  duration, **never** sent as an absolute time: the server's clock is not the
  client's (`architecture.md` §9.7).
- The ring is dealt from `Rng.fromSeed(effect.seed)`. `Ring.assign` derives
  `"seats"` itself; `Session` does not derive again.

**Pinned at PLANNED → RED (2026-10-02, lead-po).** RED may amend any block
below in place, with a reason; GREEN builds what the amended block says.
Everything here was read off the real modules (`PhaseMachine.luau`,
`Ring.luau`, `Projection.luau`, `RoundConfig.luau`) on that date.

- **`Session.new`** returns `{ round = PhaseMachine.initial(config, seed,
  roundId, sessionId), assignment = nil }`. The `round` it holds must
  deep-equal `PhaseMachine.initial` on the same arguments.
- **One step, two machine steps.** `step` feeds `event` to
  `PhaseMachine.step`. If the effects contain `AssignSeats`, it deals
  `Ring.assign(effect.players, Rng.fromSeed(effect.seed))`. It uses the
  effect's `players` and `seed`, never `round.players` or `round.seed`, which
  are equal today but are not the contract. It then steps the phase machine
  again with `{ kind = "SeatsAssigned" }` at the same `now`, so the returned
  state is in `Round`. `step` mutates neither its `state` nor its `event`.
- **Events from outside.** A `SeatsAssigned` event from outside is ignored:
  the same state comes back, with `{}` effects and no RoundView. Every other
  `PhaseMachine.Event` kind is forwarded unchanged, `RoundResolved` included.
  `SLICE-005` decides whether `RoundResolved` becomes internal. The type alias
  stays `PhaseMachine.Event`.
- **Effect order within one step.** This is the shape RED pins:
  1. the phase machine's pass-through effects (`Emit`, `PromptRematch`,
     `ComputeTrace`), in emission order, first step's then the `SeatsAssigned`
     step's, with `AssignSeats` removed;
  2. the `SendTo`/`SeatView` effects, in the assignment's seat order
     (`assignment.players`);
  3. at most one `Broadcast`/`RoundView`, last.

  AC-5 itself only requires the pass-through effects to keep their relative
  order.
- **When the assignment is cleared.** `assignment` is set by the dealing step,
  kept through `Round`, `Resolution` and `Post`, and **cleared to `nil` by the
  step that enters `Lobby`**. A stale ring in the next lobby would otherwise be
  withdrawn from, and seat views sent, for a round that no longer exists.
- **AC-3 withdraw rule.** On `PlayerLeft`, the session applies
  `Ring.withdraw(assignment, leaver)` **iff** `assignment ~= nil` and the phase
  machine actually unseated the leaver: the leaver is in the old
  `round.players` and not in the new one. Today that happens only for a leave in
  `Round`, including the leave that drops the round below quorum and resolves it
  in the same step. Leaves in `Resolution` and `Post`, duplicate leaves, and
  leaves by strangers withdraw nothing and send no `SeatView`.
  - **Recipients:** every remaining seated player `p` for whom
    `Projection.forPlayer(new, p)` does not deep-equal
    `Projection.forPlayer(old, p)`, in the new ring's seat order. The leaver is
    never a recipient.
  - **Every remaining view changes today**, because `PublicSeatView.seatOrder`
    is public and shrinks on every withdrawal. So with the real modules the
    recipient set is "every remaining player". The "no one whose view is
    unchanged" half is still the rule GREEN builds, as a diff rather than a
    broadcast, and the leaver is the only no-send case the real data can show.
    PO decision 2.
- **AC-4 RoundView: when it is sent.** One per step, built from the state at
  the **end** of the step, and emitted when any of these hold:
  - the phase at the end differs from the phase at the start;
  - `#round.players` differs;
  - the event is a `Tick` and the end phase is `Lobby`, `Round` or `Post`.

  A step that is a pure no-op, such as a refused join, a stranger's leave or an
  ignored event, emits nothing.
- **AC-4 RoundView: what it carries.**
  - `players` is a **copy** of `round.players`.
  - `playersMin` and `playersMax` are `config.playersMin` and
    `config.playersMax`.
  - `secondsLeft` is `math.ceil(duration − (now − round.phaseEnteredAt))`, where
    `duration` is `config.lobbySeconds`, `config.roundSeconds` or
    `config.postRoundSeconds`, never a literal.
  - `secondsLeft` is `nil` in `Assignment` and `Resolution`, and in a `Lobby`
    with `#players < playersMin`.

  So the dealing step's RoundView says `Round` with
  `secondsLeft == config.roundSeconds`. Case for RED: a fractional elapsed time
  must round **up**, e.g. 0.5 s into the lobby is `lobbySeconds` and not
  `lobbySeconds − 1`.
- **Seed per round (AC-1 control).** Two consecutive rounds run through
  `Round` → (Tick at `roundSeconds`) `Resolution` → `Post` → (Tick at
  `postRoundSeconds`) `Lobby` → (Tick at `lobbySeconds`) the second deal. Each
  deal must equal `Ring.assign(effect.players, Rng.fromSeed(effect.seed))` for
  **its own** `AssignSeats` seed. The two seeds differ, because
  `nextSeedFrom` re-derives the seed on entering `Lobby`. A fixed-seed stand-in
  must fail.
- **Type.** `SessionEffect`'s pass-through arm is `PhaseMachine.Effect`. The
  type cannot express "minus `AssignSeats`", so AC-5 pins it behaviourally.
- **Constants from tuning.** `players_min = 4`, `players_max = 6` and
  `min_players_to_continue = 3` come from `src/shared/Tuning.luau`. Tests read
  them through `RoundConfig.fromTuning(Tuning)`, never as literals.

**Existing exports: no signature changes.** Callers are unaffected. Checked
2026-10-02: `rg -n "Session" src tests` returns only the `sessionId` field of
`PhaseMachine` and telemetry, and no `src/server/session/` exists. RED's
handoff restates this against the tree.

**Oracle partition.** AC-1, AC-2, AC-3 and AC-5 are **mechanical**: compare to
the M2 functions' own output, never to a hand copy. AC-4 is **settled**: the
durations are `RoundConfig`'s; read them, do not restate them.

## Deferred verifications

**D-1. AC-2 discriminates.** With `scripts/mutate.sh` changing the `SendTo`
effect's `playerId` to the first seated player for every view, AC-2 **must**
fail. RED cannot run this; there is no `Session` yet. Owner: GATES.

*Result (GATES, 2026-10-02, lead-po): HOLDS.* Every dealt view was addressed to
`dealt.players[1]`. AC-2 and the order pin went red, and the file was restored
byte-for-byte.

    203 + 			table.insert(sends, seatView(dealt, dealt.players[1]))
      FAIL  tests/server/session_test.luau :: AC-2: on each dealing step there is exactly one SendTo/SeatView per seated player, addressed to them, payload deep-equal to Projection.forPlayer(assignment, p), nobody else addressed, and no Broadcast on any step carries a seat view by kind or by shape
      FAIL  tests/server/session_test.luau :: Contract: within a step the effects are ordered pass-through first, then SendTo/SeatView in seat order, then at most one Broadcast last
    857 passed, 2 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T203315Z.1344532.bak) ===

**D-2. AC-1 reads the effect's seed.** With `scripts/mutate.sh` making
`Session` deal from `Rng.fromSeed(0)` (or from any fixed value) in place of the
effect's seed, AC-1 **must** fail on the two-round case. RED cannot run this.
Owner: GATES.

*Result (GATES, 2026-10-02, lead-po): HOLDS.* Dealing from `Rng.fromSeed(0)`
turned both AC-1 tests red, including the two-round case. AC-2 and both AC-3
deal-dependent tests went red with them. The file was restored byte-for-byte.

    198 + 		local dealt = Ring.assign(deal.players, Rng.fromSeed(0))
      FAIL  tests/server/session_test.luau :: AC-1: across two consecutive rounds (Round -> Resolution -> Post -> Lobby -> deal) the AssignSeats seeds differ and each deal equals Ring.assign from ITS OWN effect's seed - a fixed-seed session fails
      FAIL  tests/server/session_test.luau :: AC-1: with players_min joined and the lobby timer elapsed, one Tick reaches Round and state.assignment deep-equals Ring.assign(effect.players, Rng.fromSeed(effect.seed)) for the AssignSeats effect PhaseMachine.step emits
      FAIL  tests/server/session_test.luau :: AC-2: on each dealing step there is exactly one SendTo/SeatView per seated player, ...
      FAIL  tests/server/session_test.luau :: AC-3: when a seated player leaves a six-player Round (quorum kept), ...
      FAIL  tests/server/session_test.luau :: AC-3: with players_min seated, a leave that keeps quorum and then one that drops below it ...
    854 passed, 5 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T203734Z.1351940.bak) ===

**D-3. AC-4's ceiling is a ceiling (a wrong value, not a missing field).** With
`math.ceil` mutated to `math.floor` in the `secondsLeft` computation, AC-4
**must** fail. Separately, with the `Round` duration read from
`config.lobbySeconds`, AC-4 **must** fail. RED cannot run this. Owner: GATES.

*Result (GATES, 2026-10-02, lead-po): HOLDS on both.* Both are wrong-value
mutations. (a) `math.ceil` to `math.floor`, and (b) the `Round` duration read
from `config.lobbySeconds`. Each turned AC-4's payload test red, alone, and
each file was restored byte-for-byte. A single-assertion catch in each case is
expected: only that test reads `secondsLeft`.

    148 + 	return math.floor(duration - (now - round.phaseEnteredAt))
      FAIL  tests/server/session_test.luau :: AC-4: every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax } by pairs; secondsLeft = ceil(RoundConfig duration - elapsed) ... - 0.5 s in rounds UP, the dealing step says roundSeconds - ...
    858 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T204155Z.1358010.bak) ===

    141 + 		duration = config.lobbySeconds
      FAIL  tests/server/session_test.luau :: AC-4: every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax } by pairs; ...
    858 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T204619Z.1364217.bak) ===

**D-4. AC-3 never addresses the leaver.** With the withdraw step mutated to
send a `SeatView` to every player in the **old** ring, so that it addresses the
leaver, `Projection.forPlayer` raises for the leaver against the new ring.
Either the step raises or AC-3 **must** fail; the suite must go red either way.
RED cannot run this. Owner: GATES.

*Result (GATES, 2026-10-02, lead-po): HOLDS, by the "step raises" branch.* The
withdraw step was mutated to iterate the **old** ring, so it addresses the
leaver. `Projection.forPlayer(withdrawn, leaver)` raises, `Session.step` raises
on that leave, and every test whose plan passes through it went red: 14 of 15,
all but `Session.new`. The file was restored byte-for-byte.

    214 + 		for _, playerId in old.players do
      FAIL  tests/server/session_test.luau :: AC-3: when a seated player leaves a six-player Round (quorum kept), ... and never to the leaver
      ... (13 more, every plan-driven test in tests/server/session_test.luau)
    845 passed, 14 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .claude/state/mutations/src_server_session_Session.luau.20261002T205032Z.1370207.bak) ===

## Out of scope

- The facility, the Procedure, the channel, positions: later stories add them.
- Performing effects: the interpreter and the driver are `SLICE-004`.
- Rejoin within the grace window (`Ring.rejoin` exists; wiring it is `SEAT-004`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-003` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/server/round/RoundView.luau` (source), `src/server/session/Session.luau` (source), `src/shared/Tuning.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Oracle partition as in `## Contract`. Every expected value is computed by the
M2 module that owns it; RED must not hand-copy a seat view.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.
- PLANNED → RED orchestration - `lead-po` - `claude-opus-5-5`. 2026-10-02.
- RED - `test-developer` - **unresolved**. It was dispatched with an explicit
  `model: fable`, as PROC-005 was, but the agent reported that "the dispatch
  carried no `model:` override" and that it ran on its definition's `opus`.
  The orchestrator cannot see which won. PROC-005's RED, given the same
  parameter, reported `fable`. Record this as a discrepancy, not as a
  measurement of either model. 2026-10-02.

## Test plan

Written in RED (2026-10-02, test-developer). One new module, so one real
suite that fails at `require` today, backed by a helper carrying the checks
and a controls suite that EXECUTES every check in RED against a reference
stand-in and against one-defect stand-ins - the house `*Contract` /
`*_controls_test` arrangement (`TurnRequestsContract`, PROC-005).

**Level.** Unit: `Session` is a pure composition root over pure modules, and
the contract lives in how it composes them. Every scenario is driven by
`Session.new` + `Session.step` over the real `PhaseMachine`, `Ring`,
`Projection`, `Rng` and `RoundConfig.fromTuning(Tuning)`. No Roblox, no real
time, no interpreter (SLICE-004's).

**The oracle is the M1/M2 modules, stepped independently.**
`SessionContract.run` drives a scripted plan through the session under test
and, beside it, through `PhaseMachine.step` directly - one machine step per
event, a second with `SeatsAssigned` when the first emitted `AssignSeats` -
and tracks the Contract's assignment itself: `Ring.assign(effect.players,
Rng.fromSeed(effect.seed))` on a deal, `Ring.withdraw` when the machine
unseats a seated player in Round, `nil` on entering Lobby, recipients =
remaining players whose `Projection.forPlayer` differs. No expected value is
read off the session's own output; a session whose round drifts from the
machine's is caught by its own check, and every other check compares against
the oracle's state.

**Oracle partition, honoured.** AC-1/2/3/5 mechanical as above - no ring,
view or effect list is hand-copied. AC-4 settled: `lobbySeconds`,
`roundSeconds`, `postRoundSeconds`, `playersMin`, `playersMax` are read
through `RoundConfig.fromTuning(Tuning)`; the helper's only numeric literals
are the plan's clock offsets (0.5, 1.5, 100.25, 10.5, +1, +2, +5, +6), which
the fixtures test asserts are fractional against the config's durations so
ceil and floor disagree. `PublicSeatView`'s key list and the RoundView's key
list are written in the helper because they ARE the Contract's.

**Two plans.** `lifecycle()`: `playersMax` players join (below min, at min,
to max), fractional ticks, a refused surplus join, a duplicate join, a
stranger's leave, an outside `SeatsAssigned`, DEAL 1, a fractional tick in
Round, an outside `SeatsAssigned`, an ignored rematch, a seated leave
(6 -> 5, quorum kept), the same leave again, a stranger's leave, the clock
ending the Round, a leave in Resolution, Resolution -> Post, a rematch in
Post, a leave in Post, a fractional tick in Post, Post -> Lobby, a seated
leave in the new Lobby, DEAL 2 (4 players, a different seed). `quorumDrop()`:
`playersMin` players, a deal, a leave that keeps quorum (4 -> 3), a leave that
drops below it (3 -> 2) and resolves the round in the same step.

| File | Level | Covers |
|---|---|---|
| `tests/helpers/SessionContract.luau` | 15 checks over a `Session` module; `run`, the two plans, `expectedRoundView`, `looksLikeSeatView` | Contract (6), AC-1 (2), AC-2 (1), AC-3 (4), AC-4 (2), AC-5 (1) |
| `tests/server/session_test.luau` | the real `src/server/session/Session.luau` | 15 tests, one per check (red) |
| `tests/server/session_controls_test.luau` | reference + 28 one-defect stand-ins + fixtures + instrument, run in RED | that every check fires on exactly its defect; the story's named controls and D-1..D-4's shapes |

Edges covered: 3, 4, 6 and 2 seated players; the leave that keeps quorum and
the one that drops it; a leave in each of Lobby (ring gone), Round,
Resolution, Post; stranger, duplicate and surplus events; fractional elapsed
times in all three timed phases; a Lobby both below and at `playersMin`; an
outside `SeatsAssigned` in Lobby, Round and a hand-built Assignment state.
Out of scope is not pinned: nothing touches `Ring.rejoin`, a facility, a
Procedure or a transport.

**Not observable from outside, so not pinned:** `secondsLeft == nil` in
`Assignment` (the session never returns an Assignment-phase state - the two
machine steps happen inside one `step`), and "the effect's `players`/`seed`
rather than `round.players`/`round.seed`" (equal on every path the machine
has). Both are stated in the Contract; neither has a test that could fail.

## Handoff: RED -> GREEN

Written 2026-10-02 by test-developer. The dispatch named no model override;
this agent's definition says `model: opus`, and the orchestrator records what
the dispatch resolved to.

### The command

    lune run test

There is no per-file filter in the runner; the whole suite is 859 tests
(`--list`), 48 of them this story's. The new tests are the lines matching
`session_`:

    lune run test 2>&1 | grep -E 'tests/server/session_|passed, '

For the loop, the ignored scratch runner `.claude/state/red/run.luau` runs
named files in ~2 s:

    lune run .claude/state/red/run.luau -- tests/server/session_test tests/server/session_controls_test

### The failure, verbatim

    859 tests                         (lune run test -- --list: 811 before this story + 15 real + 33 controls)
    844 passed, 15 failed             (lune run test, 2026-10-02, 7 m 25 s locally; exit 1)

All 15 failures are in `tests/server/session_test.luau`; the other 844 pass,
the 33 new control tests among them.

    FAIL  tests/server/session_test.luau :: AC-1: across two consecutive rounds (Round -> Resolution -> Post -> Lobby -> deal) the AssignSeats seeds differ and each deal equals Ring.assign from ITS OWN effect's seed - a fixed-seed session fails
          ...tests\server\session_test:40: src/server/session/Session.luau did not load: error requiring module "../../src/server/session/Session": could not resolve child component "session"
    FAIL  tests/server/session_test.luau :: AC-1: with players_min joined and the lobby timer elapsed, one Tick reaches Round and state.assignment deep-equals Ring.assign(effect.players, Rng.fromSeed(effect.seed)) for the AssignSeats effect PhaseMachine.step emits
          (same message)
    FAIL  tests/server/session_test.luau :: AC-2: on each dealing step there is exactly one SendTo/SeatView per seated player, addressed to them, payload deep-equal to Projection.forPlayer(assignment, p), nobody else addressed, and no Broadcast on any step carries a seat view by kind or by shape
    FAIL  tests/server/session_test.luau :: AC-3 (Contract): the step that enters Lobby clears state.assignment to nil, and a seated player's leave in that Lobby sends no SeatView and leaves it nil
    FAIL  tests/server/session_test.luau :: AC-3: a leave in Resolution or Post, a stranger's leave, a duplicate leave and every other step that unseats nobody send no SendTo at all and leave state.assignment deep-equal to what it was
    FAIL  tests/server/session_test.luau :: AC-3: when a seated player leaves a six-player Round (quorum kept), state.assignment deep-equals Ring.withdraw(old, leaver) and a SeatView goes to exactly the remaining players whose Projection.forPlayer view changed, in new seat order, and never to the leaver
    FAIL  tests/server/session_test.luau :: AC-3: with players_min seated, a leave that keeps quorum and then one that drops below it (resolving the round in the same step) both withdraw the leaver and send views to the remaining players
    FAIL  tests/server/session_test.luau :: AC-4: every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax } by pairs; secondsLeft = ceil(RoundConfig duration - elapsed) in Lobby (at/above playersMin), Round and Post - 0.5 s in rounds UP, the dealing step says roundSeconds - and nil in Resolution and a short Lobby
    FAIL  tests/server/session_test.luau :: AC-4: exactly one Broadcast/RoundView on every step whose phase or #players changed and on every Tick ending in Lobby, Round or Post; none on a refused join, a stranger's leave, an ignored event, a rematch or a leave in Post
    FAIL  tests/server/session_test.luau :: AC-5: on every step the non-SendTo, non-Broadcast effects deep-equal PhaseMachine.step's own effects on the same inputs minus AssignSeats, in order (Emit on join/leave/round end/rematch, ComputeTrace on Resolution -> Post, PromptRematch on Post -> Lobby), and AssignSeats never appears
    FAIL  tests/server/session_test.luau :: Contract: Session.new(config, seed, roundId, sessionId) holds exactly PhaseMachine.initial on the same arguments, with assignment nil
    FAIL  tests/server/session_test.luau :: Contract: a SeatsAssigned event from outside (in Lobby, in Round, and on a hand-built Assignment-phase state) and every step the machine ignores return the same state with {} effects
    FAIL  tests/server/session_test.luau :: Contract: after every step of a two-round lifecycle and a quorum drop, state.round deep-equals PhaseMachine.step on the same inputs (both machine steps on a deal)
    FAIL  tests/server/session_test.luau :: Contract: step mutates neither its state nor its event - deep snapshots taken before each step deep-equal the arguments afterwards
    FAIL  tests/server/session_test.luau :: Contract: within a step the effects are ordered pass-through first, then SendTo/SeatView in seat order, then at most one Broadcast last

**Why this is the right failure.** The module is new, so "the module does not
exist" is the first thing the story requires, and each of the 15 tests fails
on its own `assert(loaded, ...)` naming `src/server/session/Session.luau`
rather than as one LOAD FAIL for the file. Nothing else in the tree is red.

Because the real suite fails at `require`, **no assertion in it has run**.
Every check it calls is therefore executed in RED by the controls suite,
against a reference stand-in that must pass all 15 and 28 one-defect
stand-ins that must each fail exactly the set named. Those 33 control tests
pass today; the measured sets are in the table below.

### Files touched

| File | Status | Purpose |
|---|---|---|
| `tests/helpers/SessionContract.luau` | new | the 15 checks over a `Session` module, `run` (subject + oracle side by side), `lifecycle()` and `quorumDrop()` plans, `expectedRoundView`, `looksLikeSeatView`, `CHECKS`, `failures` |
| `tests/server/session_test.luau` | new | 15 tests on the real `Session` (red) |
| `tests/server/session_controls_test.luau` | new | 33 tests: reference + 2 fixtures + 1 instrument + 28 one-defect stand-ins + a missing-function control (green in RED) |
| `docs/backlog/stories/SLICE-003.md` | edited | `## Test plan`, this section |
| `.claude/tests/project-counters.test.sh` | edited (harness, RED-only by check 3j) | baselines set to the PREDICTED post-GREEN counts: `BASE_FORMAT`/`BASE_LINT` 137 -> 141, `BASE_TYPECHECK` 26 -> 27, `NARROW_FORMAT`/`NARROW_LINT` 26 -> 27, `NARROW_TYPECHECK` 8 unchanged; derivation in the file's header |

No source, config or manifest file was touched. No test dependency was
needed. `.claude/state/red/seeds.luau` (ignored scratch) measured the seed
choice below and is not part of the story.

One row per test, what it asserts, which AC:

| Test (short) | Asserts | AC |
|---|---|---|
| `Contract: Session.new ... holds exactly PhaseMachine.initial` | `state.round` deep-equals `PhaseMachine.initial(config, 20261002, "round-1", "session-A")`; `state.assignment == nil` | Contract |
| `Contract: after every step ... state.round deep-equals PhaseMachine.step` | over both plans, `after.round` deep-equals the oracle's round (two machine steps on a deal) | Contract |
| `AC-1: ... one Tick reaches Round and state.assignment deep-equals Ring.assign(...)` | DEAL 1 (6 players at `lobbySeconds`): phase `Round`; assignment deep-equals `Ring.assign(effect.players, Rng.fromSeed(effect.seed))` | AC-1 |
| `AC-1: across two consecutive rounds ...` | seeds differ (20261002 then 279127814, precondition); each deal equals its own effect's ring | AC-1 |
| `AC-2: on each dealing step ... exactly one SendTo/SeatView per seated player ...` | on both deals: per seated `p` exactly one SendTo with key set `{kind, payload, payloadKind, playerId}`, `payloadKind == "SeatView"`, payload deep-equal `Projection.forPlayer`; no SendTo to anyone else; on EVERY step no Broadcast with a non-`RoundView` kind or a payload containing any `PublicSeatView` key at depth <= 4 | AC-2 |
| `AC-3: when a seated player leaves a six-player Round ...` | assignment deep-equals `Ring.withdraw(old, "cat")`; SendTo set == remaining players whose view differs (5 of 5, printed), payload `forPlayer(new, p)`; none to `cat` | AC-3 |
| `AC-3: with players_min seated, a leave that keeps quorum and then one that drops below it ...` | both leaves withdraw and send to the remaining (3, then 2); second ends in Resolution (precondition) | AC-3 |
| `AC-3: a leave in Resolution or Post, a stranger's leave, a duplicate leave and every other step that unseats nobody ...` | on all 22 non-deal, non-withdraw, non-Lobby-entry steps: zero SendTo; `after.assignment` deep-equals the subject's own `before.assignment` | AC-3 |
| `AC-3 (Contract): the step that enters Lobby clears state.assignment ...` | `nil` after Post -> Lobby; the Lobby leave (unseats `fay`) sends nothing and keeps `nil` | AC-3 |
| `AC-4: exactly one Broadcast/RoundView on every step whose phase or #players changed and on every Tick ... none ...` | per step count == 1 iff oracle phase/count changed or (Tick and end phase in Lobby/Round/Post) else 0; 14 wanted, 11 silent | AC-4 |
| `AC-4: every RoundView is exactly { phase, secondsLeft, players, playersMin, playersMax } ...` | Broadcast key set `{kind, payload, payloadKind}`; payload key set by `pairs` == the five minus `secondsLeft` when nil; `secondsLeft == math.ceil(duration - (now - phaseEnteredAt))` from `RoundConfig` (Lobby only at/above `playersMin`), nil in Resolution/short Lobby; `players` deep-equals the round's and is not `rawequal` to it | AC-4 |
| `AC-5: on every step the non-SendTo, non-Broadcast effects deep-equal PhaseMachine.step's own effects ... minus AssignSeats` | over both plans, filtered effects deep-equal the oracle's pass-through list (content and order); no `AssignSeats` anywhere | AC-5 |
| `Contract: a SeatsAssigned event from outside ... and every step the machine ignores return the same state with {} effects` | outside `SeatsAssigned` in Lobby and Round, refused/duplicate join, stranger's leave, duplicate leave, rematch in Round: `after` deep-equals `before`, `#effects == 0`; a hand-built Assignment-phase state + `SeatsAssigned`: unchanged, `{}` | Contract |
| `Contract: within a step the effects are ordered pass-through first, then SendTo/SeatView in seat order, then at most one Broadcast last` | no pass-through after a SendTo; SendTos contiguous and their `playerId` sequence == `assignment.players` (deal) or the recipient list (withdraw); <= 1 Broadcast and it is last | Contract |
| `Contract: step mutates neither its state nor its event` | live input tables deep-equal their pre-step snapshots after the run | Contract |

### The export shape the tests already pin

Nothing below is a suggestion. Each name and signature is already imported or
called by a test, so getting it wrong is a red test rather than a debate.

    src/server/session/Session.luau              -- NEW, required as "../../src/server/session/Session"
      Session.new(config: RoundConfig.RoundConfig, seed: number, roundId: string, sessionId: string) -> SessionState
          -- { round = PhaseMachine.initial(config, seed, roundId, sessionId), assignment = nil }
      Session.step(state: SessionState, event: PhaseMachine.Event, now: number) -> (SessionState, { SessionEffect })
          -- state.round  : PhaseMachine.RoundState   (read by every check; config is read from it by the stand-ins,
          --                                            but the tests never pass a config to step)
          -- state.assignment : Ring.Assignment?       (deep-compared to Ring.assign / Ring.withdraw output; nil in Lobby)
          -- effects: ALWAYS a table ({} for nothing), never nil
      SendTo effect   : exactly { kind = "SendTo", playerId = <string>, payloadKind = "SeatView", payload = Projection.forPlayer(assignment, playerId) }
      Broadcast effect: exactly { kind = "Broadcast", payloadKind = "RoundView", payload = { phase, secondsLeft?, players (a COPY), playersMin, playersMax } }
      pass-through    : the PhaseMachine.Effect tables themselves (deep-equal; identity is not checked), AssignSeats removed
      -- order within a step: pass-through, then SendTo in assignment.players order (the new ring's on a withdrawal), then at most one Broadcast last

    Modules the tests import and do not change:
      src/server/round/PhaseMachine, src/server/round/RoundConfig, src/server/seats/Ring,
      src/server/seats/Projection, src/shared/Rng, src/shared/Tuning

**Not constrained** (the implementer's choice): how `Session` requires the
M1/M2 modules (`@shared/...` or relative); whether `SessionState` carries
extra keys (only `round` and `assignment` are read); whether `RoundView` is
built inline or by a local function; the wording of any `error`; whether
the ignored-event path returns the input table itself or an equal copy (only
deep-equality is checked); where the types are declared; the Lua-level
identity of pass-through effects. The `SeatsAssigned` early return is
observable only through the hand-built Assignment-phase state - the scripted
cases in Lobby and Round are ignored by the machine anyway.

### Tests that passed on arrival

The 33 tests in `session_controls_test.luau` are green in RED by design: they
run the checks against stand-ins, not the missing module. Each is earned by
the reference/one-defect structure - the reference passes all 15 checks and
every defect fires an exactly pinned set, measured and printed as
`[measured]` lines. None of the 15 real-suite tests passed on arrival.

### Negative controls: expected and measured in RED

Measured by the scratch runner and by `lune run test` on 2026-10-02 (local;
no test here is timing-bound). "Fires" is the exact set of checks that
raised; one more or one fewer is a failure in the controls file. Where my
prediction was wrong the row says so and the file carries the measured set
with the reason.

| Control (one edit to the reference) | Expected to fire | Measured in RED |
|---|---|---|
| reference | nothing | 0 of 15 |
| `fixedSeed` (AC-1's named control; D-2's shape, `Rng.fromSeed(0)`) | deal, two-rounds, own-view, withdraw, quorum | as expected |
| `reusesTheFirstSeed` (D-2's subtler shape: every round from the initial seed) | predicted two-rounds only | **two-rounds, own-view** - the own-view check runs on both deals and deal 2's ring is wrong; the single-deal check passes, as the control is for |
| `skipsSeatsAssigned` (stays in Assignment) | "the checks that need a Round" | 11 of 15: all but new, ignores, no-withdraw, purity |
| `broadcastsAllSeatViews` (AC-2's named control) | own-view | own-view, **order** (two Broadcasts) |
| `sendsEveryViewToFirstPlayer` (D-1's shape) | own-view, withdraw, quorum, order | as expected |
| `sendsTheAssignment` (payload is the whole ring, sigma included) | own-view, withdraw, quorum | as expected (after widening the defect to withdrawals too) |
| `sendsTheSuppliersView` | own-view | own-view |
| `resendsViewsOnEveryTick` | no-withdraw | no-withdraw |
| `sendsToTheLeaver` (AC-3's named control; D-4's shape) | withdraw, quorum, order | as expected |
| `skipsWithdraw` (AC-3's named control; stale views) | withdraw, quorum | as expected |
| `withdrawsInPostToo` | predicted no-withdraw | **no-withdraw, order** - the order check compares addressees to the oracle's recipient list, empty where nobody was unseated |
| `keepsTheRingInLobby` | predicted clears, no-withdraw | **clears, no-withdraw, order** - same reason, on the Lobby leave |
| `sendsOnlyToTheSupplier` | withdraw, quorum, order | as expected |
| `broadcastsOnEveryStep` | when, ignores | as expected |
| `noRoundViewOnTicks` | when | when |
| `floorsSecondsLeft` (D-3's first shape) | payload | payload |
| `roundTimedFromLobbySeconds` (D-3's second shape) | payload | payload |
| `secondsLeftInShortLobby` | payload | payload |
| `absoluteDeadline` | payload | payload |
| `aliasesPlayers` | payload | payload |
| `leaksSeedInRoundView` (extra key) | payload | payload |
| `dropsEmits` | pass-through | pass-through |
| `leaksAssignSeats` | predicted pass-through, order | **pass-through only** - the order check counts an unknown kind as pass-through, where it sits |
| `reversesPassThrough` | pass-through | pass-through |
| `acceptsOutsideSeatsAssigned` | ignores | ignores (on the hand-built Assignment state) |
| `roundViewFirst` | order | order |
| `mutatesState` | purity | purity (after the run record started snapshotting `after`; before that the live-table reads in four other checks fired too) |
| `mutatesEvent` | purity | purity |
| a module without `step` / without `new` | all 15, naming the function | 15 / 15 |

**Fixtures, measured through the reference:** the lifecycle deals twice with
seeds `20261002 -> 279127814` (6 then 4 players); on both deals the real ring
differs from `Rng.fromSeed(0)`'s and from `Rng.fromSeed(20261002)`'s. The
seed was CHOSEN for that: with 4 players there are only 6 rings and my first
pick, 7919, collided with seed 0 on deal 2 (`.claude/state/red/seeds.luau`
measured a dozen candidates). The quorum plan ends in Resolution and both
leaves have recipients == remaining (3 of 3, 2 of 2); the lifecycle's leave
has 5 of 5 (PO decision 2). `looksLikeSeatView` accepts a view, a list of
views, a nested map and a single key, and rejects a RoundView payload, a list
of ids and a string.

**Two defects were in my checks, found by the reference and fixed in RED:**
(1) a Tick that moves nothing in Lobby/Round/Post is a machine no-op the
Contract still answers with a RoundView, so the no-op tag excludes those;
(2) the no-withdraw check compared the ring to the oracle's, so a wrong deal
fired it on every step - it now compares to the subject's own previous ring,
leaving "is the ring right" to AC-1.

These numbers were measured against stand-ins and my own oracle.
**Confirming them against the shipped module is GREEN's job**: after GREEN
the 15 real tests must pass and the 33 control tests must still pass
unchanged.

### GREEN confirmation (2026-10-02, feature-developer)

Measured against the shipped `src/server/session/Session.luau`.

- **The real module against every check:** `SessionContract.failures(Session)`
  run directly (ignored scratch `.claude/state/red/green_failures.luau`)
  printed `real Session fails 0 of 15`. Matched: the reference's 0 of 15.
- **The controls suite**, re-run with the shipped module present: 33 of 33
  pass, and every `[measured]` fired set is identical to the table above -
  matched for all 29 rows: `reference` 0 of 15; `fixedSeed` {deal,
  two-rounds, own-view, withdraw, quorum}; `reusesTheFirstSeed` {two-rounds,
  own-view}; `skipsSeatsAssigned` the 11 (all but new, ignores, no-withdraw,
  purity); `broadcastsAllSeatViews` {own-view, order};
  `sendsEveryViewToFirstPlayer` {own-view, withdraw, quorum, order};
  `sendsTheAssignment` {own-view, withdraw, quorum}; `sendsTheSuppliersView`
  {own-view}; `resendsViewsOnEveryTick` {no-withdraw}; `sendsToTheLeaver`
  {withdraw, quorum, order}; `skipsWithdraw` {withdraw, quorum};
  `withdrawsInPostToo` {no-withdraw, order}; `keepsTheRingInLobby` {clears,
  no-withdraw, order}; `sendsOnlyToTheSupplier` {withdraw, quorum, order};
  `broadcastsOnEveryStep` {when, ignores}; `noRoundViewOnTicks` {when};
  `floorsSecondsLeft`, `roundTimedFromLobbySeconds`,
  `secondsLeftInShortLobby`, `absoluteDeadline`, `aliasesPlayers`,
  `leaksSeedInRoundView` {payload} each; `dropsEmits`, `leaksAssignSeats`,
  `reversesPassThrough` {pass-through} each; `acceptsOutsideSeatsAssigned`
  {ignores}; `roundViewFirst` {order}; `mutatesState`, `mutatesEvent`
  {purity} each; missing `step`/`new` 15/15.
- **Fixtures:** deals `20261002 -> 279127814`, 6 then 4 players, both rings
  differ from seed 0's and the first seed's; the lifecycle leave is 5 of 5
  views changed. Matched.
- **What this does and does not show.** The one-defect controls are edits of
  the helper's reference stand-in, not of the shipped module, so their fired
  sets cannot move with GREEN; their re-run confirms only that nothing
  regressed. The confirmation that is new in GREEN is the 0 of 15 above. The
  mutations of the shipped module itself are D-1..D-4, GATES' job.
- **Contract mechanisms against the real modules:** all held as written. The
  outside-`SeatsAssigned` early return precedes the machine step; the deal
  uses the effect's `players`/`seed`; withdrawal is gated on the machine
  having unseated the leaver; recipients are a field-by-field
  `PublicSeatView` diff in the new ring's order; the ring is cleared on
  entering `Lobby`. No divergence.

### Deferred verifications D-1..D-4: DECLINED in RED

I cannot run D-1, D-2, D-3 or D-4: each mutates a module that does not exist
in this phase. They are owned by GATES, as the story says. What RED did
instead is show the checks WOULD see each one: D-1 is
`sendsEveryViewToFirstPlayer` (fires own-view, both withdraw checks, order);
D-2 is `fixedSeed` (fires both AC-1 checks and three more) and
`reusesTheFirstSeed` (fires the two-round check); D-3 is `floorsSecondsLeft`
and `roundTimedFromLobbySeconds` (each fires exactly the AC-4 payload check,
on the fractional ticks and on the dealing step respectively); D-4 is
`sendsToTheLeaver` (fires both withdraw checks). On D-4's "either the step
raises or AC-3 fails": `SessionContract.run` turns a raise inside `step` into
a `Contract.fail` naming AC-3, so the real suite goes red either way. GATES
runs the real mutations with `bash scripts/mutate.sh` and pastes the red.

### Callers list, restated against the tree

`rg -n "src/server/session|Session\." src tests` returned nothing before
these tests were written (exit 1, 2026-10-02). After them the only hits are
the three new test files. `PhaseMachine`, `Ring`, `Projection`, `Rng` and
`RoundConfig` keep their signatures; the tests call them exactly as the
existing suites do. No `src/server/session/` exists.

### Contract pins, checked against the real modules

Every pin held: a reference built to the Contract's text passes all 15
checks against the independently stepped oracle. Nothing in `## Contract` was
amended. Two observations for the implementer, neither a contradiction:

- "A step that is a pure no-op emits nothing" and "a Tick whose end phase is
  Lobby, Round or Post emits a RoundView" meet on a Tick that moves nothing:
  the machine returns its input and `{}`, and the session still emits one
  RoundView. The RoundView bullet is the one that applies; the tests pin it.
- `Ring.withdraw` on a 3-ring returns a well-formed 2-ring and
  `Projection.forPlayer` projects it, so the below-quorum leave sends two
  SeatViews for a round that has already resolved. That is what the Contract
  says ("including the leave that drops the round below quorum"); the tests
  pin it.

### Notes for the implementer

- The hand-built Assignment-state case means the `SeatsAssigned` early return
  has to come BEFORE the phase-machine step, not after: forwarding it to the
  machine in Assignment moves to Round with no ring.
- `RoundView.players` must be a fresh copy - `table.clone(round.players)` is
  fine here (this is not `Projection`, whose on-disk guard bans copy helpers).
- The withdraw rule reads the machine's before/after `players`: leaver in the
  old list and not in the new one, and `assignment ~= nil`. A leave in
  Resolution or Post leaves the player seated, so no withdrawal.
- Build the recipient list as a diff over `Projection.forPlayer` old vs new,
  in the new ring's order (`Deep.equal` is a test helper; GREEN writes its own
  comparison or compares field by field). Today the diff is every remaining
  player; the tests assert the diff, so "send to all remaining" also passes
  today - PO decision 2 says the diff is still the rule to build.
- Timings: the three new files run in ~2 s together through the scratch
  runner; no test here owns a timeout or a sweep.

### `bash scripts/gates.sh --fast` at the end of RED (2026-10-02, local)

    PASS         format (1s, observed 140)
    PASS         lint (2s, observed 140, floor 1)
    PASS         typecheck (5s, observed 26)
    FAIL         unit (303s, exit 1) -> .claude/state/gate-logs/unit.log      844 passed, 15 failed
    UNCONFIGURED coverage
    PASS         build (3s, observed 93179)
    FAIL         harness (52s, exit 1) -> .claude/state/gate-logs/harness.log  project-counters: 28 passed, 12 failed
    --fast skipped: integration mutation
    2 required gate(s) failed.

The shape is the one RED wants: format, lint, typecheck and build green;
`unit` red with exactly the 15 real-suite assertions above and nothing else
(the floor 507 is far below the observed 844). `harness` is red for the
documented RED reason, in two parts, and GREEN must not touch it:

1. **The "no stray .luau files" precondition** fails while the three new test
   files are untracked. It clears at the RED commit. **The orchestrator must
   make a `phase: RED` commit carrying the three test files, the story and
   `.claude/tests/project-counters.test.sh` before setting GREEN** -
   `check-boundaries.sh` 3j refuses a `.claude/tests/**` change in any
   commit whose story says GREEN or later. I did not commit: the brief said
   the orchestrator would.
2. **AC-7's counts** read `expected 141 / actual 140` (format, lint),
   `expected 27 / actual 26` (typecheck over `src`, and both narrow `src`
   counts), `142 / 141` and `28 / 27` for the untracked-file cases: every
   count is exactly 1 short, which is `src/server/session/Session.luau`. The
   baselines are the predicted post-GREEN values, as the counters file's
   header prescribes; GREEN confirms them by writing exactly that one module
   and nothing else under `src/`. A second source file, or a module placed
   under `src/shared/` (which would move `NARROW_TYPECHECK`), is a counter
   failure GREEN cannot fix - it would be a return to RED.

Timings above are from this machine; `project.conf` carries no `ci-factor`
for `unit`, and nothing in this story's tests is timing-bound (no sweeps, no
sleeps, no timeouts - the three files run in ~2 s together).

**Floor.** `floor | unit | 507` is not raised here: the counters file is the
RED-only edit this story makes, and `project.conf` is the Lead PO's. The
measured post-RED count is 844 passing; GREEN's full run should read 859.

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

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-10-02T21:09:47Z
    commit: ca8d53a
    tree:   5c47b6385f097a455522700e0b22ea8c741ed73c
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 141)
    PASS         lint (1s, observed 141, floor 1)
    PASS         typecheck (4s, observed 27)
    PASS         unit (223s, observed 859, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 97283)
    PASS         harness (64s, observed 40)
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


**PO decisions (PLANNED → RED, 2026-10-02, lead-po).**

1. **The required gate is `unit`.** It covers `src/server/**`, which includes
   `src/server/session/`. No optional gate is involved, so `required_gates`
   stays empty.
2. **AC-3's "no one whose view is unchanged" is pinned as a diff rule.**
   `PublicSeatView.seatOrder` is public and shrinks on every withdrawal, so with
   the real `Ring` and `Projection` every remaining player's view changes, and
   the recipients are exactly the remaining players. The rule GREEN builds is
   still the diff, not "send to everyone": the leaver is the only no-send case
   real data can exhibit, and a stand-in that also sends to the leaver must
   fail. A later story that makes some view stable under a withdrawal would
   exercise the other half. The criterion's text is unchanged.
3. **The assignment is cleared on re-entering `Lobby`,** and a withdrawal
   happens only when the phase machine actually unseated the leaver, which
   today means a leave in `Round` only. The AC does not say either; both are
   pinned in `## Contract` so that a stale ring cannot produce seat views in
   the next lobby.
4. **`RoundResolved` is forwarded unchanged** for now. The contract comment
   lists four event kinds, but the alias is `PhaseMachine.Event`, and making
   `RoundResolved` internal belongs to `SLICE-005`, which produces it from the
   Procedure.
5. **Epic done-when check.** EPIC-03 done-when 4 is exactly this story's AC-1,
   AC-2 and AC-4. Clauses 1 to 3 are `SLICE-001` and `SLICE-002`, clause 5 is
   `THEME-001`, and clauses 6 and 7 are `SLICE-004` and `HUD-007`, all still
   ahead. Nothing promised falls between finished stories and this one.
6. **Counter baselines.** GREEN adds exactly one source file,
   `src/server/session/Session.luau`, outside `src/shared/`. RED moves
   `.claude/tests/project-counters.test.sh` to the predicted post-GREEN counts
   and commits it in a `phase: RED` commit, because check-boundaries 3j freezes
   `.claude/tests/**` outside RED.

**RED verified (2026-10-02, lead-po).**

- The orchestrator read `tests/helpers/SessionContract.luau`'s `run`. Its
  oracle replays every step through `PhaseMachine.step` (twice on a deal),
  `Ring.assign(effect.players, Rng.fromSeed(effect.seed))`, `Ring.withdraw` and
  `Projection.forPlayer`, and reads no expected value off the subject.
- `lune run test`: `844 passed, 15 failed`. All 15 are
  `tests/server/session_test.luau`, each failing with `did not load: error
  requiring module "../../src/server/session/Session": could not resolve child
  component "session"`.
- `bash scripts/gates.sh --fast` after the RED commit `068ae60`:
  - format, lint, typecheck and build pass (140 / 140 / 26);
  - unit fails on the 15 above;
  - harness fails `28 passed, 12 failed`, and every count failure is exactly one
    short of the predicted baseline (for example `expected count: 141` against
    `stylua over 140 files`), which is the one module GREEN writes.

**GREEN (2026-10-02, lead-po).**

- Freeze: snapshot taken right after `phase.sh set SLICE-003 GREEN`, over the
  three test files and `.claude/tests/project-counters.test.sh`. Before leaving
  GREEN: `frozen: OK — 4 path(s) unchanged since the snapshot for SLICE-003`.
- The orchestrator read `src/server/session/Session.luau` against every
  `## Contract` pin and found no divergence.
  - `sameView` compares the six `PublicSeatView` fields explicitly. A story that
    widens `PublicSeatView` must widen it too, or AC-3's diff goes silently
    stale; VIEW-003 is the likely one.
- Model: `feature-developer` dispatched with `model: opus`, and it reported
  `claude-opus-5-5`. 2026-10-02.

**GATES (2026-10-02, lead-po).**

- Freeze: snapshot retaken right after `phase.sh set SLICE-003 GATES` (the same
  four paths). After D-1 to D-4 and the full run:
  `frozen: OK — 4 path(s) unchanged since the snapshot for SLICE-003`.
- Deferred verifications D-1 to D-4 all hold. Their results are pasted under
  each block, and each mutation went through `scripts/mutate.sh` with a
  verified restore.
- Full `bash scripts/gates.sh` passed: 6 ran, 0 failed, 3 unconfigured, and
  `## Gate results` was written by the script. No source change was needed in
  GATES. This story adds or changes no gate, so `## Gate probes` does not apply.
- Local timing: unit took 223 s and harness 64 s. Both are slower than the
  PROC-005 runs on this machine (126 s and 16 s), and the 48 new tests do not
  account for the difference. Compare against CI at REVIEW.
