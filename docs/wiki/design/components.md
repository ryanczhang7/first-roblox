# Components

One entry per surface M3 draws. Each says what the component is for, the **model**
that describes it (a pure function in `src/client/models/`, tested under
`tests/client/`), its states with the data each needs and the tokens each uses,
and its input on touch, keyboard/mouse and gamepad. The view that turns a model
into Instances is Studio-verified (`accessibility.md` §3 lists the checks).

Model names and signatures are **proposals** for the Feature Developer; the
states, the data and the tokens are the decision.

**Payloads** (`architecture.md` §9.7; field lists as the Lead PO gave them,
2026-09-30):

| Payload | Route | Carries |
|---|---|---|
| `FacilityView` | broadcast, once per round | rooms `{id, column, row}`, doors sorted by `(a, b)`, spawn room, each machine `{id, room, slot, tag, keyClass}` |
| `RoundView` | broadcast, on change and ≥ 1/s while a clock runs | `phase`, `secondsLeft`, `playerCount`, `playersMin`, `progress {committed, total}`, `instability`, dark rooms, active pings `{senderId, kind, target, setting?}`, each machine `{id, dial {setting?, state}, live, partnerLamp?}` |
| `SeatView` | private | M2's `PublicSeatView`: `playerId`, `keyClasses`, `lensClass`, `supplierId`, `dependentId`, `seatOrder` |
| `LensView` | private | `readings {machineId, setting}` |
| `TurnCues` | private | `live {ids}`, `next {ids}` |
| `TurnResult` | private, to the turner | `{machineId, kind, reason?}` |
| `PresetFailed`, `PingRefused` | private, to the sender | — |
| `PresetShown` | broadcast | sender, preset, position at send |
| `TraceView` | broadcast, once, entering Post | `architecture.md` §9.11 |

A machine's public identity (tag, key class, room) comes from `FacilityView`;
its changing state (dial, live, partner lamp) from `RoundView`. The class-to-player
mapping is **not** a game secret (Game Designer, 2026-09-30: it is learnable by
watching who turns what); the secrets are required settings and turn cues.

**Stories** (Lead PO, 2026-09-30):

| Story | Components |
|---|---|
| `THEME-001` | `tokens.md` and the PT-* checks; precedes the client stories |
| `HUD-001` | C-14, C-15, C-19, C-20 |
| `HUD-002` | C-01, C-02, C-16, C-17, C-21 |
| `HUD-003` | C-03, C-06, C-07, C-08, and C-09 for Ping |
| `HUD-004` | C-09 for Presets, C-10, C-11, C-12, C-13 |
| `HUD-005` | C-24, C-25 |
| `HUD-006` | C-22, C-27 |
| `HUD-007` | C-04, C-05, C-26 |

`SLICE-004` is the runtime skeleton plus a phase-and-countdown label
(`PhaseClockModel`); it implements no component here, and not C-19.

Token and glyph names are `tokens.md`'s. Regions (A–I) are `layout.md` §3's.

| ID | Component | Where | Phase |
|---|---|---|---|
| C-01 | Machine | world | Round |
| C-02 | Player light | world | Round |
| C-03 | Player marker | world | Round |
| C-04 | Relations strip | HUD A | Round |
| C-05 | Seat card | notice | Assignment, first seconds of Round |
| C-06 | Reticle and target preview | HUD D + world | Round |
| C-07 | Ping marker | world | Round |
| C-08 | Helper-ping edge arrow | HUD G | Round |
| C-09 | Action buttons (Ping, Presets) | HUD I | Lobby, Round, Post |
| C-10 | Preset panel ("the wheel") | HUD H | Lobby, Round, Post |
| C-11 | Preset bubble | world | wherever a preset is legal |
| C-12 | Preset beacon | world + HUD G | Round |
| C-13 | Preset chat line | chat window | wherever a preset is legal (if CA-6 holds) |
| C-14 | Turn cues | HUD C | Round |
| C-15 | Progress bar | HUD B | Round |
| C-16 | Dial control (turning) | HUD H | Round |
| C-17 | Turn prompt | world | Round |
| C-19 | Round clock | HUD E | Round |
| C-20 | Instability meter | HUD F | Round |
| C-21 | Facility pulse | HUD edges | Round |
| C-22 | Seat-change notice | notice | Round |
| C-24 | Trace, with outcome header | screen | Post |
| C-25 | Rematch card | screen, beside C-24 | Post |
| C-26 | Lobby panel | screen | Lobby |
| C-27 | Spectator banner | notice | any, while spectating |

(C-18 and C-23 were folded into C-17 and C-24 during drafting; the numbers are
not reused.)

---

## C-01 Machine

**Purpose.** The thing everything happens at: recognised by its tag, owned by a
key class, set by its dial, read by its helper.

**Model.** `MachineModel.describe(machine, viewer, lens, pings, aim) -> MachineLook`

- `machine`: the machine's `FacilityView` entry (id, room, slot, tag, keyClass)
  joined with its `RoundView` entry (dial `{setting?, state}`, live,
  partnerLamp?) and whether its room is in `RoundView`'s dark rooms. Committed
  and rejected are read from the dial's `state`; a machine is a finale machine
  iff `partnerLamp` is present.
- `viewer`: the viewer's `SeatView` (`keyClasses`, `lensClass`, `supplierId`,
  `dependentId`, `playerId`).
