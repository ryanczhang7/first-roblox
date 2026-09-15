# The loop — the seven questions, answered

**Status: the design exists.** Revised 2026-09-15 (second pass) after the
operator resolved T1, T3 and T4 (product-brief §0b amendments 8–10).

Scope of this pass: **the whole game**. The genre is decided — candidate B,
asymmetric-information co-operative — so the five questions can be answered and
the mechanics, roles and constants specified.

| File | What it holds |
|---|---|
| this file | the seven questions, answered; why 4 players; the record of why B was chosen |
| `mechanics.md` | one section per mechanic — inputs, rules, states, edge cases |
| `roles.md` | the lens/key asymmetry: what each player knows, wants, must do |
| `tuning.md` | every constant, with value, label and rationale |
| `playtest.md` | what observation would prove each of these wrong |

**Sections 3 and 4 are the historical record** of why B was chosen and are kept
deliberately. Sections 1 and 2 have been rewritten; their superseded text is in
the appendix, because a decision is only reviewable if the reasoning it replaced
is still readable.

---

## 0. The game in one paragraph

Four players are inside a dark facility that must be brought to a safe state by
executing a **Procedure** — an ordered sequence of operations on machinery —
before a clock expires. No player can see enough to know what the Procedure is,
and no player can operate the machinery they *can* see. The only channel between
them is a fixed wheel of abstract **marks** with no grammar: the vocabulary can
name qualities and sequence, but it cannot bind them to each other or to
anything in the world. Groups that keep playing together invent the binding
themselves. That invention is the game, and it is also the retention thesis.

---

## 1. The seven questions

| # | Question | Answer |
|---|---|---|
| 1 | Core verb | **Signal** — convert one thing you can see into one token someone else can act on |
| 2 | The decision | *Which single fact of the many I can see is the one the group cannot deduce without me?* |
| 3 | Pressure | A clock, plus instability that both shortens the clock and destroys information |
| 4 | Variance | Generated instances; and the conventions a specific group accumulates |
| 5 | Failure cost / lesson | One round; the **post-round trace** names the fact that was never sent |
| 6 | What forces the configuration | Cyclic derangement of lens and key; simultaneous operations; k-essentiality |
| 7 | Why each acts | Per-player non-transferable budget; nobody can act on what they can see |

### 1. Core verb — **signal**

Second to second a player does one of three things, and only one of them is a
choice the game is about:

- **Look** — turn your light onto a panel and read it. Free, continuous, and it
  is where information enters the system.
- **Actuate** — set a machine to a value. Rare, decisive, punished when wrong.
- **Signal** — spend one token from a finite personal budget to put one mark in
  front of everyone else, for a few seconds, and then it is gone.

The verb the game is *about* is **signal**, because it is the only one with a
cost, an opportunity cost, and no correct answer written anywhere. Looking is
free and has a dominant strategy (look at the thing in front of you). Actuating
is determined once you know what to do. Signalling is the whole design surface.

Movement is the substrate, as it was for every candidate, and it is not a verb
any player chooses — but under B it is *constrained* rather than free: see Q6.

### 2. The decision — which fact is load-bearing

When you spend a token you are choosing between every fact currently in your
view, under three kinds of ignorance:

- You do not know what the others can already see.
- You do not know what they have already worked out.
- You do not know what they will still need, because the Procedure's order is
  itself distributed.

It is non-obvious for a reason that can be stated precisely rather than
asserted: **the budget is smaller than the cost of describing your view.** You
cannot dump. You must select. Selecting well means modelling what the group
already knows — and the only evidence about that is the tokens they have spent,
which are themselves selections made under the same ignorance.

That is a real decision, it recurs every fifteen seconds or so, and it has no
dominant option. It is also exactly what `tuning.md: signal_budget_per_player`
regulates, and the reason that constant carries a derived *relation* even though
its absolute value is a placeholder.

### 3. Pressure — the clock, and the dark

Two sources, and the second one is the interesting one.

- **Clock.** `round_seconds`, within pillar A3 #5's 6–10 minutes. In a
  co-operative game a clock is genuine pressure with no turtling failure mode:
  waiting loses for everybody, so nobody's dominant strategy is inaction. This is
  the single thing co-op gets for free that hidden-role did not.
- **Instability.** Every wrong actuation raises instability. Instability
  (a) subtracts from the clock and (b) **turns rooms dark**, permanently removing
  a player's ability to read the panels in them. Information is destroyed by
  failure. Guessing is not merely unrewarded; it is the mechanism by which the
  group loses the ability to stop guessing.

