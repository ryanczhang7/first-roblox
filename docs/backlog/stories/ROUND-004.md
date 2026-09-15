---
id: ROUND-004
title: The lobby holds below the minimum and admits no more than the maximum
slug: the-lobby-holds-below-the-minimum-and-ad
epic: EPIC-01
type: feature
status: todo
phase: PLANNED
branch: story/ROUND-004-the-lobby-holds-below-the-minimum-and-ad
depends_on: [ROUND-003]
required_gates: []
---

## Context

`players_min` is 4 and `players_max` is 6 — ratified in product-brief §0c R1, and
derived rather than preferred: 4 is the smallest ring in which the two-layer
puzzle has room (`loop.md` §2), and 6 is where channel contention turns the shared
signal stream from a channel into noise. A4's "target 8–12, cap 16" came from
hidden-role faction ratios that amendment 8 removed and is **withdrawn, not
scaled**.

This story teaches the phase machine those two numbers. It is deliberately
separate from `ROUND-003` because the *behaviour* is separate and each is one
clean cycle: the lifecycle advances on a clock, the lobby gates on a count.

The one non-obvious rule is the hold. **Below `players_min`, the lobby timer holds
rather than resetting.** `lobby_seconds` is a floor on lobby dwell time — time for
players to gather and socialise (A4) — not a punishment for a late fourth player.
A resetting timer means a lobby that gains and loses a player every 30 seconds
never starts, which is precisely the M6 lobby-fill risk amendment 1 was lowering
the floor to reduce.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a lobby with `players_min − 1` players, when the clock is
  advanced well past `lobby_seconds`, then the phase is still `Lobby`.
- **AC-2** — Given that lobby, when one more player joins so the count reaches
  `players_min`, then the phase becomes `Assignment` on the next tick **without
  waiting a further `lobby_seconds`** — the elapsed lobby time already served is
  not discarded.
  *Control:* an implementation that resets `phaseEnteredAt` on every join **must**
  fail this, and must pass AC-1. A test that only asserts "it eventually starts"
  cannot tell the two apart; assert the `now` at which it starts.
- **AC-3** — Given a lobby that reached `players_min`, when a player leaves before
  `lobby_seconds` has elapsed and the count drops below `players_min`, then the
  phase stays `Lobby` past `lobby_seconds`, and when the count is restored the
  round starts on the next tick.
- **AC-4** — Given a lobby holding `players_max` players, when another
  `PlayerJoined` arrives, then the seated list still holds exactly `players_max`
  players and the surplus player is not among them.
- **AC-5** — Given a lobby, when the same `PlayerJoined` event for one player is
  applied twice, then that player appears once in the seated list.
- **AC-6** — Given a seated list, when players join and leave in any order, then
  the relative order of the remaining players is unchanged.
  *Semantics:* seat order is the order of joining. `SEAT-001` deals the ring from
  this list, so a list whose order depends on removal mechanics makes a round's
  ring depend on something nobody specified.

## Contract

Extends `src/server/round/PhaseMachine.luau` from `ROUND-003`. No new module and
**no signature change** — `step` keeps `(state, event, now) -> (state, {Effect})`,
so there is no caller list to grep.

### The rules, exactly

- **`PlayerJoined`** appends to `state.players` if the player is not already
  present and `#players < playersMax`. Otherwise the state is returned unchanged
  with an empty effect list — a rejected join is not an error (`ROUND-003` AC-7).
- **`PlayerLeft`** removes the player, preserving the order of the rest.
- **`phaseEnteredAt` is never rewritten by a join or a leave.** This is the hold,
  and it is one line. It is also the line a plausible implementation gets wrong in
  the other direction, which is why AC-2 asserts the *time* the round starts and
  not merely that it starts.
- The `Lobby → Assignment` guard is `now - phaseEnteredAt >= lobbySeconds and
  #players >= playersMin`, evaluated on every step, so a join that satisfies the
  count after the time has already elapsed starts the round on the next tick.
- **Rejecting the surplus join at the door is the machine's job**, not the
  driver's. A driver that filters is a driver that can forget.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1..AC-4 | **Settled** | 4 and 6 are derived and ratified (`tuning.md` §1, product-brief §0c R1). Read them out through `RoundConfig`; do not pick numbers, and do not hard-code 4 or 6 in a test where the config value belongs. |
| AC-2 | **Settled, with a control** | The control distinguishes hold from reset. It is the only criterion here a wrong implementation passes half of. |
| AC-5, AC-6 | **Mechanical** | Pin exactly. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None.
-->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

Brief RED that AC-1–AC-4's numbers are **settled** — they were derived by the Game
Designer from channel contention and ring length, and ratified by the Lead PO.
There is nothing to calibrate. The single oracle-free judgement is how AC-2's
control is phrased so that a resetting implementation cannot pass it.

## Out of scope

- Matchmaking, queueing, or what happens to the rejected surplus player. There is
  no server list and no lobby browser; a rejected join simply is not seated.
- Private servers (A6, product-brief §0c R5). A product decision, M5.
- The mid-round quorum rule. `ROUND-005`.
- Seat assignment from the seated list. `SEAT-001`.
- Any player-facing feedback about a full lobby. No UI exists.

## Game design

Implements `tuning.md` §1's `players_min` (4, derived) and `players_max` (6,
derived) and `loop.md` §2's derivation of the band.

The decision AC-2 protects is **M6's lobby-fill risk**, which the brief names as
the highest-risk assumption in the plan. A 4-player floor roughly halves the
concurrent-player density a round needs; a resetting lobby timer would give a
chunk of that back for no design benefit.

Note for M3: `players_max` 6 is derived but its **exact boundary is soft** —
`playtest.md: P-N` reads where channel contention actually bites. If that playtest
moves the number, it moves in `tuning.md` and then in `ROUND-002`'s module, and
this story's tests should still pass unchanged. If they do not, a test hard-coded
a number instead of reading the config.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Make `PlayerJoined` set `phaseEnteredAt = now`. Predicted: AC-2 goes red,
   AC-1 stays green. This is the hold-versus-reset mutation and it is the one
   assertion in the story that a weak test would miss.
2. Remove the `#players < playersMax` check. Predicted: AC-4 goes red.
3. Change the duplicate-join guard to always append. Predicted: AC-5 goes red.

**Raise the `unit` floor** to the new real count.
