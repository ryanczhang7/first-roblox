# Roles

Co-operative does not mean symmetric. Every player has the same verbs — look,
signal, actuate — and none of them has the same **position** in the information
structure. A role here is not a class, a loadout or an unlock. It is a seat in a
ring, assigned per round by the generator, and the seat determines who you must
talk to and who must talk to you.

Constants are named, not valued; see `tuning.md`.

---

## 1. Why a co-op game has roles at all

Three things must be true at once, and one mechanism produces all three.

- **Nobody can act alone.** If any player can both see what is required and do it,
  that player is a solo game with three spectators.
- **Nobody is redundant.** If any three players can finish without the fourth,
  the fourth is a spectator by a slower route.
- **Nobody can be replaced by a spokesperson.** If one player can absorb the other
  three and direct them, the game has one player and three input devices.

The mechanism is a **cyclic derangement of lens and key**. It is one line of
generation logic, requires no art, produces all three properties, and is exactly
checkable by a test.

---

## 2. The ring

Each player `p` is dealt two things for the round:

| | Name | What it is |
|---|---|---|
| **key** | `k(p)` | the class of actuators `p` — and only `p` — may operate |
| **lens** | `λ(p)` | the class of actuators whose **required values** `p` — and only `p` — can read |

The binding is a permutation `σ` over the players, and the generator constrains it
to be a **single n-cycle** (`mechanics.md §6.2` invariant 3):

    λ(p) = k(σ(p))          σ(p) ≠ p, and σ is one cycle, not two

Two consequences, both structural:

- **You cannot act on what you can see.** `σ` has no fixed points. Every required
  value you can read belongs to an actuator you cannot touch.
- **The dependency graph is one ring, not two pairs.** A derangement of four
  players could also be two disjoint swaps, which would produce two independent
  two-player games sharing a map. The cycle constraint forbids it.

For four players the ring reads:

    P1 ──sees the values for──▶ P2 ──▶ P3 ──▶ P4 ──▶ P1

Two terms used throughout:

- your **supplier** is your ring-predecessor: the one player who can see what your
  actuators need.
- your **dependent** is your ring-successor: the one player whose actuators only
  you can see.

There are six possible cyclic derangements of four players and the generator
picks one per round, so the ring's shape is itself variance — you do not develop
a fixed relationship with one person.

---

## 3. What each seat knows, wants and must do

Every seat is structurally identical; what differs is who is on either side of
you and which fragments you were dealt. So this is one description, not four.

### What you know

| Source | Content | Shared with |
|---|---|---|
| **Your lens** | `pairs_per_lens` pairings *(tag → required value)* for your **dependent's** actuators | nobody |
| **Your fragments** | `order_fragments_per_player` precedence statements over operations, named by value | nobody |
| **Public world** | tags, key classes and current settings of every actuator you have light on | anyone in the room |
| **The stream** | every token anyone has sent in the last `signal_display_seconds`, attributed | everyone, briefly |

Note what you do **not** know: the required values for your own actuators, the
full order, what any other player can see, and what any other player currently
believes.

### What you want

The same thing everyone wants — the Procedure completed before the clock. There
is no private win condition, no traitor, no scoring against each other
(amendment 9). But the *local* obligations are asymmetric and they are what you
act on minute to minute:

1. **Get your dependent right.** Only you can. Every wrong actuation by your
   dependent is, in the trace's accounting, usually your transfer that failed.
2. **Get yourself told.** You cannot read your own actuators' requirements. If
   your supplier is lost, confused, or out of budget, you are stuck holding a key
   and no knowledge — and you cannot fix it by looking harder.
3. **Contribute your fragments to the order.** These are the only facts that do
   not flow along the ring. They are group property and they are the reason the
   round is not four private conversations.

### Why you must act — you specifically, not the group

This is question 7 of the five-questions set, in its co-op form: *why do you act
rather than let the confident player run the round?*

