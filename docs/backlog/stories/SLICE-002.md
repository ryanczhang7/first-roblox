---
id: SLICE-002
title: Every declared remote is bound through the wrapper and secrets reach only their player
slug: every-declared-remote-is-bound-through-t
epic: EPIC-03
type: feature
status: in-progress
phase: RED
branch: story/SLICE-002-every-declared-remote-is-bound-through-t
depends_on: [SLICE-001, SLICE-008]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. B4's one enforceable rule is "no `OnServerEvent:Connect`
outside `src/ReplicatedStorage/Net/`" (`architecture.md` §4, D6), and it is already guarded by
`tests/net/raw_remote_guard_test.luau` — which also forbids `.OnClientEvent`
outside `src/ReplicatedStorage/Net/`. M0–M2 built the pipeline (`Remotes`, `Schema`, `Wrapper`,
`RateLimiter`) and **never connected it to a `RemoteEvent`**. This story builds
the one module allowed to, on both sides, and makes the second trust rule of M3
structural: **a per-player payload is sent to its player only** (`architecture.md`
§9.7, D13).

It reaches `src/ReplicatedStorage/Net/` (moved from `src/net` by `SLICE-008`) through
`@game/ReplicatedStorage/Net/…`; the `@net` alias (D21) is superseded (`SLICE-001`).

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
  no source module outside `src/ReplicatedStorage/Net/` (the existing guard, which must still pass
  with the new modules in its scanned set).
- **AC-7** — Given `.luaurc`, when it is read, then it still declares exactly
  one alias, `game` → `src` (`SLICE-008`); this story adds no alias. Every
  require of the net layer from `src/server` or `src/client` begins
  `@game/ReplicatedStorage/Net/` (re-planned by the Lead PO at `SLICE-001`'s
  close, 2026-10-07, while this story is PLANNED: `@net` is superseded).

## Contract

**Modules.** `src/ReplicatedStorage/Net/Transport.luau` (server) and
`src/ReplicatedStorage/Net/ClientTransport.luau` (client). Both take their Roblox objects through
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

**Pinned at PLANNED → RED (Lead PO, 2026-10-08).** These blocks are the
contract GREEN builds. RED may amend a block in place with a one-line reason;
GREEN builds what the amended block says.

- **C-1. Handlers carry the call control.** The `handlers` parameter is typed
  `{ [string]: (playerId: string, args: any, call: Wrapper.CallControl) -> () }`
  — the signature `Wrapper.guard` already takes — not the two-argument form
  sketched above. `Ping` and `SendPreset` handlers decline through
  `call.decline()` (CHAN-003, D18); a transport that dropped the third
  argument would make every decline unreachable in a real place. `bind` hands
  each handler to `Wrapper.guard` itself; the `CallControl` the wrapper builds
  reaches the handler.
- **C-2. The connected function returns the guard's result.** The function
  `bind` connects to `OnServerEvent` returns what the guarded function returns
  (`nil` or a `Wrapper.Rejection`). Roblox discards it; tests read it, and that
  is how AC-1's `shape` and AC-5's `identity` are observed.
- **C-3. Identity.** The connected function calls `ports.idOf(player)` once
  and passes its result — a string, or `nil` — as the guard's `playerId`. The
  raw player object never reaches the guard, `context.isSeated` or the
  handler.
- **C-4. Ports are read at bind time.** `bind` calls `ports.remoteEvent(name)`
  exactly once for each declared remote and exactly once for each of the ten
  `PayloadKind`s. `sendTo` and `broadcast` never call `ports.remoteEvent`.
- **C-5. `bind` validates before it touches anything.** On an AC-2 failure it
  raises before calling `ports.remoteEvent` or connecting anything. The
  message names the remote (a declared-but-unhandled name, or a handled but
  undeclared one).
- **C-6. Kind discipline, both directions.** `sendTo` with a public kind, and
  `sendTo` or `broadcast` with a string in neither set, raise naming the kind,
  and fire nothing. (`broadcast` with a private kind is AC-4.)
- **C-7. `ClientTransport` is module state with explicit init.** `on` or
  `send` before any `init` raises, naming the call. `init` may be called again
  and replaces the ports (each test inits its own fakes). `on` connects
  `ports.remoteEvent(kind).OnClientEvent` and raises for a kind in neither
  set; `send` calls `ports.remoteEvent(remoteName):FireServer(args)` with
  `args` as the single argument after `self`. `ClientTransport` may require
  `Transport` for the kind sets.
