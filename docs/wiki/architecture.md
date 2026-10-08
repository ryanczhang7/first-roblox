# Architecture — M0 to M3

## 0. Scope, and a warning about reading it

**This document covers milestones M0 to M3.** §1–§8 are the M0–M2 architecture,
built and verified (every M0–M2 story is DONE). §9 is M3, the playable vertical
slice, planned 2026-09-30 against the Game Designer's **third pass** of
`docs/wiki/game/` and product-brief §0d. It is not yet built.

**It is still not the architecture of the product.** M4 (feel), M5 (progression,
persistence, monetisation) and M6 (launch) are unplanned, and an agent that
"finishes the backlog" at the end of M3 has finished a game nobody can keep
playing. §10 lists what is deliberately undecided.

### What changed for M3, and why the M2 plan's M3 list is void

The M2 plan listed M3 as "the signal channel, budget accounting, reserve unlock,
ephemerality, order fragments, invariants I1–I3". **That channel no longer
exists.** Brief §0d #19 found it did not comply with Roblox's preset-system
guidelines, and the operator chose (a): the channel is a compliant preset system
for all ages. The third pass replaced it with:

> **Presets carry intent. Pings carry reference. The world carries facts.**
> (`mechanics.md` §4.0)

So M3 builds, in this order of dependency:

1. **The runtime spine** — a real place boots, players join, the existing phase
   machine runs on the real clock, and remotes pass through the existing
   wrapper. Nothing in M0–M2 has yet run inside a Roblox runtime (§1, "The
   limit"), so this goes first.
2. **The facility generator** — rooms, machines, required settings, the
   two-track Procedure with its finale, and par (`mechanics.md` §6).
3. **The Procedure at run time** — turning, the finale window, instability,
   blackout, and the outcome (`mechanics.md` §3, §5, §8).
4. **The channel** — pings and presets (`mechanics.md` §4), with its compliance
   rules as tests.
5. **What each player is told** — the lens view and turn cues (per-player
   secrets) and the public round view, including the progress bar
   (`roles.md` §6, `mechanics.md` §3.2).
6. **The slice** — blockout geometry, the client HUD, and the driver that wires
   it all; done when four humans complete a round in Studio (brief §0c R2).
7. **The trace** — the post-round lesson (`mechanics.md` §7).

### What survives from M0–M2 unchanged

Everything. The phase machine, the ring, the allowlist projection, the validation
pipeline, the rate limiter and telemetry are all used as built. The redesign
touched only stale comments (`Projection.luau`, `Ring.luau`, `Tuning.luau`) and
the example in §4 — which is the evidence that §0's old rule ("M0–M2 must not
know about the channel") paid off.

### The rules M3 must keep

- **The phase machine stays outcome-agnostic** (D4). M3's Procedure computes the
  outcome and hands it to the machine as `RoundResolved`, exactly as M1 planned.
- **Every per-player secret is built up by an allowlist** (D8), and **sent only to
  its player** (D13). There are now two secrets, not one: the lens contents
  (required settings) and the turn cues.
- **Pure core, thin driver** (§1). Every M3 rule is a pure function of state; the
  Roblox runtime appears only behind injected ports (§9.6), and anything that
  genuinely needs it is a written Studio step, not a faked unit test.

---

## 1. Layers, and the one dependency rule

Repository layout follows brief B3 and the `roblox-luau` profile:

    src/shared/    types, constants, pure helpers, validation schemas
    src/server/    authoritative logic: phase machine, seats, round driver
    src/net/       remote definitions and server-side validation wrappers
    src/client/    presentation only: input, UI, camera, audio   (empty in M0-M2; M3, §9.9)
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

**Measured in a real place: `@shared` does not resolve; `@game` does
(`SLICE-001`, 2026-10-07).** Roblox Studio 0.742, with Rojo 7.7.0 serving
`default.project.json` into a new Baseplate, then Play:

    server alias: false error requiring "@shared/Clock": @shared is not a valid alias
    client alias: false error requiring "@shared/Clock": @shared is not a valid alias
    server game alias: true table: 0x9e333e8e77839707
    client game alias: true table: 0xace9ede3db5a50b3

- **Same-layer relative requires work in a place.** `Generator`'s `./Layout`
  loaded, and the failure came one level down, at `Layout`'s `@shared` line. So
  **no module that requires `@shared` loads in a place today**, which is every
  module that crosses into shared.
- **Roblox reads no `.luaurc`.** As of the latest staff statement (2026-01-08,
  the require-by-string announcement on the DevForum), it has not shipped custom
  aliases. Only the built-in `@self` and `@game` exist. So no file Rojo could
  map into the place would make `@shared` work. That rules out the fallback
  this section used to name first.
- **`@game` is resolved by all three readers, given one condition.**
  - Studio: natively.
  - `luau-lsp` 1.69.0: through the sourcemap. A probe annotating
    `require("@game/ReplicatedStorage/Shared/Clock")` as `number` got
    `Expected this to be 'number', but got 'Clock'`.
  - `lune` 0.10.5: only when `.luaurc` defines `game` as a directory. Without
    it, Lune reports `@game is not a valid alias`; with
    `"game": "<dir>"` it resolves `<dir>/ReplicatedStorage/Shared/X`.

**Decision (operator, 2026-10-07): mirror the DataModel on disk for the shared
layers, and spell cross-layer requires with `@game`.** `src/shared` becomes
`src/ReplicatedStorage/Shared`, and `src/net` becomes
`src/ReplicatedStorage/Net`. `.luaurc` declares exactly one alias,
`"game": "src"`. A cross-layer require reads:

    local Rng = require("@game/ReplicatedStorage/Shared/Rng")

That one spelling resolves natively in Studio, in `luau-lsp` and in Lune, with
no generated files and no shim. `src/server` and `src/client` keep their
paths: nothing may require them across a layer.

Two alternatives were weighed and rejected:
- **A generated junction or symlink tree for Lune** would change fewer files.
  But it adds platform-specific generated state, and it gives Lune two paths to
  one file, so a test requiring `src/shared/X` would load a second instance of
  the module that source loads through `@game`.
- **Instance requires behind a Lune shim** (this section's earlier fallback)
  would need a fake `game` and a replaced global `require` in Lune. That is the
  most fragile of the three, now that `@game` exists.

`SLICE-008` implements the decision. Until it merges, the `@shared` spelling
above is still what the repository uses, and it still fails in a place.

**The dependency rule needs a guard now.** `@game` is a path from the
DataModel root, so in Studio and `luau-lsp` it can name
`@game/ServerScriptService/…` from the client, which `@shared` could never
spell. Lune would refuse it, because no `src/ServerScriptService` exists, but
that is incidental. So `SLICE-008` adds a guard test: a string require in
`src/` that leaves its own layer must begin `@game/ReplicatedStorage/`. D21's
`@net` alias is superseded: `src/ReplicatedStorage/Net` is reached the same way.

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

    Remotes.define("SendPreset", {
        args        = Schema.shape({ preset = Schema.integer(1, 10) }),
        legalPhases = { "Lobby", "Round", "Post" },
        rateLimit   = { minIntervalSeconds = MechanicsTuning.channel.preset_rate_limit_seconds },
    })

*(Revised for M3. The M2 example declared the superseded `SubmitSignal` at
1.5 s; the channel is now presets and pings at 10 s, §9.5.)*

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
client's. M3's version of this is §9.8: positions are sampled server-side and a
sample is accepted only if it is plausible.

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
does **not** carry lens contents — those are required settings from the facility
generator, which is M3. M2 drew the projection so that M3 would add to an
allowlist rather than invent a replication path; M3 does that with two **separate**
allowlisted views, `lensFor` and `turnCuesFor`, beside `forPlayer` rather than
inside it (D16, §9.7). The M2 plan's `pairings` and `fragments` fields will not be
added: fragments are superseded (`roles.md` §6) and "pairings" became "the
required settings I am reading now".

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
- **Entry scripts (M3):** Rojo turns `*.server.luau` into a `Script` and
  `*.client.luau` into a `LocalScript`. There is one of each —
  `src/server/RoundService.server.luau` and `src/client/Main.client.luau` — and
  every other file stays a `ModuleScript`. `SLICE-001` confirms the mapping in a
  real place.
- **Playing it (M3):** `bash scripts/task.sh dev` serves the project; Studio's
  local server with four clients is how a human runs a round. The M3 definition
  of done is four humans (brief §0c R2), which is an operator step, not a gate.
- **Publishing:** Open Cloud, scripted, **operator-approved per B1 #5**. Not built
  in M0–M3 and not automated on merge.
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
| D11 | **The Procedure owns the round deadline** (§9.2); the phase machine's `round_seconds` is a backstop | a new phase-machine event that shortens the round | the clock penalty is an instability rule, and D4 keeps M3's mechanics out of M1. The backstop cannot fire first, because penalties only subtract. Cost: two clocks, one of which must never be read for display. |
| D12 | The facility is **generated after seats** | generate it independently of the ring | `INV_finale` needs ring adjacency; a facility drawn without σ would have to be resampled against it anyway. |
| D13 | **Secrets travel by `sendTo` (FireClient) only**; never Attributes or Value objects | attributes on the `Player` instance, which Roblox replicates for free | `Player` instances replicate to every client, so anything written on one is public. `Transport` exposes no path that could broadcast a per-player payload. |
| D14 | The lens view is gated **on the server** by class, range, line of sight and a lit room; light *direction* is presentation | a `Look` remote on which the client claims what it is pointing at | the trust property is "never to a non-holder", which the server gate already guarantees; a look remote adds a rate-limited round trip to every glance and narrows only what the rightful holder may already know. |
| D15 | **Public world facts replicate to every client**; "readable in person" is enforced by rendering | proximity-filtered replication of lamps, dials and pings | none of those facts is a secret (`roles.md` §6); filtering them is a second projection to keep correct for no trust gain. Cost, accepted: an exploited client sees public lamps from afar. |
| D16 | Lens and turn cues are **separate allowlisted views** beside `PublicSeatView` | widen `PublicSeatView`, as SEAT-002's header planned | the seat view is sent once per round, the lens on every step a helper takes; and a separate type per secret gets its own leak property. `roles.md` §6 also forbids widening the per-player type with shared fields. |
| D17 | **One remote per player action (`SendPreset`, `Ping`, `Turn`, `AcceptRematch`), one send limiter each per player**; per-preset phases checked in the handler | one remote per preset, each with its own phases in the wrapper | C4 is "one preset per 10 s per player, across the whole wheel"; ten remotes are ten limiters. |
| D18 | A handler may **decline** a call so the wrapper refunds its **send limit**; a separate, non-refundable **attempt floor** runs first (§9.5) | (a) filter and validate targets before the wrapper; (b) move the 10 s cooldown out of the wrapper into channel state | (a): nothing may run before identity and shape (D6, D7). (b): C4 is checked "by the net wrapper's rate stage, declared at 10" (`mechanics.md` §4.3), and moving it would leave the remotes' declared limit at 1 s and the provenance test comparing the wrong number. G9 made refused targets and out-of-phase presets "not sends", so the refund is no longer a filter-only special case. |
| D19 | `tuning.md` §2–§4 in **`MechanicsTuning.luau`** with its own drift guard | add sub-tables to `Tuning.luau` | ROUND-002's frozen guard asserts `Tuning.luau` is exactly §1 and §5. |
| D20 | Client UI in **plain Instances**, no UI package | a Wally UI library | a dependency is an operator decision (B1 #5); M3's UI is minimal; pure view models give the testability a framework would. Revisit at M4. |
| D21 | ~~A second alias, **`@net`**~~ **superseded by `SLICE-001`** | relative requires into `src/net` | Roblox has no custom aliases; `src/net` moves to `src/ReplicatedStorage/Net` and is required as `@game/ReplicatedStorage/Net/…` (§1, `SLICE-008`). |
| D22 | A **pure `Session`** composition root, and a **headless full round** as M3's integration test | integration verified only in Studio | Studio is manual and gates nothing; a headless round is the only evidence a required gate can hold that the pieces compose. |
| D23 | **Which player holds which key class is not a secret**; the secrets are required settings and turn cues | permute the class-to-pattern mapping per round and replicate only viewer-relative "mine / partner's / neither" flags | the Game Designer's ruling (`mechanics.md` §1): the mapping is learnable within a round by watching who turns what, nothing can be addressed to a player, and `Ring` deals class *i* to seat *i* with `seatOrder` public anyway. SEAT-002's "no other player's key class in the projection" stays true of the projection and is **not** a secrecy guarantee; `FacilityView` publishes each machine's key class. Revisit only if playtesting shows the mapping being used to steer. |
| D24 | **Two public payloads**: `FacilityView` once per round, `RoundView` on change | one view carrying static and dynamic facts | the layout and machine placement never change in a round; resending them every second is waste, and a smaller dynamic view is easier to hold to its allowlist. |

---

## 9. M3 — the playable vertical slice

Planned 2026-09-30. The game is specified in `docs/wiki/game/` (third pass); the
screens in `docs/wiki/design/`. This section says where each rule lives, how the
pieces talk, and where state is held. It does not restate the rules.

### 9.1 Module map

| Path | Kind | Responsibility |
|---|---|---|
| `src/shared/MechanicsTuning.luau` | pure, data | `tuning.md` §2–§4 as a frozen table, keys verbatim (D19) |
| `src/shared/channel/Presets.luau` | pure, data | the preset table (`mechanics.md` §4.2): id, word, icon key, legal phases. Shared because the client draws the wheel from it |
| `src/server/facility/Layout.luau` | pure | rooms, doorways, shortest-path distances |
| `src/server/facility/Machines.luau` | pure | machine placement, key classes, tags, required settings |
| `src/server/facility/Steps.luau` | pure | which machines are steps, the tracks, the finale |
| `src/server/facility/Par.luau` | pure | the canonical schedule and `INV_traversal` |
| `src/server/facility/Generator.luau` | pure | composes the four, resamples on an invariant failure, returns a `Facility` |
| `src/server/procedure/Procedure.luau` | pure | step states, turning, the finale window, instability, blackout, the deadline, the outcome |
| `src/server/channel/Pings.luau` | pure | ping target validation, one active ping per player, expiry, the ping log |
| `src/server/channel/PresetSends.luau` | pure | per-preset phase legality, the positioned broadcast, the preset log |
| `src/server/seats/Projection.luau` | pure | extended: `lensFor`, `turnCuesFor` beside `forPlayer` (D16) |
| `src/server/round/RoundView.luau` | pure | the public round view, including the progress bar |
| `src/server/trace/Trace.luau` | pure | the post-round trace from logs |
| `src/server/facility/Blockout.luau` | pure | part specifications for the generated rooms, walls, doorways and machine anchors (`MAP-001`); a thin builder instantiates them |
| `src/server/procedure/TurnRequests.luau` | pure | a guarded `Turn` call into `Procedure.turn`, and the private reply |
| `src/server/session/Positions.luau` | pure | position plausibility (§9.8) |
| `src/server/session/Handlers.luau` | pure | one adapter per remote: guarded call → `SessionEvent` |
| `src/server/ports/*.luau` | impure edge | the real adapters for positions, line of sight and filtering (§9.6), each with a Studio check |
| `src/server/session/Session.luau` | pure | the composition root's logic: holds every piece of round state, routes events, returns effects (D22) |
| `src/server/session/Interpreter.luau` | pure over ports | maps each effect to exactly one port call |
| `src/server/RoundService.server.luau` | **impure driver** | builds the real ports, feeds events in, hands effects to the interpreter. Logic-free |
| `src/net/GameRemotes.luau` | pure, data | `SendPreset`, `Ping`, `Turn` declared through `Remotes.define` |
| `src/net/Transport.luau` | impure edge | the **only** `OnServerEvent:Connect` site: binds each declaration through `Wrapper.guard`; `sendTo` / `broadcast` for server-to-client payloads |
| `src/client/Theme.luau` | pure, data | `docs/wiki/design/tokens.md` implemented by token name, with a drift guard (`THEME-001`) |
| `src/client/models/*.luau` | pure | view models: data in, text/icon/colour/layout out |
| `src/client/views/*.luau` | impure | build and update Instances from a model. Studio-verified |
| `src/client/Main.client.luau` | impure | the client entry |

`src/server/facility/` is named for the game's word. `Instance` is Roblox's own
global type, so the generated thing is a **`Facility`**, never an "instance", in
any type name.

### 9.2 The Session, and where round state lives

All round state lives on the server in one value, owned by the driver and
replaced — never mutated — by each `Session.step`:

    SessionState = {
        round:      RoundState,        -- M1, unchanged
        assignment: Assignment?,       -- M2 ring, from AssignSeats
        facility:   Facility?,         -- generated once per round (D12)
        procedure:  ProcedureState?,   -- steps, instability, deadline, dark rooms
        channel:    ChannelState?,     -- active pings, recent presets, both logs
        positions:  { [PlayerId]: Vector3-like }, -- last plausible sample (§9.8)
    }

    Session.step(state, event, now) -> (SessionState, { SessionEffect })

Events are the phase machine's own plus `PositionsSampled`, and one per accepted
remote call (`PresetSent`, `PingRequested`, `TurnRequested`) — a remote handler
does nothing but build the event and call `step`.

**The order within one `step` is fixed**: the event is applied; the Procedure is
advanced on `Tick`; if it produced an outcome, that outcome is fed to the phase
machine as `RoundResolved` in the **same** step; then views are rebuilt and
diffed into replication effects. The phase machine's own precedence
(`RoundResolved` > quorum > clock, §3) is untouched.

**The round deadline belongs to the Procedure (D11).** Instability removes
seconds from the clock (`mechanics.md` §5), so the Procedure keeps
`deadline = roundStart + round_seconds − penalties` and resolves `lost(clock)`
itself. The phase machine's own `round_seconds` expiry stays as a backstop that
can never fire first, because penalties only subtract.

**Outcome vocabulary** (`mechanics.md` §5, G12): the `reason` the phase machine
records verbatim, and the trace and telemetry report.

| result | reason | when |
|---|---|---|
| `won` | `procedure_complete` | the finale commits while the clock is above 0 |
| `lost` | `clock` | the deadline is reached, including by a clock penalty |
| `lost` | `instability` | `instability_max` is reached |
| `no_contest` | `below_quorum` | M2, unchanged |
| `no_contest` | `generation_failed` | the generator exhausted `generator_attempts_max` (§9.3) |

When one event causes several, they resolve **win, then instability, then
clock** (`mechanics.md` §5). `unwinnable` has **no trigger in M3**: the Game
Designer withdrew the clock arm (a naive par would end rounds a good group could
still win) and the structural arm cannot occur while quorum holds
(`mechanics.md` §8). The phase machine still accepts it; nothing emits it.

### 9.3 The facility generator

    Generator.generate(assignment: Assignment, seed: number, tuning,
                       predicateOverride?, stagesOverride?) -> GenerateResult
    -- { kind = "facility", facility } | { kind = "failed", failures = { { attempt, invariant } } }
    -- facility = { layout, placement, steps, spawnRoom, par, attempt }   (GEN-004 Contract C-1)
    -- the two overrides are test seams (GEN-004 AC-3, AC-4); production passes nil

- **Generated after seats (D12)**, because `INV_finale` needs ring adjacency: the
  finale's two key classes must not be neighbours on σ when n ≥ 4.
- **Randomness**: attempt *i* (from 1) draws only from
  `Rng.fromSeed(seed):derive("instance"):derive("attempt-" .. i)`
  (`mechanics.md` §6.2), and inside an attempt each stage takes its own
  sub-stream — `"layout"`, `"machines"`, `"steps"` — so a change to one stage
  cannot move another's draws (D2). `"instance"` is the label §2 reserved.
- **Resampling**: the first attempt that satisfies every invariant is the
  facility. After `generator_attempts_max` failures the round resolves
  `no_contest / generation_failed`, and each attempt's failed invariant is
  logged. There is no hand-authored fallback facility.
- **Every invariant in `tuning.md`'s "Generator invariants" table is a named
  predicate** in the module that owns its stage, exported so a test can assert
  it per seed and a control can feed it a hand-built violating facility.
- **Par** is computed once, at generation, by `Par.luau`, with the canonical
  schedule exactly as `mechanics.md` §6.3 writes it, and is stored on the
  `Facility`. `INV_traversal` and the trace read it; nothing recomputes it.
- **The seed sweep** — at least 1,000 seeds at every generation-time n — is the
  real guarantee, and it reports first-attempt acceptance, which `tuning.md:
  generator_attempts_max` says what to do with.

`Facility` carries the layout, the machines (tag, key class, room, slot,
required setting), the steps and tracks, the finale pair, the spawn room, and
par. It is **never replicated whole**; clients see it only through §9.7.

### 9.4 The Procedure at run time

    Procedure.start(facility, now, tuning)                                  -> ProcedureState
    Procedure.turn(state, assignment, playerId, machineId, setting, now, positions) -> (ProcedureState, TurnResult)
    Procedure.tick(state, assignment, now, positions)                       -> (ProcedureState, Outcome?)

- A step is live when its position among its track's uncommitted steps is 0 —
  except the **finale, whose two steps go live together** once every ordinary
  step of both tracks is committed (`finale_live_together`, `mechanics.md` §3.2).
  A turn is judged against server state only.
- **Key class is read from the current `Assignment`**, so a key transferred by
  `Ring.withdraw` (SEAT-003) works without the Procedure knowing about
  disconnects.
- **A turn is either refused or evaluated** (`mechanics.md` §5, G12):
  - *refused, never penalised*: not the key holder, out of `turn_range_studs`, a
    committed machine, a resetting dial, an already-armed finale machine. No
    instability, no tone, no dial reset; the turner is told why.
  - *evaluated*: `committed`, `armed`, or rejected as `wrong_setting` or
    `not_live` (diagnostic, T13) at a cost of exactly one instability point; a
    failed finale attempt costs exactly one in every case.
- **Blackout** draws from the round seed's `derive("blackout")`, weighted as
  `tuning.md: blackout_selection` specifies, so which room goes dark is
  reproducible and cannot perturb the generator.

### 9.5 The channel

Four remotes, declared in `src/net/GameRemotes.luau` and nowhere else:

| Remote | Args (schema) | Legal phases | Send limit (refundable) | Attempt floor |
|---|---|---|---|---|
| `SendPreset` | `{ preset = integer(1, preset_count) }` — **no recipient field** (C9) | the union of the preset table's phases | `preset_rate_limit_seconds` | `channel_attempt_min_interval_seconds` |
| `Ping` | `{ kind = literal("setting","machine","doorway"), target = integer, setting = optional integer(1, dial_settings) }` | `Round` | `ping_rate_limit_seconds` | `channel_attempt_min_interval_seconds` |
| `Turn` | `{ machine = integer, setting = integer(1, dial_settings) }` | `Round` | `turn_rate_limit_seconds` | — |
| `AcceptRematch` | `{}` | `Post` | an engineering flood bound in `GameRemotes.luau` (the phase machine already counts one acceptance per player per round) | — |

**The rematch card is shown during `Post`**, driven by `RoundView.phase`,
because the phase machine records `RematchAccepted` only in `Post` and brief A4
puts the prompt in the post-round window. The machine's `PromptRematch` effect,
emitted on leaving `Post`, dismisses it. There is no lobby ready-up.

- **Only a send that is broadcast consumes the 10 s limit**
  (`tuning.md: channel_limiter_consumed_by`, G9). A ping refused for its target,
  a preset refused by its own phase list, and a preset whose filtering failed are
  not sends. The wrapper's rate stage therefore holds **two** limiters per
  remote: a non-refundable **attempt floor** checked first, and the **send
  limit**, which the handler can refund by **declining** the call (D18). The
  attempt floor is what keeps B4's anti-spam guarantee when refunds exist.
- **Rates come from `MechanicsTuning`, and their provenance is tested against
  `tuning.md`** through `tests/helpers/RateLimitSpec.luau`, which already reads
  both 10 s rows. The test compares the **declaration**, not a copy of the
  number.
- **Per-preset phase legality** is the handler's, not the wrapper's: the wrapper
  admits the union, `PresetSends` refuses a preset outside its own row and
  declines. One remote and one limiter per player spans the wheel, which is what
  C4 ("per send", across the whole wheel) requires (D17).
- **Filtering is a port** (`filter(playerId, text) -> (ok, text?)`, §9.6), called
  **once per send** (settled by `CHAN-001`, below). **Fail closed**: nothing is
  sent, the sender is told, and the call is declined.
- **Delivery route** (settled by `CHAN-001`, below): presets are broadcast by the
  server, already filtered, with their sender and sender position, for the
  in-world bubble and beacon; **each client** then also writes the chat line
  (C-13) itself, as a `TextChatService` system message labelled "system preset".
  The server cannot put a system message on anyone's screen.

#### 9.5.1 Filtering and the chat route — `CHAN-001`'s findings (2026-10-05)

Read from Roblox's documentation source, `Roblox/creator-docs` at `9f840b1`
(the published pages are generated from it). **Authority** is the API reference
and the creator guides; **corroboration only** is marked as such.

**The filter call (AC-1).** On the server, once per send:

    local result = TextService:FilterStringAsync(word, sender.UserId, Enum.TextFilterContext.PublicChat)
    local text = result:GetNonChatStringForBroadcastAsync()

- `FilterStringAsync(stringToFilter, fromUserId, textContext = PrivateChat)`
  ([API](https://create.roblox.com/docs/reference/engine/classes/TextService#FilterStringAsync)).
  `fromUserId` is the **sender's** `UserId`: a preset is filtered on the behalf
  of the player who sent it. `textContext` is `PublicChat`, the enum's value for
  text "visible to all players or a broad public audience"
  ([enum](https://create.roblox.com/docs/reference/engine/enums/TextFilterContext));
  the reference says it "does not impact the filtered result … and is only used
  to improve Roblox's text filtering", so it is correctness-neutral and set for
  honesty. The adapter maps the session's `playerId` to the `Player` and reads its
  `UserId`.
- The broadcast form is `TextFilterResult:GetNonChatStringForBroadcastAsync()`,
  "the text in a properly filtered manner for all users"
  ([API](https://create.roblox.com/docs/reference/engine/classes/TextFilterResult)).
  It is the **only** non-deprecated all-audience method: `GetChatForUserAsync` is
  deprecated and "returns an empty string". The docs do not reconcile the
  method's "non-chat" name with a line that is later shown in the chat window;
  the preset guideline's requirement ("All presets must go through
  `TextService:FilterStringAsync()`") is met either way, and this is the form
  the text-filtering guide prescribes for text "visible to all users in a game"
  ([guide](https://create.roblox.com/docs/ui/text-filtering)).
- **Both calls yield** (`FilterStringAsync` "always yields"; the result method
  is tagged `Yields`). The handler therefore runs off the wrapper's synchronous
  path or accepts the yield; `SLICE-006` decides which.
- **Failure modes.** `FilterStringAsync` "may throw if there is a service error
  … do not retry the request, as this method implements its own retry logic",
  and "currently throws if `fromUserId` is not online on the current server".
  The result method can also throw (the guide wraps it in `pcall`). The
  reference: "If it fails, do not display the text to any user." So the adapter
  wraps both in `pcall`, returns `(false, nil)` on any raise, and never retries.
  A filtered string may come back altered (hashed); what is broadcast is the
  returned string, never the table's word.

**The chat route (AC-2).** `TextChannel:DisplaySystemMessage(systemMessage,
metadata)` "Can only be used in a `LocalScript`, or in a `Script` with
`RunContext` of `Enum.RunContext.Client`. Messages are only visible to that
user and aren't automatically filtered or localized"
([API](https://create.roblox.com/docs/reference/engine/classes/TextChannel#DisplaySystemMessage)).
So:

- the server **cannot** display a system message to every client;
- each client calls `TextChatService.TextChannels.RBXGeneral:DisplaySystemMessage(line, "system_preset")`
  when the `PresetShown` broadcast arrives, which is the documented pattern for a
  system message ([chat window guide, "System"](https://create.roblox.com/docs/chat/chat-window#system));
- because the call does not filter, **only the server-filtered text** may reach
  it, which the broadcast already guarantees.

**The "system preset" label (C6).** The guideline requires "All UI of presets
must be properly labeled as **system preset** when displaying within chat"
([guidelines](https://create.roblox.com/docs/chat/preset-system-guidelines#requirements)).
It is written into the line itself (C-13's model), and the `metadata` argument
(`"system_preset"`) lets a `TextChatService.OnIncomingMessage` callback restyle
those lines without parsing them — the guide's own pattern for system messages
identified by `Metadata`.

**Rich text.** "The default `TextChatService` UI relies on rich text to format
and customize how messages are displayed"
([guide](https://create.roblox.com/docs/chat/in-experience-text-chat#customize-message-display));
`<b>` and `<font face="…">` are both supported tags
([rich text](https://create.roblox.com/docs/ui/rich-text#supported-tags)). The
documented chat examples put rich text in `PrefixText` and `Text` through
`OnIncomingMessage`; none states in so many words that a `DisplaySystemMessage`
body is parsed as rich text. C-13 therefore keeps its markup and its Studio
check (SC-C1, `HUD-004`) is where the body's rendering is observed.

**Escaping a player name.** Rich text's five escape forms: `<` → `&lt;`,
`>` → `&gt;`, `"` → `&quot;`, `'` → `&apos;`, `&` → `&amp;`
([rich text, "Escape forms"](https://create.roblox.com/docs/ui/rich-text#escape-forms)).
`&` is replaced **first**, or the other four's ampersands are escaped twice.

**Per send, not once per session (AC-3).** Decided by the API reference: "This
method should be called once each time a user submits a message"
([FilterStringAsync](https://create.roblox.com/docs/reference/engine/classes/TextService#FilterStringAsync)).
A preset send is a user submitting a message, so a cached result per sender per
session is not permitted. This matches the stricter reading `CHAN-004` already
held.

**Open risk — a Roblox preset service.** Roblox staff announced on 2026-03-26:
"In June, we'll add support for a Roblox-defined preset service … Once
released, all creators will need to migrate their own systems to using
Roblox's preset service", and "We advise against building your own system now,
unless it's necessary for your experience to function"
([announcement](https://devforum.roblox.com/t/march-26-2026-an-update-on-our-age-check-to-chat-fast-follow-roadmap/4539685)).
The Spring 2026 roadmap lists "Customizable Chat Presets across age groups" —
"Integrate tooling into TextChatService for creators to build and customize
tools for chat presets" — for mid-2026
([roadmap](https://devforum.roblox.com/t/creator-roadmap-2026-spring-update/4625473)).
**As of `9f840b1` the API reference contains no preset class, enum or guide**
beyond the guidelines page, so nothing has shipped to build on. The design is
kept migratable by the existing seams: the preset table is data
(`Presets.ALL`), filtering is a port, and the chat line is a client model; the
remote and the in-world bubble and beacon are game state the service would not
replace. Whether to build `CHAN-004` now or wait is a product decision recorded
in `CHAN-001`'s `## Notes`.

**Corroboration only.** A 2026 DevForum answer recommends `DisplaySystemMessage`
for a preset wheel's chat line "for consistency"
([thread](https://devforum.roblox.com/t/is-preset-chat-must-be-recived-with-displaysystemmessage/4542175));
the brief's "forum-reported, effective 2026-01-09" claim that system messages
are *the* sanctioned route was **not found** in any official page, and nothing
official requires the chat route — the guideline only requires the label *when*
presets display within chat.
- **Pings carry no text** and are broadcast with the sender's id; the client
  colours them. A setting-ping deliberately reveals that setting to everyone —
  that is the verb (`loop.md` §1.1), not a leak.

### 9.6 Ports — the only way the runtime reaches the pure core

| Port | Real adapter (driver) | Headless stand-in | Studio check |
|---|---|---|---|
| `clock` | `Clock.real()` | `Clock.manual` | — (M1) |
| positions | sample each character's root part each tick | a table | positions match where the avatars stand |
| `lineOfSight(from, to) -> boolean` | `workspace:Raycast` against the blockout | a predicate | a wall blocks a ping; a doorway does not |
| `filter(playerId, text)` | `TextService:FilterStringAsync(text, UserId, PublicChat)` + `GetNonChatStringForBroadcastAsync()`, both under `pcall`, never retried (§9.5.1) | a function | a filtered preset is delivered; a forced failure is not |
| transport | `Transport` over `RemoteEvent`s | a recording fake | four clients each receive only their own secrets |
| telemetry | `Sink.noop()` in M3 (the live sink is M5) | `Sink.recording()` | — |

A port's real adapter is the only code in M3 that is not headlessly tested, and
each one has a named Studio check in the story that builds it.

### 9.7 Replication — what each client is sent

| Payload | Built by | Sent with | Cadence |
|---|---|---|---|
| `SeatView` (`PublicSeatView`, M2) | `Projection.forPlayer` | `sendTo(p)` | on seat assignment and on a ring change |
| `LensView` | `Projection.lensFor` | `sendTo(p)` | when its contents change |
| `TurnCues` | `Projection.turnCuesFor` | `sendTo(p)` | when its contents change |
| `TurnResult`, `PresetFailed`, `PingRefused` | the Procedure / the channel | `sendTo(p)` | per refused or evaluated call, to its caller only |
| `RoundView` | `RoundView.public` | `broadcast` | when its contents change, and at least once a second while the clock runs |
| `FacilityView` | `RoundView.facility` | `broadcast` | once per round, entering `Round`: the layout and each machine's static public facts |
| `PresetShown` | the channel | `broadcast` | per event; active pings travel inside `RoundView` |
| `TraceView` | `Trace` | `broadcast` | once, entering `Post` |

- **Secrets go by `sendTo` only (D13).** A per-player payload is never broadcast
  and never written to an Attribute or Value object: `Player` instances replicate
  to every client, so an attribute there is public. `Transport` offers no API
  that could broadcast a per-player payload type; a test enumerates the payload
  kinds and asserts each one's route.
- **The lens view is gated on the server by class, range, line of sight and a
  lit room (D14).** It holds required settings only for machines of `λ(p)`
  within `lens_read_range_studs` in sight and not in a dark room. Whether the
  player's light is *pointing at* the machine is presentation: the client shows
  the glow only then.
- **Public world facts go to everyone (D15)**: each machine's tag, key class,
  current dial, live lamp, committed state and partner lamp; dark rooms; active
  pings; recent presets; the phase and the deadline; the progress bar. None is a
  secret under `roles.md` §6. "Readable only in person" is enforced by rendering
  (light, range, darkness), not by replication — recorded as a cost: an exploited
  client can see public lamps from afar. It cannot see a required setting.
- **The progress bar is `{ committed, total }` inside `RoundView`**, never in the
  per-player views (`roles.md` §6), and its type has no other field
  (`mechanics.md` §9).

### 9.8 Positions are claims

A character's position is owned by its client's physics, so it is a claim (B4).
The driver samples positions server-side each tick; `Session` accepts a new
sample only if it is **plausible** — reachable from the previous accepted sample
at no more than `walk_speed_studs_per_second` (the platform default, which the
game does not change) times a tolerance over the elapsed time — and otherwise
keeps the previous one. A server placement (spawn, round start) resets the
baseline. Range checks (lens, ping, turn, partner lamp) read only accepted
samples, and **every range in M3 is a horizontal (x, z) distance**: the facility
has one storey, and a machine's position is its floor point (`GEN-002`), so a
3-D distance would shorten every range by the character's root height. The tolerance is an engineering constant in
`src/server/session/Positions.luau`, justified in `VIEW-004`; it bounds a trust
check and is deliberately not game tuning.

### 9.9 The client

`src/client/` imports only `@shared` and `@net` (§1). Everything it shows arrives
as one of §9.7's payloads; it computes nothing a server rule depends on. Its logic
is split so the gates can see it:

- **models** (pure, tested under `tests/client/`): a payload plus local input
  state in, a description out — which text, which icon key, which design token,
  which arrow angle, which wheel entries are disabled and why.
- **views** (impure): turn a model into `ScreenGui` / `BillboardGui` /
  `SurfaceGui` instances. Verified by a named Studio check, never by a Lune test
  of `@lune/roblox`'s datamodel (§1, "The pure core").

Tokens, components and the accessibility floor are `docs/wiki/design/`'s; a
`src/client/Theme.luau` implements the tokens by their names there, the way
`Tuning.luau` implements `tuning.md`.

### 9.10 Tuning for M3

`tuning.md` §2–§4 land in **`src/shared/MechanicsTuning.luau`**, not in
`Tuning.luau` (D19): ROUND-002's frozen guard asserts `Tuning.luau` carries §1
and §5 exactly. A second guard (`TUNE-001`) reads §2–§4 by name and compares
every numeric, boolean and `= other` row to the module. Rows whose value is a
rule rather than a constant (for example `key_classes`, `actuators_per_class`,
`spawn_room`, `blackout_selection`, `channel_limiter_consumed_by`,
`hud_round_clock_form`, `ping_budget_per_player`) and the invariant table are
named in the guard as not-constants, so that a new row is either in the module
or explicitly excluded — never silently ignored.

### 9.11 The trace

`Trace.compute(facility, logs, outcome) -> TraceView` is a pure function of the
generated facility, the ping, preset and actuation logs, and the outcome
(`mechanics.md` §7). `TraceView`'s type has **no player field**: T14 (names
steps, not players) is structural, not a formatting choice.

### 9.12 How M3 is verified

| Claim | Evidence | Gate |
|---|---|---|
| each rule in `mechanics.md` §9's left column | a Lune test per rule, with controls | `unit` |
| the pieces compose into a round | **a headless full round**: four scripted players win a generated facility, and a second script loses it to instability (`SLICE-005`) | `unit` |
| no client can read another's secret | property tests over `lensFor`, `turnCuesFor`, `RoundView`, and `Transport`'s routing | `unit` |
| the place builds, the scripts type-check | the existing gates | `build`, `typecheck` |
| it works in Roblox | named Studio checks, run by the operator and pasted into the story | none — recorded, never assumed |
| four humans finish a round | the M3 definition of done (brief §0c R2), run by the operator | none — recorded |

`src/client/**` joins the `unit` gate's `covers` list with the first story that
puts a model there (`THEME-001`), so a client model read only by optional gates
fails the run (`quality-gates`).

---

## 10. Deliberately not decided here

Listed so their absence reads as a boundary and not an oversight.

- **The tone of the dark** (T15): spooky or calm. M4, with the Lead Designer.
- Lighting, fog, audio mixing, camera: M4. M3 names audio cues; it does not mix
  them.
- **Creator Store assets.** Brief M3 names "Creator Store parts plus generated
  blockout geometry"; M3 plans blockout only, because an asset is a dependency
  (B1 #5) and its value is aesthetic (M4). Open for the operator.
- Persistence: DataStore budgets, ordered stores, throttling, retry (M5). M3's
  telemetry sink on a live server is `Sink.noop()`.
- Progression, monetisation, purchase validation (M5); A5 days 2–7 (open, Lead
  PO, before M5).
- Publishing and Open Cloud (M6, operator-gated).
- Voice of any kind: amendment 3, and §0d #15's posture needs no voice feature.