The second one is worth stating as a design property: **the failure state and the
aesthetic are the same system.** A2 #3 and A3 #2 put the entire art budget into
lighting and audio. Under B that budget now does mechanical work rather than
decorating it — which is the specific criticism §5 of the first pass levelled at
candidate B ("the 3D space carries mood only"), and this is the repair.

### 4. Variance — generated instances, and accumulated convention

Three layers, in increasing order of how much retention they carry:

1. **Instance generation.** Layout, which constraints land in which lens, the
   lens/key permutation, Procedure length and shape. A system, not content —
   satisfying A2 #4. `mechanics.md §6` specifies the generator and its invariants.
2. **Difficulty band.** Generator parameters, not more assets.
3. **The group's convention stock.** The vocabulary has no grammar. A group that
   has played thirty rounds together has agreed — without ever being told it
   could — that two marks in immediate succession mean an ordered pair, that
   `AGAIN` after a pause means "I am re-asserting, not repeating", that a
   particular mark has become the group's word for the west stair. None of that
   is authored. It is generated by the players, it is worth more every session,
   and it is worthless to a stranger.

Layer 3 is the answer to A2 #2 (28-day retention, intentional co-play), and it is
the strongest argument for B over every other candidate: **the thing that
accumulates is the group, not the account.** It costs nothing to build, because
it is the absence of a feature — the game never teaches, labels or autocompletes
a convention.

It also carries a risk that must be named rather than admired: a design whose
retention depends on player-invented convention retains groups that invent and
loses groups that do not. `playtest.md: P-C` is the protocol that decides whether
ordinary four-person groups invent anything at all, and it is the single most
important observation in this project.

### 5. Cost of failure, and what it teaches

**Cost:** the round — `round_seconds`, 6–10 minutes — and the session's shared
season progress. Adequate, and per amendment 9 it is shared, so nobody is
individually punished for the group's loss.

**Lesson: the post-round trace.** The first pass's complaint about the
hidden-role shape was that a reveal is a result, not a lesson. The trace is the
repair, and it is a pure function of state:

    the generated instance
      + the signal log (every token, sender, timestamp)
      + the actuation log
      = the first moment at which the group collectively held enough to solve,
        and the fact that was in someone's view and never left it

The post-round screen shows the Procedure that was actually required, aligned
against the signal log, with two things highlighted: **the tokens that carried no
information the group did not already have** (wasted budget) and **the fact
nobody sent**. "The third valve was AMBER. It was in your lens for four minutes."

That is actionable, it is specific to the round, it is computable headlessly, and
it teaches the thing the game is actually about — selection under a budget. It is
specified in `mechanics.md §7`.

### 6. What forces the configuration — three mechanisms, none of them hope

Co-op needs players **dependent**, and dependency between four people in one room
is not dependency. The first pass's sharpest finding was that the brief named no
mechanic that separated players and merely hoped "objectives" would. Under B
there are three, and all three are properties the generator enforces and a test
can check:

1. **Cyclic derangement of lens and key.** Each player has a *lens* (a class of
   information their view renders) and a *key* (a class of actuator only they can
   operate). The permutation binding lenses to keys is a **cyclic derangement** —
   no player can act on what they can see, and the dependency graph is a single
   ring rather than two independent pairs. One generation rule, no art, exactly
   testable. See `roles.md §2`.
2. **k-essentiality.** The generated instance has a unique solution under the
   union of all *n* views and **at least two** solutions under the union of any
   *n−1* views. No player is redundant; no three players can finish without the
   fourth. This is a generator invariant, brute-forceable on the instance sizes
   involved, and `mechanics.md §6.3` specifies it.
3. **Simultaneous operations.** At least one operation per Procedure requires two
   keys turned in two rooms within a short window. Bodies cannot be in one place.

Mechanism 1 forces dependency, 2 forces it to be *everyone's*, 3 forces it to be
spatial. That last one is what keeps the 3D space mechanical.

### 7. Why each player acts rather than defers

Co-op replaces "why does the hidden role act rather than turtle" with a harder
question the brief was right to name: **why does each player act rather than let
the one confident player solve it out loud?** That is the co-op analogue, and it
is the failure mode that kills most co-operative designs — three people watching
one person play.

It is answered structurally, not by exhortation, by six independent devices:

| # | Device | Why it stops quarterbacking |
|---|---|---|
| 1 | Budget is **per player and non-transferable** | the confident player cannot spend your tokens; only you can send your facts |
| 2 | **k-essentiality** | no *n−1* subset determines the answer, so "tell me everything" still leaves them guessing |
| 3 | `signal_budget_per_player` < cost of enumerating your own view | you cannot say everything you know, so three players cannot brief a fourth even by spending everything |
| 4 | **Derangement** | the solver cannot act — they hold the answer and no key |
| 5 | **Ephemeral signals**, no scrollback | one person cannot hold four views in working memory for eight minutes |
| 6 | **Simultaneous operations** | at least one moment per round needs two bodies acting, not one brain |

Devices 1 and 3 are the load-bearing ones and they are both tuning constants;
`tuning.md` records the relation between them. Device 5 is the most likely to be
experienced as frustration rather than as difficulty, and it is open as **T7**.

`playtest.md: P-Q` is the protocol that tests whether these six actually work, and
its "not working" reading is written to catch the polite version of the failure —
three players who *do* act, but only when told to.

---

## 2. Why four players — re-derived under co-operation

The first pass derived the 4-player floor's consequences under hidden-role
**elimination** rules: a 1/3 blind vote, a parity threshold, a round that is
structurally one vote long. **None of that applies.** There is no vote, no
elimination and no faction. That derivation is superseded and kept in the
appendix; here is what replaces it.

Under B, the number of players is the **length of the dependency ring**, and it is
bounded from both sides by things that can be argued rather than asserted.

**Lower bound — why not 3.** Derangements of 3 elements are both 3-cycles, so a
ring exists. But at n=3 each player's lens covers a third of the machinery and
the global-order layer has only three fragments, which two players can usually
brute-force between them; k-essentiality becomes hard for the generator to
satisfy without making individual views trivially small. n=4 is the smallest ring
in which the two-layer puzzle (`mechanics.md §3`) has room. **Derived.**

**Upper bound — channel contention.** Signals are broadcast into one shared,
ephemeral stream. The number of tokens in flight scales with n; a player's
capacity to read and attribute them does not. Above roughly six senders the
stream stops being a channel and becomes noise, and the game's difficulty
migrates from *selection* (interesting) to *keeping up* (not). **Derived, with a
placeholder boundary** — the exact n at which this bites is `players_max`, a
placeholder falsified by `playtest.md: P-N`.

**Therefore the band is 4–6, not A4's "target 8–12, cap 16."** This is a real
finding and it contradicts the brief:

- A4's 8–16 band was derived from hidden-role faction ratios, which no longer
  exist. It should be withdrawn, not scaled.
- A smaller cap makes M6's lobby-fill risk **strictly easier**, which is the same
  direction amendment 1 was already pushing.
- It costs the "big lobby" feel, and it means private servers (A6) are the
  natural venue rather than an upsell — which is arguably better for A2 #2, since
  a private server is where a stable group plays.

Four is therefore not a compromise floor under B. It is close to the ideal.

---

## 3. What the surviving constraints implied — the record of the genre choice

**Historical. Kept because it is the record of why B was chosen.** The candidate
comparison below is what the operator decided from (amendment 8). Nothing in the
second pass contradicts it; §7 of this section notes the one thing that has
sharpened.

These four survive §0b unamended, plus one new one:

| | Constraint | Filter it applies to a genre |
|---|---|---|
| S1 | 28-day retention, intentional co-play (A2 #2) | rewards playing with *the same people*; variance must come from systems |
| S2 | No character art; R15 avatars; hard-surface modular environment; atmosphere from lighting + audio (A2 #3, A3 #2) | **no NPCs with rigs** — this kills every PvE/wave/enemy genre outright |
| S3 | Code-dominant, not content-dominant (A2 #4) | difficulty in state machines and generators, not authored content volume |
| S4 | Server-authoritative, headlessly verifiable (A3 #4, B4, B5) | rules must be functions of state |
| S5 | **Fully playable with zero free-form communication** (amendment 7) | the channel is developer-authored vocabulary over observable world state |

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

### B. Asymmetric-information co-op — the constrained channel *is* the puzzle — **CHOSEN**

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

> **Second-pass note.** Two of these costs resolved better than the first pass
> expected and one resolved worse.
> - *"The 3D space carries mood only"* — **repaired.** Instability turns rooms
>   dark and destroys information (§1.3), and simultaneous operations force bodies
>   apart (§1.6). Lighting is now a mechanic.
> - *"The ladder does not fit"* — **confirmed and accepted** by amendment 9.
> - *"Retention needs puzzle volume"* — **partly dissolved**: the deepest
>   variance layer turned out to be group-invented convention (§1.4), which costs
>   nothing. But the generator is still the hardest system in the project and that
>   estimate stands.
> - **Worse than expected:** out-of-band voice. See §5, T5. This is the one thing
>   in the second pass that bears on the T1 decision itself.

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
core mechanic. This is why we have no character art budget."

The derivation ran backwards. The no-art constraint (A2 #3) yields *"avatars are
the only characters we have"*. It does **not** yield *"identifying players is a
mechanic"*. That second clause was a design commitment presented as a consequence
of a budget decision, and it silently survived amendment 6 because it did not
look like a genre choice.

**Resolved.** Amendment 10 withdraws it. Under B, identifying a player visually
is not a mechanic — but note what replaced it: signals are **attributed to their
sender by name** (`tuning.md: signal_reveals_sender`), so knowing *who* said a
mark is central. The game needs player identity; it does not need visual
recognition of avatars in a dark room. A3 pillar 1 should be rewritten by the
Lead PO to say the first half and not the second.

---

## 5. Open questions for the operator

T1–T4 are resolved. T5–T9 are new, arising from this pass. They are ordered by
how much rests on them, and **T5 is the one that bears on a decision already
made**.

### T5 — out-of-band voice. **Read this one first.**

Four friends on Discord can say "the third valve is amber" in one second. The
vocabulary constraint is a rule of the *game*, not of the *players*, and nothing
can enforce it. For a group on voice, the expressive half of the channel's
lossiness evaporates.

The first pass did not raise this. It should have, and the operator decided T1
without it. That is worth saying plainly.

**It is not fatal, and here is the argument for why.** Spaceteam is played
face-to-face with unlimited speech and is still a good game, because its
bottleneck is *attention and speed*, not vocabulary. The correction it implies is
a design rule rather than a retreat: **the channel must be lossy along an axis
voice cannot repair.** This design has two such axes, and they are independent:

| Axis | Repaired by voice? |
|---|---|
| **Expressive** — no referents, no binding, no grammar | **Yes.** A voice group loses this constraint entirely. |
| **Attentional** — signals are ephemeral, the stream is shared, reading a panel and attending to the stream compete for the same seconds | **No.** Voice is also serial, also ephemeral, and also competes with looking. |

So B survives with the attentional axis carrying more weight than the first pass
assumed. The design consequences are already in this pass: ephemerality, no
scrollback, rate limiting, and a generator that must guarantee a *rate* of
required transfers rather than only a quantity.

**What is genuinely open is the operator's posture**, and it is taste:

- **(a) Design for the voiceless floor.** Tune so a group with no voice can win.
  Voice groups find it easy; offer them a harder band. Cost: the game's marketed
  difficulty is not the difficulty most groups experience.
- **(b) Design for voice.** Assume Discord, lean hard on the attentional axis,
  tune the rate so that speech is *also* too slow. Cost: brutal for the voiceless,
  which contradicts amendment 7's binding rule if taken far enough.
- **(c) Two bands, generator-parameterised.** Most honest, and cheapest under S3
  since it is generator parameters. Cost: splits an already-small matchmaking
  pool, which M6 can least afford.

I have specified (c) provisionally in `tuning.md: difficulty_band`, labelled
**taste-pending**. If the operator picks (a) or (b) the constants move but no
mechanic changes.

### T6 — does a signal broadcast the sender's location?

`tuning.md: signal_reveals_sender_room`. Currently **false**.

- **False** (specified): deixis is entirely absent, "here" is unsayable, and
  location must be established by convention. Maximum puzzle, maximum chance of
  early frustration.
- **True**: a signal carries its room automatically, which gives the language a
  free referent for one dimension. Much gentler, and it makes the map legible.
  Cost: it hands players the single most useful binding for nothing, and the
  invention of spatial convention — probably the most satisfying thing a group
  will do — never happens.

This is the largest single lever on early-session difficulty in the design. It is
taste, and `playtest.md: P-3` reads it.

### T7 — ephemerality: how much memory load is difficulty and how much is exclusion?

`tuning.md: signal_display_seconds`, `signal_log_depth`.

Specified as 6 seconds and no scrollback. That is device 5 of the anti-quarterback
set (§1.7) and part of the voice-proof attentional axis (T5), so weakening it
costs real structure. But memory load is the least inclusive difficulty there is:
it excludes by working memory, it punishes interruption, and it is unpleasant
rather than hard for some players.

Options: a per-player **recall** action that costs one token to re-show the last
three signals (keeps the cost, removes the cliff); a persistent log of only
*your own* sent tokens; or a longer display window. Each is one constant. The
consequences differ and none is obviously right.

### T8 — is the vocabulary a moderation surface?

Not a design question but it lands in my file. Platform finding 1 says a fixed
developer-authored vocabulary is game state and sits outside `TextChatService`.
That reading is sound for *pings*. It is weaker for an **ordered stream of 16
distinct tokens with an arbitrary length**, which a determined group can use as a
cipher. The budget (`signal_budget_per_player`) bounds it hard — 18 tokens per
player per round is not a conversation — and the marks are abstract glyphs with
no natural-language mapping, which makes spelling awkward. **For the Lead PO to
verify against current Community Standards before M3**, not for me to rule on.

### T9 — season rotation of the vocabulary

A season could retire two marks and introduce two others. This deliberately
invalidates part of a group's convention stock and forces rebuilding, which turns
§1.4's layer-3 variance into a recurring event rather than a one-way accumulation.

It is also the most hostile thing in this document: it takes away the thing the
group built. It might be exactly the seasonal hook A5 days 8–28 needs, or it
might be the reason a group stops playing. I have not specified it. It is
recorded so it is decided rather than drifted into.

### Still not mine to answer — for the Lead PO

- **The audience constraint** (§0b: "A2 needs a replacement constraint"). Still
  open, and it now matters *more*, not less: B's difficulty is cognitive and its
  retention thesis assumes groups that will invent conventions over weeks. That is
  a specific kind of player. Rule complexity, session length and T5's posture all
  depend on it.
- **A4's lobby band** should be withdrawn and replaced with 4–6 per §2.
- **A3 pillar 1** should be rewritten per §4.
- **A5/M5** ranked ladder should be withdrawn per amendment 9.
- **M3's "6 humans"** definition of done should become 4, per §2.

---

## Appendix — superseded analysis (first pass, 2026-09-15)

Kept because a revision is only reviewable against what it replaced.

### A1. The five questions, answered "no" against the unamended brief

The first pass found questions 1, 2, 6 and 7 unanswerable and 3, 4, 5 partly
answerable. The reasons were: no objective was named anywhere in the brief; no
evidence mechanism existed; the vote's decision depended on two unspecified
systems; no mechanic separated players; and both the hidden role and the majority
had turtling as a dominant strategy. **All of these were findings about the
hidden-role shape and are resolved or void under B.**

One argument from that pass survives and is worth keeping because it generalises:

> Under a fixed developer-authored vocabulary, *deception costs nothing*. In
> speech, lying is expensive: you improvise under time pressure, stay consistent,
> and control your voice while three people listen for the seam. With a canned
> phrase list, the liar and the truth-teller select from the same dropdown at
> identical cognitive cost, and there is no seam to hear. A channel that makes
> lying free removes the asymmetry hidden-role deduction runs on.

This is why amendment 7 and a hidden-role genre were in tension, and it is part of
why B was chosen. Under B there is nobody to lie to, so it is void as a
constraint — but it remains the correct answer if anyone proposes re-adding a
traitor variant on top of B. **A traitor in a co-op with a canned vocabulary is
free to lie, and should not be added without solving that.**

### A2. The 4-player derivation under elimination rules — **void**

> At 4 players with 1 hidden (the brief's ~25%), under Among Us-lineage
> elimination rules: an uninformed vote convicts the hidden player with
> probability **1/3**; a wrong first vote leaves 3 players, 1 hidden — at or
> adjacent to the parity threshold at which the hidden faction wins in every game
> of this lineage; therefore a 4-player round is, structurally, **one vote long**.
>
> Three repairs existed: raise the floor to 5 or 6; make resolution
> non-eliminating; or change genre so that identity is not what is voted on.

The operator took the third repair. There is no vote, no elimination and no
hidden faction, so none of this arithmetic applies. Replaced by §2 above.

### A3. Why there was no tuning.md

The first pass declined to write `tuning.md`, `mechanics.md` or `roles.md`
because every number the brief offered was withdrawn pending T1 and none could be
re-derived without a mechanic. That was correct then. T1 has landed, and all three
files now exist.

Of the four values that pass listed as withdrawn: round length is re-derived in
`tuning.md: round_seconds`; the lobby band is re-derived in §2 as 4–6; the hidden
faction ratio is void; and lobby/post-round pacing survives as UX timing, now with
`post_round_seconds` raised because the post-round trace (§1.5) needs reading time.
