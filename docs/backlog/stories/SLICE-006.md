---
id: SLICE-006
title: The session carries pings, presets and every view, and a scripted round is won by showing
slug: the-session-carries-pings-presets-and-ev
epic: EPIC-08
type: feature
status: in-review
phase: REVIEW
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
- **AC-4** — Given a `PresetSent` whose filter result succeeded, when the step
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

## Amendments

**AC-4, 2026-10-06, in PLANNED (Lead PO, PO-3).** It said: *"Given a `PresetSent`
with a succeeding filter port, when the step returns, ..."* It now says: *"Given a
`PresetSent` whose filter result succeeded, when the step returns, ..."*; nothing
else in the criterion changed. **Why:** `CHAN-001` established that both Roblox
filter calls yield, so the filter cannot be a port of the pure `Session.step`. The
driver calls it and the event carries its answer (C-5). The old words named a
mechanism that no longer exists; what the criterion requires (a broadcast at the
stored position on success, a sender-only `PresetFailed` on failure) is unchanged.
**Approved by:** Lead PO, before the story left PLANNED. It was not put to the
user. The PO-3 note's claim that "no `## Amendments` entry is due" was wrong:
`check-boundaries.sh` compares against the base branch whatever the phase of the
edit, and refused this commit until this entry existed.

## Contract

`src/server/session/Session.luau`, extended. Every block below was pinned by
`lead-po` at PLANNED -> RED (2026-10-06) against the tree at `eb21397`. **RED may
amend a block in place, with a one-line reason under it; GREEN builds what the
amended block says.**

**C-1. Types.**

    export type SessionPorts = { lineOfSight: (from: Procedure.Vec, to: Procedure.Vec) -> boolean }

    export type FilterResult = { ok: true, text: string } | { ok: false }

    export type ChannelState = { presets: PresetSends.PresetState, pings: Pings.PingState }

    export type Sent = {                       -- the last value sent to each audience
        roundView: RoundView.RoundView?,
        lens: { [string]: Projection.LensView },
        cues: { [string]: Projection.TurnCues },
    }

    SessionState gains:  channel: ChannelState, sent: Sent, ports: SessionPorts
    SessionEvent gains:
        | { kind: "PresetSent",    playerId: string, presetId: number,
            filtered: FilterResult, call: PresetSends.CallControl }
        | { kind: "PingRequested", playerId: string, target: Pings.PingTarget,
            call: Pings.CallControl }
    SessionEffect gains:
        | { kind: "SendTo",    playerId: string, payloadKind: "LensView",     payload: Projection.LensView }
        | { kind: "SendTo",    playerId: string, payloadKind: "TurnCues",     payload: Projection.TurnCues }
        | { kind: "SendTo",    playerId: string, payloadKind: "PingRefused",  payload: Pings.PingRefused }
        | { kind: "SendTo",    playerId: string, payloadKind: "PresetFailed", payload: PresetSends.PresetFailed }
        | { kind: "Broadcast", payloadKind: "PresetShown",  payload: PresetSends.PresetShown }
        | { kind: "Broadcast", payloadKind: "FacilityView", payload: RoundView.FacilityView }

**C-2. CHANGED signature (PO-1).**

    Session.new(config, seed, roundId, sessionId, ports: SessionPorts, options: SessionOptions?) -> SessionState

`ports` is **required**: `Session.new` raises when `ports` is not a table or
`ports.lineOfSight` is not a function. There is no default: a defaulted
always-true sight would let a lens read through walls the day a caller forgets
it. `options` (`tuning`, `generatorPredicate`) moves from 5th to 6th, unchanged.
The initial state holds `channel = { presets = PresetSends.new(), pings = Pings.new() }`,
`sent = { roundView = nil, lens = {}, cues = {} }` and `ports` as given.

**Callers of the changed signature** (`rg -n "S\.new|Session\.new" src tests`,
2026-10-06, at `eb21397`). There are **no source callers**: the earlier mention of
`RoundService.server.luau` was wrong - that file does not exist yet; `SLICE-007`
creates it. Every test caller is updated in this RED and named in `## Test plan`,
and RED's handoff must state that it re-ran this `rg` against the tree and found no
others:

| File | Line(s) | What |
|---|---|---|
| `tests/helpers/ScriptedRound.luau` | 147, 149 | `S.new(config, seed, ..., options)` - options moves to 6th |
| `tests/helpers/SessionContract.luau` | 17 (doc), 261, 547 | `pcall(S.new, ...)` with 4 args |
| `tests/helpers/SessionRoundContract.luau` | 566, 968-1012 | `pcall(S.new, ...)`; the "fifth options argument" check |
| `tests/helpers/PositionsContract.luau` | 1144 | `S.new(ScriptedRound.config(), 108, "r", "s")` |
| `tests/helpers/SessionRoundStubs.luau` | 107 | stub `S.new` (controls) |
| `tests/server/session_controls_test.luau` | 88 | stub `S.new` (controls) |
| `tests/server/session_test.luau` | 47 | test name pins the 4-arg form |
| `tests/server/session_round_test.luau` | 45 | test name: "accepts an optional fifth options argument" |

**C-3. Superseded behaviour of DONE stories (PO-2).** These existing assertions
contradict AC-1 or `architecture.md` §9.7 and are amended in this RED, each named in
`## Test plan` with the old and new wording - narrowed only as far as the new
effects require, never deleted:

- `SessionRoundContract.luau` ~1476-1559 and `session_round_test.luau:77`
  (SLICE-005 C-3 as rewritten by VIEW-004): "the only effect a `PositionsSampled`
  may emit is `Placed`". It now may also emit the `LensView` sends and the
  `RoundView` broadcast of C-6, and nothing else.
- `PositionsContract.luau` `expectNoEffects` call sites: the same, where the step is
  in `Round` and a lens can change. Where none can, the assertion stands.
- `SessionContract.luau` ~1071-1101 / `session_test.luau:91` (SLICE-003 AC-4): the
  "every Tick in a timed phase" half **stands unchanged** (C-6); "none otherwise"
  becomes "none otherwise unless the view differs from the last one sent". Every
  case that test names (refused join, stranger's leave, ignored event, rematch,
  leave in `Post`) leaves the view unchanged, so RED should expect those cases to
  pass unedited - if one does not, that is a finding to report, not to absorb.
- Any further assertion RED finds that pins an exact effect list or an exact
  `SessionState` key set on a path this story extends. RED lists each in the
  handoff.

**C-4. Pings.** `PingRequested` in **any** phase:
`Pings.request(if phase == "Round" then state.procedure else nil, state.positions,
playerId, target, call, state.ports.lineOfSight)`.
- Refused: one `SendTo` `PingRefused` to `playerId` with the returned value
  (`call` already declined by `Pings.request`, exactly once). No other effect from
  the ping. Outside `Round` this is always `no_such_target`.
- Accepted: `channel.pings = Pings.accept(pings, playerId, target,
  Pings.targetPosition(procedure, target), now, roomLit)` where `roomLit` is
  `not Procedure.isDark(procedure, room)` for a setting or machine target's
  machine room, and `true` for a doorway. No `SendTo`.
- Every `Tick`, in every phase: `channel.pings = Pings.tick(pings, now, tuning)`,
  before the views are built.
- Every machine whose `procedure.committed[id]` became `true` in this step (from a
  turn or a tick): `channel.pings = Pings.onCommitted(pings, id)`.
- `RoundView.public` gets `pings = Pings.shown(channel.pings)` in `Round`, `{}`
  in every other phase.

**C-5. Presets (PO-3, from `CHAN-001`).** The filter yields in production
(`TextService:FilterStringAsync` and `GetNonChatStringForBroadcastAsync`, §9.5.1),
so it is **not** a port: the driver calls it before building the event and puts the
answer in `filtered`. `Session` hands `PresetSends.send` a non-yielding filter that
returns `(filtered.ok, filtered.text)`, so `PresetSends`' own order - phase first,
filter second, fail closed - is unchanged and still its own. Then
`PresetSends.send(channel.presets, playerId, presetId, round.phase,
state.positions[playerId], now, thatFilter, call)`.
- `shown`: one `Broadcast` `PresetShown` with the returned payload. Its `position`
  is the sender's **stored** (accepted) position, copied.
- `failed`: one `SendTo` `PresetFailed` to `playerId` only.
- **No stored position (PO-4):** `call.decline()` once, state unchanged, **no
  effect**. `PresetSends.send` is not called (its `position` is not optional).
  In production the driver samples every character each step, so this is the
  window before a player's first sample.

**C-6. Views and change detection.** At the end of **every** step, including
`PositionsSampled` (which no longer returns early):
- **Private views**, only when the end state is `Round` with a procedure and an
  assignment, for each player in `assignment.players` in seat order:
  `Projection.lensFor(assignment, procedure, p, positions[p], ports.lineOfSight)`
  then `Projection.turnCuesFor(assignment, procedure, p)`. Each is sent as its own
  `SendTo` to `p` alone **iff** it is not deep-equal to `sent.lens[p]` /
  `sent.cues[p]`; an absent entry is never equal, so the first view of a round is
  always sent, even an empty one. `sent` records exactly what was sent.
