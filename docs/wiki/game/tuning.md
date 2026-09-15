# Tuning constants

**This file is the specification.** The module that implements these values is
source, written by the Feature Developer in GREEN. If a value in the module and a
value here disagree, that is a defect — raise it with the Lead PO rather than
editing either to match.

Every constant carries exactly one label:

| Label | Means |
|---|---|
| **derived** | follows from a constraint or another constant; the derivation is stated |
| **taste** | could legitimately be otherwise; the operator chose it, or is asked to |
| **placeholder** | a guess, present so the thing can be built; names the observation that replaces it |

A fourth appears in one place: **taste-pending** — a value specified provisionally
so implementation is not blocked, on a question the operator has not yet answered.
It is a placeholder whose replacement is a decision rather than an observation.

Names are the names the implementing module should use.

---

## 1. Session and lobby

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `players_min` | 4 | **derived** | product-brief §0b amendment 1. Also the smallest ring in which the two-layer puzzle has room — `loop.md §2`. |
| `players_max` | 6 | **derived** | channel contention: tokens in flight scale with `n`, comprehension does not (`loop.md §2`). **Supersedes A4's cap of 16.** The exact boundary is soft; `playtest.md: P-N` reads it. |
| `min_players_to_continue` | 3 | **derived** | a 3-cycle ring is still a ring (`roles.md §6`). Below 3 there is no derangement worth the name. |
| `lobby_seconds` | 60 | taste | inherited from A4. UX pacing rather than game tuning; the Lead Designer owns it once a screen exists. |
| `post_round_seconds` | 45 | **placeholder** | A4 said 30; the post-round trace (`mechanics.md §7`) is four items of reading. Replace when two consecutive playtests show groups still reading at the cut, or consistently skipping before 20s. |
| `season_length_days` | 28 | **derived** | A2 #2 measures days 8–28. A season shorter than the retention window it is meant to drive is measuring itself. |

---

## 2. The instance

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `room_count` | 6 | **placeholder** | enough for blackout to bite (§5) and for `paired_room_distance_min` to be meaningful, few enough to traverse inside the clock. Replace when playtests show more than ~25% of round time spent walking, or when players never leave one room. |
| `actuator_count` | 16 | **derived** | `procedure_length × actuator_redundancy`. |
| `actuator_redundancy` | 2 | **derived from a design requirement** | half the actuators are not in the Procedure. This is what makes a player's view **larger than their contribution**, which is what makes selection a decision and what gives `signal_budget_per_player < view_enumeration_tokens` something to bite on. Without redundancy, every fact you hold is needed and "which fact matters" is not a question. |
| `procedure_length` | 8 | **placeholder** | 2 operations per player at the 4-floor. Replace when playtests finish with more than 90s of clock left twice running (too short) or when groups reach the clock with 3+ operations uncommitted twice running (too long). |
| `mark_alphabet_size` | 8 | **derived** | must equal `procedure_length`, so that required values are in bijection with operations and **a value-mark uniquely names an operation** (`mechanics.md §3.1`). This is the property that turns a vocabulary with no referents into one where referents can be discovered. |
| `key_classes` | = `players_min`..`players_max` | **derived** | one key class per player (`roles.md §2`). |
| `actuators_per_class` | 4 | **derived** | `actuator_count / key_classes` at n=4. |
| `pairs_per_lens` | 4 | **derived** | = `actuators_per_class`. A lens covers exactly one key class. |
| `order_fragments_per_player` | 3 | **placeholder** | 12 fragments total over 8 operations. A total order over `k` elements needs at least `k−1` covering relations, so 7 are load-bearing and 5 are redundancy. Replace if groups routinely resolve the order without spending a token on it (too much redundancy) or never resolve it at all (too little). |
| `simultaneous_ops_min` | 1 | **derived** | `loop.md §1.6` device 3: the mechanism that puts bodies in two rooms. One per round is the minimum that makes the claim true. |
| `simultaneous_window_seconds` | 5 | **placeholder** | long enough to survive a `GO` token plus a reaction; short enough that the two players must already be in position. Replace when paired operations succeed on the first attempt every time (too long) or when groups stop attempting them (too short). |
| `paired_room_distance_min` | 2 | **derived** | at distance 1 a single player could sprint between them inside the window, which would defeat the mechanism the constant exists for. |

