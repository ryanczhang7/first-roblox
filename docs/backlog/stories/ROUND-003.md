---
id: ROUND-003
title: A round advances through all five phases on an injected clock
slug: a-round-advances-through-all-five-phases
epic: EPIC-01
type: feature
status: done
phase: DONE
branch: story/ROUND-003-a-round-advances-through-all-five-phases
depends_on: [ROUND-001, ROUND-002]
required_gates: []
---

## Context

The walking skeleton of the game's server. `Lobby → Assignment → Round →
Resolution → Post → Lobby`, as a pure function of state driven by the injected
clock from `ROUND-001` and the durations from `ROUND-002`.

This is the one large system in the project that is **genre-independent**: it was
specified before amendment 8 replaced hidden-role deduction with
asymmetric-information co-op, and not a line of it moved when the genre changed.
Keeping it that way is a design constraint of this story, not a nice property —
see `## Out of scope`.

Read `docs/wiki/architecture.md` §3 for the transition table and the effect
vocabulary. This story builds the happy-path lifecycle; `ROUND-004` adds the lobby
gating and `ROUND-005` the three ways a round can end.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a fresh machine with `players_min` players seated, when the
  clock is advanced past `lobby_seconds`, then the phase becomes `Assignment` and
  not before: at `lobby_seconds − 0.1` elapsed the phase is still `Lobby`.
- **AC-2** — Given the machine in `Assignment`, when it entered that phase, then
  it emitted exactly one `AssignSeats` effect carrying the round's seed and the
  seated player list; and when a `SeatsAssigned` event is applied, then the phase
  becomes `Round`.
- **AC-3** — Given the machine in `Round`, when a `RoundResolved` event carrying an
  outcome is applied, then the phase becomes `Resolution` and the state records
  that outcome unchanged — the machine does not inspect, compute or override it.
- **AC-4** — Given the machine entering `Resolution`, when the next step occurs
  with no further input, then it emits a `ComputeTrace` effect and the phase
  becomes `Post` without waiting on the clock.
- **AC-5** — Given the machine in `Post`, when the clock is advanced past
  `post_round_seconds`, then a `PromptRematch` effect has been emitted and the
  phase returns to `Lobby` with a **new** round seed, distinct from the previous
  round's.
- **AC-6** — Given any state and any event, when `step` is called twice with
  identical `(state, event, now)`, then the two calls return equal states and equal
  effect lists, and the input state is not mutated.
- **AC-7** — Given a state in any phase, when an event that phase does not
  recognise is applied — including one it already consumed — then the state is
  returned unchanged with an empty effect list and no error is raised.
  *Control:* an implementation that raises on an unknown event **must** fail this.
- **AC-8** — Given a full lifecycle driven end to end by a manual clock, when the
  sequence of phases and effects is recorded, then it is exactly
  `Lobby, Assignment, Round, Resolution, Post, Lobby` with effects
  `AssignSeats, ComputeTrace, PromptRematch` in that order, and no Roblox runtime
  was required at any point.

## Contract

### `src/server/round/PhaseMachine.luau`

    export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"

    export type PlayerId = string
    export type RoundId  = string

    export type Outcome = {
        result: "won" | "lost" | "no_contest",
        reason: string,          -- opaque to this module; M3 supplies the vocabulary
    }

    export type RoundState = {
        phase:          Phase,
        phaseEnteredAt: number,      -- the `now` at which the phase was entered
        roundId:        RoundId,
        seed:           number,
        players:        { PlayerId },   -- seat order; stable within a round
        outcome:        Outcome?,
    }

    export type Event =
        | { kind: "PlayerJoined",  playerId: PlayerId }
        | { kind: "PlayerLeft",    playerId: PlayerId }
        | { kind: "Tick" }
        | { kind: "SeatsAssigned" }
        | { kind: "RoundResolved", outcome: Outcome }
        | { kind: "RematchAccepted", playerId: PlayerId }

    export type Effect =
        | { kind: "AssignSeats",   seed: number, players: { PlayerId } }
        | { kind: "PromptRematch" }
        | { kind: "ComputeTrace",  roundId: RoundId }

    PhaseMachine.initial(config: RoundConfig, seed: number, roundId: RoundId) -> RoundState
    PhaseMachine.step(state: RoundState, event: Event, now: number) -> (RoundState, { Effect })

**AMENDED AT PLANNED -> RED by the Lead PO — the `Emit` and `ReplicateSeat`
variants are removed from this story's union.** They were planned as

        | { kind: "Emit",          event: TelemetryEvent }
        | { kind: "ReplicateSeat", playerId: PlayerId, view: PublicSeatView }

and `TelemetryEvent` and `PublicSeatView` do not exist in this tree. That is not
a style preference, it is a required gate: **measured on this machine,
2026-09-15**, with a two-variant union naming one undefined type in a
`--!strict` module under `src/server/round/`:

    luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau \
      --base-luaurc=.luaurc --ignore='Packages/**' src
    exit=1
    src/server/round/__probe_undefined_type.luau [...](5,27):
        TypeError: Unknown type 'TelemetryEvent'

So carrying them costs the `typecheck` gate, and the only ways to keep them are
two stubs this story has no criterion for or an `any` hole in a `--!strict`
module. Both are worse than the omission, and the omission contradicts no
acceptance criterion: this story emits neither, and `## Out of scope` already
says `TEL-002` adds the emitters and `SEAT-002` the seat views. `TEL-002` and
`SEAT-002` restore their own variant together with the payload type that makes
it typecheck. `architecture.md` §3 keeps the full five-variant vocabulary and is
not edited: it describes M1 through M3, not this story.

**`initial` takes three arguments here, not two.** `architecture.md` §3 writes
`initial(config, seed)`; this Contract adds `roundId`, because AC-4's
`ComputeTrace` effect carries a `RoundId` and the machine has nowhere else to
get one. The Contract is what GREEN builds; the architecture document is the
older and less specific of the two.

**RED may amend any block in this Contract in place, with the reason written
next to it, and GREEN builds what the amended block says.** An amendment is a
finding, not a failure — the one above is the Lead PO taking its own advice.
Amending an **acceptance criterion** is a different act and goes through
`## Amendments` with the user's approval.

### Callers of every changed signature

**None. Checked against the tree at `abf37d1`, not assumed:**

    $ grep -rn "PhaseMachine\|RoundConfig" src tests lune | wc -l
    0

Both modules are new; no existing export changes signature; there is no caller
for GREEN to break when a signature moves, because no signature moves. RED's
handoff states that it re-checked this against the tree.

### `src/server/round/RoundConfig.luau`

    export type RoundConfig = {
        lobbySeconds:          number,
        postRoundSeconds:      number,
        roundSeconds:          number,
        playersMin:            number,
        playersMax:            number,
        minPlayersToContinue:  number,
    }

    RoundConfig.fromTuning(tuning) -> RoundConfig

The config is **injected**, never read from `Tuning` inside the machine. That is
what lets a test run a whole lifecycle in a few simulated seconds instead of nine
real minutes, and it is why `ROUND-002`'s placeholder values can move without
touching this module.

### The semantics behind each number and each rule

- **`phaseEnteredAt`** is the `now` passed to the `step` that entered the phase,
  not the `now` of the step that noticed. A phase's duration is measured from
  entry, so a driver that ticks irregularly cannot stretch a phase.
- **The comparison is `now - phaseEnteredAt >= duration`**, inclusive. At exactly
  `lobby_seconds` the phase leaves. AC-1's `− 0.1` pins the other side.
- **`Assignment` is a step, not a pause.** It has no duration. It waits for
  `SeatsAssigned`, which the driver produces by calling `Ring.assign` (SEAT-001).
  Until SEAT-001 exists, the driver is a test.
- **`Resolution` has no duration either.** It transitions on the next step. The
  visible pause after a round is `Post`, which is where `post_round_seconds` lives
  and where the trace is read.
- **A new seed per round.** AC-5 requires the returning `Lobby` to carry a seed
  distinct from the last round's. Derive it deterministically from the machine's
  own state — `Rng.fromSeed(previousSeed):derive("nextRound"):nextInteger(...)` or
  equivalent — **not** from a real random source, or `step` stops being pure and
  AC-6 becomes unsatisfiable.
- **`step` is total.** Unknown event, duplicate event, event for a player not
  seated: return `(state, {})`. AC-7. Late and duplicate delivery is normal in a
  networked game; a machine that throws is a machine a lagging client can crash.
- **`step` never mutates.** It returns a new `RoundState`. AC-6's non-mutation
  clause is the one that will be violated first and noticed last.

