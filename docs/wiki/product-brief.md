# Project Brief: Asymmetric Round-Based Multiplayer (Roblox)

> Title amended 2026-09-15. Was "Asymmetric Voice-First Multiplayer (Roblox, 17+)";
> voice-first and 17+ gating are under amendment — see §0b before relying on either.

**Audience for this document:** an agentic coding agent operating inside a general-purpose
development harness, plus the human operator supervising it.

**Status:** Greenfield. No code exists yet.

---

## 0. How to use this document

This brief is the standing context for the project. Load it at the start of every session.
**Read §0b (Operator amendments) first — it overrides Part A where they conflict.**

It is deliberately split into:

- **Part A — Product.** What we are building and why. Do not renegotiate this without the operator.
- **Part B — Engineering.** Stack, repo layout, verification gates, and the rules you must follow.
- **Part C — Milestones.** Ordered, each with an explicit definition of done.
- **Appendix — Harness profile.** The Roblox extension spec for the general dev harness.

If a decision is not covered here, prefer the option that is **easier to verify headlessly** and
**cheaper to delete**.

---

---

## 0b. Operator amendments — 2026-09-15

**These override Part A where they conflict. Read them before acting on any
constraint below.** The original text is left intact deliberately: the reasoning
in Part A is still the best record of *why* the shape was chosen, and knowing
what was traded away matters when these decisions are revisited.

| # | Amendment | Overrides | Status |
|---|---|---|---|
| 1 | **Minimum lobby size is 4, not 6.** Target band and cap to be re-derived. | A4 ("Minimum 6 players") | Decided |
| 2 | **No 17+/age-verification gating for v1.** Ship at a standard maturity label. | A2 constraint #1; A6 "18+ SKU" rationale | Provisional — see below |
| 3 | **Proximity voice is not a v1 requirement.** | A3 pillar 3; A1 "proximity voice" | Provisional — see below |
| 4 | Brief lives at `docs/wiki/product-brief.md`, harness convention, not `docs/roblox-project-brief.md`. | B3 | Decided |
| 5 | **`coverage` gate stays unconfigured; the mutation gate replaces it.** Lune can instrument via `coverageLevel` but exposes no way to read coverage back. Record in `docs/wiki/stack.md` at plan-product. | B5 | Decided |
| 6 | **Genre is re-opened.** The hidden-role social-deduction shape was derived from constraint #1 and the voice pillar, both now amended. | A1, A3, A4 | Open |
| 7 | **Communication model: structured vocabulary (B) over an observable world (C), with `TextChatService` (A) as optional later enrichment.** Binding architectural rule: **the game must be fully playable with zero free-form communication.** Chat, if added, is a bonus for players who have it — never a dependency. | A3 pillar 3 | Decided |
| 8 | **Genre decided: candidate B — asymmetric-information co-operative.** The constrained channel *is* the puzzle: players hold different pieces of what is needed and must coordinate through a lossy structured vocabulary. Decided by the operator (ryanczhang7), 2026-09-15, from the five candidates in `docs/wiki/game/loop.md` §3. Supersedes the hidden-role social-deduction shape in A1/A3/A4. | A1, A3, A4; amendment 6 | Decided |
| 9 | **Cooperative, not competitive** (T4). Players win or lose together; progression is shared/seasonal rather than a ranked ladder. Decided by the operator, 2026-09-15. Consistent with amendment 8 — B is inherently co-operative. Supersedes A5's ranked ladder and the competitive framing of M5. | A5, M5 | Decided |
| 10 | **T3 resolved as a consequence: "recognising who is who" is NOT a mechanic.** Candidate B does not need it (`loop.md` §4). The no-art-budget constraint still holds; the genre commitment laundered into A3 pillar 1 is withdrawn. | A3 pillar 1 | Decided |
| 11 | **`players_max` is 6, not 16** — derived from channel contention in `docs/wiki/game/tuning.md`, not preference. A4's 8–12 target and cap of 16 came from hidden-role faction ratios that amendment 8 removed, so they are **withdrawn, not scaled**. Consequences: M6's lobby-fill risk gets strictly easier, private servers become the natural venue, and **M3's "6 humans complete a round" becomes 4**. | A4, M3, M6 | Open — Lead PO to ratify |
| 12 | **A5's day-1 promise conflicts with the design's own numbers.** `lobby_seconds` 60 + `round_seconds` 480 = 9 minutes against A5's "first round must complete inside 8 minutes of joining". One must move. Recommendation on record: shorten `round_seconds` to 420 rather than weaken a tracked discovery signal. Not decided. | A5 | Open — operator |
| 13 | **Out-of-band voice is unenforceable and was missed in the first design pass.** Four players on a voice call defeat the *expressive* axis of the constrained channel entirely. B survives on the *attentional* axis (ephemeral signals, one serial stream, reading competes with looking), which voice does not repair. `docs/wiki/game/playtest.md: P-V` tests this and is paper-runnable; **it bears on amendment 8, which was decided before this was known, and should run before M3.** | amendment 8 | Open — playtest pending |

