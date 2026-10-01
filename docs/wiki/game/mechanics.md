# Mechanics

One section per mechanic: inputs, rules, states, edge cases, and the decision it
produces. Constants appear by **name**. Their values, labels and rationale are in
`tuning.md` and nowhere else. If a number appears here, it is because it is
structural (a cycle length, a count ceiling set by a platform rule), not tuned.

Everything below is a function of state. §9 maps each rule to what a Lune test
can check without a Roblox runtime. A rule that is not in that table should not
have been specified.

**Revised 2026-09-30 (third pass) for brief §0d #19.** Section numbers are
unchanged on purpose, because source, tests and stories cite them.

| § | Status in this pass |
|---|---|
| 1 World | revised: machines have dials; a live lamp |
| 2 Look | kept; reading requires range as well as light |
| 3 Procedure | **3.1 revised, 3.2 replaced**: two tracks, private turn cues, a public progress bar (T10 (c)), no order fragments |
| 4 Channel | **replaced**: pings and presets. The old signal channel is summarised in §4.7 |
| 5 Actuation | kept; the finale replaces free-floating paired operations |
| 6 Generator | revised: invariants re-derived, I2 superseded, I3 replaced |
| 7 Trace | re-aimed |
| 8 Edge cases | revised |
| 9 Headless | revised |

**Gap closure for M3 planning, 2026-09-30 (G1–G12).** The Lead PO's M3 stories
needed rules this pass had not written down. They are added in place, each
marked with its G-number, and the constants are in `tuning.md` §2–§4. Two change
an earlier rule rather than filling a gap, and are flagged where they are:
**the finale goes live together** (§3.2), and **`unwinnable` is structural
only; the clock arm is withdrawn** (§8).

---

## 1. The world

**Inputs:** none. The generator establishes it at round start (§6).