### AMENDED AT RED by the Test Developer — five things the tests pin that the Contract did not say

Every one of these is a question the tests could not avoid answering, answered
the only way the rest of the Contract and the criteria allow. **GREEN builds what
this block says.** None of them changes an acceptance criterion.

1. **`initial(config, seed, roundId)` returns
   `{ phase = "Lobby", phaseEnteredAt = 0, roundId = roundId, seed = seed,
   players = {}, outcome = nil }`.** `initial` takes no `now`, so `phaseEnteredAt`
   has exactly one self-consistent value, and the whole of AC-1 is measured from
   it. Pinned by *"Contract: initial returns a Lobby entered at 0 …"*.

2. **`PlayerJoined` seats a player: it appends `playerId` to `players` and emits
   nothing.** `initial` takes no player list and the Event union has no other way
   to seat one, so AC-1's "with `players_min` players seated" and AC-2's "the
   seated player list" are otherwise unreachable. Order is arrival order —
   `RoundState.players` is documented "seat order; stable within a round".
   Pinned by *"Contract: PlayerJoined seats a player, in arrival order"*.

3. **A `PlayerJoined` for a player already seated is an unrecognised event** in
   AC-7's sense: state unchanged, no effects, nobody seated twice. Appending a
   duplicate would put one player in two seats of the ring, and
   `architecture.md` §3 says duplicate delivery is normal. Pinned by *"AC-7: a
   duplicate PlayerJoined does not seat the same player twice"*.

4. **Phase durations are evaluated on the events the phase recognises — in
   practice `Tick` — and never on an event the phase does not recognise.** AC-7
   is read literally: *"the state is returned unchanged with an empty effect
   list"*, with no exception for a duration that has already come due. An
   implementation that folds "check the timers" into the top of every `step`
   fails here and nowhere else. This is the one place two reasonable readings
   differ and the criterion decides it; it is called out in the test's own
   comment and in `## Handoff`. Pinned by *"AC-7: an unrecognised event is
   ignored in every phase, even when the phase's duration is due"* (`now = 9`,
   past Lobby's 3 and past Post's 2).

5. **A step that changes nothing emits nothing.** AC-8 fixes the whole effect
   sequence of a lifecycle at `AssignSeats, ComputeTrace, PromptRematch`, so
   `SeatsAssigned`, a seating `PlayerJoined`, and a `Tick` that is not due all
   return an empty effect list. `AssignSeats` in particular is emitted by the
   step that ENTERS `Assignment`, once, not once per step while in it. Pinned by
   *"AC-2: a further step inside Assignment does not emit AssignSeats a second
   time"* and *"AC-2: SeatsAssigned moves Assignment to Round and emits
   nothing"*.

**And one note on `fromTuning`, which is not an amendment but a warning.** The
tests call `RoundConfig.fromTuning(tuning)` with a structural duplicate of
`Tuning` carrying values that appear nowhere in the real one. Luau is
structurally typed, so `fromTuning(tuning: Tuning.Tuning)` accepts it and the
test tells a mapping apart from a module that requires `Tuning` and ignores its
argument. Do not type the parameter in a way that depends on table identity.

**What RED deliberately did NOT constrain**, so it stays GREEN's choice: whether
the returning `Lobby` keeps or clears `players` and `outcome`; whether it takes a
new `roundId`; the exact derived value of the next round's seed (only that it is
deterministic, differs from the previous seed, and differs when the previous seed
differs); whether phases other than `Lobby` and `Post` check a duration at all;
and the internal shape of the module beyond the two exported functions.

### What this module must not contain

No reference to Procedures, operations, actuators, instability, signals, budgets,
marks or lenses. `Outcome.reason` is an opaque string that M3 fills in. If the
implementation needs to know *why* a round ended in order to route it, the routing
is wrong.

### Test-only dependencies

None.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1..AC-5, AC-8 | **Mechanical** | Pin the transition table exactly, from `architecture.md` §3. Precision beats invention; leave nothing open-ended. |
| AC-6, AC-7 | **Mechanical, with a control each** | Purity and totality. The controls are named in the criteria. AC-6's non-mutation half needs a deep comparison of the input state before and after, not an identity check. |
| — | **Settled** | The durations come from `ROUND-002`, which reads them from `tuning.md`. Do not choose or calibrate a duration. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None. Every criterion here can be exercised in RED against a machine that does not yet exist, and the two controls (AC-7's raising implementation, AC-6's mutating one) can be demonstrated against a hand-written stub.
-->

## Model guidance

**Resolved model of every dispatch, by name:**

| Phase | Agent | Model as configured | Resolved model |
|---|---|---|---|
| orchestration | lead-po | `opus` | `claude-opus-5` (this session) |
| RED | test-developer | `opus` | `claude-opus-5` (no override at dispatch) |
| GREEN, GATES | feature-developer | `opus` | `claude-opus-5` (no override at dispatch) |

This story is almost entirely **mechanical**: the transition table is written down
in `architecture.md` §3 and the job is to pin it exactly. Brief RED accordingly —
precision, not invention. The one place judgement is wanted is AC-6's non-mutation
assertion, where the obvious test (compare references) asserts nothing.

## Out of scope

- **Lobby player-count gating.** `ROUND-004`. This story seats `players_min`
  players and leaves them there.
- **Clock expiry and quorum loss ending a round.** `ROUND-005`.
- **What actually resolves a round.** M3. The machine routes `RoundResolved`; it
  never computes an outcome.
- **The seat assignment itself.** `AssignSeats` is an effect with nothing behind it
  until SEAT-001.
- **Telemetry.** The `Emit` effect is in the vocabulary and this story emits none.
  `TEL-002` adds the emitters.
- **The trace.** `ComputeTrace` is emitted and nothing consumes it. `mechanics.md`
  §7 is M3.
- **The driver.** `RoundService.luau` — the impure loop that owns the real clock
  and performs effects — is not needed until something networked exists. Tests
  drive `step` directly.

## Game design

Implements the round structure in `docs/wiki/game/loop.md` and brief A4, with the
amendments in product-brief §0b/§0c applied: no vote, no elimination, no hidden
faction (amendment 8), and a `Post` phase lengthened to 45 seconds because the
post-round trace is four items of reading (`tuning.md` §1).

The design decision this story protects: **the round is short and the post-round
is deliberately not.** A4 calls the rematch prompt "the highest-value thirty
seconds in the product" and A2 #2 makes intentional co-play the headline retention
signal. `PromptRematch` being an effect the machine emits — rather than something
the UI decides to show — is what makes that testable.

Edge cases the rules produce, and where each is handled:

| Case | Here or elsewhere |
|---|---|
| Two terminal conditions in the same step | `ROUND-005` — precedence is specified there |
| Player count below `players_min` at lobby end | `ROUND-004` — the timer **holds**, it does not reset |
| Player count below `min_players_to_continue` mid-round | `ROUND-005` — `no_contest`, no loss recorded |
| Disconnect and rejoin changing the ring | `SEAT-003` |

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Change the phase-duration comparison from `>=` to `>`. Predicted: AC-1's
   boundary assertion goes red and little else — a single assertion, which is where
   a vacuous boundary test hides.
2. Make `step` mutate and return the input state. Predicted: AC-6's non-mutation
   assertion goes red. If it stays green, AC-6 was written as an identity check.
3. Make the returning `Lobby` reuse the previous seed. Predicted: AC-5's distinct-
   seed assertion goes red.

Run mutation 1 first.

**Raise the `unit` floor** to the new real count.

**Added in GREEN — a `.luaurc` require alias, and it is a project-wide
convention rather than a detail of this story.** `PhaseMachine` is the first
module in `src/` to require another module in `src/`, and the relative form does
not survive the `typecheck` gate. Measured, this machine, 2026-09-15, with
`local Rng = require("../../shared/Rng")`:

    luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau \
      --base-luaurc=.luaurc --ignore='Packages/**' src
    exit=1
    src/server/round/RoundConfig.luau [game/ServerScriptService/Server/round/RoundConfig](24,16):
        TypeError: Unknown require: game/ServerScriptService/shared/Tuning
    src/server/round/RoundConfig.luau [...](46,41): TypeError: Unknown type 'Tuning.Tuning'
    src/server/round/PhaseMachine.luau [...](65,13):
        TypeError: Unknown require: game/ServerScriptService/shared/Rng

