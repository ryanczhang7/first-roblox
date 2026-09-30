---
id: HARNESS-022
title: A test that reads a file outside the gate hash fails, naming it
slug: a-test-that-reads-a-file-outside-the-gat
epic: 
type: feature
status: todo
phase: PLANNED
branch: story/HARNESS-022-a-test-that-reads-a-file-outside-the-gat
depends_on: [HARNESS-021]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

The follow-up HARNESS-021 left open. See its `## Out of scope`, "Detecting the
next doc a test starts to read", and Q2, which the user answered "yes" on
2026-09-30.

HARNESS-021 put a `docs` path into the gate tree hash when a
`covers | <gate> | <glob>` line in `.claude/harness/project.conf` names it.
`project.conf` now declares `covers | unit | docs/wiki/game/tuning.md` and
`covers | unit | docs/wiki/stack.md`. **The declaration is by hand.** If a test
starts reading `docs/wiki/game/loop.md` and nobody adds a covers line, then an
edit to `loop.md` after a gate run changes what `unit` reports while the recorded
stamp still matches. That is the HARNESS-021 bug again, and nothing says so.

The general form of the invariant is: **every file a unit test reads must be in
the gate hash**. Docs are the case that leaked, but the same holds for a harness
`.md` file or an ignored file (`sourcemap.json`, `build/`). This story makes the
unit run enforce it at the moment of the read.

### What was measured (worktree `fervent-curran-bab70a`, at `c54148d`, which is `main`)

**1. How the tests reach the filesystem.** Nine files require `@lune/fs`:

    $ grep -rln '@lune/fs' tests lune
    tests/helpers/RateLimitSpec.luau    tests/helpers/SourceScan.luau
    tests/helpers/TuningSpec.luau       tests/net/phase_union_guard_test.luau
    tests/server/projection_test.luau   tests/shared/contract_raise_test.luau
    tests/shared/source_guard_test.luau tests/shared/tuning_spec_test.luau
    lune/test.luau

    $ grep -rhoE 'fs\.[a-zA-Z]+' tests | sort | uniq -c
         2 fs.isFile   1 fs.readDir   17 fs.readFile   1 fs.removeFile   1 fs.writeFile

Every read is written `fs.readFile(<expr>)`, and the member is looked up at call
time. No file captures it at load (`grep -rnE 'local [A-Za-z_]+ *= *fs\.' tests lune`
finds only `local text = fs.readFile(...)` calls). The runner (`lune/test.luau`)
uses only `fs.readDir`, `fs.isDir` and `fs.isFile`, to walk `tests/`. It reads no
file contents.

**2. The runner cannot intercept `fs`, because `@lune/fs` is frozen.** This was
prototyped in the scratchpad on lune 0.10.5:

    frozen: true
    assign ok: false  ...main:5: attempt to modify a readonly table

A cloned table is not frozen (`table.clone(fs)` gives `clone frozen: false`), so
a wrapper module can present the same members. But there is **no in-process
choke point that tests get without asking for it**. The choke point has to be a
module the tests require instead of `@lune/fs`, and a static rule has to say
that they do.

**3. A missing file's read error does not name the path.**
`pcall(fs.readFile, "docs/nope.md")` gives
`The system cannot find the file specified. (os error 2)`, with a stack and no
path. So "hide the uncovered docs and see what breaks" could detect a reader, but
it could not name the path (option D in `## Notes`).

**4. What "in the gate hash" costs to ask.** `gated_stdin`
(`.claude/hooks/lib.sh`) is the one definition. Run over the whole tree:

    $ time (git ls-files --cached --others --exclude-standard | classify_stdin | gated_stdin)
    real 0m0.142s      -> 153 of 265 paths kept, including exactly
                          docs/wiki/game/tuning.md and docs/wiki/stack.md among docs/

`scripts/classify.sh --list source src` took **4.17s**, because it calls
`classify` once per path. So a new mode has to go through the stdin pipeline
rather than the per-path loop. It is asked once per run. Spawning `bash` from lune
costs `0.023s` of CPU (`os.clock`). `SourceScan.classifierList` already spawns
`bash scripts/classify.sh` from the unit run
(`tests/helpers/SourceScan.luau:117`), so the unit gate already depends on bash
and git.

