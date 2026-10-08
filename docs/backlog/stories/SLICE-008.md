---
id: SLICE-008
title: Modules load in a real place: shared code moves under the DataModel path and requires use @game
slug: modules-load-in-a-real-place-shared-code
epic: EPIC-03
type: chore
status: todo
phase: PLANNED
branch: story/SLICE-008-modules-load-in-a-real-place-shared-code
depends_on: [SLICE-001]    # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. Written by the Lead PO on 2026-10-07 to close `SLICE-001`
(AC-4), which measured in a real place that **`@shared` is not a valid alias**
in Roblox, while the built-in **`@game`** resolves. The full result and the
operator's decision are in `docs/wiki/architecture.md` §1 ("Measured in a real
place"). In one line: every module that requires `@shared` fails to load in
Studio today, so no Studio check, including `MAP-001`'s D-1, can run.

The decision: mirror the DataModel on disk for the shared layers, and spell
cross-layer requires `@game/ReplicatedStorage/...`.

- `src/shared` → `src/ReplicatedStorage/Shared` (`git mv`, history kept)
- `src/net` → `src/ReplicatedStorage/Net`
- `.luaurc` declares exactly `"aliases": { "game": "src" }`
- every `require("@shared/X")` → `require("@game/ReplicatedStorage/Shared/X")`
- `src/server` and `src/client` keep their paths

This is a **chore** under SCAFFOLD. It is one indivisible move: the directory,
the alias, the require strings, the Rojo mapping, `paths.conf` and the gate
`covers` lines all depend on each other, and none of them can be written
test-first before the others exist. The one new behaviour, the layer guard
(AC-3), still gets a failing test first, with its probe.

**Which required gate would fail if this story's artifact broke:** `unit` (the
guard and the whole suite through the new paths), `typecheck` (`luau-lsp`
resolving `@game` through the alias and the sourcemap), and `build` (the Rojo
mapping). The in-place half is `D-1`, run by the operator.

## Acceptance criteria

- **AC-1** — Given the tree after the move, when every source and test module is
  scanned (the file list from `scripts/classify.sh`, as the existing guards
  do), then no string require begins `@shared` or `@net`, and nothing under
  `src/shared` or `src/net` exists any more.
- **AC-2** — Given `.luaurc`, when it is read, then it declares exactly one
  alias, `game` → `src`.
- **AC-3** — Given a source module under `src/`, when it holds a string require
  that leaves its own layer, then the guard refuses it unless the require begins
  `@game/ReplicatedStorage/`. In particular, a module under `src/client` that
  requires `@game/ServerScriptService/...` is refused, and the refusal names the
  file and the require.
  *Control:* a committed `__probe_` module under `src/client/` that requires
  `@game/ServerScriptService/Server/round/PhaseMachine` must be reported.
- **AC-4** — Given the moved tree, when the full gate run executes, then the
  `unit`, `typecheck`, `lint`, `build` and `harness` gates pass. The test count
  is not lower than before the move (1373 at `37efbeb`), and `typecheck`
  analyses the same number of source files as before, the moved ones included.

## Contract

Pinned by the Lead PO at PLANNED, 2026-10-07. RED may amend a block in place
with a reason; SCAFFOLD builds what the amended block says.

**C-1. Paths.** `git mv src/shared src/ReplicatedStorage/Shared` and
`git mv src/net src/ReplicatedStorage/Net`. Every file keeps its name.
`default.project.json` maps `ReplicatedStorage.Shared` to
`src/ReplicatedStorage/Shared` and `ReplicatedStorage.Net` to
`src/ReplicatedStorage/Net`. The DataModel is unchanged:
`ReplicatedStorage.Shared.Clock` is still at that instance path.

**C-2. Requires.** In `src/`, `require("@shared/X")` becomes
`require("@game/ReplicatedStorage/Shared/X")`. Same-layer relative requires
(`./Layout`, `../seats/Ring`) are untouched. They were measured working in a
place. Tests keep requiring source by file path (`../../src/...`) and are
updated to the new paths. Callers checked on 2026-10-07 with
`rg -l '@shared/' src tests lune`: `src/net/{Wrapper,RejectionReporter,GameRemotes}`
and, under `src/server/`, `session/Session`, `round/{RoundView,RoundConfig,PhaseMachine}`,
`procedure/Procedure`, `channel/{PresetSends,Pings}`, `seats/Ring` and
`facility/{Steps,Par,Generator,Machines,Layout,Blockout}`. No test or `lune/`
file uses the alias. About 119 non-doc files spell `src/shared` or `src/net` as
a path (`rg -l 'src/(shared|net)\b' --glob '!docs/**' .`); SCAFFOLD
re-runs that command and the result must be empty, outside `## Notes` history.

