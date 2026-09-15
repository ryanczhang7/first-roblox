# Mechanics

One section per mechanic: inputs, rules, states, edge cases, and the decision it
produces. Constants appear by **name**; their values, labels and rationale are in
`tuning.md` and nowhere else. If a number appears here it is because it is
structural (a bijection size, a cycle length), not because it is tuned.

Everything below is a function of state. `§9` maps each rule to what a Lune test
can check without a Roblox runtime; if a rule is not in that table it should not
have been specified.

---

## 1. The world

**Inputs:** none — established at round start by the generator (§6).

The facility is `room_count` rooms of modular hard-surface geometry, connected as
a graph. It is dark. Each player carries a directional light; a player sees what
their light is pointed at and little else. There are no NPCs, no enemies and no
combat, per A2 #3 and its anti-goals.

Each room contains zero or more **actuators**. An actuator is a machine with:

| Property | Visible to | Notes |
|---|---|---|
| **tag** — one mark | anyone with light on it | the actuator's name, and the only name it has |
| **key class** — one of `n` classes | anyone with light on it | who may operate it |
| **current setting** — a mark, or unset | anyone with light on it | changes when actuated |
| **required value** — a mark | only the lens that covers its key class | this is the secret |
| **committed** — bool | anyone with light on it | the operation has been performed correctly and in turn |

**States:** `unset → set(mark) → committed`. A committed actuator cannot be
changed. An actuator set to the wrong value, or set out of turn, does not commit
and returns to `unset` after `actuation_reset_seconds`.

**Edge case — an actuator in a blacked-out room.** Its tag and key class become
unreadable (§5). Its required value was never readable there anyway. A player may
still actuate it if they can reach it and already know what it is; blackout
removes information, not access. This is deliberate: the group's memory of a room
is worth something after the lights fail.

**The decision it produces:** none directly. The world is the substrate. It
exists to make *where you are standing* determine *what you can know*, which is
what makes §4's channel necessary.

---

## 2. Look — observation and the lens

**Inputs:** player position, player camera direction.

A player learns a fact when their light falls on a surface carrying it. Two
classes of fact exist, and the distinction is the whole asymmetry:

- **Public facts** — an actuator's tag, key class and current setting. Anyone
  with light on it reads them. These are properties of the world.
- **Lens facts** — an actuator's *required value*. Rendered only for the player
  whose **lens** covers that actuator's key class, and only while they have light
  on it. These are properties of the player.

A lens fact is therefore a **pairing**: *(tag, required value)* — two marks. That
shape is the reason the channel is hard, and §4.4 explains why.

**Rules:**

- A player's lens covers exactly one key class, fixed for the round (`roles.md §2`).
- Lens rendering is server-authoritative and **the required value is never
  replicated to a client that does not hold the lens**, per B4. A client that is
  not the lens-holder must not be able to read it out of its own memory.
- Reading is free, instantaneous, unlimited and untimed. There is no scanning
  minigame. Looking is not where the difficulty lives.

**Edge cases:**

- *Two players in the same room.* Both read the public facts. Only the
  lens-holder sees the lens fact — co-location does not share lenses. This is why
  standing together is not an exploit, merely a waste of one body.
- *A player looks at an actuator whose class their lens covers and which they can
  also operate.* Impossible by construction: the lens/key permutation is a
  derangement (`roles.md §2`). If a future variant breaks the derangement, that
  player becomes self-sufficient for that actuator and k-essentiality fails.

**The decision it produces:** *where to stand.* Standing at an actuator lets you
read it and actuate it; it does not let you read the room your lens-partner needs
you to describe. Movement is the opportunity cost of observation, and §3's
simultaneous operations make it a hard one.

---

## 3. The Procedure — the two-layer puzzle

This is the objective. The first pass's sharpest complaint about the brief was
that no objective was named anywhere in it; this is the repair.

**The Procedure** is an ordered sequence of `procedure_length` operations. Each
operation is *set actuator a to its required value v*, and the sequence must be
performed **in order**. Performing every operation correctly and in order before
the clock expires is the win condition. There is no other win condition.

