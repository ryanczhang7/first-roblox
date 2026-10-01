# The loop — the seven questions, answered

**Status: the design exists, and its central mechanic was replaced on
2026-09-30.** Third pass, after product-brief §0d: #14 (audience is everyone,
children included), #15 (design for the voiceless floor), #18
(`round_seconds` = 420), and above all **#19** (the signal channel must be a
Roblox-compliant preset system for all ages, without age-gating).

The earlier passes are kept, not deleted:

| Pass | Date | What it decided | Where it is now |
|---|---|---|---|
| first | 2026-09-15 | the genre was open; five candidates compared | §3 (the record of the genre choice) and appendix A1–A3 |
| second | 2026-09-15 | candidate B; a 16-mark wheel with no grammar; "the group invents a language" | **superseded by §0d #19.** Summarised in appendix A4 |
| third | 2026-09-30 | this file. B survives; the invented language does not | §0–§2 (with §1a), §5 |

| File | What it holds |
|---|---|
| this file | the seven questions; floor and ceiling; why 4 players; the record of why B was chosen |
| `mechanics.md` | one section per mechanic. **§4 (the channel) is replaced**; §3.2 (order) is replaced; the rest is revised |
| `roles.md` | the ring (unchanged), what each seat knows (revised) |
| `tuning.md` | every constant, labelled; §9 is the list of what was superseded |
| `playtest.md` | the protocol, re-aimed, with a child-comprehension protocol added |

---

## 0. The game in one paragraph

Four players are inside a dim facility that must be brought to a safe state by
running a **Procedure**: two short tracks of machine settings, done in order,
ending in one two-handed finale, before a clock runs out. **You can see what your
partner's machines need, but you cannot turn them. Your machines can only be
turned by you, and only your helper can see what they need.** Nobody can tell
anybody anything in words. You **show**: stand at your partner's machine, shine
your light on the right setting, and ping it. A small wheel of presets ("Help",
"On my way", "Ready", "Go") says what you *intend*, never what you *know*. The
facts only ever travel by pointing at the world, so the game is about being in
the right place at the right time.

### What changed from the second pass, in one table

| Second pass (2026-09-15) | Third pass (2026-09-30) | Why |
|---|---|---|
| Core verb **signal**: spend a token to put an abstract mark in a shared stream | Core verb **show**: point at a world object you can read and your partner cannot | §0d #19: a preset system "must not gain meaning when combined, repeated, or sequenced". The old verb was built on exactly that |
| The difficulty was *expressive*: the vocabulary cannot bind a mark to anything | The difficulty is *spatial and temporal*: the only binding is being there | Pointing binds for free, so the puzzle has to move to where bodies are |
| Retention came from a group's **invented conventions** | Retention comes from generated variety plus a group's **choreography**: who goes where, and when | Invented meaning over presets is the thing the guideline forbids. Choreography is strategy, not a code (§1.4) |
| 16 tokens, 1.5 s rate limit, 12-token budget | 10 presets plus 1 ping, 10 s preset rate limit, no budget | the guideline's own numbers: 12 or fewer, 10 s per send |
| One sequence, order read from fragments and relayed | Two tracks, order seen privately by each key-holder, never relayed | a fact that needs a *sequence* of references to transfer cannot be carried compliantly (`mechanics.md` §3.2) |

---

## 1. The seven questions

| # | Question | Answer | Source |
|---|---|---|---|
| 1 | Core verb | **Show**: point your light at the one setting your partner cannot see, and ping it | brief §0d #19(a) names the ingredients ("pointing at world objects"); the mechanic is this pass's |
| 2 | The decision | *Two things need me now, in two places. Which do I serve first, and do I wait for help or guess?* | derived from the ring plus two live tracks |
| 3 | Pressure | A 420 s clock, plus instability that shortens the clock and darkens rooms | §0d #18; the second pass's instability survives |
| 4 | Variance | Generated instances; a group's choreography | the generator survives; the convention layer does not (**finding**, §1.4) |
| 5 | Failure cost / lesson | One round. The trace shows the group's timeline against the best route | re-aimed from the second pass |
| 6 | What forces the configuration | The ring; reading only in person; a finale that needs four bodies in two rooms | the ring survives; the other two are new or strengthened |
| 7 | Why each acts | Your lens is the only source of your partner's settings, and your key is the only way yours turn. Nobody can brief anybody | re-derived |

**All seven are answerable from what I have been given.** Questions 3, 5, 6 and 7
come from mechanisms that survive the redesign. Questions 1 and 2 come from the
ingredients §0d #19(a) names, worked into a mechanic here. Question 4 is
answerable, but its answer is a **finding against amendment 8's original
rationale**, and the operator should read §1.4 before M3 is planned.

### 1. Core verb — **show**

Second to second a player does one of four things:

- **Move**: walk between rooms. Cheap, and constant. Now it is the binding
  resource.
- **Look**: turn your light onto a machine. If it is one of your partner's
  machines and you are close enough, you see which of its settings is the right
  one. Nobody else does.
