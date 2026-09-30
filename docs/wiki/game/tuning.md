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

### Read this before editing §1, §3 or §5: tests read this file

Three test helpers parse this document directly, so a change here can turn the
suite red without any source changing. That is deliberate: they are drift
guards.

| Reader | Reads | What this revision does to it |
|---|---|---|
| `tests/helpers/TuningSpec.luau` (ROUND-002, frozen) | every backticked-name row in **§1 and §5**, by `## N.` heading number; checks them against `src/shared/Tuning.luau` and against ROUND-002's frozen AC values | **goes red.** `round_seconds` 480 → **420** (§0d #18) and `traversal_reserve_seconds` 120 → **60** (re-derived, §5). The module and ROUND-002's frozen criteria both still say 480 and 120. **Needs a story, with an `## Amendments` entry on ROUND-002**, as §0d already anticipated |
| `tests/helpers/RateLimitSpec.luau` (NET-003) | the single row anywhere whose first cell is exactly `` `signal_rate_limit_seconds` `` | **goes red: no such row.** The constant is superseded (§9). The wrapper test's 1.5 s remote needs its provenance re-pointed to `preset_rate_limit_seconds` (10) or `ping_rate_limit_seconds` (also 10, since the Lead PO's CA-1 decision). **Needs a story** |
| `tests/shared/tuning_spec_test.luau` AC-5 anchor | §7's text contains `hidden_faction_ratio`, `vote_`, `score`, `rank`, `MMR`, `ladder` | unaffected; §7 keeps all six |

Two rules that follow, for anyone editing later:

- **Do not renumber sections.** The parsers select §1 and §5 by heading number.
- **A new row in §1 or §5 is a code change.** Every row there must exist in
  `Tuning.luau`. New constants go in §2, §3, §4 or §6 unless they really are
  session or round timing.

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
| `actuators_per_class` | 4 | **derived** | `actuator_count / key_classes` at n = 4. A helper's lens covers these 4, of which 2 are steps. |
| `dial_settings` | 4 | **placeholder** | positions on each machine's dial. Sized so that **guessing is a real choice, not a dominant or a dead one**: a blind guess costs on average `(dial_settings − 1) / 2` = 1.5 wrong turns, which is 1.5 × `instability_clock_penalty_seconds` = 30 s of clock plus blackout risk, about the same as waiting for a helper two rooms away. At 6 settings guessing would almost never pay; at 2 it would almost always pay. Also the fewest positions a child reads at a glance. Replace via `playtest.md: P-G` (guess rate and guess accuracy). |
| `turn_cue_lookahead` | 1 | **taste (operator, 2026-09-30)** | T10 answered (c) and the rest at default, so 1 stands. How far ahead a turner sees their own steps. 0 would make every step a surprise and remove anticipation, the main ceiling skill; 1 lets a turner walk to their next machine early; more gives a planner too much. Changing it is now an operator decision; `playtest.md: P-Q` and `P-K` inform it. |
| `progress_bar_segments` | = `procedure_length` | **derived** | T10 (c): the public progress bar is one segment per step, filled as steps commit (`mechanics.md` §3.2). Its payload is `{committed, total}` and nothing else. |
| `progress_bar_split_by_track` | false | **derived** | from the operator rejecting T10 (b). Per-track progress would tell a planner which track is behind, which is most of what a public board says. |
| `progress_bar_marks_finale` | true | **derived** | the finale is always the last `procedure_tracks` commits by construction, so marking those segments adds no information. It gives a child "the big one at the end". |
| `lens_read_range_studs` | 12 | **placeholder** | how close a helper must be to read a glow. Short enough that reading means going there (`mechanics.md` §2), long enough that you do not have to touch the machine. Replace when the M3 slice shows helpers reading from doorways across a room (too long) or crowding the turner (too short). |
| `simultaneous_window_seconds` | 5 | **placeholder** | the finale window. With the partner lamp showing both turners in position, 5 s is enough to turn together without a preset. Replace when the finale succeeds first time every time (too long) or when groups need three or more attempts (too short). |
| `paired_room_distance_min` | 2 | **derived** | at distance 1 one player could sprint between the finale machines inside the window, which defeats the finale. |
| `room_traversal_seconds` | 8 | **placeholder** | the generator's walking model: seconds per doorway edge on a shortest path. Used only to compute par (`mechanics.md` §6.3). Replace with the median measured edge time from the M3 slice's position samples. |
| `schedule_slack` | 1.5 | **placeholder** | `INV_traversal` requires `par × schedule_slack ≤ round_seconds`. Worked for the default instance: a naive schedule is about 8 steps × (16 s walking + 10 s ping at `ping_rate_limit_seconds` + 3 s turn) ≈ 240 s, and 240 × 1.5 = 360 ≤ 420. The slack pays for being wrong, and for children walking slowly. Replace when win rate sits outside `win_rate_target`. |
| `trace_position_sample_seconds` | 1 | **placeholder** | how often positions are logged for the trace's waiting-for attribution. Replace if telemetry cost says otherwise; the trace only needs to tell "arrived" from "not arrived". |

### Generator invariants — not constants, but specified here so they are checkable

| Invariant | Statement |
|---|---|
| `INV_tags_distinct_in_class` | tags are distinct within a key class, so "my ◆ machine" names one machine. |
| `INV_cyclic_sigma` | σ is a single n-cycle (`roles.md` §2). Already enforced by construction in `Ring.luau`. |
| `INV_every_class_has_a_step` | every key class has at least one step. With the ring, this is all k-essentiality needs (`mechanics.md` §6.3 I1). |
| `INV_balanced_steps` | step counts per class differ by at most 1. |
| `INV_track_alternates` | consecutive steps within a track have different key classes. |
| `INV_finale` | the finale's machines are in different rooms at least `paired_room_distance_min` apart, of non-adjacent key classes when n ≥ 4. |
| `INV_k_essential` | re-derived: follows from `INV_cyclic_sigma` + `INV_every_class_has_a_step` + `dial_settings` ≥ 2. Still worth a direct test per seed. |
| `INV_traversal` | `par × schedule_slack ≤ round_seconds`, with par computed with pings at 10 s (`mechanics.md` §6.3). **Replaces `INV_rate`.** |
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
| `blackout_selection` | weighted toward rooms with live or waiting steps | **derived** | random selection would often darken a finished room and do nothing. |

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
| — | walking model | `room_traversal_seconds`, `traversal_reserve_seconds`, `room_count` | the first timed M3 playtest |
| — | two red tests on landing | `round_seconds`, `traversal_reserve_seconds` (ROUND-002); `signal_rate_limit_seconds` (NET-003) | Lead PO: stories and ROUND-002 amendment |

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
