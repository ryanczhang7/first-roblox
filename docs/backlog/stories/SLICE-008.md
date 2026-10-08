---
id: SLICE-008
title: Modules load in a real place: shared code moves under the DataModel path and requires use @game
slug: modules-load-in-a-real-place-shared-code
epic: EPIC-03
type: chore
status: in-progress
phase: RED
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

This is a **chore**, run as a full RED → GREEN cycle rather than under
SCAFFOLD. Lead PO, 2026-10-08, revised at PLANNED → RED; no AC changed. The
phase lock splits the move cleanly:
- every test file, the harness suites (`.claude/tests/**`, which
  check-boundaries 3j allows only in RED) and `project.conf` are writable in
  RED;
- every source file, `.luaurc` and `default.project.json` are writable in GREEN.

So RED points the tests and guards at the new paths and adds AC-1 to AC-3's
guards. The suite then fails for the right reason: the modules are not at the
new paths yet. GREEN does the `git mv`, the require strings and the
configuration, under a test freeze. See C-7.

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

*Amended in RED (test-developer, 2026-10-08), count only - the decision is
unchanged.* The C-2 list above names **17** files, not 19, and they hold
**27** `require("@shared/…")` calls, not 32: measured with
`rg -l 'require\("@shared/' src | wc -l` → 17 and
`rg -o 'require\("@shared/[^"]*"\)' src | wc -l` → 27 on `3b2c8ec`. The 32
was a line count that included comment mentions (`rg -c '@shared' src` sums
to 31 lines). AC-1's guard reports the same 27, by file and line, in the RED
run pasted in the handoff. `src/server/facility/Blockout.luau` (MAP-001) is in
the list and was missing from the sentence above.

**C-3. Harness and configuration that name the old paths** (checked on
2026-10-08 with `rg -l --hidden 'src/(shared|net)|@shared|@net'`). Live,
non-comment uses:
- `.claude/harness/project.conf`: `covers | unit | src/shared/**` and
  `src/net/**`, and the `discovery | sourcemap` grep for
  `src/shared/Scaffold.luau`. Owner: RED (harness).
- `.claude/tests/project-counters.test.sh`: the `NARROW_TYPECHECK` target
  `src/shared` (it stays 9 files), and `UNTRACKED_REL` and `UNFORMATTED_REL`
  under `src/shared/`. Owner: RED.
- `.claude/tests/harness-gate.test.sh`: `PROBE_REL` under `src/shared/`.
  Owner: RED.
- `default.project.json` and `.luaurc`. Owner: GREEN.

Not changed:
- `.claude/tests/stray-luau.test.sh` builds `src/shared` inside its own temp
  fixture, which is independent of the repository layout;
- comments in `scripts/stray-luau.sh` and the history comments in
  `project-counters.test.sh`;
- `.claude/skills/stack-profiles/reference/roblox-luau.md`, a generic stack
  profile.

Test directories keep their names (`tests/shared`, `tests/net`).
`selene.toml` names no path.

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

**C-7. The phase split, and what each phase leaves.**
- **RED** (test-developer):
  - the AC-1 to AC-3 guards, with AC-3's committed probe
    `src/client/__probe_cross_layer.luau`. It requires
    `@game/ServerScriptService/Server/round/PhaseMachine` and nothing else,
    and classifies as `test` under the `__probe_` convention;
  - every `src/shared` and `src/net` path in `tests/**` and `lune/**` rewritten
    to `src/ReplicatedStorage/Shared` and `src/ReplicatedStorage/Net`;
  - C-3's RED rows;
  - `project-counters` baselines set to the **predicted post-GREEN** values,
    then committed in a `phase: RED` commit (memory:
    counter-baselines-move-in-red).

  At the end of RED, nearly the whole unit suite fails at import with
  "could not resolve" on `src/ReplicatedStorage/...`. That is the right
  failure. Any other failure is not.
- **GREEN** (feature-developer):
  - `git mv` the two directories;
  - rewrite the 27 `@shared/` requires in the 17 C-2 files (count amended in
    RED, see C-2; three of the 17 are the `src/net` modules, which GREEN
    rewrites at their new `src/ReplicatedStorage/Net` path);
  - `.luaurc` → exactly `{"game": "src"}`; keep its other keys;
  - `default.project.json`;
  - no test edits.
