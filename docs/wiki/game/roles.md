# Roles

Co-operative does not mean symmetric. Every player has the same verbs (move,
look, show, turn) and none of them has the same **position** in the information
structure. A role here is not a class, a loadout or an unlock. It is a seat in a
ring, assigned per round, and the seat decides who you must help and who must
help you.

Constants are named, not valued; see `tuning.md`.

**Revised 2026-09-30 (third pass) for brief §0d #19.** The ring (§2) is
unchanged and already built (SEAT-001 to SEAT-003). What each seat *knows* and
*how it passes it on* changed (§3), and so did the emergent roles (§4). Section
numbers are unchanged, because source and tests cite them.

---

## 1. Why a co-op game has roles at all

Three things must be true at once, and one mechanism produces all three.

- **Nobody can act alone.** If any player can both see what is required and do
  it, that player is playing a solo game with three spectators.
- **Nobody is redundant.** If any three players can finish without the fourth,
  the fourth is a spectator by a slower route.
- **Nobody can be replaced by a spokesperson.** If one player can absorb the
  other three and direct them, the game has one player and three input devices.

The mechanism is a **cyclic derangement of lens and key**. It is one line of
generation logic, needs no art, produces all three properties, and a test can
check it exactly. The third property is now *stronger* than in the second pass:
there is no channel through which a spokesperson could collect everyone's facts
(§3).

---

## 2. The ring

*Unchanged. Built by SEAT-001; its projection by SEAT-002; disconnects by
SEAT-003.*

Each player `p` is dealt two things for the round:

| | Name | What it is |
|---|---|---|
| **key** | `k(p)` | the class of machines `p`, and only `p`, may turn |
| **lens** | `λ(p)` | the class of machines whose **required settings** `p`, and only `p`, can read |

The binding is a permutation `σ` over the players, constrained to be a **single
n-cycle** (`mechanics.md` §6.2 invariant 3):

    λ(p) = k(σ(p))          σ(p) ≠ p, and σ is one cycle, not two

- **You cannot act on what you can see.** `σ` has no fixed points.
- **The dependency graph is one ring, not two pairs.** Two disjoint swaps would
  be two two-player games sharing a map.

For four players the ring reads:

    P1 ──can read the settings for──▶ P2 ──▶ P3 ──▶ P4 ──▶ P1

Two terms used throughout (and in `Ring.luau`):

- your **supplier** is your ring-predecessor, σ⁻¹(p): the one player who can see
  what your machines need. In player-facing words, your **helper**.
- your **dependent** is your ring-successor, σ(p): the one player whose machines
  only you can read. In player-facing words, your **partner**.

The player-facing names are the Lead Designer's to choose. "Supplier" and
"dependent" are not words a seven-year-old should have to learn (§0d #14).

There are six cyclic derangements of four players, and one is picked per round,
so you do not develop a fixed relationship with one person.

---

## 3. What each seat knows, wants and must do

Every seat is structurally identical, so this is one description, not four.

### What you know

| Source | Content | Shared with |
|---|---|---|
| **Your lens** | the required setting of each of your **partner's** machines, **only while you stand within `lens_read_range_studs` with your light on it** | nobody |
| **Your turn cues** | which of your own machines is live now, and which is next once it is within `turn_cue_lookahead` steps | nobody |
| **Public world** | tags, key classes, dial positions, live lamps, committed lights, partner lamps, for machines you can see | anyone who can see them |
| **Pings** | every player's current ping, in their colour; your helper's also as a HUD arrow | everyone |
| **Presets** | every preset sent in the last `preset_display_seconds`, with sender and position | everyone, briefly |
| **The progress bar** | how many steps the group has committed, out of `procedure_length`, with the finale's segments marked. Never which step is next, which track, which machine, or whose (`mechanics.md` §3.2) | everyone, the same bar. **Added 2026-09-30, T10 (c)** |

> **Superseded 2026-09-30 by brief §0d #19:** "Your fragments", the
> `order_fragments_per_player` precedence statements, and "The stream", every
> token sent in the last `signal_display_seconds`. Order is now seen privately
> as turn cues and never relayed (`mechanics.md` §3.2). The stream is replaced by
> pings (reference) and presets (intent).

What you do **not** know: the required settings of your own machines; anyone
else's turn cues, and so the order of anything but your own steps (the progress
bar tells you how far the group has got, never where it goes next); and what
anyone else is about to do, except what the world and their presets show you.

### What you want

Everyone wants the same thing: the Procedure done before the clock. There is no
private win condition and no traitor (amendment 9). But the *local* obligations
are asymmetric:

1. **Get your partner's machines right.** Only you can read them. When their
   machine is live, you are the only person who can make it go well, and you
   have to be standing there to do it.
2. **Get yourself helped.** You cannot read your own machines. When your step is
   live and your helper is elsewhere, you wait, call (`Help`), or guess.
3. **Be where the finale needs you.** At the end, four bodies in two rooms.

