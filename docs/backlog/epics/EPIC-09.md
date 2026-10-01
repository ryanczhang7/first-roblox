---
id: EPIC-09
title: The round teaches - the post-round trace
status: todo
stories: [TRACE-001, TRACE-002, ROUND-007, HUD-005]
---

## Goal

When a round ends, everyone sees the same short account of it for
`post_round_seconds`: one sentence a child can read naming the longest wait and
what it waited for, the group's time against par, a timeline of every step
labelled *waiting for helper* or *waiting for turner*, and the guesses and
whether they were right. It names steps and machines, never players (T14), and
it ends with the rematch prompt.

## Why now

The trace is the lesson of a failed round (`loop.md` §1.5) and the visible skill
ceiling of a won one (par). A5 calls the post-round window "the highest-value
thirty seconds in the product". It depends on the logs EPIC-06 and EPIC-05
write, so it comes after the slice.

## Done when

1. The trace is a pure function of the facility, the logs and the outcome, and
   each step's timeline and gap labels follow from the logs alone (`TRACE-001`).
2. Guesses — turns with no helper ping on that machine — are listed with whether
   they were right (`TRACE-001`).
3. The headline names the longest wait and its kind; par against actual uses the
   facility's stored par; the trace type has no player field (`TRACE-002`).
4. A seated player can accept a rematch once during `Post` through a validated
   remote, and every client sees who has accepted (`ROUND-007`).
5. In Studio, every client shows the trace for `post_round_seconds` and a rematch
   prompt, and the whole group returns to the lobby together when `Post` ends
   (`HUD-005`, recorded by the operator).

## Stories

1. `TRACE-001` — The trace times every step and labels who was waiting.
2. `TRACE-002` — The trace leads with one sentence and par against actual,
   naming no player.
3. `ROUND-007` — A seated player can accept a rematch once during Post.
4. `HUD-005` — The post-round screen shows the trace and the rematch prompt.

## Deliberately not in this epic

- Season progress, XP, leaderboards: M5.
- Whether anyone reads the trace, and whether a child understands it:
  `playtest.md: P-T`, a human reading.
