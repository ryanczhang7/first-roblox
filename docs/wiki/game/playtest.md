# Playtest protocol

No gate judges fun, and none ever will. `lune run check` (B5) will tell you the
round state machine is correct, that the generator's invariants hold, and that no
client can read another player's lens — and it will tell you nothing about whether
anyone wants to play it. This file is the compensating practice. It is what turns
M3 and M4 from "the operator signs off" into an observation.

**Rewritten 2026-09-15 (second pass).** The previous version falsified *candidates*
because the genre was open. The genre is decided (amendment 8), so every entry
below falsifies a **constant in `tuning.md` or a mechanic in `mechanics.md`**, and
names what a bad reading sends you back to.

**Priority order.** If you can only run three, run **P-C, P-Q and P-B**. P-C tests
the retention thesis, P-Q tests whether it is a four-player game, and P-B tests the
number the design is least sure of.

**Paper-runnable** entries need no code and can be run today: P-1, P-3, P-Q, P-B,
P-V. The rest need at least the M3 vertical slice.

---

## Carried over from the first pass

| Old | Disposition |
|---|---|
| **P1** — does a 4-player group separate on its own? | **Kept, re-aimed** → P-1 below. Candidate B still needs bodies apart: observation is position-dependent (`mechanics.md §2`) and paired operations require two rooms at once. What changed is that B *has* a forcing mechanic, so the question is no longer "will they separate" but "does the mechanism actually hold them apart". |
| **P2** — does a fixed vocabulary carry a lie? | **Retired.** There is nobody to lie to. The finding it would have produced is already recorded in `loop.md` appendix A1 and stands as the argument against ever bolting a traitor onto this design. |
| **P3** — is the constrained channel a puzzle or a handicap? | **Kept, re-aimed** → P-3 below, now against the actual 16-token vocabulary rather than a generic one. |
| **P4** — does a 4-player hidden-role round survive its first vote? | **Retired.** No vote, no elimination, no hidden faction. |

---

## P-C — Does a group invent conventions?

    Question    over repeated sessions, does the same four-person group build
                shared meaning the vocabulary does not carry — an agreed order for
                a pairing, a mark that has become a place name, a rhythm that
                distinguishes assertion from repetition?
    Working     by session 4, at least two conventions exist that the group can
                state out loud afterwards and that were never in the UI; budget
                efficiency (wasted tokens, per mechanics.md §7) falls session over
                session; the group's win rate rises while the difficulty band
                does not change
    Not working by session 6 the group is still sending tokens literally and
                reading them literally; wasted-token count is flat; players
                describe the channel as "guessing"; OR the group converges
                instantly on one obvious convention in session 1 and nothing
                further ever develops
    Sessions    6 with the SAME four people. This is the longest protocol here and
                it cannot be shortened — the thing being measured is accumulation.
                Run it with two independent groups, because one group that happens
                to contain a puzzle enthusiast proves nothing.
    Falsifies   the retention thesis itself (loop.md §1.4), and with it the main
                argument for B over the other candidates. Constants it sends you
                back to: vocabulary composition (tuning.md §3: mark_alphabet_size,
                ordinal_tokens, meta_tokens), signal_reveals_sender_room (T6),
                signal_display_seconds.
    How         paper-runnable from session 1: four people, printed lenses, a
                16-token card each, a token budget in counters, a referee holding
                the instance. No screens needed.
    Result      not yet run

**Read the second "not working" carefully.** Instant convergence is as bad as
never converging: it means the language's gap was trivially fillable and layer-3
variance (`loop.md §1.4`) does not exist. That reading sends you toward a *larger*
gap, not a smaller one, and it is the reading the design is least prepared for.

---