### What amendment 1 buys

Lobby fill was the highest-risk assumption in the plan (see M6). A 4-player floor
roughly halves the concurrent-player density needed for a round to start, and it
is the single cheapest de-risking move available. It has design consequences that
must be re-derived, not assumed: a hidden faction at ~25% of 4 players is one
player, which changes the social dynamic qualitatively — one hidden player cannot
coordinate, cannot be outvoted incorrectly in the same way, and a single early
wrong vote ends the round. **Re-derive the faction ratio and round length for a
4-player floor rather than scaling the existing numbers.**

### What amendments 2 and 3 cost — flagged, not resolved

These two are marked provisional because together they remove the load-bearing
element of A2 and A3, and the brief does not currently say what replaces it.

- **Constraint #1 collapses.** The entire justification for the 18+ audience was
  the DevEx rate differential. Without age gating, that rationale is gone — which
  is fine, but it means the *audience* is now unspecified rather than
  deliberately chosen. A2 needs a replacement constraint.
- **Pillar 3 collapses.** "Every round is a story told out loud" was the primary
  interface. Without voice, the game needs another accusation and negotiation
  channel — text chat with its own constraints, a ping/marker system, a
  structured accusation UI — and that is a *design* problem, not a smaller
  version of the voice one. Social deduction without a communication channel is
  not a quieter game; it is a different game.
- **A6 is partly invalidated.** "Private Server — highest-value 18+ SKU" was
  priced on the 18+ rate. Private servers remain a good SKU; the stated rationale
  no longer holds.
- **What is unaffected:** R15 avatars, the no-character-art budget, darkness and
  audio carrying the aesthetic, server authority, short rounds, and every one of
  the M0–M2 engineering milestones. The trust boundary does not care who is
  playing.

**These two amendments do not block M0–M2.** The stack, the gates, the round
state machine and the trust boundary are identical either way. They must be
resolved before M3 (vertical slice), because M3 is where the communication
channel gets built.

### Platform findings — checked against Roblox docs, 2026-09-15

Three facts that change the communication decision, and were not in the original
brief:

1. **All text-based player-to-player communication must route through
   `TextChatService`.** This is a Community Standards requirement, not a
   convenience. A custom free-form text channel over a RemoteEvent is not a
   permitted design. `TextChatService` filters automatically, so developers do
   not implement filtering — but they also cannot opt out of it.
2. **Chat now requires an account-level age check, globally.** Users who have not
   completed one are prompted and cannot chat until they do. This applies to
   text chat, not only voice.
3. **Chat is segmented into age bands** — under 9, 9–12, 13–15, 16+ — and users
   communicate with their own band plus adjacent ones, with wider access for
   13+ "Trusted Connections".

**Consequence for amendment 3.** Dropping voice in favour of free-form text does
*not* avoid the verification problem — it inherits it. Both channels require an
age check and both are age-band segmented. In a 4-player lobby, two players who
cannot hear each other break the round outright, and that is now a platform
property rather than a design choice.

The channel that escapes this entirely is one carrying **no user-generated
text**: a fixed, developer-authored vocabulary — pings, markers, canned phrases,
a structured accusation UI — is game state, not communication, and sits outside
the chat surface. This is the strongest argument for a structured channel, and it
is an argument the original brief could not have made.

*Account-level age checks are a separate system from an experience's maturity
label. Amendment 2 concerns the maturity label and does not affect any of the
above.*

### Still unverified

Nothing in this brief's Roblox platform claims has been checked against current
Roblox documentation — DevEx rates, maturity labels, voice-verification
requirements, private-server mechanics. With amendments 2 and 3 in place, most of
those claims are no longer load-bearing, but A6 still prices SKUs against them.
Verify before M5.

