# Tuning constants

**This file is the specification.** The module that implements these values is
source, written by the Feature Developer in GREEN. If a value in the module and a
value here disagree, that is a defect. Raise it with the Lead PO rather than
editing either one to match.

Every constant carries exactly one label:

| Label | Means |
|---|---|
| **derived** | follows from a constraint or another constant; the derivation is stated |
| **taste** | could legitimately be otherwise; the operator chose it |
| **placeholder** | a guess, present so the thing can be built; names the observation that replaces it |

A fourth appears where a question is open: **taste-pending** means a value
specified provisionally so implementation is not blocked, on a question the
operator has not yet answered (`loop.md` §5a). It is a placeholder whose
replacement is a decision rather than an observation. **The operator answered
T10–T20 on 2026-09-30**, and each affected row reads **taste (operator,
2026-09-30)**. **No live constant is taste-pending.** The label survives only in
§9's record of superseded values.

Names are the names the implementing module should use.

**Revised 2026-09-30 (third pass) for brief §0d #14, #15, #18 and #19.** §3 is
replaced; §2, §4 and §6 are revised; §1 is unchanged in value; §5 changes two
values; §9 is new and records everything superseded, with its old value.

**Revised again 2026-09-30 (M3 gap closure, G1–G12).** The Lead PO's M3
planning found places where no rule or number was given that a test would need.
Each is closed below with its label. New rows are in §2, §3 and §4 only; §1 and
§5 are unchanged. The one new taste-pending item (T21, how the clock is shown)
is not a module constant, and is listed in §8.

### Read this before editing §1, §3 or §5: tests read this file

Test helpers parse this document directly, so a change here can turn the suite
red without any source changing. That is deliberate: they are drift guards.

