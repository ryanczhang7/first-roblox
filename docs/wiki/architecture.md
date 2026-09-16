# Architecture — M0 to M2 only

## 0. Scope, and a warning about reading it

**This document covers milestones M0, M1 and M2 and stops there. It is not the
architecture of the product.**

The backlog stops in the same place. **Do not read the end of the backlog as the
end of the product.** M3 (the playable vertical slice — the signal channel, the
Procedure, the instance generator, the map, the UI) is deliberately unplanned,
and an agent that "finishes the backlog" has finished about a fifth of the game.

### Why the line is drawn here

The Game Designer's finding, accepted by the operator: **M0–M2 are
genre-independent.** The toolchain, the gates, the
`Lobby → Assignment → Round → Resolution → Post` phase machine and the trust
boundary are identical under every genre candidate that survived the constraint
filter in `docs/wiki/game/loop.md` §3 — and they were identical before the genre
changed, which is the evidence for the claim rather than an assertion of it.

M3 onward is not. It depends on:

- **T5** — the operator's posture toward out-of-band voice, which sets
  `difficulty_band` and everything it varies.
- **T6** — whether a signal carries its sender's room. The largest single lever on
  early-session difficulty in the design.
- **T7** — how much memory load is difficulty and how much is exclusion.
- **T8** — whether a 16-token ordered stream is a moderation surface under
  Community Standards. A Lead PO verification, not a design question.
- **T9** — seasonal vocabulary rotation.
- **`playtest.md: P-V`**, which bears on amendment 8 — the genre decision itself —
  and which was decided before P-V's finding was known. It is paper-runnable and
  **should run before M3**.

Also open and not this document's to settle: product-brief amendment 12 (the
`lobby_seconds` + `round_seconds` = 9 minutes vs A5's 8-minute day-1 promise), and
the replacement for A2's withdrawn audience constraint.

Planning M3 now would mean inventing answers to those, and an architecture
derived from a game nobody has settled is a guess with a diagram.

### What M0–M2 must therefore not do

Everything here is built so that the M3 decisions remain *decisions*:

- The phase machine knows about **phases and outcomes**, and nothing about
  Procedures, instability, signals or actuators. An outcome arrives as an event
  carrying a reason; the machine does not compute it.
- The net layer defines the **validation pipeline**, not the remotes of the signal
  channel. It must make adding a remote cheap and adding an *unvalidated* remote
  impossible.
- Seat assignment builds the **ring** (`σ`, key classes). It does not build lens
  *contents*, which come from the instance generator and are M3.
- Telemetry defines the **envelope, the sink interface and the bucket mapping**. It
  emits the events the phase machine can actually observe, and no others.

---

## 1. Layers, and the one dependency rule

Repository layout follows brief B3 and the `roblox-luau` profile:

    src/shared/    types, constants, pure helpers, validation schemas
    src/server/    authoritative logic: phase machine, seats, round driver
    src/net/       remote definitions and server-side validation wrappers
    src/client/    presentation only: input, UI, camera, audio   (empty in M0-M2)
    tests/         Lune tests, mirroring src/
    lune/          test.luau, build.luau, analyze.luau

**The rule, in one line:** `shared` imports nothing from the other three;
`client` imports only from `shared` and `net`; `server` imports from `shared` and
`net`; **`client` never imports from `server`.**

That is not stylistic. On Roblox, a module reachable from a `LocalScript` is a
module an exploiter can read in full — constants, comments and all. "The client
does not import this" is the *only* mechanism that keeps server logic off the
client, and it is enforced by the Rojo project file's instance mapping plus a
guard test over the import graph.


### How a module in `src/` requires another module in `src/`

**Alias, never a relative path across a layer.** Written down here because
`ROUND-003` was the first story to need a cross-layer require and the obvious
spelling fails a required gate:

    local Rng = require("@shared/Rng")        -- crossing from server to shared
    local RoundConfig = require("./RoundConfig")  -- same directory: relative is fine

The alias lives in `.luaurc`:

    "aliases": { "shared": "src/shared" }

**Why the relative form cannot work.** `luau-lsp` resolves a relative string
require *through the sourcemap*, in the Roblox instance tree — not in the
directory tree. `src/shared` maps to `game/ReplicatedStorage/Shared` while
`src/server/round` maps to `game/ServerScriptService/Server/round`, so
`require("../../shared/Rng")` asks for `game/ServerScriptService/shared/Rng`,
which does not exist. Measured on this machine, 2026-09-15, reproduced by the
Lead PO through `scripts/mutate.sh` against the shipped module:

    src/server/round/PhaseMachine.luau [game/ServerScriptService/Server/round/PhaseMachine](65,13):
        TypeError: Unknown require: game/ServerScriptService/shared/Rng

