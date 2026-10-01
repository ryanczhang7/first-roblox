# Layout

Where each HUD component sits, how the HUD scales, and what reflows. Component
IDs (C-nn) are `components.md`'s. Sizes are base values from `tokens.md` §5,
before `UIScale`.

---

## 1. Orientation and safe area

- **Landscape only** (`StarterGui.ScreenOrientation = LandscapeSensor`). A
  first-person-ish light-aiming game in portrait on a 5-inch phone leaves no room
  for the scene. Alternative rejected: supporting portrait doubles every Studio
  check for a posture almost nobody plays action games in.
- Every HUD `ScreenGui` uses `ScreenInsets = CoreUISafeInsets`, so nothing sits
  under Roblox's own top bar buttons, a notch or the home indicator. Positions
  below are within that safe area.

## 2. Scale and breakpoints

One root `UIScale` per `ScreenGui`, from a pure function of the safe-area size:

    uiScale(safeW, safeH) = clamp(min(safeW, safeH) / 390, 0.9, 1.3)

| Breakpoint | Rule | Typical device | What changes |
|---|---|---|---|
| `compact` | short side < 480 | phones | touch action cluster shown (if touch is enabled); relations strip shows chips only (no names); next turn cue hidden when a live cue is showing and the short side < 360 |
| `regular` | short side ≥ 480 | tablets, desktop, console | names beside chips; next cue always shown |

The breakpoint is a pure function of the same size (`Layout.breakpoint`, PT-L1).
Input type is independent of breakpoint: a touch-enabled tablet is `regular` and
still shows the touch cluster; a desktop window narrowed below 480 is `compact`
and does not.

Smallest supported safe area: **568 × 262** (a 4-inch phone in landscape after
Roblox's top inset). Every layout below must fit it at `UIScale` 0.9 without
overlap (SC-L1).

## 3. HUD regions during a Round

```
+--------------------------------------------------------------------------+
| [A relations strip]      [B progress bar]                    [E clock]    |
|                          [C live turn cue]                  [F pips]     |
|                          [C next turn cue]                                |
|                                                                           |
|<[G edge arrows]                 + reticle [D]                  [G]>       |
|                                                                           |
|                     [H dial control / preset panel]      [I touch cluster]|
|                                                             (Ping) (Say) |
+--------------------------------------------------------------------------+
```

| Region | Component | Anchor / position | Max size |
|---|---|---|---|
| A | C-04 relations strip | `AnchorPoint (0,0)`, `Position (0, 16, 0, 16)` | 2 chips + names: 240 × 56 |
| B | C-15 progress bar | `AnchorPoint (0.5,0)`, `Position (0.5, 0, 0, 16)` | 320 wide × 28 |
| C | C-14 turn cues | `AnchorPoint (0.5,0)`, below B with `space.3` | live 200 × 72; next 160 × 48 below it |
| D | C-06 reticle | screen centre | 20 × 20 |
| E | C-19 round clock (mm:ss) | `AnchorPoint (1,0)`, `Position (1, -16, 0, 16)` | 120 × 72, with the "−20" to its left |
| F | C-20 instability pips | under E, right-aligned, `space.2` below it | 120 × 40 (pips and blackout marks) |
| G | C-08 / C-12 edge arrows | clamped to a 24 px inset of the safe area | 48 × 48 each |
| H | C-16 dial control, C-10 preset panel | `AnchorPoint (0.5,1)`, `Position (0.5, 0, 1, -24)` | dial 288 × 288; panel 536 × 256 |
| I | C-09 touch cluster | `AnchorPoint (1,1)`, above-left of Roblox's jump button | 2 × 72 plus gap |

**E and F are decided** (Game Designer, Q-G1: `tuning.md` §4 G8). The clock's
*form* is still open with the operator (T21), so both stay anchored to the
top-right corner with nothing else positioned relative to them: a different form
for E, or hiding either, moves nothing outside the corner (SC-L2).

**B never shares a row with E.** The progress bar is the only bar-shaped thing on
the HUD. The clock is a number in a different corner (`hud_clock_separate_from_progress`), so a
child cannot read the progress bar as a timer (`playtest.md: P-K`'s "reads it as
a timer" failure).

**H holds one thing at a time.** Opening the preset panel closes the dial control
and the reverse; both are modal only in the sense that they take H.

## 4. Other phases

| Phase | Screen | Layout |
|---|---|---|
| Lobby | C-26 lobby panel | panel centred, max 560 × 320. The touch cluster keeps its Presets button (`Ready` is Lobby-legal) |
| Assignment → first `design.seat_card_seconds` of Round | C-05 seat card | centred, 480 × 200, over the Round HUD, then shrinks into region A |
| Resolution | none of its own | Resolution passes straight to Post; the outcome is C-24's header |
| Post | C-24 trace, C-25 rematch card | full safe area, scrim at transparency 0.12. `regular`: trace column max 560 wide on the left, rematch card 240 wide on the right. `compact`: one column, rematch card pinned under the trace header (never scrolls away). Presets button stays (Post presets) |

## 5. What reflows at `compact`

| Component | `regular` | `compact` |
|---|---|---|
| C-04 relations strip | chip + name + glyph | chip + glyph (names are not floor information) |
| C-14 turn cues | live and next stacked | at short side < 360, next is hidden while a live cue shows |
| C-10 preset panel | 2 × 5 tiles | unchanged (it is sized for compact) |
| C-24 trace | headline, par, timeline, guesses in one column, rematch card beside it | timeline scrolls horizontally inside its row; headline and par never scroll |
| C-26 lobby | names beside slots | chips only |

Nothing else reflows. Fewer layouts, fewer Studio checks.