The Procedure is never known to anyone in full. It is split into two layers whose
information lands in different heads, and the split is what makes the round a
group problem rather than four private ones.

### 3.1 The local layer — what value

Every actuator carries a **tag** (a mark, public) and a **required value** (a
mark, visible only through a lens). The generator's constraints:

- Tags are distinct **within a key class**, so a player can name their dependent's
  actuators unambiguously.
- `required_value ≠ tag` for every actuator — the answer is never written on the
  machine.
- The `procedure_length` required values of the operations *in the Procedure* are
  pairwise distinct and exhaust the mark alphabet, which is why
  `mark_alphabet_size = procedure_length`.

That last constraint has the consequence the whole language leans on:

> **A value-mark uniquely names an operation** — and nothing in the game says so.
> A group discovers that marks have become referents. That discovery is the first
> convention most groups will build, and it costs nothing to support.

**There are more actuators than operations** — `actuator_count =
procedure_length × actuator_redundancy`, so at the default band half of them are
not in the Procedure at all, and a lens does not say which. So a player's lens
shows `pairs_per_lens` pairings of which only some matter, and *which* is
determined by the order layer — which is in other people's heads. This is what
makes a view larger than a contribution, and it is the reason "which fact is
load-bearing" is a question rather than a formality.

The union of all `n` lenses determines every required value. No `n−1` of them do
(§6.3).

### 3.2 The global layer — what order

The generator picks a total order over the `procedure_length` operations and
publishes it to nobody. It distributes **order fragments** — statements of the
form *the operation whose value is `x` precedes the operation whose value is `y`*
— `order_fragments_per_player` to each player, readable from a fixed terminal in
a designated room rather than from a lens.

The cross-cut is the point: an order fragment names operations by **value**, and
the player holding the fragment generally does not know which actuator has that
value — that is somebody else's lens. So the order layer cannot be resolved along
the ring. It requires the whole group.

**States of an operation:** `unknown → value-known → placed (order known) → committed`.
A group does not need to fully order the Procedure before starting; it needs to
know what comes *next*, which is why partial order fragments are playable.

**Edge cases:**

- *Fragments that are individually satisfiable but jointly contradictory.*
  Forbidden by construction — the generator derives fragments from a real total
  order, so the union is always consistent. A group may still *believe*
  contradictory things, which is a different thing and is the game.
- *A group that attempts operation k+1 before k.* Rejected; instability +1; the
  actuator does not commit. This is the main channel through which order errors
  are punished, and it is deliberately as costly as a wrong value.
- *Simultaneous operations.* At least `simultaneous_ops_min` operations are
  flagged **paired**: two actuators, in different rooms, of different key classes,
  which must both be set within `simultaneous_window_seconds` or neither commits
  and instability rises. This is the mechanism that puts bodies in two places
  (loop.md §1.6 device 3).

**The decision it produces:** *act on a belief now, or spend another token
confirming it.* A wrong actuation costs instability, a clock penalty and a room's
lights. A confirmation costs a token from a budget that will not last. Every
operation in the Procedure is that trade made once, under a clock that makes
waiting lose too.

---

## 4. The signal channel — the central mechanic

Read this section before any other. Everything else exists to make this one
matter.

### 4.1 What a signal is

**Inputs:** one token selected from a radial wheel of `vocabulary_size` marks.

Pressing a token spends one unit of the sender's budget and broadcasts, to every
living player:

    (sender_id, token, server_timestamp)

That is the entire message format. It is the whole language.

**Rules:**

- The budget is `signal_budget_per_player`, **per player, per round, and
  non-transferable.** Nobody can send on your behalf.
- `signal_reserve` tokens of that budget are locked until
  `reserve_unlock_seconds_remaining` seconds are left on the clock, so no player
  can be rendered completely mute by their own early enthusiasm.
- Every token costs `signal_cost` = 1. No token costs more than any other.
- A sender may send at most one token per `signal_rate_limit_seconds`. This is
  simultaneously a game rule (it makes the stream readable) and a trust-boundary
  requirement (B4: every remote is rate-limited).
