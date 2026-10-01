---
id: EPIC-05
title: Turning machines - the Procedure, the finale and the dark
status: todo
stories: [PROC-001, PROC-002, PROC-003, PROC-005]
---

## Goal

During a round the server runs the Procedure. A turn on a live step at its
required setting commits it. A turn on the wrong setting, or on a step that is
not live, is rejected with a reason the turner can learn from and costs one
instability point. A turn that fails a check before it is evaluated is refused
at no cost. The finale goes live for both tracks at once and commits only when
both machines are turned inside the window. Instability shortens the clock,
darkens rooms and can end the round. The round ends won, lost on the clock, or
lost to instability, with a deterministic reason the phase machine records
verbatim.

## Why now

This is the objective (`mechanics.md` §3, §5, §8). Without it there is nothing to
win or lose, and nothing but a test has ever sent the phase machine a
`RoundResolved`.

## Done when

1. A turn is judged only against server state. The key holder, within
   `turn_range_studs`, turning a live step to its required setting commits it
   (`PROC-001`, `PROC-005`).
2. An evaluated wrong turn (`wrong_setting` or `not_live`, for a decoy too)
   costs exactly one instability point. A refused turn (not the key holder,
   out of reach, a committed machine, a resetting dial, an armed finale
   machine) costs nothing and does not reset the dial (`PROC-001`).
3. The two finale steps go live together, only when every ordinary step is
   committed. Both commit only if both are turned correctly within
   `simultaneous_window_seconds`. Every failed finale attempt costs exactly
   one point, and a partner lamp shows when the other turner is within reach
   (`PROC-002`).
4. Each instability point removes `instability_clock_penalty_seconds`. Each
   threshold crossing darkens rooms by the specified weighted draw. The round
   ends at `instability_max`, and a single event resolves win, then
   instability, then clock (`PROC-003`).
5. The `Turn` remote is declared at `turn_rate_limit_seconds`, validated, and
   judged against the server's accepted positions (`PROC-005`).

## Stories

1. `PROC-001` — A turn commits a live step on the right setting and says why it
   failed otherwise.
2. `PROC-002` — The finale commits only when both machines are turned inside the
   window.
3. `PROC-003` — Instability shortens the clock, darkens rooms and ends the round
   in a fixed order.
4. `PROC-005` — A turn arrives as a validated remote and is judged against
   server positions.

The gap in numbering is deliberate. `PROC-004` ("a round that can no longer be
finished in time ends as unwinnable") was drafted in this planning pass and
dropped before it was committed. The Game Designer withdrew the clock arm of
`unwinnable` (`mechanics.md` §8, G6), and its structural arm cannot occur while
quorum holds, so M3 has nothing that could trigger it.

## Deliberately not in this epic

- How a turn looks and sounds (`HUD-002`). The tone of the dark is M4 (T15).
- Wiring into the session (`SLICE-005`).
- `unwinnable`: the phase machine still accepts it, but nothing in M3 emits it.