- **Show**: ping one thing, for example that setting, that machine or that
  doorway. A marker in your colour appears there for everyone, for a while.
- **Turn**: set one of your own machines. Rare and decisive, and punished when
  wrong.

The verb the game is *about* is **show**, because it is the only moment where a
fact crosses from one head to another, and it can only happen in person. The
choices around it (where to be so that you can show, and when) are what the
rest of the design regulates.

The preset wheel is **not** a verb the game is about. It carries intent ("Help",
"On my way"), never facts. That is a compliance requirement (§0d #19) and it is
also a design rule: `mechanics.md` §4.3.

### 2. The decision — which call do I answer first, and do I wait?

Every player is two things at once: a **helper** (the only one who can read their
partner's machines) and a **turner** (the only one who can operate their own).
The Procedure has two tracks, so two machines are often live at once. The
decision that recurs all round is:

> *My machine is live on one side of the facility, and my partner's machine is
> live on the other. Somebody needs me in two places. Where do I go first? And
> when my helper is far away, do I wait for them or guess?*

Why it is non-obvious, stated rather than asserted:

- **It has no dominant answer.** Going to your partner first unblocks them but
  leaves your own step waiting. Calling your helper first unblocks you but pulls
  *them* away from their own partner. The right answer depends on distances and
  on where the other two players are, and that changes every round.
- **It is made under partial information.** You see your own next step before it
  goes live (`turn_cue_lookahead`). You do not see anyone else's. What they need
  reaches you only as world state (a lit lamp on a machine) or as a preset with a
  position ("Help", shown where the sender stands). The public progress bar
  (T10 (c)) tells you how far the *group* has got, as one count, and nothing
  about which step is next or whose it is.
- **The guess is a real option.** A dial has `dial_settings` positions. Guessing
  a 4-setting dial costs 1.5 wrong turns on average, and each wrong turn costs
  clock and edges the facility toward a blackout. Waiting 30 s for a helper
  costs clock too. `tuning.md: dial_settings` exists to keep that trade close.

The second pass's decision was *which fact to spend a token on*. That was
selection under a vocabulary budget, and it was the heart of the old design. It
is gone, because pointing at a thing you can see costs nothing to express.
Selection now happens over **bodies and seconds** instead of tokens.

### 3. Pressure — the clock, and the dark

Unchanged in kind, re-tuned in number.

- **Clock.** `round_seconds` = 420 (§0d #18). Waiting loses for everybody, so no
  player's dominant strategy is inaction.
- **Instability.** Every wrong turn raises instability, which (a) takes seconds
  off the clock and (b) at thresholds **darkens a room**. In a dark room a helper
  can no longer read their partner's machines. So failure destroys the one
  channel facts travel by, and guessing becomes the way a group loses the ability
  to stop guessing.

The failure state and the aesthetic are still the same system, which is the
second pass's best property, and it survives. For an all-ages audience, whether
the dark reads as spooky or as calm is a tone question (**T15**), not a mechanic.

### 4. Variance — generated instances, and choreography

Three layers:

1. **Instance generation.** Layout, machine placement, the ring, which machines
   are in the Procedure, the order of each track, the finale's two machines. A
   system, not content (A2 #4). Specified in `mechanics.md` §6.
2. **Difficulty.** Generator parameters. Per §0d #15 there is one band, tuned
   for the voiceless floor. A harder band was optional, and the operator chose
   none for v1 (**T17**, 2026-09-30).
3. **Choreography.** A group that plays together learns *who goes where*: "the
   runner takes the far room", "whoever finishes first goes to the finale
   early", "call Help before your step is live, not after". That is strategy,
   and it accumulates.

> **Finding. The second pass's retention thesis does not survive #19, and this
> is worth the operator reading before M3.**
>
> The second pass rested its strongest argument for B on layer 3 as it was then:
> a group invents a *language* ("two marks in succession mean an ordered pair";
> "this mark is our word for the west stair"). That is precisely "slang that
> could carry hidden or evolving meanings", built by "combining, repeating or
> sequencing" presets. The guideline forbids it, and §0d #19 chose compliance.
>
> Choreography is what replaces it. It is **compliant**, because nothing in it
> gives a preset a meaning it did not have. It is **weaker**, because strategy is
> more transferable to strangers than a private language, so it binds a specific
> group less tightly. That weakens A2 #2 (co-play with the same people) and, with
> it, part of the case the second pass made for B over candidate D.
>
> It does not reopen the genre on its own: B's asymmetric-information co-op
> shape survives #19 whole (§0d #19, consequence 3). But amendment 8 was decided
> partly on a thesis that no longer holds, and that should be a known fact rather
> than a buried one. **T16** framed it, and the operator answered (a) on
> 2026-09-30: choreography plus generated variety is the retention layer.
> `playtest.md: P-C` is re-aimed to measure
> whether choreography accumulates at all.

### 5. Cost of failure, and what it teaches

**Cost:** the round (420 s) and the session's shared season progress. Per
amendment 9 it is shared, so nobody is individually punished.

**Lesson: the post-round trace**, re-aimed. It is still a pure function of state:

    the generated instance
      + the ping log and the preset log (sender, target or intent, position, time)
      + the actuation log
      + position samples
      = for every step: when it went live, when its helper first pinged it,
        when it was turned, and who was waiting for whom

It shows the group's timeline against the **best route**: the canonical schedule
the generator already computes to prove the instance is solvable in time
(`mechanics.md` §6.3, `INV_traversal`). The headline is one sentence a child can
read ("Step 3 waited 40 seconds for its helper") and the detail underneath is for
the group that wants it. Whether the trace names *players* is a real question for
an all-ages game (**T14**).

### 6. What forces the configuration — three mechanisms, none of them hope

Co-op needs players **dependent**, and **apart**.

1. **The ring: a cyclic derangement of lens and key.** Unchanged, and already
   built (SEAT-001). No player can act on what they can see, and the dependency
   is one ring, not two pairs. `roles.md` §2.
2. **Reading only in person.** A helper sees the right setting only with their
   light on the machine, within `lens_read_range_studs`. There is no channel that
   carries a setting from somewhere else. This is **stronger** than the second
   pass's version: the old design let a helper describe a machine from anywhere
   with tokens. Now every fact has to be delivered on site.
3. **The finale.** The last step of each track is a single paired operation: two
   machines in two rooms, at least `paired_room_distance_min` apart, of two key
   classes that are **not neighbours on the ring**. At n = 4 that needs four
   distinct bodies (two turners, two helpers) in two rooms at once.

Mechanism 1 makes everyone dependent, 2 makes the dependency physical, and 3
makes it simultaneous. Movement is no longer the substrate of the game. It is the
game.

### 7. Why each player acts rather than defers

The co-op form of question 7: why does each player act rather than let one
confident player run the round?

| # | Device | Why it stops quarterbacking |
|---|---|---|
| 1 | **Knowledge is local.** Settings are readable only by your partner's helper, only in person | a would-be planner cannot know anyone else's settings. There is nothing to centralise |
| 2 | **Keys are non-transferable** (the derangement) | the knower cannot act. Knowing is not doing |
| 3 | **No channel carries a fact except a ping on site** | a briefing is impossible, not merely expensive. You cannot relay a setting you are not standing at |
| 4 | **Turn cues are private; the only public view of the order is a count** | nobody sees the whole order, so nobody can plan the whole round. The progress bar (T10 (c), `mechanics.md` §3.2) says how many steps are done, never which is next or whose, so it gives a planner a clock, not a plan |
| 5 | **Presets are broadcast and unaddressed** | there is no preset for "you, go there". You cannot give one player an order |
| 6 | **The finale needs four bodies** | at least one moment per round needs everyone acting, not one brain |

Devices 1 and 3 used to be *tuning constants* (the budget had to be smaller than
the cost of describing your view). They are now **structural**: no constant can
be mis-set to reintroduce a briefing channel. That is a real gain from the
redesign. The second pass's device 5 (ephemeral signals and no scrollback) is
**retired**. It was the least inclusive difficulty in the design, and the spatial
devices do its job without it.

`playtest.md: P-Q` tests whether these work. Its "not working" reading still
names the polite failure: three players who act, but only when told to. The
remaining risk is a planner who **pings doorways** to steer people. Device 5
limits it: a ping is not addressed, and only one of yours exists at a time.

---

## 1a. Floor and ceiling — where "rewards good thinking" lives

§0d #14: *nothing too complex for a child, but it still rewards good play and
good thinking.* That constraint pulls against memory load and cognitive depth,
so the design puts **nothing the floor needs into memory or reading**, and puts
the depth into **planning**, which is optional at the floor and unbounded above
it.

**The floor: what a first-time 7-year-old needs to know.** Three sentences, all
of them shown by the world rather than explained:

1. *When your screen says your machine is ready, go to it.* (a private turn cue,
   with a direction arrow)
2. *When you see your partner's machine light up, or they call "Help", go and
   shine your light on it. One setting glows for you. Ping it.*
3. *When you see your helper's ping on your machine, turn it to that.*

No reading is required: the preset wheel is icon plus word. Nothing has to be
remembered, because a ping persists (`ping_display_seconds`) and the turn cue
stays up until the step is done. The progress bar shows the group getting
closer to done, which a child reads without being told. There is no budget to
manage. A child who only
ever follows sentences 1 to 3 is a *useful* player, and the finale is
choreographed by the world: a partner lamp shows when the other machine's turner
is in position.

**The ceiling: where thinking wins, and nothing here is required.**

| Skill | What a thoughtful group does | Why it pays |
|---|---|---|
| **Routing** | answers calls in the order that minimises everyone's waiting, not their own | per-step waits in the trace are the dominant cost of a round |
| **Anticipation** | walks to your next machine *before* it goes live, calls Help early, pre-positions for the finale | the turn-cue lookahead exists to reward exactly this |
| **Guess or wait** | guesses a 4-setting dial when the helper is two rooms away and instability is low, and waits when a blackout is one error off | `dial_settings` and `instability_blackout_threshold` make this close, deliberately |
| **Reading the world** | infers who is where from lit lamps, committed lights and preset positions, without being told | nothing announces it. It is there to be read |
| **Blackout memory** | remembers a setting seen before the room went dark | optional memory that pays, never required memory that excludes |
| **Choreography** | a group's standing plan (§1.4) | makes the group fast in a way a stranger group is not |

The trace's "your time against the best route" is the visible skill ceiling, and
it is the only leaderboard this design needs (amendment 9).

**The rule that keeps the floor low.** Each of the six ceiling skills must be
*additive*: a group that does none of them can still win at the standard band.
`INV_traversal` enforces it, because the canonical schedule the generator
verifies uses no anticipation, no guessing and no presets.

---

## 2. Why four players — re-derived under the redesign

The second pass's bounds were derived from the token stream. The lower bound
mostly survives, and the upper bound's argument is void.

**Lower bound — why not 3. Derived, and now sharper.** In a 3-cycle every pair of
key classes is adjacent on the ring. So the finale's two turners always include
one who is also the other's helper, and "four distinct bodies in two rooms at
once" cannot be satisfied. At n = 4 the opposite seats on the ring are
non-adjacent, and the finale needs everybody. **n = 4 is the smallest ring in
which the finale forces all players apart.** A 3-player round after a
disconnect still works, because a ping persists: the helper pings one finale
machine and then walks to the other. It is structurally thinner, as before.

**Upper bound — void, value retained.** The second pass derived `players_max`
= 6 from channel contention (too many senders in one serial token stream). There
is no token stream. The value stands as the Lead PO's ratified cap (§0c R1), and
the pressure that now bounds it is different: with `procedure_length` 8 at
n = 6, each player has about 1.3 steps, and idle time rises. `players_max` is
re-labelled a **placeholder** in `tuning.md`, and `playtest.md: P-N` is re-aimed
at idle time rather than stream noise.

The 4–6 band therefore survives and still contradicts A4's 8–16, for a
different reason.

---

## 3. What the surviving constraints implied — the record of the genre choice

**Historical. Kept because it is the record of why B was chosen.** The candidate
comparison below is what the operator decided from (amendment 8). The note at the
end of B records what the third pass changed.

These four survive §0b unamended, plus one new one:

| | Constraint | Filter it applies to a genre |
|---|---|---|
| S1 | 28-day retention, intentional co-play (A2 #2) | rewards playing with *the same people*; variance must come from systems |
| S2 | No character art; R15 avatars; hard-surface modular environment; atmosphere from lighting + audio (A2 #3, A3 #2) | **no NPCs with rigs** — this kills every PvE/wave/enemy genre outright |
| S3 | Code-dominant, not content-dominant (A2 #4) | difficulty in state machines and generators, not authored content volume |
| S4 | Server-authoritative, headlessly verifiable (A3 #4, B4, B5) | rules must be functions of state |
| S5 | **Fully playable with zero free-form communication** (amendment 7) | the channel is developer-authored vocabulary over observable world state |

Added 2026-09-30:

| | Constraint | Filter |
|---|---|---|
| S6 | **Everyone, children included** (§0d #14) | the floor needs no reading, no memory, no rules explanation |
| S7 | **Compliant preset system, all ages, no age-gating** (§0d #19) | 12 or fewer presets; 10 s per send; no meaning from sequence; no encoding |

**What the filter rejected, with reason** — derived, not opinion:

- *Wave/PvE/tower-defence*: enemies need rigs and animation. Violates S2 and the
  A2 anti-goal on custom humanoids. Rejected.
- *Building/creative*: is content, not systems. Violates S3. Rejected.
- *Racing/parkour/obby*: passes every filter, but fails S1 — you race strangers
  as happily as friends, so it carries no co-play thesis. Admissible, weak.

**What the filter admitted.** Five shapes.

### A. Hidden role, binding claims — the brief's shape, repaired

Structured vocabulary, but every claim is recorded server-side as a commitment
the world can later contradict.

- **Keeps**: everything already reasoned in Parts A–C; the vote; the ladder.
- **Costs**: the one-vote problem at 4 players; the vocabulary itself is authored
  content, in mild tension with S3.
- **Verifiability**: excellent.

### B. Asymmetric-information co-op — **CHOSEN**

All players on one team; information is split so no one player can act alone
(Keep Talking / Spaceteam / Hanabi lineage). The lossy vocabulary stops being a
handicap and becomes the difficulty.

- **Keeps**: S5 becomes a feature rather than a workaround; strongest S1 fit —
  co-op with a hard channel is a game you need *specific* people for; no
  betrayal, so nobody leaves angry.
- **Costs**: no deduction drama; 28-day retention needs puzzle volume, which is
  content unless generated procedurally (solvable, but the generator becomes the
  hardest system in the project); the competitive ladder in A5/M5 does not fit.
- **Verifiability**: excellent, and a generator is testable headlessly.

> **Second-pass note (2026-09-15).** "The 3D space carries mood only" was
> repaired by instability and blackouts. "The ladder does not fit" was accepted
> by amendment 9. "Retention needs puzzle volume" was partly dissolved by
> group-invented convention. Out-of-band voice was worse than expected (T5).

> **Third-pass note (2026-09-30).** §0d #19 removes "the lossy vocabulary *is* the
> difficulty". B's shape (asymmetric information, co-operative, nobody can act
> alone) survives whole, and the 3D space now does *more* work than before,
> because facts travel only by being there. But the second-pass note's
> "partly dissolved by group-invented convention" is **withdrawn**: that
> convention is the forbidden kind (§1.4). The S1 fit is weaker than the
> comparison below assumed. The operator decided B with the stronger version in
> view, so this was recorded as **T16**. **Answered (a) by the operator,
> 2026-09-30**: B stands, with choreography as its retention layer.

### C. Observable-world forensics — the world testifies, nobody claims

Player actions leave traces in world state; the round is about reading traces and
controlling which of your own you leave.

- **Keeps**: S5 trivially; S2 natively; S3; the deduction *feeling* without
  deduction's dependence on rhetoric.
- **Costs**: less social than A; "recognising who is who" needs an explicit
  mechanic (T3); genuinely novel, so no lineage to borrow tuning from.
- **Verifiability**: excellent.

### D. Open asymmetric pursuit — roles public (heist / hunt / extraction)

- **Keeps**: S5 trivially; works at exactly 4; high variance from opponent
  behaviour; hard-surface environment is native to heist.
- **Costs**: abandons the deduction pillar; crowded category on Roblox; S1 needs
  the ladder to do all the retention work.
- **Verifiability**: good.

### E. Simultaneous commitment — a board-game shape rendered in 3D

- **Keeps**: S5 natively; perfect S4; works at exactly 4; bluffing survives.
- **Costs**: barely uses the 3D space or the avatar, discarding pillar A3 #1 and
  most of the argument for A3 #2.
- **Verifiability**: best on the list.

---

## 4. A laundering defect in the brief itself — **resolved by amendment 10**

**Historical. Kept because it is the record of a finding the operator acted on.**

A3 pillar 1 stated: "The avatar is the character. Recognising who is who is a
core mechanic. This is why we have no character art budget." The no-art
constraint yields *"avatars are the only characters we have"*; it does not yield
*"identifying players is a mechanic"*. Amendment 10 and §0c R3 withdrew the
second clause.

Third-pass note: identity is still carried by **attribution**, now by colour on
pings and by name on presets (`tuning.md: ping_reveals_sender`,
`preset_reveals_sender`). It still needs no art.

---

## 5. Open questions for the operator

### Closed since the second pass

| # | Question | Disposition | By |
|---|---|---|---|
| T5 | posture toward out-of-band voice | **(a) design for the voiceless floor.** A harder band is optional (T17) | operator, §0d #15 |
| T6 | does a signal reveal its sender's room? | **Superseded, and transformed.** See below | this pass, from §0d #19 |
| T7 | memory load: recall action? | **Superseded.** See below | this pass, from §0d #19 and #14 |
| T8 | is the vocabulary a moderation surface? | **Yes, as specified.** It did not comply. Redesigned | Lead PO check, operator §0d #19 |
| T9 | seasonal vocabulary rotation | **Superseded.** There is no invented vocabulary to disrupt. Rotating preset wording would change nothing a group built | this pass |
| amendment 12 | 60 + 480 > 8 min | `round_seconds` = 420 | operator, §0d #18 |
| A2 audience | — | everyone, children included | operator, §0d #14 |

**T6 (#16, "no, a signal does not reveal the sender's room"): superseded, and the
answer flips for presets. The operator should acknowledge this.** #16 tuned a
channel whose facts travelled in tokens, where hiding the sender's room was what
made "here" unsayable and spatial convention necessary. Under the redesign:

- a **ping** is positional by nature: it sits on the thing it points at. The
  question does not arise.
- a **preset** carries intent, not facts. The guideline requires that each preset
  "stand alone and be complete". "Help" with no position is not complete,
  because it forces a follow-up ("where?") that the channel cannot carry. So a
  preset **shows the sender's position** (`preset_reveals_sender_position` =
  true), and that is **derived from compliance**, not chosen.

What #16 protected (the invention of spatial convention) is exactly what #19
removed. So the decision has nothing left to decide. It is recorded as
superseded, not reversed.

**T7 (#17, "recall: spend one token to re-show the last three signals"):
superseded.** Recall assumed two things that no longer exist: a token budget to
spend, and an ephemeral stream of *facts* that punished a look away. Now:

- facts travel as pings, which **persist** (`ping_display_seconds`) and sit in the
  world where they point, and your helper's current ping is also shown on your
  HUD. There is nothing fact-bearing to recall.
- presets carry no facts, so missing one costs nothing but a little timing.
  They expire quickly, as the guideline prefers.

What #17 was protecting (the least inclusive difficulty in the design, which
excluded by working memory) is now protected **structurally**: the floor has no
memory load (§1a). `signal_display_seconds` and `signal_log_depth` are
superseded (`tuning.md` §9). No recall constant is specified.

### Answered — new in this pass

The third pass raised T10–T19 as taste questions and left each at a provisional
value. **The operator answered all of them on 2026-09-30**: *"T16 a, T10 c, rest
default"* (ryanczhang7, relayed by the coordinator). "Default" means the
provisional option below. In `tuning.md` every affected label is now
**taste (operator, 2026-09-30)**.

| # | Question | Answer | Differs from provisional? | Recorded by |
|---|---|---|---|---|
| T16 | Is B still the game? | **(a)** accept choreography plus generated variety as the retention layer | no | ryanczhang7, 2026-09-30 |
| T10 | Who sees the order? | **(c)** private turn cues **plus a public progress bar** | **yes**: the provisional was (a). Applied in `mechanics.md` §3.2 | ryanczhang7, 2026-09-30 |
| T11 | Ping budget? | **(a)** none; rate limit only | no | ryanczhang7, 2026-09-30 |
| T12 | Preset words | the provisional list of 10 | no | ryanczhang7, 2026-09-30 |
| T13 | Does a failed turn say why? | **(a)** yes | no | ryanczhang7, 2026-09-30 |
| T14 | Does the trace name players? | **(a)** steps only | no | ryanczhang7, 2026-09-30 |
| T15 | The dark, for all ages | blackout is **permanent**. **The tone stays open**, shared with the Lead Designer (M4) | no | ryanczhang7, 2026-09-30 |
| T17 | Harder band in v1? | **no**, one band | no | ryanczhang7, 2026-09-30 |
| T18 | Win-rate targets | **0.45** for regular groups, **0.6** for a first session | no | ryanczhang7, 2026-09-30 |
| T19 | Youngest player the floor is for | **7** | no | ryanczhang7, 2026-09-30 |
| T20 | Limit setting-pings to live machines? | **(a)** no: pings may target any setting in range | no. Raised later the same day by the Lead PO's CA-1 decision, and answered separately | ryanczhang7, 2026-09-30 |

The options are kept below as the record of what was chosen between.

### 5a. Taste questions, in order of how much rests on them — answered 2026-09-30

**T16 — Is B still the operator's game, given that its retention thesis changed?**
*(bears on amendment 8)*
- **(a) Yes: accept choreography plus generated variety as the retention
  engine.** Costs: A2 #2 (same-group co-play) is served less distinctively than
  amendment 8 was told. `playtest.md: P-C` then decides whether choreography is
  enough.
- **(b) Yes, and add a retention layer that is not language**, for example
  persistent facility state per private server, or a season of hand-tuned
  layouts. Costs: content (A2 #4 tension), and M5 scope.
- **(c) Re-open the genre comparison against S6 and S7.** Costs: M3 slips.
  Candidate D (open asymmetric pursuit) and E (simultaneous commitment) were
  both S5-native and gain relatively.
- Provisional: (a). Nothing in `mechanics.md` depends on the answer unless (c).
- **Answered: (a)**, ryanczhang7, 2026-09-30. `playtest.md: P-C` is now the
  protocol that tells the operator whether this answer holds up.

**T10 — Who sees the order?**
- **(a) Private turn cues** (provisional): each turner sees only their own live
  step and their own next one. Feels like being called on. It is the strongest
  anti-quarterback device (§1.7 #4), and it makes "Help" the natural first
  preset. Costs: the least legible for a group, and a first-round group may not
  realise there are two tracks.
- **(b) A public board** in a hub room shows both tracks' next steps. Feels like
  a shared plan. It is the most legible and the gentlest for children. Costs: it
  hands a planner the whole round (P-Q risk), and the hub room becomes a place
  everyone returns to, which fights §1.6.
- **(c) Private cues plus a public progress bar** (steps done out of 8, no
  identities). Costs: little. It is a middle point, not a third design.
- **Answered: (c)**, ryanczhang7, 2026-09-30. The bar is specified in
  `mechanics.md` §3.2 so that it cannot drift into (b): it shows one number,
  steps committed out of `procedure_length`, and never which step is next, which
  track, which machine, which room or whose.

**T11 — Do pings have a budget?**
- **(a) No budget** (provisional); the rate limit only. Feels generous and is
  kindest to children. Costs: no "is this worth it" moment, since selection lives
  in bodies and seconds instead (§1.2).
- **(b) A per-round budget**, for example 12 pings. Feels tactical, and brings
  back a legible scarcity ("I have 3 left"). Costs: a second resource for a child
  to manage, and "mute" becomes possible again.
- **Answered: (a)**, ryanczhang7, 2026-09-30.

**T12 — The preset list.** Provisional: `Ready`, `Wait`, `Go`, `Help`,
`On my way`, `Follow me`, `Got it`, `Thanks`, `Nice one`, `Well played`. That is
10, plus the ping, making 11 of the 12 the guideline allows *per universe*.
Options: this list; a smaller list (drop the social three and leave room for
future modes); or swap wording. The **count ceiling and the rule that no preset
names a fact are derived** (`mechanics.md` §4.3). The words are taste.
**Answered: the provisional list of 10**, ryanczhang7, 2026-09-30.

**T13 — Should a failed turn say why?** `actuation_failure_is_diagnostic`.
- **(a) Yes** (provisional, for §0d #14): "wrong setting" and "not yet" look
  different. Feels fair and is the most learnable for a child. Costs: removes an
  ambiguity that thoughtful groups enjoyed resolving.
- **(b) No** (the second pass's choice): identical failure. Feels harder and
  more mysterious. Costs: a young player may never learn why they failed.
- **Answered: (a)**, ryanczhang7, 2026-09-30.

**T14 — Does the trace name players?**
- **(a) Name steps, not players** (provisional): "Step 3 waited 40 s for its
  helper". Costs: less actionable for adults.
- **(b) Name players**, as the second pass did ("attribution is not accusation").
  Costs: for children, being named as the reason the group lost may be exactly an
  accusation.
- **(c) Name players only for good things** ("fastest help: Sam"). Costs: a
  trace that praises and never blames may teach less.
- **Answered: (a)**, ryanczhang7, 2026-09-30.

**T15 — The dark, for all ages.** Is a blacked-out room permanent (the
provisional choice, and the second pass's) or does it recover after some time?
And is the tone spooky or calm? Permanent darkness is the sharpest consequence
in the design, and it is also the most frightening thing in it. Costs: recovery
weakens "guessing destroys your ability to stop guessing" (§1.3). The tone is
shared with the Lead Designer (M4).
**Answered: permanent**, ryanczhang7, 2026-09-30. **The tone is still open**, and
is shared with the Lead Designer for M4.

**T17 — Build a harder band in v1?** §0d #15 makes it optional. Provisional:
**no, one band**. That keeps the matchmaking pool whole (M6) and costs voice
groups a game that is easy for them. If yes, the levers are all generator
parameters: `dial_settings`, `turn_cue_lookahead`, `actuation_failure_is_diagnostic`,
`procedure_length`.
**Answered: no harder band in v1**, ryanczhang7, 2026-09-30.

**T18 — How often should an ordinary group win?** `win_rate_target`. The second
pass set 0.45 for groups that had played together, so that a win is an
achievement. For an all-ages audience, a first-session group of strangers
including a child is a different population. Options: keep 0.45 for regular
groups, with a separate first-session target (provisional 0.6); a single higher
target; or keep 0.45 everywhere. Costs: higher targets flatten the ceiling.
**Answered: 0.45 regular, 0.6 first session**, ryanczhang7, 2026-09-30.

**T19 — The youngest player the floor is designed for.** §0d #14 says children,
not which. The child-comprehension protocol (`playtest.md: P-K`) needs an age to
recruit against. Options: 6, 7 or 9 and up. Provisional: **7**, which is the age
at which icon-plus-word presets and arrow cues are a reasonable expectation,
and below Roblox's under-9 band so the no-chat case is covered. This is
product scope as much as taste, so it is the operator's.
**Answered: 7**, ryanczhang7, 2026-09-30.

**T20 — Limit setting-pings to live machines?** *(new, 2026-09-30; answered the same day)*
`ping_settings_live_only`. Raised by the Lead PO's CA-1 decision: whether a
ping counts as a preset cannot be confirmed, so the rate is already 10 s (the
stricter reading). The remaining risk is a sequence of setting-pings used as a
slow code.
- **(a) No, pings may target any setting in range** (provisional). Keeps early
  pinging: a helper can visit their partner's upcoming machine and ping it
  before it goes live, which is the anticipation skill at the ceiling (§1a).
  Costs: the cipher risk stays open, though a 10 s rate, one active ping per
  player and 4-setting dials make any code extremely slow.
- **(b) Yes, only on live machines.** Closes most of the cipher risk,
  because setting-pings then only happen when they are directly useful.
  Costs: early pinging goes, the helper must be present when the step is live,
  and routing gets less forgiving. Children lose nothing at the floor, because
  the floor pings live machines anyway.
- **Answered: (a)**, ryanczhang7, 2026-09-30. `ping_settings_live_only` stays
  false. `playtest.md: P-S` watches for the behaviour this guards against, and
  a confirmed "not working" there reopens T20.

### 5b. Open — raised by M3 planning, 2026-09-30

**T21 — How is the round clock shown?** `tuning.md: hud_round_clock_form`,
**taste-pending**. That the clock is perceivable is derived (pressure you cannot
perceive is not pressure, §3); its form is not. Whatever is chosen, the clock
never combines with the progress bar into a pace or forecast (`mechanics.md`
§3.3), and instability is shown as pips with the blackout thresholds marked
(derived, not part of this question).
- **(a) A numeric mm:ss countdown, always visible**, each penalty flashing −20
  (provisional). Most legible: a group can reason "90 s, two steps, one of them
  far", which is the ceiling skill of pacing. Costs: the likeliest to make a
  7-year-old panic, and a number invites adults to plan the whole round against
  it.
- **(b) Shown only in the last 60 s**, with an ambient cue before that. Calm for
  most of the round and urgent at the end. Costs: pacing across the middle of the
  round becomes guesswork, and the −20 penalty is invisible until late, which
  weakens what a wrong turn teaches (T13's reason).
- **(c) Ambient only, no number**: the facility's hum rises and its lights
  shift as time runs down. The most atmospheric and the gentlest. Costs: the
  least learnable, and "we lost to the clock" arrives with no warning a child
  can read.
- The Lead Designer is designing the HUD in parallel and should build (a) until
  this is answered. `playtest.md: P-H` is the observation that informs it.

### Still not mine to answer — for the Lead PO

- **Compliance assumptions** CA-2 to CA-8 in `mechanics.md` §4.6. They are
  readings of a published guideline and need verifying, not designing. **CA-1**
  (is a ping a preset?) was found unconfirmable on 2026-09-30, and the Lead PO
  took the stricter reading on rate: `ping_rate_limit_seconds` = 10. CA-3 is
  supported by the guideline's own allowed examples. CA-6 now includes the
  reported `TextChatService` system-message route for engineering to confirm.
- ~~**Two red tests on the day `tuning.md` lands**~~ **Closed** by ROUND-006
  (DONE 2026-09-30, PR #41): `Tuning.luau` at 420 / 60, ROUND-002 amendment A-1,
  and `RateLimitSpec` re-pointed at the preset and ping rows.
- **Where the channel's send limiter is consumed** (`tuning.md:
  channel_limiter_consumed_by`, G9). The design rule is settled: a ping or preset
  the server refuses is not a send and does not start the 10 s cooldown. The net
  wrapper consumes its rate stage before the handler validates a target, so
  honouring the rule is an architecture change, and it is yours.
- **`/plan-product` must be re-run for M3.** The central mechanic changed, and
  `architecture.md` §0's M3 list (signal channel, budget, reserve, ephemerality,
  order fragments, I1–I3) describes a design that no longer exists.
- **A5 days 2–7 re-derivation** (§0c R4) is still open and still yours.

---

## Appendix — superseded analysis

Kept because a revision is only reviewable against what it replaced.
The verbatim text of each superseded pass is in git history (the second pass is
as of commit `38dc58a`).

### A1. The five questions, answered "no" against the unamended brief (first pass)

The first pass found questions 1, 2, 6 and 7 unanswerable and 3, 4, 5 partly
answerable, all as findings about the hidden-role shape, and all resolved or
void under B.

One argument survives and generalises:

> Under a fixed developer-authored vocabulary, *deception costs nothing*. With a
> canned phrase list, the liar and the truth-teller select from the same
> dropdown at identical cognitive cost, and there is no seam to hear.

**A traitor in a co-op with a canned vocabulary is free to lie, and should not
be added without solving that.** This is still true under the preset system, and
more so. A traitor could also *ping* a wrong setting, which would be
indistinguishable from an honest ping.

### A2. The 4-player derivation under elimination rules — **void**

At 4 players with 1 hidden player, an uninformed vote convicts with probability
1/3 and a wrong first vote reaches parity, so a round is one vote long. The
operator removed the vote, elimination and the faction (amendment 8).

### A3. Why there was no tuning.md (first pass)

Correct at the time: every number was withdrawn pending T1.

### A4. The second pass — **superseded 2026-09-30 by brief §0d #19**

Summarised. The verbatim text is at `38dc58a`.

| Question | Second-pass answer | Status |
|---|---|---|
| Core verb | **Signal**: spend one token from a finite budget to put one abstract mark (of 16) in front of everyone for 6 s | **Superseded.** A mark whose meaning a group discovers is the forbidden "evolving meaning" |
| Decision | which single fact of the many I can see is the one the group cannot deduce without me? (selection under a budget smaller than your view) | **Superseded.** Pointing costs nothing to express, so selection moved to bodies and seconds |
| Pressure | clock (480) + instability and blackout | **Kept**; clock now 420 |
| Variance | generated instances + difficulty band + **the group's invented conventions** (the retention thesis) | **Partly superseded.** The convention layer is forbidden. See §1.4's finding |
| Failure | trace: the fact nobody sent; wasted tokens; convention mismatch | **Re-aimed** to timelines and waits |
| Configuration | derangement; k-essentiality; simultaneous ops | **Kept**, with reading in person added and the finale sharpened |
| Why act | six devices, two of them budget constants, one of them ephemerality | **Re-derived**. Devices are now structural, and ephemerality is retired |

The second pass's §2 derivations: the lower bound ("the two-layer puzzle has
room at 4") is replaced by the finale argument; the upper bound ("channel
contention") is void.

The second pass's T5 argument about axes of lossiness is also worth keeping in
summary. It said the channel must be lossy along an axis voice cannot repair,
and that the *attentional* axis (ephemeral, serial, competing with looking) was
that axis. Under the redesign the axis voice cannot repair is **spatial**: a
helper still has to be standing at the machine to read it, and a turner at
theirs to turn it. Voice lets a helper describe a setting instead of pinging it,
and lets the group announce turn cues. Per §0d #15 that advantage is accepted.
