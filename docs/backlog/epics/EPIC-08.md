---
id: EPIC-08
title: Four humans finish a round in Studio
status: todo
stories: [SLICE-005, SLICE-006, MAP-001, HUD-001, HUD-002, HUD-003, HUD-004, SLICE-007]
---

## Goal

The M3 definition of done (brief §0c R2): **four humans complete a full round
end-to-end in Studio.** The session composes everything EPIC-04 to EPIC-07
built; a generated facility becomes blockout rooms the players walk; the HUD
shows each player their turn cues, the progress bar, pings and presets; a player
can turn a machine and a helper can see its glow; and the round ends in a win or
a loss the players understand.

## Why now

It is the milestone. Everything before it is verified headlessly; this is the
first time the game is played.

## Done when

1. A headless test drives four scripted players through a generated facility to a
   win, and another to a loss by instability, through `Session.step` alone
   (`SLICE-005`, `SLICE-006`, `unit`).
2. The scripted win uses pings as the only way a setting reaches its turner:
   removing the pings from the script makes it fail or guess (`SLICE-006`).
3. A generated facility is built as walkable blockout geometry, with every
   machine at its generated room and position (`MAP-001`).
4. Every HUD element's view model is unit-tested against the design tokens and
   the "never show" rules (`HUD-001` to `HUD-004`).
5. **Four humans complete a round in Studio, and the operator records the
   session**: the outcome, the time, and each Studio check named by the stories
   above (`SLICE-007`).

## Stories

1. `SLICE-005` — The session runs the facility and the Procedure, and scripted
   turns win or lose a round.
2. `SLICE-006` — The session carries pings, presets and every view, and a
   scripted round is won by showing.
3. `MAP-001` — A generated facility becomes blockout geometry the players can
   walk.
4. `HUD-001` — The HUD shows private turn cues and the public progress bar.
5. `HUD-002` — A player can turn a machine and a helper sees the glow.
6. `HUD-003` — A player can ping and sees whose ping is whose.
7. `HUD-004` — A player can send a preset from the wheel and everyone sees it.
8. `SLICE-007` — Four humans complete a full round in Studio.

## Deliberately not in this epic

- The post-round trace (EPIC-09); `Post` shows the outcome only until then.
- Lighting, fog, audio mixing, camera, the tone of the dark: M4.
- Creator Store assets: blockout only (`architecture.md` §10; an operator
  question).
- Playtest protocols (`playtest.md`): the slice makes P-D, P-K, P-Q and P-S
  runnable; running them is the operator's, after this epic.
