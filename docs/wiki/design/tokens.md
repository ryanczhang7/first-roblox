# Tokens

Every value the client draws with, by **role**, never by appearance.
`src/client/Theme.luau` implements this file by these names, the way
`MechanicsTuning.luau` implements `tuning.md` (`architecture.md` §9.9). If the
module and this file disagree, that is a defect: raise it with the Lead PO rather
than editing either to match.

Durations that are **game rules** are not copied here. They are referenced by
their `tuning.md` name and read from `MechanicsTuning` at run time, so a tuning
change can never leave a stale animation behind. Only durations that are pure
presentation have values in this file.

First pass: 2026-09-30, for M3. Nothing here decides the **tone of the dark**
(T15, M4). §9 says which tokens M4 is expected to move and which it may not.

---

## 0. The principle that resolves the colour collision

> **Hue belongs to people. Everything the game says is white, grey, light level,
> shape, pattern or position.**

The game docs put four alphabets on one machine and asked for them to be
disjoint: tags, dial settings, key classes, and (through pings landing on it)
player colours. Hue can carry at most one of them to a colour-blind player, so it
carries exactly one:

| Alphabet | Carried by | Never by | Count |
|---|---|---|---|
| **player** (who pinged, who sent a preset, who is your helper) | **hue** (§1.2) | — | 6 (`players_max`) |
| **tag** (which machine: "my ◆") | **shape** (§2.1) | hue | 6 shapes |
| **dial setting** (which position) | **position on the dial + pip count** (§2.2) | hue | `dial_settings` = 4 |
| **key class** (who may turn it) | **housing pattern** (§2.3), plus a **viewer-relative trim** in the turner's hue on your own and your partner's machines (§1.3) | a shared public hue | up to 6 patterns |
| **system state** (live, committed, glow, failure, disabled) | **light level, glyph and motion**, achromatic (§1.1, §2.4) | hue | — |

**Accepted by the Game Designer (Q-G3, 2026-09-30); `mechanics.md` §1 is
reworded to match.** This replaces two readings of the earlier §1 wording:

- key classes were "shown as the class's colour". They are shown as a
  **pattern**: a public per-class hue would collide with player hues (six of each
  cannot be told apart, colour-blind or not), and a hue shared with the player
  palette would make one colour mean two things on one machine.
- "settings are colours" was the example of a disjoint alphabet. Settings are
  **positions with pips**. The requirement (disjoint from tags) is kept.

---

## 1. Colour

One theme. The HUD always sits on a dark scrim over a 3D scene the HUD does not
control, so there is no light/dark mode switch: the scrim is the guarantee (§1.4).
If M4 wants a lighter HUD it changes the scrim and re-runs the contrast tests.

### 1.1 System roles (achromatic)

| Token | Value | Use |
|---|---|---|
| `color.surface.scrim` | `#0E1116`, `BackgroundTransparency` **0.12** | behind every HUD element that carries text or a glyph |
| `color.surface.raised` | `#1B2029`, transparency 0.12 | a control's own fill (preset tile, dial button) on the scrim |
| `color.surface.selected` | `#2A313D`, transparency 0 | a selected tile; paired with `stroke.focus` |
| `color.text.primary` | `#FFFFFF` | all HUD text and glyphs |
| `color.text.muted` | `#B8C0CC` | secondary text: the "next" turn cue, labels, captions |
| `color.text.disabled` | `#8A93A0` | disabled tile content. Large glyphs and words only (§1.4) |
| `color.stroke.control` | `#8A93A0` | the boundary of every interactive control |
| `color.stroke.focus` | `#FFFFFF`, 3 px | keyboard/gamepad focus and the selected state |
| `color.signal.on` | `#FFFFFF` emissive (`Neon`) | a lit lamp: live lamp, pair lamp, committed check |
| `color.signal.off` | `#2A313D` | an unlit lamp |
| `color.signal.lens` | `#DDEBFF` emissive | the helper-only glow on the required setting. Never used for anything else |
| `color.world.housing` | `#3A414C` | machine body paint (blockout) |
| `color.world.pattern` | `#C9D0DA` | the key-class pattern on the housing band |
| `color.world.neutralTrim` | `#5C6470` | trim on a machine that is neither yours nor your partner's |

No system role has a saturation above 0.15 (HSV). That is the checkable form of
the principle in §0 (PT-T3, `accessibility.md`).

### 1.2 Player palette