**5. The baseline.** `lune run test` gives `452 passed, 0 failed`.
`lune run test -- --list` takes 0.40s wall and prints `452 tests`. It must stay
free of spawns (see the Contract, "lazy").

**6. Controls that exist in the tree today.**
`docs/wiki/architecture.md` is **mentioned** in two test comments
(`tests/helpers/RoundEndingContract.luau:17` and
`tests/helpers/TelemetryContract.luau:55`) and is read by nothing. It is the
uncovered-doc control, as it was in HARNESS-021.

### The required gate that fails if this story's artifact breaks

There are two halves.

- **Project half** (`tests/**`): the `unit` gate (`lune run test`, required). A
  read outside the gate hash raises, so the case that made it fails and the run
  exits 1.
- **Harness half** (`scripts/classify.sh --gated`): no `gate |` line reads it.
  It is pinned in `.claude/tests/classify.test.sh`, which CI's required `gates`
  job runs through `selftest.sh`, as in HARNESS-020 and HARNESS-021. `unit` also
  consumes it, so if `--gated` breaks, every checked read fails closed, loudly.

`required_gates` stays empty: there is no optional gate to promote.

## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

The artifact is **option B** in `## Notes`. A harness question
(`classify.sh --gated`) answers "which files does the gate hash cover". A test
helper (`tests/helpers/GatedFs.luau`) asks it on every `readFile`. A guard test
makes the helper the only way the tests reach `@lune/fs`.

**Harness half: `scripts/classify.sh --gated`.**

- **AC-1** (it lists what the hash covers, and only that). Take a fixture whose
  `project.conf` has `covers | unit | docs/wiki/game/tuning.md`, and whose tree
  holds `src/main.ts`, `docs/wiki/game/tuning.md`, `docs/wiki/architecture.md`,
  `docs/backlog/stories/T-1.md`, `.claude/commands/x.md`, and an ignored
  `build/out.txt`. Then `bash scripts/classify.sh --gated` prints the lines
  `src/main.ts` and `docs/wiki/game/tuning.md`, each matched as a **whole line**,
  and prints none of the other four as a whole line.
  *Control, no covers line:* the same tree with the covers line removed does
  **not** print `docs/wiki/game/tuning.md`, and it still prints `src/main.ts`.

- **AC-2** (it agrees with `gate_tree_hash`, the definition it reports). In the
  AC-1 fixture:
  - editing a file that `--gated` printed (`docs/wiki/game/tuning.md`) moves
    `gate_tree_hash`;
  - editing one it did not print (`docs/wiki/architecture.md`) leaves the hash
    unchanged.
  Each edit gets its own before and after hash. There is no loop.

- **AC-3** (pathspecs narrow the question, and an empty answer is not an error).
  `classify.sh --gated docs` prints `docs/wiki/game/tuning.md` and does not print
  `src/main.ts`. `classify.sh --gated docs/wiki/game/nope.md`, a path that does
  not exist, prints nothing and exits 0. An untracked, non-ignored file created
  after the fixture's commit (`src/late.ts`) is printed by
  `classify.sh --gated src/late.ts`.

**Project half: `GatedFs` and the guard.**

- **AC-4** (a read inside the gate hash is an ordinary read). With the shipped
  `project.conf`, `GatedFs.readFile(p)` returns a string equal to
  `@lune/fs`'s `readFile(p)`, compared with `==`, for each of
  `docs/wiki/game/tuning.md`, `docs/wiki/stack.md` and
  `src/shared/Scaffold.luau`.

- **AC-5** (a read outside the gate hash fails, naming the path). With the
  shipped `project.conf`, `GatedFs.readFile("docs/wiki/architecture.md")` raises.
  The first line of the error message equals
  `read outside the gate hash: docs/wiki/architecture.md`, compared **whole
  line with `==`**. The same holds for `docs/wiki/game/loop.md` and for
  `.claude/commands/advance-story.md` (a harness prompt, which HARNESS-021 AC-3
  keeps out of the hash).
  *Control, the same call through the raw module:*
  `@lune/fs`'s `readFile("docs/wiki/architecture.md")` succeeds. That shows the
  refusal comes from the gate check and not from a missing file.
  *Control, the case never moves on to read:* the raise happens before any read,
  so it is not the os error of measurement §3. The message contains no `os error`.