| | Because |
|---|---|
| **Your budget is yours** | `signal_budget_per_player` is per player and non-transferable. Nobody else can spend it. Your facts can only enter the world through you. |
| **You are not redundant** | k-essentiality (`mechanics.md §6.3` I1): any three lenses admit at least two consistent Procedures. Your three teammates cannot finish without you, however well they play. |
| **The solver cannot act** | `σ` is a derangement. A player who has somehow deduced everything still holds the wrong key for almost all of it. Knowing is not doing. |
| **The channel cannot carry a briefing** | I2's centralisation bound: three players spending their entire budgets cannot relay their full views to a fourth. |
| **Somebody has to be in the other room** | paired operations require two keys turned in two rooms inside `simultaneous_window_seconds`. |
| **Nobody can hold it all** | signals are ephemeral and there is no log. A would-be quarterback is trying to keep four decaying views in working memory for eight minutes. |

These six are structural, which is the only kind of answer worth writing down.
Whether they *work* is `playtest.md: P-Q`, and its "not working" reading is
deliberately written to catch the polite failure — three players who act, but only
when instructed.

---

## 4. Emergent roles — not authored, not prevented

Within a session a group will invent functional roles, and the design neither
provides nor forbids them:

- the **runner** who takes the far room because the paired operations keep landing
  there;
- the **clock** who spends tokens on `WAIT` and `GO` rather than on facts, buying
  synchronisation with information;
- the **cartographer** who stops reading their lens and spends the round assembling
  the global order from fragments.

These are good. They are the group's own solution to a problem the design posed,
they cost nothing to support, and they are exactly the kind of thing that makes a
specific group's play different from a stranger group's — which is the A2 #2
thesis (`loop.md §1.4`).

They become the failure mode only when one of them is **"the one who decides"**,
which is what §3's six devices exist to prevent. The distinction to watch in
playtest is not whether roles emerge — they will — but whether any emergent role
is *decisional* rather than *functional*.

---

## 5. What this design deliberately does not have

| Absent | Why |
|---|---|
| **Character classes** | a class is content; a seat in a generated ring is a system. A2 #4. |
| **Role unlocks** (A5, days 2–7) | there is nothing to unlock. Under amendment 9 progression is shared and seasonal; unlock cadence should be re-derived by the Lead PO against a co-op shape, and "more roles" is not the answer available to it. |
| **A hidden role / traitor** | amendment 8. And see `loop.md` appendix A1: under a fixed vocabulary, lying is free, so a traitor bolted onto this design would be undetectable by construction. If anyone proposes one later, that is the argument to answer first. |
| **Visual identification of players** | amendment 10. Identity is carried by signal attribution (`signal_reveals_sender`), which works in a dark room and needs no art. |
| **Per-player skill trees or stat differences** | they would break the k-essentiality symmetry and give a "best" player a reason to take over. |

---

## 6. Assignment, the trust boundary, and disconnects

**Assignment** happens server-side at round start, from the generator's seed. Per
B4:

- A player's lens contents are replicated **only to that player**. A required value
  must not exist in any other client's replicated state at any point. This is the
  single most important trust-boundary property in the game: a client that can
  read another player's lens is not cheating at a scoreboard, it has deleted the
  game.
- `σ`, the total order, and the full value assignment exist only on the server until the trace.
- Every actuation remote validates that the caller's key class matches the
  actuator's, in addition to proximity, phase and rate (`mechanics.md §5`).

**Disconnect** breaks the ring, and the repair is the only one that keeps the
instance solvable: the leaver's **key class transfers to their supplier** — the
player who could already see those required values. That player now holds two
keys and can act on one of their own lens's pairings, so the round gets easier and
k-essentiality is degraded. That is correct: the group has been harmed enough.

The leaver's **lens is lost**, which means their dependent's requirements become
unknowable and those operations must be brute-forced against instability. This is
the sharpest consequence of a dropout and it is why `min_players_to_continue` and
`disconnect_grace_seconds` matter more here than in most designs.

**Rejoin** inside the grace window restores the original seat and the remaining
budget. After it, the seat is gone and the player spectates until the next round.

**Edge case worth naming:** with `n = 3` after a dropout, the ring is a 3-cycle and
the game is playable but structurally thinner (`loop.md §2`). It is a degraded
round, not a different game, and the trace should say so rather than record it as
a clean result.