---

## 0c. Lead PO ratifications — `/plan-product` pass, 2026-09-15

The Game Designer's second pass ended with a list under `loop.md` §5, "Still not
mine to answer — for the Lead PO". This section closes the ones that are mine,
and says who owns each one that is not. **It has the same authority as §0b and
overrides Part A where they conflict.**

| # | Ratification | Overrides | Status |
|---|---|---|---|
| R1 | **Amendment 11 is ratified.** `players_min` = 4, `players_max` = 6. A4's "target 8–12, cap 16" is **withdrawn, not scaled** — it was derived from hidden-role faction ratios that amendment 8 removed. | A4; amendment 11 | Decided |
| R2 | **M3's definition of done becomes "4 humans complete a full round end-to-end in Studio"**, a consequence of R1. | M3 | Decided |
| R3 | **A3 pillar 1 is rewritten** to: *"The avatar is the character — it is the only character art this project has, and that is a budget decision (A2 #3)."* The second clause, "recognising who is who is a core mechanic", is **withdrawn**: it was a design commitment presented as a consequence of a budget constraint (`loop.md` §4), and amendment 10 already withdrew it. Identity is carried by signal attribution, which works in a dark room and needs no art. | A3 pillar 1 | Decided |
| R4 | **A5's seasonal ranked ladder and M5's competitive framing are withdrawn** per amendment 9. Progression is shared and seasonal. The friend-group leaderboard survives as co-play reinforcement; the ranked placement does not. A5's days 2–7 (daily objectives, first-win-of-day, **role unlock cadence**) must be re-derived against a co-operative shape — and `roles.md` §5 says "more roles" is not an option available to it, because there are no roles to unlock. | A5, M5 | Decided; the days 2–7 re-derivation is **open, owner: Lead PO, before M5** |
| R5 | **Private servers are retained as an SKU, with the rationale replaced.** A6 priced them on the 18+ DevEx rate, which amendment 2 removed. The replacement rationale is stronger and comes from the design: at a 4–6 band with a retention thesis built on a *specific group* accumulating conventions over weeks (`loop.md` §1.4), a private server is the natural venue rather than an upsell. | A6 | Decided |

### Still open, with owners

Recorded here so that no later agent reads silence as settlement.

| Question | Owner | Blocks |
|---|---|---|
| **Amendment 12** — `lobby_seconds` 60 + `round_seconds` 480 = 9 minutes against A5's "first round completes inside 8 minutes of joining". The Game Designer's recommendation on record is to shorten `round_seconds` to 420 rather than weaken a tracked discovery signal. | **Operator** | Nothing in M0–M2 — the phase machine is parameterised by these constants and does not care what they are. Blocks any claim that A5's day-1 promise is met. |
| **A2's replacement audience constraint.** Amendments 2 and 3 removed the DevEx rationale, so the audience is now *unspecified* rather than deliberately chosen. It matters more under candidate B, not less: B's difficulty is cognitive and its retention thesis assumes groups that will invent conventions over weeks. | **Operator** | M3. Rule complexity, session length and T5's posture all depend on it. |
| **T5** — posture toward out-of-band voice. `playtest.md: P-V` is paper-runnable and **bears on amendment 8, which was decided before it was known.** | **Operator**, informed by P-V | M3 |
| **T6, T7, T9** — sender's room, memory load, seasonal vocabulary rotation. | **Operator** | M3 (T6, T7); M5 (T9) |
| **T8** — whether an ordered stream of 16 developer-authored tokens is a moderation surface under current Community Standards. A fixed vocabulary is game state, not communication; that reading is sound for pings and weaker for an arbitrary-length ordered stream a determined group could use as a cipher. | **Lead PO**, to verify against current Roblox documentation | M3 |
| **A6's SKU pricing against current DevEx rates and maturity labels.** Nothing in this brief's Roblox platform claims has been checked against live documentation. | **Lead PO** | M5/M6 |

### Scope of this planning pass

`/plan-product` was run **scoped to M0–M2 only**, and the artefacts it produced
(`docs/wiki/stack.md`, `docs/wiki/architecture.md`, `docs/backlog/**`) stop there
deliberately.