- **AC-6** (a file that appears during the run is judged, not refused). After a
  first `GatedFs.readFile` has run, a test writes
  `tests/helpers/__probe_gated_late.luau`, which classifies as `test`, is
  untracked and is not ignored. `GatedFs.readFile` of that path then returns its
  contents and does not raise. The test removes the file in the same case, on
  pass or on fail.
  (Today `tests/shared/source_guard_test.luau` writes
  `src/shared/__ac6_uncommitted_fixture.luau`, and `SourceScan` reads it through
  the migrated helper, so this is a live path and not a hypothetical one.)

- **AC-7** (the helper is the only way in). No file that
  `bash scripts/classify.sh --list test tests` returns, other than
  `tests/helpers/GatedFs.luau`, contains a string literal whose content is
  exactly `@lune/fs` in its code. Comments do not count. On failure the message
  names each offending path. The rule itself is checked on in-memory sources:
  - `local fs = require("@lune/fs")` is flagged;
  - `local name = '@lune/fs'` is flagged, because the literal is the needle and
    not the `require` call;
  - `-- use require("@lune/fs") here` is **not** flagged (a comment);
  - `--[[ require("@lune/fs") ]]` is **not** flagged (a block comment);
  - `local x = "@lune/fsx"` is **not** flagged (whole-literal equality, not a
    substring).

- **AC-8** (end to end: removing a covers line makes `unit` fail, naming the
  doc). With `covers | unit | docs/wiki/stack.md` deleted from `project.conf`,
  `lune run test` exits non-zero. Its output contains the line fragment
  `read outside the gate hash: docs/wiki/stack.md`, and the final line matches
  `^[0-9]+ passed, [1-9][0-9]* failed$`. The same holds for
  `docs/wiki/game/tuning.md`.
  *Control:* with `project.conf` as shipped, `lune run test` prints
  `^[0-9]+ passed, 0 failed$` with the passed count **at least** the baseline
  of 452 plus the new cases. That is so while `RoundEndingContract.luau` and
  `TelemetryContract.luau` still mention `docs/wiki/architecture.md` in comments:
  a mention is not a read. This is verified in GATES as **DV-1**, because it
  needs `--gated` to exist.

## Contract

<!-- Amendable by RED in place, with a reason. GREEN builds what the amended block says. -->

### Files

| Path | `classify.sh` says | Who writes it | What changes |
|---|---|---|---|
| `scripts/classify.sh` | `tooling` | GREEN | the new `--gated [PATHSPEC...]` mode, plus the usage text and the header comment |
| `.claude/tests/classify.test.sh` | `harness` | RED | AC-1, AC-2 and AC-3, in a new `describe` |
| `tests/helpers/GatedFs.luau` | `test` | RED | **new**. The choke point (see below) |
| `tests/shared/gated_fs_test.luau` | `test` | RED | **new**. AC-4, AC-5, AC-6 and AC-7 |
| `tests/helpers/{RateLimitSpec,SourceScan,TuningSpec}.luau` | `test` | RED | `require("@lune/fs")` becomes `require("./GatedFs")` (or whatever relative form lune resolves; RED measures) |
| `tests/net/phase_union_guard_test.luau`, `tests/server/projection_test.luau`, `tests/shared/{contract_raise,source_guard,tuning_spec}_test.luau` | `test` | RED | the same one-line migration, to `require("../helpers/GatedFs")` |
| `docs/wiki/stack.md` | `docs` | Lead PO, at GREEN's end | one paragraph in the testing section: tests read files through `GatedFs`, and why. **stack.md is itself a covered doc**, so this edit moves the gate hash. Make it before the final `gates.sh` run |
| `.claude/skills/quality-gates/SKILL.md` | `harness` | GREEN | one sentence by HARNESS-021's covers paragraph: `classify.sh --gated` lists the hashed set |

`lune/test.luau` is **not** migrated (see Out of scope). `project.conf`,
`paths.conf` and `lib.sh` do not change. `--gated` composes
`classify_stdin | gated_stdin` and does not re-define either.

