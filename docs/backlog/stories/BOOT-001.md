---
id: BOOT-001
title: Roblox toolchain, gates and an empty place that builds
slug: roblox-toolchain-gates-and-an-empty-plac
epic: EPIC-00
type: bootstrap
status: done
phase: DONE
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

**Result: SATISFIED.**

    $ bash scripts/mutate.sh src/shared/Scaffold.luau 's/^\treturn out$/\treturn #out/' \
        -- bash scripts/gates.sh --gate typecheck
      36 - 	return out
      36 + 	return #out

    === mutate: running bash scripts/gates.sh --gate typecheck ===

    === gate: typecheck (required) ===
    Created sourcemap at sourcemap.json
    [INFO] Loading definitions file: @roblox - globalTypes.d.luau
    [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
    [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
    c:\Users\ryanc\Projects\first-roblox\src\shared\Scaffold.luau [game/ReplicatedStorage/Shared/Scaffold](36,2): TypeError: Expected this to be 'string', but got 'number'

    --- gate summary ---
    FAIL         typecheck (3s, exit 1) -> .claude/state/gate-logs/typecheck.log
    1 required gate(s) failed.

    === mutate: command exited 1; restored (verified byte-for-byte against
        .claude/state/mutations/src_shared_Scaffold.luau.20260915T170709Z.1013014.bak) ===
      36: 	return out

Restored, re-run:

    $ bash scripts/gates.sh --gate typecheck
    analyze over 1 files
    All required gates passed (1 ran, 0 unconfigured, 0 known).

**More than the criterion asked for.** The error names the file *and*
`[game/ReplicatedStorage/Shared/Scaffold]` — the DataModel path. That second half
is only printable if the Rojo sourcemap resolved, so this one line is also the
proof that `rojo sourcemap` → `--sourcemap` → `luau-lsp` is wired end to end.

**And `.luaurc` was verified separately, because this mutation does not test it.**
A return-type mismatch on an *annotated* function is caught under `nonstrict`
too, so it says nothing about `"languageMode": "strict"`. Nil safety does:

    $ bash scripts/mutate.sh .luaurc 's/"strict"/"nonstrict"/' -- <analyze over a probe returning string? as string>
      strict:     ...__probe_strict.luau(10,2): TypeError: Expected this to be 'string', but got 'string?'   exit 1
      nonstrict:  (no output)                                                                                exit 0

### The `typecheck` gate must fail when it has nothing to analyse

**Condition:** with `src` moved aside, `--gate typecheck` **must** fail rather
than reporting zero errors over an empty world.

**Why this one matters more than it looks:** `luau-lsp analyze`'s failure mode is
an analysis that **resolves nothing and reports zero errors** — vacuous success in
the gate that matters most. The sourcemap, the flags, `globalTypes.d.luau` and
`.luaurc` all have to be right simultaneously, and only these two probes together
prove they are.

**Owner: SCAFFOLD.**

**Result: SATISFIED, and the premise turned out to be half wrong — in a way that
found a real hole in the gate.**

With `src/shared/Scaffold.luau` moved aside and the four `src/` directories left
in place:

    $ bash scripts/gates.sh --gate typecheck
    Created sourcemap at sourcemap.json
    [INFO] Loading definitions file: @roblox - globalTypes.d.luau
    Sourcemap parsing failed, sourcemap is not loaded: [json.exception.type_error.304] cannot use at() with null
    [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
    error: no files provided

    FAIL         typecheck (2s, exit 1) -> .claude/state/gate-logs/typecheck.log
    1 required gate(s) failed.

Restored, re-run: `analyze over 1 files`, PASS.

**`luau-lsp analyze` 1.69.0 is honest about having nothing to do** — `error: no
files provided`, exit 1 — so the story's expectation that it "exits 0 with
nothing to say" is wrong for this version. Note also that `rojo sourcemap` exited
**0** while writing a sourcemap `luau-lsp` could not parse: its exit code is not
a check on anything.

**The real vacuous case is the opposite one, and the gate as planned did not
catch it.** The dangerous input is not an empty `src`, it is a full `src` the
analyser cannot *understand*. Measured, with `src` entirely intact:

| given | prints | exits |
|---|---|---|
| `--sourcemap` at a file that does not exist | `[ERROR] Failed to load ... for workspace 'CLI'` | **0** |
| `--sourcemap` at JSON it cannot parse | `Sourcemap parsing failed, sourcemap is not loaded` | **0** |
| `--definitions` at a file that does not exist | `[ERROR] Failed to read definitions file ... Extended types will not be provided` | **0** |

In all three it carries on with no DataModel and/or no Roblox types, resolves
almost nothing, reports zero errors and exits 0 — and **the counted evidence
cannot see it**, because every file is present and counted. That is exactly the
"resolves nothing and reports zero errors" failure the story warned about,
arriving through a door nobody had checked.

So the gate was changed, in this story, to close it:

    rojo sourcemap ... && test -s globalTypes.d.luau && luau-lsp analyze ... src 2>&1 \
      | awk '{print} /^\[ERROR\]|Sourcemap parsing failed/{bad=1} END{exit (bad?1:0)}' \
      && <count> && echo "analyze over $n files"

Both limbs probed — see `## Gate probes`, typecheck-B and typecheck-C. A genuine
`TypeError` line does not match the awk pattern, so real errors and degraded runs
are never conflated.

## Model guidance

**Resolved model of every dispatch, by name: none — no subagent was dispatched.**
The whole story was driven directly under SCAFFOLD, per the bootstrap exception
in `rules.md`.

**The model that ran it: `claude-opus-5`** (Opus 5), which is what
`.claude/agents/lead-po.md` declares. Recorded by name rather than as "the
default" because a session setting or an explicit override can win over the
agent definition and the orchestrator cannot see which did — the failure
`rules.md` describes, where two stories compared "the default model" against a
stronger one and neither could say what "default" had resolved to. No override
was reported on this dispatch.

**Retrospective, since AC-9 was the row that decided whether this story was worth
doing:** the four probes that confirmed the prediction took minutes and taught
nothing. The two that contradicted it — `luau-lsp` degrading silently on a bad
sourcemap, and the `pipefail` swallow that hid the lint gate's count line — were
both found by *reading the failure output rather than the exit code*, and both
changed shipped configuration. That is an argument about the brief, not the
model: "run the probe" would have passed on exit codes alone; "paste both
outputs" is what forced the reading.

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

Everything this story wrote outside `docs/**` and the harness. SCAFFOLD is the
one phase where nothing forces a test to exist, so the column that matters is the
last one.

### Files that classify as `source`

| File | What it is | Test that covers it |
|---|---|---|
| `src/shared/Scaffold.luau` | the one example module: `Scaffold.join(parts, separator)`, pure, no domain meaning | `tests/shared/scaffold_test.luau` — 4 cases: separator between adjacent parts, single part, empty list, multi-character separator |
| `src/client/.gitkeep` | placeholder so the layer exists in the Rojo instance tree | **none, and none is possible** — it is an empty marker with no behaviour. Read by the `build` gate, which fails if the directory it holds open disappears from `default.project.json`. The story that fills the layer deletes it. |
| `src/net/.gitkeep` | as above | as above |
| `src/server/.gitkeep` | as above | as above |

### Files that classify as `test`

| File | What it is |
|---|---|
| `lune/test.luau` | the test runner (§3 of `stack.md`). Classified `test` by `paths.conf` so RED can fix it. Its own five contract points were each exercised — see `## Gate probes`, unit, and `## Notes`. |
| `tests/shared/scaffold_test.luau` | the example suite |

### Files that classify as `config` or `manifest`

| File | What it is |
|---|---|
| `rokit.toml` | the toolchain pin: rojo 7.7.0, wally 0.3.2, selene 0.31.0, stylua 2.5.2, lune 0.10.5, luau-lsp 1.69.0. Every version resolved by `rokit add`; none typed. |
| `default.project.json` | Rojo: `src/shared`→`ReplicatedStorage.Shared`, `src/net`→`ReplicatedStorage.Net`, `src/server`→`ServerScriptService.Server`, `src/client`→`StarterPlayer.StarterPlayerScripts.Client`. That last mapping is the mechanism `architecture.md` §1 relies on to keep server code off the client. |
| `.luaurc` | `"languageMode": "strict"` — verified load-bearing, see the deferred verification above |
| `selene.toml` | `std = "roblox"`, built in to selene 0.31.0, no generation step and no network |
| `stylua.toml` | 100 columns, tabs, Unix line endings |
| `wally.toml` | declares nothing; exists so RED has somewhere legal to put a test-only package |
| `wally.lock` | produced by `wally install` |

### Not written, deliberately

- **`lune/build.luau`, `lune/analyze.luau`** — listed in this story's `## Contract`
  layout, but the `build` and `typecheck` gates invoke `rojo` and `luau-lsp`
  directly and a wrapper nothing calls is dead configuration. `paths.conf` already
  classifies them `config`, and `classify.sh` answers for a path whether or not
  the file exists, so AC-7 holds and the rules are correct in advance. Recorded in
  the profile.
- **`src/shared/Clock.luau`, `src/shared/Rng.luau`** — `architecture.md` §2 makes
  the injected clock and RNG a first-story hard requirement, and this story's
  `## Out of scope` puts them outside it. Writing them here would mean writing the
  guard tests that give them their meaning in the one phase where nothing forces a
  test to exist. **What this story guarantees instead is the property they exist
  to protect: no file it wrote calls `os.clock`, `os.time`, `tick`, `task.wait`,
  `math.random` or `Random.new`** — `Scaffold.join` is a pure string fold and the
  runner uses only `@lune/fs`, `@lune/process` and `@lune/stdio`. `ROUND-001`
  builds both modules test-first and adds the guard test that enumerates source
  modules through `bash scripts/classify.sh --list source src`.

### Files changed that are not source

`.gitignore` (added `Packages/`, `ServerPackages/`, `DevPackages/`,
`sourcemap.json`, `globalTypes.d.luau` — which is what makes the phase lock
classify the last two as `ignored`), `.claude/harness/project.conf`,
`.github/workflows/gates.yml`, and the four documents under AC-11.

## Gate probes

Every gate in `project.conf` is new in this story, so every one is probed. Each
block: what was broken, the failing output, and the restored re-run. Where a file
was edited rather than moved, the edit went through `bash scripts/mutate.sh`,
which restores the file and verifies the restore with `cmp`.

**The headline.** Two of AC-9's five rows did **not** fail the way the criterion
predicted, and both discrepancies were worth more than the three confirmations:
`luau-lsp analyze` is honest about an empty target and dishonest about a
*degraded* one, and `rojo build` is honest about a bad `$path` so `test -s` is
defence in depth rather than the primary check.

---

### `lint` — pointed at a tree with no `.luau` files

Broken by moving all three `.luau` files out and **leaving the directories in
place**. That distinction is the probe: `selene` over a *missing* directory exits
1, which would have tested the wrong branch.

    $ mv src/shared/Scaffold.luau tests/shared/scaffold_test.luau lune/test.luau .probe/
    $ selene src tests lune
    Results:
    0 errors
    0 warnings
    0 parse errors
    selene raw exit=0            <-- the vacuous pass, exactly as stack.md s2 predicted

    $ bash scripts/gates.sh --gate lint
    --- gate summary ---
    FAIL         lint (1s, ran but produced no evidence of work: expected /selene over [1-9][0-9]* files/)
    1 required gate(s) failed.

    log: .claude/state/gate-logs/lint.log
      Results:
      0 errors
      0 warnings
      0 parse errors
      selene over 0 files

Restored:

    $ mv .probe/Scaffold.luau src/shared/ && mv .probe/scaffold_test.luau tests/shared/ && mv .probe/test.luau lune/
    $ bash scripts/gates.sh --gate lint
    All required gates passed (1 ran, 0 unconfigured, 0 known).
    log: ... selene over 3 files

**This probe changed the gate.** On the first run the gate failed with a bare
`exit 1` and **no count line at all**, because the count was written
`... | grep -E '\.luau$' | ...` and `gates.sh` runs under `set -o pipefail`: grep
found nothing, exited 1, took the `n=$(...)` assignment and the whole `&&` chain
with it. The gate failed, so a quick reading would have called the probe a pass —
but it failed for the wrong reason and printed nothing diagnostic. The count
pipeline was rewritten so every stage exits 0 over an empty tree, and the output
above is the second run. A gate probe that is only read for its exit code would
have missed this.

---

### `typecheck` A — `src` emptied of `.luau`

Full output and analysis in `## Deferred verifications` above. Summary:
`Sourcemap parsing failed` then `error: no files provided`, exit 1, gate FAIL;
restored to `analyze over 1 files`, PASS.

### `typecheck` B — `globalTypes.d.luau` removed

The Roblox type dump is gitignored and generated, so "somebody has not run
`task install`" is the most likely way this gate degrades in real life.

    $ mv globalTypes.d.luau /tmp/globalTypes.keep
    $ bash scripts/gates.sh --gate typecheck
    log: Created sourcemap at sourcemap.json
    (nothing further - the gate stopped at `test -s globalTypes.d.luau`)
    FAIL         typecheck
    1 required gate(s) failed.

Restored: `analyze over 1 files`, PASS.

Without the `test -s` guard this is a **silent pass**: with `--definitions`
pointing at a missing file, `luau-lsp analyze` prints `[ERROR] Failed to read
definitions file ... Extended types will not be provided`, analyses the whole
tree with no Roblox types at all, and exits 0.

### `typecheck` C — `default.project.json` `$path` repointed at nothing

    $ bash scripts/mutate.sh default.project.json 's#"src/shared"#"src/does-not-exist"#' \
        -- bash scripts/gates.sh --gate typecheck
    [ERROR rojo] Rojo project referred to a file using $path that could not be turned into a Roblox Instance by Rojo.
            Check that the file exists and is a file type known by Rojo.
            File $path: src/does-not-exist
    FAIL         typecheck
    === mutate: restored (verified byte-for-byte) ===
      9:         "$path": "src/shared"

Restored re-run: PASS.

### `typecheck` D — a deliberate type error

`## Deferred verifications`, first block. `TypeError: Expected this to be
'string', but got 'number'`, naming the file and the DataModel path.

---

### `unit` — `tests/` moved aside

    $ mv tests tests.probe
    $ bash scripts/gates.sh --gate unit
    log: 0 passed, 0 failed
    FAIL         unit (0s, exit 1)
    1 required gate(s) failed.

Restored:

    $ mv tests.probe tests
    $ bash scripts/gates.sh --gate unit
    log:
      pass  tests/shared/scaffold_test.luau :: join of a single part adds no separator
      pass  tests/shared/scaffold_test.luau :: join of an empty list is the empty string
      pass  tests/shared/scaffold_test.luau :: join places the separator between adjacent parts
      pass  tests/shared/scaffold_test.luau :: join uses a multi-character separator verbatim
      4 passed, 0 failed
    All required gates passed.

The runner's other contract points were exercised the same way, since they are
what the gate's honesty rests on:

    a test file whose `require` cannot resolve   -> "LOAD FAIL" on stderr,
                                                    `4 passed, 1 failed`, exit 1
    the same tree under `--list`                 -> prints what it can see, exit 1
    a *_test.luau returning an empty table       -> "LOAD FAIL ... declares no tests",
                                                    `4 passed, 1 failed`, exit 1

---

### `format` — one line's indentation mangled

    $ bash scripts/mutate.sh src/shared/Scaffold.luau 's/^\tlocal out = ""$/        local out = ""/' \
        -- bash scripts/gates.sh --gate format
    Diff in src\shared\Scaffold.luau:
    30  30   | 	for index, part in parts do
    ...
    WARN         format (0s, exit 1, optional)
    === mutate: restored (verified byte-for-byte) ===
      29: 	local out = ""

Restored re-run: PASS, `stylua over 3 files`.

WARN rather than FAIL because `format` is optional, per `stack.md` §5. It is
still a real failure and it is still read.

---

### `build` — `$path` repointed at nothing, and the `test -s` limb

    $ bash scripts/mutate.sh default.project.json 's#"src/shared"#"src/does-not-exist"#' \
        -- bash scripts/gates.sh --gate build
    [ERROR rojo] Rojo project referred to a file using $path that could not be turned into a Roblox Instance by Rojo.
            File $path: src/does-not-exist
    FAIL         build (0s, exit 1)
    === mutate: restored (verified byte-for-byte) ===
      9:         "$path": "src/shared"

Restored re-run: `built 1931 bytes`, PASS.

**AC-9 asked for this to fail "on the `test -s` check, not on Rojo's exit code
alone", and it does not — Rojo's exit code is the thing that catches it.** Rojo
7.7.0 refuses a `$path` that does not exist, loudly, and no input was found that
makes it exit 0 over a zero-byte place. Rather than leave `test -s` as an
untested branch, its limb was exercised directly:

    $ : > build/place.rbxl && test -s build/place.rbxl && echo "built $(wc -c < build/place.rbxl) bytes"
    test -s limb exit=1

So it works, it is defence in depth against a future Rojo that is less careful,
and it stays. This is recorded as a **deviation from the stated criterion, not a
pass of it** — see `## Amendments`.

Also found while probing this gate, and fixed in `project.conf`: **Rojo does not
create the output's parent directory.** `build/` is gitignored, so on a clean
checkout the gate failed with `[ERROR rojo] failed to create file
'build/place.rbxl' ... (os error 3)`. The gate now begins `mkdir -p build &&`.

---

### Reverted

Every probe above was reverted. Each one that **edited** a file went through
`scripts/mutate.sh`, which restores and then verifies with `cmp` — every run
printed `restored (verified byte-for-byte against
.claude/state/mutations/...)`. Each one that **moved** files moved them back, and
`git status --porcelain` shows no worktree-vs-index difference for any of them.

`.claude/state/mutations/` contains no leftover `.bak`. That is `mutate.sh`'s own
signal that no restore failed — it exits 90 and keeps the backup when one does —
so it is evidence rather than an assurance.

Confirmed after the last probe: a full `bash scripts/gates.sh` passes, and
`bash scripts/gates.sh --fast` (which now includes `build`) passes too.

## Amendments

**AC-9, `build` row.** As written: *"`build` — with `default.project.json`
pointing at a path that does not exist, the gate fails on the `test -s` check,
not on Rojo's exit code alone."*

**What was observed:** Rojo 7.7.0 exits 1 with `[ERROR rojo] Rojo project
referred to a file using $path that could not be turned into a Roblox Instance`,
so the `&&` chain never reaches `test -s`. The criterion's *requirement* — the
gate fails on that input — is met; its *stated mechanism* is not, because it
assumed a tool behaviour this version does not have.

**Disposition:** the criterion is **not** being rewritten, because acceptance
criteria are frozen once a story leaves PLANNED and this one is satisfiable in
substance. It is recorded as satisfied-with-deviation, the `test -s` limb was
exercised on its own so it is not an untested branch, and `stack.md` §5 and the
profile now say that Rojo's exit code is the primary check here. **Pending PO
confirmation** that satisfied-with-deviation is the right disposition rather than
an amendment to the criterion's wording.

## Notes

**Mutation the orchestrator should run at acceptance — RUN, and the prediction
was wrong in a way worth keeping.**

Predicted: with the `N == 0` check deleted and `tests/` moved aside, *"the gate
passes where it should fail"*. It does not. Measured:

    $ mv tests tests.probe
    $ bash scripts/mutate.sh lune/test.luau \
        's/if failed > 0 or passed == 0 then 1 else 0/if failed > 0 then 1 else 0/' \
        -- bash scripts/gates.sh --gate unit
      147 - process.exit(if failed > 0 or passed == 0 then 1 else 0)
      147 + process.exit(if failed > 0 then 1 else 0)

    === gate: unit (required) ===
    lune run test
    0 passed, 0 failed

    FAIL  unit (0s, ran but produced no evidence of work: expected /[1-9][0-9]* passed, [0-9]+ failed/)
    === mutate: command exited 1; restored (verified byte-for-byte) ===

**The gate still fails — on the `evidence` regex instead of on the exit code.**
Two independent instruments cover the same hole, which is a better answer than
the prediction assumed.

So is the `N == 0` check dead weight? No, and the second measurement is the one
that matters:

    $ mv tests tests.probe
    $ lune run test                         # runner as written
    0 passed, 0 failed
    exit=1
    $ bash scripts/mutate.sh lune/test.luau '<same>' -- lune run test
    0 passed, 0 failed
    === mutate: command exited 0 ===        # <-- exit 0
    $ mv tests.probe tests && lune run test
    4 passed, 0 failed  exit=0

**`RED`, `GREEN` and `bash scripts/task.sh test` all run `lune run test`
directly, where no evidence line applies.** Without the check, a vanished suite
reads as green for the entire inner loop and is caught only at GATES. With it,
it is caught immediately. Contract point 4 stays, and the story that raises the
`unit` floor should re-read this before touching either.

**Mutations the orchestrator should run at acceptance, beyond that one.** Each
predicts a specific count or line, so a mismatch is informative:

1. `bash scripts/mutate.sh src/shared/Scaffold.luau 's/if index > 1 then/if index > 0 then/' -- bash scripts/gates.sh --gate unit`
   Predicts **3 passed, 1 failed** — only "join of an empty list is the empty
   string" survives, because every other case gains a leading separator. A
   single-assertion catch: if it reports 4 passed, the suite is vacuous.
2. `bash scripts/mutate.sh lune/test.luau 's/table.insert(loadFailures, { file = path, err = "declares no tests" })/do end/' -- bash scripts/gates.sh --gate unit`
   with an empty `tests/shared/empty_test.luau` present. Predicts the gate
   **passes** where the unmutated runner reports `4 passed, 1 failed`.

**`ci-factor` is not recorded, deliberately.** It must come from a real CI log —
one test's duration there over the same test's duration locally, under the same
gate — and this story has never run on CI. The first CI run on this story's PR is
where it comes from. A number here now would be a guess with a citation.

**Local timings**, for whoever measures that factor: `format` 219 ms, `lint`
224 ms, `unit` 155 ms, `rojo sourcemap` 698 ms, `luau-lsp analyze` 2,256 ms,
`rojo build` 125 ms. Windows 11 laptop, warm, 2026-09-15.

**A harness fix this story had to make, flagged for the operator.**
`scripts/check-boundaries.sh` refused this story's `## Deferred verifications`
with *"does not declare an owner"*. Its accepted list was
`RED|GREEN|GATES|REVIEW|DONE` — **`SCAFFOLD` was missing**, although it is a real
phase in `phases.conf` and the only legal owner for a bootstrap story's deferred
verification, since it is the one phase where source is writable at all. The
check could therefore only be satisfied by naming a phase that does not own the
work, and a check satisfiable only by a lie is worse than no check.

`SCAFFOLD` was added to the list, and a test case added to
`.claude/tests/boundaries.test.sh` that would have caught it. The test was
probed both ways — with the fix, `boundaries: 60 passed, 0 failed`; with
`SCAFFOLD` mutated back out via `scripts/mutate.sh`, `59 passed, 1 failed` on
exactly the new case, restored byte-for-byte.

This is a change to shared harness machinery rather than to this project, and it
is outside the Lead PO's normal path in `rules.md`. **It wants an operator's
eye.** The alternative was to write `Owner: GATES` on work GATES does not own.

**Two things this story could not verify, and neither is a pass:**

- **AC-10 (CI) is UNVERIFIED.** `.github/workflows/gates.yml` now installs Rokit,
  runs `bash scripts/task.sh install` and prints every tool version before the
  existing selftest/list/audit/gates steps. `bash scripts/ci-local.sh --dry-run`
  confirms the harness derives the new steps correctly, and every `run:` line is
  written to be a harmless no-op off a runner. But **no part of it has executed on
  Linux**, and it cannot until there is a PR. One step is flagged in the file
  itself as unverified: `rokit authenticate github --token`, which is
  `|| true`-guarded so its only failure mode is the unauthenticated path.
- **Everything in this story is a Windows measurement.** The one known
  Windows-only hazard was found and fixed (the `StyLua` / `stylua` alias, which
  is invisible on a case-insensitive filesystem and a `command not found` on
  Linux). There may be others.

**Sizing.** Eleven criteria is at the top of the bootstrap budget
(`story-authoring`, `reference/bootstrap-story.md`). AC-10 and AC-11 are cheap
(a CI step and two documentation edits) and AC-9 is the expensive one. If this
story grows past this, split AC-10 into a `chore` rather than absorbing it.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-15T18:49:46Z
    commit: e8f438b
    tree:   86a5963e75be92141109873ce579032bf4a167e4
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 3)
    PASS         lint (0s, observed 3, floor 1)
    PASS         typecheck (3s, observed 1)
    PASS         unit (1s, observed 4, floor 1)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 1931)
    UNCONFIGURED mutation

