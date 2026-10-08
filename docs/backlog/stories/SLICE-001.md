---
id: SLICE-001
title: A module requires across layers inside a real Rojo-served place
slug: a-module-requires-across-layers-inside-a
epic: EPIC-03
type: spike
status: done
phase: DONE
branch: story/SLICE-001-a-module-requires-across-layers-inside-a
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. **Nothing in this repository has yet executed inside a Roblox
runtime.** `docs/wiki/architecture.md` §1 ("The limit") records that alias
requires (`require("@shared/Rng")`) are verified under `luau-lsp analyze` and
under Lune, and are **untested in a real place**: `.luaurc` is not synced by
`default.project.json`, and the `build` gate proves only that the place file
builds. Every M3 runtime story (`SLICE-002` onward) depends on the answer, and
M3 also plans a second alias, `@net` (`architecture.md` D21).

This is a **spike**: a timeboxed investigation whose output is a decision in
`docs/wiki/architecture.md`, not shipped code. It needs Roblox Studio, so the
**operator runs the Studio half**; the Lead PO prepares the probe and records
the result.

**Which required gate would fail if this story's artifact broke:** none — the
artifact is a recorded observation. It is a spike precisely because no gate can
hold it; the stories it unblocks carry their own Studio checks.

## Acceptance criteria

- **AC-1** — Given the project served by `bash scripts/task.sh dev` into an empty
  Studio place, when a server `Script` under `ServerScriptService/Server` runs
  `require("@shared/Clock")`, then the result is recorded verbatim: either the
  module table, or the exact error text.
- **AC-2** — Given the same place, when a `LocalScript` under
  `StarterPlayerScripts/Client` runs `require("@shared/Clock")`, then the result
  is recorded verbatim in the same way.
- **AC-3** — Given a file named `*.server.luau` under `src/server/` and one named
  `*.client.luau` under `src/client/`, when Rojo syncs them, then the recorded
  observation names the class Studio shows for each (expected: `Script` and
  `LocalScript`).
- **AC-4** — Given AC-1 to AC-3's results, when the spike closes, then
  `architecture.md` §1 "The limit" is replaced by the observed result and, if
  aliases do **not** resolve, by the chosen fallback with its reason, and the
  Lead PO has written or re-planned the story that implements the fallback
  before `SLICE-002` starts.

## Contract

**The probe, prepared by the Lead PO and never committed.** Two throwaway files
the operator creates locally (or on a scratch branch that is deleted):

    src/server/__spike_require.server.luau
        print("server alias:", pcall(require, "@shared/Clock"))
        print("server relative:", pcall(require, "../../ReplicatedStorage/Shared/Clock"))
    src/client/__spike_require.client.luau
        print("client alias:", pcall(require, "@shared/Clock"))

Run in Studio with **Test → Start** (one client is enough). Paste the Output
window lines into `## Notes`.

**Probe extended by the Lead PO, 2026-10-07 (PLANNED; no AC changed).** The
files as written locally add three lines:
- each script prints `script.ClassName` and `script:GetFullName()` (AC-3);
- `server instance:` and `client instance:`: an instance require of
  `ReplicatedStorage.Shared.Clock`. This baseline separates "the module does not
  load" from "the alias does not resolve";
- `server chain (Generator):` requires `facility/Generator` by instance. Its own
  requires are strings (`./Layout`, `../seats/Ring`, `@shared/MechanicsTuning`,
  `@shared/Tuning`), which is how every real module in `src` is written, and
  what `MAP-001`'s D-1 snippet depends on. `@shared/Clock` alone cannot show
  this: `Clock` requires nothing.

Headless cross-check for AC-3, not a substitute for it: `rojo sourcemap` (Rojo
7.7.0) maps `__spike_require` to `"className":"Script"` under `Server` and
`"className":"LocalScript"` under `Client`.

**If AC-1 or AC-2 fails**, the fallbacks to weigh, in order of preference:

1. A `.luaurc` (or whatever configuration Roblox's require-by-string reads in a
   place) mapped into the place by `default.project.json`, so `@shared` resolves
   there as it does under `luau-lsp` and Lune.
2. `architecture.md` §1's recorded fallback: an instance require in the place
   behind a Lune-side shim, so source keeps one spelling.

Relative paths across a layer are **not** a fallback: §1 records why they fail
under `luau-lsp`.

**Oracle partition.** AC-1 to AC-3 are **mechanical** observations: record
exactly what Studio prints. AC-4 is a decision.

## Out of scope

- Any remote, any gameplay, any UI.
- Committing the probe files. They are deleted when the spike closes.
- `CHAN-001`'s questions (preset delivery route, filtering). Separate spike.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `default.project.json` (config), `src/client/__spike_require.client.luau` (source), `src/server/__spike_require.server.luau` (source), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

The operator performs the Studio steps; the Lead PO writes the result into
`architecture.md` §1 and, if needed, the fallback story. No RED or GREEN
dispatch exists for a spike.

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