## P-Q — Does one player run the round?

    Question    do the six anti-quarterback devices (loop.md §1.7) actually
                produce four players making decisions, or three players executing
                one player's instructions?
    Working     all four players originate facts unprompted; at least two players
                per round spend a token that changes what somebody else does;
                post-round, players disagree about what happened, which means they
                held different models
    Not working one player's token stream is more than ~40% of the round's total;
                the other three send mostly YES and AGAIN; players describe the
                round afterwards in terms of what one person "worked out"; OR — the
                polite failure — everyone acts, but only after being asked to
    Sessions    4, with group composition varied. Quarterbacking is a property of a
                group, not of a design, so one group with a dominant personality is
                not a finding and one group of four strangers is not either.
    Falsifies   the device set in loop.md §1.7. Constants:
                signal_budget_per_player (device 1/3 — if it is too generous,
                briefing fits), actuator_redundancy and view_enumeration_tokens
                (the bound depends on V > budget), signal_display_seconds and
                signal_log_depth (device 5), simultaneous_ops_min (device 6).
                A confirmed "not working" on the polite failure specifically
                implicates INV_k_essential: if three players can proceed on
                instruction alone, the fourth's lens was not load-bearing.
    How         paper-runnable. Record every token with its sender; the 40%
                threshold is countable afterwards.
    Result      not yet run

The polite failure is the one to write down before the session and watch for
during it. A group where everyone participates and nobody decides looks
indistinguishable from a working round until you count who originated.

---

## P-B — Is the budget the right size?

    Question    is `signal_budget_per_player` = 12 across 480 seconds scarcity that
                makes each token an event, or scarcity that makes players stop
                trying?
    Working     players visibly hesitate before spending; at least one player ends
                most rounds with 0–2 tokens left; someone says a version of "is it
                worth it" out loud; the reserve unlocks into a real endgame rather
                than into tokens nobody needs
    Not working players finish rounds with 5+ unspent tokens routinely (too
                generous — and the centralisation bound is then weaker than
                specified, so check P-Q too); OR players are mute by the halfway
                point and the round becomes a silent guessing game; OR players stop
                spending at all and simply brute-force actuations against
                instability, which is the budget being priced above its value
    Sessions    3 at the specified value, then 3 at a value 50% higher, same
                groups, same band. A budget cannot be read without a comparison —
                a single value always feels like "the rules".
    Falsifies   signal_budget_per_player, signal_reserve,
                reserve_unlock_seconds_remaining, protocol_slack. If the
                brute-force reading appears, it also implicates instability_max and
                instability_clock_penalty_seconds: guessing is only rational when
                it is cheaper than talking.
    How         paper-runnable with physical counters, which is better than a
                screen for this — a shrinking pile of tokens is legible in a way a
                number is not, and the hesitation is observable.
    Result      not yet run

---

## P-1 — Does the mechanism hold bodies apart?

    Question    do `simultaneous_ops_min` paired operations and position-dependent
                observation actually keep four players in different rooms, or do
                they cluster between the forced moments?
    Working     no more than two players in the same room for >30s for most of the
                round; the paired operation is a scramble that has to be set up
                rather than a formality; players choose where to stand rather than
                following each other
    Not working the group moves as a block and splits only for the paired
                operation, then re-forms; OR players find one room from which most
                actuators are reachable and the map collapses to it
    Sessions    3 — group movement is habit-driven and the first session is always
                people being polite
    Falsifies   simultaneous_ops_min, paired_room_distance_min, room_count,
                simultaneous_window_seconds, and the actuator-to-room placement
                rule in mechanics.md §6.1. The block-movement reading means one
                paired operation per round is not enough; the collapsed-map reading
                means placement is not spreading actuators.
    How         paper-runnable with a map on a table and four tokens for players,
                but the reading is much better in the M3 slice, because walking is
                the cost being measured and a table has no walking.
    Result      not yet run (carried from first-pass P1, re-aimed)

---