- On the step that **deals** (entry into `Round`), `sent.lens` and `sent.cues`
  are reset to `{}` before this comparison. On entering `Lobby` they are reset with
  the ring. A player no longer in `assignment.players` loses their entries and is
  never sent another.
- **`RoundView`**: one `Broadcast` when the existing trigger fires - the phase or
  `#players` changed, or the event is a `Tick` ending in `Lobby`, `Round` or
  `Post` (SLICE-003 AC-4, unchanged: it is the "at least once a second" half of
  §9.7, since the driver ticks once a second) - **or** the built view is not
  deep-equal to `sent.roundView`. Never more than one per step. `sent.roundView`
  records it.
  *Amended in RED (test-developer, 2026-10-07):* that deep-equal comparison
  **ignores `secondsLeft`** - compare the built view and `sent.roundView` with
  that key removed from both; `sent.roundView` still records the whole view.
  Reason: `secondsLeft` moves with `now` on every non-Tick step, so a strict
  comparison broadcasts a RoundView on every ignored event, duplicate leave,
  rematch, refused sample and turn outside Round that arrives at a later `now`;
  measured against the reference stand-in with a strict `Deep.equal`, six
  DONE-story checks that C-3 says must pass unedited fail (SLICE-003
  `broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration` and
  `ignoresASeatsAssignedEventFromOutsideAndEveryNoOp`, SLICE-005
  `handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone` and
  `ignoresATurnOutsideRoundOrWithoutAProcedure`, VIEW-004
  `resyncPlacesBackInRoundOnly`). The per-second Tick already carries the clock.
  *RED note, not an amendment:* the reset of `sent.lens`/`sent.cues` on the deal
  is unobservable from outside - nothing enters them between the Lobby reset and
  the next deal, since private views are built only in `Round` - so the tests pin
  the Lobby reset (`state.sent` in the next Lobby) and the second deal's full
  send; implement the deal reset or not, the tests cannot tell.
- No `Broadcast` ever carries a `LensView` or a `TurnCues`.

**C-7. `FacilityView`.** On the dealing step, when generation **succeeds**: one
`Broadcast` `FacilityView` of `RoundView.facility(facility)`. Never on any other
step; never when generation failed.

**C-8. Channel lifetime.** `channel` is reset to `{ presets = PresetSends.new(),
pings = Pings.new() }` on entering `Lobby`, with the ring. It is **kept** through
`Resolution` and `Post`, so both logs are there for the trace (EPIC-09).

**C-9. Effect order within one step.** Fixed, each group in the order given:
1. the machine's pass-through effects, as today;
2. `Placed`, in seat order (dealing) or ascending `playerId` (resync), as today;
3. `SendTo` `SeatView`s, as today;
4. the `Broadcast` `FacilityView` (C-7);
5. the reply to the caller: `TurnResult`, `PingRefused` or `PresetFailed`;
6. the `Broadcast` `PresetShown`;
7. per player in seat order: their `LensView` then their `TurnCues`, each only if
   changed;
8. at most one `Broadcast` `RoundView`, last.

**C-10. The AC-2 script - the oracle - and its rules.** A new script in
`tests/helpers/` (RED names it), built on `ScriptedRound`'s driver (`walk`,
`tick`, `turn`, `step`). Its **players** decide from an **inbox per player** built
only from effects: the `SendTo`s addressed to that player and every `Broadcast`.
A decision function never receives `d.state`, `facility`, `procedure`,
`assignment` or a `requiredSetting`. What each may read:

| Role | May read | Never |
|---|---|---|
| everyone | its own `SeatView` (`lensClass`, `supplierId`, `dependentId`), the `FacilityView`, the latest `RoundView`, its own position (the script moved it), the tuning, and `Machines.positionOf` applied to `FacilityView` rooms and slots | anything in `state` |
| helper `q` | its own latest `LensView` | another player's `LensView` |
| turner `t` | its own `TurnCues`; `PingShown` entries **from `t`'s `supplierId`** in the latest `RoundView` | any setting not in such a `PingShown` |

- A helper walks to a live, uncommitted machine of its `lensClass` (from
  `FacilityView` and `RoundView`), and pings `{ kind = "setting", target = id,
  setting = s }` only for a reading `{ machineId = id, setting = s }` in its own
  latest `LensView`. No reading, no ping.
- A turner turns machine `m` to `s` only when its supplier's `PingShown` names
  `m` and `s`. No ping, no turn - it never guesses.
- The finale's two turners turn at the same `now`, as `ScriptedRound` does today.
- The outcome is read from `state.round` **by the test**, never by a player.
- The sight port in the script is a constant `true` (no geometry headlessly); the
  handoff names it as such.

So a broken lens, a broken ping or broken routing leaves the script **unable to
act**, and the round ends `lost / clock`; nothing in the script can cheat its way
to a win. The `ScriptedRound` header's "may read the secret" stays true of the
SLICE-005 scripts and must be stated as **not** true of this one.

**Oracle partition.**
- **Mechanical, exact pinning:** AC-1, AC-3, AC-4, AC-5, AC-6, C-2, C-9.
- **Settled with a control:** AC-2. The oracle is C-10's rules. Control: the same
  script with the helper's ping suppressed must end `lost / clock` on every seed
  it runs (RED picks a seed count small enough for the clock-out cost, at least
  3 per n, and records it).
- AC-6 is checked **per payload kind**, from an allowlist: a `LensView` reading
  for `p` must be of a machine whose `keyClass` is `λ(p)` (read from the state by
  the *test*, not by a player); every other private kind (`SeatView`,
  `TurnCues`, `TurnResult`, `PingRefused`, `PresetFailed`) must have no field
  carrying a required setting; a `SendTo` of a kind not on the allowlist fails.
  Do **not** search payloads for a number equal to some required setting -
  settings are small integers and that needle matches everywhere.

## Deferred verifications

**D-1. AC-2 depends on the ping.** Use `scripts/mutate.sh` to make `Pings.shown`
return an empty list. AC-2 **must** then fail. RED cannot run this. Owner:
GATES.

**D-2. AC-2 depends on the lens.** Use `scripts/mutate.sh` to make `lensFor`
return the dependent's class (the direction error). AC-2 **must** then fail,
and AC-6 **must** fail. Owner: GATES.

**D-3. AC-1's "a player whose view did not change receives nothing" depends on
the diff.** Use `scripts/mutate.sh` on `Session.luau` to make the lens comparison
always report "changed" (send every lens on every step). AC-1's no-change
assertion **must** then fail, and the AC-2 win must still pass (the diff is a
bandwidth rule, not a correctness one - if AC-2 fails here, the script is reading
"a lens arrived" as a signal, which C-10 does not allow). RED cannot run this.
Owner: GATES.


**Results (lead-po, GATES, 2026-10-07)**, each run through `scripts/mutate.sh` against
commit `6c4ba26`, with `lune run test` and the file restored byte-for-byte after each
run:

