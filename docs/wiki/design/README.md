# Design

How the game looks and behaves on screen, written so the Feature Developer can
implement it and a test (or a named Studio check) can hold it to account.
Owned by the Lead Designer. First pass: 2026-09-30, for M3, the playable
vertical slice.

## 1. Index

| File | Contents |
|---|---|
| [`tokens.md`](tokens.md) | colour (system, player palette, viewer-relative trim, contrast), the four alphabets (tags, settings, key classes, glyphs), preset icons, type, spacing, sizes, layers, motion, audio cue names |
| [`components.md`](components.md) | every M3 surface (C-01 to C-27): purpose, model, states with data and tokens, input per platform |
| [`layout.md`](layout.md) | orientation, safe area, `UIScale`, breakpoints, HUD regions, what reflows |
| [`accessibility.md`](accessibility.md) | the floor (A-1 to A-15), colour independence meaning by meaning, the pure tests (PT-*) and Studio checks (SC-*) |
| [`voice.md`](voice.md) | the few words there are, player-facing names, the trace headline's shape |

**Implementation.** `src/client/Theme.luau` implements `tokens.md` by name
(`architecture.md` §9.9). Models in `src/client/models/` are pure and tested
under `tests/client/` (`THEME-001` implements `tokens.md` and the PT-* checks
first); views in `src/client/views/` are verified by the SC-*
checks. A story's `## Design notes` cites component IDs, states and check IDs
from here rather than restating them.

## 2. What is decided

