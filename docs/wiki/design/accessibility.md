# Accessibility floor

Not a feature and not a story: the floor every user-facing M3 story is measured
against. Every rule names how it is checked, either by a **pure test** (PT-*, a
Lune test over a model in `src/client/models/` or over `Theme.luau`) or by a
**named Studio check** (SC-*, run by a human in Studio, result pasted into the
story). A rule with neither is not on this page.

The audience is everyone, children included; the youngest floor player is 7
(brief §0d #14, T19). About 80% of Roblox sessions are on phones.

---

## 1. The rules

| # | Rule | Measure | Checked by |
|---|---|---|---|
| **A-1** | **Touch targets** | every interactive control ≥ 44 × 44 rendered px at the smallest supported safe area (568 × 262), which follows from `size.target.min` 56 × `UIScale` floor 0.9 = 50.4 | PT-A2 (tokens × scale floor), SC-L1 |
| **A-2** | **Text size** | no rendered text below 16 px at any supported safe area (`type.caption` 18 × 0.9 = 16.2). `TextScaled` is not used | PT-A3, SC-A1 |
| **A-3** | **Contrast, HUD** | text ≥ 4.5:1 and glyphs, large text and control boundaries ≥ 3:1, **against the worst composite** (scrim at transparency 0.12 over `#FFFFFF`), not against a sample | PT-A1 (every pairing in `tokens.md` §1.4, computed), SC-A2 |
| **A-4** | **The scrim is the guarantee** | every HUD element carrying text or a glyph has an ancestor or own background of `color.surface.scrim` at transparency ≤ 0.12 | PT-A4 (Theme values); SC-A2 (Instance tree) |
| **A-5** | **Never colour alone** | every meaning carried by hue is carried by something else too (table §2) | PT-T3, PT-T4, per-model tests in §2 |
| **A-6** | **Never sound alone** | every audio cue has a visual equivalent (`tokens.md` §8) | PT-A5 (the cue table has a visual for every row), SC-A3 (play a round muted) |
| **A-7** | **Reduced motion** | when reduced motion is on: no pulse, shake, scale or slide; opacity may change; every state stays distinguishable | PT-A6 (each model given `reducedMotion = true` returns no transform motion and a static glyph where a pulse was), SC-A4 |
| **A-8** | **No reading at the floor** | every element the floor needs (`loop.md` §1a's three sentences) has an icon or glyph, and its words are optional redundancy | PT-A7 (every model output a floor component returns has a non-nil `iconKey`/glyph; a test renders the floor set with all words blanked and asserts nothing floor-relevant is lost), `playtest.md: P-K` |
| **A-9** | **No memory at the floor** | who your helper/partner is, what is live, and your helper's ping stay on screen until they stop being true | C-04 persists; C-14 until commit; C-07 for `ping_display_seconds`. PT per model; P-K's memory reading |
| **A-10** | **Every action from every input** | touch, keyboard/mouse and gamepad each reach: move, look, ping, open presets, send each preset, turn, choose each detent, accept rematch, dismiss the seat card | SC-K1 (keyboard only), SC-K2 (gamepad only), SC-K3 (touch only) |
| **A-11** | **Focus** | every control has a visible focus state (`stroke.focus`, 3 px white, ≥ 3:1 against `color.surface.raised`); disabled controls are not focus stops; panels return focus to the game on close | PT-A8 (tile/button models expose focus state; disabled ⇒ not selectable), SC-K2 |
| **A-12** | **Legible in the dark** | lamps, the lens glow and ping markers are emissive and readable in a blacked-out room from `lens_read_range_studs`; paint (tag, pattern, dial) is not readable at range there, by design (`mechanics.md` §1) | SC-W1 |
| **A-13** | **Readable on a 5-inch phone** | tag glyph, detent pips and the lens glow can be told apart by a first-time player at `lens_read_range_studs` on a 5-inch phone | SC-W2 |
| **A-14** | **Preset compliance, visible** | preset words are the table's, never punctuated; in chat they are labelled "system preset" and set in a different face | PT-C6 (`PresetChatModel.line`), SC-C1 |
| **A-15** | **The bar is not a timer, and nothing combines it with the clock** | the progress bar has no continuous motion, no number, and no neighbour that is a bar; the clock is a number in another corner; nothing on the HUD derives pace, "on track" or a forecast from the two (`hud_clock_separate_from_progress`) | PT-P1, PT-K1, SC-L2 |

**Reduced motion and text size in Roblox.** The client reads the player's
reduced-motion preference and preferred text size from Roblox's accessibility
settings (reported as `GuiService.ReducedMotionEnabled` and
`GuiService.PreferredTextSize`; SC-A5 confirms the API names in Studio before a
story depends on them). Preferred text size multiplies the type scale only,
never the layout, and the layout must survive its largest value (SC-A5). If the
API is not there, a settings toggle is **not** added in M3 (Q-O2).

## 2. Colour independence, meaning by meaning

| Meaning | Hue | Non-colour carrier | Test |
|---|---|---|---|
| this ping is my helper's | helper's hue | `glyph.eye` badge, pulse, `alwaysOnTop`, edge arrow, `sfx.ping.helper` | PT on `PingModel`: badge iff sender = `supplierId` |
| this ping is mine | my hue | white outer ring | PT on `PingModel` |
| whose ping (other players) | their hue | where it is, and the avatar standing near it. **Hue only at distance: accepted gap** (see below) | — |
| this machine is mine / my partner's | trim in my / partner's hue | `glyph.key` / `glyph.eye` badge | PT on `MachineModel` |
| which key class | none | pattern | PT-T4 |
| which tag | none | shape | PT-T4, PT-T5 |
| which setting | none | compass position + pips | PT-T6 |
| live / committed / idle | none | lamp lit / ✓ lit / nothing lit | PT on `MachineModel` |
| my helper / my partner (people) | their hue | badge glyph over the avatar; chip glyph in C-04 | PT on `PlayerMarkerModel`, `RelationsModel` |
| wrong setting vs not live yet | none | glyph (✕ vs hourglass), place (detent vs hub), shake, sound | PT on `DialControlModel` |
| preset sender | stripe in their hue | position (over them) and their name | PT on `PresetBubbleModel` |

**Accepted gap.** For a colour-blind player at n = 6, telling apart two
*non-helper* pings of close hues (sky/green for tritanopes) relies on position.
Nothing at the floor needs it: the floor only needs "is it my helper's", which
has four non-colour carriers. Pings have no text by rule (CA-1), so a name label
is not available to close it. Recorded so it is a decision.

## 3. The checks

### Pure tests (PT)

Each is a Lune test the Feature Developer's first client story can own.

| ID | Asserts |
|---|---|
| PT-A1 | `contrast(fg, composite(scrim, 1 − 0.12, #FFFFFF))` meets the floor for every pairing in `tokens.md` §1.4, from `Theme.luau`'s values (WCAG 2 relative luminance) |
| PT-A2 | every target size token × 0.9 ≥ 44 |
| PT-A3 | every type token × 0.9 ≥ 16 |
| PT-A4 | `Theme` scrim transparency ≤ 0.12 |
| PT-A5 | every audio cue in `Theme`'s cue table has a non-empty visual equivalent |
| PT-A6 | with `reducedMotion = true`, no model returns a scale, position or rotation tween, and every model that pulses returns a static glyph instead |
| PT-A7 | every floor component's model returns an icon or glyph key for every state it can be in |
| PT-A8 | a disabled tile/button model reports `selectable = false` |
| PT-T3 | no system colour token has HSV saturation > 0.15; player hue tokens are used only by trim, markers, stripes, rings and swatches |
| PT-T4 | the icon-key sets for tags, class patterns, system glyphs and preset icons are pairwise disjoint |
| PT-T5 | `#tag alphabet ≥ ceil(actuator_count / players_min)` from `MechanicsTuning` |
| PT-T6 | detent layout for `dial_settings` = 2..6 (angles `360 / n` from the top, pips = index); 7 or more is rejected |
| PT-T7 | player hues: pairwise CIE76 ΔE ≥ 30 in normal vision, and ≥ 10 under Machado protan/deutan/tritan simulation (severity 1.0); seats 1–4 ≥ 25 under all four; each hue ≥ 15 from `#FFFFFF` and `#8A93A0` under all four |
| PT-P1 | `ProgressModel.segments` accepts only `{ committed, total }` (a type check plus a runtime assertion that no other key is read), fills exactly `committed`, marks exactly the last `procedure_tracks` |
| PT-C6 | for every preset: `PresetChatModel.line` contains "system preset", the word is unmodified, no line ends in `.`, `!` or `?`, and a name containing `<b>` is escaped |
| PT-L1 | `Layout.uiScale` and `Layout.breakpoint` at 568 × 262, 667 × 339, 1024 × 700, 1920 × 1000 |
| PT-K1 | `ClockModel`: `mm:ss` floored and never negative (e.g. 419.6 → `6:59`, −1 → `0:00`); a penalty yields U+2212 followed by `instability_clock_penalty_seconds` from `MechanicsTuning`; the model takes no progress input |
| PT-I1 | `InstabilityModel.pips`: `instability_max` pips, exactly `instability` filled, `marksBlackout` exactly at multiples of `instability_blackout_threshold`, no room identity in the output |
| PT-N1 | `TurnCueModel` arrow target: the machine when in its room; otherwise the next doorway on a shortest doorway path, ties to the lower-indexed next room, over a hand-built layout that includes a tie and a dark room (which changes nothing) |
| PT-T8 | `design.turn_prompt_studs` ≤ `turn_range_studs` |
| PT-R1 | `DialControlModel` pre-selects a detent only for a setting-ping by `supplierId` on a machine in the viewer's `keyClasses`; a ping by anyone else, or on another machine, pre-selects nothing |
| PT-R2 | `RematchModel` is visible iff phase = "Post" and no `PromptRematch` has arrived since |

Plus the per-model tests named in `components.md` (aim picking, edge-arrow
placement, beacon edge rule, seat-change diff, trace has no player hue).

### Studio checks (SC)

Run by a human in Studio's device emulator unless stated. Each result is pasted
into the story that builds the component, with the device and settings used.

| ID | Check | Passes when |
|---|---|---|
| SC-L1 | every HUD state at 568 × 262 (smallest phone) and 1920 × 1080 | nothing overlaps, nothing clips, every target ≥ 44 px (measure `AbsoluteSize`) |
| SC-L2 | set C-19 and C-20 `Visible = false`, then swap C-19 for a wider placeholder | nothing outside the top-right corner moves; the progress bar has no bar-shaped neighbour |
| SC-A1 | read every HUD string on the 5-inch emulator profile at 100% zoom | all legible; smallest `TextBounds` height ≥ 16 |
| SC-A2 | stand in the brightest spot of the map and against a white wall | all HUD text readable; every text element has the scrim ancestor |
| SC-A3 | play a full round with the sound muted | every event that has a cue was noticed |
| SC-A4 | enable reduced motion in Roblox settings | nothing pulses, shakes or slides; all states still distinguishable |
| SC-A5 | confirm the reduced-motion and preferred-text-size API names; set text size to largest | text grows, layout holds at 568 × 262 |
| SC-K1 | keyboard and mouse only | every action in A-10 done; focus always visible |
| SC-K2 | gamepad only | every action in A-10 done; panels take and return selection |
| SC-K3 | touch only (phone emulator) | every action in A-10 done |
| SC-W1 | black out a room; stand at the door and at `lens_read_range_studs` | lamps and pings visible from the door; tag, pattern and dial are not; up close with your light they are; no lens glow in the dark room |
| SC-W2 | on a real 5-inch phone, a person who has not seen the game names the tag, the lit detent and the pips from `lens_read_range_studs` | correct on first try, three machines out of three |
| SC-W3 | four clients: one pings a setting | the partner sees the helper badge and edge arrow; the other two do not; the helper sees their own ring |
| SC-W4 | colour-blind simulation (a screenshot of a 6-player round through a CVD simulator) | all six ping hues distinguishable from each other and from white under deutan and protan |
| SC-C1 | send each preset with CA-6's route on | chat shows "system preset", the name, the word in Fredoka One, no punctuation |
| SC-W5 | four clients: one player turns a live machine to a wrong setting, then a not-live machine | only the turner sees ✕ then the hourglass; every client hears the same `sfx.fail` twice and sees two pips fill; players with the machine in view see its dial snap back |
| SC-S1 | two players at one machine | each sees their own trim; only the helper sees the glow |