Assigned by **seat index**: position in `seatOrder`, which is public and is
**join order** (Lead PO, Q-P3: the phase machine appends players as they join,
and `Ring` keeps that list). So a hue is stable from the lobby into the round. It
changes only if someone earlier in the join order leaves before seats are dealt,
which is accepted; the seat card (C-05) shows each player's hue at round start.

| Token | Seat | Value | Why this order |
|---|---|---|---|
| `color.player.1` | 1 | `#00B386` green | seats 1–4 are the four hues with the largest minimum separation under every simulated colour-vision deficiency (ΔE76 ≥ 28.6, below). The 4-player floor gets the best four |
| `color.player.2` | 2 | `#F0E442` yellow | |
| `color.player.3` | 3 | `#E8671C` vermillion | |
| `color.player.4` | 4 | `#B58CFF` violet | |
| `color.player.5` | 5 | `#E69F00` orange | added at n = 5 |
| `color.player.6` | 6 | `#56B4E9` sky | added at n = 6 |
| `color.player.none` | spectator | `#8A93A0` | a spectator never pings or presets, but appears in lobby lists |

Derived from Okabe–Ito, brightened to read as light in a dark room. Measured
(CIE76 ΔE in Lab, Machado 2009 simulation at severity 1.0):

| Set | Normal | Protan | Deutan | Tritan |
|---|---|---|---|---|
| seats 1–4 | ≥ 28.6 | ≥ 28.6 | ≥ 28.6 | ≥ 28.6 |
| seats 1–6 | ≥ 34.9 | ≥ 20.7 | ≥ 13.5 | ≥ 11.2 |
| each hue vs `#FFFFFF` and vs `#8A93A0` | ≥ 16.8 in every mode | | | |

At n = 6 the tightest pair is sky/green for tritanopes (11.2) and sky/violet for
deuteranopes (13.5). Distinguishable, not comfortable; that is why hue never
works alone (`accessibility.md` A-5).

**Player hue is never used for small text.** Vermillion over the worst-case
scrim composite is 4.15:1, below 4.5. A player's name is always white, next to a
swatch of their hue (§1.4).

### 1.3 Viewer-relative trim

The client paints the trim of a machine by **who the viewer is**, from the
viewer's own `SeatView` (`keyClasses`, `lensClass`, `dependentId`) against the
machine's public `keyClass` in `FacilityView`:

| Machine's key class | Trim on this viewer's screen | Badge |
|---|---|---|
| in the viewer's `keyClasses` | the **viewer's** hue | key glyph (§2.4) |
| equal to the viewer's `lensClass` | the **viewer's partner's** hue | eye glyph |
| anything else | `color.world.neutralTrim` | none |

Two players at one machine see different trims. That is intended: the trim
answers "is this mine?", which is a different question per viewer, and it leaks
nothing: it uses only the viewer's own projection and public facts. (The
class-to-player mapping is not a game secret in any case; the Game Designer
ruled it learnable by watching who turns what. The secrets are required settings
and turn cues.) The
**pattern** (§2.3) is the shared, public identity of the class. After a
disconnect transfer, inherited machines take the inheritor's trim automatically.

### 1.4 Contrast floor, against the worst background

The HUD floats over a scene the generator controls, so the worst case is
specified, not sampled: **pure white** (`#FFFFFF`) behind the scrim. The scrim at
transparency 0.12 over white composites to `#2B2E32`.

| Foreground | On scrim (dark scene) | On worst composite | Floor | Use it for |
|---|---|---|---|---|
| `text.primary` `#FFFFFF` | 18.9 | **13.6** | 4.5 | any text |
| `text.muted` `#B8C0CC` | 10.3 | **7.4** | 4.5 | any text |
| `text.disabled` `#8A93A0` | 6.1 | **4.39** | 3.0 | large text (≥ 24 px rendered, or ≥ 19 px bold) and glyphs only |
| `stroke.control` `#8A93A0` | 6.1 | **4.39** | 3.0 | control boundary |
| player hues (worst: vermillion) | 5.75 | **4.15** | 3.0 | swatches, markers, strokes, large glyphs. Never small text |
| violet `#B58CFF` | 7.35 | 5.30 | 3.0 | |

**The mechanism is the rule, not the sample:** every HUD text or glyph has an
ancestor with `color.surface.scrim` at transparency ≤ 0.12, so the composite
above is the worst it can get (PT-A1). World-space text (BillboardGui) gets the
same scrim as its own background.

---

## 2. Alphabets and glyphs

