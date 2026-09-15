---
id: BOOT-001
title: Roblox toolchain, gates and an empty place that builds
slug: roblox-toolchain-gates-and-an-empty-plac
epic: EPIC-00
type: bootstrap
status: todo
phase: PLANNED
branch: story/BOOT-001-roblox-toolchain-gates-and-an-empty-plac
depends_on: []
required_gates: []
---

## Context

This is milestone **M0** and the first story in the project. It turns a directory
of documents into a Roblox project: Rokit pins the toolchain, Rojo builds a place
headlessly, Lune runs a test suite, and every gate command in
`.claude/harness/project.conf` is executed for the first time.

Read `docs/wiki/stack.md` before anything else, and read its banner literally:
**nothing in it has been run.** No part of this toolchain is installed on this
machine. Every command in it, and in
`.claude/skills/stack-profiles/reference/roblox-luau.md`, is a documented
intention. Correcting both files against real output is this story's single most
valuable product.

`stack.md` §2 is the reason this story is unusual. **Every tool in this ecosystem
prints nothing when it is happy and exits 0 just as quietly when pointed at a
directory that does not exist.** There is no "Checked 47 files" line to lean on.
So each gate counts its own inputs with `git ls-files | wc -l` and echoes the
number, and **proving the vacuous case fails is the work** — not a formality after
it.

Run `/setup-environment` before starting this story. Planning chose a toolchain;
it did not install one, and this story cannot pass its gates on a machine that
does not have it.

**Which required gate would fail if this story's artifact broke:** all of them.
That is the artifact.

## Acceptance criteria

- **AC-1** — `bash scripts/gates.sh --gate lint` runs Selene over the scaffolded
  `.luau` files and passes, and its output names a non-zero file count.
- **AC-2** — `bash scripts/gates.sh --gate unit` runs `lune run test`, which
  discovers and passes at least one real example test, and prints a line matching
  the `unit` evidence regex with a real count.
- **AC-3** — `bash scripts/gates.sh --gate typecheck` produces a Rojo sourcemap
  and runs `luau-lsp analyze` over `src` with zero errors; and a **deliberately
  introduced type error makes it fail**. This is M0's own definition of done.
- **AC-4** — `bash scripts/gates.sh --gate build` produces a non-empty
  `build/place.rbxl` and prints its byte count.
- **AC-5** — `bash scripts/task.sh install` installs the pinned toolchain and the
  generated `globalTypes.d.luau` from a clean checkout; `bash scripts/task.sh dev`
  starts `rojo serve`.
- **AC-6** — `.claude/harness/project.conf` has a verified command for every
  required gate, an `evidence` line for each, a `floor` for `unit` and `lint`, at
  least one `covers` line per required gate taken from the runner's real include
  list, a `discovery` line proving the runner can see `tests/`, and
  `BOOTSTRAPPED=yes`.
- **AC-7** — `.claude/harness/paths.conf` classifies this stack's files correctly:
  `bash scripts/classify.sh lune/test.luau` reports `test`,
  `bash scripts/classify.sh lune/build.luau` reports `config`,
  `bash scripts/classify.sh wally.toml` reports `manifest`,
  `bash scripts/classify.sh rokit.toml` reports `config`, and
  `bash scripts/classify.sh sourcemap.json` reports `vendor`.
- **AC-8** — `bash scripts/gates.sh --audit` passes: every required gate has a
  command, an existing `cwd`, and an `evidence` line; every `floor` has an
  evidence line that covers the whole number; every `slow` line names a real gate
  and carries a reason.
- **AC-9** — **Each required gate has been observed to fail on the vacuous case**,
  not merely on a broken input:
  - `lint` — pointed at a tree with no `.luau` files, the evidence count goes to
    zero and the gate fails on evidence rather than passing silently.
  - `typecheck` — with `src` emptied, the gate fails rather than reporting zero
    errors over nothing.
  - `unit` — with `tests/` moved aside, the runner exits non-zero on `N == 0`.
  - `build` — with `default.project.json` pointing at a path that does not exist,
    the gate fails on the `test -s` check, not on Rojo's exit code alone.
  - `format` — with a file's indentation mangled, `stylua --check` fails.
  Both outputs (failing and restored) are pasted into `## Gate probes` for each.
