# Playtest protocol

No gate judges fun, and none ever will. `lune run check` (B5) will tell you the
phase machine is correct, that the generator's invariants hold, that no client
can read another player's lens, and that the preset table obeys the guideline's
countable rules. It will tell you nothing about whether anyone wants to play it,
or whether a seven-year-old can. This file is the compensating practice. It is
what turns M3 and M4 from "the operator signs off" into an observation.

**Revised 2026-09-30 (third pass) for brief §0d #14 and #19.** The channel the
second pass's protocols measured no longer exists. Every entry below falsifies a
constant in `tuning.md` or a mechanic in `mechanics.md` *as they now stand*, and
names what a bad reading sends you back to. Retired entries are kept in the
table below with the reason.

**Priority order.** If you can only run four, run **P-D, P-K, P-Q and P-S**.

- P-D tests whether the central decision exists at all.
- P-K tests whether a child can play the floor (§0d #14).
- P-Q tests whether it is a four-player game.
- P-S tests whether players bend the presets into a code, which would be a
  compliance problem the design claims it has removed the reason for.

P-C, which the second pass ranked first, is now fifth. It measures the
retention layer that replaced invented language (`loop.md` §1.4), and it only
matters if P-D says there is a game.

**Paper-runnable** entries need no code and can be run today: P-D (weakly),
P-Q, P-S, P-G, P-V. The rest need the M3 vertical slice, because walking is the
thing being measured, and a table has no walking.

---

## Carried over from the second pass

| Old | Disposition |
|---|---|
| **P-C**: does a group invent conventions? | **Re-aimed.** Invented conventions over the channel are what §0d #19 forbids. Now: does a group develop *choreography*? See P-C below |
| **P-Q**: does one player run the round? | **Kept, re-aimed** at structural devices, and at a new form of steering: doorway pings |
| **P-B**: is the budget the right size? | **Retired.** There is no budget. Its "brute-force against instability" reading survives as **P-G** |
| **P-1**: does the mechanism hold bodies apart? | **Kept**, with constants updated for the finale and reading range |
| **P-3**: is the channel a puzzle or a handicap? | **Retired.** It tested the Expressibility Rule, which is superseded. Its useful half ("do players ask for a way to say X?") is now **P-S**'s working reading, inverted: they should not need to |
| **P-V**: does out-of-band voice dissolve the puzzle? | **Re-aimed.** The posture is decided (§0d #15). P-V now only sizes the voice advantage, which informs T17 |
| **P-M**: is ephemerality difficulty or exclusion? | **Re-aimed.** Ephemerality of facts is retired. Now: does anything at the floor still depend on memory? Folded into **P-K** as its memory reading, with its own constants |
| **P-T**: does the trace teach anything? | **Kept, re-aimed** to the new trace, and to whether a child reads the headline |
| **P-I**: pressure or punishment? | **Kept**, with a reading for young players and T15 |
| **P-N**: where does the channel become noise? | **Re-aimed** to idle time at n = 5 and 6 |

---

## P-D — Does the central decision happen?

    Question    does a player, several times a round, face "my step and my
                partner's step both need me: which first?" and "wait for my
                helper, or guess?" - and do different players answer
                differently?
    Not working players never face the conflict, because the two tracks rarely
                have steps live at once that want the same body; OR they face it
                and always answer the same way (for example "always help my
                partner first"), which is a dominant option, not a decision; OR
                nobody ever guesses, or everybody always guesses
    Working     each player meets the two-place conflict at least twice a round;
                the answer varies with distance and with who is where; post-round,
                players can say why they went where they went; guesses happen,
                and are sometimes wrong and sometimes right
    Sessions    3 in the M3 slice, same group. A decision that exists shows up in
                the first session; whether it has a dominant answer needs three
    Falsifies   the claim in loop.md §1.2, and with it the redesign's core.
                Constants: procedure_tracks (no conflicts: consider 3 tracks, or
                shorter tracks), INV_track_alternates, actuator placement
                (conflicts always resolve the same way: placement is making one
                answer always nearer), dial_settings and
                instability_clock_penalty_seconds (the guess half, and see P-G)
    How         count, per player, the moments at which one of their own machines
                and one of their partner's machines were live at once. The
                server log has this for free once the slice exists; on paper a
                referee can tally it, but paper has no walking, so the "answer
                varies with distance" half is weak there
    Result      not yet run

A "not working" here is the one that would send the design back to the drawing
board rather than to a constant. Run it before any other slice protocol.

---

## P-K — Can a child play the floor?

New, 2026-09-30, for §0d #14. The only protocol whose subjects are not the
people the operator usually plays with.

    Question    can a child at the youngest age the floor is designed for
                (T19: 7, operator, 2026-09-30) play a useful round - find their live
                machine, go to their partner's, ping the glowing setting, turn
                their own dial to their helper's ping - with no rules explanation
                and no adult help, and does anything at the floor depend on
                reading or memory?
    Not working the child needs an adult to explain what to do more than once
                after the first minute; OR they cannot say, afterwards, what
                their helper does for them; OR they turn their dial to pings that
                are not their helper's; OR they arrive at a pinged machine after
                the ping has expired and are stuck (the memory reading, formerly
                P-M); OR they never use the preset wheel because they cannot
                read it; OR they are frightened by the dark or the failure tone
                (T15); OR the adults in a mixed group take over the child's key
                by telling them exactly where to go and what to press; OR the
                child watches the progress bar instead of their own turn cue,
                or reads it as a timer and panics
    Working     by the end of the second round, the child finds and turns their
                own machine with their helper's ping without being told; they can
                point at their helper on screen; they have pinged a setting for
                their partner at least once unprompted; asked what the progress bar
                means, they say something like "how much we've done";
                they want another round
    Sessions    3 groups: two mixed (one child with three adults or teenagers)
                and one all children, each for 2 rounds. Children's play varies
                far more by individual than adults', so one child is an anecdote
    Falsifies   the floor in loop.md §1a. Constants and rules: ping_display_seconds
                and preset_display_seconds (the memory reading),
                actuation_failure_is_diagnostic (T13: a child who cannot tell
                "wrong" from "not yet" is the T13 answer), turn_cue_lookahead,
                dial_settings (can a child distinguish the settings in the dark),
                blackout_permanent (T15), first_session_win_rate_target (T18),
                progress_bar_marks_finale and the bar's presentation (the
                bar-as-timer reading is a Lead Designer finding, not a reason
                to show more on it),
                and the preset presentation requirements (icon plus word) for
                the Lead Designer. The "adults take over" reading implicates
                P-Q's devices, specifically the fact that a ping to a doorway is
                a way to steer a child
    How         the M3 slice. Guardian consent and a guardian present, every
                time. Record counts and short notes, never audio or video of
                children, and no identifying details in this file. The operator
                runs it
    Result      not yet run

Write down the "adults take over" reading before the session. It looks like
kindness, and it is the child being turned into an input device.

---

## P-Q — Does one player run the round?

    Question    do the six devices in loop.md §1.7 produce four players making
                decisions, or three players executing one player's plan?
    Not working one player's pings and presets are more than about 40% of the
                round's total; others' pings are mostly to settings when told to
                go there, and rarely to doorways or machines of their own
                choosing; players describe the round afterwards in terms of what
                one person "worked out"; OR - the polite failure - everyone acts,
                but only after being pinged towards somewhere; OR a planner
                steers everyone with doorway pings; OR - new with T10 (c) - the
                progress bar becomes a planning signal: a player reads a jump
                in the bar, infers which track moved from who was where, and
                directs the group from it; or the group waits for the bar to
                move before acting
    Working     all four players choose where to go unprompted most of the time;
                at least two players per round make a routing choice the others
                did not expect; post-round, players disagree about what happened,
                which means they held different pictures
    Sessions    4, with group composition varied. Quarterbacking is a property of
                a group, not of a design
    Falsifies   the device set. T10, answered (c) by the operator on 2026-09-30:
                this protocol is what tells the operator whether that answer
                holds. A public board, T10 (b), would make this reading more
                likely; private cues are the defence, and the bar is safe only
                while it is a count. If the bar-as-plan reading appears, the
                repair is to show LESS on the bar (drop progress_bar_marks_finale
                first), never more, and it goes back to the operator because it
                reopens T10. Also: active_pings_per_player,
                ping_rate_limit_seconds (now 10 and derived, Lead PO CA-1
                decision 2026-09-30; a compliance value, so the doorway-steering
                reading goes to active_pings_per_player before the rate), and
                finale_paired_ops. Devices 1 and 3 are structural and cannot be
                mis-tuned: if the reading is "not working" anyway, the cause is
                elsewhere, and the first suspect is doorway steering
    How         paper-runnable for the counting; the slice for steering
    Result      not yet run

---

## P-S — Do players bend presets into a code?

New, 2026-09-30. The compliance claim in `mechanics.md` §4.3 C3 is that pointing
is always the cheapest way to send a fact, so no group has a reason to give
presets meanings they were not shipped with. That is a claim about behaviour,
and only a playtest can check it.

    Question    does any group, over several sessions, start using presets in
                combination, repetition or sequence to mean something the preset
                does not say ("Wait Wait" means the left one; "Go" twice means
                the second setting)?
    Not working any sequence convention appears and is used more than once; OR
                players say, in any words, "we need a way to say which one" and
                then build one from presets; OR a group asks for a preset that
                names a colour, a number or a place
    Working     presets are used one at a time, for what they say; when a player
                needs to say "which", they ping; nobody asks for more words
    Sessions    4 sessions with the same group (conventions need time to form),
                plus 2 with a second group. This is the one protocol where the
                reading "not working" is a compliance finding for the Lead PO,
                not only a design one
    Falsifies   INV_ping_dominates and C3. Constants: lens_read_range_studs and
                ping_range_studs (if pointing is too hard to do, a code becomes
                cheaper), preset_count (fewer presets,
                fewer ingredients), ping_settings_live_only (T20, answered (a)
                by the operator 2026-09-30: this protocol is what would reopen
                it, and a confirmed
                "not working" here is the strongest argument for (b)). The ping
                rate is fixed at the guideline's 10 s, so it is not a lever. A confirmed "not
                working" goes to the Lead PO as a compliance risk as well as to
                this file
    How         paper-runnable: printed preset cards, a 10 s timer per player
                (the rate limit is part of what is being tested), pings as a
                finger on the map, no speech. Then again in the slice
    Result      not yet run

---

## P-C — Does a group develop choreography?

Re-aimed 2026-09-30. The second pass asked whether a group invents *language*.
That is now forbidden. This asks whether a group invents *strategy*, which is
what `loop.md` §1.4 now rests the retention thesis on.

    Question    over repeated sessions, does the same group build a shared plan
                the game never taught them - who takes the far room, who goes to
                the finale early, calling Help before a step is live - and does
                it make them measurably faster?
    Not working by session 6 the group plays each round as if it were the first;
                their time against par is flat; players cannot name anything they
                do differently from session 1; OR the group converges in session
                1 on one obvious plan and nothing further develops
    Working     by session 4, the group can name at least two standing habits
                that were never in the UI; their margin against par grows session
                over session at the same band; a stranger dropped into the group
                is visibly slower until they learn its habits
    Sessions    6 with the SAME four people, run with two independent groups.
                Accumulation cannot be measured in fewer
    Falsifies   the retention thesis as re-stated in loop.md §1.4, and so bears
                on T16. Constants: room_count and actuator placement (maps that
                are too similar leave nothing to learn; maps that are too
                different make habits useless), turn_cue_lookahead (anticipation
                is the raw material of choreography), procedure_tracks
    How         the M3 slice; par and margin come from the trace for free
    Result      not yet run

**The stranger reading is the one that matters most for A2 #2.** If a stranger
is no slower, the group has built nothing that binds it, and the co-play thesis
is resting on generated variety alone. That goes straight to T16.

---

## P-G — Is guessing a real choice?

New, 2026-09-30. It replaces P-B's "brute-force" reading, which was the budget
being priced above its value.

    Question    is "guess the dial, or wait for my helper" a live decision, or
                does one option dominate?
    Not working nobody ever guesses (dial_settings too high, or penalties too
                steep: waiting always wins); OR guessing is the default and
                helpers stop coming (too cheap: the ring stops mattering); OR
                guesses are made regardless of instability, which means players
                do not see the cost
    Working     guesses happen in a minority of steps, more often when the helper
                is far and instability is low, less often a threshold away from
                a blackout; groups can say afterwards when guessing was worth it
    Sessions    3 at dial_settings 4, then 3 at 6, same group. Like P-B before it,
                a price cannot be read without a comparison
    Falsifies   dial_settings, instability_max, instability_clock_penalty_seconds,
                instability_blackout_threshold
    How         the slice, ideally; the trace's guess list is the count. On paper
                it works if a referee enforces walking time by turns
    Result      not yet run

---

## P-1 — Does the mechanism hold bodies apart?

    Question    do two tracks, reading in person and the finale keep four players
                in different rooms, or do they cluster between forced moments?
    Not working the group moves as a block, reading and turning as a crowd, and
                splits only for the finale; OR players find one room from which
                most machines are within lens_read_range_studs, and the map
                collapses to it
    Working     no more than two players in the same room for more than 30 s for
                most of the round; the finale is a scramble that has to be set up
                rather than a formality
    Sessions    3. Group movement is habit-driven, and the first session is
                always people being polite
    Falsifies   room_count, paired_room_distance_min, lens_read_range_studs,
                procedure_tracks, INV_track_alternates, and machine placement
                (mechanics.md §6.1). The block reading means tracks are not
                pulling people apart; the collapsed-map reading means placement
                or range is too generous
    How         the M3 slice. Paper has no walking
    Result      not yet run

---

## P-T — Does the trace teach anything?

    Question    does the re-aimed trace (mechanics.md §7) change what a group does
                next round, and can a child read its headline?
    Not working players skip or talk over it; the same kind of wait (for example
                "step waited for its helper") tops the headline four rounds
                running for the same group; a child cannot say what the headline
                said; adults cannot say what par is
    Working     after a headline about a helper wait, the same helper calls or
                arrives earlier next round; margin against par improves after a
                trace that showed a long wait; players point at the timeline and
                argue about it
    Sessions    4 consecutive rounds with the same group, one of which includes a
                child (share the sitting with P-K)
    Falsifies   post_round_seconds, and the trace's content: if players engage
                with only one of the four items, the rest are noise. T14 (whether
                naming players or steps changes engagement, and whether naming a
                child upsets them)
    How         the M3 slice
    Result      not yet run

---

## P-I — Does degradation read as pressure or as punishment?

    Question    do instability, the clock penalty and blackouts feel like the
                group tightening its own noose, or like the game kicking them
                while they are down - and for a young player, like a scare?
    Not working the first blackout ends the round in practice and the rest is
                ceremonial; OR instability never reaches the first threshold, so
                the mechanism is decorative; OR groups call the dark unfair; OR a
                young player is frightened rather than challenged
    Working     the first blackout changes behaviour - fewer guesses, more waiting
                for helpers; groups describe losses by instability as their own
                doing
    Sessions    3, recording the loss reason every round. If losses by
                instability and by clock are not within roughly 2:1 of each
                other, one loss condition is not real
    Falsifies   instability_max, instability_blackout_threshold,
                blackout_rooms_per_threshold, instability_clock_penalty_seconds,
                blackout_selection, blackout_permanent (T15). The "ceremonial"
                reading implicates blackout_selection's weighting
    Result      not yet run

---

## P-V — How much easier is it on voice?

Re-aimed 2026-09-30. The posture is decided: design for the voiceless floor
(§0d #15). This no longer bears on the genre; it sizes a gap.

    Question    the same instance type, same group, twice: once under strict no
                speech, once on voice. How much does voice help, and where?
    Not working (for T17's purposes) the voice run is won with a margin against
                par so large that the round is a formality; players stop pinging
                and read settings aloud across rooms (a helper can then describe
                a setting instead of pointing, but still has to be at the machine
                to read it)
    Working     the voice run is faster but still loses sometimes; the bottleneck
                stays walking and position, which voice does not repair
    Sessions    2 matched pairs, different instances, same group. Silent run FIRST
                in each pair, or the voice run teaches the instance
    Falsifies   nothing in the standard band. A large gap is the case for T17's
                harder band, and its levers: dial_settings,
                turn_cue_lookahead, actuation_failure_is_diagnostic
    How         paper-runnable, better in the slice
    Result      not yet run

---

## P-N — Is there enough to do at five and six?

Re-aimed 2026-09-30 from "where does the channel become noise". There is no
serial token stream to saturate.

    Question    at n = 5 and 6, with procedure_length 8, does every player still
                have enough to do?
    Not working at n = 6 a player spends more than a third of the round with
                neither their own step nor their partner's live, and nowhere
                useful to be; players drift to the finale and wait
    Working     idle stretches are short and are used for anticipation
                (pre-positioning, early Help calls)
    Sessions    2 each at n = 4, 5, 6. n = 4 is the control, not a formality
    Falsifies   players_max (now a placeholder), procedure_length scaling with n,
                procedure_tracks (3 tracks at n = 6?)
    Result      not yet run

Low priority until lobby fill is a real question, but cheap to ride along with
any session that happens to have five or six people.

---

## Running rules

- **Write the "not working" reading before the session, never after.** A
  protocol with only a success condition confirms whatever happened. Every entry
  above puts it first for that reason.
- **Name the constants a bad reading sends you back to.** Every entry does. An
  observation that changes nothing was not worth making.
- **Record sessions that went nowhere.** Four people who spent the round joking
  and never engaged is data about the mechanic.
- **Count, do not remember.** P-D's conflicts, P-Q's 40%, P-S's sequences,
  P-G's guesses and P-I's loss reasons are all counts. Once the M3 slice exists
  the server logs every one of them for the trace (`mechanics.md` §7), so the
  counting is free. Until then, a tally sheet.
- **Sessions can share a sitting.** P-D, P-Q, P-1 and P-G all want the same
  four people playing normally and differ only in what is counted. P-K and P-T
  share a sitting. P-S rides along with anything, because it is a watch for one
  behaviour. P-V needs its own matched pairs. P-C is the frame the others sit
  inside.
- **Vary the group.** P-Q, P-K and P-S are the most sensitive to who is in the
  room. Each has a "not working" reading that a group of enthusiasts will never
  produce.
- **Children are playtested with a guardian present and consenting, and
  nothing identifying them is recorded here.** Counts and short notes only.
- **The operator runs these, not an agent.** Nothing here is automatable and
  nothing here should be simulated. A simulated playtest is a model of the
  designer's expectations, which is the thing being tested.