The reason is the Game Designer's finding, accepted: **M0–M2 are
genre-independent.** The toolchain, the gates, the
`Lobby → Assignment → Round → Resolution → Post` phase machine and the trust
boundary are identical under every genre candidate in `loop.md` §3 — which is
demonstrated by the fact that they survived the genre *changing*, in amendment 8,
without a line of them moving.

M3 onward is not genre-independent. It depends on every open question in the
table above.

**The backlog therefore ends at M2, and the end of the backlog is not the end of
the product.** `architecture.md` §0 says the same thing in the place an
implementing agent will actually be reading.

---

# Part A — Product

> **A1 and A3 pillar 1 below are superseded.** A1 describes the hidden-role
> social-deduction shape that amendment 8 replaced; the current one-line pitch is
> `loop.md` §0. A3 pillar 1's second clause is withdrawn by R3. Both are kept
> because the reasoning is the record of what was traded away.

## A1. One-line pitch

A round-based asymmetric multiplayer game for verified 17+ players, where a small hidden faction
works against an uninformed majority inside a compact, dark, atmospheric map, resolved through
proximity voice, evidence, and a server-authoritative vote.

## A2. Why this shape (the constraints that produced it)

These are binding constraints, not preferences. Every design decision is checked against them.

| # | Constraint | Consequence |
|---|---|---|
| 1 | **Target verified US 18+ spend** | Qualifies for the $0.0054 DevEx rate vs $0.0038 standard (+42%). Voice-first design self-selects for age-verified users. Requires R15 avatars. |
| 2 | **Optimise for 28-day retention and intentional co-play** | Roblox's Recommended For You now measures day 1, days 2–7, and days 8–28 separately, with co-play as the headline signal. Design for repeat sessions with the *same* people. |
| 3 | **Minimise art surface, especially anything animated or organic** | Characters are player R15 avatars. No custom rigs, no skinning, no bespoke character animation. Environment is modular hard-surface. Atmosphere carried by lighting + audio. |
| 4 | **Code-dominant, not content-dominant** | Difficulty must live in systems (state machines, authority, matchmaking, ranking), which an agent can build and verify, not in asset volume, which it cannot. |

**Anti-goals.** Do not propose, and reject if suggested: custom humanoid characters; bespoke
character animation; open-world scope; large prop libraries requiring style consistency across
100+ assets; first-person weapon systems; any pay-to-win mechanic; any idle/tycoon/"steal-a-X"
loop.

## A3. Design pillars

1. **The avatar is the character.** Recognising who is who is a core mechanic. This is why we
   have no character art budget and it is a feature, not a limitation.
2. **Darkness does the work.** Lighting, fog, and audio carry the aesthetic. Mesh fidelity is
   deliberately low-priority and largely invisible.
3. **Every round is a story told out loud.** Proximity voice is the primary interface. Silence,
   interruption, and accusation are mechanics.
4. **The server is the only source of truth.** See B4. This is a competitive social game; the
   entire product dies the day it is exploitable.
5. **Short rounds, long seasons.** A round is 6–10 minutes. Progression is measured in weeks.

## A4. Core loop

- **Lobby** (60s) — players gather, socialise, ready up. Minimum 6 players, target 8–12, cap 16.
- **Assignment** — roles distributed server-side. Hidden faction ~25% of lobby.
- **Round** (5–8 min) — objectives, movement, proximity voice, evidence generation.
- **Resolution** — server-authoritative vote, reveal, scoring.
- **Post-round** (30s) — XP, season progress, rematch prompt with the same lobby.

The rematch prompt is a **co-play retention mechanic** and is not optional. It is the highest-value
thirty seconds in the product.

## A5. Retention architecture

- **Day 1:** first round must complete inside 8 minutes of joining. First-play bounce is a tracked
  discovery signal — a player who leaves before a round resolves is a direct ranking penalty.
- **Days 2–7:** daily objective set, first-win-of-day bonus, role unlock cadence.
- **Days 8–28:** seasonal ranked ladder with visible placement, cosmetic case cadence, and a
  friend-group leaderboard (co-play reinforcement).

Instrument all three buckets separately from day one. See B6.

## A6. Monetisation (design now, implement in M5)

All SKUs must be cosmetic, convenience, or social. **Nothing that affects round outcome.**