- A received token is displayed for `signal_display_seconds` and is then **gone**.
  `signal_log_depth` is 0: there is no scrollback, no history, no transcript.
- Signals are attributed to their sender by name (`signal_reveals_sender`). They
  do **not** carry the sender's room (`signal_reveals_sender_room` = false, open
  as T6).
- The server records every signal for the post-round trace (§7). Players do not
  see that record until the round is over.

**States:** a player is `has_budget → reserve_only → mute`. A mute player can still
look, move and actuate; they cannot originate. The reserve exists so that
`mute` before the endgame is a real failure of husbandry rather than a common
accident.

### 4.2 What the vocabulary can express

`vocabulary_size` tokens in four groups:

| Group | Count | Tokens | Literal meaning |
|---|---|---|---|
| **Marks** | `mark_alphabet_size` | abstract glyphs | the qualities tags and values take. No referent, no noun, no verb. |
| **Ordinals** | 3 | `FIRST`, `BEFORE`, `AFTER` | sequence relations, unbound to anything |
| **Polarity** | 2 | `YES`, `NO` | assertion and denial, unattached to any proposition |
| **Meta** | 3 | `AGAIN`, `WAIT`, `GO` | re-assert my last token; hold; act now |

A mark can be uttered. A relation can be uttered. **Nothing can be said about
anything.**

### 4.3 What the vocabulary deliberately cannot express

This list is the design, not a list of missing features:

- **Binding.** There is no way to attach a mark to an actuator, a room, a player
  or another mark. `AMBER TEAL` is two marks. Whether that is one pairing or two
  unrelated facts, and in which direction, is not in the language.
- **Deixis.** No `HERE`, no `THAT ONE`, no room names, no player names as
  addressees. You cannot point.
- **Scope for polarity.** `NO` denies nothing in particular. It denies whatever
  the listener currently believes is under discussion, which may not be what the
  sender believes is under discussion.
- **Quantity.** There are no numbers.
- **Time beyond order.** `BEFORE` and `AFTER` relate two things the language
  cannot identify.
- **Addressing.** Everything is broadcast. You cannot speak to one player.

### 4.4 Why the gap is the puzzle and not a frustration

The distinction is not rhetorical and it can be stated as a rule the generator
must satisfy.

> **The Expressibility Rule.** For every fact the round requires to be transferred
> between two players, at least one encoding of that fact exists within the
> vocabulary and within the budget. No required fact is *unsendable*; some
> required facts are unsendable in **one token**.

A design where the necessary thing cannot be said at all produces frustration and
players who blame the game. A design where the necessary thing can be said only
by inventing a convention produces players who blame themselves and ask to go
again — which is precisely the working/not-working split in `playtest.md: P-3`.

The gap is bridged by exactly one resource the language does have and never
mentions: **adjacency in the stream**. Two tokens from the same sender in quick
succession are two events with an order, and order is a free bit the language did
not intend to carry. A group that agrees "tag first, then value" has manufactured
a grammar out of timing. A group that has not will send `AMBER TEAL`, have it read
backwards, actuate wrongly, lose a room's lights, and learn.

This is the moment the whole design is built around. Three properties protect it:

1. **The game never teaches it.** No tutorial, no tooltip, no autocomplete, no UI
   affordance that pairs two tokens into a phrase. The wheel sends one token.
2. **The game never rewards a canonical convention.** There is no "correct"
   grammar the design has in mind. Tag-then-value and value-then-tag are equally
   workable; what matters is that four people use the same one.
3. **Failure is legible.** A convention mismatch produces a *specific*, visible
   wrong actuation, not a vague loss — and the post-round trace (§7) shows the
   pairing that was sent and the pairing that was needed, side by side.

**The second lossy axis.** Expressive lossiness is defeated by a group on
Discord (loop.md T5). The channel is therefore lossy along a second axis that
voice does not repair: signals are **ephemeral**, the stream is **shared and
serial**, and attending to it competes for the same seconds as pointing your light
at a panel. `signal_display_seconds`, `signal_log_depth` and
`signal_rate_limit_seconds` are the constants that carry this, and the generator
must satisfy a *rate* requirement (§6.3) and not merely a quantity one.