## P-3 — Is the channel a puzzle or a handicap?

    Question    with the actual 16-token vocabulary and no deixis, does the gap in
                the language read as the interesting difficulty or as a missing
                feature?
    Working     failures are attributed to "we described it badly"; players retry;
                the phrase that appears is some version of "we need a way to say
                X", which is players proposing a convention rather than requesting
                a feature
    Not working "if I could just say" appears repeatedly and is followed by nothing
                constructive; someone opens a voice call unprompted in session 1;
                players ask which token means what, repeatedly, past session 2 —
                which would mean the marks are not learnable, a UI finding for the
                Lead Designer rather than a mechanic finding
    Sessions    2 — this reading is fast and unambiguous
    Falsifies   the Expressibility Rule (mechanics.md §4.4) and T6. Constants:
                signal_reveals_sender_room — this is the protocol that most
                directly informs whether deixis should be free; also
                mark_alphabet_size and the meta_tokens set.
    How         paper-runnable. Four people, printed token cards, a referee, strict
                enforcement of no speech.
    Result      not yet run (carried from first-pass P3, re-aimed)

---

## P-V — Does out-of-band voice dissolve the puzzle?

    Question    the same instance, same group, played twice: once under strict no
                speech, once with the group on voice. Does the voice run reduce the
                game to a formality?
    Working     the voice run is faster and easier but still loses sometimes; the
                bottleneck visibly moves from "how do I say it" to "who is where
                and when" — attention and timing rather than expression; the group
                still spends tokens, because gating with WAIT/GO is faster than
                talking
    Not working the voice run is trivially won with the token budget almost
                untouched; players stop looking at the stream entirely; the round
                becomes four people reading a list to each other
    Sessions    2 matched pairs (4 rounds), different instances, same group. Do
                the silent run FIRST in each pair or the voice run teaches the
                instance.
    Falsifies   **the T5 posture, and indirectly the T1 = B decision.** A confirmed
                "not working" does not kill B, but it means the expressive axis of
                lossiness is doing none of the work for a voice group, and every
                design lever must move to the attentional axis: signal_display_seconds
                down, signal_log_depth stays 0, procedure_length and per_operation_seconds
                compressed so speech is also too slow, rate_headroom reduced.
                It would also make `difficulty_band` mandatory rather than
                taste-pending.
    How         paper-runnable, and it should be run early because it bears on a
                decision already taken.
    Result      not yet run

This is the protocol that tests the thing the first pass missed. It should have
been run before T1 was decided; run it before M3 instead.

---

## P-M — Is ephemerality difficulty or exclusion?

    Question    does `signal_display_seconds` = 6 with no scrollback produce
                productive memory pressure, or does it exclude players and punish
                ordinary interruption?
    Working     players develop memory strategies — repeating a mark under their
                breath, actuating immediately on receipt, asking for AGAIN; missing
                a signal is a recoverable mistake and costs one token
    Not working players report the round as stressful in a way they do not enjoy;
                a player who looks away for five seconds is functionally out of the
                round; AGAIN becomes the most-sent token, which means the budget is
                being spent on the interface rather than on facts
    Sessions    3, and deliberately include at least one group that is not
                composed of people who are good at this. Memory load is the least
                inclusive difficulty in the design and a protocol run only on
                enthusiasts will read as working.
    Falsifies   signal_display_seconds, signal_log_depth, and T7. If AGAIN
                dominates, the specific repair is one of T7's three options, not a
                longer display window — a longer window weakens the voice-proof
                axis (P-V) and device 5 of the anti-quarterback set (P-Q), so this
                constant cannot be moved on this protocol's reading alone.
    Result      not yet run

Note the cross-dependency explicitly: P-M, P-Q and P-V all pull
`signal_display_seconds` in different directions. Read all three before moving it.

---

