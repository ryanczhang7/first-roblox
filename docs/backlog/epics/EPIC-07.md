---
id: EPIC-07
title: Each player is told only what is theirs to know
status: todo
stories: [VIEW-001, VIEW-002, VIEW-003, VIEW-004]
---

## Goal

Every client receives exactly what its player may know and nothing more: its own
lens contents (the required settings of its partner's machines, only where it is
standing and only in a lit room), its own turn cues, and a public round view
whose progress bar is two numbers. Positions the server bases these on are
checked for plausibility, because a position is a claim.

## Why now

`roles.md` §6: a client that can read another player's lens "has not cheated at
a scoreboard, it has deleted the game." M3 introduces the two per-player secrets
the design is made of — required settings and turn cues — and the moment they
exist is the moment the allowlist must hold them.

## Done when

1. For every player in a large seeded sample, the lens view contains no required
   setting of a machine outside that player's lens class, out of range, out of
   sight or in a dark room (`VIEW-001`).
2. A player's turn cues name only machines of their own key classes, and only
   the live step and the next within `turn_cue_lookahead` (`VIEW-002`).
3. The public round view contains no required setting of an uncommitted machine,
   no σ, no track or step order, and its progress bar is exactly
   `{ committed, total }` (`VIEW-003`).
4. A position sample that could not have been walked to is not used by any range
   rule (`VIEW-004`).

## Stories

1. `VIEW-001` — A player's lens view holds only settings their lens may read from
   where they stand.
2. `VIEW-002` — A player's turn cues name only their own live and next machines.
3. `VIEW-003` — The public round view carries public facts and a progress bar of
   exactly two numbers.
4. `VIEW-004` — An implausible position is not trusted for any range check.

## Deliberately not in this epic

- Rendering any of it (`HUD-*`).
- Streaming or proximity-filtered replication of public facts (`architecture.md`
  D15).