### Generator invariants — not constants, but specified here so they are checkable

| Invariant | Statement |
|---|---|
| `INV_no_self_value` | for every actuator, `required_value ≠ tag`. Excludes the instance where the answer is written on the machine. |
| `INV_tags_distinct_in_class` | tags are distinct within a key class, so a player can name their dependent's actuators unambiguously. |
| `INV_values_distinct` | the `procedure_length` required values are pairwise distinct and exhaust the mark alphabet. |
| `INV_cyclic_sigma` | the lens/key permutation is a single `n`-cycle, not two 2-cycles (`roles.md §2`). |
| `INV_k_essential` | all `n` views admit exactly one consistent Procedure; any `n−1` admit at least two (`mechanics.md §6.3` I1). For the order layer this is nearly free: any player's-worth of fragments removed leaves fewer than `procedure_length − 1` covers, so the order is underdetermined. For the value layer it must be checked by construction. |
| `INV_centralisation` | `signal_budget_per_player < view_enumeration_tokens` (§3). |
| `INV_rate` | the canonical cooperative protocol's transfers fit in the round with `rate_headroom` to spare (`mechanics.md §6.3` I3). |

---

## 3. The signal channel

The three constants that carry the design. Read `mechanics.md §4` first.

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `vocabulary_size` | 16 | **derived** | `mark_alphabet_size (8) + ordinals (3) + polarity (2) + meta (3)`. |
| `ordinal_tokens` | `FIRST`, `BEFORE`, `AFTER` | **derived** | the minimum set that can express a precedence and an anchor. Two would not distinguish direction. |
| `polarity_tokens` | `YES`, `NO` | **taste** | could be one (`NO` alone) for a harsher language. Two is the gentler choice and was taken deliberately. |
| `meta_tokens` | `AGAIN`, `WAIT`, `GO` | **derived** | `WAIT`/`GO` are what make the order layer cheap to *act on* and expensive to *relay* — the asymmetry the centralisation bound depends on (see `view_enumeration_tokens` below). `AGAIN` exists so re-assertion costs a token rather than being free. |
| `wheel_rows × wheel_columns` | 4 × 4 | **derived** | a radial wheel must be navigable in about a second under pressure. Beyond roughly 20 entries it is a menu, not a reflex, and the channel's difficulty migrates from selection to UI. This bounds `vocabulary_size` from above and is the reason the four groups are sized as they are. |
| `signal_cost` | 1, uniform | **taste** | variable cost would create an economy in which some facts are cheaper to state than others, which is interesting and adds a second thing to learn. Uniform was chosen so the only question is *what*, never *how much*. |
| `signal_budget_per_player` | 12 | **placeholder** | **The most uncertain number in this document.** 12 tokens across 480 seconds is roughly one every 40s. That sparsity is the design's whole thesis — it is what makes a token an event — and it is also exactly how the design could be paralysing rather than tense. Constrained from both sides below. Replace via `playtest.md: P-B`. |
| `view_enumeration_tokens` | ≈ 17 | **derived** | `pairs_per_lens (4) × 2 + order_fragments_per_player (3) × 3`. What it would cost to say everything you know, literally. |
| — the upper bound | `signal_budget_per_player < view_enumeration_tokens` | **derived** | 12 < 17. **You cannot say everything you know.** This is what forces selection (`loop.md §1.2`) and what makes centralising impossible (`loop.md §1.7` device 3): three players spending their entire budgets cannot brief a fourth. |
| — the lower bound | `cooperative_minimum_tokens × protocol_slack ≤ signal_budget_per_player` | **derived** | ≈ 6 × 2.0 = 12. The canonical protocol costs about 6 tokens per player — around 4 for the pairings that turn out to be in the Procedure, and 1–2 spent *gating* with `WAIT`/`NO` rather than transferring the fragments themselves. The slack is what pays for being wrong. |
| `cooperative_minimum_tokens` | ≈ 6 | **derived, per instance** | computed by the generator for each instance, not a global constant. The value here is the expected case at the default band. |
| `protocol_slack` | 2.0 | **placeholder** | a group should be able to be wrong roughly once per fact and still win. Replace when win rate at the default band sits outside `win_rate_target`. |
| `signal_reserve` | 2 | **placeholder** | of the 12, locked until the endgame so no player can render themselves mute by 3:00. Replace if players routinely hit the reserve before it unlocks (raise, or reconsider the budget) or never touch it (lower). |
| `reserve_unlock_seconds_remaining` | 90 | **placeholder** | the endgame. Replace alongside `signal_reserve`. |
| `signal_rate_limit_seconds` | 1.5 | **derived** | two purposes at once: it keeps the shared stream readable at `players_max` senders, and it satisfies B4's requirement that every remote be rate-limited. Not a scarcity mechanism — `signal_budget_per_player` is the binding constraint by two orders of magnitude. |
| `signal_display_seconds` | 6 | **placeholder** | the attentional axis (`mechanics.md §4.4`) — long enough to read and attribute, short enough that you cannot batch. Open as **T7**; replace via `playtest.md: P-M`. |
| `signal_log_depth` | 0 | **taste** | no scrollback. This is anti-quarterback device 5 and half of the voice-proof axis. It is also the least inclusive difficulty in the design. **T7** offers three softer options, each one constant. |
| `signal_reveals_sender` | true | **taste** | attribution is what lets the group model who knows what, and what makes the trace actionable. Turning it off would make the stream anonymous and the language very much harder; that was not chosen. |
| `signal_reveals_sender_room` | false | **taste** | **open as T6, and the largest single lever on early-session difficulty.** False means deixis is entirely absent and location must be built by convention. True hands the language a free referent and makes the map legible. |