- `lens`: the viewer's `LensView` entry for this machine, or nil.
- `pings`: active `PingShown` whose target is this machine or one of its detents.
- `aim`: whether the viewer's light is on the machine (C-02).

**Anatomy.** Housing (`color.world.housing`) with a **pattern band** (key class,
`class.*`), a **trim** (viewer-relative, `tokens.md` §1.3) with its badge, a **tag
plate** (`tag.*`, white paint), a **dial** (detents with pips, a needle), one
**lamp** on top, and, on finale machines only, a **pair lamp** beside it.

Paint (lit by the world, `LightInfluence` 1): housing, pattern, trim, tag, dial
face, pips, needle. **Light** (emissive, readable in the dark): lamp, pair lamp,
the ✓ face, the lens glow, ping markers. This split is what makes a blacked-out
room remove the tag, class and dial at range but keep the lamps and pings, as
`mechanics.md` §1 specifies, without any special case in code.

| State | When | Shows | Tokens |
|---|---|---|---|
| idle | not live, not committed (includes decoys) | lamp off | `color.signal.off` |
| live | first uncommitted step of its track | lamp on, pulsing; under reduced motion, steady with `glyph.live` on the lamp | `color.signal.on`, `motion.pulse` |
| rejected | a wrong turn, for `actuation_reset_seconds` | needle at the turned detent, then retracts to unset at the end | — |
| armed | finale machine turned correctly, window open | needle set; lamp still live. The armed state itself is shown only to its turner (C-16) | — |
| committed | step done | lamp off, `glyph.done` lit on the face, room light raised (M4 sets how much) | `color.signal.on` |
| pair lamp off / on | finale machines: the other finale turner out of / within reach of *their* machine | second lamp with `glyph.pair`, unlit / lit steady | `color.signal.off` / `.on` |
| lens glow | viewer holds the lens for this class **and** `lens` has this machine **and** `aim` is true | the required detent gets `glyph.lens` and a halo | `color.signal.lens` |
| dark room | the room is blacked out | no change in the model: paint goes unreadable because the room has no light; lamps and pings stay. `lens` is empty there, because the server gates it (D14) | — |

**Trim and badge** (viewer-relative), computed from the viewer's own `SeatView`
against the machine's public `keyClass`: in `keyClasses` → viewer's hue +
`glyph.key`; equal to `lensClass` → partner's (`dependentId`'s) hue +
`glyph.eye`; otherwise `color.world.neutralTrim`, no badge.

**Pure-testable.** Trim role for each of the three cases; after a key transfer
the inherited class gets the `self` trim; lens glow is false whenever any of its
three conditions is false (and the glow detent is the lens's, never derived from
anything else); a decoy is `idle` forever; lamp state for each machine state; the
output has no hue for anything but trim and ping markers (PT-T3).

**Input.** None directly. Turning goes through C-17 → C-16; pinging through C-06.

---

## C-02 Player light

**Purpose.** "Look" is shining your light. It is presentation (D14): the server
gates the lens by range, sight and a lit room; the client shows the glow only
while the light is on the machine.

- A `SpotLight` on the character, direction = the camera's look vector. Range
  and brightness are M4's, with one floor: range ≥ `lens_read_range_studs`, so a
  helper in range can always light what they may read.
- **"Light on it"** is `Aim.isLit(targetPos, cameraCFrame, coneDegrees)`: the
  target is inside a cone of 15° half-angle around the look vector. Pure (PT).
- No states and no input beyond the camera. Works identically on every platform,
  because every platform already controls the camera.

---

## C-03 Player marker

**Purpose.** Identity without character art (amendment 10): which avatar is who,
in whose colour, and which one is your helper or partner (`playtest.md: P-K`
asks a child to "point at their helper").

- Every seated avatar: a `Highlight` outline in the player's hue,
  `DepthMode = Occluded`. Never through walls: avatar positions through walls
  would be information the game docs do not grant.
- Your **helper** gets an overhead badge: `glyph.eye` in their hue on a scrim
  chip. Your **partner** gets `glyph.key` in their hue. Nobody else gets a badge.
  The badge describes what that person does *for this pair*: the helper sees,
  the partner turns.
- States: present; away (disconnected, inside `disconnect_grace_seconds`: the
  outline is gone because the avatar is gone, and C-04 shows the chip as away);
  spectator (no outline).
- **Model:** `PlayerMarkerModel.describe(playerId, seatOrder, viewer)` →
  `{ hueToken, badge = "helper" | "partner" | nil }`. Pure.

---

## C-04 Relations strip

**Purpose.** The seat card, kept on screen all round, so nothing about who helps
whom has to be remembered (`loop.md` §1a).

**Model.** `RelationsModel.describe(viewer, presence) -> { helper, you, partner }`,
each `{ playerId?, hueToken, glyph, state }`.

Layout, left to right: **helper chip** (headshot in a `stroke.player` ring,
`glyph.eye`), a small arrow, a **you swatch** (your hue), a small arrow, **partner
chip** (`glyph.key`). The arrows show the direction of seeing: helper → you →
partner. Names beside chips at `regular` only (`layout.md` §5).