| SKU | Type | Rationale |
|---|---|---|
| Season Pass | Developer Product, recurring per season | Recurring, aligns with 8–28 day retention |
| Cosmetic cases / role flair | Developer Product | The avatar is the canvas; players stare at each other all round |
| Private Server | Roblox private server | **Highest-value 18+ SKU.** Recurring Robux, qualifies for the 18+ rate, ideal for adult friend groups |
| Lobby customisation | Game Pass | One-time, social display |

Tier passes at 3–5 price points. Do **not** ship rewarded video or immersive ads before M6;
immersive ads require 2,000 unique monthly visitors anyway.

---

# Part B — Engineering

## B1. Non-negotiables

1. **Never write authoritative logic on the client.** See B4.
2. **Never commit code that does not pass the full gate suite** (B5).
3. **Never use the Studio MCP `run_code` tool as the primary development channel.** It is for
   inspection and playtest verification only. Source of truth is the filesystem.
4. **Never point MCP at a published production place.** The MCP server grants third-party tools
   read and write access to the open place.
5. **Ask the operator before** publishing, changing monetisation, changing maturity settings, or
   adding any dependency not already in the toolchain manifest.

## B2. Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | Luau, `--!strict` in every file | No exceptions. Strict mode is a gate. |
| Toolchain manager | Rokit | Pins every tool version. Committed. |
| Sync | Rojo | Filesystem is source of truth; Studio is a viewport. |
| Packages | Wally | Lockfile committed. |
| Headless runtime | Lune | **The critical piece.** Enables tests + build on Linux CI with zero Roblox credentials. |
| Types / analysis | luau-lsp | Driven by `rojo sourcemap --watch` output. |
| Lint | Selene | |
| Format | StyLua | |
| Deploy | Open Cloud API | Scripted, gated behind operator approval. |
| Studio bridge | Roblox official `studio-rust-mcp-server` | Optional outer loop only. Tools: `run_code`, `insert_model`. |

Do not introduce roblox-ts. The TypeScript indirection costs more in agent confusion than it buys.

## B3. Repository layout

```
.
├── CLAUDE.md                  # agent standing instructions -> points here
├── rokit.toml                 # pinned toolchain
├── wally.toml / wally.lock
├── default.project.json       # Rojo
├── selene.toml
├── stylua.toml
├── src/
│   ├── server/                # authoritative. Round state machine, roles, voting, scoring
│   ├── client/                # presentation ONLY. Input capture, UI, camera, audio
│   ├── shared/                # types, constants, pure functions, validation schemas
│   └── net/                   # remote definitions + server-side validation wrappers
├── tests/                     # Lune unit tests. Mirrors src/ structure
├── lune/
│   ├── check.luau             # runs every gate
│   ├── test.luau
│   ├── analyze.luau
│   └── build.luau             # headless .rbxl build
└── docs/
    ├── roblox-project-brief.md  # this file
    └── decisions/               # one short ADR per non-obvious choice
```

## B4. The trust boundary (read this before writing any networking code)

Roblox clients are fully hostile. Exploiters can call any RemoteEvent with any arguments, read any
value replicated to them, and modify any LocalScript.

**Rules:**

- Role assignment, vote tallying, win conditions, and scoring live on the server and are never
  replicated to clients that shouldn't know them. A hidden role must not exist in any client's
  replicated state.
- Every RemoteEvent handler validates: sender identity, argument types, argument ranges, rate
  limit, and whether the action is legal in the current round phase.
- Every remote gets a server-side validation wrapper in `src/net/`. No raw
  `OnServerEvent:Connect` in `src/server/`.
- Client-supplied position, timing, and target selection are **claims**, not facts. Re-derive or
  sanity-check server-side.
- Never validate a purchase client-side.

**This is the highest-risk area for agent-generated code.** Generated Luau is prone to trusting
remote arguments. Every remote handler requires a written test in `tests/net/` asserting that
malformed, out-of-phase, and rate-exceeding calls are rejected.

## B5. Verification gates

`lune run check` must pass before any commit. It runs, in order:

1. `stylua --check src tests lune`
2. `selene src tests`
3. `rojo sourcemap default.project.json --output sourcemap.json`
4. `lune run analyze` — strict luau-lsp type analysis, zero errors
5. `lune run test` — unit tests, zero failures
6. `lune run build` — headless place build succeeds

**This is the agent's inner loop.** Do not report a task complete on the basis of reading the code.
Run the gates, read the failures, iterate. If a gate cannot run, stop and tell the operator rather
than proceeding blind.