| Reader | Reads | State on `main` (ROUND-006 DONE, PR #41, 2026-09-30) |
|---|---|---|
| `tests/helpers/TuningSpec.luau` (ROUND-002; re-pointed by ROUND-006) | every backticked-name row in **§1 and §5**, by `## N.` heading number; checks them against `src/ReplicatedStorage/Shared/Tuning.luau` | **green.** `Tuning.luau` carries 420 and 60; ROUND-002's criteria were amended (A-1). Any new row in §1 or §5 turns it red until the module has it |
| `tests/helpers/RateLimitSpec.luau` (NET-003; re-pointed by ROUND-006) | **exactly one** row anywhere whose first cell is `` `preset_rate_limit_seconds` ``, and exactly one for `` `ping_rate_limit_seconds` ``; and **no live row** for `` `signal_rate_limit_seconds` `` (§9's is struck through, so it does not count) | **green.** A second row starting with either live name, anywhere in this file, turns it red |
| `tests/shared/tuning_spec_test.luau` AC-5 anchor | §7's text contains `hidden_faction_ratio`, `vote_`, `score`, `rank`, `MMR`, `ladder` | green; §7 keeps all six |
| TUNE-001 drift guard (planned, M3) | every table row in **§2–§4** whose first cell is a bare backticked name | not yet built. Value cells here are kept to one of: a bare number, `true`/`false`, `` = `other_name` ``, or plain text for a rule that is not a module constant. Invariant rows start with `INV_` |

Rules that follow, for anyone editing later:

- **Do not renumber sections.** The parsers select §1 and §5 by heading number.
- **A new row in §1 or §5 is a code change.** Every row there must exist in
  `Tuning.luau`. New constants go in §2, §3, §4 or §6 unless they really are
  session or round timing.
- **Never add a second row whose first cell is a live rate constant's name.**
  Refer to it in running text or in another row's rationale instead.

---

## 1. Session and lobby

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `players_min` | 4 | **derived** | product-brief §0b amendment 1. Also, re-derived 2026-09-30: the smallest ring in which the finale's two turners are non-adjacent, so it needs four distinct bodies (`loop.md` §2). |
| `players_max` | 6 | **placeholder** | Lead PO ratified 6 (§0c R1). **Its derivation is void as of 2026-09-30**: it was channel contention in a serial token stream, and there is no token stream. The value is kept, not re-chosen. The pressure that now bounds it is idle time: at n = 6 with `procedure_length` 8 each player has about 1.3 steps. Replace via `playtest.md: P-N` (idle time at n = 5 and 6). |
| `min_players_to_continue` | 3 | **derived** | a 3-cycle is still a ring (`roles.md` §6). Below 3 there is no derangement worth the name. |
| `lobby_seconds` | 60 | taste | inherited from A4. UX pacing; the Lead Designer owns it once a screen exists. |
| `post_round_seconds` | 45 | **placeholder** | the trace is re-aimed (`mechanics.md` §7): a one-sentence headline, par, a timeline, and guesses. Probably shorter reading than before, but no observation says so yet, so the value is unchanged. Replace when two consecutive playtests show groups still reading at the cut, or consistently skipping before 20 s. |
| `season_length_days` | 28 | **derived** | A2 #2 measures days 8–28. A season shorter than the retention window it is meant to drive is measuring itself. |

---

## 2. The instance

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `room_count` | 6 | **placeholder** | enough for blackout to bite and for `paired_room_distance_min` to mean something, few enough to cross inside the clock. Replace when playtests show players never leaving one room, or more than about 40% of round time spent walking *without* being on the way to a live step. (Walking is now the game, so a higher share than the second pass's 25% is expected.) |
| `actuator_count` | 16 | **derived** | `procedure_length × actuator_redundancy`. |
| `actuator_redundancy` | 2 | **placeholder** | **re-labelled 2026-09-30; was derived.** Its derivation (view larger than the token budget) is void. Its new job: decoys make a helper's early reading a gamble (they cannot tell which of their partner's machines matter until the partner says `Help` or a lamp lights), and make "turn everything" a losing strategy. Replace if dependents routinely turn decoys by mistake (too many for a child: lower) or if no helper ever reads a decoy (no effect: consider 1). |
| `procedure_length` | 8 | **placeholder** | 2 steps per player at the 4-floor. Unchanged. Replace when playtests finish with more than 90 s left twice running (too short), or reach the clock with 3+ steps uncommitted twice running (too long). Tune together with `round_seconds`. |
| `procedure_tracks` | 2 | **derived** | the minimum at which one player can be the turner of one live step and the helper of another at the same time. With 1 track, `loop.md` §1.2's decision never arises (`mechanics.md` §3.2). |
| `steps_per_track` | 4 | **derived** | `procedure_length / procedure_tracks`. The last step of each track is its half of the finale. |
| `finale_paired_ops` | 1 | **derived** | the finale is one paired operation joining the tracks (`mechanics.md` §3.2). **Replaces `simultaneous_ops_min`**; it is the same guarantee, placed. |
| `key_classes` | = `players_min`..`players_max` | **derived** | one key class per player (`roles.md` §2). |
| `actuators_per_class` | `actuator_redundancy` × that class's step count | **derived** | **Revised 2026-09-30 (G3); was 4, "`actuator_count / key_classes` at n = 4".** That formula does not divide at n = 5 or 6. Every class instead gets exactly one decoy per step, so every helper faces the same gamble whatever n is, and the total is still `actuator_count` (Σ steps × 2 = 16). With `procedure_length` 8: n = 4 → steps 2,2,2,2, machines 4,4,4,4; n = 5 → steps 2,2,2,1,1, machines 4,4,4,2,2; n = 6 → steps 2,2,1,1,1,1, machines 4,4,2,2,2,2. Which classes get the extra steps is drawn from the seed. `INV_class_machines` checks it. |
| `machines_per_class_max` | 4 | **derived** | ⌈`procedure_length` / `players_min`⌉ × `actuator_redundancy` = 2 × 2. The largest class at any generation-time n in 4..6. Sizes the tag alphabet. |
| `procedure_length_depends_on_n` | false | **derived** | **G3.** `procedure_length` stays 8 at n = 5 and 6. At most `procedure_tracks` steps are live at once, so the group's throughput is bounded by tracks, not by bodies: more players do not finish more steps per minute, and a longer Procedure at n = 6 would not fit the clock. What more players do add is idle time, which is `playtest.md: P-N`'s question and `players_max`'s placeholder. |
| `tag_alphabet_size` | = `machines_per_class_max` | **derived** | **G4.** The fewest tag shapes that satisfy `INV_tags_distinct_in_class` at every n. One global alphabet of shapes; each class draws its tags from it **without replacement**, independently of other classes, so two classes may both have a ◆ (the class colour tells them apart). At n = 4 every class uses all four. Fewer shapes is kinder to a child than globally unique tags, which would need 16. The shapes themselves are the Lead Designer's. |
| `dial_settings` | 4 | **placeholder** | positions on each machine's dial. Sized so that **guessing is a real choice, not a dominant or a dead one**: a blind guess costs on average `(dial_settings − 1) / 2` = 1.5 wrong turns, which is 1.5 × `instability_clock_penalty_seconds` = 30 s of clock plus blackout risk, about the same as waiting for a helper two rooms away. At 6 settings guessing would almost never pay; at 2 it would almost always pay. Also the fewest positions a child reads at a glance. Replace via `playtest.md: P-G` (guess rate and guess accuracy). |
| `turn_cue_lookahead` | 1 | **taste (operator, 2026-09-30)** | T10 answered (c) and the rest at default, so 1 stands. How far ahead a turner sees their own steps. 0 would make every step a surprise and remove anticipation, the main ceiling skill; 1 lets a turner walk to their next machine early; more gives a planner too much. Changing it is now an operator decision; `playtest.md: P-Q` and `P-K` inform it. |
| `progress_bar_segments` | = `procedure_length` | **derived** | T10 (c): the public progress bar is one segment per step, filled as steps commit (`mechanics.md` §3.2). Its payload is `{committed, total}` and nothing else. |
| `progress_bar_split_by_track` | false | **derived** | from the operator rejecting T10 (b). Per-track progress would tell a planner which track is behind, which is most of what a public board says. |
| `progress_bar_marks_finale` | true | **derived** | the finale is always the last `procedure_tracks` commits by construction, so marking those segments adds no information. It gives a child "the big one at the end". |
| `lens_read_range_studs` | 12 | **placeholder** | how close a helper must be to read a glow. Short enough that reading means going there (`mechanics.md` §2), long enough that you do not have to touch the machine. Replace when the M3 slice shows helpers reading from doorways across a room (too long) or crowding the turner (too short). |
| `simultaneous_window_seconds` | 5 | **placeholder** | the finale window. With the partner lamp showing both turners in position, 5 s is enough to turn together without a preset. Replace when the finale succeeds first time every time (too long) or when groups need three or more attempts (too short). |
| `paired_room_distance_min` | 2 | **derived** | at distance 1 one player could sprint between the finale machines inside the window, which defeats the finale. |
| `room_traversal_seconds` | 8 | **placeholder** | the generator's walking model: seconds per doorway edge on a shortest path. Used only to compute par (`mechanics.md` §6.3). **Not** meant as 128 studs of straight walking (G2): rooms are `room_pitch_studs` = 64 apart, 4 s centre to centre at `walk_speed_studs_per_second`. The factor of 2 pays for the real path (machine slot → mid-wall doorway → machine slot is 45 to 101 studs, up to about 1.6× the centre distance), for finding things with a torch in the dark, and for a 7-year-old's walking. Replace with the median measured edge time from the M3 slice's position samples. |
| `schedule_slack` | 1.5 | **placeholder** | `INV_traversal` requires `par × schedule_slack ≤ round_seconds`. Worked for a typical instance with the exact algorithm of `mechanics.md` §6.3: 6 ordinary steps plus the finale are 7 sequential units, each about 2 edges of walking (16 s) + `par_ping_seconds` (10) + `par_turn_seconds` (3) = 29 s, so par ≈ 203 s and 203 × 1.5 ≈ 305 ≤ 420. The worst layout (a 6-room chain, 5-edge walks) gives 7 × 53 = 371 and 371 × 1.5 = 556 > 420, so the invariant does reject instances. The slack pays for being wrong, and for children walking slowly. Replace when win rate sits outside `win_rate_target`. |
| `par_ping_seconds` | 10 | **derived** | **G6.** The flat cost the canonical schedule charges once per step (each finale sub-step pays its own, in parallel) for the helper's ping: a full rate-limit interval, as if the helper had just pinged something else. Fixed at the guideline's 10 s, so par never depends on CA-1 being read in our favour (`mechanics.md` §6.3). Equal to the current ping rate by construction, and not a second row for it. |
| `par_turn_seconds` | 3 | **placeholder** | **G6.** Time the canonical schedule charges per step for the turner to step up and set the dial. Was the worked example's unnamed "3 s turn". Replace with the median measured time from "turner within `turn_range_studs` with a read helper ping present" to commit, from the M3 slice. |
| `trace_headline_min_wait_seconds` | = `room_traversal_seconds` | **derived** | **Q-G6.** The trace headline names a wait only if it lasted at least this long; otherwise it says "Nobody waited long." (`mechanics.md` §7). A wait shorter than one room's walk is someone walking over, not someone being waited for, so naming it would teach nothing. **Replaces the Lead Designer's provisional 5 s** (`design/voice.md` §3), which would name a helper who was simply on their way. Moves with the walking model. |
| `generator_attempts_max` | 64 | **placeholder** | **G11.** How many whole-instance samples the generator tries before giving up (`mechanics.md` §6.2). Sized so that if at least a quarter of first samples pass every invariant, exhaustion has probability 0.75^64 ≈ 10⁻⁸. The seed-sweep test measures the real first-attempt acceptance; **if it is below 0.25, that is a design finding for this file** (a layout or slack problem), not a reason to raise this bound. |

### The layout — G1 and G2

The generator's blockout. Studs are Roblox units. Only the walking model, the
ranges and the capacity rules are game design; the look of a room is the Lead
Designer's, and the numbers marked "Lead Designer may change" can move without
this file changing so long as the rules in their rationale still hold.

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `layout_grid_columns` | 3 | **placeholder** | rooms are cells of a square grid, `room_pitch_studs` apart. 3 × 3 is the smallest square grid with more cells than `room_count`, so the set of occupied cells has a shape that varies per seed (a 2 × 3 grid would hold exactly 6, always the same shape). Replace with `room_count`. |
| `layout_grid_rows` | 3 | **placeholder** | as above. |
| `layout_loop_door_chance` | 0.25 | **placeholder** | doorways: a uniformly random spanning tree over grid-adjacent occupied cells, then every other grid-adjacent pair gets a doorway with this chance. So the graph is connected, has degree ≤ 4 (the grid), and usually has a loop or two, which gives route choice. At 0 every layout is a tree and walks are long; at 1 every adjacent pair connects and layout stops mattering. Replace if most instances fail `INV_traversal` (raise) or if routing never matters in play (lower). |
| `spawn_room` | the room of least eccentricity in the doorway graph; ties to the lowest room index | **placeholder** | **G1.** Every player spawns in this one room at round start. A graph centre keeps the opening walk short for everyone and makes par's start position a pure function of the layout. Rooms are indexed by grid cell, row-major from 1. The spawn room is an ordinary room and may hold machines. Replace if the opening (round start to first commit, compared with `traversal_reserve_seconds`) is regularly spent standing together deciding where to go: starting players apart is the alternative. |
| `room_pitch_studs` | 64 | **placeholder** | centre-to-centre distance of grid-adjacent rooms. Big enough that a machine cannot be read or pinged from a doorway (every quadrant slot is at least 22 studs from every doorway, and `lens_read_range_studs` is 12), small enough that one edge is about 4 s of straight walking. Replace together with `room_traversal_seconds` once edge times are measured. |
| `room_footprint_studs` | = `room_pitch_studs` | **derived** | rooms abut and share walls, with doorways in the shared wall. No corridors: a corridor is walking that `room_traversal_seconds` would have to model separately. |
| `room_ceiling_studs` | 16 | **placeholder** | Lead Designer may change. No rule reads it except line of sight. |
| `doorway_width_studs` | 8 | **placeholder** | Lead Designer may change. Two R15 avatars pass without blocking each other, so a doorway is never a chokepoint a player can hold. Centred in the shared wall. |
| `doorway_height_studs` | 10 | **placeholder** | Lead Designer may change. Clears an R15 avatar at default scale with margin. |
| `machine_slots_per_room` | 4 | **placeholder** | machines stand at the four quadrant centres of a room (±`room_pitch_studs`/4 on each axis from its centre), so slots are 32 studs apart and at least 22 studs from any doorway. Lead Designer may move slots if `machine_spacing_min_studs` still holds. Capacity 6 × 4 = 24 ≥ `actuator_count`. |
| `machines_per_room_min` | 1 | **placeholder** | every room is somewhere to go; an empty room is a corridor under another name. Replace if blackouts regularly land on rooms that matter too much (a lone step in a room is exposed). |
| `machines_per_room_max` | = `machine_slots_per_room` | **derived** | one machine per slot. |
| `machine_spacing_min_studs` | 20 | **derived** | 2 × `turn_range_studs`: no position is within turning reach of two machines, so "the machine I am at" is never ambiguous to a player (the server still checks the named machine). |
| `walk_speed_studs_per_second` | 16 | **derived** | the platform's default R15 `WalkSpeed`. The game does not change it (A2 #3: no custom movement). Stated so that `room_pitch_studs` and `room_traversal_seconds` can be checked against each other. |
| `turn_range_studs` | 10 | **placeholder** | **G5.** Server proximity check for a turn: the turner's character root must be within this distance of the machine's position, in the server's view. Shorter than `lens_read_range_studs` so a helper reading from 12 studs does not crowd the turner. The client's own prompt should appear at a shorter distance (the Lead Designer's number, which must be ≤ this) so that latency rarely makes the server refuse a turn the client offered. Replace if refusals for range show up in telemetry from honest clients, or if players turn from visibly across the room. |
| `partner_lamp_range_studs` | = `turn_range_studs` | **derived** | **G5.** "Within reach" means "could turn it now". A finale machine's partner lamp is lit while the finale is live and the *other* finale machine's key holder is within this distance of *that other* machine (`mechanics.md` §3.2). |
| `trace_position_sample_seconds` | 1 | **placeholder** | how often positions are logged for the trace's waiting-for attribution. Replace if telemetry cost says otherwise; the trace only needs to tell "arrived" from "not arrived". |

### Generator invariants — not constants, but specified here so they are checkable

| Invariant | Statement |
|---|---|
| `INV_tags_distinct_in_class` | tags are distinct within a key class, so "my ◆ machine" names one machine. Tags are drawn from one global alphabet of `tag_alphabet_size` shapes (G4). |
| `INV_layout` | **new (G1).** `room_count` distinct cells of the `layout_grid_columns` × `layout_grid_rows` grid; doorways only between grid-adjacent occupied cells; the doorway graph is connected. Consequences a test may also check: every room has degree ≤ 4, and some pair of rooms is at least 2 edges apart (any 6 connected cells of a 3 × 3 grid include two at grid distance ≥ 2), so `INV_finale` is always satisfiable. |
| `INV_room_capacity` | **new (G2).** every room holds between `machines_per_room_min` and `machines_per_room_max` machines, one per slot. |
| `INV_class_machines` | **new (G3).** each key class has exactly `actuator_redundancy` × (its step count) machines, and the class sizes sum to `actuator_count`. |
| `INV_settings_uniform` | **new (G12).** every machine, decoys included, has a required setting drawn uniformly from 1..`dial_settings`, independently. Decoys must have one, or a helper could tell a decoy by its missing glow. |
| `INV_cyclic_sigma` | σ is a single n-cycle (`roles.md` §2). Already enforced by construction in `Ring.luau`. |
| `INV_every_class_has_a_step` | every key class has at least one step. With the ring, this is all k-essentiality needs (`mechanics.md` §6.3 I1). |
| `INV_balanced_steps` | step counts per class differ by at most 1. |
| `INV_track_alternates` | consecutive steps within a track have different key classes. |
| `INV_finale` | the finale's machines are in different rooms at least `paired_room_distance_min` apart, of non-adjacent key classes when n ≥ 4. |
| `INV_k_essential` | re-derived: follows from `INV_cyclic_sigma` + `INV_every_class_has_a_step` + `dial_settings` ≥ 2. Still worth a direct test per seed. |
| `INV_traversal` | `par × schedule_slack ≤ round_seconds`, with par computed by the exact algorithm in `mechanics.md` §6.3, from `spawn_room`, with `par_ping_seconds` and `par_turn_seconds`. **Replaces `INV_rate`.** |
| `INV_ping_dominates` | every fact that must transfer is a required setting and has a one-ping form (`mechanics.md` §4.3 C3). Structural; stated so a later change that adds a non-pointable fact is caught at review. |

Superseded invariants (`INV_no_self_value`, `INV_values_distinct`,
`INV_centralisation`, `INV_rate`) are listed in §9.

---

## 3. The channel — pings and presets

**Replaced 2026-09-30.** Read `mechanics.md` §4 first, and §4.3 before changing
any number marked *derived from the guideline*. Those are compliance
requirements (brief §0d #19), not tuning.

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `presets_plus_pings_max` | 12 | **derived** | the guideline: "Limit the number of presets displayed to 12 or less for your Universe". Counted with the ping included, so the design survives CA-1 being read against it. Universe-wide, so every future mode shares it. |
| `preset_count` | 10 | **taste (operator, 2026-09-30)** | the operator chose the provisional list in `mechanics.md` §4.2 (T12, ryanczhang7, 2026-09-30). Must satisfy `preset_count + ping_kinds ≤ presets_plus_pings_max`; at 10 it leaves one spare slot. |
| `ping_kinds` | 1 | **derived** | one text-free marker. Target types (setting, machine, doorway) are not kinds, because they carry no label. Kinds with labels would be predefined text, and would count as presets. |
| `preset_rate_limit_seconds` | 10 | **derived** | the guideline: "Add a rate-limit (10 seconds per send)". One limiter per player across the whole wheel. Also satisfies B4's requirement that every remote be rate-limited. |
| `preset_display_seconds` | 5 | **placeholder** | presets should "ideally expire quickly". Long enough to see who sent it and where; short enough that the screen does not fill. Replace if players miss presets they needed (a `Help` nobody answered for lack of seeing it) or if the HUD strip is cluttered at n = 6. |
| `preset_reveals_sender` | true | **derived** | attribution is what lets a player know that a `Help` is from *their* partner. |
| `preset_reveals_sender_position` | true | **derived** | "Each preset must stand alone and be complete": `Help` without a place needs a follow-up the channel cannot carry. **Supersedes §0d #16's `signal_reveals_sender_room` = false** (`loop.md` §5). Contingent on CA-3. |
| `ping_rate_limit_seconds` | 10 | **derived** | **Lead PO decision on CA-1, 2026-09-30** (product-brief §0d): whether a ping is a preset cannot be confirmed from published Roblox documentation (there is no official page on pings and no staff answer), so the design takes the stricter reading on rate and applies the guideline's "Add a rate-limit (10 seconds per send)" to pings too. **Was 3, a placeholder.** Costs: a mis-ping takes 10 s to correct, and doorway pings ("this way") are sluggish. Nothing becomes unwinnable, because `INV_traversal` was already computed at 10. Also satisfies B4. |
| `ping_display_seconds` | 15 | **placeholder** | long enough for a partner two rooms away to arrive and still see the ping, so nothing has to be remembered (`loop.md` §1a). Replace if turners arrive to find pings gone (too short) or if stale pings mislead (too long). |
| `active_pings_per_player` | 1 | **derived** | a new ping replaces the old one, so no player can lay out a pattern of markers. Removes the drawing surface a sequence-cipher would need (`mechanics.md` §4.1). |
| `ping_range_studs` | = `lens_read_range_studs` | **derived** | you can point at exactly what you could read, and no further. |
| `ping_reveals_sender` | true | **derived** | a ping's meaning comes from who made it, via the ring. An anonymous ping carries no knowledge. |
| `ping_settings_live_only` | false | **taste (operator, 2026-09-30)** | **T20 answered (a)**: pings may target any setting in range. Raised the same day by the Lead PO's CA-1 decision. CA-1 is unconfirmed, so the cipher risk (a sequence of setting-pings used as a slow code) is accepted rather than ruled out, in exchange for keeping early pinging, the anticipation skill at the ceiling (`loop.md` §1a). The rate is 10 s either way. `playtest.md: P-S` is the protocol that would reopen it: a confirmed "not working" there goes back to the operator. |
| `channel_limiter_consumed_by` | a send that is broadcast | **derived** | **G9.** The 10 s preset limiter and the 10 s ping limiter are consumed only when the preset or ping is actually broadcast. A ping refused for its target (missing, out of `ping_range_studs`, out of sight, or a committed machine) and a preset refused because its own phase list excludes the current phase are **not sends**, so they do not start the cooldown, exactly as a failed filter already does not (`mechanics.md` §4.2). Derived from the guideline's own unit, "10 seconds **per send**", and from the precedent. For the floor: a child whose ping the server silently disagreed with (latency, a raycast the client saw differently) must not also be locked out for 10 s. **Consequence for the architecture, the Lead PO's:** the net wrapper's rate stage runs before the handler validates the target, so as built it consumes the limiter on these refusals. Either the send limiter moves to the point of broadcast, or the rate stage gains a refund, and `channel_attempt_min_interval_seconds` covers B4's anti-spam requirement in the meantime. |
| `channel_attempt_min_interval_seconds` | 1 | **placeholder** | **G9.** A per-player floor on *attempts* at the ping and preset remotes, consumed by every call that reaches the rate stage whether or not it is later broadcast. It exists only so that refunds cannot be abused to make the server validate targets at frame rate (B4). One second is slower than any exploit needs and faster than any honest retry. Replace if telemetry shows honest clients hitting it. |
| `ping_budget_per_player` | none | **taste (operator, 2026-09-30)** | T11 answered (a): unlimited, rate-limited only, which is kindest to children. A budget would have brought back legible scarcity and the "is it worth it" moment, at the cost of a second resource to manage. |

Every constant of the second pass's signal channel is listed, with its old value
and disposition, in §9.

---

## 4. Actuation and instability

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `actuation_reset_seconds` | 3 | **placeholder** | a rejected dial returns to unset. Long enough to see it failed, short enough not to punish twice. Replace if players queue waiting for resets. |
| `actuation_failure_is_diagnostic` | true | **taste (operator, 2026-09-30)** | T13 answered (a). **Flipped from the second pass's false**, for §0d #14: "wrong setting" and "not live yet" look different, which is the most learnable response for a child. The cheapest difficulty lever, and the first candidate for any later harder band. |
| `instability_max` | 5 | **placeholder** | the round is lost at 5 wrong turns. With `dial_settings` 4 a group can blind-guess about three steps (1.5 expected errors each) and survive, which is what keeps guessing a live option. Replace when losses by instability and by clock are not within roughly 2:1 of each other. |
| `instability_per_wrong_value` | 1 | **derived** | wrong setting and not-live must cost the same, or the scoreboard is diagnostic when `actuation_failure_is_diagnostic` is false. |
| `instability_per_out_of_order` | 1 | **derived** | as above. |
| `instability_per_failed_pair` | 1 | **derived** | one operation, one penalty (`mechanics.md` §5). |
| `instability_clock_penalty_seconds` | 20 | **placeholder** | 5 errors remove 100 s of 420, about 24%. Also half of `dial_settings`' guess arithmetic. Replace if groups reach `instability_max` before the clock matters. |
| `instability_blackout_threshold` | 2 | **placeholder** | blackouts at instability 2 and 4, so a group feels the mechanism twice before losing to it. Replace if the first blackout regularly ends the round in practice. |
| `blackout_rooms_per_threshold` | 1 | **placeholder** | of `room_count` 6. Replace alongside the threshold. |
| `blackout_permanent` | true | **taste (operator, 2026-09-30)** | T15 answered: permanent, the second pass's choice and the sharpest consequence in the design. **The tone of the dark (spooky or calm) is still open**, shared with the Lead Designer for M4; it is not a constant. |
| `blackout_selection` | weight of a lit room = Σ over its uncommitted steps of the step weights below; uniform over lit rooms if every weight is 0 | **derived** | **Specified 2026-09-30 (G7).** At each threshold crossing the server draws `blackout_rooms_per_threshold` rooms, without replacement, from the rooms not already dark, with probability proportional to the weight. Decoys and committed steps weigh nothing. Derived: random selection would often darken a finished room and do nothing. The draw uses the round seed's `rng:derive("blackout")` sub-stream, so it is reproducible in a test and in the trace. |
| `blackout_weight_live_step` | 1 | **placeholder** | **G7.** Weight of a live or armed step. Replace via `playtest.md: P-I`: if blackouts always wreck the step in hand, lower it; if they rarely touch it, raise it. |
| `blackout_weight_waiting_step` | 1 | **placeholder** | **G7.** Weight of a waiting step. Equal to the live weight until a playtest says otherwise. |
| `blackout_repeat_allowed` | false | **derived** | **G7.** An already-dark room is never picked again: darkening a dark room does nothing, which is the failure the weighting exists to prevent. If every room is already dark, a threshold does nothing more. |
| `turn_rate_limit_seconds` | 1 | **placeholder** | the turn remote's per-player rate (B4 requires one on every remote). Well below any honest re-attempt, which `actuation_reset_seconds` already paces per machine. A turn refused for rate is not evaluated and costs nothing (`mechanics.md` §5). Replace if telemetry shows honest clients hitting it. |
| `finale_live_together` | true | **derived** | **G12, a rule change.** The two finale steps go live **at the same moment**, when both tracks have committed everything before them; until then an early track's finale machine is waiting, not live. Derived from what the live lamp means, "may be turned now" (`mechanics.md` §1): a lone finale turn cannot succeed however well it is played, so lighting it as live would invite a guaranteed instability point, which is a trap and not a decision. Replaces the second-pass wording "its finale machine goes live and waits". |

### What the HUD shows of the round — G8

Round-public state, the same for every player, beside the progress bar. None of
these is in the per-player projection.

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `hud_shows_round_clock` | true | **derived** | pressure a player cannot perceive is not pressure (`loop.md` §3): the clock must be perceivable. **How** it is shown is T21 below, and is not derived. |
| `hud_round_clock_form` | a numeric mm:ss countdown, always visible; each penalty shows as a brief −20 beside it | **taste-pending** | **T21 (§8).** Provisional default. The alternatives are a clock shown only in the final 60 s, or an ambient clock with no number (the facility's hum and lights changing). A number is the most legible and the most learnable; it is also the likeliest to make a 7-year-old panic (`playtest.md: P-K`, P-H). |
| `hud_clock_separate_from_progress` | true | **derived** | the clock and the progress bar are two elements and nothing combines them: no pace line, no "on track / behind", no forecast. `mechanics.md` §3.2 forbids time on the bar because a count plus a clock is a forecast, and par belongs to the trace. |
| `hud_shows_instability` | true | **derived** | instability ends the round at `instability_max`; a loss by a meter you could not see teaches nothing, and T13 already chose the learnable side for failures. Shown as `instability_max` pips, filled as instability rises. |
| `hud_marks_blackout_thresholds` | true | **derived** | the pips at each multiple of `instability_blackout_threshold` are marked, so "one more wrong turn and a light goes out" is readable before it happens. That is the cost of failure stated in advance (`loop.md` §5). It does not say **which** room: the draw happens at the crossing. |

---

## 5. Round timing

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `round_seconds` | 420 | taste | **decided by the operator, brief §0d #18 (2026-09-30)**; was 480, a placeholder. 60 + 420 = 480 meets A5's day-1 promise. Inside A3 pillar 5's band. Tune with `procedure_length` as a pair; any change is now an operator decision, not a playtest one. |
| `round_seconds_min` / `_max` | 360 / 600 | **derived** | A3 pillar 5. A round outside this band is a different product decision, not a tuning change. |
| `per_operation_seconds` | 45 | **derived** | `(round_seconds − traversal_reserve_seconds) / procedure_length` = (420 − 60) / 8. It is the **group's average cadence**: one step committed every 45 s across both tracks. Per track, a step has about twice that. Unchanged in value. |
| `traversal_reserve_seconds` | 60 | **placeholder** | **re-derived 2026-09-30; was 120.** Its meaning changed with the design. In the second pass, deciding (per operation) and walking (the reserve) were separate. Now every step *is* a walk, because reading requires being there, so walking lives inside `per_operation_seconds`, and the reserve is only the opening: reading your first turn cue and making your first walk. Replace with the measured time from round start to first commit in the M3 slice. |
| `first_round_within_seconds` | 480 | **derived** | A5's day-1 requirement. With `lobby_seconds` 60 and `round_seconds` 420 it is **now met exactly** (§0d #18 closed amendment 12). |
| `disconnect_grace_seconds` | 30 | **placeholder** | long enough for a reconnect, short enough that the ring is not broken for a large part of the round. Replace with observed reconnect times once telemetry exists (B6). |

---

## 6. Difficulty bands

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `difficulty_band` | `{ standard }` | taste | **decided by the operator, §0d #15**: design for the voiceless floor. The second pass's provisional `{ standard, hard }` (T5 option (c)) is withdrawn. **T17 answered by the operator, 2026-09-30: no harder band in v1.** |
| band-varied constants | `dial_settings`, `turn_cue_lookahead`, `actuation_failure_is_diagnostic`, `procedure_length`, `schedule_slack` | **derived** | the levers a harder band would move, if a later version adds one (T17 said not in v1). All are generator parameters or rules; none is content (A2 #4). |
| `win_rate_target` | 0.45 | **taste (operator, 2026-09-30)** | T18. For the standard band, for a group that has played together several times. Below half, so that a win is an achievement. Revisit (an operator decision) when observed win rate is stable across 20+ sessions and the qualitative reading disagrees with the number. |
| `first_session_win_rate_target` | 0.6 | **taste (operator, 2026-09-30)** | T18. A group's first session, including a child, is a different population from a regular group. Set so that a first round usually ends in a win and A5's day-1 bounce signal is not spent on a loss. |

---

## 7. Constants this design deliberately does not have

Recorded so their absence is a decision rather than an omission.

| Absent | Why |
|---|---|
| `hidden_faction_ratio` | amendment 8. There is no hidden faction. |
| `vote_*` anything | there is no vote. Resolution is the Procedure completing or not. |
| any per-player score, rank, MMR or ladder constant | amendment 9: players win or lose together and progression is shared. |
| role unlock cadence | `roles.md` §5: there are no roles to unlock. A5 days 2–7 needs re-deriving against a co-op shape. |
| any constant affecting round outcome that a purchase could change | A6: all SKUs cosmetic, convenience or social. |
| any vocabulary, token or signal budget constant | **new, 2026-09-30.** §0d #19: there is no vocabulary for a group to build on. Pings have no budget either (T11, operator, 2026-09-30). |
| any preset that names a setting, colour, shape, tag, room, number or ordinal | **new.** `mechanics.md` §4.3 C2. A preset like that would make the wheel fact-bearing and bring back the sequence problem. |
| any age or chat-eligibility gate on the channel | **new.** §0d #19 chose (a), compliance for all ages, over (b), gating behind `TextChatService:CanUsersChatAsync`. The channel must work for an unverified player and an under-9. |

---

## 8. Open, and what closes each

| # | Question | Constants waiting on it | Closed by |
|---|---|---|---|
| T15 (tone) | is the dark spooky or calm, for all ages? | none; blackout permanence is decided | operator with the Lead Designer, M4 |
| CA-1 | is a ping a preset | **rate decided**: `ping_rate_limit_seconds` = 10 (Lead PO, 2026-09-30, stricter reading). The question itself stays unconfirmed | Roblox, if ever documented. Until then the design assumes the stricter reading on rate and count |
| CA-3 | does a positioned preset stay "standalone" | `preset_reveals_sender_position` | Lead PO. **Supported** by the guideline's own allowed examples, "Defending this area" and "Enemy nearby", which are standalone presets whose meaning includes the sender's location (`mechanics.md` §4.6) |
| CA-4 | are lamps and the progress bar game state | `progress_bar_*` (removed rather than counted if not) | Lead PO |
| — | guess economics | `dial_settings`, `instability_max`, `instability_clock_penalty_seconds` | `playtest.md: P-G` |
| T21 | how is the round clock shown? | `hud_round_clock_form` (taste-pending; default: numeric countdown, always visible) | operator, with the Lead Designer; `playtest.md: P-H` informs it |
| — | walking model | `room_traversal_seconds`, `traversal_reserve_seconds`, `room_count`, `room_pitch_studs`, `par_turn_seconds`, `turn_range_studs` | the first timed M3 playtest |
| — | where the send limiter is consumed | `channel_limiter_consumed_by`, `channel_attempt_min_interval_seconds` | Lead PO: the design rule is settled; where the wrapper enforces it is architecture |
| ~~—~~ | ~~two red tests on landing~~ | **closed** by ROUND-006 (DONE 2026-09-30, PR #41): `Tuning.luau` at 420 / 60, ROUND-002 amendment A-1, `RateLimitSpec` re-pointed at the preset and ping rows | — |

**Closed 2026-09-30 by the operator (ryanczhang7): "T16 a, T10 c, rest
default".** Recorded in full in `loop.md` §5 and §5a.

| # | Answer | Constants it fixed |
|---|---|---|
| T10 | (c) private turn cues plus a public progress bar | `turn_cue_lookahead` 1; new `progress_bar_segments`, `progress_bar_split_by_track`, `progress_bar_marks_finale` |
| T11 | (a) no ping budget | `ping_budget_per_player` none |
| T12 | the provisional 10 words | `preset_count` 10 |
| T13 | (a) a failed turn says why | `actuation_failure_is_diagnostic` true |
| T14 | (a) the trace names steps only | a rule in `mechanics.md` §7 |
| T15 | blackout permanent; tone still open (above) | `blackout_permanent` true |
| T16 | (a) choreography plus generated variety | none |
| T17 | no harder band in v1 | `difficulty_band` `{ standard }` |
| T18 | 0.45 regular, 0.6 first session | `win_rate_target`, `first_session_win_rate_target` |
| T19 | youngest floor player is 7 | none directly; `playtest.md: P-K` recruitment |
| T20 | (a), a separate answer the same day: setting-pings may target any setting in range; the cipher mitigation is declined (P-S would reopen it) | `ping_settings_live_only` false |

Closed earlier: T5 (§0d #15), T6 and T7 (superseded, `loop.md` §5), T8 (§0d
#19), T9 (superseded), and the A5 day-1 conflict (§0d #18).

---

## 9. Superseded 2026-09-30 by brief §0d #19

Every constant of the second pass that this revision removes, with the value it
had, so that nothing vanished. Names are struck through so that no parser or
implementer mistakes a row here for a live specification.

| Constant (superseded) | Old value | Old label | Why superseded | Replaced by |
|---|---|---|---|---|
| ~~`vocabulary_size`~~ | 16 | derived | > 12, the guideline's ceiling; and the vocabulary was the language | `preset_count` + `ping_kinds` ≤ 12 |
| ~~`mark_alphabet_size`~~ | 8 | derived | existed so that "a value-mark uniquely names an operation": a discoverable, evolving meaning | `dial_settings` (no bijection) |
| ~~`ordinal_tokens`~~ | `FIRST`, `BEFORE`, `AFTER` | derived | fact-bearing (order) and meaningless without sequence | order is never relayed (`mechanics.md` §3.2) |
| ~~`polarity_tokens`~~ | `YES`, `NO` | taste | a question/answer structure, and a two-symbol code | `Got it` (acknowledgement only) |
| ~~`meta_tokens`~~ | `AGAIN`, `WAIT`, `GO` | derived | their job was gating order information cheaply | `Wait`, `Go` survive as presets with no information role; `AGAIN` retired |
| ~~`wheel_rows × wheel_columns`~~ | 4 × 4 | derived | sized for 16 | the Lead Designer, for ≤ 11 entries |
| ~~`signal_cost`~~ | 1, uniform | taste | no tokens | — |
| ~~`signal_budget_per_player`~~ | 12 | placeholder | no tokens | T11 (pings) |
| ~~`view_enumeration_tokens`~~ | ≈ 17 | derived | the centralisation bound's right-hand side; void | structural: no channel carries a setting from a distance |
| ~~`cooperative_minimum_tokens`~~ | ≈ 6 | derived | no tokens | par (`mechanics.md` §6.3) |
| ~~`protocol_slack`~~ | 2.0 | placeholder | no tokens | `schedule_slack` |
| ~~`signal_reserve`~~ | 2 | placeholder | no budget | — |
| ~~`reserve_unlock_seconds_remaining`~~ | 90 | placeholder | no budget | — |
| ~~`signal_rate_limit_seconds`~~ | 1.5 | derived | 1.5 < the guideline's 10 s. **NET-003's provenance test reads this row**; see the header | `preset_rate_limit_seconds` (10), `ping_rate_limit_seconds` |
| ~~`signal_display_seconds`~~ | 6 | placeholder | ephemerality of facts is retired (`loop.md` §5, T7) | `ping_display_seconds`, `preset_display_seconds` |
| ~~`signal_log_depth`~~ | 0 | taste | as above; §0d #17 kept it at 0 contingent on #19 | — |
| ~~`signal_reveals_sender`~~ | true | taste | no signals | `ping_reveals_sender`, `preset_reveals_sender` (both derived now) |
| ~~`signal_reveals_sender_room`~~ | false | taste (§0d #16) | contingent on #19; superseded and transformed (`loop.md` §5) | `preset_reveals_sender_position` = true |
| ~~recall~~ (never tabled) | one token re-shows the last three signals | taste (§0d #17) | contingent on #19; superseded (`loop.md` §5) | persistent pings |
| ~~`order_fragments_per_player`~~ | 3 | placeholder | order fragments cannot be relayed compliantly (`mechanics.md` §3.2) | private turn cues, `turn_cue_lookahead` |
| ~~`pairs_per_lens`~~ | 4 | derived | a "pairing" was the unit a token transferred | `actuators_per_class` (a lens covers them) |
| ~~`simultaneous_ops_min`~~ | 1 | derived | same guarantee, now placed at the end | `finale_paired_ops` |
| ~~`difficulty_band`~~ `{ standard, hard }` | two bands | taste-pending | §0d #15 | `{ standard }`, T17 |
| ~~`INV_no_self_value`~~ | required value ≠ tag | invariant | tags and settings are now disjoint alphabets | — |
| ~~`INV_values_distinct`~~ | in-Procedure values exhaust the alphabet | invariant | the bijection is gone | — |
| ~~`INV_centralisation`~~ | budget < view enumeration | invariant | structural now | — |
| ~~`INV_rate`~~ | transfers fit the rate limit with headroom | invariant | the binding resource is walking, not sending | `INV_traversal` |

Values that changed but whose constants survive: `round_seconds` 480 → 420
(§0d #18); `traversal_reserve_seconds` 120 → 60 (re-derived); `players_max` and
`actuator_redundancy` re-labelled derived → placeholder with values unchanged;
`actuation_failure_is_diagnostic` false → true (taste, operator, T13);
`first_round_within_seconds` unchanged, now satisfied.