| State (per chip) | When | Shows |
|---|---|---|
| present | the relation exists and is connected | headshot, hue ring, glyph |
| loading | headshot not yet fetched | a filled circle in their hue, glyph |
| error | headshot fetch failed | same as loading, permanently. Never a broken image |
| away | disconnected, inside the grace window | chip at 50% opacity, `glyph.wait` over it |
| none (helper) | you have no helper (your helper left, `mechanics.md` §8) | a dashed `stroke.control` circle, `glyph.eye` struck through. Meaning: your machines are guesses now |
| none (partner) | nobody depends on you any more | chip hidden; the strip shrinks from the right |

**Input.** None. It is not a control, and it is skipped by focus.

---

## C-05 Seat card

**Purpose.** At round start, show who your helper and partner are, and what
yours look like, without a word needing to be read.

**Model.** `SeatCardModel.describe(viewer, seatOrder)` → the three people (hues,
glyphs) and a **sample machine**: a small machine icon trimmed in your hue with
`glyph.key`, and one trimmed in your partner's hue with `glyph.eye`.

Layout: `[helper headshot, eye] → [you, large, your hue] → [partner headshot,
key]`, and under it the two sample machines. Optional words under each
(`type.label`): "Your helper", "You", "You help", and under the samples "Yours to
turn" and "You can see these" (`voice.md`).

| State | Shows |
|---|---|
| entering | slides down from region A (`motion.slow`); fade under reduced motion |
| showing | for `design.seat_card_seconds` |
| collapsing | shrinks into the relations strip (C-04) (`motion.slow`); fade under reduced motion |
| loading / error (headshots) | hue circles, as C-04 |

It never blocks input. The round clock is already running (Assignment is a step,
not a pause), so the card is dismissible: any tap, click, Esc, B or movement
input collapses it early.

---

## C-06 Reticle and target preview

**Purpose.** Show what a Ping will point at *before* it is sent. A mis-ping costs
`ping_rate_limit_seconds` to correct, so the preview is the cheapest error
prevention in the game.

**Model.** `AimModel.pick(candidates, cameraCFrame, viewerPos) -> Target?` where
candidates are detents, machines and doorways, and a Target is
`{ kind = "setting" | "machine" | "doorway", id, setting?, inRange }`.

Rules (pure, PT):
- The candidate must be inside a 6° snap cone of the camera's look vector; the
  one nearest the cone's axis wins.
- **Most specific wins**: when a detent and its machine are both in the cone, the
  detent is chosen if it is within 2° of the axis, the machine otherwise. A
  doorway loses to anything on a machine.
- `inRange` = distance ≤ `ping_range_studs`. Line of sight is the server's
  (`architecture.md` §9.6); the client does not pre-judge it.

| State | Reticle | World preview (this viewer only) |
|---|---|---|
| idle | 12 px white dot | none |
| target, in range | 20 px ring in your hue | outline in your hue: `Highlight` on a machine; a ring around a detent; a frame on a doorway |
| target, out of range | 20 px hollow ring, `color.text.disabled` | none. The Ping button shows its denied state if pressed |
| cooling | ring as above plus a thin arc draining over `ping_rate_limit_seconds` | as above |

**Input.** Aiming is camera control on every platform. Pinging is C-09.

---

## C-07 Ping marker

**Purpose.** "This." The only way a fact crosses between players. No text, no
kinds, no label (`mechanics.md` §4.1): a marker and a colour.

**Model.** `PingModel.describe(ping, viewer, now) -> PingLook`:
`{ hueToken, badge = "self" | "helper" | nil, alwaysOnTop, opacity, anchor }`.

- `hueToken` is the sender's seat hue.
- `badge = "helper"` iff `ping.sender == viewer.supplierId`; `"self"` iff it is
  the viewer's own.
- `alwaysOnTop` is true **only** for your helper's ping, on your screen (so you
  can find it through a wall). Every other marker is depth-tested.

Form: `glyph.ping` (a location pin), emissive, in the sender's hue, with a
`stroke.player` ring around the target:

| Target kind | Anchor |
|---|---|
| setting | the ring sits on the detent; the pin stands just above it |
| machine | the pin above the machine's lamp |
| doorway | the pin at the top centre of the doorway frame |

| State | When | Shows | Tokens |
|---|---|---|---|
| appearing | `PingShown` arrives | scale 0 → 1 over `motion.fast` (fade only under reduced motion) | |
| active | until expiry | as above. `helper`: `glyph.eye` badge on the pin, pulsing ring (steady under reduced motion), `sfx.ping.helper`. `self`: a thin white outer ring | `motion.pulse` |
| expiring | the last `motion.slow` of `ping_display_seconds` | fades out | |
| cleared | its machine commits | fades out over `motion.fast` | |
| replaced | the sender pings again | the old marker is removed at once | |
| shared | two or more pings on one target | markers side by side, offset 0.4 studs, each in its own hue (`mechanics.md` §8) | |
| dark room | always | unchanged: markers are light | |

**Input.** None (markers are not interactive).

---

## C-08 Helper-ping edge arrow

**Purpose.** "Your helper's ping" on the HUD, so a turner can find it from
anywhere (`mechanics.md` §4.1).

**Model.** `EdgeArrowModel.place(targetScreenPos, isBehindCamera, safeRect) ->
{ visible, position, angle }`. Visible iff the helper's ping is active and its
marker is off-screen or behind the camera. Position is the intersection of the
ray from screen centre toward the target with the safe rect inset by 24 px.
Pure (PT).

