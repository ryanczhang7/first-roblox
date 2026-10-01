---
id: EPIC-03
title: A real place runs the round, and four Studio clients see the same phase
status: todo
stories: [SLICE-001, SLICE-002, SLICE-003, THEME-001, SLICE-004, HUD-007]
---

## Goal

The M0–M2 core — phase machine, ring, projection, validation pipeline — runs
inside a real Roblox place for the first time. Players join a Rojo-served place
in Studio, the lobby counts them in, seats are dealt, each client is told its own
seat and nobody else's, and every client shows the same phase and countdown until
the round ends by the clock. No gameplay yet: this is M3's walking skeleton.

## Why now

Nothing in this repository has executed in a Roblox runtime (`architecture.md`
§1, "The limit"). Every other M3 epic ends in something a human must see in
Studio, so the runtime spine — requires resolving in a place, remotes bound
through the wrapper, secrets routed to one client — must be proven before
anything is built on it. It is also the cheapest place to find out that an
assumption about the platform is wrong.

## Done when

Clause by clause, each observable:

1. A module in `src/server/` and one in `src/client/` each require a
   `src/shared/` module inside a real place, and the result is recorded in
   `architecture.md` §1 (`SLICE-001`).
2. Every declared remote is connected exactly once, only through
   `Wrapper.guard`, and only in `src/net/` (`SLICE-002`, `unit`).
3. A per-player payload can only be sent to its own player; broadcasting one
   raises (`SLICE-002`, `unit`).
4. A pure `Session` deals seats from the round's seed and emits one seat view per
   seated player, addressed to that player, plus a public round view
   (`SLICE-003`, `unit`).
5. The design tokens exist in `src/client/Theme.luau`, match `docs/wiki/design/tokens.md`,
   and pass every token-level check of the accessibility floor (`THEME-001`,
   `unit`).
6. In Studio, four clients each show the current phase and a countdown that
   agrees across clients to within a second; the round ends by the clock and
   returns to the lobby (`SLICE-004`, recorded by the operator).
7. The lobby panel shows who is waiting against `players_min`, and at
   `Assignment` each client's seat card names its own helper and partner, then
   stays on screen as the relations strip (`HUD-007`, `unit` plus a recorded
   Studio check).

## Stories

1. `SLICE-001` (spike) — A module requires across layers inside a real
   Rojo-served place.
2. `SLICE-002` — Every declared remote is bound through the wrapper and secrets
   reach only their player.
3. `SLICE-003` — The session deals seats and sends each player only their own
   seat view.
4. `THEME-001` — Design tokens exist in source and meet the accessibility floor.
5. `SLICE-004` — Four Studio clients see the phase, the countdown and their own
   seat card.
6. `HUD-007` — The lobby panel and the seat card show who is waiting and who your
   helper and partner are.

## Deliberately not in this epic

- Any machine, ping, preset or map geometry (EPIC-04 to EPIC-08).
- Proximity voice: amendment 3 removed it from v1; brief M3's "proximity voice
  wired" is void.
- Telemetry to a live sink: `Sink.noop()` until M5.