The whole project half is `test`, so RED writes it and GREEN may not touch it.
That is deliberate. The only production code in this cycle is `--gated`. RED
therefore fails for one reason, "`--gated` does not exist", and that failure
spreads to every migrated read (see "RED's expected failure").

### `scripts/classify.sh --gated [PATHSPEC...]`

- **Output:** one path per line, sorted (`LC_ALL=C sort -u`), with no category
  column. These are the files under the pathspecs (default `.`) that
  `git ls-files --cached --others --exclude-standard` enumerates and that
  `classify_stdin | gated_stdin` keeps. This is the `--list` enumeration, fed
  **through stdin in one pipeline** and not through the per-path `classify` loop
  (measurement §4: 0.14s against 4.17s).
- **Exit 0** on an empty answer. **Exit non-zero** with the existing `usage` when
  it is combined with `--only` or `--list` (one mode per call).
- **Agreement with the hash** is by construction, because it uses the same two
  functions. One known difference is stated rather than fixed: a file deleted
  from the working tree but still in the index is enumerated by
  `ls-files --cached`, and `gate_tree_hash`'s `git add -A` drops it. That cannot
  matter for a read, because the file does not exist. AC-2 pins agreement on
  present files.
- **Reads `$HARNESS_DIR/project.conf`** implicitly, through `gated_stdin`.

### `tests/helpers/GatedFs.luau`

```luau
-- returns a table with the @lune/fs members the tests use today:
GatedFs.readFile(path: string): string        -- checked
GatedFs.writeFile(path: string, contents: string): ()   -- pass-through
GatedFs.isFile(path: string): boolean                    -- pass-through
GatedFs.isDir(path: string): boolean                     -- pass-through
GatedFs.readDir(path: string): { string }                -- pass-through
GatedFs.removeFile(path: string): ()                     -- pass-through
GatedFs.gated(path: string): boolean                     -- the check, exposed for AC-5/AC-6
```

- **Build it as a new table.** Do not mutate `@lune/fs`, which is frozen
  (measurement §2).