There is no relative spelling that both `luau-lsp` and Lune accept across that
boundary, which is what makes this a convention rather than a preference.

**The limit, recorded rather than left in a comment.** Two of the three things
that read a require have been measured — `luau-lsp analyze` exits 0 and
`lune run test` resolves the alias — and the third has not: **nothing in this
repository executes a module inside a Roblox runtime**, `.luaurc` is not synced
by `default.project.json`, and the `build` gate proves only that the place file
builds. So alias resolution *in a real place* is untested as of `ROUND-003`. The
first story that runs a module in a place — the `RoundService` driver, or the
first `src/net/` story with a live remote — verifies it, and if it does not hold
the fix is a Rojo-side instance require behind a Lune-side shim, not a return to
relative paths.

Note that this does not weaken §1's dependency rule: an alias for `shared` is
the only one, so a `client` module cannot spell a require for `server` at all.
### The pure core

Every rule in `src/server/` and `src/net/` is written as a **pure function of
state**. Impurity — a clock, a random source, a RemoteEvent, a DataStore — is
confined to a thin *driver* at the composition root, which:

1. reads the world (time, network events),
2. calls pure functions,
3. carries out the **effects** they return.

The pure functions never perform an effect; they *describe* one. This is what
makes `docs/wiki/game/mechanics.md` §9's "headlessly verifiable" column true
rather than aspirational, and it is why the test suite needs no Roblox runtime.

A test that constructs a Roblox `Instance` under Lune and asserts on its
properties is testing `@lune/roblox`'s datamodel emulation, not this game. Where
something genuinely requires the Roblox runtime, it is a Studio playtest step and
is written down as one — not faked in a unit test.

---

## 2. Determinism is load-bearing, and it is a first-story requirement

**Hard requirement: the clock and the random source are injected from the very
first story.** Retrofitting either means rewriting the phase machine and the
generator, so there is no cheap moment to add it later.

### `src/shared/Clock.luau`

    export type Clock = { now: () -> number }          -- seconds, monotonic

    Clock.manual(startSeconds: number) -> ManualClock  -- ManualClock:advance(dt)
    Clock.real() -> Clock                              -- the ONLY sanctioned adapter

`Clock.real` is the single place in `src/` permitted to call `os.clock`,
`os.time`, `tick`, `DateTime.now` or `task.wait`. A guard test enumerates every
source module via `bash scripts/classify.sh --list source src` — the same answer
the phase lock uses, not a private regex — and asserts none of the others
mentions them.

Time enters the pure core **only** as the `now` argument of `PhaseMachine.step`.
The machine never asks what time it is.

### `src/shared/Rng.luau`

    Rng.fromSeed(seed: number) -> Rng
    Rng:nextInteger(min: number, max: number) -> number
    Rng:shuffle<T>(list: {T}) -> {T}                   -- returns a new list
    Rng:derive(label: string) -> Rng                   -- an independent sub-stream

`Rng` is the only module permitted to touch `math.random` or `Random.new`, under
the same guard.

`derive` earns its place: it means **adding a new consumer of randomness cannot
shift an existing consumer's sequence.** Without sub-streams, inserting one
`nextInteger` call anywhere changes every downstream draw, every recorded seed
stops reproducing its instance, and every seeded test in the suite has to be
re-baselined for a change that was supposed to be additive. With them, seat
assignment draws from `rng:derive("seats")` and the M3 generator from
`rng:derive("instance")`, and neither can perturb the other.

A round's seed is recorded with the round. An instance is reproducible from a
seed, which is what makes a bad round reportable and the generator testable
(`mechanics.md` §6.1).

---

## 3. The round phase machine (M1)

    src/server/round/PhaseMachine.luau     pure
    src/server/round/RoundConfig.luau      durations and thresholds, from Tuning
    src/server/round/RoundService.luau     the driver: impure, thin, untested logic-free

### Shape

    export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"

    PhaseMachine.initial(config: RoundConfig, seed: number) -> RoundState
    PhaseMachine.step(state: RoundState, event: Event, now: number) -> (RoundState, {Effect})

`step` is total, pure and deterministic: the same `(state, event, now)` yields the
same `(state', effects)` forever. It returns a **new** state; `RoundState` is
never mutated in place, because a mutated state makes "what did the machine do"
unanswerable in a test and unloggable in the trace.

An event the current phase does not recognise is **ignored, not an error** — it
returns the state unchanged and an empty effect list. A distributed system
delivers late and duplicate events, and a machine that throws on one is a machine
that can be crashed by a lagging client.