**C-3. Harness configuration that names the old paths:** `paths.conf` and every
`covers` line in `project.conf` naming `src/shared/**` or `src/net/**`,
`selene.toml` if it does, the `discovery | shared` line (it greps
`tests/shared/`, which does **not** move), and
`.claude/tests/project-counters.test.sh` if it names paths. Test directories
keep their names (`tests/shared`, `tests/net`).

**C-4. The guard (AC-3).** A test under `tests/shared/` reads the source file
list from `scripts/classify.sh --list source src` through the existing
`SourceScan` helper. It classifies each file's layer as `shared`, `net`,
`server` or `client` by path, and treats each string require as follows:
- `./` and `../` stay inside the layer;
- `@game/ReplicatedStorage/Shared/…` and `@game/ReplicatedStorage/Net/…` are the
  only permitted crossings;
- `@self` is permitted;
- any other `@…` is a violation.

`net` may require `shared`; `shared` requires nothing outside itself. Do not
build a second scanner: `rules.md` explains why.

**C-6. Planned stories and the wiki.** Every PLANNED story and every
`docs/wiki/` page that spells `src/shared`, `src/net`, `@shared` or `@net` is
updated to the new spelling in the same PR. Stories already DONE keep their
history. Find them with `rg -l 'src/(shared|net)|@shared|@net' docs`.

**C-5. Oracle partition.** Every AC is **mechanical**: an exact file list,
an exact alias table, an exact refusal with its control, and exact counts read
from the gate evidence before and after.

## Deferred verifications

**D-1. Studio (the operator).** Serve the moved tree (`bash scripts/task.sh dev`)
into a new Baseplate, then Play. In the command bar, run
`print(pcall(require, game.ServerScriptService.Server.facility.Generator))`;
it must print `true`. Then run `MAP-001`'s D-1 snippet (its `## Notes`) and
record that story's outstanding Studio check here or there. Owner: REVIEW.

**D-2. The guard discriminates against the real tree.** Using
`scripts/mutate.sh`, change one real require in `src/server/round/RoundView.luau`
from `@game/ReplicatedStorage/Shared/` to `@game/ServerStorage/Shared/`. AC-3's
guard must fail, naming that file, and must pass again after the restore.
Owner: GATES.

**D-3. Which resolution `luau-lsp` uses for `@game`.** With
`"game": "src"` in `.luaurc`, `luau-lsp` might resolve `@game` through the alias
(the file tree) or natively (the sourcemap). Record which it does, by probing a
require of a path that exists only in one of the two, so the next person
knows. Owner: GATES.
## Amendments

<!-- Acceptance criteria are frozen once the story leaves PLANNED. If one turns
     out to be wrong or unsatisfiable, stop, put it to the product owner, and
     record the change here: which AC, what it said, what it says now, who
     approved it and why. check-boundaries.sh fails a PR whose criteria differ
     from the base branch without an entry here. Omit the section if unused.
     Where the change came from a subagent's claim that the criterion was
     wrong, record the ORCHESTRATOR'S OWN reproduction of it - different
     inputs, not the subagent's code. That claim is also what an agent says
     when it wants to stop failing. -->

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write SLICE-008` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `default.project.json` (config), `scripts/classify.sh` (tooling), `selene.toml` (config), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

<!-- FILLED BY A TOOL, not by hand: `bash scripts/plan.sh write <id>`, as the
     last step of PLANNED once the ## Contract exists. It renders the per-phase
     plan from .claude/harness/models.conf with the reason for each row. Run it
     again after amending the contract; it rewrites only the region between the
     `plan.sh:generated` markers. Everything you write OUTSIDE them in this
     section is preserved - that is where the two halves below belong.

     Not at story creation: the plan depends on the contract, and the "no
     contract, so RED stays on the stronger model" exception would be baked in
     before anybody had a chance to write one.

     What you add BY HAND is the other half - a departure from the plan, and
     the model each dispatch RESOLVED to. Make a departure falsifiable rather
     than folklore:
       * which phase, which model, and why that phase specifically
       * THE RESOLVED MODEL ACTUALLY DISPATCHED, by name - never the word
         "default". An agent definition's `model:` field, or the session's
         setting, or an override: the orchestrator cannot see which won unless
         it records it. Two stories once compared "the default model" against a
         stronger one, and neither could say what the default had resolved to,
         so the comparison may have been the stronger model against itself
       * what the orchestrator should stay on
       * HOW to brief it differently - a model chosen for judgement wants the
         criteria and the constraints, not a pre-decided test design
       * the ORACLE PARTITION of the criteria: which are settled (read the
         numbers out, do not calibrate), which are oracle-free (invent the
         metric and demand a negative control that fires hard), which are
         mechanical (pin exactly). Measured to matter more than the model
       * a success condition that could come out either way
     Then record the VERDICT against that condition when the phase ends, with
     evidence. The verdict is the part that gets skipped, and without it a model
     choice becomes a habit nobody can argue with. -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

<!-- Explicit non-goals. Prevents the Feature Developer from over-building. -->

## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

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