- **AC-10** — `.github/workflows/gates.yml` installs the pinned toolchain and the
  full gate suite passes on CI, on Linux, with no Roblox credentials.
- **AC-11** — The `# UNVERIFIED` banners are **deleted** from `docs/wiki/stack.md`
  and `.claude/skills/stack-profiles/reference/roblox-luau.md`, every command in
  both files matches what was actually run, and `stack.md` §1's version table
  carries the versions Rokit resolved.

## Contract

### The layout (brief B3, `stack.md` §6)

    rokit.toml                 pinned toolchain          -> config
    wally.toml, wally.lock     packages (none yet)       -> manifest
    default.project.json       Rojo                      -> config
    selene.toml stylua.toml .luaurc                      -> config
    src/server/  src/client/  src/shared/  src/net/      -> source
    tests/                     mirrors src/              -> test
    lune/test.luau             the runner                -> test
    lune/build.luau  lune/analyze.luau                   -> config
    .gitignore                 add: Packages/ ServerPackages/ DevPackages/
                                    sourcemap.json globalTypes.d.luau

`build/` and `dist/` are already ignored and already classify as `vendor`, so the
`build` gate's output needs no new rule.

### The test runner — `lune/test.luau`

A hard contract, because `evidence`, `floor` and `discovery` all read its output.
Evaluate any third-party Lune framework you find against these five points; adopt
it only if it satisfies all of them.

1. Walks `tests/` recursively for `*_test.luau` and `require`s each one.
2. **A file that fails to load is a failure, never a skip.** Do not wrap `require`
   in a silent `pcall`. This is the single line that stops a suite quietly
   shrinking while staying green.
3. Prints a final line matching `N passed, M failed` with real counts.
4. Exits non-zero if `M > 0` **or if `N == 0`**.
5. Supports `--list`: the same walk, printing a first line matching
   `^[1-9][0-9]* tests?` and then each test name, running nothing.

Point 5 is a requirement on code you are about to write, not a flag that exists.

### The example test

One trivial pure module under `src/shared/` with one behaviour and a test for it,
present to prove the runner runs. It is **not** the start of the architecture and
`ROUND-001` does not build on it. Something with no domain meaning at all is
correct here.

### `.luaurc`

Set `"languageMode": "strict"` so `--!strict` is the default rather than a
per-file opt-in (brief B2: "no exceptions"). A guard test that every source file
*also* carries the header is real behaviour and belongs in its own story; do not
write one here.

### `globalTypes.d.luau`

Generated, not authored. Establish where it comes from, pin that source, fetch it
in `task install`, and gitignore it. A stale dump produces type errors that look
like code errors. Record the source in `stack.md` §6.

### Versions

Do **not** copy version numbers out of `stack.md` or the profile — neither has
any. Run `rokit add` per tool, let Rokit resolve the current release, commit
`rokit.toml`, and write the resolved versions back into `stack.md` §1.

### `project.conf`

The gate commands, evidence lines, floors, `slow` lines and the discovery line are
already written into `project.conf` by the planning pass, each under a
`# UNVERIFIED` marker. **They are candidates, not truth.** Run each, correct it,
and delete the marker for the ones you have verified. Add the `covers` lines,
which planning deliberately left empty because a `covers` line must come from a
runner's real include list and nothing had been run.

Then set `BOOTSTRAPPED=yes`. Note what that switch does: unconfigured **required**
gates stop being a warning and become a hard failure. `coverage` and `mutation`
are already demoted to `optional` for exactly this reason (`stack.md` §4).

### Oracle partition