Every glyph named here is an **icon key**, a string. `Presets.luau` stores the
icon key per preset (`architecture.md` §9.1); `Theme.luau` maps keys to assets.
How a key becomes pixels (an uploaded image, a built-in glyph, primitives) is
with the operator (`README.md` §5 Q-O1); M3 assumes Unicode or emoji placeholders. The alphabets must be **pairwise disjoint** as sets of
silhouettes (PT-T4).

### 2.1 Tags (shape)

| Key | Shape | Notes |
|---|---|---|
| `tag.circle` | ● | |
| `tag.triangle` | ▲ | points up |
| `tag.square` | ■ | axis-aligned; never rotated, so it cannot read as the diamond |
| `tag.diamond` | ◆ | the docs' running example ("my ◆") |
| `tag.crescent` | ☾ | |
| `tag.bolt` | ⚡ | |

**Count: 6.** Tags need only be distinct within a key class
(`INV_tags_distinct_in_class`), and the largest class is `actuators_per_class` = 4
at n = 4 (`ceil(actuator_count / key_classes)`, largest at the smallest n). Six
leaves two spare. Rule: `#tag alphabet ≥ ceil(actuator_count / players_min)`
(PT-T5), so a later `actuator_count` change fails a test rather than a playtest.

Excluded on purpose: star (reads as the lens glow, §2.4), cross/plus (reads as the
failure ✕), heart (a preset icon), arrow shapes (turn cues).

Drawn white (`color.text.primary`, emissive on the tag plate) on a
`color.world.housing` plate, at least 40% of the machine's front face height.

### 2.2 Dial settings (position + pips)

The dial has `dial_settings` detents at fixed **compass positions**, read
clockwise from the top, each marked with a pip count equal to its index:

| Setting | Position (4 detents) | Pips |
|---|---|---|
| 1 | top (12 o'clock) | ● |
| 2 | right (3 o'clock) | ●● |
| 3 | bottom (6 o'clock) | ●●● |
| 4 | left (9 o'clock) | ●●●● |

For `dial_settings` other than 4, detents are spaced `360 / dial_settings` degrees
apart starting at the top, pips = index, up to 6 (PT-T6 asserts the layout for 2..6
and rejects 7+, where pips stop being countable at a glance).

Why position first: the only moment a setting must cross from one screen to
another is a ping, and a ping **points at a position**. A turner matches "where
the ping is" to "where I turn", which needs no reading, no colour and no counting.
Pips are the redundant second channel (and they are what a player remembering a
setting through a blackout will use; that is a ceiling skill, `loop.md` §1a).

The pointer (current setting) is a thick white needle from the hub to a detent.
**Unset** is the needle retracted into the hub, no detent marked.

### 2.3 Key classes (pattern)

A band across the machine housing, `color.world.pattern` on `color.world.housing`:

| Key class index | Pattern key | Pattern |
|---|---|---|
| 1 | `class.bars_h` | horizontal bars |
| 2 | `class.bars_v` | vertical bars |
| 3 | `class.diagonal` | diagonal bars |
| 4 | `class.checker` | checkerboard |
| 5 | `class.chevron` | chevrons |
| 6 | `class.crosshatch` | crosshatch |

Paint, not light: in a blacked-out room the pattern is unreadable at range, which
is exactly `mechanics.md` §1's edge case. Readable by anyone with light on it.
Dots are excluded (they would read as pips).

### 2.4 System glyphs

| Key | Glyph | Meaning | Where |
|---|---|---|---|
| `glyph.key` | a key | "yours to turn" | trim badge, seat card, trace gap label |
| `glyph.eye` | an eye | "you can see for them" / "helper" | trim badge, seat card, helper-ping badge |
| `glyph.live` | a lit ring ◎ | live | turn cue, live lamp label under reduced motion |
| `glyph.next` | a hollow ring ○ | next (lookahead) | turn cue |
| `glyph.done` | ✓ | committed | machine face, progress bar icon |
| `glyph.wrong` | ✕ | wrong setting | turn result |
| `glyph.notyet` | an hourglass | not live yet | turn result |
| `glyph.lens` | a four-point sparkle ✦ | the lens glow | helper's dial only |
| `glyph.pair` | two linked rings | the finale pair lamp | machine face |
| `glyph.finale` | a small crown | the finale segments | progress bar |
| `glyph.ping` | a location pin | ping | action button, ping marker |
| `glyph.preset` | a speech bubble with no text | open presets | action button |
| `glyph.wait` | a clock face with no hands | cooldown | action buttons, preset tiles |
| `glyph.dark` | a bulb with a slash | a room went dark | facility event (C-21) |
| `glyph.again` | a looped arrow | rematch | C-25 |
| `glyph.guess` | a tossed coin (not a die: dice pips would read as dial pips) | a turn made with no helper ping | C-24 trace |

### 2.5 Preset icons

`mechanics.md` §4.2's list, in the panel's fixed order (C-10). Words are the
operator's (T12) and are never altered by the client.

| Order | Preset | Icon key | Silhouette |
|---|---|---|---|
| 1 | `Help` | `preset.help` | a lifebuoy |
| 2 | `On my way` | `preset.on_my_way` | two footprints |
| 3 | `Follow me` | `preset.follow_me` | two figures, one leading |
| 4 | `Wait` | `preset.wait` | a raised open palm |
| 5 | `Go` | `preset.go` | a running figure |
| 6 | `Ready` | `preset.ready` | a flag |
| 7 | `Got it` | `preset.got_it` | a thumbs-up |
| 8 | `Thanks` | `preset.thanks` | a heart |
| 9 | `Nice one` | `preset.nice_one` | two hands clapping |
| 10 | `Well played` | `preset.well_played` | a trophy |

No icon depicts a colour, a shape from §2.1, a number or a direction that could be
read as a fact (C2, `mechanics.md` §4.3). The "follow" figures face the viewer's
right and carry no arrow.

---

## 3. Type

Fonts are Roblox built-ins, so no asset is needed.

| Token | Font | Base size / line height | Weight | Use |
|---|---|---|---|---|
| `type.display` | Fredoka One | 40 / 1.1 | regular (the face is bold) | the trace headline, the outcome banner |
| `type.title` | Builder Sans | 28 / 1.15 | Bold | panel titles, the lobby count |
| `type.label` | Fredoka One | 20 / 1.2 | regular | **preset words, everywhere they appear**, button labels |
| `type.body` | Builder Sans | 20 / 1.35 | Medium | trace rows, notices |
| `type.caption` | Builder Sans | 18 / 1.3 | Medium | the smallest text that exists |

Sizes are **base** sizes, multiplied by the root `UIScale` (`layout.md` §2), whose
floor is 0.9. So the smallest rendered text is 18 × 0.9 = **16.2 px**
(`accessibility.md` A-2). `TextScaled` is not used anywhere: it can shrink text
below the floor without anything noticing. Long strings wrap (`TextWrapped`)
inside a fixed box, at most 2 lines.

Why Fredoka One for presets: native Roblox chat is Builder Sans. A different face
is the cheapest reliable way to make a preset "visually distinct from native
chat" (C6), and it is also the rounded, friendly face a 7-year-old reads best.

---

## 4. Spacing, radii, strokes

**Spacing** (base px, before `UIScale`): `space.1` 4, `space.2` 8, `space.3` 12,
`space.4` 16, `space.5` 24, `space.6` 32, `space.7` 48. Nothing else.

| Token | Value | Use |
|---|---|---|
| `radius.control` | `UDim.new(0, 12)` | tiles, buttons, cards |
| `radius.chip` | `UDim.new(0.5, 0)` | round chips, cooldown rings, swatches |
| `stroke.control` | 2 px, `color.stroke.control` | every interactive control's boundary |
| `stroke.focus` | 3 px, `color.stroke.focus`, `ApplyStrokeMode.Border` | focus and selected |
| `stroke.player` | 3 px, the player's hue | player chips, ping markers |

## 5. Sizes (base, before `UIScale`)

| Token | Value | Notes |
|---|---|---|
| `size.target.min` | 56 × 56 | every touch/click target. × 0.9 floor = 50.4 ≥ 44 (A-1) |
| `size.button.action` | 72 × 72 | the touch Ping and Presets buttons |
| `size.tile.preset` | 96 × 112 | icon 40, word up to 2 lines |
| `size.icon.hud` | 32 | |
| `size.icon.tile` | 40 | |
| `size.tag.cue` | 48 | tag glyph in the live turn cue; 32 in the next cue |
| `size.arrow.cue` | 40 | |
| `size.chip.player` | 48 | headshot chip in the relations strip |
| `size.progress.segment` | 28 × 14, gap 4 | shrinks to fit `layout.md` §3's max width |
| `size.reticle` | 12 (idle), 20 (target) | |

World sizes (studs, `BillboardGui.Size` uses studs via Scale so markers shrink
with distance, clamped by `MinSize`/`MaxSize` offsets where noted):

| Token | Value |
|---|---|
| `world.ping.marker` | 1.6 studs, min 28 px, max 72 px on screen |
| `world.preset.bubble` | 5 × 1.6 studs above the head, min 120 px wide |
| `world.preset.beacon` | 40 px fixed (`AlwaysOnTop`), independent of distance |
| `world.tag.plate` | ≥ 40% of the machine face height |
| `world.dial` | diameter ≥ 1.5 studs; detent pips ≥ 0.12 studs each |

## 6. Layers (`DisplayOrder` / `ZIndex`)

| Token | DisplayOrder | Contents |
|---|---|---|
| `layer.world` | BillboardGuis | markers, bubbles, beacons |
| `layer.hud` | 10 | relations strip, progress bar, turn cues, clock slots, action buttons, edge arrows |
| `layer.control` | 20 | dial control, preset panel |
| `layer.notice` | 30 | seat card, seat-change notice, outcome banner |
| `layer.screen` | 40 | trace, lobby panel |

No elevation shadows: the scrim does that job, and shadows on a dark scene are
invisible.

## 7. Motion

Presentation durations (design-owned):

| Token | Value | Easing | Use |
|---|---|---|---|
| `motion.fast` | 0.12 s | Quad Out | press feedback, focus ring |
| `motion.base` | 0.20 s | Quad Out in / Quad In out | panels open and close |
| `motion.slow` | 0.40 s | Quad Out | seat card, commit flourish, marker fade-out |
| `motion.pulse` | 1.2 s period, sine | — | live lamp, helper-ping badge |
| `motion.shake` | 0.30 s, ±6 px, 3 cycles | — | wrong-setting feedback on the dial control |
| `design.seat_card_seconds` | 4 s | — | how long the seat card stays up before collapsing into the relations strip |
| `design.notice_seconds` | 5 s | — | how long a seat-change notice (C-22) stays up |
| `design.penalty_flash_seconds` | 2 s | — | how long the clock's "−20" stays beside it (C-19) |
| `design.turn_prompt_studs` | `turn_range_studs` − 2 | — | not a duration: the turn prompt's activation distance (C-17). Must be ≤ `turn_range_studs` (`tuning.md` §2); PT-T8 |

Durations that are **game rules**, referenced, never copied:

| What | Lasts | Tuning name |
|---|---|---|
| ping marker | until expiry, target commit, or replacement | `ping_display_seconds` (fade-out = the last `motion.slow` of it) |
| preset bubble and beacon | | `preset_display_seconds` |
| preset cooldown ring | | `preset_rate_limit_seconds` |
| ping cooldown ring | | `ping_rate_limit_seconds` |
| rejected dial state | | `actuation_reset_seconds` |
| armed finale ring (turner only) | | `simultaneous_window_seconds` |
| lobby countdown | | `lobby_seconds` |
| trace | | `post_round_seconds` |

**Reduced motion** (`accessibility.md` A-7): pulses become a steady state plus a
static glyph; shakes are removed (the ✕ glyph remains); slides become fades of
`motion.fast`; the commit flourish is instant. Opacity changes remain. Nothing a
player needs is carried by motion alone.

## 8. Audio cue names

M3 names cues; M4 mixes them (`architecture.md` §10). Every cue has a visual
equivalent, listed so a deaf player loses nothing (A-6).

| Cue | Heard by | Visual equivalent |
|---|---|---|
| `sfx.commit` | everyone (facility-wide) | room brightens; progress bar fills a segment |
| `sfx.fail` | everyone (facility-wide) | C-21 facility pulse at the screen edges |
| `sfx.turn.wrong` | the turner | ✕ on the dial control, shake |
| `sfx.turn.notyet` | the turner | hourglass on the dial control |
| `sfx.finale.armed` | the turner | armed ring on the dial control |
| `sfx.blackout` | everyone | the room goes dark; C-21 with `glyph.dark` |
| `sfx.ping` | everyone within earshot of the target (3D) | the marker |
| `sfx.ping.helper` | the pinger's partner only | the helper badge + edge arrow |
| `sfx.preset` | everyone (3D at the sender) | bubble + beacon |
| `sfx.cue.live` | the turner | the live turn cue card appears |
| `sfx.ui.press` / `sfx.ui.denied` | the local player | press state / wait state |
| `sfx.outcome.won` / `sfx.outcome.lost` | everyone | the outcome banner |

## 9. What M4 may and may not move

M4 owns lighting, fog, audio and the tone of the dark (T15). It **may** change
world lighting, `color.world.*` values, audio, and motion character. It **may
not**, without revisiting this file: give a system role a hue, give a player hue
to a system meaning, remove the scrim, or drop any alphabet's non-colour channel.
The spooky-or-calm decision lives in lighting and audio; nothing in the HUD
presupposes either.