- **C-8. No other changes.** No existing export's signature changes, so there
  are no callers to list (checked with `rg` over `src` and `tests` at PLANNED:
  nothing calls a `Transport` or `ClientTransport` yet). The existing guard
  `tests/net/raw_remote_guard_test.luau` may be extended in RED to name the
  two new modules in its scanned set.

**`.luaurc`** is not changed by this story. **Re-planned at `SLICE-001`'s close
(2026-10-07):** Roblox has no custom aliases, so `@net` (D21) is superseded.
After `SLICE-008`, the net layer lives at `src/ReplicatedStorage/Net` and is
required as `@game/ReplicatedStorage/Net/…`. Every net-layer path in this story
means that directory. AC-7's test reads `.luaurc` through
`tests/helpers/GatedFs.luau` (HARNESS-022), never `@lune/fs` directly; if
`classify.sh --gated` does not include `.luaurc`, RED stops and says so rather
than reading around the gate.

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

Lock coverage: SUPPRESSED by `src/ReplicatedStorage/Net/ClientTransport.luau` (source), `src/ReplicatedStorage/Net/Transport.luau` (source), `tests/helpers/GatedFs.luau` (test) (+1 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- RED - `test-developer` - `claude-fable-5-1` (dispatched with an explicit `model: fable`; the agent reported no override). 2026-10-08.

## Test plan

**Level: unit, against injected fakes.** Every criterion is mechanical, so
every test pins exact calls on recording fakes of `RemoteEvent` - which
method, which arguments, how many times. The idiom is the repo's
`*Contract.luau` + `*Stubs.luau` + `*_controls_test.luau` triple, so that each
check is EXECUTED in RED against a hand-written transport with one known
defect while the real-module suite is red at require.

| File | Role |
|---|---|
| `tests/helpers/TransportStubs.luau` | `fakeRemoteEvent(name)` (records `OnServerEvent.Connect`, `FireClient`, `FireAllClients`, `OnClientEvent.Connect`, `FireServer`), `ports(players)` (the Contract's `Ports` over an id→object map, recording every `remoteEvent`/`idOf`/`playerFor` call), `correct()` (a reference transport driving the real `Wrapper.guard`) and `with(defect)` for 27 one-defect transports |
| `tests/helpers/TransportContract.luau` | 21 checks over `{ Transport, ClientTransport }`, one per AC clause / Contract block |
| `tests/net/transport_controls_test.luau` | 27 tests: the baseline passes all 21 checks; every defect fails EXACTLY the pinned set (measured first, see Handoff); the two criterion-named controls (AC-1 no-guard bind, AC-3 broadcasting `sendTo`) are here |
| `tests/net/transport_test.luau` | 21 tests applying the checks to the real `@game/ReplicatedStorage/Net/Transport` and `ClientTransport` - red at require in RED |
| `tests/net/net_requires_test.luau` | AC-7: `.luaurc` through `GatedFs` (one alias, `game` → `src`); every require from `src/server`/`src/client` that reaches the net layer by ANY spelling begins `@game/ReplicatedStorage/Net/`; two in-memory controls of the rule |
| `tests/net/raw_remote_guard_test.luau` | C-8: `NET_MODULES` extended with `Transport.luau` and `ClientTransport.luau` (red in RED: not yet in the scanned set) |
| `.claude/tests/project-counters.test.sh` | counter baselines set to the predicted post-GREEN values (217/217/37, narrow 37/37/9) |

| Check (TransportContract) | Covers |
|---|---|
| `bindConnectsEachDeclaredRemoteExactlyOnce` | AC-1 (one connection per remote; none on the ten kind events) |
| `malformedCallIsRejectedForShapeAndNeverReachesTheHandler` | AC-1, C-2 (`shape`, handler count 0; non-table payload too) |
| `wellFormedCallReachesTheHandlerWithTheMappedIdAndACallControl` | AC-1, C-1, C-2, C-3 (nil result, mapped `"p2"`, third arg has `decline`) |
| `aHandlerThatDeclinesMakesTheConnectedFunctionReturnDeclined` | C-1 (`declined` through the wrapper's own CallControl) |
| `bindRaisesNamingADeclaredRemoteWithNoHandlerBeforeTouchingPorts` | AC-2, C-5 (names `Orphaned_Declared`; 0 `remoteEvent` calls; nothing connected) |
| `bindRaisesNamingAHandlerForAnUndeclaredRemoteBeforeTouchingPorts` | AC-2, C-5 (names `Stray_Handler`) |
| `bindReadsEveryPortExactlyOnceAndSendsReadNone` | C-4 (12 calls, each name once; sends/broadcasts add none) |
| `sendToFiresEachPrivateKindOnItsOwnEventToThatPlayerOnly` | AC-3 (six kinds, `FireClient` once on the kind's event with `playerFor`'s object; `FireAllClients` 0 globally) |
| `sendToForAPlayerWithNoObjectIsANoOp` | Contract (no raise, nothing fired, `playerFor` asked once per send) |
| `broadcastWithAPrivateKindRaisesNamingItAndFiresNothing` | AC-4 |
| `broadcastFiresEachPublicKindOnceOnItsOwnEvent` | AC-4 |
| `kindSetsAreExactlyTheSixAndTheFour` | AC-4 (both sets, both directions) |
| `sendToWithAPublicOrUnknownKindRaisesNamingItAndFiresNothing` | C-6 |
| `broadcastWithAnUnknownKindRaisesNamingItAndFiresNothing` | C-6 |
| `unmappedPlayerIsRejectedForIdentityAndTheRawObjectReachesNothing` | AC-5, C-3 (`identity`; `idOf` once with the object; `isSeated` sees nil, not the object) |
| `mappedPlayerIsIdentifiedOncePerCallAndNeverSeenRaw` | C-3 (`isSeated` sees `"p1"`,`"p2"`; `idOf` once per call) |
| `clientOnAndSendBeforeInitRaiseNamingTheCall` | C-7 |
| `clientOnDeliversEachKindsPayloadToItsOwnListener` | AC-6 (ten kinds, one `OnClientEvent` connection each, own payload only) |
| `clientSendCallsFireServerWithArgsAsTheSinglePayload` | AC-6 (`select("#")` == 1 and `args[1] == args`) |
| `clientOnWithAKindInNeitherSetRaisesNamingIt` | C-7 |
| `clientInitAgainReplacesThePorts` | C-7 |

**Edges covered:** empty/unknown kind strings (`""`, `"seatview"`, `"RoundViews"`,
`"Nonsense"`), a non-table payload, a player who left between build and send,
a mapped-but-unseated player versus an unmapped one, a second `init`.
**Out of scope and not tested:** real `RemoteEvent` creation and the `bind`
driver (SLICE-004), any game remote's declaration, payload contents.

## Handoff: RED -> GREEN

**Written by the Test Developer, 2026-10-08. Dispatched on the planned `fable`
row (model `claude-fable-5-1`, from the model's own identification; no
override was reported in the dispatch).**

### The command

    lune run test                      # the whole suite (~4 min here); the unit gate
    lune run test -- --list            # discovery

The runner has no per-file filter. For a single file, a scratch runner under
the gitignored `build/` is what RED used (not committed; recreate it):

    mkdir -p build && cat > build/one_test.luau <<'EOF'
    local process = require("@lune/process")
    local passed, failed = 0, 0
    for _, path in process.args do
    	if path == "--" then continue end
    	local ok, suite = pcall(require, "../" .. path)
    	if not ok then print(`  LOAD FAIL  {path}\n             {tostring(suite)}`); failed += 1
    	else
    		local names = {} for name in suite do table.insert(names, name) end table.sort(names)
    		for _, name in names do
    			local ran, err = pcall(suite[name])
    			if ran then passed += 1; print(`  pass  {path} :: {name}`)
    			else failed += 1; print(`  FAIL  {path} :: {name}\n        {tostring(err)}`) end
    		end
    	end
    end
    print(`{passed} passed, {failed} failed`)
    process.exit(if failed > 0 or passed == 0 then 1 else 0)
    EOF
    lune run build/one_test.luau -- tests/net/transport_test tests/net/transport_controls_test

### The failure, verbatim (RED tree, `lune run test` under `gates.sh --fast`)

    FAIL  tests/net/transport_test.luau :: AC-1: after bind, each declared remote's event has exactly one OnServerEvent connection, every one of the ten kind events has none, and none has an OnClientEvent connection
          D:\first-roblox\tests\net\transport_test:34: src/ReplicatedStorage/Net/Transport.luau did not load: error requiring module "@game/ReplicatedStorage/Net/Transport": could not resolve child component "Transport"
    ... (the same for all 21 tests in transport_test.luau; the first assertion in bundle() fires on Transport, so ClientTransport's load failure is masked until Transport exists)
    FAIL  tests/net/raw_remote_guard_test.luau :: AC-7: the scanned set is the real source tree - at least six modules, including three outside src/ReplicatedStorage/Net/ and the net layer's five inside it (SLICE-002 adds Transport and ClientTransport)
          D:\first-roblox\tests\net\raw_remote_guard_test:103: src/ReplicatedStorage/Net/Transport.luau is not in the scanned set, so the guard cannot know it is the exempt layer and not a missing one: ...
    1434 passed, 23 failed

Why it is the right failure: the two modules are the first thing the story
requires, and nothing else in the tree is red. `gates.sh --fast` on this tree:
format PASS (215), lint PASS (215), typecheck PASS (35), build PASS, **unit
FAIL (the 23 above and nothing else)**, **harness FAIL (counter baselines,
see below - expected in RED)**.

The 27 controls in `transport_controls_test.luau` and the 4 AC-7 tests in
`net_requires_test.luau` are GREEN in RED, by design - see "Controls" and
"Passed on arrival".

### Files touched

| File | AC |
|---|---|
| `tests/helpers/TransportStubs.luau` (new) | fakes + reference + 27 defects |
| `tests/helpers/TransportContract.luau` (new) | AC-1..AC-6, C-1..C-7 checks (table in `## Test plan`) |
| `tests/net/transport_controls_test.luau` (new) | the controls, executed in RED |
| `tests/net/transport_test.luau` (new) | AC-1..AC-6, C-1..C-7 against the real modules |
| `tests/net/net_requires_test.luau` (new) | AC-7 |
| `tests/net/raw_remote_guard_test.luau` (edited) | AC-6 second half / C-8: `NET_MODULES` += `Transport.luau`, `ClientTransport.luau`; one test name reworded |
| `.claude/tests/project-counters.test.sh` (edited) | baselines → predicted post-GREEN 217/217/37, narrow 37/37/9; narration block |
| `docs/backlog/stories/SLICE-002.md` | `## Test plan`, this section |

**The RED commit.** `.claude/tests/**` edits are refused by `check-boundaries`
from any phase but RED (check 3j), and the `harness` gate's "no stray .luau
files" precondition is red until the test files are committed. The
orchestrator must commit this tree with the story at `phase: RED` before
GREEN starts. GREEN never edits the counters; if GREEN adds a third source
file, the counters are wrong and that is a return to RED.

### The export shape the tests already pin (fact, not suggestion)

`src/ReplicatedStorage/Net/Transport.luau`, required as
`@game/ReplicatedStorage/Net/Transport`, returns a table with:

- `Transport.PRIVATE_KINDS: { [string]: true }` — keys exactly `SeatView`,
  `LensView`, `TurnCues`, `TurnResult`, `PresetFailed`, `PingRefused`, each
  `== true`; no other key.
- `Transport.PUBLIC_KINDS: { [string]: true }` — keys exactly `RoundView`,
  `FacilityView`, `PresetShown`, `TraceView`; no other key.
- `Transport.bind(definitions, context, handlers, ports) -> Bound`, called
  with `.` (not `:`). `definitions` are plain `Remotes.RemoteDefinition`
  tables (`{ name, args = Schema.shape(...), legalPhases = { "Round" } }`),
  NOT registered through `Remotes.define`. `context` has `isSeated`, `phase`,
  `clock.now` only (no `telemetry`). `handlers[name]` is
  `(playerId, args, call) -> ()` and must be handed to `Wrapper.guard` as is.
  `ports` is `{ remoteEvent(name), idOf(player), playerFor(playerId) }`,
  called as plain functions (`ports.idOf(player)`, not `ports:idOf`).
- `bind` connects, per declared remote, exactly ONE function via
  `ports.remoteEvent(def.name).OnServerEvent:Connect(fn)` where
  `fn(player, payload)` RETURNS `guarded(ports.idOf(player), payload)` —
  `nil` or the `Wrapper.Rejection`. `idOf` is called exactly once per call.
  It calls `ports.remoteEvent` exactly once per declared name and once per
  each of the ten kinds, all at bind, AFTER the AC-2 validation; on an AC-2
  failure it raises (any `error` form; the tests read `tostring(err)`) with
  the remote's name as a plain substring and has called `remoteEvent` zero
  times. The fake's `Connect` returns a table with `Disconnect`; the tests
  do not care whether you keep it.
- `Bound:sendTo(playerId, kind, payload)` and `Bound:broadcast(kind,
  payload)` are called with `:` (self first). `sendTo` → exactly one
  `event:FireClient(ports.playerFor(playerId), payload)` on the event
  `remoteEvent(kind)` returned AT BIND; `playerFor` → nil is a silent return
  (`playerFor` is called once per send, before any fire). `broadcast` →
  exactly one `event:FireAllClients(payload)` on that kind's bind-time event.
  Both raise with the kind as a plain substring on the wrong set or an
  unknown string (including `""`), firing nothing.

`src/ReplicatedStorage/Net/ClientTransport.luau`, required as
`@game/ReplicatedStorage/Net/ClientTransport`, returns a table with:

- `ClientTransport.init(ports)` — `ports.remoteEvent(name)` only. Callable
  again; the second ports fully replace the first.
- `ClientTransport.on(kind, fn)` — before any `init`: raises with a message
  containing both `ClientTransport.on` and `init` as plain substrings.
  Unknown kind: raises with the kind as a substring and calls
  `ports.remoteEvent` zero times. Otherwise exactly one
  `ports.remoteEvent(kind).OnClientEvent:Connect(fn)`; the fake invokes `fn`
  with the single payload.
- `ClientTransport.send(remoteName, args)` — before `init`: raises naming
  `ClientTransport.send` and `init`. Otherwise exactly one
  `ports.remoteEvent(remoteName):FireServer(args)` with `args` as the ONE
  argument after self (`select("#", ...) == 1`).

**Not constrained** (implementer's choice): the exact wording of every raise
beyond the named substrings; `error` level; whether `bind` validates
unhandled-before-undeclared or the reverse; whether `ports.remoteEvent` is
called before or after `Wrapper.guard` within bind; whether the kind events
are fetched before or after the remote events (only the count and the
"after validation" order are pinned); what `Connect`'s return is done with;
the Luau types (the typecheck gate judges `--!strict`, the tests do not);
whether `ClientTransport` requires `Transport` for the kind sets (C-7 allows
it) or re-declares them; `ClientTransport.init` on the server is never
exercised.

**One ordering fact GREEN inherits.** `ClientTransport` is module state, so
`transport_test.luau`'s before-init test must run before any other test in
that file calls `init`. The runner sorts a file's names and `(` sorts before
every letter and digit, so the test named `AC-6 (first) C-7: ...` runs
first. Do not add a test to that file whose name sorts before it and inits.

### Passed on arrival, and what earns each

`tests/net/net_requires_test.luau` (AC-7) is green on arrival: `.luaurc`
already has one alias, and NO module under `src/server` or `src/client`
requires the net layer today (`rg 'Net/' src/server src/client` at RED:
nothing - the driver is SLICE-004's). Both tree assertions were earned with
`scripts/mutate.sh`, which restored and verified each file:

Probe 1 - a relative net require in a real server module:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau 's|require("@game/ReplicatedStorage/Shared/Rng")|require("../../ReplicatedStorage/Net/Wrapper")|' -- lune run build/one_test.luau -- tests/net/net_requires_test
    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed by ...) ===
      150 - local Rng = require("@game/ReplicatedStorage/Shared/Rng")
      150 + local Rng = require("../../ReplicatedStorage/Net/Wrapper")
      FAIL  tests/net/net_requires_test :: AC-7: every require from src/server or src/client that reaches the net layer begins @game/ReplicatedStorage/Net/
            D:\first-roblox\tests\net\net_requires_test:143: 1 net-layer require(s) over 20 file(s) do not begin @game/ReplicatedStorage/Net/:
    src/server/round/PhaseMachine.luau:150 requires "../../ReplicatedStorage/Net/Wrapper"; it must begin @game/ReplicatedStorage/Net/
    3 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20261008T194111Z.1074691.bak) ===

Note this spelling PASSES SLICE-008's `layer_requires_test` (its rule permits
every `../` require), which is why this file exists rather than a duplicate.

Probe 2 - a second alias in `.luaurc`:

    $ bash scripts/mutate.sh .luaurc 's|"game": "src"|"game": "src", "net": "src/ReplicatedStorage/Net"|' -- lune run build/one_test.luau -- tests/net/net_requires_test
      FAIL  tests/net/net_requires_test :: AC-7: .luaurc, read through GatedFs, declares exactly one alias and it is game -> src
            D:\first-roblox\tests\net\net_requires_test:110: .luaurc must alias exactly "game" and nothing else; it aliases: game, net
    3 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/.luaurc.20261008T194122Z.1074992.bak) ===

`raw_remote_guard_test.luau`'s other tests pass unchanged; its scanned-set
test is red (above) and goes green when the two modules exist.

### Controls: measured sets (RED, outside the runner, then pinned)

Every check was run against the baseline and each of the 27 defects with a
scratch script (`build/measure_transport.luau`, same loop as
`failsExactly`). Baseline: 0 of 21 checks fail. The controls suite pins each
set EXACTLY, so a check that goes vacuous or over-eager shows as a red line
in `transport_controls_test.luau`. These ran and passed in RED (27/27); they
need no GREEN confirmation because they never touch the real module, but
GREEN should re-run the file and see 27/27 still.

| Defect | Checks it fails (label, as in the controls file) | First failure names |
|---|---|---|
| `bindBypassesGuard` (**AC-1's control, D-1 #2**) | AC-1 shape, C-1 decline, AC-5, C-3 (4) | `expected a Rejection with reason "shape", got nil` |
| `bindConnectsTwice` | all 12 server checks that build a world (fixture vacuity guard) | `"Ping" has 2 OnServerEvent connection(s)` |
| `bindAcceptsUnhandled` | AC-2 unhandled (1) | `expected a raise naming "Orphaned_Declared"` |
| `bindAcceptsUndeclared` | AC-2 undeclared (1) | `expected a raise naming "Stray_Handler"` |
| `bindReadsPortsFirst` | AC-2 unhandled, AC-2 undeclared (2) | `bind called ports.remoteEvent 3 time(s) before raising (C-5)` |
| `bindRaiseOmitsName` | AC-2 unhandled, AC-2 undeclared (2) | `the raise does not name "Orphaned_Declared"` |
| `dropsCallControl` | AC-1 handler, C-1 decline (2) | `the handler received 2 argument(s) and call = nil` |
| `connectedReturnsNil` | AC-1 shape, C-1 decline, AC-5, C-3 (4) | `expected a Rejection with reason "shape", got nil` |
| `passesRawPlayer` | AC-1 shape, AC-1 handler, C-1 decline, AC-5, C-3 (5) | `a caller sending table as a player id` |
| `idOfCalledTwice` | AC-5, C-3 (2) | `ports.idOf was called 2 time(s) for one call` |
| `kindEventsReadLazily` | AC-1 once, C-4 (2) | `bind never asked ports.remoteEvent for the kind "SeatView"` |
| `sendToFiresAll` (**AC-3's control, D-1 #1**) | AC-3 (1) | `called FireAllClients (1 call(s) across every event) for a per-player payload (AC-3)` |
| `sendToOnSharedEvent` | AC-3 (1) | `sendTo("p2", "LensView") called FireClient on "LensView" 0 time(s)` |
| `sendToRaisesWithoutPlayer` | C-4, AC-3 no-op (2) | `no player for "nobody"` |
| `sendToAcceptsPublicKind` | C-6 sendTo (1) | `expected a raise naming "RoundView"` |
| `sendToFiresTwice` | AC-3 (1) | `called FireClient on "SeatView" 2 time(s)` |
| `broadcastAcceptsPrivate` | AC-4 private (1) | `expected a raise naming "SeatView"` |
| `broadcastFiresTwice` | AC-4 public (1) | `called FireAllClients on "RoundView" 2 time(s)` |
| `broadcastOnSharedEvent` | AC-4 public (1) | `called FireAllClients on "FacilityView" 0 time(s)` |
| `unknownKindAccepted` | C-6 sendTo, C-6 broadcast (2) | `expected a raise naming "Nonsense"` |
| `privateKindsMissingOne` | C-4, AC-3, AC-3 no-op, AC-4 sets, AC-6 on (5) | `"PingRefused" is not a per-player payload kind` |
| `publicKindsHaveExtra` | AC-4 private, AC-4 sets (2) | `broadcast("LensView"): expected a raise naming "LensView"` |
| `clientNoInitCheck` | C-7 init (1) | `the raise does not name "init"` |
| `clientOnAcceptsUnknownKind` | C-7 unknown (1) | `expected a raise naming "Nonsense"` |
| `clientSendWrapsArgs` | AC-6 send (1) | `expected exactly one, the args table itself` |
| `clientInitKeepsFirstPorts` | C-7 replace (1) | `the first ports were still used after init was called again` |
| `clientOnSharedEvent` | AC-6 on, C-7 replace (2) | `on("SeatView") never asked ports.remoteEvent for "SeatView"` |

No threshold or metric exists in this story (all criteria are mechanical), so
there is no "candidate range" column: each control's expected value is "fails
exactly these checks", and the measured value equals it.

### D-1 (owner: GATES) - declined here, with the prediction

RED cannot run D-1: there is no `Transport.luau` to mutate. GATES runs it
with `bash scripts/mutate.sh src/ReplicatedStorage/Net/Transport.luau '<expr>' -- lune run test`.
From the controls above, the predicted red in `transport_test.luau`:

| D-1 mutation of the real module | Tests predicted red in `transport_test.luau` |
|---|---|
| `sendTo` calls `FireAllClients` instead of `FireClient` | exactly 1: `AC-3: sendTo for each of the six per-player kinds ...`, failing on `called FireAllClients (1 call(s) across every event) for a per-player payload (AC-3)` |
| `bind` connects the handler without `Wrapper.guard` (handler called directly with the mapped id) | exactly 4: `AC-1: a seated player's { token = "four" } ...` (shape → nil), `C-1: a handler that calls call.decline() ...`, `AC-5 / C-3: ... idOf maps to nil ...`, `C-3: across a seated and an unseated ...`. If the bypass also drops the third argument, add `AC-1 / C-1 / C-2: ... CallControl ...` (5) |

If GATES measures a different set, the suite's discrimination has changed
and it is worth a line in `## Gate probes`.

### Discovered, and worth knowing before implementing

- `Wrapper.guard` does NOT pcall the handler, so a handler error (e.g. the
  `dropsCallControl` control's `attempt to index nil with 'decline'`)
  propagates out of the connected function. The Contract does not ask
  `bind` to contain it; the tests do not pin either behaviour.
- `idOf` → nil must be passed to the guard as `nil` (C-3). `Wrapper`'s
  `identity` check handles it (`isSeated(nil) ~= true`), and the AC-5 test
  asserts `context.isSeated` received a non-table. Do not add a second
  identity check in `bind` - the test counts `isSeated` calls (exactly 1).
- `SourceScan` returns `src/ReplicatedStorage/Net/.gitkeep` in the source
  set (visible in the guard's failure message). Pre-existing, harmless to
  every assertion here; not this story's.
- No contract block was amended. C-1..C-8 were implementable as written by
  the reference transport in `TransportStubs.luau`.

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

**PO decisions at PLANNED → RED (2026-10-08, Lead PO, `/complete-story`).**

1. **Required gate:** `unit` (required) — `covers | unit | src/ReplicatedStorage/Net/**`
   in `project.conf`. Every criterion is exercised against fakes under
   `lune run test`; `required_gates` stays empty because no optional gate is
   needed.
2. **Contract C-1 (handler arity).** The sketched two-argument handler would
   have silently disabled CHAN-003's decline path for `Ping` and `SendPreset`
   (`src/server/channel/Pings.luau:199`, `PresetSends.luau:106` take a
   `call`). Pinned to `Wrapper.guard`'s own handler signature. No AC text
   changed.
3. **Epic done-when.** EPIC-03 clauses 2 and 3 are this story's; clause 2's
   `src/net/` is the pre-SLICE-008 name for `src/ReplicatedStorage/Net/`. No
   gap between SLICE-008 and this story.
4. **AC-7 is largely already enforced** by SLICE-008's
   `tests/shared/layer_requires_test.luau` and the `.luaurc` checks. A test
   that passes on arrival must be earned by a `scripts/mutate.sh` probe in RED.