### The transitions

| From | Leaves when | To | Notes |
|---|---|---|---|
| `Lobby` | `lobby_seconds` elapsed **and** `#players >= players_min` | `Assignment` | Below `players_min` the timer **holds** rather than resetting: the clock is a floor on lobby dwell time, not a punishment for a late fourth player. |
| `Lobby` | `#players > players_max` | `Lobby` | The surplus join is rejected at the door, by the driver; the machine never holds more than `players_max`. |
| `Assignment` | `SeatsAssigned` event | `Round` | Assignment is a *step*, not a pause. Entering emits an `AssignSeats` effect; the driver runs `Ring.assign` and feeds the result back. A timeout here is a server fault, not a game state — it ends the round as `no_contest`. |
| `Round` | `RoundResolved{outcome}` | `Resolution` | The machine does **not** compute the outcome. M3 decides what resolves a round; M1 only routes it. |
| `Round` | `round_seconds` elapsed | `Resolution` | outcome `lost(clock)`. |
| `Round` | `#players < min_players_to_continue` | `Resolution` | outcome `no_contest` — "the group did not fail, the lobby did" (`mechanics.md` §8). No loss recorded. |
| `Resolution` | immediately, on entry | `Post` | Emits the trace-computation effect. In M1 the trace is a stub; M3 fills it. |
| `Post` | `post_round_seconds` elapsed | `Lobby` | Emits the rematch prompt effect. A4 calls this "the highest-value thirty seconds in the product"; `post_round_seconds` is 45 because the trace is four items of reading. |

**Simultaneous conditions are ordered deterministically, and the order is
specified rather than emergent** (`mechanics.md` §8): when the clock expiry and a
resolving event land in the same `step`, the *event* wins — it describes something
that happened inside the round. When two terminal conditions both hold, the
recorded reason is the one earlier in a fixed precedence list, because the trace
reports the reason and a nondeterministic reason is a bug report nobody can
reproduce.

**The list, stated once** (`ROUND-005`). Within a single `step` on a `Round`
state, terminal conditions are evaluated in this fixed order and the first that
holds wins:

    1. RoundResolved  — an event carrying an outcome; the machine records it verbatim
    2. below_quorum   — `#players < min_players_to_continue`; `no_contest`, never `lost`
    3. clock          — `now - phaseEnteredAt >= round_seconds`; `lost`, reason `clock`

A round nobody can play did not run out of time, and an event describing
something that happened inside the round outranks the round running out around
it. This ordering is the contract: a later story may not reorder it without an
`## Amendments` entry on the story that does, because `mechanics.md` §7 reports
the reason to players and `TEL-002` emits it as telemetry.

The clock is consulted only for an event the phase recognises — in practice
`Tick` — never at the top of `step`; quorum is consulted on `Tick` and on
`PlayerLeft`, which is the only event that can change the count. An event the
phase does not recognise is still ignored in full, whatever the clock says.

### Effects

    type Effect =
        | { kind: "AssignSeats",   seed: number, players: {PlayerId} }
        | { kind: "Emit",          event: TelemetryEvent }
        | { kind: "ReplicateSeat", playerId: PlayerId, view: PublicSeatView }
        | { kind: "PromptRematch" }
        | { kind: "ComputeTrace",  roundId: RoundId }

Effects are values. A test asserts on the list; the driver performs it. This is
what lets telemetry (§6) be verified without a sink and replication (§5) be
verified without a network.

### What it does not know

No Procedure, no operations, no actuators, no instability, no signals, no budget.
Those are M3 and they arrive through `RoundResolved` and through effects the
machine forwards without interpreting. Keeping this true is what makes the M1
work survive the M3 decisions.

---

## 4. The trust boundary (M2)

Brief **B4**, restated as architecture. This is the highest-risk area for
agent-generated code, because generated Luau is prone to trusting its arguments.

### The rule that is actually enforceable

> **No `OnServerEvent:Connect` outside `src/net/`.**

A guard test enumerates source modules through `scripts/classify.sh --list` and
asserts the string appears nowhere in `src/server/` or `src/client/`. Every remote
therefore passes through one wrapper, and "did we remember to validate this one"
stops being a per-story question.

### The pipeline

    src/net/Remotes.luau      the declaration registry
    src/net/Schema.luau       structural validators
    src/net/RateLimiter.luau  per-player, clock-injected
    src/net/Wrapper.luau      guard(definition, handler) -> guardedHandler

A remote is **declared**, not connected:

    Remotes.define("SubmitSignal", {
        args        = Schema.shape({ token = Schema.integer(1, 16) }),
        legalPhases = { "Round" },
        rateLimit   = { minIntervalSeconds = 1.5 },
    })

