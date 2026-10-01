---
id: SLICE-002
title: Every declared remote is bound through the wrapper and secrets reach only their player
slug: every-declared-remote-is-bound-through-t
epic: EPIC-03
type: feature
status: todo
phase: PLANNED
branch: story/SLICE-002-every-declared-remote-is-bound-through-t
depends_on: [SLICE-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. B4's one enforceable rule is "no `OnServerEvent:Connect`
outside `src/net/`" (`architecture.md` §4, D6), and it is already guarded by
`tests/net/raw_remote_guard_test.luau` — which also forbids `.OnClientEvent`
outside `src/net/`. M0–M2 built the pipeline (`Remotes`, `Schema`, `Wrapper`,
`RateLimiter`) and **never connected it to a `RemoteEvent`**. This story builds
the one module allowed to, on both sides, and makes the second trust rule of M3
structural: **a per-player payload is sent to its player only** (`architecture.md`
§9.7, D13).

It also adds the `@net` alias (D21), because `src/server/` and `src/client/`
will require `src/net/` across the instance tree.

**Which required gate would fail if this story's artifact broke:** `unit` — the
binding and routing are tested against injected fakes of `RemoteEvent`. The
real `RemoteEvent` adapter is a Studio check (`SLICE-004`).

## Acceptance criteria

- **AC-1** — Given a set of declared remotes and a handler for each, when
  `Transport.bind` runs, then each declaration's `RemoteEvent` has exactly one
  `OnServerEvent` connection, and a call arriving on it reaches the handler only
  through `Wrapper.guard` — shown by a malformed call being rejected with the
  wrapper's `shape` reason and never reaching the handler.
  *Control:* a `bind` that connects the handler directly (no guard) must fail
  this AC: the malformed call reaches the handler.
- **AC-2** — Given a declared remote with no handler, or a handler for a name
  that was never declared, when `Transport.bind` runs, then it raises, naming
  the remote. A declared-but-unbound remote is a silently dead wire; an
  undeclared handler is an unvalidated one.
- **AC-3** — Given a bound transport, when a per-player payload
  (`SeatView`, `LensView`, `TurnCues`, `TurnResult`, `PresetFailed`, `PingRefused`) is sent for player `p`, then it is
  delivered with `FireClient` to `p`'s player object and to no other, and
  `FireAllClients` is never called for it.
  *Control:* a `sendTo` implemented with `FireAllClients` must fail this AC.
- **AC-4** — Given a bound transport, when `broadcast` is called with a
  per-player payload kind, then it raises and nothing is fired. When it is
  called with a public kind (`RoundView`, `FacilityView`, `PresetShown`,
  `TraceView`), `FireAllClients` is called once with the payload.
- **AC-5** — Given a call on a remote from a player object the id port cannot
  map to a seated `PlayerId`, when it arrives, then it is rejected with the
  wrapper's `identity` reason — the transport passes the mapped id, never the
  raw object, into the guard.
- **AC-6** — Given the client side, when `ClientTransport.on(kind, fn)` is
  registered and the server fires that kind, then `fn` receives the payload;
  and `ClientTransport.send(remoteName, args)` calls `FireServer` on that
  remote's event with `args` as the single payload. `.OnClientEvent` appears in
  no source module outside `src/net/` (the existing guard, which must still pass
  with the new modules in its scanned set).
- **AC-7** — Given `.luaurc`, when it is read, then it declares exactly the
  aliases `shared` → `src/shared` and `net` → `src/net`, and no alias whose
  target is under `src/server` or `src/client`.

## Contract

**Modules.** `src/net/Transport.luau` (server) and
`src/net/ClientTransport.luau` (client). Both take their Roblox objects through
ports so the tests can pass fakes.

    export type PayloadKind = "SeatView" | "LensView" | "TurnCues" | "TurnResult" | "PresetFailed" | "PingRefused"  -- per-player: sendTo only
                            | "RoundView" | "FacilityView" | "PresetShown" | "TraceView"  -- public: broadcast only
    Transport.PRIVATE_KINDS: { [string]: true }  -- exactly the first six
    Transport.PUBLIC_KINDS: { [string]: true }   -- exactly the last four

    export type RemoteEventLike = {
        OnServerEvent: { Connect: (self: any, fn: (player: any, payload: any) -> ()) -> any },
        FireClient: (self: any, player: any, payload: any) -> (),
        FireAllClients: (self: any, payload: any) -> (),
    }
    export type Ports = {
        remoteEvent: (name: string) -> RemoteEventLike,  -- one per declared remote, plus one per PayloadKind
        idOf: (player: any) -> string?,                  -- nil: not a player this server knows
        playerFor: (playerId: string) -> any?,
    }
    export type Bound = {
        sendTo: (self: Bound, playerId: string, kind: PayloadKind, payload: any) -> (),
        broadcast: (self: Bound, kind: PayloadKind, payload: any) -> (),
    }
    Transport.bind(definitions: { Remotes.RemoteDefinition }, context: Wrapper.GuardContext,
                   handlers: { [string]: (playerId: string, args: any) -> () }, ports: Ports) -> Bound

- Server→client payloads each travel on their **own** `RemoteEvent` named by
  the kind, so a client listening for `RoundView` cannot be handed a `LensView`.
- An unmapped player (`idOf` → nil) is passed to the guard as a non-string id,
  which `Wrapper`'s identity check already rejects (`describeCaller`). Do not
  add a second identity check here.
- `sendTo` for a `playerId` with no player object (`playerFor` → nil) is a
  no-op, not a raise: a player may leave between building and sending a view.

    ClientTransport.on(kind: PayloadKind, fn: (payload: any) -> ()) -> ()
    ClientTransport.send(remoteName: string, args: any) -> ()
    ClientTransport.init(ports: { remoteEvent: (name: string) -> any }) -> ()

**`.luaurc`** gains `"net": "src/net"`. This is `config`, written in GREEN.
AC-7's test reads it through `tests/helpers/GatedFs.luau` (HARNESS-022), never
`@lune/fs` directly; if `classify.sh --gated` does not include `.luaurc`, RED
stops and says so rather than reading around the gate.
`SLICE-001`'s result decides whether this alias resolves in a place; this story
starts only after it (`depends_on`).

**Existing exports: no signature changes.**

**Oracle partition.** All criteria are **mechanical**: pin exact calls on the
fakes (which method, which arguments, how many times). The controls in AC-1 and
AC-3 are hand-written wrong implementations the tests are shown to fail against.

## Deferred verifications

**D-1. The routing test discriminates.** With `Transport.luau`'s `sendTo`
changed by `scripts/mutate.sh` to call `FireAllClients`, AC-3's test **must**
fail; with `bind`'s guard call bypassed, AC-1's must. RED cannot run this —
there is no `Transport` to mutate. Owner: GATES.

## Out of scope

- The real `RemoteEvent` creation in a place and the driver that calls `bind`
  (`SLICE-004`).
- Any game remote's declaration (`CHAN-003`, `CHAN-005`, `PROC-005`).
- Payload contents: this story routes kinds, it does not build views.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-002` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table. Only what lies BETWEEN these two markers is rewritten when
this command runs again; the rest of the section is yours and is preserved.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `fable` | the measured case. With a partitioned contract to work from, the brief carries the judgement and the weaker model writes sharper negative controls than the stronger one did without it |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

Lock coverage: SUPPRESSED by `src/net/ClientTransport.luau` (source), `src/net/Transport.luau` (source), `tests/helpers/GatedFs.luau` (test), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Oracle partition as in `## Contract`: every criterion is mechanical. Brief RED
with the port shapes and the two hand-written wrong implementations as controls.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain:
       * the exact command that runs the new tests
       * the failure output, and why it is the RIGHT failure
       * every file touched, and which AC each test covers
       * the EXPORT SHAPE the tests already pin: every module they import, the
         exact exported names and signatures, and the types the assertions
         destructure. Not a suggestion - a test already imports them, so a
         wrong guess is a compile error. Say what the tests do NOT constrain
         too, so it stays the implementer's choice.
       * any test that passed on arrival, and the probe or negative control
         that earns it
       * the EXPECTED VALUE of every negative control, as a table: threshold,
         candidate range, and the number the control measured. In RED the
         suite fails at import, so no assertion in it has run - the controls
         are claims until GREEN confirms them against the shipped module
       * anything discovered that changes the approach -->

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A test that is wrong is never edited into passing, and the
     return is not a footnote - it is the story failing to be one clean cycle,
     and the next person needs to know why. One block per return:
       * which test, what it asserted, and what was wrong with it
       * how the defect was found
       * what it asserts now
       * what earns it, since "watched it fail" cannot apply once the
         implementation exists - the corrected assertion passes on its first
         run and every run after, whether or not it asserts anything: either a
         PROBE (mutate the specific behaviour the test pins, paste the red,
         confirm the revert) or, where the defect was cost rather than
         correctness, a BEFORE/AFTER measurement taken under the gate command -
         not the plain test command, which is the faster one.
         PASTE THE OUTPUT. check-boundaries.sh refuses a PR whose Regressions
         or Gate probes section describes a failure without showing one
       * whether GREEN was a no-op, and the command output proving the source
         was untouched and still passes -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Scaffold inventory

<!-- REQUIRED for a bootstrap or chore story that writes production code under
     SCAFFOLD, where nothing forces a test to exist first, and for a spike that
     commits its throwaway code. Omit otherwise.
     One line per production file written, and for anything with behaviour
     rather than configuration, the test that covers it:
       src/core/palette.ts        - src/core/palette.test.ts
       vite.config.ts             - configuration, no behaviour
     check-boundaries.sh refuses the PR if any changed source file is not
     named here. -->

## Notes