`luau-lsp` resolves a relative string require **through the sourcemap**, i.e. in
the Roblox instance tree, where `src/shared` is `game/ReplicatedStorage/Shared`
and not `../../shared` of `game/ServerScriptService/Server/round`. A require
inside one directory (`require("./RoundConfig")`) resolves fine; one that crosses
the ReplicatedStorage/ServerScriptService boundary cannot, in any relative
spelling that Lune would also accept.

So `.luaurc` gained

    "aliases": { "shared": "src/shared" }

and both modules say `require("@shared/Rng")` / `require("@shared/Tuning")`.
**Both tools were measured, not assumed:** `luau-lsp analyze` exits 0 over `src`,
and `lune run test` resolves the same alias (137 passed). `.luaurc` classifies as
`config`, which GREEN may write.

**What is NOT verified, stated plainly:** no gate executes anything inside a
Roblox runtime, so whether `require("@shared/Rng")` resolves in a real place file
is untested here — `.luaurc` is not synced by `default.project.json`. The `build`
gate only proves the place builds. If the Lead PO wants the convention recorded in
`architecture.md`, or wants a different one (an instance-path require behind a
Lune shim), that is a docs decision and this note is the input to it.

**`typecheck` and `format` report `observed 5` and `observed 21` — unchanged from
RED — because both counts come from `git ls-files`, and this story's two modules
are not yet committed.** The tools do read them (`analyze` walks `src/`, not the
git index; it is what produced the errors above). Expect 7 and 23 after the
commit. Nothing to fix; recorded so that a flat count is not read as a gate that
stopped looking.

---

## PO decisions at PLANNED -> RED