The one-line version: **hue belongs to people; everything the game says is
white, grey, light level, shape, pattern or position.** Tags are shapes, dial
settings are compass positions with pips, key classes are patterns (plus a trim
in *your* colour on your own machines and your partner's colour on theirs),
system states are achromatic light and glyphs, and the six player hues are
chosen to survive colour-blindness at the 4-player floor.

The round clock (C-19) and instability (C-20) are shown (Game Designer, Q-G1,
`tuning.md` §4 G8). The clock's *form* is taste-pending with the operator (T21);
C-19 builds the provisional default, a numeric `mm:ss` countdown with a brief
"−20" per penalty, and sits alone in its corner so a different form moves
nothing else.

Not decided here, on purpose: the tone of the dark (T15, M4). `tokens.md` §9
says what M4 may move.

## 3. Decisions, and what lost

| # | Decision | Alternative | Why it lost |
|---|---|---|---|
| D-1 | **Hue is reserved for players.** System state is achromatic | green for done, red for wrong, a hue per key class | the game has at most one colour channel a colour-blind player can rely on. Three alphabets on one machine cannot share it, and "red = wrong" collides with the vermillion player |
| D-2 | **Dial settings are compass positions with pips** | settings as colours (`mechanics.md` §1's example) | a ping *points at a position*, so position is the channel the fact already travels on. Colours would collide with player hues on the same dial, and fail colour-blind turners at the one moment that costs instability |
| D-3 | **Key class is a housing pattern, plus a viewer-relative trim** in your hue (yours) or your partner's hue (theirs), computed from your own `SeatView` against the machine's public `keyClass` | player colour = key-class colour, one palette | one colour would then mean two things on one machine (who turns it, and who pinged it), and a ping in the "wrong" colour would look like an error. The class-to-player mapping is not a secret (Game Designer: it is learnable by watching), so this is a legibility decision, not a trust one. Accepted, Q-G3 |
| D-4 | **Player hue by seat index**, Okabe–Ito-derived, the four most separable first | players choose; one fixed hue per account | chosen colours collide and need a lobby UI; at n = 4 this order keeps ΔE ≥ 28.6 under every simulated deficiency (`tokens.md` §1.2) |
| D-5 | **A dark scrim is the contrast guarantee**, one HUD theme | light and dark HUD themes; sampled contrast | the HUD floats over a scene it does not control; the floor is computed against white behind the scrim, which is the worst case |
| D-6 | **Preset panel is a 2 × 5 grid**, not a radial wheel | a 10-slice radial | ten icon-plus-word targets of ≥ 44 px do not fit a ring on a 568 × 262 phone; a grid does, maps to `1`–`0` and to native gamepad D-pad selection, and keeps fixed positions |
| D-7 | **Turning takes two actions**, and the dial control **pre-selects your helper's pinged detent** | one tap turns; or no pre-selection | a mis-tap costs clock and blackout risk, so one tap is too cheap; without pre-selection, floor sentence 3 ("turn it to that") asks a child to match a marker to a button |
| D-8 | **Ping aims at the centre reticle** with snapping and a private preview, on every platform | tap-on-world on touch | a tap on the world is also a camera drag; one targeting rule for all inputs is one thing to test, and the preview prevents the 10 s mis-ping |
| D-9 | Your **helper's ping is drawn through walls on your screen only**; preset beacons get edge chevrons **only for your helper and partner** | every ping and beacon through walls / at the edge | at n = 6 that is five competing markers; relevance is computed from your own seat view, so nothing leaks |
| D-10 | **"Wrong setting" and "not live yet" differ in glyph, place and sound**, shown to the turner only | a single "rejected"; a public diagnosis | T13 (`actuation_failure_is_diagnostic` = true); Q-G4 keeps it private |
| D-11 | The **progress bar never shares a row with a bar**; the clock is a number in another corner, and nothing combines the two | a clock bar next to it; a pace or "on track" line | `playtest.md: P-K` names "reads it as a timer and panics" as a failure |
| D-12 | **Landscape only** | portrait support | doubles every Studio check for a posture action games are rarely played in |
| D-13 | **Fredoka One for preset words**, Builder Sans elsewhere | one face | native chat is Builder Sans; a different face is the cheapest reliable "visually distinct" (C6), and it reads well for children |
| D-14 | **No lobby ready toggle** | a ready-up | the phase machine has no ready state (`architecture.md` §3). `Ready` is an intent preset only. Confirmed by the Lead PO, Q-P1 |
| D-15 | **"Partner" never appears on screen**; the label is "You help" | "partner" | the finale's "partner lamp" would make a child think they are related |
| D-16 | **Plain Instances, no UI package** | a Wally UI library | agrees with `architecture.md` D20. Nothing here needs one: the testable part is the pure models |

## 4. What could not be satisfied, or only partly

- **Colour-only at the ceiling.** Telling two *non-helper* pings apart at n = 6,
  for a colour-blind player, rests on hue and position alone (tritan ΔE 11.2 for
  sky/green). Pings may carry no text (CA-1), so no label can close it. Nothing
  at the floor depends on it. Accepted and recorded (`accessibility.md` §2).
- **Icons have no final delivery route** (Q-O1, with the operator). M3 assumes
  Unicode or emoji placeholders, each confirmed on a real phone by SC-W2.
- **Reduced motion and text size** depend on Roblox APIs this pass could not
  confirm (SC-A5); whether to add an in-game toggle if they are missing is with
  the operator (Q-O2).

## 5. Questions

### Answered, 2026-09-30

| # | Answer | Folded into |
|---|---|---|
| Q-G1 | clock and instability are shown: `hud_shows_round_clock`, `hud_shows_instability` (as `instability_max` pips), `hud_marks_blackout_thresholds`, `hud_clock_separate_from_progress`, all true. Clock form is T21 (operator), default numeric `mm:ss` with a brief −20 | C-19, C-20, `layout.md` §3, A-15 |
| Q-G2 | in the machine's room the arrow points at the machine; elsewhere at the next doorway on a shortest doorway path, ties to the lower-indexed next room (`mechanics.md` §3.2) | C-14, PT-N1 |
| Q-G3 | accepted: tags are shapes, settings are compass positions with pips, key classes are patterns, hue is for players; `mechanics.md` §1 reworded | `tokens.md` §0 |
| Q-G4 | the diagnosis goes to the turner only; everyone else gets one `sfx.fail` (the same for both kinds), the pips, and the dial snapping back | C-16, C-21, SC-W5 |
| Q-G5 | pre-selection kept, only for the helper's ping and only on the turner's own machine (`mechanics.md` §5) | C-16, PT-R1 |
| Q-G6 | a third form, "…for the other pair." (finale); `{s}` rounded down; step numbers in par's canonical order; fallback threshold `trace_headline_min_wait_seconds` = `room_traversal_seconds` | `voice.md` §3, C-24 |
| Q-G7 | the beacon stays where the preset was sent | C-12 |
| Q-P1 | no ready-up in M3; `Ready` is an intent preset only | D-14, C-26 |
| Q-P2 | the rematch card is shown during Post beside the trace, driven by `RoundView.phase`; `AcceptRematch` carries acceptance; `PromptRematch` (on leaving Post) dismisses it | C-25, `layout.md` §4, PT-R2 |
| Q-P3 | `seatOrder` is join order, so hue is stable from the lobby; it changes only if an earlier joiner leaves before seats are dealt, which is accepted | `tokens.md` §1.2, C-26 |
| Q-P4 | added to the `CHAN-001` spike | C-13 |

### Still open, with the operator

- **Q-O1.** Icons: (a) uploaded image assets, (b) Unicode or emoji placeholders,
  (c) UI primitives. M3 assumes (b), as recommended; (a) in M4.
- **Q-O2.** If Roblox's reduced-motion setting cannot be read from a script, add
  an in-game toggle? It would need persistence (M5), so M3 ships without.
- **T21** (the Game Designer's, shared with the Lead Designer): the clock's form.
  Only C-19 changes with the answer.