| AC | Kind | Instruction |
|---|---|---|
| AC-1..AC-5, AC-10 | **Mechanical** | Pin exactly. These are commands and exit codes, not judgements. |
| AC-6, AC-7, AC-8 | **Settled** | The classifications and the gate list are decided in `stack.md` §5–§6 and `paths.conf`. Read them out; do not re-derive them. |
| AC-9 | **Oracle-free, and the heart of the story** | Nobody has seen these tools fail on this machine. Invent the vacuous case for each gate and make it fire hard. A gate that "passes" after you break what it guards is the finding. |
| AC-11 | **Mechanical** | The banner either matches reality or it does not. |

## Deferred verifications

### The `typecheck` gate must fail on a deliberate type error

**Condition:** with a type error introduced into one `src/**/*.luau` file,
`bash scripts/gates.sh --gate typecheck` **must** exit non-zero and name that
file.

**Why it cannot run earlier:** there is no `src/` and no configured analyzer until
this story creates both. This is also M0's stated definition of done in the brief.

**Owner: SCAFFOLD** (this story — the phase where source is writable). Use
`bash scripts/mutate.sh` so the file is restored and the restore is verified.

**Result:** _(paste: the mutation, the failing output naming the file, the
restore, and the passing re-run)_

### The `typecheck` gate must fail when it has nothing to analyse

**Condition:** with `src` moved aside, `--gate typecheck` **must** fail rather
than reporting zero errors over an empty world.

**Why this one matters more than it looks:** `luau-lsp analyze`'s failure mode is
an analysis that **resolves nothing and reports zero errors** — vacuous success in
the gate that matters most. The sourcemap, the flags, `globalTypes.d.luau` and
`.luaurc` all have to be right simultaneously, and only these two probes together
prove they are.

**Owner: SCAFFOLD.**

**Result:** _(paste)_

## Model guidance

**Resolved model of every dispatch, by name:** none. This story was planned and
is expected to be driven directly by the Lead PO under SCAFFOLD, per the bootstrap
exception in `rules.md`. If any part of it is dispatched to a subagent, record the
**resolved** model here by name — never the word "default" — and ask the subagent
to say whether it was dispatched with an override.

The oracle partition is in `## Contract` above, and AC-9 is the row that decides
whether this story was worth doing.

## Out of scope

- **Any game logic.** No phase machine, no seats, no remotes, no telemetry, no
  tuning constants module.
- **Any guard test over the source tree.** No-`os.clock`, no-`OnServerEvent`, and
  `--!strict`-header rules are all real behaviour and get a failing test first, in
  `ROUND-001` and `NET-001`. SCAFFOLD is the one phase where nothing forces a test
  to exist, and it is the worst place to put anything that could have one.
- **Any Wally package.** `wally.toml` exists and declares nothing. B1 #5 makes a
  new dependency an operator decision.
- **Configuring `coverage` or `mutation`.** Both stay optional and unconfigured;
  `stack.md` §4 is the record of why.
- **Open Cloud, publishing, MCP, Studio.** B1 #3–#5. No gate may need any of them.
- **Raising the `unit` floor above 1.** There is one example test. Later stories
  raise it as they add suites.

## Scaffold inventory

_(Required. One line per production file written, and for anything with behaviour
rather than configuration, the test that covers it. `check-boundaries.sh` refuses
the PR if a changed source file is missing here.)_

## Gate probes

_(Required — this story adds every gate. One block per gate: what was broken, the
pasted failure output, and confirmation the probe was reverted. AC-9.)_

## Notes

**Mutation the orchestrator should run at acceptance.** Against the committed
scaffold, delete the `N == 0` check from `lune/test.luau`'s exit condition via
`bash scripts/mutate.sh`, move `tests/` aside, and run `--gate unit`. Predicted:
the gate passes where it should fail — which is the whole reason point 4 of the
runner contract exists. Restore and confirm it fails again. Record the output
here.

**Sizing.** Eleven criteria is at the top of the bootstrap budget
(`story-authoring`, `reference/bootstrap-story.md`). AC-10 and AC-11 are cheap
(a CI step and two documentation edits) and AC-9 is the expensive one. If this
story grows past this, split AC-10 into a `chore` rather than absorbing it.