- **Normalise before asking:** turn `\` into `/` and strip a leading `./`. Do
  nothing else. An absolute path is not rewritten. It fails the check, loudly.
  No test reads one today (measurement §1).
- **Lazy:** nothing is spawned at `require` time. The first `gated()` call runs
  `bash scripts/classify.sh --gated` once and caches the set. So
  `lune run test -- --list` (the `discovery` lines in `project.conf`) spawns
  nothing and keeps its 0.40s.
- **On a miss, ask once more for that path:**
  `bash scripts/classify.sh --gated <path>`. If it is printed, add it to the set
  and allow the read. This is AC-6. It is also the path that
  `source_guard_test`'s uncommitted fixture takes. Memoise hits and misses per
  path.
- **Fail closed:** if `classify.sh` exits non-zero, raise with its exit code,
  stdout and stderr, in the shape of `SourceScan.classifierList:118-122`. Never
  treat that as "allowed".
- **The refusal:** `error("read outside the gate hash: " .. path .. "\n" .. hint, 0)`.
  Level `0` means Luau adds no `file:line:` prefix, so the first line is exact
  (measured: `pcall` returns `[read outside the gate hash: docs/wiki/architecture.md]`
  verbatim). `hint` names the fix:
  `add "covers | unit | <path>" to .claude/harness/project.conf if a gate really reads it`.
  The wording of the hint is free. The first line is not.

### The AC-7 guard

- **The file list comes from** `SourceScan.classifierList("test", "tests")`,
  which is the harness's answer (`rules.md`, "A test that needs this answer asks
  for it"). There is no `readDir` walk and no glob.
- **Probe files:** rules.md's `__probe_` convention makes a scanner skip them.
  The guard skips paths whose basename matches `^__probe_` or `^__.*_probe%.`,
  so that AC-6's transient `__probe_gated_late.luau` can never be scanned mid-run
  (it contains no `@lune/fs` anyway). No on-disk offending file is needed,
  because the rule is tested on in-memory strings (AC-7's five cases).
- **The needle is a string literal whose whole content is `@lune/fs`, in code.**
  `SourceScan.codeOnly` blanks string literals as well as comments, so it cannot
  be used as-is. RED adds a reader of string-literal contents with comments
  excluded (for example `SourceScan.stringLiteralsIn(text): { string }`, built on
  the existing `walk`). **`codeOnly` and `commentsOnly` must not change output.**
  Their existing suites pin them, and RED records the before and after counts of
  the suites that use them.
- **Exemption:** exactly the one path `tests/helpers/GatedFs.luau`, by equality.

### RED's expected failure, stated in advance

After the migration, every test that reads a file through `GatedFs` goes red
with `scripts/classify.sh --gated exited <n>` (unknown option). That covers every
`SourceScan` guard and every `TuningSpec`/`RateLimitSpec` reader: 11 test files
reach `fs` through those helpers (`grep -rln 'SourceScan\|TuningSpec\|RateLimitSpec' tests --include=*_test.luau`).
The count is unknown until RED runs it. **RED records the failed count and shows
that every `FAIL` message contains `--gated`**, for example with
`lune run test | grep -A1 '^  FAIL' | grep -v '^  FAIL' | grep -vc -- '--gated'`
giving `0`. A failure without `--gated` is a migration bug, not the expected red.
AC-7 is the exception, since the guard is pure text plus a `classify.sh --list`
call. It **passes on arrival** once the migration is done. It is earned by DV-3.

### Changed signatures

None. No existing export changes shape. The eight migrated files change only
their `require` target, and `GatedFs` offers the same member names they call
(measurement §1). Callers of `SourceScan`, `TuningSpec` and `RateLimitSpec` are
untouched. If RED adds `SourceScan.stringLiteralsIn`, that is new, not changed.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-3 | **Mechanical** | Whole-line needles (`grep -cx`), one assertion per path, printed and not-printed paired in the same fixture. The fixture's `project.conf` goes through `write_conf` **before** the commit |
| AC-2 | **Mechanical** | The `lib.test.sh` shape: own before/after `gate_tree_hash`, `if [ "$a" = "$b" ]`. It is paired: the moving case fails if `--gated` lists something the hash ignores, and the static case fails if the reverse |
| AC-4, AC-5 | **Mechanical, needles by value** | `==` on the first line of the error (split on `\n`), never `string.find`. `read outside the gate hash: X` is not a substring of any success output, but `==` removes the question. The raw-`fs` control runs in the same case |
| AC-6 | **Mechanical** | Remove the probe in every exit path (`pcall` the body, remove, re-raise) |
| AC-7 | **Mechanical** | Five in-memory cases, as listed. Then one real-tree assertion whose failure message lists the offending paths |
| AC-8 | **Settled + deferred** | The two docs are HARNESS-021's measured readers. Do not re-derive them. Owner: GATES (DV-1) |

### Test commands (from `project.conf`)

    lune run test                          # task test / gate unit
    lune run test -- --list                # discovery
    bash .claude/tests/classify.test.sh    # the harness half; one suite, not selftest

Do not run `gates.sh` or `selftest.sh` in RED (`gates.sh` stamps the active
story, and selftest takes 10-25 minutes and collides with overlapping runs). Do
not run the lune suite and a gate concurrently: `source_guard_test` writes a
transient file under `src/`, which makes `typecheck` miscount.

### Test-only dependencies

None. Lune's `@lune/fs` and `@lune/process` are built in. Bash suites use
`_lib.sh` (`make_fixture`, `write_conf`, `commit_all`).

## Deferred verifications

**DV-1. AC-8 end to end: deleting a covers line makes `unit` fail, naming the
doc. Owner: GATES.** RED cannot run this, because `--gated` does not exist, so
every read is red for that reason instead. In GATES:

    bash scripts/mutate.sh .claude/harness/project.conf '/^covers | unit      | docs\/wiki\/stack\.md$/d' -- lune run test
    bash scripts/mutate.sh .claude/harness/project.conf '/^covers | unit      | docs\/wiki\/game\/tuning\.md$/d' -- lune run test

(Dry-run each expression against `project.conf` first. It must delete exactly one
line.) Each run must print `read outside the gate hash: <that doc>` and a final
`N passed, M failed` with `M >= 1`, and `mutate.sh` must report a verified
restore. The tuning.md run is expected to fail at least the 5 cases that
HARNESS-021 DV-2 saw fail on a value change. Then run the shipped-conf control
once: `0 failed`. Paste all three.

**DV-2. The helper's check discriminates. Owner: GATES.** The helper is `test`
code written in RED, and in RED it only ever failed for "`--gated` missing".
Against the real `--gated`, break the check and watch AC-5 go red:

    bash scripts/mutate.sh tests/helpers/GatedFs.luau '<make gated() return true unconditionally>' -- lune run test

The AC-5 cases must fail, and AC-4 must stay green. Do a second mutation that is
a **wrong value** rather than a removed check, and does not normalise: drop the
`./` strip and add a case, or make the miss-path re-ask return the cached answer
without spawning. The AC-6 case must go red. Paste both.

**DV-3. The AC-7 guard fires on the real tree. Owner: GATES.** It passes on
arrival in RED, once the migration is done.

    bash scripts/mutate.sh tests/server/projection_test.luau 's#require("../helpers/GatedFs")#require("@lune/fs")#' -- lune run test

The AC-7 real-tree case must fail, and its message must name
`tests/server/projection_test.luau`. Paste it. (RED may run this one itself,
because the guard needs no `--gated`. If it does, paste it into `## Handoff`
and mark DV-3 done there.)