Shows a 48 px scrim chip at the edge: an arrow in the helper's hue pointing at
the target, with `glyph.eye`. It pulses once when a new helper ping arrives
(once only, not continuously; nothing under reduced motion).

States: hidden (no helper ping, or it is on screen), shown, updated (target
moved to a new ping: jumps, no tween).

---

## C-09 Action buttons

**Purpose.** A visible, pressable path to Ping and to the presets on every
platform, and the place their cooldowns are shown. Shown on all platforms (with
key hints on keyboard and gamepad), not only on touch: the cooldown has to be
visible to everyone.

| Button | Glyph | Touch | Keyboard / mouse | Gamepad |
|---|---|---|---|---|
| Ping | `glyph.ping` | tap | `Q` or middle mouse | `ButtonR1` |
| Presets | `glyph.preset` | tap (toggles C-10) | `T` (toggles C-10) | `ButtonL1` (toggles C-10) |

**Model.** `ActionButtonModel.describe(kind, phase, isSpectator, cooldownUntil,
now, aimTarget) -> { state, ringFraction }`.

| State | When | Shows | Tokens |
|---|---|---|---|
| default | usable | glyph on `color.surface.raised`, `stroke.control` | |
| hover / focus-visible | pointer over / gamepad selected | `stroke.focus` | `motion.fast` |
| pressed | down | scale 0.94 (no scale under reduced motion) | `motion.fast` |
| cooling | inside the rate limit | a ring draining over `preset_rate_limit_seconds` / `ping_rate_limit_seconds`, `glyph.wait` in the corner | |
| denied | pressed while cooling, or Ping with no in-range target | ring flashes once, `sfx.ui.denied`. **Does not restart the cooldown** (`mechanics.md` §8) | |
| disabled | Ping outside Round; Presets in a phase with no legal preset (Assignment, Resolution); any spectator | glyph at `color.text.disabled`, no focus stop | |
| refused | `PingRefused` arrives (out of range or sight, in the server's view) | as *denied*; the ping cooldown stays as the server applied it | |
| not sent | `PresetFailed` arrives: filtering failed (fail closed) | Presets button shows `glyph.wrong` over the bubble for `motion.slow` × 3; the cooldown is **not** shown (it was refunded, D18) | |

Key hints (`Q`, `T`, `RB`, `LB`) are a `type.caption` chip under each button on
keyboard/gamepad. They are not floor information.

---

## C-10 Preset panel ("the wheel")

**Purpose.** Say what you intend, in one of `preset_count` shipped presets, with
no reading required.

**Decision: a 2 × 5 grid, not a radial wheel.** See `README.md` D-6.

**Model.** `PresetPanelModel.entries(presets, phase, cooldownUntil, now) ->
{ panelState, entries }`, each entry `{ id, word, iconKey, enabled, reason }` with
`reason = "phase" | "cooling" | nil`. `presets` is `Presets.luau`'s table,
unmodified: the word shown is the table's word, byte for byte.

Tiles in `tokens.md` §2.5's order, row-major: row 1 `Help`, `On my way`,
`Follow me`, `Wait`, `Go`; row 2 `Ready`, `Got it`, `Thanks`, `Nice one`, `Well
played`. The order never changes by phase: illegal tiles are disabled in place,
not removed, so positions stay learnable.

Each tile: `size.tile.preset`, icon (`size.icon.tile`) above the word
(`type.label`, up to 2 lines), `radius.control`, `stroke.control`.

| Panel state | When | Shows |
|---|---|---|
| closed | default | nothing in region H |
| open, ready | opened, not cooling | legal tiles enabled |
| open, cooling | opened inside `preset_rate_limit_seconds` | every tile disabled with `reason = "cooling"`, a draining ring and `glyph.wait` in the panel's top edge. It still opens, so a child sees *why* nothing works |
| unavailable | no preset is legal in this phase | the panel cannot open; C-09 Presets is disabled |

| Tile state | Shows | Tokens |
|---|---|---|
| default | icon + word, white | `color.surface.raised`, `color.text.primary` |
| hover / focus-visible | `stroke.focus` | `motion.fast` |
| pressed | `color.surface.selected`, scale 0.96 (none under reduced motion) | |
| disabled (phase) | icon and word at `color.text.disabled`; skipped by focus | |
| disabled (cooling) | as phase, plus the panel's wait ring | |

Sending: pressing an enabled tile sends `SendPreset { preset = id }`, closes the
panel (`motion.base`), and puts C-09 Presets into cooling optimistically. If the
server declines for filtering, C-09 shows *not sent* and the cooldown is cleared.

**Input.**

| | Open | Move | Send | Close |
|---|---|---|---|---|
| Touch | tap Presets | — | tap a tile | tap outside the panel, or Presets again |
| Keyboard / mouse | `T` | mouse, or arrow keys / `Tab` | click, `Enter`, or `1`–`9`, `0` (row-major, **only while open**) | `Esc`, `T` |
| Gamepad | `ButtonL1` (first enabled tile selected via `GuiService.SelectedObject`) | D-pad / left stick | `ButtonA` | `ButtonB`, `ButtonL1` |

The panel does not capture movement: a player can walk while it is open. Focus
never leaves the panel while it is open, and returns to the game when it closes.
The Roblox backpack hotbar is disabled so number keys are free.

---

## C-11 Preset bubble

**Purpose.** Show a preset over the person who sent it (attributed by name and
position, `mechanics.md` §4.2).

**Model.** `PresetBubbleModel.describe(presetShown, viewer, now) -> { word,
iconKey, hueToken, senderName, opacity, relation }`.

A world `BillboardGui` above the sender's head (`world.preset.bubble`),
depth-tested: scrim pill, a 6 px stripe in the sender's hue on its left edge, the
icon, the word (`type.label`), and the sender's name above it (`type.caption`,
white). One bubble per sender; a new preset replaces the old.