Studio/MCP verification is a **separate, later, human-initiated step** for things gates cannot
catch: readability on a 5-inch screen, whether the round feels tense, whether audio mixing works.

## B6. Telemetry (build in M2, not later)

Emit structured events for: join, first-round-complete, round-complete, bounce-before-resolution,
rematch-accepted, session-end, day-N-return, co-play-with-known-player, purchase.

Map these directly onto the discovery buckets: D1, D2–7, D8–28. First-play bounce and intentional
co-play are the two you will tune hardest against.

---

# Part C — Milestones

Each milestone ends with `lune run check` green and a written summary in `docs/decisions/`.

### M0 — Harness and skeleton
Rokit manifest, Rojo project, all six gates wired and passing on an empty-but-valid project.
Empty place builds headlessly. CI runs on push.
**Done when:** a deliberately introduced type error fails the gate suite and nothing else does.

### M1 — Round state machine
Server-authoritative phase machine: Lobby → Assignment → Round → Resolution → Post. Pure,
fully unit-tested, no rendering, no remotes. Time-driven transitions with deterministic tests.
**Done when:** the full round lifecycle is exercised by tests with no Roblox runtime involved.

### M2 — Networking, trust boundary, telemetry
Remote definitions with validation wrappers. Role assignment (server-only visibility). Vote
submission and tally. Rate limiting. Telemetry event emission.
**Done when:** every remote has an adversarial test asserting rejection of malformed, out-of-phase,
and flooded calls.

### M3 — Playable vertical slice
One map (modular, hard-surface, built from Creator Store parts plus generated blockout geometry).
Proximity voice wired. Minimal UI: role card, objective, vote panel. R15 avatars only.
**Done when:** 6 humans can complete a full round end-to-end in Studio.

### M4 — Feel pass
Lighting, fog, audio, camera. This is where the aesthetic is actually produced. Expect this to take
longer than M3 and to be the least agent-automatable milestone.
**Done when:** the operator signs off on atmosphere. No gate can judge this.

### M5 — Progression and monetisation
XP, seasonal ladder, role unlocks, daily objectives. Cosmetic SKUs. Private servers. Season pass.
Purchase validation server-side, with tests.
**Done when:** a purchase cannot be spoofed by a client, proven by test.

### M6 — Soft launch
Publish 17+. Seed CCU deliberately — social games are worthless below a lobby-fill floor, and new
games face an unresolved cold-start question under the 28-day discovery window. Monitor
Creator Analytics → Acquisition → Home Recommendations weekly; developer reports (unconfirmed by
Roblox) describe some games losing 70–80% of Home impressions during algorithm tests.
**Done when:** D1 and D7 return rates are instrumented and trending, and lobbies fill without seeding.

---

# Appendix — Harness profile spec

**Decision: extend the general harness with a Roblox profile. Do not fork it.**

Nothing Roblox-specific is architectural. It decomposes into four kinds of content the harness
already knows how to consume:

```
profiles/roblox/
├── toolchain.toml         # Rokit pins, install bootstrap
├── gates.yaml             # the six commands in B5, with expected exit codes
├── context/
│   ├── luau-idioms.md     # strict mode, type patterns, common API shapes
│   ├── trust-boundary.md  # B4, expanded, with worked examples
│   ├── datastore.md       # request budgets, ordered stores, throttling, retry patterns
│   └── perf.md            # mobile targets; ~80% of Roblox sessions are mobile
├── mcp/
│   └── studio.json        # official studio-rust-mcp-server registration (opt-in, dev places only)
└── deploy/
    └── open-cloud.luau    # publish script, requires operator approval
```

**The one thing to verify in the general harness before starting.** Roblox punishes any harness
lacking a true inner loop — run a verification command, read the failure, iterate — because the
naive Roblox agent workflow is firing `run_code` into Studio and hoping. If the harness does not
already do gate-driven iteration, fix that generally. It is a gap on every stack, not a Roblox one.

**What makes this tractable:** Lune. With a headless Luau runtime, type checking, linting, tests,
and place builds all run on Linux CI with no Roblox credentials and no GUI. From the harness's
point of view this becomes an ordinary compiled-language project, and Studio + MCP demote to an
optional outer loop for visual and playtest verification only.

**Escalate to the operator** for: publishing, monetisation changes, maturity-rating changes, new
dependencies, any MCP session, and anything touching the trust boundary that you are not fully
confident in.