`Wrapper.guard` runs, in this order, and stops at the first failure:

1. **identity** — the sender is a seated player in this round;
2. **shape** — arity and types match the schema;
3. **range** — every number is inside its declared domain;
4. **phase legality** — the current phase is in `legalPhases`;
5. **rate limit** — per player, measured against the injected clock;
6. **handler** — only now does game logic see the call.

**Each failure returns a distinct reason**, and that is not a nicety. A wrapper
that rejects *everything* passes a naive adversarial test — "malformed calls are
rejected" is satisfied by a wrapper that rejects valid calls too. Distinct reasons
let a test assert *which* check fired, so the suite can tell a working boundary
from a broken one. Every rejection also emits a telemetry effect, because a spike
of one rejection kind is the earliest signal of an exploit attempt.

### Replication: allowlist, never denylist

The single most important trust-boundary property in the game
(`roles.md` §6): a client that can read another player's lens has not cheated at a
scoreboard, it has deleted the game.

So server state is never filtered *down* to a client view by copying a record and
removing fields. It is built *up*, field by field, by a projection function whose
output type names every field it may contain:

    Projection.forPlayer(assignment: Assignment, playerId: PlayerId) -> PublicSeatView

A denylist is one forgotten field away from leaking the round; an allowlist is one
forgotten field away from a visibly missing feature. Those failure modes are not
symmetric, and the architecture picks the one that fails loudly.

The property a test asserts: for every player `p` and every field of the private
assignment record, that field's value for any player other than `p` does not
appear anywhere in `Projection.forPlayer(assignment, p)`.

### Client claims are claims

Client-supplied position, timing and target selection are **claims, not facts**,
and are re-derived or sanity-checked server-side. In M0–M2 the only claims are
identity and timing; proximity arrives with M3's actuation and will be
server-checked against the server's own position record, never against the
client's.

---

## 5. Seats — the ring (M2)

    src/server/seats/Ring.luau        assign, withdraw, rejoin — all pure
    src/server/seats/Projection.luau  the allowlist projection above

`roles.md` §2 in one sentence: each player `p` holds a **key** `k(p)` (the class of
actuators only `p` may operate) and a **lens** `λ(p) = k(σ(p))` (the class whose
required values only `p` can read), where `σ` is a **single n-cycle** over the
seated players.

    Ring.assign(players: {PlayerId}, rng: Rng) -> Assignment
    Ring.withdraw(assignment: Assignment, playerId: PlayerId) -> Assignment
    Ring.rejoin(assignment: Assignment, playerId: PlayerId) -> Assignment

Three properties the generator must hold, all exactly checkable and all cheap:

- `σ` has **no fixed point** — you cannot act on what you can see;
- `σ` is **one orbit**, not two 2-cycles — four players are one ring, not two
  independent pairs sharing a map;
- assignment is **seeded** — the same seed yields the same ring.

`withdraw` implements `roles.md` §6: the leaver's key class transfers to their
**supplier** (their ring-predecessor, `σ⁻¹`), who could already see those required
values, so the instance stays solvable and gets easier. Their lens is lost. The
ring closes to an `(n−1)`-cycle. Below `min_players_to_continue` the phase machine
ends the round as `no_contest`.

`Assignment` in M2 carries `σ`, the key class per player, and the seat order. It
does **not** carry lens contents — those are pairings from the instance generator,
which is M3. The projection type is drawn now so that M3 adds a field to an
allowlist rather than inventing a replication path.

---

## 6. Telemetry (M2, per B6)

    src/shared/telemetry/Event.luau   the envelope and the bucket mapping
    src/shared/telemetry/Sink.luau    the interface, plus recording() and noop()

    type TelemetryEvent = {
        name:      string,
        at:        number,          -- from the injected clock, never os.time
        bucket:    "D1" | "D2_7" | "D8_28",
        sessionId: string,
        playerId:  PlayerId?,
        fields:    { [string]: string | number | boolean },
    }

    type Sink = { emit: (TelemetryEvent) -> () }

**Emission is an effect, not a call.** Pure code returns `{ kind = "Emit", event }`
and the driver hands it to the sink. Three things follow: telemetry is verified
without a sink, a sink failure cannot break a round, and the events are part of
the phase machine's tested output rather than a side channel nobody asserts on.

B6's event list, and who can emit it:

| Event | Bucket | M2? |
|---|---|---|
| `join` | D1 | yes |
| `first_round_complete` | D1 | yes |
| `round_complete` | D2_7 | yes |
| `bounce_before_resolution` | D1 | yes — the phase machine sees the leave and the phase |
| `rematch_accepted` | D2_7 | yes |
| `session_end` | D1 | yes |
| `day_n_return` | D8_28 | **no** — needs persistence (M5) |
| `co_play_with_known_player` | D8_28 | **no** — needs a friend/history store (M5) |
| `purchase` | D8_28 | **no** — M5 |

The three marked no are **declared in the envelope's bucket mapping and not
emitted**, so that M5 adds an emitter rather than a vocabulary. A5 requires all
three buckets instrumented separately from day one; M2 delivers that for every
event a server round can observe without persistence, and the gap is named here
rather than discovered later.

`bounce_before_resolution` is the one to get exactly right: A5 makes first-play
bounce a direct ranking penalty, so it is the most valuable event in the list and
the easiest to emit twice or not at all. Its rule: emitted when a player leaves
while the phase is `Lobby`, `Assignment` or `Round`, at most once per player per
round, and never when they leave during `Resolution` or `Post`.

---

## 7. Deployment shape

- **Inner loop:** filesystem → `rojo serve` → Studio, for a human. No gate uses it.
- **Gates:** `stylua`, `selene`, `rojo sourcemap` + `luau-lsp analyze`,
  `lune run test`, `rojo build`. All headless, all Linux, no credentials.
- **CI:** `.github/workflows/gates.yml` and `boundaries.yml`, already present.
  `BOOT-001` adds the Rokit setup step to the gates job. The harness self-test
  stays in the bash-only job.
- **Publishing:** Open Cloud, scripted, **operator-approved per B1 #5**. Not built
  in M0–M2 and not automated on merge.
- **The production image excludes the harness.** `.claude/`, `docs/`, `scripts/`
  and `.github/` never ship (`rules.md`). Rojo's project file decides what becomes
  an Instance, so the exclusion is enforced by `default.project.json` mapping only
  `src/`, and by nothing else — which makes that file's contents a trust-boundary
  artefact, not just build configuration.

---

## 8. Decisions, and what lost

| # | Decision | Alternative | Why it lost |
|---|---|---|---|
| D1 | Clock and RNG injected from story one | call `os.clock` / `math.random` at the point of use | the phase machine and the generator become untestable and the seed stops reproducing a round. Retrofitting means rewriting both. Cost: one interface and one guard test. |
| D2 | `Rng:derive(label)` sub-streams | one global sequence | adding a consumer anywhere shifts every downstream draw, invalidating every recorded seed and every seeded test. |
| D3 | Pure `step` returning **effects as values** | perform side effects inside the machine | effects-as-values is what makes telemetry, replication and the trace assertable in a test with no runtime, no sink and no network. Cost: a driver that interprets them. |
| D4 | Phase machine is **outcome-agnostic** | machine computes win/loss from the Procedure | it would bind M1 to M3's unsettled mechanics; the scope line in §0 would not hold. |
| D5 | Unknown event → ignored | unknown event → error | late and duplicate delivery is normal; throwing turns a lagging client into a server fault. |
| D6 | Remotes **declared**, connected only in `src/net/` | connect where convenient, validate in the handler | validation you must remember is validation you will forget once. A guard test makes the rule mechanical. |
| D7 | Distinct rejection reason per pipeline stage | a single boolean reject | a reject-everything wrapper passes an adversarial test that only asserts "rejected". |
| D8 | Replication by **allowlist projection** | copy the state and strip private fields | the two failure modes are not symmetric: a denylist leaks the game silently, an allowlist shows a missing feature loudly. |
| D9 | Telemetry buckets declared for all nine B6 events, three unemitted | declare only what M2 emits | M5 then adds an emitter, not a vocabulary — and the gap is visible now rather than found later. |
| D10 | Own test runner (`lune/test.luau`) | adopt a third-party Lune framework | see `stack.md` §3: controlling the output contract is what makes `evidence`, `floor` and `discovery` exact in an ecosystem with no counting tools. Revisit if a framework appears that satisfies the same contract. |

---

## 9. Deliberately not decided here

Listed so their absence reads as a boundary and not an oversight. Each needs the
open questions in §0 closed first.

- The signal channel: wheel UI, budget accounting, reserve unlock, ephemerality
  timing, the server signal log.
- The instance generator: layout, tags, value assignment, the Procedure, order
  fragments, paired operations, and invariants I1–I3 (`mechanics.md` §6).
- The post-round trace computation (`mechanics.md` §7).
- Actuation, instability, blackout selection.
- Any client module: rendering, input, camera, audio, lighting.
- Persistence: DataStore request budgets, ordered stores, throttling, retry.
- Progression, monetisation, purchase validation (M5).
- The map and anything to do with geometry.