### 4.5 The decision it produces

Stated once, since it is the answer to the second of the five questions:

> Which single fact of the many I can see is the one the group cannot deduce
> without me — and is it worth more than the token it costs?

You are choosing under three ignorances: what others can see, what they have
already inferred, and what the order layer will turn out to require. Your only
evidence about the first two is the tokens they have spent, which were selected
under the same ignorance. There is no dominant option, the choice recurs
throughout the round, and the budget guarantees you cannot dodge it by saying
everything.

---

## 5. Actuation, instability and the dark

**Inputs:** a player at an actuator whose key class matches their key, selecting a
mark.

**Rules:**

- Actuation is server-validated: sender identity, key class match, proximity,
  phase legality, rate limit (B4).
- The server evaluates: is this actuator the *next* operation in the Procedure,
  and is the selected mark its required value?
  - **Both true** → commit. The actuator locks. A light in that room comes up and
    a confirming tone plays. Progress is public and unambiguous.
  - **Either false** → reject. `instability += 1`. The actuator returns to `unset`
    after `actuation_reset_seconds`. A failure tone plays, audible facility-wide.
- **The rejection does not say which was wrong.** Wrong value and wrong turn
  produce an identical response. That ambiguity is information the group must
  resolve through the channel, and it is the single cheapest difficulty lever in
  the design; it is `actuation_failure_is_diagnostic`, a taste constant.

**Instability effects** (thresholds in `tuning.md`):

| Effect | Rule |
|---|---|
| Clock | each point of instability removes `instability_clock_penalty_seconds` from the remaining clock, immediately |
| Blackout | at each multiple of `instability_blackout_threshold`, `blackout_rooms_per_threshold` rooms go permanently dark; tags and key classes in them become unreadable |
| Loss | at `instability_max`, the round ends in failure regardless of the clock |

Blackout room selection is server-side and **weighted toward rooms with
uncommitted operations**, so degradation bites. It is not random cruelty; it is
the mechanism that makes early guessing a compounding mistake.

**States:** the round is `running → won → lost(clock) → lost(instability)`.

**Edge cases:**

- *Two players actuate the correct next operation simultaneously.* Impossible by
  key class — an operation has exactly one eligible key-holder — except for paired
  operations, where both actuations are required. Resolution is server-ordered by
  receipt timestamp.
- *A paired operation where the second actuation arrives after the window.* Both
  reject, instability +1 (not +2 — one operation, one penalty).
- *The last uncommitted operation's actuator is in a blacked-out room, and its
  key-holder has disconnected.* See §8. The round can become unwinnable; the
  design's position is that it should **end immediately with a stated reason**
  rather than run the clock out on a group that cannot win.

**The decision it produces:** *how much confirmation is an actuation worth.*
Instability is the price of acting on a belief you have not checked, and the
blackout rule makes that price rise as you pay it.

---

## 6. The generator

The hardest system in the project, and the one that carries A2 #4 (difficulty in
systems, not asset volume) and A2 #2 (28-day retention without content).

### 6.1 What it produces

An **instance**:

| Component | Shape |
|---|---|
| layout | `room_count` rooms and their connectivity |
| actuator placement | actuators to rooms |
| tag assignment | marks to actuators, distinct within each key class |
| **value assignment** | a required value per actuator, never equal to its own tag; the values of operations *in* the Procedure exhaust the mark alphabet |
| **the Procedure** | which `procedure_length` of the `actuator_count` actuators are in it |
| **total order** | a permutation of the operations |
| **σ** | a cyclic derangement over players: lens/key binding (`roles.md §2`) |
| lens split | which required-value pairings land in which lens |
| fragment split | which order fragments land with which player |
| paired ops | which operations are simultaneous, and their rooms |

Every component is combinatorial and tiny. The whole instance is a few hundred
bytes. Generation is seeded, so an instance is reproducible from a seed — which
is what makes the generator testable and a bad round reportable.

### 6.2 Structural invariants

These are hard constraints; the generator rejects and resamples.

