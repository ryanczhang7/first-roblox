---
id: EPIC-02
title: The server is the only source of truth, and it says so out loud
status: todo
stories: [TEL-001, NET-001, NET-002, NET-003, SEAT-001, SEAT-002, SEAT-003, TEL-002, TEL-003]
---

## Goal

Every remote call reaching this server is validated for sender identity, argument
shape, argument range, phase legality and rate — through one wrapper, in one
place, with a distinct reason per rejection. Seats are dealt as a seeded
single-cycle derangement, a player's replicated view is built by an allowlist that
cannot contain anyone else's secrets, and the round emits the structured telemetry
A5's three retention buckets are measured from.

This is milestone **M2**, with one substitution the genre change forces: M2's
"vote submission and tally" is void — amendment 8 removed the vote — and its place
is taken by the **seat ring**, which is the role assignment M2 always named.

## Why now

B4 calls the trust boundary "the highest-risk area for agent-generated code", and
gives the reason: generated Luau is prone to trusting remote arguments. A3 pillar
4 puts it more sharply — this is a social game and the entire product dies the day
it is exploitable.

There is a second reason specific to this design. `roles.md` §6: a client that can
read another player's lens has not cheated at a scoreboard, **it has deleted the
game.** The whole puzzle is that information is split. The replication rule is
therefore not a security nicety bolted onto a working game; it is the mechanism
the game is made of, and it is cheapest to make structural now, while the only
thing to replicate is a seat.

Telemetry is here rather than later because B6 says "build in M2, not later", and
because an event emitted as a value from a pure function is testable, while an
event emitted as a side effect from a handler is not.

## Done when

Every remote has an adversarial test asserting rejection of **malformed,
out-of-phase and flooded** calls — B4's own definition of done — and each of those
tests asserts *which* check fired, not merely that something was rejected.

Plus:

- `Ring.assign` produces a permutation with no fixed point and exactly one orbit,
  for every seated count from 3 to 6, reproducibly from a seed.
- For every player `p`, nothing private to any other player appears anywhere in
  `Projection.forPlayer(assignment, p)`.
- A disconnect transfers the leaver's key class to their supplier and closes the
  ring, and a rejoin inside the grace window restores the seat.
- The six B6 events a server round can observe without persistence are emitted
  with the right bucket, exactly once per occurrence, and every rejected remote
  call emits one naming its reason.

## Stories

1. **TEL-001** — Telemetry events carry an envelope, a bucket and an injected
   timestamp. The envelope, the D1/D2–7/D8–28 mapping for all nine B6 events
   (three of them declared and not yet emitted), and an injectable sink.
2. **NET-001** — Every remote is declared with a schema and rejects malformed
   calls. The registry, the structural validators, the wrapper, and the guard test
   that `OnServerEvent:Connect` appears nowhere outside `src/net/`.
3. **NET-002** — A remote is rejected when it is called in the wrong phase, with a
   reason distinct from a shape rejection.
4. **NET-003** — A remote is rate-limited per player against the injected clock,
   independently per sender.
5. **SEAT-001** — Seats are dealt as a seeded single-cycle derangement over 3 to 6
   players.
6. **SEAT-002** — A player's replicated seat view is built by an allowlist and
   contains nothing of anyone else's.
7. **SEAT-003** — A disconnect transfers the key class to the supplier and closes
   the ring; a rejoin inside the grace window restores the seat.
8. **TEL-002** — The round lifecycle emits the B6 events a server round can
   observe, each exactly once.
9. **TEL-003** — Every rejected remote call emits a telemetry event naming the
   reason and the sender.

## Deliberately not in this epic

- **The signal remote and the actuation remote.** Those are the M3 channel, and
  their schemas depend on T6 and T7. This epic builds the pipeline they will be
  declared into, and declares nothing of the channel itself.
- **Lens contents.** `Assignment` carries `σ`, key classes and seat order. The
  pairings a lens shows come from the instance generator (`mechanics.md` §6) and
  are M3. The projection type is drawn now so M3 adds a field to an allowlist
  rather than inventing a replication path.
- **Client-side anything.** Nothing receives the projection yet. The story asserts
  what the server would send, which is the half that can leak.
- **Persistence.** `day_n_return`, `co_play_with_known_player` and `purchase` are
  declared in the bucket mapping and deliberately not emitted; they need a store,
  which is M5.
- **Proximity validation.** There are no positions yet. The pipeline leaves room
  for it as a sixth check; M3 fills it, server-side, against the server's own
  position record and never the client's claim.
- **Purchase validation.** M5, and its own definition of done.