> **Superseded 2026-09-30:** "Contribute your fragments to the order" (the second
> pass's third obligation). There are no fragments. The group-level problem the
> fragments used to create (the round is not four private conversations) is now
> created by the **two tracks**: your step and your partner's step compete for
> your body.

### Why you must act — you specifically, not the group

| | Because |
|---|---|
| **Only you can read your partner's machines** | knowledge is local and in person. Nobody can tell your partner what you know unless they stand where you would have stood, and they could not read it anyway |
| **You are not redundant** | k-essentiality (`mechanics.md` §6.3 I1): every class has a step, so without you one class cannot be read and one cannot be turned |
| **The knower cannot act** | σ is a derangement. Knowing is not doing |
| **Nobody can brief anybody** | no preset names a fact, and a ping works only on site (`mechanics.md` §4.3). A planner cannot collect settings, because there is no channel that would carry them to the planner |
| **Nobody sees the whole order** | turn cues are private, and the only public view of the order is a count (T10 (c), operator, 2026-09-30). A planner knows how many steps are left, and not what is next for anyone else |
| **Somebody has to be in the other room** | the finale needs four bodies in two rooms at n = 4 |

> **Superseded 2026-09-30:** "Your budget is yours" (there is no budget), "The
> channel cannot carry a briefing" as a *tuned* bound (it is now structural), and
> "Nobody can hold it all" through ephemerality (retired; the floor has no memory
> load).

Whether these work is `playtest.md: P-Q`. Its "not working" reading still
catches the polite failure: three players who act, but only when told to. The
new form of that failure to watch for is a planner steering people with doorway
pings.

---

## 4. Emergent roles — not authored, not prevented

Within a session a group will invent functional roles, and the design neither
provides nor forbids them:

- the **runner**, who takes the far rooms because their legs are the group's
  bottleneck;
- the **anchor**, who goes to the finale early and waits there, pinging the way;
- the **caller**, who sends `Help` *before* their step is live so that their
  helper arrives on time.

These are good. They are the group's own solution to a problem the design posed,
they cost nothing to support, and they are the **choreography** that `loop.md`
§1.4 now leans on for retention.

> **Superseded 2026-09-30:** the **clock** (spent tokens on `WAIT` and `GO` to buy
> synchronisation with information; presets now carry no information, and the
> finale's partner lamp does the synchronising) and the **cartographer**
> (assembled the global order from fragments; there are no fragments).

They become the failure mode only when one of them is **"the one who decides"**.
The distinction to watch in playtest is still whether an emergent role is
*decisional* rather than *functional*.

---

## 5. What this design deliberately does not have

| Absent | Why |
|---|---|
| **Character classes** | a class is content; a seat in a generated ring is a system. A2 #4 |
| **Role unlocks** (A5, days 2–7) | there is nothing to unlock. Progression is shared and seasonal (amendment 9); the days 2–7 re-derivation is the Lead PO's (§0c R4) |
| **A hidden role / traitor** | amendment 8. And a traitor could now also ping a wrong setting, indistinguishable from an honest ping (`loop.md` appendix A1) |
| **Visual identification of players** | amendment 10. Identity is carried by ping colour and preset attribution |
| **Per-player skill trees or stat differences** | they would give a "best" player a reason to take over |
| **A free-text or invented vocabulary** | new, 2026-09-30. §0d #19: every word a player can send is one of `preset_count` shipped presets, and none of them names a fact |

---

## 6. Assignment, the trust boundary, and disconnects

**Assignment** happens server-side at round start from the round's seed. Per
B4:

- A player's **lens contents** (required settings of their class of machines) are
  replicated **only to that player**, and in practice only for the machine they
  are reading. A required setting must not exist in any other client's
  replicated state at any point. This is unchanged and is still the most
  important trust property in the game.
- A player's **turn cues** are replicated only to that player. New in this pass,
  and the second per-player secret.
- `σ`, the Procedure, the track order and the full setting assignment exist only
  on the server until the trace.
- Every turn validates key class, proximity, phase and rate (`mechanics.md` §5).
  Every ping validates target kind, range and line of sight. Every preset
  validates phase and the 10 s rate, and passes the filter.

**What changes in the projection (`src/server/seats/Projection.luau`).** It stays
an allowlist. M3 adds, by name:

| Field | Carries | Status |
|---|---|---|
| lens contents | the required setting of a partner machine the player is reading | as planned in SEAT-002 ("pairings"), narrowed to "what I am reading now" |
| turn cues | own live step and own next step | **new** |
| ~~fragments~~ | ~~own order fragments~~ | **superseded 2026-09-30.** SEAT-002's header names this as a field M3 would add. It will not be added |

**The progress bar is not in the per-player projection.** It is the same for
every player and carries no secret: its payload is exactly `{committed, total}`
(`mechanics.md` §3.2), and every commit it counts is already public world state.
It belongs with round-public state, next to the phase and the clock. It must not
be built by widening `PublicSeatView`, because that type is the allowlist for
*per-player* facts, and a shared field there invites a per-player one next to it.

Nothing already built is invalidated. `playerId`, `keyClasses`, `lensClass`,
`supplierId`, `dependentId` and `seatOrder` are all still exactly what a player
needs, and `supplierId` is now what lets the HUD say "your helper's ping".

**Disconnect** *(unchanged, built by SEAT-003)*. The leaver's **key class
transfers to their supplier**, the player who could already read those settings,
who can now read and turn them. The leaver's **lens is lost**, so their partner's
settings become unreadable and must be guessed. With `dial_settings` at 4 that is
survivable rather than fatal, which suits an all-ages audience.

**Rejoin** inside `disconnect_grace_seconds` restores the seat. After it, the
player spectates until the next round.

**Edge case:** with n = 3 after a dropout, the ring is a 3-cycle and the finale's
turners are ring-neighbours (`mechanics.md` §3.2). It is a degraded round, not a
different game, and the trace says so.
