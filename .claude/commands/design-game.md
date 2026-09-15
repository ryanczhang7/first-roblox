---
description: Turn a game's intent into falsifiable design - the core verb, the decision space, the tuning constants and the playtest protocol
argument-hint: [mechanic, question, or 'genre' to work the shape itself]
---

Delegate to the **game-designer** subagent. Scope: $ARGUMENTS (default: the
whole game — start from the core loop).

Read `docs/wiki/product-brief.md` first. If it does not exist, stop and tell the
user to run `/create-product`.

This command is **idempotent**. If `docs/wiki/game/` already exists, diff
against it: keep what still holds, revise what the brief's amendments have
changed, and mark superseded decisions rather than silently deleting them — a
design decision that was reversed is more useful than one that vanished.

## First, establish whether the design exists

Load the `game-design` skill and answer its five questions — core verb, the
decision, the pressure, the variance, the cost of failure — plus the two
multiplayer questions where they apply.

**If any of them cannot be answered from the brief, that is the result.** Say
which, say what the brief offers instead, and stop. Do not specify the tuning of
a mechanic nobody has defined; that is the most expensive way to be wrong, and a
brief carrying a genre and a loop usually cannot answer three of the five.

## Then produce, in this order

1. **`docs/wiki/game/loop.md`** — the five questions, answered.
2. **`docs/wiki/game/mechanics.md`** — one section per mechanic: inputs, rules,
   states, edge cases, and the decision each produces.
3. **`docs/wiki/game/roles.md`** — for asymmetric games: what each role knows,
   what it wants, and why it must act rather than turtle.
4. **`docs/wiki/game/tuning.md`** — every constant, with value, label and
   rationale.
5. **`docs/wiki/game/playtest.md`** — the protocol, with the "not working"
   reading written before the "working" one.

## Label every number

Each constant is **derived**, **taste**, or **placeholder**, and a placeholder
names the observation that would replace it. Never present one as another, and
never launder taste as derivation — "four players implies one hidden role" is a
choice about exposure, not arithmetic.

## Do not answer the taste questions

Where a decision is genuinely a matter of taste, frame it: the options, what
each would feel like, what it costs elsewhere. Put it to the user, wait, and
record the answer they give with their name on it. An open question is a known
unknown; an invented answer is a placeholder that nobody knows is one.

Collect these and ask them together at the end rather than blocking on each in
turn — do everything that does not depend on the answers first.

## Boundaries

Write only `docs/wiki/game/**`. No source, no tests, no config — including the
tuning-constants module, which this command **specifies** and the Feature
Developer implements in GREEN.

Finally, report: which of the five questions the brief could answer, the open
taste questions, and — if the game shape itself changed — tell the user to
re-run `/plan-product`, because the architecture and the backlog follow from
the mechanics.