The facility is `room_count` rooms of modular hard-surface geometry, connected as
a graph through doorways. **Shape (G1, G2):** rooms are cells of a
`layout_grid_columns` × `layout_grid_rows` grid, `room_pitch_studs` apart, abutting
with no corridors; doorways join only grid-adjacent rooms (a random spanning tree,
plus extra doorways at `layout_loop_door_chance`), so the graph is connected with
degree ≤ 4 and may have loops. Rooms are indexed by grid cell, row-major from 1,
and every tie-break in this file uses that index. Machines stand in
`machine_slots_per_room` fixed slots per room. Every player spawns in
`spawn_room`. It is dim. Each player carries a directional light,
sees what their light is pointed at, and sees little else at range. There are no
NPCs, no enemies and no combat (A2 #3 and its anti-goals).

Each room contains zero or more **machines** (called *actuators* in earlier
passes and in code comments; the same thing). A machine has:

| Property | Visible to | Notes |
|---|---|---|
| **tag**: a symbol | anyone with light on it | how a person recognises "my ◆ machine". Distinct within a key class |
| **key class**: one of `n` | anyone with light on it | who may turn it. Shown as a **housing pattern** (`design/tokens.md` §2.3), never as a hue |
| **dial**: `dial_settings` positions, and its current setting | anyone with light on it | the thing a turner sets |
| **required setting** | **only the helper for its key class**, within `lens_read_range_studs`, with light on it | the secret. The right position glows for that one player |
| **live lamp**: lit or dark | anyone who can see the machine | lit while this machine is a step that may be turned now (§3.2) |
| **committed**: bool | anyone who can see the machine | the step is done. Its room gets a little brighter |

Tags, dial settings and key classes use **pairwise disjoint visual alphabets**.
This is derived: if tags and settings shared one, a tag could be read as an
answer; if settings and classes did, a setting could be read as "whose". The
Lead Designer picks them, and **did (Q-G3, accepted 2026-09-30):** tags are
**shapes**, settings are **compass positions with pip counts** (1 to
`dial_settings`), key classes are **housing patterns**, and **hue belongs only to
players** (`design/tokens.md` §0, §2). This meets the rule, and it is better
than this section's earlier example (settings as colours, classes as colours):
position is what a ping points at, so a turner matches a ping to a detent with no
reading and no colour vision.

**What the pattern may and may not reveal (Q-G3).** The game's secrets are the
required settings and the turn cues (`roles.md` §6); nothing in play depends on
*who holds which class* being secret, because nothing can be addressed to a
player (§4.4) and anyone learns it within a round by watching who turns what.
The built projection is stricter (it never sends anyone else's key class), and
that is the Lead PO's defence in depth, not a game rule. **If** the Lead PO keeps
it, note that `Ring.luau` deals key class *i* to seat *i* and `seatOrder` is
public, so a fixed class-to-pattern table, or a class index replicated on each
machine, publishes the mapping anyway. Keeping the promise then needs the
class-to-pattern table permuted per round from the seed and machines replicated
with a pattern key (and a per-viewer "mine / partner's / neither" for the trim)
rather than a class index.

**The dial (G12).** A dial starts the round **unset** (no position). A turn is
one action that names one setting in 1..`dial_settings`; there is no rotating
through intermediate positions, so nothing is evaluated on the way.

**States of a machine:** `idle → live → committed`, and `live → rejected → live`
on a wrong turn, after `actuation_reset_seconds`. A committed machine cannot be
changed, and is not offered as turnable (a turn on one is refused without
penalty, §5). Machines that are not in the Procedure (decoys, §3.1) stay `idle`
all round, and turning one is a wrong turn.

**Edge case: a machine in a blacked-out room.** Its tag, key class and dial
become unreadable at range, and **its required setting can no longer be read by
its helper** (§5). Pings remain visible, because a ping is a light source.
Turning is still possible. Blackout removes information, not access, so a
setting remembered from before the lights went is still worth something.

**The decision it produces:** none directly. The world is the substrate. It
makes *where you are standing* decide *what you can know*, and that is what
makes §4's channel spatial.

---

## 2. Look — observation and the lens

**Inputs:** player position, player light direction.

Two classes of fact, and the distinction is the whole asymmetry:

- **Public facts:** tag, key class, dial position, live lamp, committed. Anyone
  with light on the machine reads them.
- **Lens facts:** the *required setting*. Rendered only for the player whose
  **lens** covers the machine's key class, only within `lens_read_range_studs`,
  and only while their light is on it.

**Rules:**

- A player's lens covers exactly one key class, fixed for the round (`roles.md`
  §2), and stored, not recomputed (SEAT-003).
- **The required setting is never replicated to a client that does not hold the
  lens** (B4). A non-holder's client must not be able to read it from its own
  memory. This is unchanged and is still the single most important trust
  property in the game.
- Reading is free, instantaneous and untimed. There is no scanning minigame.

**Edge cases:**

- *Two players at the same machine.* Both read the public facts. Only the helper
  sees the glow. Standing together does not share a lens.
- *A helper outside `lens_read_range_studs`.* They see the machine, but no glow.
  To help, they have to walk over. This rule is the reason the design is
  spatial, and it is why a range, and not only light, is specified.
- *A player whose lens covers their own key class.* Impossible by construction:
  σ is a derangement (`roles.md` §2).

**The decision it produces:** *where to stand.* Standing at your partner's
machine lets you read it. Standing at yours lets you turn it. You cannot do both
at once, and that is the tension §3's two tracks turn into a decision.

---

## 3. The Procedure

The objective. There is one win condition: every step of the Procedure committed
before the clock expires.

### 3.1 The steps — what setting, on which machine

The Procedure is `procedure_length` **steps**. Each step is *turn machine m to
its required setting v*. The generator's constraints:

- There are more machines than steps: `actuator_count = procedure_length ×
  actuator_redundancy`. The rest are **decoys**. A helper who reads all of their
  partner's machines sees more required settings than matter, and does not know
  which ones matter, because the order is not theirs to see (§3.2).
- Every key class has at least one step (`INV_every_class_has_a_step`). This is
  all k-essentiality now needs (§6.3).
- Steps are spread across classes as evenly as `procedure_length / n` allows
  (`INV_balanced_steps`), so nobody is a passenger.
- **At n = 5 and 6 (G3)** `procedure_length` stays 8
  (`procedure_length_depends_on_n`): steps per class are 2,2,2,1,1 and
  2,2,1,1,1,1, with the seed choosing which classes get two. Each class has
  exactly one decoy per step (`actuators_per_class`, `INV_class_machines`), so the
  total stays `actuator_count`. Only generation-time n matters here, and that is
  4..6; n = 3 arises only from a disconnect, after generation.

> **Superseded 2026-09-30 by brief §0d #19: the value-mark bijection.** The second
> pass required the Procedure's required values to be pairwise distinct and to
> exhaust the mark alphabet (`mark_alphabet_size = procedure_length`), so that "a
> value-mark uniquely names an operation". That existed to let a group *discover*
> that marks had become referents, which is the evolving meaning the guideline
> forbids. Nothing now needs a setting to name a step: a ping names it by
> pointing. Settings may repeat across steps.

### 3.2 The tracks — what order, and who knows it

The Procedure is split into `procedure_tracks` **tracks**, each an ordered
sequence of steps. Within a track steps must be done in order. The tracks are
independent of each other, except at the end.

- A step's **position** is its index among the uncommitted steps of its track
  (0 = first uncommitted). An ordinary step is **live** when its position is 0.
  Its machine's live lamp is lit.
- **The finale.** The last step of every track forms one **paired operation**:
  the two machines must both be turned correctly within
  `simultaneous_window_seconds` of each other, or neither commits. **The finale
  goes live together (G12, `finale_live_together`; a rule change):** both finale
  steps are live exactly when both are at position 0, that is, when every
  ordinary step of both tracks is committed. Before that, a finale step at
  position 0 is still `waiting` and its lamp is dark.
- **The partner lamp (G5).** Each finale machine has one. Machine A's partner
  lamp is lit while the finale is live **and** the key holder of machine B's
  class is within `partner_lamp_range_studs` (= `turn_range_studs`) of machine
  B, and the same the other way round. So the lamp at your machine says "your
  opposite number could turn theirs right now", and the world, not a preset,
  tells a pair they are both in position. It is updated from the server's
  position samples, no less often than `trace_position_sample_seconds`.
- **Private turn cues.** A turner is shown, privately, when one of their own
  machines is live ("your ◆ is live", with a direction arrow),
  and which of their machines is **next**: a step of theirs that is not live and
  whose position is ≤ `turn_cue_lookahead`. A turner with steps in both tracks can
  hold two cues at once. A finale step waiting on the other track is "next" by
  this rule, never "live". Nobody else is shown anyone else's cues. **T10
  answered (c) by the operator, 2026-09-30**: private cues, plus the public
  progress bar below.
- **Where the cue's arrow points (Q-G2, derived, 2026-09-30).** In the
  machine's room: at the machine. Elsewhere: at the **next doorway on a shortest
  doorway path** from the player's current room to the machine's room, ties
  broken toward the lower-indexed next room. Derived from the floor (§0d #14): a
  straight-line arrow through walls asks a 7-year-old to path-find, and
  path-finding in six rooms is not a skill this game rewards. The ceiling is
  *which* step and *when* (`loop.md` §1.2), not *how to get there*. It leaks
  nothing: the doorway graph is public geometry and the target is the player's own
  machine. Blackouts do not change it (they remove information, not access). It
  applies only to your own cues; nothing points you at your partner's machine,
  which you find from their `Help` beacon or by knowing the facility.
- **The public progress bar.** Every player's HUD shows the same bar. It is the
  only public view of the order, and it is specified by what it must not show as
  much as by what it shows, so that it cannot turn into the public board that
  T10 (b) was rejected for.

  | The bar shows | Rule |
  |---|---|
  | **steps committed, out of `procedure_length`** | `progress_bar_segments` = `procedure_length` identical segments, filled left to right as steps commit. The fill order is the count only: segment 3 means "the third commit", never "step 3" |
  | **which segments are the finale** | the last `procedure_tracks` segments are marked as the finale (`progress_bar_marks_finale`). This adds nothing: the finale is always the last commits by construction. It gives a child "the big one at the end" |

  | The bar must **never** show | Why |
  |---|---|
  | which step is live or next, in any track | that is the order, and the order is private (anti-quarterback device 4) |
  | per-track progress, or which track a commit belonged to (`progress_bar_split_by_track` = false) | "track B is behind" is a routing instruction to a planner, and it is most of what a public board would say |
  | any machine, tag, room, key class, colour or player for any segment | identity is what turns a count into a plan |
  | the finale's armed or partner-lamp state | the partner lamp is world state, readable in person only |
  | time, pace, par, or a forecast | par belongs to the trace, after the round |

  **The bar is a function of public state only.** Every commit is already public
  (the room brightens, a tone plays facility-wide, §5), so the bar
  adds reach, not information: it tells you *how many* from anywhere, and never
  *which*. It updates on commit only. An armed finale machine does not move it,
  and the two finale steps commit together, so the bar's last move is always a
  jump of `procedure_tracks`.

  **It does not touch the preset or ping count.** The bar is game state that no
  player originates: nothing is sent, selected or sequenced. It sits under CA-4
  (§4.6) with the live and partner lamps, and outside `presets_plus_pings_max`.

Why there are two tracks, derived rather than preferred: with one track exactly
one step is live at a time, so no player ever needs to be in two places at once,
and the decision in `loop.md` §1.2 never arises. Two is the minimum at which a
player can be both the turner of one live step and the helper of another.

**States of a step:** `waiting → live → committed`; a finale step is
`waiting → live → armed (turned, window open) → committed`, or back to `live`
if the window closes.

**Edge cases:**

- *A turn on a machine that is not live* (a decoy, or a step not yet reached):
  rejected, instability +1. Out of order costs the same as a wrong setting.
- *One track finishes its ordinary steps long before the other.* Its finale
  machine waits, lamp dark, and its turner's cue shows it as "next". It goes
  live only with the other (above). The early pair is free to go and help the
  late track, which is the choreography `loop.md` §1.4 means. *(Revised
  2026-09-30, G12: it used to "go live and wait", which lit a machine that no
  turn could complete.)*
- *The finale at n = 3, after a disconnect.* The two finale turners are always
  ring-neighbours in a 3-cycle, so one of them is also the other's helper. It is
  still solvable: they ping their partner's finale setting first (a ping
  persists) and then walk to their own machine. The trace records the round as
  degraded (`roles.md` §6).

> **Superseded 2026-09-30 by brief §0d #19: order fragments.** The second pass
> distributed `order_fragments_per_player` statements of the form *the operation
> whose value is x precedes the one whose value is y*, read at a terminal and
> relayed by tokens. Relaying such a fact without a text channel would need an
> *ordered sequence of references* (point here, then there, meaning "before"),
> and that is "gaining meaning when sequenced". The rule this pass draws from
> it: **no fact in the game may need a sequence of references to transfer.**
> Order is therefore never relayed. Each turner sees their own place in it,
> privately, and the world shows what is live. The progress bar is consistent
> with this rule: it is a single count, and a count needs no sequence of
> references.

**The decision it produces:** *act now or wait.* A step is live, and your helper
is not here. Guess the dial, or call and wait? And if two steps need you, which
first? See `loop.md` §1.2.

### 3.3 The round's public state on the HUD (G8)

Beside the progress bar, and the same for every player. Round-public state, like
the phase and the bar; never in the per-player projection.

| Element | Rule | Label |
|---|---|---|
| **Round clock** | shown (`hud_shows_round_clock`). Form: `hud_round_clock_form`, provisionally a numeric mm:ss countdown, always visible, with each `instability_clock_penalty_seconds` shown as a brief −20 | shown: derived. Form: **taste-pending, T21** |
| **Instability** | `instability_max` pips, filled as it rises (`hud_shows_instability`) | derived |
| **Blackout thresholds** | the pips at multiples of `instability_blackout_threshold` are marked (`hud_marks_blackout_thresholds`). Which room will go dark is not shown; it is drawn at the crossing | derived |
| **Nothing combines them** | no pace line, no "on track / behind", no par, no forecast built from the clock and the bar (`hud_clock_separate_from_progress`) | derived from the bar's rule above |

---

## 4. The channel — pings and presets

**Replaced 2026-09-30.** The second pass's signal channel is summarised in §4.7.
Read §4.3 before changing anything in this section: its rules are compliance
requirements, not preferences.

### 4.0 The rule the section is built on

> **Presets carry intent. Pings carry reference. The world carries facts.**

A fact (a required setting) crosses from one head to another in exactly one way:
the helper stands at the machine, sees the glow, and pings that setting. The ping
itself says only "this". It is informative because of *who* made it and *where*,
and the ring (`roles.md` §2) makes that unambiguous. Presets never carry a fact
at all. They say what someone is doing or wants.

### 4.1 The ping

**Inputs:** the sender's light direction and a Ping press. The client proposes a
target, and the server decides (B4: a target is a claim).

**Targets**, and only these three kinds:

| Target | Meaning in play |
|---|---|
| a **dial setting** on a machine | "this setting". The fact-bearing ping |
| a **machine** | "this machine" |
| a **doorway** | "this way" |

There are no free-position pings on floors or walls. That is derived: a free
position is a drawing surface, and the set above is the minimum the design uses.

**Rules:**

- **One active ping per player.** A new ping replaces your previous one. Nobody
  can lay out a pattern of pings.
- A ping lasts `ping_display_seconds`, or until the machine it targets commits,
  or until you replace it.
- A sender may ping at most once per `ping_rate_limit_seconds`. **Only a ping
  that is broadcast starts that cooldown (G9, `channel_limiter_consumed_by`).**
  A ping the server refuses for its target is not a send: it is not shown to
  anyone, the sender is told it did not land, and they may try again at once,
  subject only to `channel_attempt_min_interval_seconds`.
- Server validation: the target must exist, must not be a committed machine or
  a setting on one, be within `ping_range_studs` of the
  sender, and be in the sender's line of sight. `ping_range_studs` =
  `lens_read_range_studs`, derived: you can point at exactly what you could
  read, and no further.
- **Broadcast to every player, attributed by the sender's colour**
  (`ping_reveals_sender`). Your helper's current ping is also shown on your HUD
  as an edge arrow. That is safe, because your helper's identity is already in
  your projection (`roles.md` §6).
- **No text.** A ping is a marker and a colour. It has no label, no kinds and no
  words, and that keeps it outside "predefined text" (CA-1).
- The server logs every ping (sender, target, position, time) for the trace
  (§7). Players do not see the log until the round ends.

**States per player:** `no ping → active(target) → expired`, with `cooling`
while rate-limited.

**Edge cases:**

- *A non-helper pings a setting.* Allowed, and it carries no knowledge. It is
  somebody pointing. The HUD distinguishes "your helper's ping" from anyone
  else's, and that distinction is part of the floor (`loop.md` §1a).
- *A helper pings a setting in a blacked-out room.* Allowed. They cannot read
  the glow there, so it is a guess or a memory, and the trace marks it as
  unread.
- *A ping on a machine that commits.* The ping clears. A stale marker on a
  finished machine would teach the wrong thing.

### 4.2 The preset wheel

**Inputs:** one choice from `preset_count` presets.

The list the operator chose (**T12**, ryanczhang7, 2026-09-30: the words are taste; the count and the rules are
not):

| Preset | Intent it states, completely, on its own | Phases |
|---|---|---|
| `Ready` | I am in position | Round, Lobby |
| `Wait` | hold | Round |
| `Go` | act now | Round |
| `Help` | I need my helper, here | Round |
| `On my way` | I am coming | Round |
| `Follow me` | come with me | Round |
| `Got it` | acknowledged | Round |
| `Thanks` | thanks | Round, Post |
| `Nice one` | good play | Round, Post |
| `Well played` | good game | Post |

**Rules:**

- **Broadcast to every player.** Never addressed, never directed.
- **Attributed** by name (`preset_reveals_sender`) and **positioned**: shown as a
  bubble over the sender and as a beacon at their location that others can see
  through walls, for `preset_display_seconds`
  (`preset_reveals_sender_position`). Derived from the guideline's "stand alone
  and be complete": "Help" without a place is not complete.
- **Rate limit: one preset per `preset_rate_limit_seconds` (= 10) per player,
  across the whole wheel.** It is one limiter per player, not one per preset,
  because the guideline says "per send".
- **Filtering:** every preset string passes `TextService:FilterStringAsync()`
  server-side before it is broadcast. **Fail closed:** if filtering errors, the
  preset is not sent, the sender is told, and the rate limit is not consumed.
- **The beacon stays where the preset was sent (Q-G7, derived, 2026-09-30).**
  It marks the sender's position at the moment of sending and does not follow
  them. Derived three ways: a preset is one send and says one complete thing
  (C7), and `Help` means "here", the place where help is needed, not wherever
  the sender wanders next; a beacon that tracked the sender through walls for
  `preset_display_seconds` would be a player-tracking feature the design never
  chose; and it is what the payload carries. The cost is `Follow me`, which would
  read better attached to the sender. At 5 s it hardly matters, and it is not a
  reason to track players.
- **Presentation** (for the Lead Designer, as requirements): icon plus word, so a
  non-reader can use it; visually distinct from native chat; no terminal
  punctuation; labelled **"system preset"** wherever it appears inside a chat
  surface. **Delivery route (2026-09-30):** the sanctioned implementation for a
  preset wheel is reported to be `TextChatService` system messages
  (forum-reported, effective 2026-01-09; engineering to confirm, CA-6). If so,
  presets *do* appear in the chat surface, as system messages labelled
  "system preset", in addition to the in-world bubble and position beacon,
  which carry the gameplay meaning. The earlier provisional choice (never route
  presets into chat) is superseded by that report.
- A preset is legal only in the phases its row lists. The remote's own legal
  phases are the union (Lobby, Round, Post), which the net wrapper's phase check
  enforces (NET-002); the per-preset list is checked by the handler. **A preset
  refused by its own phase list is not a send (G9):** it is not broadcast and does
  not start the 10 s cooldown, the same as a failed filter. The wheel should not
  offer an out-of-phase preset at all; this rule covers the race at a phase
  boundary.
- The server logs every preset for the trace.

**States per player:** `ready → cooling (preset_rate_limit_seconds) → ready`.

**Presets are enrichment, not a dependency.** The canonical schedule the
generator verifies (§6.3, `INV_traversal`) uses no presets. A group that never
opens the wheel can win. That is amendment 7's rule, applied one level down: the
game is fully playable with no free-form communication, and also with no preset
communication.

### 4.3 Compliance, as design rules

Each rule quotes the requirement it implements (Roblox, *Preset system
guidelines*, changed 2026-07-07) and says how it is checked.

| # | Rule | Source | Checked by |
|---|---|---|---|
| C1 | `preset_count` + `ping_kinds` ≤ 12, **across the universe** | "Limit the number of presets displayed to 12 or less for your Universe" | a headless test over the preset table; any future mode shares the same 12 |
| C2 | **No preset names a fact**: no setting, colour, shape, tag, room, number, ordinal, direction, yes or no | "immediate gameplay intent, not dialog"; no "slang that could carry hidden or evolving meanings" | review of the preset table (it is 10 rows), plus a headless denylist test for colour, shape, number and ordinal words |
| C3 | **No fact is cheaper to send by sequence than by a single ping** (`INV_ping_dominates`) | "must not gain meaning when combined, repeated, or sequenced ... 'say anything, just slower'" | structural: every transferable fact is a required setting, and a required setting has a one-ping form whenever it can be read at all |
| C4 | One preset per 10 s per player | "Add a rate-limit (10 seconds per send)" | the net wrapper's rate stage (NET-003), declared at 10 |
| C5 | Every preset string filtered | "All presets must go through `TextService:FilterStringAsync()`" | server-side, fail closed |
| C6 | "system preset" label in chat; visually distinct; no terminal punctuation | the guideline's requirements list | Lead Designer; a headless test that no preset string ends in `.`, `!` or `?` |
| C7 | Each preset complete alone | "Each preset must stand alone and be complete without requiring a response unrelated to gameplay" | the position beacon; `Got it` is the only response-shaped preset, and "'Help' followed by 'OK' is acceptable" |
| C8 | No question/answer structures, no greetings, no yes/no | the "not allowed" list | the preset table has no question, no greeting and no polarity pair |
| C9 | Broadcast only | the page's line between presets and "free-form, two-way, directed" conversation | the remote takes no recipient argument |

**Why C3 is the one that matters.** The second pass failed the guideline because
its *difficulty* lived in sequence: the only way to send a pairing was two marks
in an agreed order. This pass removes the incentive rather than trying to police
the behaviour. Pointing at a setting is always faster and clearer than any code a
group could build from ten presets at one per 10 s. A group *could* agree that
"Wait, Go" means something. It would gain nothing by it.

### 4.4 What the channel deliberately cannot carry

- **A setting from anywhere but the machine.** No preset names one, and a ping
  must be in range and in sight.
- **Order.** No channel relays "this before that" (§3.2).
- **Addressing.** Nothing is sent to one player.
- **Questions.** Nothing asks. `Help` states a need.
- **Anything invented.** There is no grammar to build, and no preset gains a
  meaning it was not shipped with.

The second pass's version of this list was the *puzzle*. This one is a
**compliance boundary**, and the puzzle is elsewhere (§2, §3.2, §5).

### 4.5 The decision it produces

The channel no longer holds the central decision. Its job is to make the spatial
decision *possible* without words:

> *Where do I need to be to show what I know, and when do I ask someone to come
> to me?*

`Help` is the preset that decision uses most. When to send it (before your step
is live, or only once it is) is a ceiling skill (`loop.md` §1a: anticipation).

### 4.6 Compliance assumptions — for the Lead PO to verify

These are readings of a published guideline, not rulings. Each says what the
design loses if the reading is wrong.

| # | Assumption | If wrong, the design loses |
|---|---|---|
| **CA-1** | **A ping is not a preset.** The guideline covers "predefined text", and a ping has no text. **Status, 2026-09-30: unconfirmable.** The Lead PO found no official Roblox page on pings and no staff answer; forum reports say only that gestures and animations are accepted. **Decision: take the stricter reading on rate** (`ping_rate_limit_seconds` = 10, derived). The count was already computed with the ping included | Already paid, by construction: the count is 11 ≤ 12, and `INV_traversal` was computed at 10 s, so no instance became unwinnable. What the design did lose: a mis-ping takes 10 s to correct, and doorway-pinging ("this way") is sluggish. The residual risk is that a sequence of setting-pings could in principle be a slow cipher. The mitigation (**allow setting-pings only on live machines**, `ping_settings_live_only`) was **declined by the operator, 2026-09-30 (T20 = (a))**, because it costs early pinging, a ceiling skill. The risk is accepted, bounded by the 10 s rate, one active ping per player and 4-setting dials. **`playtest.md: P-S` is the protocol that would reopen it**: if groups are seen building codes from ping sequences, the switch goes back to the operator |
| CA-2 | Pointing a light, walking, and turning a machine are world interaction, not communication | Nothing designable. Every co-op game on the platform relies on this reading |
| CA-3 | A preset shown with the sender's position is still one standalone preset, not a combination. **Supported by the guideline's own allowed examples**: "Defending this area" and "Enemy nearby" are listed as acceptable presets, and each is complete only because it is read with the sender's location. `Help` shown at the sender's position is the same shape | `preset_reveals_sender_position` → false. `Help` then needs the turn cue and live lamps to be found, and "complete on its own" becomes arguable. T6 reverts to #16's answer |
| CA-4 | Live lamps, committed lights, partner lamps **and the progress bar** are game state, not communication | The finale needs a preset countdown (`Ready`, `Go`), and the floor gets harder for children. The progress bar is the easiest of these to defend, because no player originates it; if even it were counted, it would be removed rather than counted, since the design does not depend on it |
| CA-5 | Broadcasting to all keeps presets outside "two-way, directed" conversation | Nothing. This is the page's own distinction |
| CA-6 | Filtering developer-authored strings with `FilterStringAsync` per send, using the broadcast form of the result, satisfies C5. **The sanctioned implementation for a preset wheel is reported to be `TextChatService` system messages** (forum-reported, effective 2026-01-09). If that holds, presets are delivered as system messages inside the chat surface, and C6's "system preset" label applies to every one of them. **Engineering to confirm both the filtering API shape and the delivery route** | engineering only; plus the presentation change in §4.2 (presets in chat, labelled) if the route is confirmed |
| CA-7 | "12 or less for your Universe" counts distinct presets, not sends, and counts lobby and post-round presets too | the spare slot. Any future mode (a tutorial, a hub) must fit within 12 − 11 = 1 new preset |
| CA-8 | "Relevant to the current game mode" permits the neutral presets (`Thanks`, `Nice one`, `Well played`) during a round | three presets move to Post only. Cosmetic |

### 4.7 Superseded 2026-09-30 by brief §0d #19: the signal channel

The second pass's §4, summarised. The verbatim text is at commit `38dc58a`.

| Old rule | What it was | Disposition |
|---|---|---|
| 4.1 message format | `(sender_id, token, server_timestamp)` from a radial wheel of `vocabulary_size` = 16 | **superseded.** 16 > 12, and the tokens were the language |
| 4.1 budget | `signal_budget_per_player` 12, non-transferable, `signal_reserve` 2 locked until 90 s remain | **superseded.** No budget; no ping budget either (T11, operator, 2026-09-30) |
| 4.1 rate | 1.5 s per token | **superseded** by 10 s (presets) and `ping_rate_limit_seconds` |
| 4.1 ephemerality | shown 6 s, `signal_log_depth` 0 | **superseded.** Pings persist; presets carry no facts |
| 4.1 sender's room | not revealed (T6, then §0d #16) | **superseded, and transformed** (`loop.md` §5) |
| 4.2 vocabulary | 8 abstract marks, `FIRST`/`BEFORE`/`AFTER`, `YES`/`NO`, `AGAIN`/`WAIT`/`GO` | **superseded.** Marks and ordinals are fact-bearing; YES/NO is a Q/A structure and a binary code. `WAIT`/`GO` survive as presets with no information role |
| 4.3 what it cannot express | no binding, no deixis, no scope, no quantity, no addressing | **inverted.** Binding and deixis are now free (pointing). Addressing is still absent |
| 4.4 the Expressibility Rule | every required fact sendable, some not in one token; bridged by inventing a grammar from adjacency | **superseded.** That bridge is exactly the forbidden mechanism. C3 replaces it: every fact is sendable in *one* ping |
| 4.4 the second lossy axis | attentional: ephemeral, serial, competing with looking | **replaced** by the spatial axis (`loop.md` appendix A4) |
| 4.5 the decision | which single fact of the many I can see is the one the group cannot deduce without me? | **superseded.** See `loop.md` §1.2 |
| — recall (§0d #17) | spend a token to re-show the last three signals | **superseded** before it was specified (`loop.md` §5) |

---

## 5. Actuation, instability and the dark

**Inputs:** a player at a machine of their own key class, choosing a dial
setting.

**Rules:**

- Server-validated: sender identity, key class match, proximity (within
  `turn_range_studs` of the machine, in the server's view of the character, G5),
  phase legality, rate limit (`turn_rate_limit_seconds`) (B4).
- **Refused, not evaluated, and never penalised (G12).** A turn that fails any
  of those checks, or names a committed machine, or names a machine whose dial is
  still resetting (`actuation_reset_seconds`), or names a finale machine that is
  already armed, is refused: no instability, no clock penalty, no failure tone,
  and it does not reset the dial. The turner is told why. Only an **evaluated**
  turn can cost anything. Derived: instability prices a wrong *decision* about
  the dial, and none of these is one.
- The server evaluates: is this machine live, and is the chosen setting its
  required setting?
  - **Both true:** commit. The machine locks, its room brightens, and a
    confirming tone plays. Progress is public.
  - **Either false:** reject. `instability += 1`. The dial shows the chosen
    setting in `rejected` state, returns to unset after
    `actuation_reset_seconds`, and a failure tone plays facility-wide. This is
    the same for a live step with the wrong setting, a waiting step, and a decoy.
- **Whether the rejection says which was wrong** is
  `actuation_failure_is_diagnostic`. **T13 answered by the operator, 2026-09-30:
  it does** (*true*), for an all-ages floor, reversing the second pass's
  *false*.
- **Who is told what (Q-G4, confirmed 2026-09-30, derived).** The diagnostic
  result (`wrong_setting`, `not_live`, `armed`, `committed`, or a refusal reason)
  goes **only to the turner**. Everyone else gets what the world already shows:
  one failure tone facility-wide, **the same tone for both kinds of failure**, the
  instability pips rising, and, for anyone who can see the machine, the dial
  snapping back. T13 made failure diagnostic so that the player who failed can
  learn from it; nobody else needs the distinction, and a public diagnostic
  would be a second, facility-wide report on every turn that a planner could use.
  A bystander who can see the live lamp can work it out anyway, which is fine:
  that is reading the world in person.
- **The dial control's pre-selection (Q-G5, kept, derived).** When the turner
  opens the dial and their helper has an active setting-ping on this machine,
  that detent is pre-selected, and turning still takes a second, deliberate
  action (`design/README.md` D-7). Kept, because it is the floor (§0d #14):
  "turn it to your helper's ping" should not ask a 7-year-old to match a marker
  to a button. It does not touch the decision: when the helper has pinged, the
  right move was never in doubt, and when they have not, nothing is pre-selected
  and wait-or-guess is untouched. Two limits: it pre-selects **only the helper's**
  ping, never another player's, and never on a machine that is not the turner's
  own. What it costs is one playtest reading, which moves (`playtest.md: P-K`).
- **The finale:** each finale turn arms its machine for
  `simultaneous_window_seconds`. If the other is turned correctly inside the
  window, both commit. If the window closes, both disarm and instability rises by
  1 (one operation, one penalty). **Exactly (G12):**
  - a correct turn on a live finale machine, with neither armed: arm it and open
    the window at the server time of that turn;
  - a correct turn on the other finale machine at or before the window's end:
    both commit, together, at that time;
  - a **wrong** turn on either finale machine, armed partner or not: rejected as
    any wrong turn (+1), and if a window is open it closes now and both disarm
    with **no second penalty**, since it is one failed attempt at one operation;
  - the window reaching its end with one machine armed: both disarm, +1;
  - a disarmed machine's dial resets after `actuation_reset_seconds` like any
    rejection.
  In every case a failed attempt at the finale costs exactly 1.

**Instability effects** (thresholds in `tuning.md`):

| Effect | Rule |
|---|---|
| Clock | each point removes `instability_clock_penalty_seconds` immediately |
| Blackout | at each multiple of `instability_blackout_threshold`, `blackout_rooms_per_threshold` rooms go dark: helpers can no longer read required settings there, and tags and dials become unreadable at range. **Permanent** (T15, operator, 2026-09-30); the tone of the dark is still open, with the Lead Designer |
| Loss | at `instability_max`, the round ends in failure regardless of the clock |

Blackout selection is server-side and **weighted toward rooms with live or
waiting steps**, so degradation bites. **Exactly (G7):** at each crossing, draw
`blackout_rooms_per_threshold` rooms without replacement from the rooms not yet
dark, with probability proportional to the room's weight: the sum over its
uncommitted steps of `blackout_weight_live_step` (live or armed) or
`blackout_weight_waiting_step` (waiting). Decoys and committed steps weigh 0.
If every lit room weighs 0, draw uniformly among lit rooms; if none is lit,
nothing happens. A dark room is never drawn again (`blackout_repeat_allowed` =
false). The draw uses `rng:derive("blackout")` from the round seed. A crossing
is instability reaching a multiple of `instability_blackout_threshold` below
`instability_max`; instability only ever rises by 1, so crossings happen one at
a time. A blackout darkens information, not access: doorways stay open and
walking times are unchanged (so §6.2 invariant 6 holds trivially, because no
room starts dark).

**States:** the round is `running → won | lost(clock) | lost(instability) |
unwinnable | no_contest`. These are exactly the outcomes the M1 phase machine
already accepts as events. It does not compute them.

**Outcome vocabulary (G12).** The phase machine's `Outcome` is
`{ result, reason }` with `reason` opaque to it and supplied by M3. M3's pairs:

| result | reason | When |
|---|---|---|
| `won` | `procedure_complete` | the last step (the finale) commits while the clock is above 0 |
| `lost` | `clock` | the remaining clock reaches 0, including by an `instability_clock_penalty_seconds` deduction |
| `lost` | `instability` | instability reaches `instability_max` |
| `no_contest` | `below_quorum` | already built (M1) |
| `no_contest` | `generation_failed` | the generator exhausted `generator_attempts_max` (§6.2). No loss is recorded: the server failed, not the group |

`unwinnable` has **no trigger in M3** (§8): the phase machine keeps accepting it,
and no M3 story needs to emit it.

**Same-tick ordering (G12).** Server events are handled in arrival order. When
one event causes several, they resolve: a commit that completes the Procedure
wins, then instability reaching its max, then the clock. So a finale commit
arriving before the deadline wins even if the clock would expire in the same
frame, and a wrong turn that both reaches `instability_max` and zeroes the clock
records `instability` (§8).

**Edge cases:**

- *Two players turn the same machine.* Impossible: a machine has one key class,
  and one holder, except after a disconnect transfer, which is still one player.
- *Finale: the second turn arrives after the window.* Both disarm, instability +1.
- *A turn with no helper ping* (a guess). Legal. A right guess commits and costs
  nothing. The trace records it as a guess (§7).

**The decision it produces:** *how much certainty is a turn worth.* A wrong turn
costs clock and moves the facility toward the dark, and the dark takes away the
only way settings are read.

---

## 6. The generator

The hardest system in the project, and the one that carries A2 #4 (difficulty in
systems, not asset volume).

### 6.1 What it produces

| Component | Shape |
|---|---|
| layout | `room_count` rooms and their doorway graph |
| machine placement | `actuator_count` machines to rooms |
| tags | a symbol per machine, distinct within each key class |
| **required settings** | a dial position per machine |
| **the Procedure** | which `procedure_length` machines are steps, split into `procedure_tracks` ordered tracks |
| **the finale** | the last step of each track: machines in different rooms, of non-adjacent key classes when n ≥ 4 |
| **σ** | a cyclic derangement over players (already built: SEAT-001) |
| **par** | the canonical schedule's duration (§6.3) |

Seeded, so an instance is reproducible. The ring draws from `rng:derive("seats")`
and the instance from `rng:derive("instance")`, so neither moves the other (a
property SEAT-001 already built for).

### 6.2 Structural invariants

Hard constraints. The generator rejects and resamples.

| # | Invariant | Status |
|---|---|---|
| 1 | `INV_no_self_value` (required value ≠ tag) | **superseded**: tags and settings use disjoint alphabets (§1) |
| 2 | `INV_tags_distinct_in_class` | kept |
| — | `INV_values_distinct` (in-Procedure values exhaust the mark alphabet) | **superseded** (§3.1) |
| 3 | `INV_cyclic_sigma`: σ is one n-cycle | kept; already enforced by construction in `Ring.luau` |
| 4 | `INV_finale`: the finale's machines are in different rooms at least `paired_room_distance_min` apart, of non-adjacent key classes when n ≥ 4 | revised from "every paired operation" |
| 5 | `INV_every_class_has_a_step`, and `INV_balanced_steps`: step counts per class differ by at most 1 | revised from "every player holds a pairing and a fragment" |
| 6 | no room is reachable only through a room that starts dark | kept |
| 7 | `INV_track_alternates`: consecutive steps in a track have different key classes | new. Stops one player camping a track |
| 8 | `INV_layout`, `INV_room_capacity`, `INV_class_machines`, `INV_settings_uniform` | new 2026-09-30 (G1–G4, G12); statements in `tuning.md` §2 |

**Resampling and failure (G11).** An **attempt** draws a whole instance (layout,
placement, tags, settings, Procedure, finale) and computes par; the attempt is
accepted if every invariant in §6.2 and §6.3 holds. Attempt *i* (from 1) draws
only from `rng:derive("instance"):derive("attempt-" .. i)`, so an instance is a
pure function of the seed and the attempt number, and adding a draw inside one
attempt cannot shift another. The first accepted attempt is the instance. If
`generator_attempts_max` attempts all fail, the round does not start: it resolves
`no_contest` / `generation_failed` (§5), the lobby reopens, and the seed and the
invariant each attempt failed are logged. No fallback instance exists, because a
hand-authored one is content (A2 #4) and would be the one layout players learn.
A headless seed sweep (at least 1000 seeds) is the real guarantee: every seed
must be accepted within the bound, and the sweep reports first-attempt
acceptance, which `tuning.md: generator_attempts_max` says what to do with.
Tests pin the invariants and the determinism, never a particular sample.

### 6.3 Information and timing invariants

**I1 — k-essentiality, re-derived.** Each required setting of class k(q) is
readable only by σ⁻¹(q), and each class's machines are turnable only by q. With
`INV_every_class_has_a_step`, removing any one player leaves at least one step
whose setting nobody can read, which has `dial_settings` ≥ 2 candidates, and at
least one step nobody can turn. So **no n−1 players can finish with certainty**.
The second pass had to *construct* this for the value layer; here it follows
from the ring and one counting invariant.

**I2 — the centralisation bound. Superseded 2026-09-30.** It required
`signal_budget_per_player < view_enumeration_tokens` so that three players could
not brief a fourth. There is no longer any channel that carries a setting from a
distance, so briefing is impossible **structurally** and no inequality needs to
hold. `INV_centralisation` is retired.

**I3 — the rate bound. Replaced by `INV_traversal`.** The binding resource is
no longer transfers per second. It is **bodies per second**. The generator
computes a **canonical schedule**:

- a naive plan: steps taken in track order, alternating tracks; for each step
  the helper and the turner walk (shortest doorway path, `room_traversal_seconds`
  per edge) to the machine, the helper pings, and the turner turns;
- **no anticipation, no guessing and no presets**;
- **pings at 10 s**, which is `ping_rate_limit_seconds` since the Lead PO's CA-1
  decision (2026-09-30), and equal to the preset rate. If a later decision ever
  lowers the ping rate, par stays computed at 10, so that the invariant never
  depends on CA-1 being read in our favour.

**The canonical schedule, exactly (G6).** A test can pin par from this alone.

    walk(a, b)   = (doorway edges on a shortest path from room a to room b)
                   × room_traversal_seconds            -- 0 when a = b
    helper(s)    = the player whose lens is the key class of s's machine
    turner(s)    = the player who holds that key class
    room(s)      = the room of s's machine

    pos[p] = spawn_room for every player p;  t = 0
    order  = T1[1], T2[1], T1[2], T2[2], ... over the ORDINARY steps
             (tracks as numbered by the generator, track 1 first; if one track
              runs out of ordinary steps first, the rest of the other follow in
              order - unreachable today, since steps_per_track is an integer)
    for each step s in order:
        d = max(walk(pos[helper(s)], room(s)), walk(pos[turner(s)], room(s)))
        t = t + d + par_ping_seconds + par_turn_seconds
        pos[helper(s)] = pos[turner(s)] = room(s)
    finale, sub-steps F1 and F2 (one per track):
        d_j = max(walk(pos[helper(F_j)], room(F_j)), walk(pos[turner(F_j)], room(F_j)))
        t = t + max(d_1, d_2) + par_ping_seconds + par_turn_seconds
    par = t

Read as rules: all players start together in `spawn_room`; steps are taken **one
at a time** (no anticipation: nobody moves toward a step before it is the current
one); for each, the helper and the turner **walk in parallel** and the step
waits for the later arrival; the ping is charged **once per step**, a flat
`par_ping_seconds` (= 10); the turn is `par_turn_seconds`. The finale is one
unit: its two pairs walk in parallel, each pays its own ping in parallel, and
the two turns are simultaneous, so the window is always met. At generation time
n ≥ 4 and `INV_finale` makes the finale's four participants four distinct
players, so the parallel reading is well defined. Players not in a step do not
move.

Par is computed **once, at generation**, from the start positions. It is used
by `INV_traversal` and shown in the trace. It is **not** recomputed during the
round, and it is **not** a test of whether the round can still be won (§8).

Its duration is **par**. The invariant is:

    par × schedule_slack  ≤  round_seconds

This is what stops the generator emitting an instance that is solvable in
principle and impossible in seven minutes. It is also what keeps the floor low:
a group that does nothing clever still fits (`loop.md` §1a). Par is shown in the
trace as the thing a good group beats.

### 6.4 What varies, and what does not

Varies per instance: everything in §6.1. Per band: nothing; the operator chose one band for v1 (T17, 2026-09-30). If a later version adds a
band, its levers are `dial_settings`, `turn_cue_lookahead`,
`actuation_failure_is_diagnostic`, `procedure_length`, `schedule_slack`.

Does **not** vary and is not authored: any preset, any grammar, any hint.

---

## 7. The post-round trace

**Inputs:** the instance, the ping log, the preset log, the actuation log,
position samples at `trace_position_sample_seconds`, the outcome.

Re-aimed 2026-09-30. The second pass's trace taught *selection* (the fact nobody
sent, wasted tokens, convention mismatches). This one teaches *choreography*. It
is still a pure function of logs.

The trace is the **first time the order is public**. During the round the
progress bar (§3.2) showed only a count. The trace shows each step with its
track, machine and position, which is exactly what the bar withheld. Nothing is
lost by showing it now: the round is over, so there is nothing left to plan.

1. **The headline.** One sentence, readable by a child: the longest wait in the
   round and what it waited for. For example: "Step 3 waited 40 seconds for its
   helper."
2. **Par against actual.** The group's finishing time (or where it got to: the
   progress bar's final count, the same number every player saw during the round)
   against par (§6.3). Beating par is the visible skill ceiling.
3. **The timeline.** Per step: went live, first helper ping, turned. Each gap is
   labelled *waiting for helper* or *waiting for turner*, which follows directly
   from the logs.
4. **Guesses.** Turns made with no helper ping on that machine, and whether they
   were right. That shows whether a group's guessing was bold or reckless.

**Definitions the four items need (G12).** All are functions of the logs.

- A **read helper ping** on step s: a ping of a *setting* on s's machine, by the
  player holding the lens for its class at that moment, made while s's room was
  lit. A ping made in a dark room is logged as **unread** (§4.1) and is not one.
- A turn is **informed** if, before it, there was a read helper ping on that
  machine (at any earlier time in the round, so an early ping counts), or the
  turner holds the lens for the class themselves (after a disconnect transfer).
  Otherwise it is a **guess** (item 4).
- **Gap attribution (item 3).** For each step, from went-live to committed, each
  position sample is labelled: *waiting for helper* while there is no read
  helper ping on it yet; otherwise *waiting for turner* while the turner is
  not within `turn_range_studs` of the machine; otherwise *turning*. For a finale
  step, a sample where both of those are satisfied but the other finale step's
  are not is *waiting for the other pair*.
- **The headline (item 1)** is the longest contiguous run of one *waiting*
  label on one step, reported as that step, that label and that duration. Ties go
  to the earlier run.
- **The headline's words (Q-G6, 2026-09-30; shape from `design/voice.md` §3).**
  One of:

      Step {n} waited {s} seconds for its helper.
      Step {n} waited {s} seconds for its turner.
      Step {n} waited {s} seconds for the other pair.     -- finale only
      Nobody waited long.

  `{s}` is the run's length rounded down to whole seconds. The fallback is used
  when no run reaches `trace_headline_min_wait_seconds`. At most 60 characters,
  which every form meets with room to spare (the longest possible is 45). A
  no-contest round has no headline. **Step numbers** are the canonical order par
  uses (§6.3): T1[1] = 1, T2[1] = 2, T1[2] = 3, … and the finale's two steps are
  7 (track 1) and 8 (track 2). The timeline uses the same numbers, so "Step 3" in
  the headline is row 3 below it. Derived: a number that depended on how the round
  went would name different steps in two rounds of the same seed.

**Rules:** shown for `post_round_seconds`, to everybody, win or lose. **Whether it
names players was T14; the operator answered (a) on 2026-09-30.** It names steps and machines,
not players.

> **Superseded 2026-09-30 by brief §0d #19:** "the fact nobody sent" (the fact is
> now visible to its helper, and was either delivered or not, which is the
> *waiting for helper* gap), "wasted tokens" (no tokens), "the convention
> mismatch" (no conventions), and "transfer count against M" (replaced by par).

**Edge case:** a win under par with no guesses shows the margin. That is the only
leaderboard this design needs (amendment 9).

---

## 8. Edge cases across mechanics

| Case | Rule |
|---|---|
| **Disconnect** | the ring breaks. The leaver's key class transfers to their **supplier**, the helper who could already read it, so that player can now read *and* turn those steps. The leaver's lens is lost: their partner's settings become unreadable and must be guessed. `dial_settings` keeps that survivable rather than fatal. `disconnect_grace_seconds` before reassignment. *(Unchanged in rule, already built: SEAT-003.)* |
| **Below `min_players_to_continue`** | no contest. No loss recorded; season progress unaffected. *(Unchanged; already built.)* |
| **The round becomes unwinnable** | **Revised 2026-09-30 (G6): structural only, and unreachable in M3.** The clock arm (remaining clock < the remaining canonical schedule) is **withdrawn**. The canonical schedule is deliberately naive, and par is what a good group *beats*, so ending a round when the clock falls below it would end rounds a good group could still win, and tell a child they lost when they had not. The only sound clock test would be an optimistic lower bound, and with a 3 s turn that fires seconds before the clock does anyway. The structural arm (a key class with no holder) cannot occur while quorum holds, because SEAT-003 closes the ring and the supplier inherits every class. A class with no *reader* (a lost lens) is not unwinnable: its steps can be guessed. So `unwinnable` has no M3 trigger; the clock ends the round as `lost` / `clock` |
| **Instability and clock hit their limits in the same tick** | instability resolves first; the recorded reason is instability |
| **A correct guess** | commits. Guessing correctly is free; guessing wrongly is what is priced |
| **Two players ping the same target** | both markers show, in both colours. Who pinged is part of what was said |
| **A preset during its sender's cooldown** | rejected by the net wrapper's rate stage, with a visible "wait" state on the wheel; the attempt does not restart the cooldown (already how `RateLimiter` behaves) |
| **Preset filtering fails** | fail closed: not sent, sender told, cooldown not consumed |
| **A ping at a target out of range or out of sight** | rejected. The client's target is a claim. **Not a send (G9):** the cooldown is not consumed; only `channel_attempt_min_interval_seconds` applies |
| **A preset outside its own phase list** | rejected by the handler; not a send, cooldown not consumed (G9) |
| **A turn refused before evaluation** (identity, key class, range, phase, rate, a committed or resetting machine, an armed finale machine) | no instability, no penalty, no tone (§5, G12) |
| **A clock penalty takes the clock to 0 or below** | `lost` / `clock`, unless the same wrong turn reached `instability_max`, which records `instability` (row above) |
| **Rejoin after disconnect** | within the grace window, the seat is restored. After it, spectate until the next round. *(Unchanged; already built.)* |
| **All steps committed with the clock running** | immediate win. The remaining seconds are the margin |
| ~~**Every player mute**~~ | **superseded**: there is no budget to exhaust |
| ~~**Two players send the same token in the same second**~~ | **superseded** by the ping row above |

---

## 9. What a headless test can check

Everything in the left column runs under Lune with no Roblox runtime.

| Mechanic | Headlessly verifiable | Needs a human |
|---|---|---|
| §1 world | machine state machine; commit is terminal; reset timing | whether a dim room is atmospheric or frightening (T15) |
| §2 lens | required settings never in a non-holder's replicated state (B4); range rule | whether reading a glow in the dark is pleasant |
| §3 Procedure | live-step rule per track; finale window; turn cues only in the key-holder's projection; **the progress bar's replicated payload is exactly `{committed, total}`**: an allowlist with no step, track, machine, room, class or player field, and `committed` equals the count of committed steps | whether two tracks are legible to a child, and whether the bar reads as progress or as a plan |
| §4 channel | ping target validation (kind, range, sight as a claim); one active ping; preset table rules C1, C2 (denylist), C6 (punctuation), C8; the 10 s limiter; fail-closed filtering; broadcast-only remote shape | **whether presets are used as intended, or bent into codes** (`playtest.md: P-S`) |
| §5 instability | thresholds, penalties, blackout weighting (a seeded draw over given weights), no penalty on refused turns, finale arm/disarm cases, loss ordering, the outcome vocabulary | whether the dark reads as pressure or punishment |
| §6 generator | **all of §6.2 and §6.3 per seed, including par and `INV_traversal`** | whether instances are interesting |
| §7 trace | headline, gaps, guesses, par. All computable from logs | whether anyone reads it, and whether a child understands the headline |
| §8 edge cases | every row | — |

The balance shifted in this pass. The mechanic with the least headless coverage
used to be the one the game lived or died by (the signal channel). Now the
channel is mostly checkable, and the thing no test can see is whether the
*spatial* decision is interesting, which is `playtest.md: P-D`.