## Amendments

<!-- Acceptance criteria are frozen once the story leaves PLANNED. -->

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-022` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `scripts/classify.sh` (tooling), `tests/helpers/GatedFs.luau` (test), `tests/shared/gated_fs_test.luau` (test) (+2 more), declared in the Contract's ### Files table — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- PLANNED, `lead-po` (dispatched by /plan-story), resolved to `claude-opus-5-5` (Opus 5.5). This is the model the subagent reports running on. No override was reported to it.

**RED brief, for the dispatch prompt:** carry the Contract's oracle partition verbatim. Everything is **mechanical**, and nothing here is oracle-free. The judgement RED owns is the negative controls' pairing, and showing that every expected-red `FAIL` names `--gated` (Contract, "RED's expected failure"). **Success condition for the planned `fable` RED, which can come out either way:** the orchestrator's re-run reproduces RED's failed count exactly, and the `grep -vc -- '--gated'` check prints `0`. If either misses, the verdict is recorded against the plan.

## Out of scope

- **Reads that do not go through `@lune/fs`.** `process.exec("cat", {...})`, a
  `require` built from concatenation (`require("@lune/" .. "fs")`), or a Lune
  built-in that reads files on another path. The AC-7 guard is textual, as
  `SourceScan` states of itself. It catches the way a read is actually written,
  which is how both of HARNESS-021's readers were written.
- **`lune/test.luau`.** It requires `@lune/fs` to walk `tests/` (readDir, isDir,
  isFile) and reads no contents (measurement §1). Migrating it would make the
  runner depend on a test helper that its own walk loads. The AC-7 guard scans
  `tests`, not `lune`.
- **Other gates' reads.** `format`, `lint`, `typecheck` and `build` read
  `src`/`tests`/`lune` and `config`, which are already hashed. `harness` reads
  `.claude/tests/project-counters.test.sh`. Only `unit` has a reader that a test
  author writes by hand.
- **Auto-writing the covers line.** The guard fails and names the fix. Whether
  a doc should be a gate input is a decision (HARNESS-021 option D shows the
  cost of "all docs"), so a human or the PO makes it.
- **Upstreaming `--gated` to `../agentic-dev-harness`.** `refresh-harness.sh`
  replaces `scripts/classify.sh`. After a refresh without it, `GatedFs` fails
  closed, every read goes red and the message quotes classify's usage error. That
  is loud, not silent. It is HARNESS-020's Q4, still open.
- **Changing what the tests read.** The same as HARNESS-021.

## Test plan

<!-- Filled by the Test Developer during RED. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. -->

## Regressions

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

## Notes

### The options, weighed

**A. A static lint over `tests/`, deriving the read set from the text.
Rejected, on HARNESS-021's measurement.** A literal-read regex
(`readFile\("docs/...`) finds only stack.md and misses tuning.md, which is read
through `SPEC_PATH`. A broad path regex finds architecture.md, which only comments
mention. A smarter static pass would have to follow constants across modules
(`TuningSpec.SPEC_PATH` is used from 12 files), which amounts to writing a Luau
evaluator. Every version is a needle of the kind `rules.md` lists. AC-7 keeps
**one** static rule, but it is about the **module** (`@lune/fs` literals), which
is a single exact token. It is not about the **argument**, which is any
expression.

**B. A choke-point module that asks the harness at read time. Chosen.** The
check runs on the value actually passed to `readFile`, so constants,
concatenation and helpers are all seen. A comment cannot trigger it, because
comments do not read. It names the path, because it holds the path. It asks
`gated_stdin`, the one definition, through a CLI (rules.md: ask, do not
reimplement), and there is no third glob converter. The cost is measured: one
spawn per run, about 0.14s of pipeline, and a second only on a miss. The price is
a static rule to keep tests on the choke point (AC-7), and that rule is exact.

**C. The runner wraps `fs` for every test (runtime observation with no
opt-in). Measured to be impossible as stated.** `@lune/fs` is frozen, so an
assignment raises `attempt to modify a readonly table`. The next version would be
the runner loading every test file through `@lune/luau` with a custom `require`
that hands out a proxy `fs`. That reimplements module resolution for relative
requires, changes chunk names in every stack trace, and rewrites the runner
BOOT-001 pinned (stack.md §3, architecture D10). That is a large blast radius to
avoid one `require` line per file.

**D. Hide what is not hashed and run the suite (sensitivity test). Rejected.**
Move every uncovered doc aside, run `lune run test`, and restore. It needs no
test changes. But: (1) a failing read does not name the path (measurement §3),
so naming it needs one run per doc, and 22 uncovered docs at the unit gate's
56s is about 20 minutes. (2) It moves authored files out of a working tree that
agents edit concurrently, and a failed restore loses a doc. (3) A test that
guards its read with `isFile` goes quiet instead of red.

**E. OS-level tracing (strace, Procmon). Rejected.** It is not portable, and
this repository runs on Windows (`rules.md`, Portability).

**Which side owns it.** Both, and the id is `HARNESS` because the invariant is
the harness's ("the gate record covers every gate input"), and the one
production change is harness tooling. The project half is a consumer written
entirely in `test` paths, just as `SourceScan` consumes `classify.sh --list`.
No project epic fits: EPIC-00 to EPIC-02 are game slices. So there is no epic,
like every HARNESS story.

### Sizing: one cycle

There is one behaviour: "a unit-test read outside the gate hash fails, naming
the path". GREEN is one mode in one tooling script, fed through a pipeline that
already exists. RED is one bash `describe`, one helper, one test file and eight
one-line migrations. A split into "`--gated`" and "`GatedFs`" was considered.
The second story would contain no production code at all, with every file
`test`, and it would pass on arrival. Keeping them together gives the project
half a real RED (it fails until `--gated` exists), and that is the cheapest way
to have watched it fail.

### Open questions for the user

- **Q1 (resolved 2026-09-30, user: keep it broad). The breadth of the rule.** The guard refuses **any**
  read outside the gate hash, not only docs. Today that changes nothing:
  measured, every read is of `src/`, `tests/` or the two covered docs. But a
  future test that reads `sourcemap.json` or `build/place.rbxl` (both ignored)
  would be refused, and the fix is not a covers line, because ignored files are
  never hashed. It would be moving the read into a gate input, or narrowing the
  rule. I recommend the broad rule, because an unhashed input is the bug whatever
  its category. Say if you want it narrowed to `docs/` only.
- **Q2 (non-blocking). The `unit` gate's cost.** It gains one
  `classify.sh --gated` spawn per run (the pipeline measured 0.14s. classify.sh's
  own startup adds to that, and RED records the real number). That is negligible
  against 56s.

### PLANNED → RED checks (Lead PO, 2026-09-30)

- **ACs testable:** yes. Each has a suite, a whole-line or `==` needle, and a
  paired control.
- **The gate that fails if the artifact breaks:** `unit` (required) for the
  project half. `selftest` → `classify.test.sh` (CI `gates` job) for the harness
  half.
- **Changed signatures:** none (see Contract).
- **Deferred verifications:** DV-1, DV-2 and DV-3, each with the owner GATES.
- **Freeze:** `scripts/classify.sh` is `tooling`, so the lock freezes it in RED.
  The project half is `test`, which GREEN cannot write.