- **Counts that must not move (AC-4):**
  - the format and lint evidence grows only by RED's new test files and the
    probe;
  - typecheck grows only by the probe (`src/client/__probe_cross_layer.luau` is
    under `src`);
  - `NARROW_TYPECHECK` stays 9 over the new shared directory;
  - unit stays ≥ 1373 plus RED's new tests.

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

Lock coverage: SUPPRESSED by `default.project.json` (config), `scripts/classify.sh` (tooling), `scripts/stray-luau.sh` (tooling) (+3 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

Written by the test-developer in RED, 2026-10-08. Every AC is mechanical
(C-5), so every test pins an exact thing: a file list, an alias table, a
refusal with its control, a count. Nothing here invents a threshold.

**Level.** All unit, under Lune, over the tree and over in-memory text. The
file lists come from `scripts/classify.sh` through `SourceScan` (no second
scanner, per `rules.md`); every file read goes through `GatedFs` so it is in
the gate tree hash. `.luaurc` IS in `classify.sh --gated` (checked:
`bash scripts/classify.sh --gated .luaurc` prints `.luaurc`), so AC-2 reads it
through `GatedFs.readFile`.

**New files**

| File | Covers | What it pins |
|---|---|---|
| `tests/helpers/LayerRequires.luau` | AC-1, AC-3 | the C-4 rule as a function of (path, text): `layerOf`, `requiresIn` (lexed through `SourceScan.codeOnly`, so a require in a comment or string is not one), `reasonFor`, `violationsIn`, `scan`, `retiredAliasesIn`, `describe` |
| `tests/shared/layer_requires_test.luau` | AC-1, AC-2, AC-3 | the tree: no `@shared`/`@net` require in any source or test module; `src/shared` and `src/net` gone; the moved modules present in the classifier's source set; `.luaurc` aliases exactly `game -> src`; zero layer violations over `--list source src`; every source file in a known layer; the committed probe reported exactly once, by file and by require, when the scan is run over `source + test` |
| `tests/shared/layer_requires_controls_test.luau` | AC-1, AC-3 | the rule on in-memory modules, both directions: six positive cases that must PASS (server → `@game/ReplicatedStorage/Shared/Rng`, `./Layout`, `../seats/Ring`, `@game/ReplicatedStorage/Net/…`; client → shared and net; net → shared; shared → `./` inside itself; `@self`; no requires) and eleven refusals, each checked to name the file AND the require (client → `@game/ServerScriptService/…`; server → `@game/StarterPlayer/…`; server → `@game/ServerScriptService/…`; shared → `@game/ReplicatedStorage/Net/…`; `@shared/X`; `@net/X`; `@game/ReplicatedStorage/Packages/…`; `@game/ReplicatedStorage/SharedExtras/…`; `@lune/net`; a bare name; a file in no layer). Plus the scanner's own discrimination: comments, string literals, `requireAll`/`prerequire`/`{ require = }`, single quotes, unparenthesised `require "x"`, line numbers, every violation in a file not only the first |
| `src/client/__probe_cross_layer.luau` | AC-3 control | requires `@game/ServerScriptService/Server/round/PhaseMachine` and nothing else; classifies as `test` (`classify.sh --list test src` lists it) |

**Rewritten files** (AC-1's other half, C-7 RED): 110 files under `tests/**`
and `lune/**`, 355 substitutions, `src/shared` → `src/ReplicatedStorage/Shared`
and `src/net` → `src/ReplicatedStorage/Net`, with `\b` so `src/network/Y.luau`
in `raw_remote_guard_test.luau` stayed as it was. Test directory names
(`tests/shared`, `tests/net`) untouched. Then `stylua` over `tests lune`,
because 100-column lines moved. Proof of completeness:
`rg -n 'src/(shared|net)\b' tests lune` → empty (only the three new files
name the old spellings, as needles).

**C-3's RED rows**: `project.conf` (`covers | unit` for both moved dirs, the
`discovery | sourcemap` grep), `project-counters.test.sh` (narrow typecheck
target, `UNTRACKED_REL`, `UNFORMATTED_REL`, the baselines), `harness-gate.test.sh`
(`PROBE_REL`). `stray-luau.test.sh` untouched, as C-3 says.

**Counters (predicted post-GREEN, set in RED):** 210/210/35, narrow 35/35/9.
Arithmetic in the file's comment block: 206 observed + 3 test files + 1 probe
= 210 for format and lint; 34 + 1 probe = 35 for typecheck and the narrow src
cases; NARROW_TYPECHECK stays 9 over `src/ReplicatedStorage/Shared` (the same
nine files `src/shared` holds today, probe included; GREEN moves and adds
none).

**What is NOT tested here and why.** `default.project.json`'s mapping is the
`build` gate's and `discovery | sourcemap`'s (the grep for
`src/ReplicatedStorage/Shared/Scaffold.luau` in the sourcemap). `.luaurc`'s
other keys (`languageMode`, `lint`, `globals`) are not pinned: AC-2 is about
the alias table. D-1, D-2 and D-3 are declined below.

## Handoff: RED -> GREEN

Written by the test-developer, 2026-10-08, on the uncommitted RED tree at
`3b2c8ec` + this story's changes. Model: dispatched as `fable` per the plan
(the agent definition's `model:` field); no override was stated.

### The command

    lune run test

The runner walks all of `tests/`; there is no per-file invocation. ~50 s on
this machine in RED (most suites fail at import, so it is faster than the
4 min baseline). The gates' view: `bash scripts/gates.sh --fast`.

### The failure, verbatim, and why it is the right one

Summary line (`lune run test`, second run, after the one fix below):

    180 passed, 132 failed

Baseline before this story: `1373 passed, 0 failed`. The 132 break down as:

- **74 `LOAD FAIL`** - whole suites that require a moved module by file path
  and cannot load. Every one of the 74 reads the same way, e.g.

        LOAD FAIL  tests/server/generator_test.luau
                   runtime error: error requiring module "../../src/ReplicatedStorage/Shared/MechanicsTuning": could not resolve child component "ReplicatedStorage"

  (38 via `MechanicsTuning`, 24 via `Clock`, 6 via `Rng`, 2 via
  `channel/Presets`, 2 via `Tuning`, 1 via `telemetry/Event`, 1 via
  `Scaffold`). The 1373 tests inside them are not counted until GREEN moves
  the files; C-7 predicted this and it is the right failure.
- **58 assertion failures** in suites that loaded, all about the not-yet-moved
  tree: `clock_test` (7), `rng_test` (16), `tuning_test` (11),
  `tuning_spec_test` (2) - `pcall(require)` of the new path then
  `did not load: ... could not resolve child component "ReplicatedStorage"`;
  `gated_fs_test` (3) - reads `src/ReplicatedStorage/Shared/Scaffold.luau`,
  which is not on disk / not in the gate hash yet; `source_guard_test` (4),
  `roblox_runtime_guard_test` (1), `raw_remote_guard_test` (2),
  `phase_union_guard_test` (6) - the moved modules and
  `src/ReplicatedStorage/Shared/__probe_clock_leak.luau` are not in the
  classifier's source/test sets, and the real `src/shared/Clock.luau` is
  now "not the owner" of `os.clock`;
- **6 in the new `layer_requires_test.luau`**, which are this story's RED:

        FAIL  tests/shared/layer_requires_test.luau :: AC-1: no source or test module requires @shared or @net
              tests/shared/layer_requires_test:70: 27 require(s) still use a retired alias, over 210 file(s):
        src/net/GameRemotes.luau:46 requires "@shared/MechanicsTuning" from (none): the @shared and @net aliases are retired; spell it @game/ReplicatedStorage/…
        src/net/RejectionReporter.luau:31 requires "@shared/telemetry/Event" from (none): ...
        src/net/Wrapper.luau:66 requires "@shared/Clock" from (none): ...
        ... (27 lines, the 17 C-2 files)
        FAIL  tests/shared/layer_requires_test.luau :: AC-1: src/shared and src/net no longer exist
              tests/shared/layer_requires_test:78: src/shared still exists; it moves to src/ReplicatedStorage/Shared
        FAIL  tests/shared/layer_requires_test.luau :: AC-1: the moved layers are where the DataModel path says, and the scan sees them
              tests/shared/layer_requires_test:94: src/ReplicatedStorage/Shared/Clock.luau is not in the scanned set: src/client/.gitkeep, src/net/.gitkeep, src/net/GameRemotes.luau, ...
        FAIL  tests/shared/layer_requires_test.luau :: AC-2: .luaurc declares exactly one alias, game -> src
              tests/shared/layer_requires_test:122: .luaurc must alias exactly "game"; it aliases: shared
        FAIL  tests/shared/layer_requires_test.luau :: AC-3: every scanned source module is in a layer the rule knows
              tests/shared/layer_requires_test:157: 15 source file(s) are in no layer, so the rule is not checking them:
        src/net/.gitkeep
        src/net/GameRemotes.luau
        ... (the 6 src/net and 8 src/shared source files)
        FAIL  tests/shared/layer_requires_test.luau :: AC-3: no source module holds a string require that leaves its layer outside @game/ReplicatedStorage/
              tests/shared/layer_requires_test:143: 34 layer-crossing violation(s) over 35 source file(s):
        src/net/GameRemotes.luau:46 requires "@shared/MechanicsTuning" from (none): the file is in no layer the rule knows
        ...

  The 34 AC-3 violations are the 27 `@shared` requires plus 7 relative
  requires in files the rule cannot place (`src/net/*`'s `./Remotes`,
  `./Schema`, …, and `src/shared/telemetry/Sink.luau`'s `./Event`); after
  the move those files are in `net`/`shared` and the relative requires are
  permitted, so the 7 vanish with the directory and the 27 vanish with the
  rewrite.

**One fix during RED, not about the move:** the first run also failed
`gated_fs_test :: AC-7` because my controls file held a literal whose whole
content was `@lune/fs` (the `@lune/…` refusal case). Changed the case to
`@lune/net`; the second run shows AC-7 passing. Everything else in both runs
is the move.

### `bash scripts/gates.sh --fast`, per gate

    PASS         format (1s, observed 210)
    PASS         lint (1s, observed 210, floor 1)
    PASS         typecheck (2s, observed 35)
    FAIL         unit (48s, exit 1)
    UNCONFIGURED coverage
    PASS         build (1s, observed 133852)
    FAIL         harness (17s, exit 1)     -> project-counters: 34 passed, 7 failed

The probe passes format, lint and typecheck: `luau-lsp` resolved
`@game/ServerScriptService/Server/round/PhaseMachine` from `src/client/` with
`.luaurc` still aliasing only `shared`, which means it reads `@game` through
the sourcemap, not the alias. That is an observation for D-3, not D-3 itself.

The 7 harness failures, all predicted in the counters file's comment block:
`the working tree carries no stray .luau files` (the new files are untracked
until the RED commit); `narrowing the typecheck target to
src/ReplicatedStorage/Shared` (`test -d` fails, no evidence line); the three
`counts the untracked file` cases (expected 211/211/36, got 210/210/35: the
scratch probe cannot be written under the missing directory); and the two
`format gate FAILS on a badly formatted file` cases (same reason). The 34
passes include the base counts: format 210, lint 210, typecheck 35, narrow
src 35/35, exactly the predicted literals.

### One line per test

`tests/shared/layer_requires_test.luau` (over the real tree):
- `AC-1: no source or test module requires @shared or @net` - AC-1; zero
  retired-alias requires over `--list source src` + `--list test tests` +
  `--list test lune`, with a vacuity floor on both lists.
- `AC-1: src/shared and src/net no longer exist` - AC-1; `isDir`/`isFile`.
- `AC-1: the moved layers are where the DataModel path says, and the scan sees them` -
  AC-1 vacuity; `src/ReplicatedStorage/Shared/Clock.luau`,
  `src/ReplicatedStorage/Net/Wrapper.luau`, `src/server/round/RoundView.luau`
  are in the classifier's source set.
- `AC-2: .luaurc declares exactly one alias, game -> src` - AC-2; JSON via
  `@lune/serde`, alias names sorted == `{"game"}`, value `"src"`.
- `AC-3: no source module holds a string require that leaves its layer outside @game/ReplicatedStorage/` -
  AC-3; zero C-4 violations over the source set, which must contain
  `RoundView.luau` so there is a crossing to judge.
- `AC-3: every scanned source module is in a layer the rule knows` - AC-3;
  a file the rule cannot place is a file it is not checking.
- `AC-3 control: the client probe's @game/ServerScriptService require is reported by file and by require` -
  AC-3's control; the scan over `source + test` names the probe exactly once,
  for exactly that require, from layer `client`, and the rendered message
  contains both the path and the require.
- `AC-3 control: the probe is not in the source set the guard asserts over` -
  the other half of the probe convention.

`tests/shared/layer_requires_controls_test.luau` (in-memory, 26 tests, all
green in RED by design, like every `_controls_test` here): listed in
`## Test plan`. Each refusal asserts exactly one violation, the right
`target`, the right `path`, and both in the rendered message.

### Files touched

New: `tests/helpers/LayerRequires.luau`, `tests/shared/layer_requires_test.luau`,
`tests/shared/layer_requires_controls_test.luau`, `src/client/__probe_cross_layer.luau`.

Rewritten (110 files, 355 substitutions): every file in
`rg -l 'src/(shared|net)' tests lune` at `3b2c8ec`, via
`sed 's#src/shared\b#src/ReplicatedStorage/Shared#g; s#src/net\b#src/ReplicatedStorage/Net#g'`,
then `stylua tests lune` (reflowed ~10 files whose lines passed 100 columns;
`raw_remote_guard_test.luau` needed a second stylua pass to reach a fixed
point). Completeness: `rg -n 'src/(shared|net)\b' tests lune` is empty.
`src/network/Y.luau` (a deliberate non-match in `raw_remote_guard_test.luau`)
is intact. Includes `SourceScan.RULES`' owner paths, every `PROBE`/`CLOCK`/
`RNG`/`NET_PREFIX` constant, and every `pcall(require, "../../src/…")`.

Harness: `.claude/harness/project.conf` (two `covers | unit` lines, the
`discovery | sourcemap` grep), `.claude/tests/project-counters.test.sh`
(baselines, comment block, narrow target, `UNTRACKED_REL`, `UNFORMATTED_REL`),
`.claude/tests/harness-gate.test.sh` (`PROBE_REL`).

Story: `## Contract` C-2 and C-7 amended (counts: 27 requires in 17 files),
`## Test plan`, this section.

### What the tests already pin (the "export shape" of a move)

- **Paths, exactly.** `src/ReplicatedStorage/Shared/{Clock,MechanicsTuning,Rng,Scaffold,Tuning,__probe_clock_leak}.luau`,
  `src/ReplicatedStorage/Shared/channel/Presets.luau`,
  `src/ReplicatedStorage/Shared/telemetry/{Event,Sink}.luau`,
  `src/ReplicatedStorage/Net/{GameRemotes,RateLimiter,RejectionReporter,Remotes,Schema,Wrapper}.luau`.
  Every file keeps its name (C-1); 110 test files require them at those paths.
- **Require spelling in `src/`.** A string require that leaves its layer
  begins `@game/ReplicatedStorage/Shared/` or `@game/ReplicatedStorage/Net/`
  (slash included - `SharedExtras` is refused). `./` and `../` stay. `@self`
  is fine. Nothing else beginning `@` is permitted - not `@game/ServerScriptService/…`
  even from `src/server`, not `@lune/…`. `shared` may not require `net`.
- **`.luaurc`.** `aliases` is exactly `{ "game": "src" }`. Other keys are not
  constrained by the tests (C-7 says keep them; `languageMode: strict` is
  what the typecheck gate relies on).
- **Nothing directly under `src/` or `src/ReplicatedStorage/`** that the
  classifier calls source: `AC-3: every scanned source module is in a layer`
  refuses it. A `.gitkeep` under `src/ReplicatedStorage/` would fail that
  test; the existing `src/net/.gitkeep` moves with `git mv` into
  `src/ReplicatedStorage/Net/` and is fine there.
- **Not constrained:** the order of requires, `default.project.json`'s
  shape beyond `build` passing and the sourcemap containing
  `src/ReplicatedStorage/Shared/Scaffold.luau`, comments that still say
  `@shared` (the scan is over code).

### Tests that passed on arrival, and what earns them

The two `AC-3 control` tests passed in RED, because the scanner and the
probe both exist now. Earned by mutating the probe through `mutate.sh` so its
one require is a *permitted* crossing, and watching exactly that assertion go
red (a throwaway single-file runner, `tests/_run_one.luau`, deleted after):

    === mutate: src/client/__probe_cross_layer.luau (1 line(s) changed by s#@game/ServerScriptService/Server/round/PhaseMachine#@game/ReplicatedStorage/Shared/Clock#) ===
      36 - local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")
      36 + local PhaseMachine = require("@game/ReplicatedStorage/Shared/Clock")
      pass  AC-3 control: the probe is not in the source set the guard asserts over
      FAIL  AC-3 control: the client probe's @game/ServerScriptService require is reported by file and by require
            tests/shared/layer_requires_test:198: src/client/__probe_cross_layer.luau must be reported exactly once (its one require); it was reported 0 time(s):
    1 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_client___probe_cross_layer.luau.20261008T164019Z.800239.bak) ===

Before the mutation the same two tests read `2 passed, 0 failed`.

The controls file is green by construction (in-memory text, no production
code), as the house pattern intends; its refusals each demand exactly one
violation with the right target, so a rule that refuses everything or
nothing fails it.

### Expected values of every control, for GREEN to confirm

These ran in RED (the suite loads; only the tree is wrong), so the numbers
are measured, not claimed. GREEN confirms each against the moved tree.

| Control | Threshold | RED measured | Expected after GREEN |
|---|---|---|---|
| AC-1 retired-alias requires over source + test files | == 0 | 27 (all `@shared/`, 17 files) over 210 files | 0 over 210 files (35 src entries + 175 tests/lune) |
| AC-1 `src/shared`, `src/net` exist | both false | both true | both false |
| AC-2 alias names | exactly `{game}`, `game == "src"` | `{shared}` | `{game}`, `"src"` |
| AC-3 violations over `--list source src` | == 0 | 34 over 35 entries | 0 over 35 entries (32 `.luau` + 3 `.gitkeep`) |
| AC-3 source files in no layer | == 0 | 15 | 0 |
| AC-3 control: probe reported over source + test | exactly 1, target `@game/ServerScriptService/Server/round/PhaseMachine`, layer `client` | 1 (among 34 others) | 1 (alone) |
| AC-3 control, mutated probe (permitted require) | reported 0 → test red | 0, red | 0, red (D-2's sibling; re-run if in doubt) |
| Controls file | 26/26 | 26/26 | 26/26 |
| `project-counters` | 210/210/35, narrow 35/35/9 | 210/210/35, 35/35 observed; narrow 9 unmeasurable (no dir) | all seven observed, 41/41 after the RED commit |
| `lune run test` | ≥ 1373 + 34 | 180 passed, 132 failed | 1407 passed, 0 failed (1373 + 8 + 26) |

### What GREEN must do (C-7, with what RED found)

1. `git mv src/shared src/ReplicatedStorage/Shared` and
   `git mv src/net src/ReplicatedStorage/Net` (the `.gitkeep` and
   `__probe_clock_leak.luau` move with them; create nothing under
   `src/ReplicatedStorage/` itself).
2. Rewrite the 27 `require("@shared/…")` calls in the 17 files C-2 lists to
   `require("@game/ReplicatedStorage/Shared/…")`. `rg -n '@shared/' src`
   should then show comments only, if anything.
3. `.luaurc`: `"aliases": { "game": "src" }`, nothing else in that table.
4. `default.project.json`: `ReplicatedStorage.Shared.$path` →
   `src/ReplicatedStorage/Shared`, `ReplicatedStorage.Net.$path` →
   `src/ReplicatedStorage/Net`.
5. No test edits. Snapshot first: `bash scripts/frozen.sh snapshot tests lune src/client/__probe_cross_layer.luau`.

### Declined, by owner

- **D-1** (Studio): operator, REVIEW. Not run.
- **D-2** (the guard discriminates against the real tree, via `mutate.sh` on
  `src/server/round/RoundView.luau`): GATES. I cannot run it: the real tree
  has no `@game/ReplicatedStorage/Shared/` require yet to mutate. The nearest
  thing I could run is the probe mutation above, which is the same assertion
  mechanism from the other side.
- **D-3** (which resolution `luau-lsp` uses for `@game`): GATES. Not run; the
  single observation above (the probe typechecks with no `game` alias in
  `.luaurc`) points at the sourcemap but is not the probe D-3 asks for.

### Things to know

- `.claude/tests/harness-gate.test.sh`'s `PROBE_REL` now points under
  `src/ReplicatedStorage/Shared/`; it is a selftest, not a gate, and will fail
  until the directory exists. Expected.
- `rg -l --hidden 'src/(shared|net)\b|@shared|@net\b' --glob '!docs/**' --glob '!src/**' .`
  now lists only: `.luaurc`, `default.project.json` (GREEN), the three new
  test files (needles), and C-3's "not changed" list (`stray-luau.sh`,
  `stray-luau.test.sh`, the stack profile, and history comments in
  `project.conf` / `project-counters.test.sh`).
- `.claude/worktrees/vigilant-engelbart-e5ebd4/` holds a stale copy of the
  tree; not touched, not in any gate.

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

### Return 1: GREEN -> RED (2026-10-08) - the AC-3 probe is not admissible to the typecheck gate

**Which test.** `src/client/__probe_cross_layer.luau`, the AC-3 negative
control owned by `tests/shared/layer_requires_test.luau`. It deliberately
requires `@game/ServerScriptService/Server/round/PhaseMachine` from the client
layer so the layer-require scanner has a crossing to refuse.

**What was wrong.** The probe opened with `--!strict`. With `.luaurc` now
aliasing `game -> src`, `luau-lsp analyze` resolves `@game` on the file tree,
and `src/ServerScriptService/...` exists only in the DataModel, so the required
`typecheck` gate failed on the probe:

    src/client/__probe_cross_layer.luau(36,22): TypeError: Unknown require: d:\first-roblox\src\ServerScriptService\Server\round\PhaseMachine.lua

The probe's job is to be scanned as text by the layer-require guard; it was
never meant to be typechecked. `lune run test` was `1407 passed, 0 failed`
throughout - the assertion was right, the file's header was not.

**How it was found.** GREEN's `bash scripts/gates.sh --gate typecheck` (see
`## Notes`, "GREEN blocked (2026-10-08)"). The Lead PO reproduced it
independently with a scratch `src/server/zz/repro.luau` requiring a
non-mirrored `@game/ServerScriptService/...` path, which answered D-3: the
alias makes `luau-lsp` resolve `@game` through the tree, not the sourcemap.
The fix is to a test-classified file, so it returned to RED.

**What it is now.** Two edits, nothing else:

1. `src/client/__probe_cross_layer.luau` line 1: `--!strict` -> `--!nocheck`.
   The require, the docstring and the exported table are unchanged, so the
   scanner still sees exactly the same offending string.
2. `tests/shared/layer_requires_test.luau` docstring line 21: "32 requires"
   -> "27 requires", matching the count amended in `## Contract` C-2.
   Comment only; no assertion changed.

No assertion was weakened, skipped, widened or deleted.

**What earns it - the corrected probe passes on its first run, so it is
probed.** First, the control on the corrected tree (`lune run test`, ~4 min):

    pass  tests/shared/layer_requires_test.luau :: AC-3 control: the client probe's @game/ServerScriptService require is reported by file and by require
    pass  tests/shared/layer_requires_test.luau :: AC-3 control: the probe is not in the source set the guard asserts over
    1407 passed, 0 failed

Then the mutation: swap the probe's require for a permitted
`@game/ReplicatedStorage/` path, so the scanner has nothing to refuse. Exactly
the AC-3 control went red, and the restore was verified:

    $ bash scripts/mutate.sh src/client/__probe_cross_layer.luau 's|@game/ServerScriptService/Server/round/PhaseMachine|@game/ReplicatedStorage/Shared/Rng|' -- lune run test
    === mutate: src/client/__probe_cross_layer.luau (1 line(s) changed by s|@game/ServerScriptService/Server/round/PhaseMachine|@game/ReplicatedStorage/Shared/Rng|) ===
      36 - local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")
      36 + local PhaseMachine = require("@game/ReplicatedStorage/Shared/Rng")

    === mutate: running lune run test ===
    ...
      FAIL  tests/shared/layer_requires_test.luau :: AC-3 control: the client probe's @game/ServerScriptService require is reported by file and by require
            D:\first-roblox\tests\shared\layer_requires_test:182: the scanner found nothing in src/client/__probe_cross_layer.luau, which requires @game/ServerScriptService/Server/round/PhaseMachine
      pass  tests/shared/layer_requires_test.luau :: AC-3 control: the probe is not in the source set the guard asserts over
      pass  tests/shared/layer_requires_test.luau :: AC-3: every scanned source module is in a layer the rule knows
      pass  tests/shared/layer_requires_test.luau :: AC-3: no source module holds a string require that leaves its layer outside @game/ReplicatedStorage/
    ...
    1406 passed, 1 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /d/first-roblox/.claude/state/mutations/src_client___probe_cross_layer.luau.20261008T173909Z.863502.bak) ===
      36: local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")

One mutation, one run, one failure - the control's own message, naming the
probe and the require - one verified revert. (The AC-3 positive assertion
stayed green under the mutation, as it should: a permitted crossing is not a
violation.)

**Gates on the corrected tree** (partial runs, not recorded):

    $ bash scripts/gates.sh --gate typecheck
    PASS         typecheck (5s, observed 35)

    $ bash scripts/gates.sh --gate harness
    FAIL         harness (17s, exit 1) -> .claude/state/gate-logs/harness.log
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
             expected:
             actual:    M src/client/__probe_cross_layer.luau
              M tests/shared/layer_requires_test.luau

The `harness` failure is only its "no stray .luau files" precondition, tripped
by the two modified files being uncommitted at the time of the run; every other
harness check passed (40 of 41). It clears once this RED commit lands.

**GREEN should be a no-op.** No source change is needed: the move committed in
`bb922b5` is untouched, `lune run test` is `1407 passed, 0 failed` on it, and
`typecheck` now passes. GREEN need only re-run `bash scripts/frozen.sh verify`
and the gates.

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


**GREEN blocked (2026-10-08). The Lead PO reproduced the escalation independently.**
GREEN finished the move, and `lune run test` gives `1407 passed, 0 failed`.
But the required `typecheck` gate fails on the frozen AC-3 probe:

    src/client/__probe_cross_layer.luau [...](36,22): TypeError: Unknown require: d:\first-roblox\src\ServerScriptService\Server\round\PhaseMachine.lua

The Lead PO reproduced it on a different input, without GREEN's code. A
scratch `src/server/zz/repro.luau` (source-named; deleted after) required
`@game/ReplicatedStorage/Shared/Rng` and `@game/ServerScriptService/Server/seats/Ring`.
The gate's own `luau-lsp analyze` command, with `.luaurc` declaring
`"game": "src"`, reported exactly one error:

    [game/ServerScriptService/Server/zz/repro](3,11): TypeError: Unknown require: d:\first-roblox\src\ServerScriptService\Server\seats\Ring.lua
    exit 1

**This answers D-3:** with the alias present, `luau-lsp` resolves `@game` through
`.luaurc`, on the file tree, not through the sourcemap. `ReplicatedStorage/...`
mirrors the disk, so every real require resolves. Only a path that exists
solely in the DataModel fails, and that is what the AC-3 probe deliberately
spells. A side effect worth keeping: `typecheck` now also refuses any
cross-layer `@game` path other than the mirrored ones.

`bash scripts/frozen.sh verify` → `frozen: OK — 200 path(s) unchanged since the snapshot for SLICE-008`.
The fix is to the probe, which is a test file, so it is a return to RED, and
that is put to the operator.
