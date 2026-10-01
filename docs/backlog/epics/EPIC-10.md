---
id: EPIC-10
title: A dropped connection is not a dropped round
status: todo
stories: [SEAT-004, HUD-006]
---

## Goal

A player whose connection drops mid-round and comes back within
`disconnect_grace_seconds` gets their seat back. Anyone arriving later spectates
until the next round. Players whose seat changed are told what changed: the
supplier who inherited a key class, and the partner who has lost their helper.
SEAT-003 built the pure rules. This epic wires them into the running session and
onto the screen.

## Why now

It follows the M3 definition of done (`SLICE-007`), which does not need it. For
an all-ages audience on mobile, though, a flaky connection is normal
(brief §0d #14; ~80% of sessions are mobile). `mechanics.md` §8 specifies
the rules, and a round that silently breaks when one child's phone hiccups is a
bounce A5 counts against us.

## Done when

1. A player who rejoins within `disconnect_grace_seconds` is re-seated from the
   stored absence, and every changed view is re-sent (`SEAT-004`).
2. A player who rejoins after the grace window spectates: they receive public
   views only, and every remote they call is rejected for `identity`
   (`SEAT-004`).
3. The inheriting supplier and the helperless partner each see the
   seat-change notice. A spectator sees the banner (`HUD-006`, `unit` plus a
   recorded Studio check).

## Stories

1. `SEAT-004` — A player who returns within the grace window gets their seat
   back, and a late one spectates.
2. `HUD-006` — A player whose seat changed, or who is spectating, is told so.

## Deliberately not in this epic

- Surviving a server restart, which needs persistence (M5).