1. No actuator's required value equals its own tag (`INV_no_self_value`).
2. Tags distinct within a key class; the required values of the operations in the
   Procedure pairwise distinct and exhausting the mark alphabet. (This is what
   makes a value-mark a referent — §3.1.)
3. `σ` is a **single n-cycle**, not merely a derangement. Two 2-cycles would split
   four players into two independent pairs who never need each other.
4. Every paired operation's two actuators are in different rooms with different
   key classes, and the rooms are at least `paired_room_distance_min` apart in the
   connectivity graph.
5. Every player holds at least one pairing and at least one order fragment. A
   player with nothing to say has nothing to do.
6. No room is reachable only through a room that starts dark.

### 6.3 Information invariants

These are the ones that make the design work, and they are the reason this
section exists rather than "generate a puzzle".

**I1 — k-essentiality.** The union of all `n` lenses and all fragments admits
**exactly one** consistent Procedure. The union of any `n−1` of them admits **at
least two**. Brute-forceable at these sizes; a Lune test can verify it
exhaustively for a generated instance.

> Worked, for the order layer, where it is nearly free: a total order over
> `procedure_length` operations needs at least `procedure_length − 1` covering
> relations. Removing any one player's `order_fragments_per_player` fragments from
> the pool leaves fewer than that, so the order is underdetermined and at least two
> Procedures remain consistent. The generator only has to check that the *full*
> pool determines it uniquely.
>
> Worked, for the value layer, where it must be constructed: with `n−1` lenses the
> union fixes every required value except those of one key class. The missing ones
> are constrained only by `INV_no_self_value` and by the requirement that the
> in-Procedure values exhaust the alphabet. The generator must verify that more
> than one assignment survives those constraints; if the leftover set is forced, the
> instance is rejected and resampled. At these sizes the check is exhaustive.

**I2 — the centralisation bound.** Let `V` = `view_enumeration_tokens` be what it
costs one player to say everything they know literally, and `M` =
`cooperative_minimum_tokens` what the canonical cooperative protocol the generator
constructs costs that player. Then, per player:

    M · protocol_slack  ≤  signal_budget_per_player  <  V

The left inequality makes the instance solvable with room to be wrong. The right
one says **you cannot say everything you know** — which is simultaneously what
forces selection (loop.md §1.2) and what makes quarterbacking not fit in the
channel, since three players spending everything still cannot brief a fourth.

The gap between `M` and `V` is not an accident of arithmetic; it is produced by
`WAIT`, `NO` and `GO`. Relaying an order fragment costs three tokens; **acting on
one** — gating the group at the moment it is about to go out of turn — costs one,
and does not require the fragment to be understood by anyone else. Distributed
control is cheaper than centralised knowledge, and that is why the meta tokens are
not filler. It is also why `actuator_redundancy` exists: without facts that turn
out not to matter, `V` and `M` converge and the bound has nothing to stand on.

**I3 — the rate bound.** The canonical protocol's `M` transfers must be
distributable across the round such that no player needs to send faster than
`signal_rate_limit_seconds` allows, with at least `rate_headroom` slack. This is
what stops the generator producing an instance that is solvable in principle and
impossible in eight minutes, and it is the invariant that makes the attentional
axis (§4.4) load-bearing rather than decorative.

### 6.4 What varies, and what does not

Varies per instance: everything in §6.1. Varies per **band**
(`difficulty_band`, taste-pending per loop.md T5): `procedure_length`,
`mark_alphabet_size`, `pairs_per_lens`, `signal_budget_per_player`,
`instability_max`, whether tags and values may collide, and whether
`actuation_failure_is_diagnostic`.

Does **not** vary and is not authored: any grammar, any convention, any hint.

---

## 7. The post-round trace

**Inputs:** the instance, the full signal log, the full actuation log, the outcome.

The answer to question 5 — what failure teaches. A reveal is a result; this is a
lesson, and it is a pure function of state.

The trace screen shows the Procedure as it actually was, in order, and against it:

1. **The critical moment.** The earliest timestamp at which the union of what had
   been *sent* was sufficient to determine the next operation. If the group acted
   wrongly after that moment, the failure was in reading the channel. If before,
   it was in filling it.