---

## 4. Actuation and instability

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `actuation_reset_seconds` | 3 | **placeholder** | a failed actuator returns to unset. Long enough to see it failed, short enough not to punish twice. Replace if players queue up waiting for resets. |
| `actuation_failure_is_diagnostic` | false | **taste** | false means wrong-value and wrong-turn produce an identical response, so the group must resolve the ambiguity through the channel. True would make failures informative and the game markedly easier. The cheapest difficulty lever in the design, and a natural axis for `difficulty_band`. |
| `instability_max` | 5 | **placeholder** | the round is lost at 5 wrong actuations. With `procedure_length` 8, that is roughly one error tolerated per 1.6 operations. Replace when losses by instability and losses by clock are not within roughly 2:1 of each other in either direction — a design where one loss condition never fires has one loss condition. |
| `instability_per_wrong_value` | 1 | **derived** | wrong value and wrong turn must cost the same, or `actuation_failure_is_diagnostic` leaks through the scoreboard. |
| `instability_per_out_of_order` | 1 | **derived** | as above. |
| `instability_per_failed_pair` | 1 | **derived** | one operation, one penalty, even though two actuations failed (`mechanics.md §5`). |
| `instability_clock_penalty_seconds` | 20 | **placeholder** | 5 errors would remove 100s of 480 — about 20% of the round — before the blackout effects are counted. Replace if groups reach `instability_max` before the clock matters, which would mean the penalty is redundant. |
| `instability_blackout_threshold` | 2 | **placeholder** | blackouts at instability 2 and 4, so a group feels the mechanism twice before losing to it. Replace if the first blackout regularly ends the round outright. |
| `blackout_rooms_per_threshold` | 1 | **placeholder** | of `room_count` 6. Replace alongside the threshold. |
| `blackout_selection` | weighted toward rooms with uncommitted operations | **derived** | random selection would frequently black out a finished room and do nothing, which turns a designed consequence into a coin flip. |

---

