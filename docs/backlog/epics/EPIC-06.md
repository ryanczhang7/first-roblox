---
id: EPIC-06
title: Show, don't tell - pings and presets that comply for all ages
status: todo
stories: [CHAN-001, CHAN-002, CHAN-003, CHAN-004, CHAN-005, CHAN-006]
---

## Goal

Players communicate with no free-form text and no fact-bearing words: a **ping**
points at a dial setting, a machine or a doorway, in the sender's colour; a
**preset** from a wheel of ten states an intent, shown over the sender and at
their position. Every rule the preset-system guidelines make countable is a
test, so the channel is compliant by construction for every age (brief §0d #19,
#14).

## Why now

The channel is how a fact crosses from one head to another (`mechanics.md` §4.0).
It is also the part of the design with a platform-compliance obligation, and the
reason M3 had to be re-planned. Two engineering facts are unconfirmed (CA-6), so a
spike leads the epic.

## Done when

1. The filter API shape and the preset delivery route are confirmed against
   Roblox documentation and recorded (`CHAN-001`).
2. The preset table matches `mechanics.md` §4.2 exactly and passes C1, C2, C6
   and C8 as tests (`CHAN-002`).
3. `SendPreset` (`CHAN-004`) is declared at `preset_rate_limit_seconds`, proven against
   `tuning.md`; it carries no recipient; one limiter per player spans the wheel;
   a preset outside its own phases is refused.
4. A call its handler declines (a refused ping target, an out-of-phase preset,
   a failed filter) costs the one-second attempt floor but not the ten-second
   send cooldown (`CHAN-003`); a preset whose filtering fails is not sent and
   the sender is told (`CHAN-004`).
5. `Ping` is declared at `ping_rate_limit_seconds`, proven against `tuning.md`,
   and accepted only at an existing target of the named kind, within
   `ping_range_studs` and in line of sight of the server's position for the
   sender (`CHAN-005`).
6. Each player has at most one active ping; it expires after
   `ping_display_seconds`, clears when its machine commits, and is replaced by
   the sender's next ping; every ping is logged (`CHAN-006`).

## Stories

1. `CHAN-001` (spike) — Confirm the preset delivery route and the filter call
   shape.
2. `CHAN-002` — The preset table obeys the countable preset-guideline rules.
3. `CHAN-003` — A call its handler declines costs the attempt floor but not the
   send cooldown.
4. `CHAN-004` — A preset is filtered and broadcast with its sender and position
   once per ten seconds.
5. `CHAN-005` — A ping is accepted only at a real target in range and in sight.
6. `CHAN-006` — Each player has at most one live ping and it clears when it
   should.

## Deliberately not in this epic

- Whether groups bend presets into codes: `playtest.md: P-S`, a human reading.
- `ping_settings_live_only`: declined by the operator (T20 = (a)).
- Any age or chat-eligibility gate: excluded by §0d #19(a).