**1. `covers | unit | src/server/**` and `discovery | server` added to
`.claude/harness/project.conf`.** This story names `unit` as the gate that would
fail if its artifact broke, and it is required — but before this change the
manifest said `covers | unit | src/shared/**` and nothing else, and this is the
first story to write under `src/server/`. `gates.sh --list` at `abf37d1`:

    unit         required  .      lune run test
                                  evidence: [1-9][0-9]* passed, [0-9]+ failed
                                  floor:    83
                                  covers:   src/shared/**

`lint`, `typecheck` and `build` all carry `covers | ... | src/**` and are all
required, so the covers check would have **passed** over this story's source
while no test gate declared it read the phase machine at all — three static
gates standing in for the one that runs the assertions. That is the renderer
failure in `project.conf`'s own header, one story later. The `discovery` line is
there because this file's rule is that a covers claim is paired with a command
that proves the runner can see it; it reads MISSING in `doctor.sh` until RED
lands `tests/server/`, and going green is part of RED's verification.
`gates.sh --audit` passes after the change.

**2. The `Emit` and `ReplicateSeat` effect variants are out of this story's
union.** Recorded in `## Contract` with the measured `luau-lsp` output that
forces it. No acceptance criterion changes, so this is a Contract amendment and
not an `## Amendments` entry.

**3. The epic's done-when is not this story's to close.** `EPIC-01` promises a
lobby that refuses to start below `players_min`, a round that ends by the clock,
one that ends by an outcome event, and one that ends `no_contest`. `ROUND-004`
and `ROUND-005` are the stories that deliver those and both are in the epic's
list, so there is no gap between the last story and this one for this story to
absorb. Checked, not skipped.

**4. The toolchain is not on this session's `PATH` and that is the stale-shell
symptom `environment.md` already records**, not a broken install: this bash
session predates the Rokit install, so every dispatch and every gate run here is
prefixed with

    export PATH="$HOME/.rokit/bin:$PATH"

Every subagent dispatch carries that line. Without it `lune run test` is
`command not found`, which a subagent could easily read as a broken test command
and work around.

---


## PO ruling at RED -> GREEN

**On RED's Contract amendment 4 — accepted, and it is a ruling rather than a
rubber stamp.** RED pinned AC-7 literally: an event a phase does not recognise
returns the state unchanged and an empty effect list **even when that phase's
duration is already due**, which forbids an implementation that folds "check the
timers" into the top of every `step`. RED flagged this as the one place two
readings differ and asked for a PO call. Three things decide it:

1. **AC-7's text admits one reading.** *"the state is returned unchanged with an
   empty effect list and no error is raised"* — with no exception for a due
   duration. Acceptance criteria are frozen once a story leaves PLANNED; reading
   this one loosely to leave GREEN more room is the move that rule exists to
   stop.
2. **The pin is satisfiable, checked and not assumed.** I read the tests rather
   than taking the claim: every clock-driven transition in the suite is driven by
   `tick()`, an event the phase recognises — AC-1 and AC-5 at their boundaries,
   and AC-4 at `machine.step(resolution, tick(), resolution.phaseEnteredAt)`. So
   evaluating durations inside the branches for recognised events satisfies AC-1,
   AC-4, AC-5 **and** AC-7 together. There is no criterion pair that only the
   check-at-the-top implementation can satisfy, so this costs GREEN one line of
   placement and no capability.
3. **It is the reading the architecture already implies.** `architecture.md` §3
   makes ignoring an unrecognised event a property of the machine's totality —
   *"a machine that throws on one is a machine that can be crashed by a lagging
   client"* — and a duplicate `SeatsAssigned` that silently ends the lobby is the
   same class of defect as one that throws, just quieter.

No acceptance criterion changed, so there is no `## Amendments` entry; this is a
Contract amendment and it stands. GREEN builds what the amended block says.

**Amendments 1, 2, 3 and 5 are accepted without argument.** Each answers a
question the criteria could not be tested without answering — `initial` has no
`now`, so `phaseEnteredAt = 0` is the only self-consistent value; `PlayerJoined`
is the only way the Event union can seat anybody, so AC-1's "with `players_min`
players seated" is unreachable otherwise; a duplicate join seating one player in
two seats of the ring would break `SEAT-001` before it is written; and AC-8 fixes
the whole effect sequence, so a step that changes nothing must emit nothing.

**On RED's correction to the story's own mutation prediction.** `## Notes`
predicted mutation 1 would fail a single assertion; RED predicts two, because it
pinned the inclusive boundary at **both** ends — `Lobby` and `Post` — so that an
implementation using `>=` for one and `>` for the other cannot pass. That is a
better suite than the prediction assumed, and the prediction is what moves. The
orchestrator runs the mutation at acceptance and records the measured count
against **2**; RED's warning to target the expression
(`now - state.phaseEnteredAt >= `) rather than the bare `>=` token is carried
into that run.

**Dispatch model, resolved.** `test-developer`, declared `model: opus` in
`.claude/agents/test-developer.md`, dispatched with no model override, resolved
to **`claude-opus-5`**.
## PO acceptance at GREEN -> GATES

### The mutation table is no longer a claim

RED predicted counts for three mutations against an implementation that did not
exist. Two were run by the orchestrator against the shipped module, through
`scripts/mutate.sh` — which backs the file up to an explicit path, applies the
expression, runs the suite, restores and verifies the restore with `cmp`.
**Both predictions matched exactly, test for test.**

**Mutation 1** — the phase-duration comparison, `>=` to `>`. RED's warning to
target the expression rather than the bare token was followed:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/elapsedIn(state, now) >= /elapsedIn(state, now) > /' -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (2 line(s) changed) ===
    135 passed, 2 failed
      FAIL  tests/server/phase_machine_test.luau :: AC-1: the Lobby leaves for Assignment at exactly lobbySeconds elapsed
      FAIL  tests/server/phase_machine_test.luau :: AC-5: the Post phase leaves at exactly postRoundSeconds elapsed
    === mutate: command exited 1; restored (verified byte-for-byte) ===

Predicted 2, measured 2, and the two named tests are the two RED named. This is
the mutation the story's `## Notes` predicted would fail **one** assertion; RED
corrected that to two because it pinned the inclusive boundary at both ends, and
the measurement settles it in RED's favour. Had only the Lobby boundary been
pinned, an implementation using `>=` there and `>` in `Post` would pass forever.

**Mutation 3** — the returning `Lobby` reuses the previous seed:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/lobby.seed = nextSeedFrom(state.seed)/lobby.seed = state.seed/' -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed) ===
    136 passed, 1 failed
      FAIL  tests/server/phase_machine_test.luau :: AC-5: the returning Lobby carries a seed distinct from the round that just ended
    === mutate: command exited 1; restored (verified byte-for-byte) ===

Predicted 1, measured 1, and it is the single assertion RED named — the case
where a vacuous test hides. Chosen over mutation 2 as the second probe precisely
because its predicted catch is one assertion: mutation 2's predicted 15 is mostly
aliasing collateral and a matching count there would prove less.

The suite is green again after both restores (`137 passed, 0 failed`), and
`.claude/state/mutations/` holds only its log — no `.bak`, so no restore failed.

### The `.luaurc` require alias — accepted, and reproduced independently

GREEN reported that a relative cross-layer require fails the `typecheck` gate and
changed `.luaurc` to add `"aliases": { "shared": "src/shared" }`. That is a
project-wide convention arriving as a side effect of one story, so it was
reproduced rather than taken on report — **not** by re-running GREEN's probe, but
against the shipped module through `mutate.sh`:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's|@shared/Rng|../../shared/Rng|' -- bash -c 'rojo sourcemap ... && luau-lsp analyze ...'

    65 - local Rng = require("@shared/Rng")
    65 + local Rng = require("../../shared/Rng")
    ...
    src/server/round/PhaseMachine.luau [game/ServerScriptService/Server/round/PhaseMachine](65,13):
        TypeError: Unknown require: game/ServerScriptService/shared/Rng
    === mutate: command exited 1; restored (verified byte-for-byte) ===

Confirmed: `luau-lsp` resolves a relative string require through the sourcemap's
instance tree, so no relative spelling crosses the ReplicatedStorage /
ServerScriptService boundary. **The decision is recorded in
`docs/wiki/architecture.md` §1, "How a module in `src/` requires another module
in `src/`", together with the limit GREEN was right to flag:** nothing in this
repository executes a module inside a Roblox runtime, `.luaurc` is not synced by
`default.project.json`, and the `build` gate proves only that the place builds —
so alias resolution *in a real place* is untested as of this story, and the first
story that runs a module in a place verifies it. A comment in a source file would
not have been enough; the architecture document is where a limit like this has to
live.

### `RoundState` carries a seventh field

GREEN reported that the Contract lists six `RoundState` fields while
`initial(config, …)` and `step(state, event, now)` between them leave the config
nowhere to live but the state. That is correct and it follows from the two
signatures the story pinned, not from a choice GREEN made: `step` has no config
parameter. Accepted as a Contract shape change; it is documented in the module
header and no test asserts a closed key set on `RoundState`.

### The `unit` floor is raised, in the story that earned it

`floor | unit | 83` → **137**, measured from this story's own full-suite runs
(`137 passed, 0 failed`, and `observed 137` in the gate summary). With `coverage`
unconfigured on this stack, the floor is the only thing that notices a suite
shrinking from 137 tests to 4, so raising it here is not bookkeeping.


### The two manifest lines added at PLANNED -> RED, observed

Not a `## Gate probes` entry — this story adds no gate — but the same standard,
because a line that cannot fail is not a check.

`discovery | server` is green now and was not before RED:

    $ bash scripts/doctor.sh
    Test discovery
      ok       tests        discovered
      ok       shared       discovered
      ok       server       discovered
      ok       sourcemap    discovered

And it is not vacuous. The command is a `grep` over the runner's own listing, so
it returns nothing when the directory it names is absent — observed both ways
against one listing:

    $ lune run test -- --list > listing
    $ grep -E 'tests/server/'  listing > /dev/null ; echo $?     # 0   (54 matches)
    $ grep -E 'tests/nowhere/' listing > /dev/null ; echo $?     # 1

`covers | unit | src/server/**` is what produced the line

    changes: 2 changed source path(s), all exercised by a required gate

in this story's recorded gate run. Without it the same two paths would still have
been "exercised by a required gate" — `lint`, `typecheck` and `build` all read
`src/**` — and the claim would have been carried entirely by static analysis with
no test gate declaring it read the phase machine.

### CI on PR #5, read for timings and not only for green

https://github.com/ryanczhang7/first-roblox/pull/5 — `boundaries` pass (5s),
`gates` pass (46s). Run 35036797532:

    PASS         format (0s, observed 30)
    PASS         lint (0s, observed 30, floor 1)
    PASS         typecheck (2s, observed 7)
    PASS         unit (1s, observed 137, floor 137)
    PASS         build (0s, observed 15638)

Two things worth reading rather than glancing at:

- **The counts moved as GREEN predicted.** `format`/`lint` 21 -> 30 and
  `typecheck` 5 -> 7, because both counts come from `git ls-files` and this
  story's files were untracked during the local run. The prediction was written
  down before the commit, which is what makes it a check rather than a
  rationalisation.
- **No margin is thin.** The whole `gates` job is 42 s of step time; the slowest
  step is the harness self-test at 25 s, and `unit` is **1 s on CI against 15 s
  on this Windows machine** — the ratio runs the safe way, because the local cost
  is `bash`/`classify.sh` subprocess launches, which Linux does cheaply. There is
  no per-test timeout in this runner and nothing sits near a limit, so there is
  no pending-failure shape here of the kind a green run three seconds under a
  30 s hook default would have.
### Dispatch model, resolved

`feature-developer`, declared `model: opus` in
`.claude/agents/feature-developer.md`, dispatched with no model override,
resolved to **`claude-opus-5`**.

## Test plan

Five files. Four under `tests/server/` (the directory the `discovery | server`
line was added for), one extension to an existing helper.

| File | What it is |
|---|---|
| `tests/server/phase_machine_test.luau` | AC-1..AC-8 against the real module. Every test fails in RED naming the module that did not load. |
| `tests/server/round_config_test.luau` | `RoundConfig.fromTuning` — the mapping and the injection. |
| `tests/server/roblox_runtime_guard_test.luau` | AC-8's "no Roblox runtime" clause, as a textual guard over `src/server/round/**`. |
| `tests/server/phase_machine_controls_test.luau` | The AC-6 and AC-7 controls, and the checks on the comparator they are built from. **Requires no production code and runs in RED.** |
| `tests/helpers/{Deep,PhaseMachineContract,MachineStubs}.luau`, `tests/helpers/SourceScan.luau` | The instrument, the checks, the wrong machines, and one extension to the existing scanner. |

### AC to test

| AC | Test | Why it discriminates |
|---|---|---|
| AC-1 | `AC-1: the Lobby leaves for Assignment at exactly lobbySeconds elapsed` | **One assertion, alone at the boundary.** `now = lobbySeconds` exactly. A `>` implementation fails here; nothing else in the suite sits on the Lobby boundary, so mutation 1 produces a small, unambiguous count. |
| AC-1 | `AC-1: at a tenth of a second short of lobbySeconds …` | The other side. Also asserts no effect is emitted early. |
| AC-1 | `AC-1: the lobby duration is measured from the step that entered the phase, not from the previous step` | Ticks at 2.9 and then 3.5. A machine measuring from the *last step* needs 5.9 and is still in Lobby at 3.5. Also pins `phaseEnteredAt == 3.5` on the entering step. |
| AC-1 | `AC-1: the machine obeys the config it was injected with, not Tuning's sixty-second lobby` | Injected `lobbySeconds = 3`; a machine reading `Tuning.session.lobby_seconds` (60) is still in Lobby at t = 4. This is the test the injected-config design exists for. |
| AC-2 | `AC-2: entering Assignment emits exactly one AssignSeats, carrying the round seed and the seated players` | `#effects == 1`, not "at least one"; seed compared to the round's own seed; players deep-compared to the seated list. |
| AC-2 | `AC-2: a further step inside Assignment does not emit AssignSeats a second time` | Separates "on entering" from "once per step". |
| AC-2 | `AC-2: Assignment is a step and not a pause …` | A tick 1,000 s later is still `Assignment`. Kills a duration nobody specified. |
| AC-2 | `AC-2: SeatsAssigned moves Assignment to Round and emits nothing` | The transition, `phaseEnteredAt`, and the empty effect list AC-8's whole-sequence claim depends on. |
| AC-3 | `AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged` | The `reason` is `reason-x7f3-set-by-the-caller-not-the-machine`, a string no implementation would invent. Asserted field by field **and** deep-compared. |
| AC-3 | `AC-3: an outcome of a different result is recorded just as unchanged` | A second result kind (`won`), so a machine that special-cases one value is caught. |
| AC-4 | `AC-4: Resolution moves to Post on the next step with the clock standing still …` | `now` is the phase's own `phaseEnteredAt` — zero elapsed. Pins "without waiting on the clock" rather than assuming it. Exactly one `ComputeTrace`. |
| AC-4 | `AC-4: the ComputeTrace effect carries the round id the machine was given` | The `roundId` the amended Contract added `initial`'s third argument for. |
| AC-5 | `AC-5: past postRoundSeconds the machine returns to Lobby, emitting exactly one PromptRematch` | The criterion's own wording: *past*. |
| AC-5 | `AC-5: the Post phase leaves at exactly postRoundSeconds elapsed` | The second inclusive boundary. Without it, an implementation could use `>=` for Lobby and `>` for Post and no test would notice. One assertion. |
| AC-5 | `AC-5: at a tenth of a second short of postRoundSeconds …` | The other side of that boundary. |
| AC-5 | `AC-5: the returning Lobby carries a seed distinct from the round that just ended` | The distinctness, asserted directly. Mutation 3 lands here. |
| AC-5 | `AC-5: the next round's seed is derived deterministically …` | Same lifecycle replayed, same next seed. AC-6's purity depends on the derivation not reaching for a real random source, and this is what makes that testable. |
| AC-5 | `AC-5: a different round seed derives a different next-round seed` | **The vacuity case.** `seed = 12345` for every round is deterministic *and* distinct from one previous seed, and is not a new seed per round. Two lifecycles seeded `n` and `n+1` must end apart. |
| AC-6 | `AC-6: two identical steps return equal states and equal effect lists, in every phase` | Six cases, one per transition — mutation happens where work happens, so no-op steps would prove little. Deep structural equality, never `==` on tables. |
| AC-6 | `AC-6: step does not mutate the state it was given, in any phase` | **The story's most important assertion.** A deep snapshot of the input before the call, deep-compared against the input after. Explicitly *not* an identity check; see the control below. Violations accumulated, asserted once, so one run names every offending phase. |
| AC-6 | `AC-6: the step that leaves the Lobby does not mutate the state it was given` | The same check on a state reached without cross-phase setup. A machine that mutates and returns its input cannot be driven through five phases at all, so the test above would fail inside `journey()` and be attributed to the wrong thing; this one fails with the message the criterion names. |
| AC-7 | `AC-7: SeatsAssigned applied a second time is ignored` | The criterion's "including one it already consumed". |
| AC-7 | `AC-7: RoundResolved in Lobby is ignored` | Wrong-phase event. |
| AC-7 | `AC-7: RematchAccepted in Round is ignored` | Wrong-phase event, the other direction. |
| AC-7 | `AC-7: an event naming a player who was never seated is ignored` | `PlayerLeft` for `never-seated-p99`. |
| AC-7 | `AC-7: a duplicate PlayerJoined does not seat the same player twice` | Contract amendment 3. A duplicate join must not put one player in two seats of the ring. |
| AC-7 | `AC-7: an event whose kind is not in the union is ignored` | `kind = "DetonateTheReactor"`. |
| AC-7 | `AC-7: an unrecognised event is ignored in every phase, even when the phase's duration is due` | All five phases at `now = 9`, past Lobby's 3 and Post's 2. Contract amendment 4; the criterion is read literally. |
| AC-8 | `AC-8: a full lifecycle on a manual clock passes through exactly Lobby, Assignment, Round, Resolution, Post, Lobby` | Whole list, deep-compared. Driven by `Clock.manual` with an **irregular** tick sequence (0.5, 3.5, 5.0, 6.0, 6.0, 7.0, 8.5). |
| AC-8 | `AC-8: a full lifecycle emits exactly AssignSeats, ComputeTrace, PromptRematch, in that order` | Whole list, in order, not membership. |
| AC-8 | `AC-8: the guard scans this story's two round modules` + `AC-8: no module under src/server/round references a Roblox runtime global` | The "no Roblox runtime" clause. Textual, over the file list `scripts/classify.sh` returns for `src/server/round`, matched with `SourceScan.hitsIn` — no private glob, no second copy of the word-boundary rules. Both tests carry the same vacuity check, because a clean scan over an empty list is the one way this can pass while proving nothing. |
| Contract | `Contract: PhaseMachine exports initial and step as plain field functions`, `… initial returns a Lobby entered at 0 …`, `… PlayerJoined seats a player, in arrival order` | The export shape and Contract amendments 1 and 2. |
| Contract | The five `round_config_test.luau` tests | Export shape; exactly the six named fields; each mapped to its `Tuning` constant *read out of `Tuning`*; the injection (a fake tuning table with values 11..23 that appear nowhere in the real one); and that `fromTuning`'s field names match the shape the machine is driven with. |

### The controls, by name

| Control | Where | What it proves |
|---|---|---|
| `MachineStubs.inert` | baseline | A machine with none of the defects passes all three checks, so a control that fires is attributable to the one defect. |
| `MachineStubs.mutating` | AC-6, named in the criterion | Mutates and returns the input. **Passes the determinism half** — that is the trap — and must fail the non-mutation half. |
| `MachineStubs.mutatingCopier` | AC-6, the reason the check is written as it is | Mutates the caller's table *and* returns a fresh copy. Passes `returned ~= given`; must fail the deep-snapshot check. This is the test that stops AC-6 being written as the version that proves nothing. |
| `MachineStubs.raising` | AC-7, named in the criterion | Raises on an unknown event; handles `Tick`, so it is a plausible machine rather than a function that only throws. |
| `MachineStubs.chatty` | AC-7, second half | Ignores the event, returns the state untouched, and emits an effect anyway. "No error was raised" does not catch it; the empty-effect-list assertion does. |
| Six comparator cases | instrument | A `Deep.equal` that always returned `true` would turn AC-6, AC-7 and AC-8 green while proving nothing. Changed leaf, missing key, extra key, wrong type, difference two levels down, longer list — plus a copy that shares no table with its original. |
| Four guard controls | AC-8 | The matcher fires on all six Roblox symbols and names the line; does not fire in comments or string literals; does not fire on `gamepad`, `scripted`, `subworkspace`, `self.script`; and the file-reading path finds a real `os.clock()` call in ROUND-001's committed probe on disk. |

## Handoff: RED -> GREEN

**Dispatched model.** `test-developer` is declared `model: opus` in
`.claude/agents/`; this dispatch resolved to **`claude-opus-5`**, with no
override in the task. Record it in `## Model guidance`.

### The command

    export PATH="$HOME/.rokit/bin:$PATH"   # this shell predates the Rokit install
    lune run test

That is the `unit` gate verbatim. Without the `PATH` line `lune` is
`command not found`; that is the stale-shell symptom `environment.md` records,
not a broken test command.

### The verbatim failure output

`lune run test` — exit 1, final line `97 passed, 40 failed`. The 40 failures,
verbatim (the 97 passes are the 83 that were already green plus this story's 14
control and instrument tests, which need no production code):

```
  FAIL  tests/server/phase_machine_test.luau :: AC-1: at a tenth of a second short of lobbySeconds the machine is still in Lobby and has emitted nothing
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-1: the Lobby leaves for Assignment at exactly lobbySeconds elapsed
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-1: the lobby duration is measured from the step that entered the phase, not from the previous step
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-1: the machine obeys the config it was injected with, not Tuning's sixty-second lobby
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-2: Assignment is a step and not a pause - it waits for SeatsAssigned however long the clock runs
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-2: SeatsAssigned moves Assignment to Round and emits nothing
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-2: a further step inside Assignment does not emit AssignSeats a second time
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-2: entering Assignment emits exactly one AssignSeats, carrying the round seed and the seated players
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-3: an outcome of a different result is recorded just as unchanged
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-4: Resolution moves to Post on the next step with the clock standing still, emitting exactly one ComputeTrace
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-4: the ComputeTrace effect carries the round id the machine was given
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: a different round seed derives a different next-round seed
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: at a tenth of a second short of postRoundSeconds the machine is still in Post
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: past postRoundSeconds the machine returns to Lobby, emitting exactly one PromptRematch
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: the Post phase leaves at exactly postRoundSeconds elapsed
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: the next round's seed is derived deterministically - the same lifecycle replayed produces the same seed
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-5: the returning Lobby carries a seed distinct from the round that just ended
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-6: step does not mutate the state it was given, in any phase
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-6: the step that leaves the Lobby does not mutate the state it was given
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-6: two identical steps return equal states and equal effect lists, in every phase
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: RematchAccepted in Round is ignored
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: RoundResolved in Lobby is ignored
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: SeatsAssigned applied a second time is ignored
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: a duplicate PlayerJoined does not seat the same player twice
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: an event naming a player who was never seated is ignored
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: an event whose kind is not in the union is ignored
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-7: an unrecognised event is ignored in every phase, even when the phase's duration is due
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-8: a full lifecycle emits exactly AssignSeats, ComputeTrace, PromptRematch, in that order
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: AC-8: a full lifecycle on a manual clock passes through exactly Lobby, Assignment, Round, Resolution, Post, Lobby
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: Contract: PhaseMachine exports initial and step as plain field functions
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: Contract: PlayerJoined seats a player, in arrival order
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/phase_machine_test.luau :: Contract: initial returns a Lobby entered at 0, with no players, no outcome, and the seed and round id it was given
        C:\Users\ryanc\Projects\first-roblox\tests\server\phase_machine_test:39: src/server/round/PhaseMachine.luau did not load: error requiring module "../../src/server/round/PhaseMachine": could not resolve child component "round"
  FAIL  tests/server/roblox_runtime_guard_test.luau :: AC-8: no module under src/server/round references a Roblox runtime global
        C:\Users\ryanc\Projects\first-roblox\tests\server\roblox_runtime_guard_test:86: this assertion would pass over the 0 file(s) the classifier returned for src/server/round, and neither of the story's modules is among them: 
  FAIL  tests/server/roblox_runtime_guard_test.luau :: AC-8: the guard scans this story's two round modules
        C:\Users\ryanc\Projects\first-roblox\tests\server\roblox_runtime_guard_test:66: the guard scanned 0 file(s) under src/server/round; a guard over nothing passes. classify.sh --list source src/server/round said: 
  FAIL  tests/server/round_config_test.luau :: Contract: RoundConfig exports fromTuning as a plain field function
        C:\Users\ryanc\Projects\first-roblox\tests\server\round_config_test:33: src/server/round/RoundConfig.luau did not load: error requiring module "../../src/server/round/RoundConfig": could not resolve child component "round"
  FAIL  tests/server/round_config_test.luau :: Contract: a config from fromTuning has the same shape the phase machine is driven with
        C:\Users\ryanc\Projects\first-roblox\tests\server\round_config_test:33: src/server/round/RoundConfig.luau did not load: error requiring module "../../src/server/round/RoundConfig": could not resolve child component "round"
  FAIL  tests/server/round_config_test.luau :: Contract: fromTuning maps each field to its specified Tuning constant
        C:\Users\ryanc\Projects\first-roblox\tests\server\round_config_test:33: src/server/round/RoundConfig.luau did not load: error requiring module "../../src/server/round/RoundConfig": could not resolve child component "round"
  FAIL  tests/server/round_config_test.luau :: Contract: fromTuning reads the tuning table it was handed, not the Tuning module
        C:\Users\ryanc\Projects\first-roblox\tests\server\round_config_test:33: src/server/round/RoundConfig.luau did not load: error requiring module "../../src/server/round/RoundConfig": could not resolve child component "round"
  FAIL  tests/server/round_config_test.luau :: Contract: fromTuning returns exactly the six fields the Contract names, all numbers
        C:\Users\ryanc\Projects\first-roblox\tests\server\round_config_test:33: src/server/round/RoundConfig.luau did not load: error requiring module "../../src/server/round/RoundConfig": could not resolve child component "round"
```

Note the two `roblox_runtime_guard_test` failures: those are **not** import
errors. They are the vacuity guard firing because `classify.sh --list source
src/server/round` returns nothing, which is the correct RED failure for a
tree-scanning guard whose subject does not exist yet.

### `bash scripts/gates.sh --fast`

Read for the shape of the failure, not for a pass. `format`, `lint`, `typecheck`
and `build` all PASS — the tests are **admissible** to the gates that will judge
them. `unit` FAILs with this story's assertions, not with a config error, a
timeout or a lint rule.

```
--- gate summary ---
PASS         format (0s, observed 21)
PASS         lint (1s, observed 21, floor 1)
PASS         typecheck (3s, observed 5)
FAIL         unit (26s, exit 1) -> .claude/state/gate-logs/unit.log
UNCONFIGURED coverage
PASS         build (1s, observed 8883)

--fast skipped: integration mutation
This is a subset, not a verdict. The full run before REVIEW is what judges the story.

(not recorded in the story: a partial run is not evidence of anything)

1 required gate(s) failed.
```

`stylua --check src tests lune` and `selene src tests lune` were also run
directly: clean, `0 errors 0 warnings 0 parse errors`.

`lune run test -- --list` reports **137 tests**, 54 of them under
`tests/server/`, so `discovery | server` in `project.conf` now passes — verified:

    lune run test -- --list | grep -E 'tests/server/' > /dev/null   # exit 0

### Every file RED touched

New:

    tests/server/phase_machine_test.luau            AC-1..AC-8 against the real module
    tests/server/round_config_test.luau             RoundConfig.fromTuning
    tests/server/roblox_runtime_guard_test.luau     AC-8's "no Roblox runtime" clause
    tests/server/phase_machine_controls_test.luau   the AC-6 and AC-7 controls
    tests/helpers/Deep.luau                         deep equality, deep copy, rendering
    tests/helpers/PhaseMachineContract.luau         the AC-6 and AC-7 checks
    tests/helpers/MachineStubs.luau                 the deliberately wrong machines

Modified:

    tests/helpers/SourceScan.luau                   see below
    docs/backlog/stories/ROUND-003.md               ## Contract (amended), ## Test plan, ## Handoff

Nothing else. No source, no config, no manifest: this story needs no test-only
dependency, so `wally.toml` is untouched. `.claude/harness/project.conf` carries
the Lead PO's `covers`/`discovery` change from PLANNED -> RED and **was not
touched by RED**.

**`SourceScan.luau` is an existing ROUND-001 helper and the change to it is
additive-plus-one-refactor**, so it needs a word:

- `classifierList(category, pathspec?)` — the pathspec is handed to
  `classify.sh`, which hands it to `git ls-files`. The cache key is now
  `category .. " " .. pathspec`. Existing single-argument callers are unchanged.
- `hitsIn(path, text, symbols)` — the word-boundary matcher, **lifted out of
  `findingsIn`**, which now calls it and attaches the AC-5 rule afterwards. One
  implementation of "this line references that symbol", not two.
- `sourceFilesIn(pathspec)`, `scanFor(paths, symbols)`, `describeHits(hits)` —
  new, thin.

ROUND-001's 12 `source_guard_test.luau` assertions run through `findingsIn` and
therefore through the lifted matcher; all 83 previously green tests are still
green in every run recorded here, which is what makes the refactor
behaviour-preserving rather than merely intended to be.

### The export shape these tests already pin

Stated as fact, not suggestion: a test already imports each of these and a wrong
guess is a failure, not a debate.

**`src/server/round/PhaseMachine.luau`** — required as
`require("../../src/server/round/PhaseMachine")` from `tests/server/`, so the
file must be at exactly that path. It returns a table with two **plain field
functions**, called with a dot, never a colon:

    PhaseMachine.initial(config, seed: number, roundId: string) -> RoundState
    PhaseMachine.step(state, event, now: number) -> (RoundState, { Effect })

`step` returns **two values**; the tests destructure both and assert
`typeof(effects) == "table"` and `#effects`, so the effect list is always a real
array, never `nil`, and empty means an empty table.

Fields the assertions read off a `RoundState`: `phase`, `phaseEnteredAt`,
`roundId`, `seed`, `players`, `outcome`. Fields read off effects:
`kind` on all three; `seed` and `players` on `AssignSeats`; `roundId` on
`ComputeTrace`; `PromptRematch` is read only for its `kind`.
Event tables are constructed by the tests as `{ kind = ... }` with `playerId`
on `PlayerJoined`/`PlayerLeft`/`RematchAccepted` and `outcome` on
`RoundResolved`.

**`src/server/round/RoundConfig.luau`** — required as
`require("../../src/server/round/RoundConfig")`. One export:

    RoundConfig.fromTuning(tuning) -> RoundConfig

returning a table whose key set is **exactly**
`{ lobbySeconds, postRoundSeconds, roundSeconds, playersMin, playersMax,
minPlayersToContinue }`, all numbers. The tests hand the machine a config
literal with those six keys, so the machine must read those names.

**Not constrained, and therefore yours:** the internal structure of either
module, any additional non-exported helpers, the exact derived value of the next
round's seed, whether the returning `Lobby` keeps `players`/`outcome`/`roundId`,
and whether phases without a specified duration consult the clock at all.

### Tests that pass on arrival, and what earns them

14 of this story's tests are green in RED. None of them is a regression guard
and none is decoration:

- **10 in `phase_machine_controls_test.luau`.** Each is an *inverted* assertion:
  it `pcall`s an AC-6 or AC-7 check against a deliberately wrong machine and
  requires it to **fail**. The check being observed to fail *is* the
  observation the law asks for, and it is the only way to get it while the
  production module does not exist. The six instrument tests are the same idea
  applied to `Deep.equal`, which every other assertion in the story leans on.
- **4 in `roblox_runtime_guard_test.luau`.** Same shape: the matcher must fire on
  a synthetic offending module and must *not* fire on comments, string literals
  or lookalike identifiers, and `scanFor` must find a real call in a real file on
  disk.

**One test in that file passes in RED for a bad reason and is guarded against
it:** `AC-8: no module under src/server/round references a Roblox runtime
global` would pass vacuously over an empty file list. It carries the same
`contains(PHASE_MACHINE) and contains(ROUND_CONFIG)` assertion the dedicated
vacuity test does, so it fails today and cannot ever pass over a directory that
was never created.

### Negative controls: expected values, and what was measured

**Every control below was actually run**, because none needs production code.
The values are measurements from `lune run test` in RED, taken by a temporary
probe test that printed each control's message and was then deleted. They are
still a *claim about GREEN*: the same checks must behave identically when
applied to the shipped module, and confirming that is GREEN's job.

| Control | Check | Expected | Measured in RED |
|---|---|---|---|
| `inert` | `stepDoesNotMutateItsInput` | passes | `ok=true` |
| `inert` | `stepIsDeterministic` | passes | passes |
| `inert` | `eventIsIgnored` | passes | passes |
| `mutating` | `stepIsDeterministic` | **passes** (the trap) | passes |
| `mutating` | `stepDoesNotMutateItsInput` | fails, naming AC-6 and the changed fields | `AC-6: step mutated the state it was given (a Tick in Lobby).` / `The input state before the call and after it differ:` / `value.phaseEnteredAt: expected 0, got 99` / `value.phase: expected "Lobby", got "Assignment"` — **2 difference lines** |
| `mutatingCopier` | identity check `returned ~= given` | **passes** — this is why AC-6 is not written as one | passes |
| `mutatingCopier` | `stepDoesNotMutateItsInput` | fails, naming the nested `players` field | `value.players.1: expected "p1", got "mutated"` plus `players.2/3/4 … got nil` — **4 difference lines** |
| `raising` | `eventIsIgnored` with `Tick` | passes (the stub is plausible) | passes |
| `raising` | `eventIsIgnored` with `RoundResolved` | fails, naming AC-7 and the case | `AC-7: step raised on a RoundResolved in Lobby instead of ignoring it: … PhaseMachine: unhandled event RoundResolved` |
| `chatty` | `eventIsIgnored` | fails on the empty-effect-list half | `AC-7: a RematchAccepted in Round produced 1 effect(s) and must produce none: { 1 = "PromptRematch" }` |
| `Deep.equal` | six differing pairs | `false` for every one | `false` for every one |
| `Deep.copy` | independence | mutating either side leaves the other alone | holds |
| Roblox matcher | offending module text | a hit for each of the 6 symbols | 6/6 found, path named in the rendered message |
| Roblox matcher | comments and string literals | 0 hits | 0 |
| Roblox matcher | `gamepad`, `scripted`, `subworkspace`, `self.script`, `self.game` | 0 hits | 0 |
| `scanFor` on disk | ROUND-001's committed probe | ≥ 1 hit, path = the probe | **1 hit**: `src/shared/__probe_clock_leak.luau:28 references os.clock` |
| `classify.sh --list source src/server/round` | the story's subject | 2 files after GREEN | **0 files** in RED — the vacuity guard's failure above |

**What GREEN must confirm:** run the same controls against the shipped module
and check the *values*, not merely that the control tests pass. In particular
the AC-6 non-mutation check must still produce a non-empty difference list when
pointed at `MachineStubs.mutating`, and `classify.sh --list source
src/server/round` must return both modules.

**Deferred verifications:** the story defers nothing, and RED declined nothing.
Every control named in AC-6 and AC-7 was demonstrable against a hand-written
stub and was demonstrated.

### The callers list, re-checked against the tree

The Contract says this returned 0 at `abf37d1`. **Re-checked, twice, and the
number moved — because RED itself moved it.** Both runs are from the working
tree at `abf37d1` (`HEAD` unchanged; the only tracked modifications are
`project.conf` and this story).

Before writing any test, at the start of RED:

    $ grep -rn "PhaseMachine\|RoundConfig" src tests lune | wc -l
    0

After writing the tests, just now:

    $ grep -rn "PhaseMachine\|RoundConfig" src tests lune | wc -l
    35
    $ grep -rln "PhaseMachine\|RoundConfig" src tests lune
    tests/helpers/MachineStubs.luau
    tests/helpers/PhaseMachineContract.luau
    tests/server/phase_machine_controls_test.luau
    tests/server/phase_machine_test.luau
    tests/server/roblox_runtime_guard_test.luau
    tests/server/round_config_test.luau
    $ grep -rn "PhaseMachine\|RoundConfig" src lune | wc -l
    0

All 35 are this story's own tests and helpers. **`src/` and `lune/` still
contain zero references**, which is the claim the Contract was actually making:
no existing export changes signature, and there is no caller for GREEN to break.

### Mutation predictions

The orchestrator should run mutation 1 first, through `scripts/mutate.sh`.
Predicted failures, by test:

| Mutation | Predicted failing tests | Count |
|---|---|---|
| **1.** phase-duration comparison `>=` → `>` | `AC-1: the Lobby leaves for Assignment at exactly lobbySeconds elapsed`; `AC-5: the Post phase leaves at exactly postRoundSeconds elapsed` | **2 tests, 1 assertion each** |
| **2.** `step` mutates and returns the input state | `AC-6: the step that leaves the Lobby does not mutate the state it was given` **with the AC-6 message**, `AC-6: step does not mutate the state it was given, in any phase`, the other 12 tests that use `journey()`, and `AC-8`'s phase-sequence test | **15** |
| **3.** the returning `Lobby` reuses the previous seed | `AC-5: the returning Lobby carries a seed distinct from the round that just ended` | **1 test, 1 assertion** |

Reasoning, so a wrong prediction is diagnosable rather than mysterious:

- **Mutation 1 is 2, not the 1 the story's `## Notes` predicted.** Every other
  clock-driven step in the suite crosses its boundary *strictly* (3.5 against 3,
  4 against 3, 8.5 and 2.5 against 2), so only the two exact-boundary tests can
  see the difference. The second one exists deliberately: without it an
  implementation could use `>=` for `Lobby` and `>` for `Post` and nothing would
  fail. **Target the expression, not the token** — a blanket `s/>=/>/` would
  also hit a `#players >= config.playersMin` guard if GREEN writes one, and with
  exactly `playersMin` players seated the Lobby would then never leave, taking
  roughly 20 tests with it and telling you nothing about the boundary. Prefer
  something like
  `s/now - state.phaseEnteredAt >= /now - state.phaseEnteredAt > /`.
- **Mutation 2 is 15, not 1, and 14 of the 15 are collateral rather than
  weakness.** The one to read is
  `AC-6: the step that leaves the Lobby does not mutate the state it was given`,
  which reaches its state with four seating steps in a single phase and so fails
  with AC-6's own message: *"step mutated the state it was given (the Tick that
  leaves Lobby)"*, followed by the differing fields. The rest fall out of
  aliasing: `journey()` drives one state through five phases and keeps all five,
  so a `step` that mutates and returns its input leaves five references to one
  table whose `phase` is `Post`, and `journey()`'s own phase assertions fire
  first — that accounts for 13 tests, including the all-phases AC-6 test, whose
  failure will therefore be attributed to `journey()` rather than to AC-6.
  `runLifecycle` records a phase only when `nextState.phase ~= state.phase`,
  never true when they are the same table, so `AC-8`'s phase-sequence test fails
  too. **If the isolated AC-6 test stays green under this mutation, AC-6 was
  written as an identity check and the story must go back to RED.** It was not:
  the same check is observed failing against `MachineStubs.mutating` and
  `MachineStubs.mutatingCopier` in every RED run.
- **Mutation 3 is exactly 1.** The determinism test still passes (reusing a seed
  is perfectly deterministic) and the different-seeds test still passes (two
  lifecycles seeded `n` and `n+1` end at `n` and `n+1`, which differ). Only the
  distinctness assertion can see it — which is what makes it worth having.

### Contract amendments, and why

Five, all in `## Contract` under *"AMENDED AT RED by the Test Developer"*, with
the reasoning next to each: `initial`'s exact return value (it takes no `now`,
so `phaseEnteredAt = 0` is the only self-consistent answer); `PlayerJoined`
seats a player (nothing else can, and AC-1 and AC-2 need seated players); a
duplicate `PlayerJoined` is ignored; **phase durations are evaluated only on
events the phase recognises**, because AC-7 says an unrecognised event returns
the state unchanged and says nothing about a due timer; and a step that changes
nothing emits nothing, which AC-8's exact effect sequence already implies.

The fourth is the one to read before implementing. It is the only place two
reasonable designs differ, and it costs one line: put the duration check inside
the `Tick` branch, not at the top of `step`.

No acceptance criterion changed, so there is no `## Amendments` entry.

### Timing, and where each number came from

All **local**, this machine, 2026-09-15; no CI numbers exist for this story yet.

- `lune run test`: **20.4 s, 22.5 s, 23.8 s** over three consecutive runs of the
  final 137-test suite on an otherwise idle machine.
- The `unit` gate under `gates.sh --fast`: **26 s**, against **16 s** recorded in
  `ROUND-002`'s full gate run for 83 tests. **The suite got slower and the cause
  is not this story's assertions**, which are table comparisons over six-field
  states and cannot account for seconds. It is `SourceScan`'s
  `process.exec("bash", "scripts/classify.sh", …)` calls, which is where the
  existing 16 s also went; this story adds one more of them
  (`--list source src/server/round`), and `SourceScan.refresh()` in ROUND-001's
  AC-6 fixture test invalidates the cache mid-run, so a new cache key costs more
  than one launch. That command takes **0.32 s** run directly from bash, so the
  overhead is in the spawn, not the script. Attribution by reasoning, not by
  measurement of each exec — flagged as such. **If a later story needs this back,
  the lever is the number of distinct `classify.sh` questions the suite asks, not
  the number of tests.**
- **No timeout budget applies to this suite.** `lune/test.luau` imposes no
  per-test timeout, there is no `beforeAll`/`afterEach` machinery to budget, and
  the `coverage` gate is UNCONFIGURED by decision (`stack.md` §4), so there is no
  instrumented second run to be slower than this one. If a timeout is ever added
  to the runner, these numbers are the baseline to size it against.

### What should change GREEN's approach

1. **Put the duration check in the `Tick` branch.** See Contract amendment 4.
   It is the single most likely way to fail a test you would otherwise expect to
   pass.
2. **`phaseEnteredAt` is set from the `now` of the step that transitions**, and
   the tests read it back (`Assignment` entered at 3.5, `Round` at 4,
   `Resolution` at 6). Carrying the old value forward, or using the previous
   step's `now`, fails immediately.
3. **Derive the next seed from `Rng`, not from a counter and not from a
   constant.** `Rng.fromSeed(state.seed):derive("nextRound"):nextInteger(…)`
   satisfies all three AC-5 seed tests; `seed + 1` also would, but a constant
   would not, and neither would anything reading a real random source.
4. **Build the new state with `table.clone` plus fresh nested tables** — a
   shallow copy that keeps the caller's `players` array and then appends to it
   fails `AC-6` at `value.players.5`, which is exactly the failure
   `MachineStubs.mutatingCopier` was written to demonstrate.
5. **`RoundConfig` is a plain mapping module.** It must not `require` the phase
   machine, and the phase machine must not `require` `Tuning` — the
   injected-config test is what would catch the second, and there is no test for
   the first because there is no reason to write one.
6. **Raise `floor | unit` in `project.conf` to the real pass count** once GREEN
   is green. The orchestrator does that in GATES; RED deliberately left it at
   83.

---

## GREEN: control values confirmed

In RED the production suite failed at `require`, so **not one assertion in
`phase_machine_test.luau` had executed** and every control value in the handoff
was a claim. Each one below was re-measured against the tree as shipped, by a
temporary probe (`control_probe.luau` at the repo root, run with
`lune run control_probe`, deleted afterwards) that calls the same
`PhaseMachineContract` checks the suite calls and prints the failure message and
its rendered line count. The story's controls are stub-based by construction -
`MachineStubs` is what a control fires against - so "against the shipped module"
means: the checks, unchanged, with the real module now present and loadable, plus
the same three checks pointed at the real machine.

| Control | Check | RED recorded | Measured in GREEN | Same? |
|---|---|---|---|---|
| `inert` | `stepDoesNotMutateItsInput` | passes (`ok=true`) | PASSED | yes |
| `mutating` | `stepDoesNotMutateItsInput` | fails; `AC-6: step mutated the state it was given (a Tick in Lobby).` / `The input state before the call and after it differ:` / `value.phaseEnteredAt: expected 0, got 99` / `value.phase: expected "Lobby", got "Assignment"` — **2 difference lines** | FAILED with that message verbatim, same two difference lines in the same order (4 rendered lines including the two headers) | yes |
| `mutatingCopier` | identity check `returned ~= given` | passes — which is why AC-6 is not written as one | `true` | yes |
| `mutatingCopier` | `stepDoesNotMutateItsInput` | fails; `value.players.1: expected "p1", got "mutated"` plus `players.2/3/4 … got nil` — **4 difference lines** | FAILED; `value.players.1: expected "p1", got "mutated"`, `value.players.2: expected "p2", got nil`, `value.players.3: …`, `value.players.4: …` — **4 difference lines** (6 rendered) | yes |
| `raising` | `eventIsIgnored` with `Tick` | passes (the stub is plausible) | PASSED | yes |
| `raising` | `eventIsIgnored` with `RoundResolved` | fails; `AC-7: step raised on a RoundResolved in Lobby instead of ignoring it: … PhaseMachine: unhandled event RoundResolved` | FAILED with exactly that text (`MachineStubs:85: PhaseMachine: unhandled event RoundResolved`) | yes |
| `chatty` | `eventIsIgnored` | fails on the empty-effect-list half; `AC-7: a RematchAccepted in Round produced 1 effect(s) and must produce none: { 1 = "PromptRematch" }` | FAILED with that message verbatim | yes |
| `classify.sh --list source src/server/round` | the guard's subject | **0 files** in RED (the vacuity guard's failure) | **2 files**: `src/server/round/PhaseMachine.luau`, `src/server/round/RoundConfig.luau` | moved as predicted |

**No value diverged from RED's record.** Every message, and both difference
counts, reproduce exactly - including the ordering of the two lines in the
`mutating` case, which `Deep.diff` derives from `pairs` order and which was not
guaranteed to match.

The same three checks applied to the **shipped** `PhaseMachine`, in a Lobby with
four players seated, over and above what the suite asserts:

| Check | Case | Result |
|---|---|---|
| `stepDoesNotMutateItsInput` | the Tick that leaves Lobby, `now = 3.5` | PASSED |
| `stepIsDeterministic` | the Tick that leaves Lobby, `now = 3.5` | PASSED |
| `eventIsIgnored` | a `RoundResolved` in Lobby at `now = 9`, with the Lobby's 3 s duration long due | PASSED — Contract amendment 4 holds against the real machine, not only against a stub |

### The named mechanism, probed rather than taken on trust

The Contract names `Rng.fromSeed(previousSeed):derive("nextRound"):nextInteger(…)`
as the way to derive the next round's seed, and that is a claim about `Rng`'s
behaviour. Measured (`seed_probe.luau`, run and deleted the same way), with the
shipped `nextSeedFrom` and `nextInteger(1, 2^31 - 1)`:

    seed 20260915 -> 2030163546
    seed 20260916 -> 1232454520
    over 200000 consecutive seeds: fixed points = 0, distinct-seed collisions = 0
    deterministic: true
    five chained rounds from 20260915: 2030163546, 2046861026, 1742749893,
                                       2081026026, 455417474

So over the swept range the derivation never returns its own input (AC-5's
distinctness) and never maps two seeds to one (AC-5's vacuity case), and it is
reproducible (AC-6). **What the sweep does not prove:** the output space is 2^31
and the input space is every number a double holds, so collisions must exist
somewhere by pigeonhole, and a fixed point outside `[1, 200000]` is not excluded.
Neither is reachable by any criterion in this story, and neither is worth
defending against with a retry loop that nothing tests. Recorded so that a later
story which needs a **guaranteed**-distinct seed knows this is a measured
property of a range, not a proof.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-15T23:34:04Z
    commit: abf37d1 (working tree had uncommitted changes)
    tree:   5d401ef57e39016f740bc4a49c14b9bec3611f0a
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 21)
    PASS         lint (1s, observed 21, floor 1)
    PASS         typecheck (3s, observed 5)
    PASS         unit (15s, observed 137, floor 137)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 15638)
    UNCONFIGURED mutation

