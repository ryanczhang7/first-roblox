---
id: EPIC-04
title: Every round is a new facility that a plain group can always finish in time
status: todo
stories: [TUNE-001, GEN-001, GEN-002, GEN-003, GEN-004]
---

## Goal

From a round's seed and its ring, the server generates a facility: rooms joined
by doorways, machines with tags and required settings, a Procedure of two
alternating tracks that ends in a finale needing four bodies, and **par** — the
time a group that does nothing clever needs. Every generated facility satisfies
every structural and timing invariant in `mechanics.md` §6 and `tuning.md`'s
invariant table, or the round does not start on it.

## Why now

A2 #4 puts difficulty in systems, and the generator is the hardest system in the
project (`mechanics.md` §6). Everything the Procedure, the channel and the views
do is a function of a generated facility, so it comes before them. It is also
where `loop.md` §1a's promise is enforced — the floor stays low because
`INV_traversal` refuses any facility a naive group could not finish.

## Done when

1. Every constant in `tuning.md` §2–§4 exists in `src/shared/MechanicsTuning.luau`
   with its specified value, and a changed value on either side fails a test
   naming it (`TUNE-001`).
2. For every seed in a fixed sample of at least 1,000 and every player count in
   `players_min..players_max`, the generated layout is connected and has
   `room_count` rooms (`GEN-001`).
3. For the same sample, tags are distinct within each key class and every
   machine has a required setting in `1..dial_settings` (`GEN-002`).
4. For the same sample, `INV_every_class_has_a_step`, `INV_balanced_steps`,
   `INV_track_alternates`, `INV_finale` and `INV_k_essential` all hold
   (`GEN-003`).
5. For the same sample, `par × schedule_slack ≤ round_seconds`, and a facility
   that violates it is never returned (`GEN-004`).
6. The same seed and ring always produce the same facility, and changing one
   stage's draws does not change another's.

## Stories

1. `TUNE-001` — Instance, channel and actuation constants match their
   specification.
2. `GEN-001` — A seeded facility layout is a connected graph of rooms with known
   distances.
3. `GEN-002` — Machines are placed with tags distinct within each key class and a
   required setting each.
4. `GEN-003` — The Procedure is two alternating tracks ending in a finale that
   needs four bodies.
5. `GEN-004` — Every generated facility can be finished inside the clock by a
   naive group.

## Deliberately not in this epic

- Geometry: turning a layout into Parts is `MAP-001`.
- Whether instances are *interesting*: `playtest.md: P-D`, a human judgement.
- A harder band: T17, none in v1.