- **D-1: PASSED.** Mutation: `s/^\t\ttable.insert(shown, entry)$/\t\tlocal _ = entry/` in
  `src/server/channel/Pings.luau`, so `Pings.shown` always returns `{}`.
  Result: `1314 passed, 30 failed`; `restored (verified byte-for-byte ...)`.
  In `session_channel_test` exactly the three RED predicted went red: **AC-2**,
  AC-3 (accepted ping shown) and C-9. The other 27:
  - 2 in `ping_lifecycle_test` (CHAN-006's own `shown` tests);
  - 25 in `session_channel_controls_test`, whose reference stand-in calls the real
    `Pings.shown`. Its baseline therefore no longer wins, and every control that
    compares against that baseline fails with it.
- **D-2: PASSED.** Mutation: `s/local lensClass = Ring.lensOf(assignment, playerId)/local
  lensClass = assignment.keyClasses[playerId][1]/` in
  `src/server/seats/Projection.luau`, so the lens reads the player's own key class
  (the direction error). Result: `1316 passed, 28 failed`; restored byte-for-byte.
  **AC-2 failed and AC-6 failed**, which is what the block requires. The rest:
  - 5 in `lens_view_test` (VIEW-001's own tests);
  - 20 in the controls file, which shares the real `lensFor`.

  **The prediction differed in one test.** RED predicted AC-1, AC-6 and AC-2. The
  real red set was AC-2, AC-6 and AC-3 (accepted ping shown); AC-1 stayed green.
  Why: AC-1's oracle calls the real `Projection.lensFor` on the end state, so it
  agrees with any lensFor, mutated or not. AC-1 pins the routing of lens views,
  not their content, and AC-6 is the test that pins content. RED's stand-in
  modelled D-2 inside the session rather than in `lensFor`, so it made AC-1
  disagree. AC-3's accepted-ping case fails because its helper is placed by the
  lens the test expects. The criterion's condition holds; only the predicted
  spread was wrong.
- **D-3: PASSED.** Mutation: `s/if not deepEqual(lensView, lastLens\[playerId\]) then/if
  true then/` in `src/server/session/Session.luau`, so every lens is sent on every
  step. Result: `1332 passed, 12 failed`; restored byte-for-byte. **AC-1 failed,
  and AC-2 and AC-6 both passed**, as the block requires: the diff is a bandwidth
  rule, and the script does not read "a lens arrived" as a signal. The red set
  matches RED's prediction exactly:
  - 5 in `session_channel_test` (AC-1, AC-3 ×2, AC-4, C-9);
  - 5 in `session_positions_test`;
  - 2 in `session_test`.

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

Lock coverage: SUPPRESSED by `src/server/session/Session.luau` (source), `tests/helpers/PositionsContract.luau` (test), `tests/helpers/ScriptedRound.luau` (test) (+6 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- *lead-po correction (2026-10-07):* the first RED dispatch was sent with
  `model: fable` explicitly, but the session ended before it reported back, so its
  **resolved** model is **unrecorded**; only the second is known to be Fable 5.1.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1, from the session's own
  model identification). Two dispatches: the first wrote the tests and was cut off
  before the handoff; the second (this one, 2026-10-07) reviewed them, wrote the
  controls file, amended C-6 and wrote the handoff. Neither dispatch message
  stated an override; the planned row is `fable`, so the plan and the resolution
  agree.
- GREEN - `feature-developer` - `claude-opus-5-5` (Opus 5.5, from the session's own
  model identification). 2026-10-07. The dispatch message stated no model
  override; the planned row is `opus`, so the plan and the resolution agree.
- GATES - no dispatch: no gate failed, so the `feature-developer` row was not
  needed. `lead-po` (`claude-opus-5-5`) ran D-1 to D-3 and `gates.sh`. 2026-10-07.
- REVIEW - `lead-po` - `claude-opus-5-5` (Opus 5.5). 2026-10-07.

## Test plan

All at the session level (unit, `lune run test`): the behaviour lives in
`Session.step`, and the oracle is the DONE pure modules called independently
(`Projection.lensFor` / `turnCuesFor`, `Pings.accept` / `shown`, `PresetSends.send`,
`RoundView.facility`). The sight port in every plan and script is a **constant
`true`** (`ScriptedRound.PORTS`): headlessly there is no geometry to cast a ray
through, so range, class, darkness and commitment are the lens and ping clauses in
play.

### New: `tests/server/session_channel_test.luau` (11 tests, every check in `tests/helpers/SessionChannelContract.luau`)

| Test (check) | Asserts | Covers |
|---|---|---|
| `Contract (C-2)` (`newRequiresPortsAndHoldsAFreshChannelSentAndPorts`) | `Session.new` raises with no 5th argument, `{}` or a non-function `lineOfSight`; holds `channel = { presets = PresetSends.new(), pings = Pings.new() }`, `sent` with exactly keys `cues`, `lens` (both `{}`; `roundView` absent while nil), `ports` the same table's function; `generatorPredicate` in the **6th** argument still reaches the generator (refuse-all ends the deal in Resolution with no facility) | C-2 |
| `AC-1` (`sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange`) | after every step of a sequence (deal, ticks, the helper of T1[1] walking sample by sample, a still sample, the turner walking, the commit, a leave, a tick and a sample after it) the private sends are exactly, in seat order and lens before cues, a `LensView` iff `Projection.lensFor` on the end state differs from the last expected and a `TurnCues` iff `turnCuesFor` differs, payload deep-equal; the first after the deal always (even empty); a player whose views did not change gets nothing; the leaver gets no SendTo of any kind on or after the leave and loses their `sent` entries; SendTo key set exact; no Broadcast carries a private view by kind or by shape | AC-1, C-6 |
| `Contract (C-6)` (`resetsTheSentViewsOnTheDealAndInLobby`) | `state.sent.lens` / `cues` are `{}` in the next Lobby; on the second deal every seated player is sent a LensView and TurnCues again, although at the spawn centre the lens equals the one round 1 ended with | C-6 |
| `AC-3` (`showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit`) | an accepted setting ping: no SendTo, no decline, `channel.pings` deep-equals `Pings.accept(previous, helper, target, Pings.targetPosition(procedure, target), now, true)`, the same step's single RoundView has `pings = Pings.shown(...)`; still shown on the tick at `ping_display_seconds - 1`, `{}` on the tick at `ping_display_seconds`, `active = {}`; a fresh ping is `{}` in the RoundView of the turn that commits its machine, log length 2; a machine ping shows `{ senderId, kind, target }` with no setting; through two leaves (Resolution), Post and Lobby the view's pings are `{}`; `channel` deep-equal kept through Resolution and Post and a fresh channel on entering Lobby | AC-3, C-4, C-8 |
| `AC-3` (`refusesAPingToTheSenderAloneDecliningOnce`) | four refusals (Lobby `no_such_target`, Round `out_of_range` from the spawn centre, Round machine-ping-with-setting `setting_mismatch`, Resolution with the procedure held `no_such_target`): exactly one effect, a `SendTo`/`PingRefused` `{ reason }` to the sender, declined exactly once, state deep-equal unchanged | AC-3, C-4 |
| `AC-4` (`broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone`) | no stored position (Lobby): declined once, no effect, state unchanged; Round "go" with `{ ok = true, text }`: exactly one `Broadcast`/`PresetShown` `{ senderId, presetId, position = stored (a copy, not the same table), text = the filtered text }`, no SendTo, no decline, `channel.presets` deep-equals `PresetSends.send`'s; `{ ok = false }`: one `PresetFailed { presetId, reason = "filter" }` to the sender alone, declined once, log unchanged; "well played" in Round: `phase_for_preset`; in Post: shown at the kept position | AC-4, C-5, PO-4 |
| `AC-5` (`broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise`) | on each of two successful deals exactly one `Broadcast`/`FacilityView` deep-equal `RoundView.facility(state.facility)`, after the last SeatView, before the first private view and the RoundView (which carries machines); none on 8+ other steps (ticks, samples, a commit, two leaves, Post, Lobby, two rejoins); none when generation fails | AC-5, C-7, C-9 |
| `Contract (C-9)` (`ordersEffectsWithinAStepAsTheContractLists`) | on every step of a sequence every effect is a named kind, ranks non-decreasing, at most one RoundView and last; the deal's labels after the pass-through are exactly `Placed x n, SeatView x n, FacilityView, (LensView, TurnCues) x n, RoundView`; an accepted ping emits exactly `{ RoundView }`, a refused one `{ PingRefused }`, a shown preset `{ PresetShown }`, a failed one `{ PresetFailed }`, the commit `TurnResult`, only private views, `RoundView` | C-9, C-6 |
| `AC-6` (`neverSendsAPlayerASettingOfAMachineOutsideTheirLens`) | over 9 full shown rounds (seeds 1-3 at n = 4, 5, 6) every `SendTo` is on the per-kind allowlist (`SeatView`, `LensView`, `TurnCues`, `TurnResult`, `PingRefused`, `PresetFailed`) with only the allowed keys; every `LensView` reading is of a machine whose `keyClass` is `Ring.lensOf(assignment, p)` (read from the state by the test); `TurnCues` lists hold machine ids only; every Broadcast is a public kind carrying no private view by shape; precondition: at least one reading per round was inspected | AC-6 |
| `AC-2` (`winsEveryRoundWhenTurnersActOnlyOnShownPings`) | `ShownRound.play` over seeds 1-50 at each n in {4, 5, 6}: every round ends `won / procedure_complete` | AC-2 (settled) |
| `AC-2 (control)` (`losesToTheClockWhenHelpersNeverPing`) | the same script with `pings = false` over seeds 1-3 at each n: every round ends Resolution `lost / clock` at exactly `startedAt + roundSeconds` with 0 turns and 0 pings | AC-2's control |

### New: `tests/server/session_channel_controls_test.luau` (27 tests; passes on arrival by design - it tests the tests)

A baseline (the reference stand-in `SessionChannelStubs.reference` passes all 11
SLICE-006 checks **and** every SLICE-005, SLICE-003 and VIEW-004 session check -
which is where C-3's narrowings and C-6's amendment are seen to leave the DONE
stories' cases untouched) and 26 one-defect controls, each pinning the exact set of
checks it fires (table in the handoff). The story's named controls: the
broadcast-lens session (AC-1), and the shapes of D-1 (`pingsNeverShown`), D-2
(`lensOfOwnClass`) and D-3 (`alwaysSendsLens` - under which the AC-2 win and AC-6
still pass).

### New helpers

- `tests/helpers/SessionChannelContract.luau` - the checks above, over a session
  module handed in.
- `tests/helpers/SessionChannelStubs.luau` - the reference stand-in (SLICE-005's
  reference wrapped with the channel, the views and the port) and its defects.
- `tests/helpers/ShownRound.luau` - the AC-2 script (C-10). Decision functions take
  exactly `(inbox, position, tuning)`; the inbox is built only from the player's
  own `SendTo`s and every `Broadcast`; the header states that this script does
  **not** read the secret.

### Edited pre-existing tests (C-2 callers and C-3 narrowings)

Every caller in C-2's table now passes `ScriptedRound.PORTS` / `SessionContract.PORTS`
fifth and the options sixth (`ScriptedRound.new`, `SessionContract.run` and
`newHoldsPhaseMachineInitial...`, `SessionRoundContract.run` and `newHolds...`,
`PositionsContract.tracksFromNewAndTheDeal`); the two stand-ins (`SessionRoundStubs`,
`session_controls_test`) accept a `_ports` fifth argument.

| File:line | Old wording | New wording |
|---|---|---|
| `session_test.luau:47` | `Session.new(config, seed, roundId, sessionId) holds exactly PhaseMachine.initial on the same arguments, with assignment nil` | `Session.new(config, seed, roundId, sessionId, ports) holds exactly PhaseMachine.initial on the first four arguments, with assignment nil (ports fifth since SLICE-006 C-2)` |
| `session_round_test.luau:45` (C-1) | `... accepts an optional fifth options argument carrying generatorPredicate` | `... accepts an optional SIXTH options argument carrying generatorPredicate, after the ports SLICE-006 C-2 made the fifth` |
| `session_round_test.luau:71` (AC-3) | `... the caller alone receives one SendTo/TurnResult carrying TurnRequests.reply(result)` | adds `; a RoundView rides along only when the phase changed or (SLICE-006 C-6) the turn was evaluated` - the check now tolerates `LensView`/`TurnCues` SendTos beside the TurnResult and 0 or 1 RoundView on a committed/armed/rejected turn (a refused turn still broadcasts nothing) |
| `session_round_test.luau:77` (C-3) | `... emits nothing but a due Placed (none here: every sample is walkable)` | `... emits no Placed (every sample is walkable) and nothing but the LensView sends and the RoundView broadcast SLICE-006 C-6 allows` |
| `session_round_test.luau:91` (C-4) | `ordered pass-through, Placed in seat order, SendTo/SeatView, SendTo/TurnResult, then at most one Broadcast/RoundView last, and nothing of another kind` | `ordered pass-through, Placed in seat order, SendTo/SeatView, Broadcast/FacilityView, the caller's reply (TurnResult, PingRefused or PresetFailed), Broadcast/PresetShown, SendTo/LensView and TurnCues, then at most one Broadcast/RoundView last, and nothing of another kind` (`RANK` widened to C-9; a Broadcast is labelled by its payloadKind) |
| `session_controls_test.luau:578` (SLICE-003 control) | `... fails exactly the own-view check ... and the order check (two Broadcasts)`, expecting `{ OWN_VIEW, ORDER }` | `... since SLICE-006 C-3 narrowed the order check to RoundView broadcasts, the second Broadcast no longer fires it`, expecting `{ OWN_VIEW }` |
| `SessionContract.luau` (helper, SLICE-003) | a SendTo of a kind other than `SeatView` was a problem; a Broadcast of a kind other than `RoundView` was a problem; the order check counted every SendTo and every Broadcast | seat-view checks read `SeatView` sends only; Broadcast kinds accepted are `PUBLIC_BROADCAST_KINDS = { RoundView, FacilityView, PresetShown }` (the shape check still applies to all); the order check reads SeatView sends and RoundView broadcasts only. **Unchanged:** the AC-4 cadence check (`broadcastsRoundViewExactlyWhen...`) and every case it names - they pass unedited against the reference, as C-3 predicted, *given* the C-6 amendment |
| `SessionRoundContract.luau` (helper, SLICE-005) | "the only effect a PositionsSampled may emit is Placed"; `#effects == 0` on a walkable sample | allowed kinds `Placed`, `SendTo/LensView`, `Broadcast/RoundView`; no `Placed` on a walkable sample. The win check's last two labels are `TurnResult, RoundView` (was `TurnResult, Broadcast`) |
| `PositionsContract.luau` `expectNoEffects` call sites | - | **unchanged**: the reference stand-in passes every VIEW-004 session check, so no sample in those plans changes a lens (they sample at the spawn centre) and the assertions stand, as C-3 allows |

## Handoff: RED -> GREEN

Written by the Test Developer (second dispatch, 2026-10-07; the first wrote the
tests and was cut off before this section - see `## Model guidance`). Everything
below was measured on this machine (Windows, Lune) unless it says CI.

### The command

    lune run test

(the `unit` gate's command, `project.conf`). There is no per-file filter in the
runner; the new tests are the 11 in `tests/server/session_channel_test.luau` and
the 27 in `tests/server/session_channel_controls_test.luau`. No test dependency
was added; no manifest was touched.

### The failure, verbatim (`lune run test`, tree at `eb21397` + this RED, 2026-10-07)

Summary line: `1330 passed, 14 failed` (the baseline before RED was `1306 passed,
0 failed`; the 27 controls are new and green by design). The 14:

    FAIL  tests/server/session_channel_test.luau :: AC-1: after every step of a scripted sequence each seated player alone receives a SendTo/LensView iff Projection.lensFor on the end state differs from the last one sent and a SendTo/TurnCues iff turnCuesFor differs (seat order, lens before cues; the first after the deal always, even empty; PositionsSampled steps included); a player whose views did not change receives nothing; the leaver is never sent another and loses their sent entries; no Broadcast carries a LensView or TurnCues by kind or by shape
          AC-1: each player alone receives their LensView and TurnCues exactly when they change (the first after the deal always), the leaver never again, and no Broadcast carries either:
    "DEAL": 0 private send(s) {  }, expected exactly 8 { 1 = "LensView -> ann", 2 = "TurnCues -> ann", 3 = "LensView -> bob", 4 = "TurnCues -> bob", 5 = "LensView -> cat", 6 = "TurnCues -> cat", 7 = "LensView -> dan", 8 = "TurnCues -> dan" } - a view goes to its player alone, iff it differs from the last one sent (C-6)
    "walk sample 1": 0 private send(s) {  }, expected exactly 1 { 1 = "LensView -> ann" } - a view goes to its player alone, iff it differs from the last one sent (C-6)
    "the turn that commits T1[1]": 0 private send(s) {  }, expected exactly 4 { 1 = "LensView -> ann", 2 = "TurnCues -> ann", 3 = "TurnCues -> cat", 4 = "TurnCues -> dan" } - a view goes to its player alone, iff it differs from the last one sent (C-6)
    "bob leaves the Round": 0 private send(s) {  }, expected exactly 1 { 1 = "TurnCues -> cat" } - a view goes to its player alone, iff it differs from the last one sent (C-6)
    state.sent is nil after the leave, expected a table (C-1)
          [measured] AC-2 control: 9/9 rounds lost / clock with no turn and no ping
    pass  tests/server/session_channel_test.luau :: AC-2 (control): the same script with the helper's ping suppressed never wins - no ping, no turn, lost / clock on the unpenalised deadline - over 3 seeds at each n
          [measured] AC-2: 0/150 rounds won by showing; max 420 s deal-to-resolution, max 846 steps; 0 pings (0 refused, 0 declines), 0 turns
    FAIL  tests/server/session_channel_test.luau :: AC-2: over 50 seeds at each n in {4, 5, 6} the shown script - each turner turns only to a setting its supplier's PingShown names, each helper pings only a reading in its own LensView, the finale gated on the partner lamp - wins every round (won / procedure_complete)
          AC-2: every scripted round (150) must be won with each turner acting only on its helper's shown ping, and each helper only on its own lens:
    seed 1, n = 4: after 420 s the round is Resolution / { reason = "clock", result = "lost" } with 0 pings and 0 turns, expected won / procedure_complete
    seed 2, n = 4: after 420 s the round is Resolution / { reason = "clock", result = "lost" } with 0 pings and 0 turns, expected won / procedure_complete
    (... 8 more shown, then)  ... and 140 more
    FAIL  tests/server/session_channel_test.luau :: AC-3: a refused ping emits exactly one SendTo/PingRefused { reason } to its sender, declines the call exactly once and changes nothing - no_such_target in Lobby and in Resolution (procedure held), out_of_range from the spawn centre, setting_mismatch for a machine ping with a setting
          AC-3: a refused ping sends one PingRefused to its sender alone, declines the call exactly once, changes nothing, and is no_such_target outside Round:
    in Lobby, before any deal: the ping was ACCEPTED (effects {  }), expected refused / no_such_target
    in Round, out of range from the spawn centre: the ping was ACCEPTED (effects {  }), expected refused / out_of_range
    in Round, a machine ping carrying a setting: the ping was ACCEPTED (effects {  }), expected refused / setting_mismatch
    in Resolution, with the procedure still held: the ping was ACCEPTED (effects {  }), expected refused / no_such_target
    FAIL  tests/server/session_channel_test.luau :: AC-3: an accepted setting ping (helper at the machine) is Pings.accept(previous, sender, target, Pings.targetPosition, now, roomLit) with no SendTo and no decline, and that step's RoundView broadcast shows Pings.shown of it; [...]
          D:\first-roblox\tests\helpers\SessionChannelContract:811: attempt to index nil with 'pings'
    FAIL  tests/server/session_channel_test.luau :: AC-4: a PresetSent whose filter result succeeded broadcasts exactly one PresetShown { senderId, presetId, position = the sender's STORED position (a copy), text = the filtered text } [...]
          D:\first-roblox\tests\helpers\SessionChannelContract:1180: attempt to index nil with 'presets'
    FAIL  tests/server/session_channel_test.luau :: AC-5: on each successful deal exactly one Broadcast/FacilityView = RoundView.facility(state.facility), after the SeatViews and before the private views and the RoundView with machines; none on any other step through Resolution, Post, Lobby and the rejoins, and none when generation fails
          AC-5 precondition: the refused deal left the phase at Round
          [measured] AC-6: 7560 steps over 9 rounds; 0 LensViews carrying 0 readings inspected
    FAIL  tests/server/session_channel_test.luau :: AC-6: over full shown rounds (3 seeds at each n) every SendTo is on the allowlist - a LensView reads only machines whose keyClass is Ring.lensOf(assignment, p), TurnCues carry only machine ids, SeatView/TurnResult/PingRefused/PresetFailed carry no setting field, any other private kind fails - and every Broadcast is a public kind carrying no private view by shape
          AC-6 precondition: only 0 readings in 0 LensViews over 9 rounds; a round in which no lens is ever read proves nothing about what a lens may carry
    FAIL  tests/server/session_channel_test.luau :: Contract (C-2): Session.new(config, seed, roundId, sessionId, ports, options?) raises without ports.lineOfSight as a function, holds channel = { presets = PresetSends.new(), pings = Pings.new() }, sent = { lens = {}, cues = {} } and the ports as given, and still reads generatorPredicate from the sixth argument
          C-2: Session.new(config, seed, roundId, sessionId, ports, options?) must raise without ports.lineOfSight and hold a fresh channel, an empty sent and the ports:
    Session.new with no fifth argument as ports returned a state; C-2 says it RAISES (a defaulted sight would read through walls)
    Session.new with an empty table as ports returned a state; C-2 says it RAISES (a defaulted sight would read through walls)
    Session.new with a lineOfSight that is not a function as ports returned a state; C-2 says it RAISES (a defaulted sight would read through walls)
    state.channel from new is nil, expected { presets = PresetSends.new(), pings = Pings.new() } = { pings = { active = {  }, log = {  } }, presets = { log = {  } } }
    state.sent from new is nil, expected a table
    state.ports from new is nil, expected the ports as given (the same lineOfSight function)
    with options.generatorPredicate refusing every attempt (sixth argument) the deal left the phase at "Round" with facility held, expected Resolution with none - the options are not being read from the sixth argument
    FAIL  tests/server/session_channel_test.luau :: Contract (C-6): sent.lens and sent.cues are {} on entering Lobby and reset on the deal, so on a second deal every seated player is sent a LensView and TurnCues again although the lens equals the last one of round 1
          C-6: sent.lens and sent.cues are reset on the deal and on entering Lobby, so the first view of every round is sent:
    state.sent is nil in the next Lobby, expected a table
    on the second deal LensViews went to {  }, expected every seated player { 1 = "ann", 2 = "bob", 3 = "cat", 4 = "dan" } in seat order - the first view of a round is always sent, even one equal to the last round's (sent is reset on the deal)
    on the second deal TurnCues went to {  }, expected every seated player { 1 = "ann", 2 = "bob", 3 = "cat", 4 = "dan" }
    FAIL  tests/server/session_channel_test.luau :: Contract (C-9): every effect of every step is a named kind in the order pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues, at most one RoundView last; [...]
          C-9: within a step the effects are pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues per player, then at most one RoundView last, and nothing of another kind:
    the deal's effects after the pass-through are { 1 = "Placed", 2 = "Placed", 3 = "Placed", 4 = "Placed", 5 = "SeatView", 6 = "SeatView", 7 = "SeatView", 8 = "SeatView", 9 = "RoundView" }, expected { 1 = "Placed", 10 = "LensView", 11 = "TurnCues", 12 = "LensView", 13 = "TurnCues", 14 = "LensView", 15 = "TurnCues", 16 = "LensView", 17 = "TurnCues", 18 = "RoundView", 2 = "Placed", 3 = "Placed", 4 = "Placed", 5 = "SeatView", 6 = "SeatView", 7 = "SeatView", 8 = "SeatView", 9 = "FacilityView" }
    an accepted ping's effects are {  }, expected exactly the RoundView
    a refused ping's effects are {  }, expected exactly the PingRefused
    a shown preset's effects are {  }, expected exactly the PresetShown
    a failed preset's effects are {  }, expected exactly the PresetFailed
    the commit turn's effects are { 1 = "TurnResult" }, expected the TurnResult, then only LensView/TurnCues (the helper's reading is gone, the cues moved), then the RoundView
    FAIL  tests/server/session_positions_test.luau :: Contract: the walk speed is state.tuning.instance.walk_speed_studs_per_second - under a tuning ten times faster a jump just past the shipped bound is accepted; under the shipped tuning it is refused
          Contract: the walk speed must be read from state.tuning, not from the shipped MechanicsTuning:
    under a tuning with walk speed 160, a 42-stud move in 1 s was not accepted: state.positions[ann] is { x = 64, y = 0, z = 64 }
    FAIL  tests/server/session_round_test.luau :: AC-2: with options.generatorPredicate refusing every attempt the dealing step ends in Resolution with no_contest / generation_failed, [...]
          AC-2: a generator that fails every attempt must resolve no_contest / generation_failed in the dealing step, with seat views still sent:
    after the dealing step the phase is "Round", expected Resolution in the same step
    (... 8 more lines)
    FAIL  tests/server/session_round_test.luau :: Contract (C-3): a TurnRequested in Lobby, Resolution, Post, the next Lobby, and Resolution after a failed generation returns the same state with {} effects
          Contract: a TurnRequested with no procedure or outside Round must return the same state with {} effects:
    "turn in Resolution after a failed generation (ignored)": { 1 = "SendTo" } emitted on a turn outside Round, expected {}
    FAIL  tests/server/session_round_test.luau :: Contract (C-3): after every step of a two-round lifecycle with samples, turns, a penalised clock-out and a failed generation, state.round, assignment, facility, procedure and positions deep-equal the Contract's own composition [...]
          after "DEAL (generation fails)": state.round differs from the Contract's composition:
    value.phase: expected "Resolution", got "Round"
    value.outcome: expected { reason = "generation_failed", result = "no_contest" }, got nil
    1330 passed, 14 failed

**Why this is the right failure.** The module loads (it exists from SLICE-005), so
every failure is an assertion, not an import error. The 10 in
`session_channel_test` each name the missing behaviour: `Session.new` accepts
missing ports and holds no `channel`/`sent`/`ports` (C-2); no `LensView`/`TurnCues`
is ever sent (AC-1, C-6); `PingRequested` and `PresetSent` are unknown events that
fall through as no-ops - "the ping was ACCEPTED (effects {})" is the refusal check
seeing neither a `PingRefused` nor a decline (AC-3, AC-4, C-9); no `FacilityView`
(AC-5); and the AC-2 script, denied every lens, never pings and never turns, so all
150 rounds clock out `lost / clock` with `0 pings and 0 turns` - the C-10 property
that a broken routing leaves the script unable to act, not able to cheat. The 4 in
`session_round_test` / `session_positions_test` are **the C-2 slot change**: every
caller now passes `ports` fifth and `options` sixth, today's `Session.new` reads
`options` from the fifth slot, so `generatorPredicate` and `tuning` are silently
lost (a refuse-all generator still deals; a 10x walk speed is not read). They go
green with C-2 alone. The AC-3 "attempt to index nil with 'pings'/'presets'" lines
are the check reading `state.channel` before its assertion - the C-2 failure seen
from AC-3's side; once `channel` exists they become the ping/preset assertions.

**`rg -n "S\.new|Session\.new" src tests`, re-run 2026-10-07** against this tree: the
only `src` hit is the definition (`Session.luau:141`). Every test hit is in C-2's
table and updated (ScriptedRound 166, SessionContract 17/281/568,
SessionRoundContract 569/956/991, PositionsContract 1144, SessionRoundStubs 110,
session_controls_test 90, the two test names), plus this story's own files, plus
two **message needles** that are not calls (`session_round_controls_test:578`,
`session_controls_test:768`, both `"Session.new is nil"`). No other caller.

### Files touched (all `test` by `paths.conf`; `src/**` untouched)

New: `tests/server/session_channel_test.luau`,
`tests/server/session_channel_controls_test.luau`,
`tests/helpers/SessionChannelContract.luau`, `tests/helpers/SessionChannelStubs.luau`,
`tests/helpers/ShownRound.luau`. Edited: `tests/helpers/ScriptedRound.luau` (`PORTS`,
`sightAlwaysTrue`, `ping`, `preset`, `call`, options sixth),
`tests/helpers/SessionContract.luau`, `tests/helpers/SessionRoundContract.luau`,
`tests/helpers/SessionRoundStubs.luau`, `tests/helpers/PositionsContract.luau`,
`tests/server/session_controls_test.luau`, `tests/server/session_round_test.luau`,
`tests/server/session_test.luau` (what changed in each: `## Test plan`). The
temporary instruments (`tests/__probe_*.luau`) are deleted. Story: this section,
`## Test plan`, the C-6 amendment and RED note in `## Contract`, the RED line under
`## Model guidance`.

### The export shape the tests already pin

Nothing here is a suggestion: a test already imports or destructures it.

    src/server/session/Session.luau            (the only module GREEN changes)
      Session.new(config, seed, roundId, sessionId, ports, options?) -> SessionState
        - raises (any message) when `ports` is not a table or `ports.lineOfSight`
          is not a function: tested with nil, {} and { lineOfSight = true }
        - options (tuning, generatorPredicate) read from the SIXTH argument
      Session.step(state, event, now) -> (SessionState, { SessionEffect })   -- unchanged
      SessionState gains, exactly as C-1:
        channel = { presets = PresetSends.new(), pings = Pings.new() }   -- deep-equal from new
        sent    = { lens = {}, cues = {} }   -- from new, keysOf(sent) == { "cues", "lens" }:
                                            -- `roundView` ABSENT while nil (a nil field is
                                            -- absent in Luau anyway; do not store false)
        ports   = the table given (asserted: state.ports.lineOfSight == the same function)
      SessionEvent gains (built by tests/helpers/ScriptedRound.ping / .preset):
        { kind = "PingRequested", playerId, target = { kind, target, setting? }, call = { decline } }
        { kind = "PresetSent", playerId, presetId, filtered = { ok = true, text } | { ok = false }, call }
      SessionEffect gains, every SendTo with EXACTLY the keys { kind, payload, payloadKind, playerId }
      and every Broadcast { kind, payload, payloadKind }:
        SendTo/LensView      payload = Projection.lensFor(assignment, procedure, p, positions[p], ports.lineOfSight)  (deep-equal)
        SendTo/TurnCues      payload = Projection.turnCuesFor(assignment, procedure, p)                               (deep-equal)
        SendTo/PingRefused   payload = exactly { reason }  (the value Pings.request returned)
        SendTo/PresetFailed  payload = exactly { presetId, reason }  (PresetSends' failed value)
        Broadcast/PresetShown  payload = PresetSends' shown value: { senderId, presetId, position, text }, position a COPY
                               (rawequal(payload.position, state.positions[sender]) must be false)
        Broadcast/FacilityView payload = RoundView.facility(state.facility)  (deep-equal)
        Broadcast/RoundView    payload = RoundView.public({ round, procedure, assignment, positions, pings, tuning }, now)
                               with pings = Pings.shown(channel.pings) in Round, {} otherwise

    Modules the tests require besides Session (all DONE, frozen; the tests call them
    as the oracle): src/server/channel/Pings (new, request, accept, targetPosition,
    tick, onCommitted, shown; state shape { active, log }), src/server/channel/PresetSends
    (new, send), src/shared/channel/Presets (ALL, keys "go", "ready", "well_played"),
    src/server/seats/Projection (lensFor, turnCuesFor), src/server/seats/Ring (lensOf),
    src/server/round/RoundView (public, facility), src/server/facility/Machines
    (positionOf), src/server/procedure/Procedure (isDark), src/shared/MechanicsTuning
    (channel.ping_display_seconds, channel.ping_range_studs, instance.turn_range_studs,
    instance.walk_speed_studs_per_second).

Behaviour the assertions pin beyond the shapes (each is a line in the output above
or in a control's expected set):

- **Refused ping** (any phase): the step's effects are exactly `{ SendTo/PingRefused }`
  to the sender, `call.decline` called exactly once (by `Pings.request`), and the
  returned state **deep-equal** to the input (a clone is fine; no `sent`/`channel`
  churn). Outside Round pass `nil` as the procedure - the test expects
  `no_such_target` in Lobby and in Resolution with the procedure still held.
- **Accepted ping**: effects exactly `{ Broadcast/RoundView }` (the view changed), no
  decline, `channel.pings` deep-equal `Pings.accept(previous, sender, target,
  Pings.targetPosition(procedure, target), now, roomLit)`.
- **Tick**: `Pings.tick(pings, now, state.tuning)` before the views; the ping is in
  the view on the tick at `pingedAt + D - 1` and gone at `pingedAt + D`.
- **Commit**: a machine whose `committed[id]` turned true this step is
  `Pings.onCommitted`; that step's RoundView shows `{}`; the log keeps both entries.
- **Preset with no stored position**: decline once, effects `{}`, state deep-equal.
  Shown: effects exactly `{ Broadcast/PresetShown }`, no decline, `channel.presets`
  deep-equal `PresetSends.send`'s. Failed: exactly `{ SendTo/PresetFailed }` to the
  sender, declined once, log unchanged. `PresetSends.send` gets `round.phase` (so
  "well played" shows in Post at the kept position).
- **Deal**: labels after the pass-through are exactly `Placed x n, SeatView x n,
  FacilityView, (LensView, TurnCues) x n, RoundView`; no FacilityView on a failed
  generation, a tick, a sample, a turn, a leave, Post, Lobby or a rejoin.
- **Commit turn**: `TurnResult`, then only `LensView`/`TurnCues` (at least one), then
  the `RoundView` - a commit changes the view, so the RoundView rides on it.
- **Leave in Round**: the leaver gets no SendTo of any kind, and
  `state.sent.lens[leaver]` / `cues[leaver]` are nil afterwards.
- **Lobby**: `state.sent.lens == {}`, `cues == {}`, `channel` deep-equal a fresh one;
  `channel` deep-equal **unchanged** on entering Resolution and Post.
- **Every step**: at most one RoundView, last; every effect one of C-9's kinds.

**Not constrained** (the implementer's choice): where in `Session.luau` the views are
built (inline or a helper); how deep-equality is implemented; the wording of the
`Session.new` error; whether the deal resets `sent` (unobservable - see the RED note
under C-6); `secondsLeft` on a non-Tick step's RoundView (C-6 as amended compares the
view without it); internal structure of `state.channel` beyond being the two modules'
states; whether `step` clones or rebuilds the state, provided a refused ping, a
no-position preset and every ignored event return a state deep-equal to the input.

### Tests that passed on arrival, and what earns them

- `AC-2 (control)` in `session_channel_test` - green today because today's Session
  never shows a ping, so the control's "lost / clock, 0 turns, 0 pings" holds
  vacuously. Earned by the controls file: on the reference stand-in the same script
  with `pings = true` wins 150/150 and with `pings = false` loses 9/9 (baseline), and
  under `pingsNeverShown` (D-1's shape) the win fails while the control still holds.
  GREEN must see it stay green against the shipped module **while AC-2 goes green** -
  the pair is the evidence.
- `session_channel_controls_test` (27) - green by design; it is the proof that each
  check fires on exactly the defect it names (table below). Also `session_round_test`
  `Contract (C-1)` now passes (today's Session ignores a sixth argument without
  raising; it is pinned by the C-2 check's sixth-argument clause, which is red).
- Every unchanged DONE-story test (SLICE-003 `session_test`, the controls files) is
  green, as C-3 predicted: the cases SLICE-003 names (refused join, stranger's leave,
  ignored event, rematch, leave in Post) pass **unedited** against the reference
  stand-in - but only with the C-6 amendment (see "Findings").

### Expected values of every negative control (measured in RED on the reference stand-in; GREEN confirms each against the shipped module)

The stand-in (`SessionChannelStubs.standIn`) is SLICE-005's reference wrapped with
C-4..C-9; it is **not** a sketch of `Session.luau`. The sight port is a constant
`true` (`ScriptedRound.PORTS`). Script-level numbers, from the baseline:

| Control / measurement | Threshold | Candidate range | Measured in RED (reference) | Measured in RED (today's Session) |
|---|---|---|---|---|
| AC-2 win, `ShownRound.play`, seeds 1-50 x n in {4,5,6} | 150/150 `won / procedure_complete` | 0-150 | **150/150**; max 64 s deal-to-resolution, max 150 steps; 1203 pings (0 refused, 0 declines), 1366 turns | 0/150; every round `lost / clock` at 420 s, 846 steps, 0 pings, 0 turns |
| AC-2 control, `pings = false`, seeds 1-3 x n in {4,5,6} | 9/9 Resolution `lost / clock` at `startedAt + roundSeconds` (420 s) with 0 turns, 0 pings | 0-9 | **9/9** | 9/9 (vacuous: no lens, no ping) |
| AC-6 sweep, seeds 1-3 x n in {4,5,6} | 0 problems; precondition >= 9 readings | - | 830 steps, 205 LensViews carrying **89 readings**, 0 problems | 7560 steps, 0 LensViews, 0 readings (precondition fails) |
| AC-1 sequence (seed 1, n = 4) | precondition >= 5 lens sends, >= 5 cue sends, >= 3 silent steps, >= 1 single-recipient step | - | 6 LensView, 8 TurnCues, 14 silent, 2 alone; 0 problems | same expectations; 0 sends |
| Reference vs the four batteries | 0 failures each | - | 0 of 11 SLICE-006, 0 of 16 SLICE-005, 0 of 15 SLICE-003, 0 of 7 VIEW-004 | n/a |

Each stand-in control fires **exactly** this set (names are
`SessionChannelContract.CHECKS` entries; the controls file asserts set equality and
that each message names its criterion). `Full` = the whole channel battery; `FAST` =
`SessionChannelContract.FAST` (the 8 cheap checks) - the full battery was also run
on every FAST control in RED and measured the same set:

| Defect (one per control) | Fires (SLICE-006) | Also fires | Battery |
|---|---|---|---|
| `acceptsMissingPorts` | C-2 | - | FAST |
| `broadcastsLensViews` (**the story's AC-1 control**) | AC-1, C-6 reset, AC-6, **AC-2 win** | SLICE-003 `sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone` | Full |
| `sendsLensToEveryone` | AC-1, C-6 reset, C-9, AC-6, AC-2 win | - | Full |
| `alwaysSendsLens` (**D-3's shape**) | AC-1, C-9, AC-3 shown, AC-3 refused, AC-4; **AC-2 win and AC-6 pass** | SLICE-003 `ignoresASeatsAssigned...`, `sendsNoSeatView...`; VIEW-004 `dealPlacementIsTheBaseline`, `implausibleSampleDoesNotReachATurn`, `resyncPlacesBackInRoundOnly`, `samplesMergeIntoFreshAcceptedCopies`, `unplacedPlayerIsAbsentAndOutOfReach` | Full |
| `lensOfOwnClass` (**D-2's shape**) | AC-1, AC-6, AC-2 win | - | Full |
| `sentKeptAcrossRounds` | C-6 reset | - | FAST |
| `sendsWithdrawnPlayers` | AC-1 | SLICE-003 `ignoresASeatsAssigned...`, `sendsNoSeatView...`, `withdrawsOnTheLeaveThatDropsBelowQuorumToo`, `withdrawsTheLeaverAndSendsViews...` | FAST |
| `pingsNeverShown` (**D-1's shape**) | AC-3 shown, C-9, AC-2 win | - | Full |
| `pingsNeverExpire` | AC-3 shown | - | FAST |
| `pingsSurviveCommit` | AC-3 shown | - | FAST |
| `broadcastsPingRefused` | AC-3 refused | - | FAST |
| `declinesAcceptedPing` | AC-3 shown | - | FAST |
| `pingsJudgedOutsideRound` | AC-3 refused | - | FAST |
| `pingsShownOutsideRound` | AC-3 shown | - | FAST |
| `roundViewOnlyOnOldTriggers` | AC-3 shown, C-9 | - | FAST |
| `channelKeptInLobby` | AC-3 shown | - | FAST |
| `channelResetInPost` | AC-3 shown | - | FAST |
| `presetAtTheOrigin` | AC-4 | - | FAST |
| `presetIgnoresFilter` | AC-4, C-9 | - | FAST |
| `broadcastsPresetFailed` | AC-4 | - | FAST |
| `presetInventsAPosition` | AC-4 | - | FAST |
| `presetWithoutPositionNotDeclined` | AC-4 | - | FAST |
| `noFacilityView` | AC-5, C-9, AC-6 (precondition: 0 readings), AC-2 win | - | Full |
| `facilityViewOnEveryTick` | AC-5 | - | FAST |
| `facilityViewOnFailedGeneration` | AC-5 | - | FAST |
| `facilityViewAfterRoundView` | AC-5, C-9 | SLICE-005 `ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast`; SLICE-003 `ordersPassThroughThenSeatViewsThenRoundViewLast` | FAST + SLICE-005 |

A defect the first dispatch had written, `sentNotResetOnDeal`, fired **nothing** and
was replaced by `sentKeptAcrossRounds`: the deal reset is unobservable given the
Lobby reset (RED note under C-6).

### Deferred verifications - declined, with predictions

RED cannot run D-1, D-2 or D-3: each mutates `src/**`, which is frozen here and
holds none of the behaviour yet (a mutation of nothing proves nothing). Owner:
**GATES**, with `bash scripts/mutate.sh ... -- lune run test`. From the stand-in
shapes above, the predicted red sets in `session_channel_test` are:

- **D-1** (`Pings.shown` returns `{}`): **3** tests - `AC-3: an accepted setting ping ...`,
  `Contract (C-9)`, `AC-2: over 50 seeds ...` (0/150 won, every round `lost / clock`
  with pings made but no turns). `AC-2 (control)` stays green. Cost: ~25 s (150
  clock-outs).
- **D-2** (`lensFor` returns the dependent's class): **3** tests - `AC-1`, `AC-6`
  (readings of a machine whose class is not `Ring.lensOf`), `AC-2` (0/150; helpers
  ping settings their dependents cannot use). The story requires AC-2 and AC-6; AC-1
  is the extra. Note the stand-in models it as the player's OWN first key class; the
  real mutation's exact wrong class may differ, the set should not.
- **D-3** (the lens comparison always "changed"): **5** tests in `session_channel_test` -
  `AC-1` (its no-change clause), `Contract (C-9)`, both `AC-3` tests, `AC-4` - **and
  AC-2 and AC-6 must stay green**; plus **2** in `session_test` (`ignoresASeatsAssigned...`,
  `sendsNoSeatView...`) and **5** in `session_positions_test` (the VIEW-004 names above),
  because a lens riding on a no-op step breaks their "{} effects" pins. If AC-2 goes
  red under D-3 the script is reading a lens's arrival as a signal, which C-10 forbids.

### Timings (local; CI not measured)

| File | Wall time here | Note |
|---|---|---|
| `session_channel_test.luau` vs today's Session | 1.6 s | no lens is built; 150 clock-outs of 846 steps |
| the same 11 checks vs the reference stand-in | 2.0 s | what the file should cost in GREEN |
| `session_channel_controls_test.luau` | **61.6 s** | five Full controls at 7-25 s each (150 clock-outs with lens building); the other 21 at ~0.1 s; baseline ~5 s |
| `session_round_controls_test.luau` (unchanged) | 18 s | for scale |
| whole `lune run test` | 5 min 8 s | 1357 tests |

**Flag:** the controls file sits at the ~60 s mark locally; CI hardware is slower
(the `quality-gates` skill's one per-test measurement on this harness was 3.4x, on
a different gate; this project's `unit` gate has no per-test CI figure yet), so
expect minutes there, not seconds. `lune/test.luau` has
no per-test timeout, so this is gate wall time, not a timeout risk. The cost is
inherent in a *losing* AC-2 sweep (150 x 420 simulated seconds); the same cost
applies to D-1/D-2 under GATES and to any GREEN run where AC-2 is still red. If the
gate's wall time becomes a problem, the lever is `SessionChannelContract.SEEDS` for
the controls only - not for the AC-2 criterion, which fixes 50.

### Findings that change the approach

1. **C-6 amended in place (secondsLeft).** See the amendment under C-6. A strict
   deep-equal on the RoundView made the reference stand-in fail six DONE-story
   checks that C-3 says must pass unedited; ignoring `secondsLeft` in the comparison
   is what makes "SLICE-003's triggers **or** a changed view" true. GREEN: compare
   the view minus `secondsLeft`; still store the whole view in `sent.roundView`.
2. **The deal reset of `sent` is unobservable** (RED note under C-6). Not an
   amendment; the tests cannot tell.
3. **C-3 held as the PO predicted**: no `PositionsContract` `expectNoEffects` site
   needed narrowing (the reference passes all 7 VIEW-004 session checks), and
   SLICE-003's AC-4 cadence check is unedited. The narrowings made are exactly the
   ones C-3 lists plus two the PO's "any further assertion" clause covers:
   SLICE-005's turn check (a RoundView may ride on an evaluated turn; LensView /
   TurnCues SendTos beside the TurnResult) and its win check's last-two-labels
   needle (`RoundView`, not `Broadcast`).
4. **An accepted ping emits only the RoundView; a preset emits only its
   PresetShown/PresetFailed** (C-9's exact lists). So a ping or preset step must not
   re-send a lens or cue (nothing changed) and must not emit a RoundView on a
   preset (the view does not carry presets). D-3's shape is what violates this.
5. **The AC-2 script needs the FacilityView to locate machines**
   (`Machines.positionOf` over its rooms and slots): `noFacilityView` makes AC-2
   fail, so the AC-5 broadcast is on the win's critical path, not decoration.

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

    run:    2026-10-07T15:17:05Z
    commit: 6c4ba26
    tree:   7b98e77e2777d11a4d1c43f3221981de919272b6
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 200)
    PASS         lint (0s, observed 200, floor 1)
    PASS         typecheck (2s, observed 32)
    PASS         unit (281s, observed 1344, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 128260)
    PASS         harness (25s, observed 41)
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


**PO decisions at PLANNED -> RED (lead-po, 2026-10-06).** Made against the tree at
`eb21397`, after `CHAN-004` and `VIEW-003` reached DONE.

1. **PO-1 - `Session.new(config, seed, roundId, sessionId, ports, options?)`.**
   The planned contract put `ports` 5th, but `options` already holds that slot
   (SLICE-005). `ports` takes it and is required; `options` moves to 6th. `ports`
   carries only `lineOfSight` (PO-3). The planned caller `RoundService.server.luau`
   does not exist; the real caller list is C-2's table.
2. **PO-2 - this story supersedes two pinned behaviours of DONE stories.** "A
   `PositionsSampled` emits nothing but `Placed`" (SLICE-005 C-3 / VIEW-004) cannot
   survive AC-1: a lens changes when its holder walks. And the `RoundView` cadence
   becomes "SLICE-003 AC-4's triggers **or** a changed view", which keeps every
   case SLICE-003 named and adds the §9.7 "when its contents change" half (an
   accepted ping, a committed machine, a partner lamp). C-3 lists the assertions;
   RED amends them in place, narrowly.
3. **PO-3 - the filter is not a port; its answer rides in the event** (the
   contract's own amendment clause, settled by `CHAN-001`: both Roblox calls
   yield). AC-4's wording "a succeeding filter port" became "whose filter result
   succeeded" - an edit made in PLANNED, recorded under `## Amendments` (an entry IS due: see there); the
   criterion's meaning is unchanged.
4. **PO-4 - a preset from a player with no stored position is declined with no
   effect.** `PresetShown` needs a position and inventing one would broadcast a
   lie; adding a `FailReason` would reopen `CHAN-004`. In production the window is
   the moment before a player's first sample.
5. **Epic done-when check (EPIC-08).** Items 1 and 2 are this story's (AC-2 and its
   control). Items 3-5 belong to `MAP-001`, `HUD-*`, `SLICE-007`. No gap between
   `SLICE-005` and this story.
6. **Gate.** `unit` (required) covers `src/server/**`; it is the gate that fails if
   this artifact breaks. No optional gate reads it, so `required_gates` stays `[]`.

**RED verification (lead-po, 2026-10-07).**

- The first RED dispatch was cut off by the session ending; its tests were on disk
  without a handoff. A second dispatch reviewed them, added
  `session_channel_controls_test.luau`, amended C-6 and wrote the handoff.
- `lune run test` (orchestrator, tree as committed in `d750b37`):
  `1330 passed, 14 failed`. All 14 are the story's: 10 in
  `session_channel_test` on missing behaviour (`state.channel` nil, no
  `LensView`/`FacilityView`, pings accepted as no-ops, AC-2 `0/150` with 0 pings and
  0 turns); 3 in `session_round_test` and 1 in `session_positions_test` because the
  callers now pass `options` 6th (C-2) and today's `Session` reads it 5th.
  Baseline before RED: `1306 passed, 0 failed`.
- **C-6 amendment reproduced independently** (not by re-running RED's stand-in):
  `SessionContract.lifecycle()` broadcasts on the Tick at `deal1 + 100.25`, then
  steps an ignored `SeatsAssigned` at `deal1 + 101`, which
  `ignoresASeatsAssignedEventFromOutsideAndEveryNoOp` requires to return `{}` and
  an unchanged state. `ceil(R - 100.25) = R - 100 ≠ R - 101 = ceil(R - 101)`, so a
  strict comparison would broadcast there. Ignoring `secondsLeft` in the diff is
  right; the per-second Tick carries the clock.
- **C-10 reviewed:** `ShownRound.goalOf/pingOf/turnOf` take `(inbox, position,
  tuning)` only; `d.state` is read only by the driver loop's phase check and by the
  test's `observe` hook (AC-6).
- `gates.sh --fast`: format, lint (200), typecheck (32), build PASS; `unit` FAIL
  with the 14 above (the right failure); `harness` FAIL 7, because RED's five new
  test files moved the format/lint counts 195 -> 200. Fixed in RED as the counters
  rule requires: `BASE_FORMAT`/`BASE_LINT` set to 200, read from the gate's own
  `observed 200`. GREEN adds no source file, so 200/200/32 are also the post-GREEN
  values. The one remaining check, the uncommitted-`.luau` precondition, cleared
  with the RED commit: `project-counters: 41 passed, 0 failed`.
- **Flag for GATES and CI:** `session_channel_controls_test.luau` costs 61.6 s
  locally and the whole suite went from 2m17s to 3m20s (5m08s under RED's load).
  CI's last full gate run took 17m57s against `timeout-minutes: 45`, so there is room,
  but read the CI timing at REVIEW.

### GREEN notes (feature-developer)

- **Files changed:** `src/server/session/Session.luau` only, header included. No
  new source file, so the `harness` counters (200/200/32) stand. `Pings`,
  `PresetSends`, `Projection` and `RoundView` are unchanged; no test or
  `.claude/tests/**` file was touched.
- **`lune run test`:** `1344 passed, 0 failed` (was `1330 passed, 14 failed`) on the
  first full run after the change, 4m48s wall time.
- **Negative controls, measured against the shipped `Session`** (the test's own
  `[measured]` lines), next to RED's reference-stand-in figures:

  | Measurement | RED (reference) | GREEN (shipped) |
  |---|---|---|
  | AC-2 win | 150/150; max 64 s, max 150 steps; 1203 pings (0 refused, 0 declines), 1366 turns | `150/150 rounds won by showing; max 64 s deal-to-resolution, max 150 steps; 1203 pings (0 refused, 0 declines), 1366 turns` |
  | AC-2 control (`pings = false`) | 9/9 lost / clock at 420 s, 0 turns, 0 pings | `9/9 rounds lost / clock with no turn and no ping` (the test asserts the 420 s deadline, 0 turns and 0 pings per round; it passes) |
  | AC-6 sweep | 830 steps, 205 LensViews, 89 readings | `830 steps over 9 rounds; 205 LensViews carrying 89 readings inspected` (precondition >= 9 holds) |
  | AC-1 sequence | 6 LensView, 8 TurnCues, 14 silent, 2 alone | `6 LensView and 8 TurnCues sends expected over the sequence; 14 silent steps; 2 steps where one player alone was sent` |

  Every figure matches the table exactly. The AC-2 control now holds non-vacuously:
  the same module wins 150/150 with pings and loses 9/9 without them.
- **Choices beyond what the tests pin:**
  - The deal **does** reset `sent.lens` / `sent.cues` (C-6 says so; RED notes it
    is unobservable).
  - Outside `Round` with a ring still held (a leave that resolves the round below
    quorum), `sent.lens` / `sent.cues` are pruned to `assignment.players`, so "a
    player no longer in `assignment.players` loses their entries" holds in every
    phase, not only when views are rebuilt. The reference stand-in does not do
    this; no test observes the difference.
  - `roomLit` is `not Procedure.isDark(procedure, machine.room)` for the target
    machine's room, `true` for a doorway, as C-4 says. No test exercises a ping
    into a dark room (AC-3's accepted ping expects `true`), so the dark branch is
    unpinned; GATES or a later story may want a case.
  - Deep equality is a local structural `deepEqual` in `Session.luau`; there is
    no shared one in `src/`, and adding a module would move the harness counters.
  - Ignored turns no longer return early: every step except an external
    `SeatsAssigned` and a no-position `PresetSent` goes through the view build,
    as C-6 requires. They still return `{}` and a deep-equal state, as SLICE-005's
    tests require.
- **`bash scripts/gates.sh --fast`** (once, uncommitted tree; not recorded):

      PASS         format (1s, observed 200)
      PASS         lint (1s, observed 200, floor 1)
      PASS         typecheck (3s, observed 32)
      PASS         unit (290s, observed 1344, floor 507)
      UNCONFIGURED coverage
      PASS         build (0s, observed 128260)
      FAIL         harness (21s, exit 1)

  `harness` is `project-counters: 40 passed, 1 failed`, and the one failure is the
  precondition `the working tree carries no stray .luau files` with
  `actual:  M src/server/session/Session.luau`: the GREEN change is not committed
  (the dispatch said not to commit). RED hit the same check and it cleared with the
  RED commit. The counts it guards are as RED set them: 200 / 200 / 32. Expect
  `harness` to pass once GREEN is committed; re-run it then rather than taking this
  note's word for it.
- **Mechanisms named in the contract** (`Pings.targetPosition`, `Procedure.isDark`
  for `roomLit`, the non-yielding filter adapter, deep-equality change detection,
  `secondsLeft` ignored in the RoundView comparison) were all used as written. None
  needed changing.

**GREEN verification (lead-po, 2026-10-07).**

- Freeze: `frozen: OK — 190 path(s) unchanged since the snapshot for SLICE-006`
  (snapshot of every tracked file under `tests/` and `.claude/tests/`, taken right
  after `phase.sh set SLICE-006 GREEN`).
- `lune run test` (orchestrator): `1344 passed, 0 failed` in 4m15s. The only source
  change is `src/server/session/Session.luau`.
- **The handoff's discrimination table, checked against the shipped module** with
  `scripts/mutate.sh`, two mutations each predicted to fail exactly one test:
  - `s/pings = Pings.tick(channel.pings, now, state.tuning)/pings = channel.pings/`
    (`pingsNeverExpire`): `1343 passed, 1 failed` - `FAIL session_channel_test ::
    AC-3: an accepted setting ping ...`; `restored (verified byte-for-byte ...)`.
  - `s/pings = Pings.onCommitted(channel.pings, id)/pings = channel.pings/`
    (`pingsSurviveCommit`): `1343 passed, 1 failed` - the same AC-3 test;
    `restored (verified byte-for-byte ...)`.
  Both counts match the table. The suite is green again on the restored file
  (`git diff --stat src` unchanged: 404 insertions, 81 deletions).
- **Known gap, not an AC:** no test pings into a dark room, so the
  `roomLit = not Procedure.isDark(...)` branch is unexercised. `roomLit` only
  feeds the ping log the trace reads, so this goes to EPIC-09's trace story, not
  to a return to RED.

- GATES freeze: `frozen: OK — 190 path(s) unchanged since the snapshot for SLICE-006`; `git diff --stat src` empty after all three mutations (each restore verified by `mutate.sh`).