2. **The fact nobody sent.** Any pairing or fragment that was in a player's lens
   for the whole round and never entered the stream, named to that player:
   *"The valve tagged AMBER needed TEAL. It was in your lens for 4:12."*
3. **Wasted tokens.** Every signal that carried no information the group did not
   already hold — a re-assertion of something already sent, or a token whose every
   consistent reading was already determined. This is the group's budget
   efficiency, and it is the number that improves as a group learns.
4. **The convention mismatch, when one occurred.** Where a pairing was sent in one
   direction and acted on in the other, both readings are shown side by side. This
   is how a group discovers it has two grammars.

**Rules:** the trace is shown for `post_round_seconds`, to everybody, win or
lose. It names players, because attribution is what makes it actionable, and
because there is no betrayal in this game so attribution is not an accusation.

**Edge case:** on a win with zero wasted tokens and no mismatch, the trace shows
the group's transfer count against `M` (§6.3) — the theoretical minimum. That is
the skill ceiling, and it is the only leaderboard this design needs.

**The decision it produces:** none in-round. It shapes the next one, which is the
point.

---

## 8. Edge cases across mechanics

| Case | Rule |
|---|---|
| **Disconnect** | the ring breaks. The leaver's key class transfers to their ring-*predecessor* — the player who could already see those values, so the instance stays solvable and gets easier. Their lens and remaining budget are lost. `disconnect_grace_seconds` before reassignment, in case they rejoin. |
| **Below `min_players_to_continue`** | the round ends immediately as a no-contest. No loss is recorded and season progress is unaffected: the group did not fail, the lobby did. |
| **Every player mute** (budget exhausted) | the round continues. It is usually lost, and that is a legitimate and instructive way to lose. The reserve (§4.1) makes it rare before the endgame. |
| **The round becomes unwinnable** (remaining clock < minimum time to execute remaining operations, or a required key-holder is gone with no predecessor) | end immediately with a stated reason, then show the trace. Never run out a clock on a group that cannot win. |
| **Instability and clock hit their limits in the same tick** | instability resolves first; the recorded loss reason is instability. Deterministic ordering matters because the trace reports the reason. |
| **A player actuates the correct operation by accident, having been told nothing** | it commits. Guessing correctly is allowed and costs nothing; the design punishes guessing *wrongly*, which is the same thing said in the direction that can be tuned. |
| **Two players send the same token in the same second** | both appear, attributed. The stream is not deduplicated — who said it is part of what was said. |
| **Rejoin after disconnect** | within the grace window, the player resumes with their lens and remaining budget. After it, they spectate until the next round; their key class has already moved. |
| **All operations committed with the clock still running** | immediate win. No bonus round, no overtime. The remaining seconds are reported in the trace as the group's margin. |

---

## 9. What a headless test can check

Per the standing preference for rules that are functions of state. Everything in
the left column runs under Lune with no Roblox runtime.

| Mechanic | Headlessly verifiable | Needs a human |
|---|---|---|
| §1 world | actuator state machine; commit is terminal; reset timing | whether a dark room is atmospheric or just annoying |
| §2 lens | lens facts never appear in a non-holder's replicated state (B4) | whether reading a panel in the dark is pleasant |
| §3 Procedure | order enforcement; paired-window resolution; every edge case in §8 | whether the two-layer split is legible |
| §4 channel | budget arithmetic; reserve unlock; rate limit; ephemerality timing; server log completeness | **everything that matters** — see `playtest.md` |
| §5 instability | thresholds, clock penalties, blackout selection weighting, loss ordering | whether degradation feels like pressure or like punishment |
| §6 generator | **all of §6.2 and §6.3, exhaustively, per seed** | whether the instances are interesting |
| §7 trace | the critical moment, the unsent fact, wasted-token accounting — all computable from logs | whether anyone reads it |
| §8 edge cases | every row | — |

The right-hand column is what `playtest.md` exists for. Note that the mechanic
with the most headless coverage (§6) and the mechanic with the least (§4) are
respectively the hardest to build and the one the game lives or dies by. That
asymmetry is worth knowing before M3 rather than during it.
