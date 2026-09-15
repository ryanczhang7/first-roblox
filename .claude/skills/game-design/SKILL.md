---
name: game-design
description: How the Game Designer turns design intent into falsifiable specification - the five questions that decide whether a design exists yet, the derived/taste/placeholder discipline for tuning constants, and the playtest protocol that stands in for the gate no tool can provide. Use when choosing or revising a game's shape, specifying a mechanic, writing a story's game-design notes, or judging whether a design is concrete enough to build.
---

# Design decisions that survive the handoff

A game design decision is real when someone with no memory of the conversation
can build it, a test can check it, and a playtest can prove it wrong. That is
the bar every file in `docs/wiki/game/` has to clear.

The failure mode this skill exists to prevent is not a bad design. It is a
*fluent* one: a document that reads well, specifies nothing, and gets built
anyway because nobody could point at the sentence that was wrong.

## Does the design exist yet?

Answer these five before specifying anything. A brief with a genre, a loop and a
milestone plan usually cannot answer three of them, and that is the finding.

1. **What is the core verb?** What does a player *do*, second to second? Not a
   category list — "objectives, movement, evidence" is not a verb. If you cannot
   name the action, there is nothing for a map, a UI or a test to be about.
2. **What is the decision?** For the central mechanic: what is the player
   choosing between, what do they know when they choose, and what makes it
   non-obvious? A choice with a dominant option is not a decision, it is a
   delay.
3. **What creates pressure?** Why not play slowly and safely? Time, scarcity,
   opposition, or an opportunity that decays. Without one, optimal play is
   cautious play, and cautious play is boring to do and to watch.
4. **What varies between sessions?** Repeat play is usually the retention
   thesis. If the map, the roles and the objectives are identical every round,
   name what is not — or say plainly that the game is single-session.
5. **What does failure cost, and what does it teach?** A failure that teaches
   nothing produces frustration; one that costs nothing produces indifference.

For multiplayer, two more:

6. **What forces the configuration the game needs?** Social deduction needs
   players apart; co-op needs them dependent; a duel needs them in contact. Name
   the mechanic that *produces* that, rather than hoping players arrange
   themselves.
7. **Why does each role act rather than turtle?** Any role whose best play is to
   do nothing is a design defect, and it is usually the hidden or asymmetric
   role that has it.

## Derived, taste, or placeholder

Every number in a design carries exactly one of these labels, and the label is
part of the record:

| Label | Means | Changed by |
|---|---|---|
| **derived** | follows from a constraint or another number — state the derivation | changing the thing it follows from |
| **taste** | could legitimately be otherwise; the operator chose it | the operator |
| **placeholder** | a guess, present so the thing can be built at all | the playtest that falsifies it |

A placeholder must name the observation that would replace it. "Round length:
420s (placeholder — replace when three consecutive playtests end with more than
90s of dead time before the vote)" is a placeholder. "Round length: 420s" is a
number that will be load-bearing within a week and unexamined within a month.

This is the game-design analogue of the `UNVERIFIED` convention in
`stack-profiles`: a guess labelled as a guess is useful, and a guess presented as
fact poisons everything downstream.

**Never launder taste as derivation.** Writing "a 4-player lobby implies one
hidden player" as though it followed from arithmetic hides a real choice — one
in four is a decision about how exposed the hidden role should feel, and someone
should make it deliberately.

## What gets recorded

| File | Contents |
|---|---|
| `docs/wiki/game/loop.md` | the five questions, answered. The core verb, the decision, the pressure, the variance, the cost of failure |
| `docs/wiki/game/mechanics.md` | one section per mechanic: inputs, rules, states, edge cases, and the decision it produces |
| `docs/wiki/game/tuning.md` | every constant, with value, label (derived/taste/placeholder) and rationale |
| `docs/wiki/game/roles.md` | asymmetric roles: what each knows, what each wants, why each must act |
| `docs/wiki/game/playtest.md` | the protocol — see below |

`tuning.md` is the **specification** of the constants. The module that
implements them is source, written by the Feature Developer in GREEN. That split
is deliberate — see `rules.md` — and it has one failure mode worth stating: the
two can drift. The mitigation is that any story changing a tuning value names
the constant and both values in its `## Game design` section, so the drift is
visible in the diff rather than discovered in a playtest.

## Game design notes on a story

Short and specific, in a `## Game design` section:

- which mechanic this story implements, and the section of `mechanics.md` it
  comes from
- which constants it introduces or changes, with values and labels
- **what makes this criterion interesting** — the decision it protects. A test
  asserting a vote is tallied is correct; a test asserting a vote is refused
  after the phase closed is the game
- any edge case the rules produce that the story must handle: ties, a lone
  survivor, a disconnect mid-vote, everyone choosing the same target

If an acceptance criterion encodes a mechanic that cannot produce an interesting
decision, say so before RED. That is the cheapest moment to find it.

## The playtest protocol

No gate judges fun, and none ever will. The compensating practice is a written
protocol, and without it M3 and M4 resolve on whoever spoke last.

One entry per open question:

    ## Do players separate on their own?
    Question    does the objective layout actually pull a 4-player group apart?
    Working     no more than two players in the same room for >30s, most of the round
    Not working players move as a block; the hidden role never gets an opening
    Sessions    3 — group behaviour is habit-driven and one session is noise
    Falsifies   tuning.md: objective_spread, objective_count

Rules that keep it honest:

- **Write the "not working" reading first.** A protocol with only a success
  condition confirms whatever happened.
- **Name the constants a bad reading would send you back to.** An observation
  that changes nothing was not worth making.
- **Say how many sessions.** Group dynamics are habit-driven; one session of
  four people is an anecdote.
- **Record what actually happened**, including the sessions that went nowhere.
  A protocol that only records confirmations is a diary.

## What not to do

- **Do not balance before there is something to balance.** Tuning a mechanic
  nobody has played is arithmetic, not design.
- **Do not design content where the constraint says systems.** If the brief says
  difficulty lives in systems rather than asset volume, a design that needs
  forty hand-authored objectives has failed the constraint regardless of how
  good it is.
- **Do not specify a mechanic whose interesting case cannot be tested
  headlessly.** Prefer rules that are functions of state — that is what this
  harness can actually verify, and it is most of a game's logic if you let it
  be.
- **Do not answer a taste question because the document has a gap in it.** Frame
  it, give the operator the options and their consequences, and leave it open.
  An open question is a known unknown; an invented answer is not.