**Observation 1 (operator run, Lead PO reading the log, 2026-10-07).** Roblox
Studio 0.742.0.7421053, Rojo 7.7.0 (CLI and plugin), a new Baseplate, then
**Play** (solo). The lines are copied verbatim from Studio's log,
`%LOCALAPPDATA%\Roblox\logs\0.742.0.7421053_20261007T215138Z_Studio_0CBC4_last.log`,
which carries every Output line (`[FLog::Output]` / `[FLog::CreatorOutput]` /
`[FLog::CreatorError]`):

    SLICE-001 server class: Script ServerScriptService.Server.__spike_require
    server alias: false error requiring "@shared/Clock": @shared is not a valid alias
    server relative: true table: 0x0f43f5f794c08cf0
    server instance: true table: 0x0f43f5f794c08cf0
    Error: error requiring "@shared/MechanicsTuning": @shared is not a valid alias
    Info: Script 'ServerScriptService.Server.facility.Layout', Line 24
    Error: Requested module experienced an error while loading
    Info: Script 'ServerScriptService.Server.facility.Generator', Line 40
    server chain (Generator): false Requested module experienced an error while loading
    SLICE-001 client class: LocalScript Players.corthan73.PlayerScripts.Client.__spike_require
    client alias: false error requiring "@shared/Clock": @shared is not a valid alias
    client instance: true table: 0xcf241a2b08beafcb

- **AC-1:** `@shared` does not resolve on the server: `@shared is not a valid alias`.
- **AC-2:** `@shared` does not resolve on the client either, with the same error.
- **AC-3:** the server probe is a `Script` and the client probe a `LocalScript`.
  The operator also confirmed both in the Explorer, and `rojo sourcemap` agrees.
- **Relative requires within a layer resolve.** `Generator`'s `./Layout` loaded,
  and the failure came one level down, at `Layout`'s `@shared` line. So did a
  relative path across the DataModel (`../../ReplicatedStorage/Shared/Clock`
  from the server script).
- **Consequence for `MAP-001` D-1:** its snippet cannot run until this is fixed,
  because every module that requires `@shared` fails to load in a place.

**Why fallback 1 is unavailable (researched 2026-10-07).** Roblox has not
shipped custom require aliases. The latest staff statement on the
require-by-string announcement thread (2026-01-08) says they are "working on"
it. Only the built-in `@self` and `@game` aliases exist
(https://devforum.roblox.com/t/introducing-require-by-string/3405078). No file
Rojo could map into the place would define `@shared`.

**`@game` checked against our tooling (Lead PO, 2026-10-07):**
- `luau-lsp analyze` 1.69.0 with the Rojo sourcemap **resolves**
  `require("@game/ReplicatedStorage/Shared/Clock")`. A probe module that
  annotated it as `number` got `TypeError: Expected this to be 'number', but
  got 'Clock'`.
- `lune` 0.10.5 **does not**:
  `error requiring module "@game/ReplicatedStorage/Shared/Clock": @game is not a valid alias`.
- Studio: probe lines `server game alias:` and `client game alias:` have been
  added, and are awaiting a second Play.

**Observation 2 (second Play, same session, 2026-10-07 22:02 UTC):**

    server game alias: true table: 0x9e333e8e77839707
    client game alias: true table: 0xace9ede3db5a50b3

The built-in `@game` alias resolves on both sides. Lune also resolves
`@game/ReplicatedStorage/Shared/X` once `.luaurc` declares `"game": "<dir>"`.
That was checked with a throwaway tree under the ignored `build/`, which printed
`true { ok = "shared via @game" }`, and the tree was deleted afterwards.

**Decision (operator, 2026-10-07): mirror the DataModel on disk.** The Lead PO
put three options to the operator:
1. mirror the DataModel on disk (`src/ReplicatedStorage/{Shared,Net}`, with
   `.luaurc` declaring `"game": "src"`);
2. a generated junction or symlink tree for Lune;
3. instance requires behind a Lune shim.

The operator chose option 1, the Lead PO's recommendation. The reasons and the
rejected alternatives are in `architecture.md` §1.

**AC-4 discharged:**
- `architecture.md` §1: "The limit" and "M3 settles this first" are replaced by
  "Measured in a real place", which records the observed result, the decision
  and its reason. D21 (`@net`) is marked superseded.
- The fallback story is written: **`SLICE-008`** (chore, `depends_on:
  [SLICE-001]`).
- `SLICE-002` is re-planned while still PLANNED: `depends_on` gains `SLICE-008`,
  AC-7 now asserts the single `game` alias instead of adding `@net`, and its
  `.luaurc` contract and Context are rewritten to match.

**Probe files deleted** at close: `src/server/__spike_require.server.luau` and
`src/client/__spike_require.client.luau`. They were never committed.

**Knock-on, recorded for `MAP-001`:** its D-1 snippet cannot run until
`SLICE-008` merges. `SLICE-008`'s D-1 runs it.

**DONE (2026-10-07).** PR https://github.com/ryanczhang7/first-roblox/pull/66 merged. Docs-only spike; CI timings not load-bearing.