## P-T — Does the post-round trace teach anything?

    Question    does the trace (mechanics.md §7) change what a group does in the
                next round, or is it a screen people skip?
    Working     a group that saw "the fact nobody sent" sends that class of fact
                earlier in the next round; wasted-token count falls after a trace
                that highlighted waste; players point at the screen and argue about
                it
    Not working players skip or talk over the trace; the same unsent-fact class
                recurs across four consecutive rounds for the same group; nobody
                can say afterwards what the trace showed
    Sessions    4 consecutive rounds with the same group, which is the minimum for
                "did it change behaviour" to be answerable at all
    Falsifies   post_round_seconds, and the trace's content selection — if players
                engage but with only one of the four items, the other three are
                noise and should be cut. A total "not working" means the answer to
                question 5 (what failure teaches) is unearned and the design is
                back to a reveal, which loop.md §1.5 argued is not a lesson.
    How         needs the M3 slice. A paper version can be refereed but the reading
                is weak, because a referee explaining the trace is not the same as
                a screen showing it.
    Result      not yet run

---

## P-I — Does degradation read as pressure or as punishment?

    Question    do instability, the clock penalty and blackouts feel like the group
                tightening its own noose, or like the game kicking them while down?
    Working     the first blackout changes behaviour — the group slows down and
                spends tokens where it had been guessing; groups describe losses by
                instability as their own fault
    Not working the first blackout ends the round in practice and the remaining
                time is ceremonial; OR instability never reaches the first
                threshold, so the whole mechanism is decorative; OR groups describe
                the darkness as unfair
    Sessions    3, and record the loss reason every round. If losses by instability
                and losses by clock are not within roughly 2:1 of each other, one
                of the two loss conditions is not real.
    Falsifies   instability_max, instability_blackout_threshold,
                blackout_rooms_per_threshold, instability_clock_penalty_seconds,
                blackout_selection. The "ceremonial" reading specifically
                implicates blackout_selection's weighting toward uncommitted rooms
                — it may be biting too hard.
    Result      not yet run

---

## P-N — Where does the channel become noise?

    Question    `players_max` is derived from channel contention but its value is a
                guess. At what `n` does the shared stream stop being readable?
    Working     at n=5 and n=6 players can still attribute tokens to senders and
                act on them; the round's difficulty still feels like selection
    Not working players stop reading the stream and fall back to acting only on
                tokens they were watching for; attribution errors appear (acting on
                the wrong player's mark); the game's difficulty has become keeping
                up rather than choosing
    Sessions    2 each at n=4, 5, 6 — six sessions, and n=4 is the control, not a
                formality
    Falsifies   players_max, signal_rate_limit_seconds, signal_display_seconds.
                Note that raising the rate limit to thin the stream costs
                throughput, which INV_rate may not have room for; check the
                generator's rate headroom before moving it.
    Result      not yet run

Low priority until lobby fill is a real question, but it is cheap to ride along
with any session that happens to have five or six people.

---

## Running rules

- **Write the "not working" reading before the session, never after.** A protocol
  with only a success condition confirms whatever happened. Every entry above was
  written before any session; keep it that way.
- **Name the constants a bad reading sends you back to.** Every entry does. An
  observation that changes nothing was not worth making.
- **Record sessions that went nowhere.** Four people who spent the round joking
  and never engaged the mechanic is data about the mechanic. A file that records
  only confirmations is a diary.
- **Count, do not remember.** P-Q's 40% threshold, P-B's unspent tokens, P-M's
  AGAIN frequency and P-I's loss reasons are all counts. Once the M3 slice exists
  the server already logs every one of them for the trace (`mechanics.md §7`), so
  the counting is free — until then, a tally sheet.
- **Sessions can share a sitting.** P-1, P-Q and P-B all want the same four people
  playing normally and differ only in what you count; run them together. P-3 and
  P-M likewise. P-V needs its own matched pairs. P-C is the frame the others sit
  inside: six sessions with one group, counting the others along the way.
- **Vary the group.** P-Q and P-M are the two most sensitive to who is in the
  room, and both have a "not working" reading that a group of enthusiasts will
  never produce.
- **The operator runs these, not an agent.** Nothing here is automatable and
  nothing here should be simulated. A simulated playtest is a model of the
  designer's expectations, which is the thing being tested.