States: appearing (`motion.fast`), showing (`preset_display_seconds`), expiring
(fade over the last `motion.slow`), replaced, own (your own preset is shown over
you too, as confirmation).

---

## C-12 Preset beacon

**Purpose.** Make "Help" complete without a follow-up: where it was said, seen
through walls (`preset_reveals_sender_position`, CA-3).

A world `BillboardGui` at the **sender's position in the `PresetShown` payload**
(where they were when they sent it, not where they walk next: confirmed by the
Game Designer, Q-G7, `mechanics.md` §4.2), `AlwaysOnTop`,
fixed 40 px (`world.preset.beacon`): the preset's icon inside a `stroke.player`
ring in the sender's hue. Lives `preset_display_seconds`.

**Off-screen:** an edge chevron (C-08's geometry, 48 px) with the icon, **only for
presets from your helper or your partner**, badged `glyph.eye` or `glyph.key`.
Other players' beacons appear only when on screen. Reason: at n = 6, five
simultaneous edge chevrons would bury the one that matters; relevance to you is
computed from your own `SeatView`, so it reveals nothing.

**Model.** `PresetBeaconModel.describe(presetShown, viewer, onScreen) ->
{ show, edge, badge }`. Pure (PT: edge is false for anyone but helper/partner).

---

## C-13 Preset chat line

**Purpose.** If CA-6 is confirmed by `CHAN-001`, presets also arrive as
`TextChatService` system messages. They must be labelled "system preset" and be
visually distinct from native chat (C6). The world bubble and beacon (C-11, C-12)
still carry the gameplay meaning; the chat line is the record.

**Model.** `PresetChatModel.line(senderName, word) -> string` (rich text):

    <font color="#B8C0CC">system preset</font>  <b>{name}</b>  <font face="FredokaOne">{word}</font>

- `{name}` is the sender's display name with `<`, `>`, `&`, `"` and `'` escaped.
- `{word}` is the table's word, unmodified: **no terminal punctuation** is ever
  added (the table has none, PT C6).
- No hue in chat text: the chat window's background is Roblox's, not ours, so
  no contrast guarantee exists for coloured text there.

States: delivered (appears in the chat window like any system message); not
delivered (filter failure: nothing appears; C-09 shows *not sent* to the sender
only).

If CA-6 is **not** confirmed, this component is not built and nothing else
changes.

---

## C-14 Turn cues

**Purpose.** Private: "your ◆ is live" and "your ● is next", with where to go.
Floor sentence 1 (`loop.md` §1a).

**Model.** `TurnCueModel.cards(turnCues, facility, viewerRoom, viewerPos,
cameraCFrame) -> { live = {Card}, next = {Card} }`, each Card `{ machineId,
tagKey, hueToken, arrowTarget, arrowAngle, atMachine, isFinale }`. Sorted nearest
first; at most 2 of each (two tracks can make two of your machines live at once;
a finale step waiting on the other track is always *next*, never *live*).

- `arrowTarget` (Q-G2, `mechanics.md` §3.2): **in the machine's room, the
  machine; anywhere else, the next doorway on a shortest doorway path** from the
  viewer's room to the machine's room over `FacilityView`'s doors, ties broken
  toward the lower-indexed next room. Pure (PT-N1: the target for every room
  pair of a hand-built layout, including a tie). Blackouts do not change it.
- `arrowAngle`: the angle on screen from "straight ahead" to `arrowTarget`, from
  the camera's flattened look vector and the flattened direction to the target.
  Pure (PT).
- `atMachine`: within the turn prompt's distance of it (C-17).

| Card | Shows | Tokens |
|---|---|---|
| live | `glyph.live` + the tag in **your** hue (`size.tag.cue`) + arrow (`size.arrow.cue`), on scrim | `color.text.primary`, your hue, `sfx.cue.live` on appear |
| live, at machine | the arrow is replaced by `glyph.key` ("turn here") | |
| live, finale | as live, plus `glyph.finale`. The pair lamp is **not** mirrored here: it is world state, readable in person (`mechanics.md` §3.2) | |
| next | `glyph.next` + tag at 32 in `color.text.muted` + a muted arrow | |
| none | nothing in region C. No empty-state text: having nothing live is normal | |
| promoted | a live machine commits: its card fades (`motion.base`) and a next card becomes live | |

Cues stay up in a blacked-out room: they are private data, not world state.

**Input.** None.

---

## C-15 Progress bar

**Purpose.** How far the group has got, from anywhere, and nothing else
(`mechanics.md` §3.2).

**Model.** `ProgressModel.segments(bar: { committed: number, total: number },
finaleCount: number) -> { segments = { { filled, finale } }, justFilled }`.

- **The parameter type is exactly `{ committed, total }`.** The model cannot be
  given anything the bar must never show, because it has nowhere to receive it.
  `finaleCount` is `procedure_tracks`, a public constant.
- `segments[i].filled = i <= committed`; `segments[i].finale = i > total -
  finaleCount`.

Shows: `glyph.done` at the left, then `total` equal segments
(`size.progress.segment`) filled left to right with `color.signal.on`; the last
`finaleCount` segments carry a double `stroke.control` border and a `glyph.finale`
above them. Empty segments are `color.signal.off` with `stroke.control`.

| State | Shows |
|---|---|
| empty | all segments empty |
| partial | first `committed` filled |
| just filled | the newly filled segments flash once over `motion.slow` (instant under reduced motion). The finale always arrives as a jump of `finaleCount` |
| complete | all filled |
| hidden | outside Round |

It **never** animates between commits, never drains, carries no number, no
per-track split, no hue, no marker for "next", and sits in its own row
(`layout.md` §3) so it cannot be mistaken for a timer.

**Input.** None.

---

## C-16 Dial control (turning)

**Purpose.** Set one of your own machines. Rare, decisive, punished when wrong:
so it takes two deliberate actions, and it makes your helper's ping the obvious
choice.

**Model.** `DialControlModel.describe(machine, pings, viewer, turnState, now) ->
DialLook`: detents `{ index, compass, pips, pingHues, helperPinged, selected,
enabled }`, hub `{ tagKey, glyph, ring }`, `turnEnabled`.

Layout (region H, 288 × 288): the machine's detents as buttons
(`size.target.min` or larger) at their **compass positions**, same as the world
dial (`tokens.md` §2.2), each showing its pips; the hub shows the machine's tag in
your hue; a **Turn** button below the dial (`glyph.key` + "Turn"). Active pings on
this machine's detents are mirrored as dots in the sender's hue on the matching
button; your helper's carries `glyph.eye`.

| State | When | Shows | Data | Tokens / cues |
|---|---|---|---|---|
| idle | opened, no helper ping | nothing selected, Turn disabled | | |
| idle, helper pinged | opened, helper has an active setting-ping here | **that detent pre-selected**, Turn enabled. Only the helper's (`supplierId`'s) ping, never another player's, and only on the turner's own machine (Q-G5, `mechanics.md` §5) | helper's ping | |
| selected | a detent chosen | `stroke.focus` on it, Turn enabled | | `motion.fast` |
| sending | Turn pressed | all disabled, hub `glyph.wait` | | |
| committed | result `committed` | `glyph.done` on the hub, then closes after `motion.slow` | | `sfx.commit` |
| armed | result `armed` (finale) | `glyph.finale` on the hub, a ring draining over `simultaneous_window_seconds`; control stays open | window start | `sfx.finale.armed` |
| pair failed | the window closed | `glyph.pair` with `glyph.wrong` over it, then *resetting* | | `sfx.turn.wrong` |
| wrong setting | result `wrong_setting` | `glyph.wrong` on the selected detent, shake (not under reduced motion), then *resetting* | | `sfx.turn.wrong`, `motion.shake` |
| not live yet | result `not_live` | `glyph.notyet` on the **hub** (not on a detent: the setting was not judged), no shake, then *resetting* | | `sfx.turn.notyet` |
| resetting | `actuation_reset_seconds` | everything disabled, ring draining, `glyph.wait` | reset end | |
| invalid | `not_your_class`, `out_of_reach` | closes; `sfx.ui.denied` | | |

"Wrong setting" and "not live yet" differ in **glyph, place and sound**, so the
diagnostic answer (`actuation_failure_is_diagnostic`) survives with the sound off
and in greyscale. The diagnosis comes from the private `TurnResult` and is shown
**to the turner only** (Q-G4, `mechanics.md` §5). Everyone else gets the same
thing for either kind of failure: `sfx.fail` (C-21), a pip filling on C-20, and,
if they can see the machine, the dial snapping back (C-01).

**Input.**

| | Choose a detent | Turn | Close |
|---|---|---|---|
| Touch | tap it | tap Turn | tap outside; walk out of reach |
| Keyboard / mouse | click, arrow keys by compass (Up = top, Right = right…), or `1`–`n` | `Enter` or `E` | `Esc`; walk out of reach |
| Gamepad | D-pad by compass | `ButtonA` | `ButtonB`; walk out of reach |

For `dial_settings` ≠ 4, compass keys pick the nearest detent clockwise and `1`–`n`
always work. Opening the control does not stop movement; leaving turn reach
closes it.

---

## C-17 Turn prompt

**Purpose.** Offer the dial control at a machine you may turn.

A `ProximityPrompt` on each machine, **enabled only on the viewer's client and
only for machines of the viewer's key classes** that are not committed.
`Style = Custom`, drawn as a 56 px scrim chip with `glyph.key` and the word
"Turn". `MaxActivationDistance` = `design.turn_prompt_studs` =
`turn_range_studs` − 2 (8 at today's 10), so latency rarely makes the server
refuse a turn the client offered (`tuning.md` §2 asks for a prompt distance ≤
`turn_range_studs`; PT asserts it). Default keys: `E` / `ButtonX` / tap.

States: hidden (not yours, committed, out of reach); shown; focused (nearest of
several: Roblox's own prompt selection); triggered (opens C-16).

**Model.** `TurnPromptModel.enabled(machine, viewer)`. Pure.

---

## C-19 Round clock

**Decided** (Game Designer, Q-G1): `hud_shows_round_clock` = true,
`hud_clock_separate_from_progress` = true (`tuning.md` §4, "What the HUD shows of
the round — G8"; `mechanics.md` §3.3). **Form is taste-pending for the operator
(T21, `hud_round_clock_form`)**; this entry builds its provisional default.

**Model.** `ClockModel.describe(secondsLeft, lastPenaltyAt, now, reducedMotion)
-> { text, penaltyText?, emphasis }`.

- **A numeric `mm:ss` countdown, always visible**, from `RoundView.secondsLeft`,
  in `type.title` with tabular digits, white on a scrim chip (72 px tall) in
  region E. `text` is `string.format("%d:%02d", m, s)`, floored, never negative.
- **Each penalty shows a brief "−20"** beside it: `penaltyText` is U+2212 followed
  by `instability_clock_penalty_seconds` (read from `MechanicsTuning`, never
  written as 20), `type.label`, for `design.penalty_flash_seconds`, fading over the last `motion.slow`.
  Two penalties inside that time show once each, stacked.
- Last 60 s: `emphasis = true`, the chip's stroke goes to `stroke.focus`. No
  colour change (hue belongs to people), no ticking sound unless M4 adds one.
- **Not a ring and not a bar.** A number cannot be read as progress, and it sits
  in a different corner from the progress bar (`layout.md` §3). **Nothing
  combines them**: no pace line, no "on track", no forecast.

| State | Shows |
|---|---|
| running | `mm:ss` |
| penalty | `mm:ss` jumps at once (no count-down animation) and `−20` appears |
| final minute | emphasis stroke |
| ended | `0:00` until the phase leaves Round |
| hidden | outside Round |

If T21 changes the form (final-60-s only, or ambient), only this entry and its
model change; region E is anchored alone (SC-L2).

## C-20 Instability meter

**Decided** (Game Designer, Q-G1): `hud_shows_instability` = true, as
`instability_max` pips; `hud_marks_blackout_thresholds` = true (`tuning.md` §4
G8; `mechanics.md` §3.3).

**Model.** `InstabilityModel.pips(instability, instability_max,
instability_blackout_threshold) -> { { filled, marksBlackout } }`.
`filled = i <= instability`; `marksBlackout = i % instability_blackout_threshold
== 0`. Pure (PT-I1).

`instability_max` pips in a row in region F (16 px each, gap 6), empty =
`color.signal.off` with `stroke.control`, filled = `color.signal.on`. Under each
`marksBlackout` pip, a `glyph.dark` (16 px): "a light goes out here". It never
says **which** room (drawn at the crossing). A pip filling flashes once
(`motion.slow`, instant under reduced motion); a marked pip filling also fires
C-21's blackout pulse.

| State | Shows |
|---|---|
| calm | 0 filled |
| rising | first `instability` filled |
| one from dark | the next pip to fill is a marked one: its `glyph.dark` is drawn at full white instead of `color.text.muted` |
| max | all filled (the round ends) |
| hidden | outside Round |

---

## C-21 Facility pulse

**Purpose.** The visual equivalent of `sfx.fail` and `sfx.blackout` (`tokens.md`
§8), so a player with the sound off knows something went wrong somewhere.

- **Fail:** a white vignette at the screen edges, 0 → 25% → 0 opacity over
  `motion.slow`. Under reduced motion, a static 15% vignette for `motion.slow`.
- **Blackout:** the same, plus a `glyph.dark` chip under the progress bar for 2 s.
- Says nothing about *which* machine or *whose* turn: `sfx.fail` is facility-wide
  and carries no more than that. It is the same for a wrong setting and for
  not live yet (Q-G4): only the turner is told which (C-16).

**Model.** `FacilityPulseModel.onEvent(event, reducedMotion)`. Pure.

---

## C-22 Seat-change notice

**Purpose.** When a disconnect reshapes the ring (`mechanics.md` §8), say what
changed for *you*.

| Case (from the new `SeatView`) | Shows | Words (optional) |
|---|---|---|
| you gained a key class | a sample machine in the new class's pattern, trimmed in your hue, with `glyph.key` | "You can turn these too" |
| you lost your helper | `glyph.eye` struck through beside your swatch | "No helper now. You can guess" |
| helper or partner is away | nothing new: C-04 shows *away* | — |

Region: notice layer, top centre under the turn cues, for `design.notice_seconds`, then gone; C-04 keeps the lasting state.

**Model.** `SeatChangeModel.diff(oldSeatView, newSeatView)`. Pure (PT: exactly
the cases above; no notice when nothing relevant changed).

---

## C-24 Trace, with outcome header

**Purpose.** What happened, readable by a child, naming steps and not players
(`mechanics.md` §7, T14).

**Model.** `TraceModel.describe(traceView, outcome, now) -> TraceLook`. It takes
no seat or player input at all. Its output contains **no player hue token**
(PT, the structural form of T14 on the client).

Layout (one column, `layout.md` §4):

1. **Outcome header.** A glyph and a word (`type.display`):

   | Outcome (`architecture.md` §9.2) | Glyph | Word |
   |---|---|---|
   | `won / completed` | `glyph.done` | "Safe" |
   | `lost / clock` | `glyph.wait` | "Out of time" |
   | `lost / instability` | `glyph.dark` | "Too many wrong turns" |
   | `lost / unwinnable` | `glyph.wait` | "Not enough time left" |
   | `no_contest / below_quorum` | `glyph.eye` struck | "Not enough players" |
   | `no_contest / generator` | `glyph.wait` | "The facility could not be built" |

2. **Headline.** The one sentence from `TraceView` (`type.display`, wraps to 2
   lines; forms in `voice.md` §3), with a pictogram before it: `glyph.wait` and
   `glyph.eye` for *waiting for helper*, `glyph.wait` and `glyph.key` for
   *waiting for turner*, `glyph.wait` and `glyph.pair` for *waiting for the
   other pair*; none for "Nobody waited long."
3. **Par against actual.** Two bars on one scale: "You" (finishing time, or, on a
   loss, the final count shown as the progress bar's segments, the same picture
   everyone saw) and "Best route" (par). Beating par gets `glyph.done`.
4. **Timeline.** Two lanes, upper and lower, one per track, told apart by
   position, never by colour. Each step is a block with its tag and class
   pattern and its **step number**, which is par's canonical order
   (`mechanics.md` §7: T1[1] = 1, T2[1] = 2, T1[2] = 3, …; the finale is 7 on
   track 1 and 8 on track 2), so "Step 3" in the headline is the block marked 3.
   Gaps are labelled by glyph and fill: *waiting for helper* = `glyph.eye`,
   hatched; *waiting for turner* = `glyph.key`, dotted; *waiting for the other
   pair* (finale only) = `glyph.pair`, cross-hatched. The finale blocks join the
   lanes and carry `glyph.finale`.
5. **Guesses.** One chip per guessed step: `glyph.guess` (a coin) with `glyph.done` or `glyph.wrong`.

| State | Shows |
|---|---|
| loading | `TraceView` not received: header and a skeleton of rows (achromatic), at most 2 s |
| error | not received after 2 s: header only, and "No replay this time" |
| no contest | header only; no headline, par or timeline (there was no game to replay) |
| no guesses | the guesses row is hidden |
| showing | for `post_round_seconds`, with a thin ring at the top right draining over it |

Presets `Thanks`, `Nice one`, `Well played` stay available (C-09, C-10).

**Input.** On `compact` the timeline row scrolls horizontally: touch drag, mouse
wheel, gamepad right stick. Nothing else is interactive.

---

## C-25 Rematch card

**Purpose.** "Play again with this group?", the co-play retention moment (A4).

**When** (Lead PO, Q-P2): shown **during Post, beside the trace**, driven by
`RoundView.phase == "Post"`. Acceptance is sent on the `AcceptRematch` remote;
the phase machine records `RematchAccepted` only in Post. The machine's
`PromptRematch` effect, emitted on leaving Post, **dismisses** the card.

**Model.** `RematchModel.describe(phase, acceptedIds, viewerId, pending) ->
{ visible, state, acceptedHues }`. Pure.

Layout: a card on the right of the trace column at `regular`, pinned under the
trace header at `compact` (it never scrolls away). One large button:
`glyph.again` + "Again" (`size.button.action` tall, full card width); under it,
chips of players who have accepted, in their hues. It takes initial gamepad
selection when Post begins.

| State | Shows |
|---|---|
| default / hover / focus-visible / pressed | as C-10 tiles |
| sending | button disabled, `glyph.wait` |
| accepted | button replaced by `glyph.done`; your chip joins the accepted row |
| refused | the remote was refused (e.g. arrived as Post ended): back to default for `motion.slow`, then gone with the card |
| dismissed | `PromptRematch` arrives or the phase leaves Post: the card closes (`motion.base`) |

Input: tap / click / `Enter` / `ButtonA`. Gets initial gamepad selection.

---

## C-26 Lobby panel

**Purpose.** Who is here, whether there are enough, and when it starts.

**Model.** `LobbyModel.describe(players, now, lobbyDeadline, players_min,
players_max) -> { slots, countdown }`.

- `players_max` slots in a row. The first `players_min` have a solid
  `stroke.control` border ("needed"); the rest are dashed ("optional").
- A filled slot: headshot in the player's lobby hue ring (+ name at `regular`).
- A countdown ring over `lobby_seconds` with the seconds as `type.title`.

| State | When | Shows |
|---|---|---|
| waiting for players | fewer than `players_min` | the countdown **holds** (`architecture.md` §3): ring frozen, `glyph.wait`; empty needed slots pulse (steady under reduced motion) |
| counting | ≥ `players_min` | ring draining |
| full | = `players_max` | all slots filled |
| starting | → Assignment | panel fades (`motion.base`) and the seat card follows |
| empty (alone) | 1 player | as *waiting*; optional words "Waiting for friends" |

There is **no ready toggle** in M3 (Lead PO, Q-P1, confirmed): the phase machine
has no ready state. `Ready` is an intent preset only, sent from C-10 like any
other. The count comes from `RoundView.playerCount` and `playersMin`. Slot hues
are by `seatOrder` index, which is join order (Q-P3), so a player keeps the same
hue from Lobby into the round.

---

## C-27 Spectator banner

For a player who rejoined after `disconnect_grace_seconds` (`mechanics.md` §8):
a notice-layer chip, `glyph.eye` + `glyph.wait`, words "You'll join next round".
Ping and Presets are disabled (C-09). Stays until Lobby.