## 5. Round timing

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `round_seconds` | 480 | **placeholder** | 8 minutes, inside A3 pillar 5's 6–10. Derived *shape*: `procedure_length × per_operation_seconds` plus traversal. Replace via the `procedure_length` observation above — the two move together and should be tuned as a pair, not independently. |
| `round_seconds_min` / `_max` | 360 / 600 | **derived** | A3 pillar 5. A round outside this band is a different product decision, not a tuning change. |
| `per_operation_seconds` | 45 | **derived** | `(round_seconds − traversal_reserve) / procedure_length`. Stated so that changing `procedure_length` changes `round_seconds` rather than silently compressing the game. |
| `traversal_reserve_seconds` | 120 | **placeholder** | time the round spends walking rather than deciding. Replace when a playtest measures it; this is currently a guess with no observation behind it at all. |
| `first_round_within_seconds` | 480 | **derived** | A5's day-1 requirement is a completed first round within 8 minutes of joining. With `lobby_seconds` 60 and `round_seconds` 480 that is **already violated** — 9 minutes. Either A5's number or this one must move; flagged for the Lead PO. |
| `disconnect_grace_seconds` | 30 | **placeholder** | long enough for a reconnect, short enough that the ring is not broken for a quarter of the round. Replace with observed reconnect times once telemetry exists (B6). |

---

## 6. Difficulty bands

| Constant | Value | Label | Rationale |
|---|---|---|---|
| `difficulty_band` | `{ standard, hard }` | **taste-pending** | **Open as T5.** Two bands exist provisionally so a group on out-of-band voice has somewhere to go; the operator has not chosen between designing for the voiceless floor, designing for voice, or splitting the pool. Nothing in `mechanics.md` changes whichever way this lands — only the values below. |
| band-varied constants | `procedure_length`, `mark_alphabet_size`, `pairs_per_lens`, `signal_budget_per_player`, `instability_max`, `actuation_failure_is_diagnostic`, `signal_display_seconds`, `actuator_redundancy` | **derived** | every difficulty lever in this design is a generator parameter or a channel constant. None of them is content. That is A2 #4 satisfied rather than asserted. |
| `win_rate_target` | 0.45 | **placeholder** | for the standard band, for a group that has played together several times. Chosen below half so that a win is an achievement and the trace has something to teach most sessions; not so low that groups stop. Replace when observed win rate at the standard band is stable across 20+ sessions and the qualitative reading disagrees with the number. |

---

## 7. Constants this design deliberately does not have

Recorded so their absence is a decision rather than an omission.

| Absent | Why |
|---|---|
| `hidden_faction_ratio` | amendment 8. There is no hidden faction. |
| `vote_*` anything | there is no vote. Resolution is the Procedure completing or not. |
| any per-player score, rank, MMR or ladder constant | amendment 9: players win or lose together and progression is shared. A5's ranked ladder and M5's competitive framing should be withdrawn by the Lead PO. |
| role unlock cadence | `roles.md §5`: there are no roles to unlock. A5 days 2–7 needs re-deriving against a co-op shape. |
| any constant affecting round outcome that a purchase could change | A6: all SKUs cosmetic, convenience or social. This line exists so that the rule is visible in the file a monetisation story would otherwise edit. |

---

## 8. Open, and what closes each

| # | Question | Constants waiting on it | Closed by |
|---|---|---|---|
| T5 | posture toward out-of-band voice | `difficulty_band` and everything it varies | operator decision |
| T6 | does a signal carry its sender's room | `signal_reveals_sender_room` | operator decision; `playtest.md: P-3` informs it |
| T7 | how much memory load | `signal_display_seconds`, `signal_log_depth` | operator decision; `playtest.md: P-M` informs it |
| T9 | seasonal vocabulary rotation | none yet — unspecified deliberately | operator decision |
| — | the budget | `signal_budget_per_player`, `signal_reserve`, `protocol_slack` | `playtest.md: P-B` |
| — | traversal cost | `traversal_reserve_seconds`, `room_count` | first timed playtest |
| — | A5 day-1 conflict | `first_round_within_seconds` | Lead PO |
