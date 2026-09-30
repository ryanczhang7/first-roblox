---
id: HARNESS-022
title: A test that reads a file outside the gate hash fails, naming it
slug: a-test-that-reads-a-file-outside-the-gat
epic: 
type: feature
status: done
phase: DONE
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
| `tests/shared/tuning_controls_test.luau` | `test` | RED | **RED amendment (2026-09-30).** Not a requirer of `@lune/fs`, but its module-level `local realRows = TuningSpec.read().rows` read `tuning.md` at **require time**, which measurement §1 missed (it grepped for `local x = fs.` captures, not for a helper called at load). Through `GatedFs` that read is a `classify.sh --gated` spawn during discovery: measured after the migration, `lune run test -- --list` took 1.17s and exited 1 with `LOAD FAIL tests/shared/tuning_controls_test.luau`. It is now a memoised `realRows()` called inside each case; `--list` is back to 0.51s, `471 tests`, exit 0, and the "lazy" bullet below holds again |
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
GatedFs.rawReadFile(path: string): string                -- UNCHECKED read; AC-5's control only (RED amendment)
```

- **RED amendment (2026-09-30): `rawReadFile`.** AC-5's control reads the
  refused path "through the raw module", and AC-7 forbids the `@lune/fs`
  literal in every test file but `GatedFs.luau` - so the test file cannot
  require the raw module itself. The helper exposes one unchecked read instead
  of the raw table (a whole table would hand every member past the check).
  The bypass this opens is closed in the same guard case: AC-7's real-tree
  assertion also reports any test file other than `gated_fs_test.luau` whose
  code mentions `rawReadFile`.

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
- **RED amendment (2026-09-30): the real-tree case is red in RED, not green.**
  The guard reads each listed file's text, and it reads it through
  `GatedFs.readFile` - a guard that bypassed the check to enforce the check
  would be the wrong example. So the real-tree case fails with
  `--gated exited 2` like every other read, and "passes on arrival" is true
  only of the five in-memory cases and the reader's own edge cases. The rule
  itself was watched to fire outside the framework instead (handoff, "AC-7
  measured outside the framework"): 8 offenders before the migration, exactly
  the eight requirers; 0 after; 1 under the DV-3 mutation, naming
  `tests/server/projection_test.luau`. In-framework DV-3 stays with GATES.
- **RED amendment: the guard's own needle.** `gated_fs_test.luau` is in the
  scanned set, so a `local NEEDLE = "@lune/fs"` in it is the guard's first
  offender (measured: 9 offenders until it was split). The needle is spelled
  `"@lune/" .. "fs"` there, the concatenation `## Out of scope` names, and
  the five in-memory cases hold the needle inside longer literals, which the
  whole-literal rule does not count.

### RED's expected failure, stated in advance

After the migration, every test that reads a file through `GatedFs` goes red
with `scripts/classify.sh --gated exited <n>` (unknown option). That covers every
`SourceScan` guard and every `TuningSpec`/`RateLimitSpec` reader: 11 test files
reach `fs` through those helpers (`grep -rln 'SourceScan\|TuningSpec\|RateLimitSpec' tests --include=*_test.luau`).
The count is unknown until RED runs it. **RED records the failed count and shows
that every `FAIL` message contains `--gated`.** A failure without `--gated` is a
migration bug, not the expected red.

**RED amendment (2026-09-30): the expression, and the count.** The expression
as first written, `grep -A1 '^  FAIL' | grep -v '^  FAIL' | grep -vc -- '--gated'`,
cannot print 0 on more than one failure: `grep -A1` emits a `--` group
separator between matches, which the final `grep -vc` counts (measured: 42 on
the run that had 43 FAILs, all of them `--gated`). With
`--no-group-separator` it measures the *first* line under each FAIL, and six
FAILs in `tuning_controls_test.luau` carry the cause on a later line, because
that file's `accepts`/`saysAll` helpers wrap the error under their own text.
The check that means what the sentence says is per FAIL **block**:

    lune run test > out.txt; awk '
      /^  (pass|FAIL)  / || /^[0-9]+ passed, / { if (inblock && !seen) missing++; inblock = ($0 ~ /^  FAIL  /); seen = 0; next }
      inblock && index($0, "--gated") { seen = 1 }
      END { if (inblock && !seen) missing++; print missing + 0 }' out.txt

which prints `0` (handoff). Measured red: `422 passed, 49 failed`, 49 FAIL
blocks, 0 without `--gated`, 0 LOAD FAIL.
AC-7's **in-memory** cases and the reader's edge cases pass on arrival (8
cases). Its real-tree case reads through `GatedFs` and is red like the rest
(see "The AC-7 guard", RED amendment).

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

### Results (GATES, Lead PO, 2026-09-30, run before `gates.sh`)

All of these ran through `scripts/mutate.sh`, which reported every restore
`verified byte-for-byte`. After them, `git diff --quiet .claude/harness/project.conf`
reported it clean, and `frozen.sh verify` gave
`frozen: OK — 77 path(s) unchanged since the snapshot for HARNESS-022`.

**DV-1: DONE.** Each expression was dry-run first and deleted exactly one line
(`-> deletes 1`).

    $ bash scripts/mutate.sh .claude/harness/project.conf '/^covers | unit      | docs\/wiki\/stack\.md$/d' -- lune run test
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_harness_project.conf.20260930T200232Z.828242.bak) ===
    469 passed, 2 failed
      FAIL  tests/shared/contract_raise_test.luau :: AC-3: stack.md records the cap as 511, keeps the prefix sentence, and records the off-by-one
      FAIL  tests/shared/gated_fs_test.luau :: AC-4: a covered doc (stack.md) reads through GatedFs byte-equal to the raw read
    grep -o 'read outside the gate hash: [^ ]*' | uniq -c  ->  2 read outside the gate hash: docs/wiki/stack.md

    $ bash scripts/mutate.sh .claude/harness/project.conf '/^covers | unit      | docs\/wiki\/game\/tuning\.md$/d' -- lune run test
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_harness_project.conf.20260930T200340Z.831943.bak) ===
    454 passed, 17 failed
    by file: tuning_spec_test 7, tuning_controls_test 6, gated_fs_test 3, rate_limit_provenance_test 1
    grep -o 'read outside the gate hash: [^ ]*' | uniq -c  ->  15 read outside the gate hash: docs/wiki/game/tuning.md

The 17 is at least the 5 that HARNESS-021 DV-2 predicted. Each final line matches
`^[0-9]+ passed, [1-9][0-9]* failed$`. The shipped-conf control is the
unmutated `lune run test`, which gave `471 passed, 0 failed` (exit 0) at the end
of GREEN, and the `unit` gate observed 471 in `gates.sh --fast` (`## Notes`,
"GREEN verified"). The two mentions of `architecture.md` in comments do not
trip it.

**DV-2: DONE, with three mutations of `tests/helpers/GatedFs.luau`.**

    allow      s/local hit = set\[key\] == true/local hit = true/          -> 465 passed, 6 failed
      AC-5: reading docs/wiki/architecture.md (uncovered) raises, first line naming the path
      AC-5: reading docs/wiki/game/loop.md (uncovered) raises, first line naming the path
      AC-5: reading .claude/commands/advance-story.md (a harness prompt) raises, first line naming the path
      AC-5: gated() agrees with readFile - true for the covered doc, false for the uncovered one
      AC-5: a backslash path and a ./ prefix are normalised before the check, and nothing else is
      AC-6 control: a doc written after the first read is still refused - the re-ask judges, it does not allow
      (every AC-4 case stayed green)
    cached     s/hit = ask({ key })\[key\] == true/hit = set[key] == true/  -> 470 passed, 1 failed   (wrong value: the re-ask answers from the stale set, no spawn)
      AC-6: a test file written after the first read is judged on the re-ask and reads back
    nostrip    s/return string.sub(slashed, 3)/return slashed/              -> 470 passed, 1 failed
      AC-5: a backslash path and a ./ prefix are normalised before the check, and nothing else is

Each run: `exit 1`, `restored (verified byte-for-byte ...)`.

*Observation (no amendment needed):* under `cached`, `source_guard_test` did
**not** fail. AC-6's parenthetical says `SourceScan` **reads**
`src/shared/__ac6_uncommitted_fixture.luau` through the helper. It does not: the
case only **lists** it through `SourceScan.sourceFiles` → `classifierList`
(`tests/shared/source_guard_test.luau:135-137`), and never calls `readFile` on it.
The parenthetical is context, not the criterion. AC-6 is pinned by its own
case, which the `cached` mutation turned red alone.

**DV-3: DONE, in-framework.**

    $ bash scripts/mutate.sh tests/server/projection_test.luau 's#require("../helpers/GatedFs")#require("@lune/fs")#' -- lune run test
    exit 1, restored (verified byte-for-byte
    470 passed, 1 failed
      FAIL  tests/shared/gated_fs_test.luau :: AC-7: no test file other than tests/helpers/GatedFs.luau names @lune/fs in code
            ...gated_fs_test:325: 1 test file(s) reach @lune/fs directly instead of through GatedFs:
      tests/server/projection_test.luau

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
- RED, `test-developer` (dispatched by /advance-story with `model: fable`), resolved to `claude-fable-5-1` (Fable 5.1), as the agent reports. That matches the plan. **Verdict on the RED success condition: met.** The orchestrator's re-run reproduced `422 passed, 49 failed` exactly. The Contract's literal `grep -vc` expression cannot print 0 (RED amendment 4; the orchestrator measured 54). The criterion it stood for, "every FAIL block names `--gated`", was confirmed as `0` by an independent block parser. One miss, caught by the orchestrator: RED did not move the `project-counters` literals for its two new `.luau` files. It was sent back once and fixed.
- GREEN, `feature-developer` (dispatched by /advance-story with `model: opus`), resolved to `claude-opus-5-5` (Opus 5.5), as the agent reports. That matches the plan.

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

Two suites. The harness half is a new `describe` at the end of
`.claude/tests/classify.test.sh`, on its own committed fixture (`GFIX`,
`make_project_fixture` + the six paths + the covers line via `write_conf`
BEFORE the commit). The project half is `tests/shared/gated_fs_test.luau`,
reading through the new `tests/helpers/GatedFs.luau`.

| AC | Test name(s) | Level / oracle |
|---|---|---|
| AC-1 | `AC-1: --gated exits 0`; `AC-1: --gated prints src/main.ts as a whole line`; `... prints the covered docs/wiki/game/tuning.md`; `... does not print the uncovered docs/wiki/architecture.md`; `... does not print the story file docs/backlog/stories/T-1.md`; `... does not print the harness prompt .claude/commands/x.md`; `... does not print the ignored build/out.txt`; `AC-1: --gated prints no category column`; `AC-1 control: without the covers line, tuning.md is not printed`; `AC-1 control: and src/main.ts still is` | bash, `grep -cx` whole line, one assertion per path; printed and not-printed paired in one output |
| AC-2 | `AC-2: --gated printed exactly one docs path, tuning.md, to edit`; `AC-2: gate_tree_hash is available on the fixture`; `AC-2: editing the doc --gated printed moves the hash`; `AC-2: editing the doc --gated did not print leaves the hash unchanged` | bash; the moving path is read OUT of `--gated`'s output (`grep '^docs/' \| head -n 1`), own before/after per edit, `if [ "$a" = "$b" ]`, no loop |
| AC-3 | `AC-3: --gated docs prints tuning.md`; `AC-3: --gated docs does not print src/main.ts`; `AC-3: --gated on a path that does not exist exits 0`; `AC-3: and prints nothing`; `AC-3: --gated build/out.txt (ignored) exits 0`; `AC-3: and prints nothing for the ignored file`; `AC-3: an untracked src/late.ts created after the commit is printed by --gated src/late.ts` | bash, whole line / exit code / empty output |
| AC-4 | `AC-4: a covered doc (tuning.md) reads through GatedFs byte-equal to the raw read`; `... (stack.md) ...`; `AC-4: a source module (Scaffold.luau) ...` | lune; `==` against `GatedFs.rawReadFile`, with `#raw > 0` so equality over nothing cannot pass |
| AC-5 | `AC-5: reading docs/wiki/architecture.md (uncovered) raises, first line naming the path`; `... docs/wiki/game/loop.md ...`; `... .claude/commands/advance-story.md (a harness prompt) ...`; `AC-5: gated() agrees with readFile - true for the covered doc, false for the uncovered one`; `AC-5: a backslash path and a ./ prefix are normalised before the check, and nothing else is` | lune; `string.split(err, "\n")[1] == "read outside the gate hash: <path>"`; controls in the same case: raw read succeeds and is non-empty, message has no `os error`, message has a second (hint) line |
| AC-6 | `AC-6: a test file written after the first read is judged on the re-ask and reads back`; `AC-6 control: a doc written after the first read is still refused - the re-ask judges, it does not allow` | lune; warm-up read first, probe written, body `pcall`ed, probe removed on every exit path, error re-raised at level 0 |
| AC-7 | in-memory: `AC-7: require("@lune/fs") in code is flagged`; `AC-7: a bare '@lune/fs' literal is flagged - ...`; `AC-7: a line comment quoting require("@lune/fs") is not flagged`; `AC-7: a block comment quoting ... is not flagged`; `AC-7: "@lune/fsx" is not flagged - whole-literal equality, not a substring`. Reader edges: `AC-7: stringLiteralsIn returns each literal's contents in order, with delimiters and comments out`; `AC-7: adding the reader changed neither codeOnly nor commentsOnly on a text with every literal kind`. Real tree: `AC-7: no test file other than tests/helpers/GatedFs.luau names @lune/fs in code` (also reports any other file calling `rawReadFile`); `AC-7 control: a probe-named file is skipped by the guard and a real helper is not` | lune; list from `SourceScan.classifierList("test", "tests")`, `__probe_`/`__*_probe.` basenames skipped, `GatedFs.luau` exempt by equality, failure message lists every offending path; size floor (`>= 10` scanned, self and the exempt path present) |
| AC-8 | none in RED (Settled + deferred, DV-1, owner GATES) | - |

Edges pinned beyond the ACs' letter: an ignored file named as a pathspec
prints nothing (AC-3); `docs//wiki/...` (a doubled slash) is NOT rewritten and
is refused (the "nothing else" half of the normalisation rule); the AC-6
negative control (a late file that is a `docs` path is still refused).

Not pinned, left to GREEN: `--gated` combined with `--only`/`--list` being a
usage error (Contract says so; no test, because it passes on arrival today
for the wrong reason - `--gated` is itself the unknown option); the hint's
wording; the exact cost of the spawn.

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. -->

**Model:** this RED ran on **Fable 5.1** (`claude-fable-5-1`), which is the
planned `fable`. No override was reported to the dispatch.

### Commands

    lune run test                          # project half; 422 passed, 49 failed in RED
    lune run test -- --list                # 471 tests, exit 0, 0.51s (no spawn at load)
    bash .claude/tests/classify.test.sh    # harness half; classify: 47 passed, 12 failed in RED

Freeze the tests before GREEN starts:
`bash scripts/frozen.sh snapshot tests .claude/tests/classify.test.sh`, and
`bash scripts/frozen.sh verify` before it ends. RED's work is uncommitted, so
`git diff` is not the check.

`gates.sh --fast` was **not** run, on the brief's instruction (it stamps the
active story; the lune suite and a gate must not overlap). In its place the
lint and format gates' tools were run directly over the whole test tree:
`stylua --check tests` clean, `selene tests` `0 errors 0 warnings 0 parse
errors`. GREEN should run `--fast` first thing.

### The red, verbatim

Harness half (`bash .claude/tests/classify.test.sh`, tail of the new describe):

      --gated lists what the gate tree hash covers, and only that (HARNESS-022, AC-1..AC-3)
        FAIL AC-1: --gated exits 0
             expected: 0
             actual:   2
        FAIL AC-1: --gated prints src/main.ts as a whole line
             expected: 1
             actual:   0
        FAIL AC-1: --gated prints the covered docs/wiki/game/tuning.md
             expected: 1
             actual:   0
        FAIL AC-1 control: and src/main.ts still is
             expected: 1
             actual:   0
        FAIL AC-2: --gated printed exactly one docs path, tuning.md, to edit
             expected: docs/wiki/game/tuning.md
             actual:
        FAIL AC-2: editing the doc --gated printed moves the hash
             --gated printed no docs path, so there was nothing to edit; its output was: classify: unknown option --gated
             [usage text]
        FAIL AC-3: --gated docs prints tuning.md
             expected: 1
             actual:   0
        FAIL AC-3: --gated on a path that does not exist exits 0
             expected: 0
             actual:   2
        FAIL AC-3: and prints nothing
             expected:
             actual:   classify: unknown option --gated
             [usage text]
        FAIL AC-3: --gated build/out.txt (ignored) exits 0
             expected: 0
             actual:   2
        FAIL AC-3: and prints nothing for the ignored file
             expected:
             actual:   classify: unknown option --gated
             [usage text]
        FAIL AC-3: an untracked src/late.ts created after the commit is printed by --gated src/late.ts
             expected: 1
             actual:   0

    classify: 47 passed, 12 failed

47 = the 38 baseline + the 9 cases that pass on arrival (see below).

Project half (`lune run test`): `422 passed, 49 failed`, 0 `LOAD FAIL`. Every
FAIL block carries `--gated` (per-block awk from the Contract: prints `0`;
`grep --no-group-separator -A1 '^  FAIL' | grep -v '^  FAIL' | grep -vc -- '--gated'`
prints `6`, all six in `tuning_controls_test.luau` where the helper wraps the
cause on the next line - inspected, each one is the `--gated exited 2` error).
The shape of every one:

      FAIL  tests/shared/gated_fs_test.luau :: AC-4: a covered doc (tuning.md) reads through GatedFs byte-equal to the raw read
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\GatedFs:68: scripts/classify.sh --gated  exited 2
    stdout:
    stderr: classify: unknown option --gated

      FAIL  tests/shared/gated_fs_test.luau :: AC-5: reading docs/wiki/architecture.md (uncovered) raises, first line naming the path
            ...gated_fs_test:81: first line of the error is [...GatedFs:68: scripts/classify.sh --gated  exited 2], not [read outside the gate hash: docs/wiki/architecture.md]; the error was:
    ...

The 49 by file: `gated_fs_test` 11 (AC-4 x3, AC-5 x5, AC-6 x2, AC-7 real-tree
x1); `tuning_spec_test` 7; `tuning_controls_test` 6; `contract_raise_test` 5;
`phase_union_guard_test` 9; `source_guard_test` 3; `projection_test` 2;
`projection_controls_test` 1; `roblox_runtime_guard_test` 2;
`raw_remote_guard_test` 2; `rate_limit_provenance_test` 1. That is the 11
files the Contract predicted reach `fs` through the helpers, plus
`gated_fs_test`.

Stage record: with the reader added to `SourceScan` and the new suite in
place but BEFORE the eight requires were migrated, the run was
`459 passed, 12 failed` - all 452 baseline cases green, so the reader changed
nothing they pin (the "before" count for `codeOnly`/`commentsOnly`, below).

### Files touched

- `tests/helpers/GatedFs.luau` - new
- `tests/shared/gated_fs_test.luau` - new
- `tests/helpers/SourceScan.luau` - `walk` takes an optional literal
  collector; new `SourceScan.stringLiteralsIn`; `require("./GatedFs")`
- `tests/helpers/TuningSpec.luau`, `tests/helpers/RateLimitSpec.luau` -
  `require("./GatedFs")`
- `tests/net/phase_union_guard_test.luau`, `tests/server/projection_test.luau`
  (the require inside the AC-4 case), `tests/shared/contract_raise_test.luau`,
  `tests/shared/source_guard_test.luau`, `tests/shared/tuning_spec_test.luau`
  - `require("../helpers/GatedFs")`
- `tests/shared/tuning_controls_test.luau` - module-level read made lazy
  (Contract amendment)
- `.claude/tests/classify.test.sh` - the new describe
- `.claude/tests/project-counters.test.sh` - baselines 90 -> 92 (see
  "project-counters" below)
- this story: `## Contract` (four amendments, each marked "RED amendment"),
  `## Test plan`, this section, `## Regressions`
- `lune/test.luau` NOT touched. `scripts/classify.sh`, `lib.sh`,
  `project.conf`, `paths.conf` NOT touched (one `mutate.sh` probe on `lib.sh`,
  restored and verified; see `## Regressions`).

Relative require forms measured to resolve under lune 0.10.5: helpers use
`require("./GatedFs")`, tests use `require("../helpers/GatedFs")` (the same
forms every neighbouring require in those files already uses; the whole suite
loads, `--list` exits 0).

### Export shape the tests already pin (fact, not suggestion)

GREEN writes only `scripts/classify.sh`, so this is what the **helper** (RED's
code, frozen in GREEN) demands of `--gated`:

- `bash scripts/classify.sh --gated` with **no** pathspec, and
  `bash scripts/classify.sh --gated <one path>`, invoked via
  `process.exec("bash", { "scripts/classify.sh", "--gated", ... })` from the
  repository root. Exit 0, one path per line on stdout, no category column
  (the helper trims each line and keys a set on it, so a `\t` column would
  make every path a miss). Paths in git's form: forward slashes, no `./`.
- On the re-ask the helper passes the **normalised** path (`\`->`/`, leading
  `./` stripped) and looks for exactly that string in the output.
- Any non-zero exit is an error (fail closed). The test never depends on the
  usage text.

What the tests pin in the harness half: `--gated` exit 0 on an empty answer;
`--gated docs`, `--gated docs/wiki/game/nope.md`, `--gated build/out.txt`,
`--gated src/late.ts` as pathspecs; whole-line output. Not pinned: ordering
(the Contract says `LC_ALL=C sort -u`; nothing asserts it), the usage error on
`--gated --only`, the header comment.

`GatedFs` exports (all in `tests/helpers/GatedFs.luau`): `readFile`,
`rawReadFile`, `writeFile`, `isFile`, `isDir`, `readDir`, `removeFile`,
`gated`. `SourceScan.stringLiteralsIn(text): { string }` is new; `codeOnly`,
`commentsOnly`, `hitsIn`, `memberHitsIn`, `classifierList` and every other
export are unchanged in name, signature and output. Checked: `git diff` on
`TuningSpec`, `RateLimitSpec` and the five migrated tests is the one
`require` line each; no caller of `SourceScan`/`TuningSpec`/`RateLimitSpec`
changed.

### `codeOnly` / `commentsOnly` before and after the reader

The reader is a third `walk` caller passing a collector; the two existing
callers pass none, so their code path is untouched. Measured, not assumed:
the suites that use them (`source_guard_test`, `phase_union_guard_test`,
`contract_raise_test`, `raw_remote_guard_test`, `roblox_runtime_guard_test`,
and `PhaseUnion` via `phase_union_guard_test`) were **all green** in the
stage run with the reader present and the requires not yet migrated
(`459 passed, 12 failed`, the 12 all in `gated_fs_test`); the baseline before
the story was `452 passed, 0 failed`. So before = 452/452, after the reader =
452/452, plus the new edge case
`AC-7: adding the reader changed neither codeOnly nor commentsOnly ...` (pass).
One thing learned while writing that case: `commentsOnly` blanks the CLOSING
`]]` of a block comment (pre-existing `walk` behaviour, the mode flips before
the close is dropped); the case pins that output as it was.

### Tests that pass on arrival, and what earns them

- Harness half, 9 cases: the six "does not print X" (AC-1 x4 incl. the
  no-column check, AC-1 control tuning.md, AC-3 `docs` does not print
  `src/main.ts`), `AC-2: gate_tree_hash is available`, and
  `AC-2: editing the doc --gated did not print leaves the hash unchanged`.
  The "does not print" cases are vacuous on a usage message and are earned
  by their pair in the same output (a `--gated` that prints everything fails
  them the moment the printed cases pass). The AC-2 static case pins
  HARNESS-021 behaviour that exists, so it was **earned by a `mutate.sh`
  probe** on `gated_stdin` (keep every doc): that one case went red and
  nothing else in the block changed. Output pasted in `## Regressions`.
- Project half, 8 cases: the five AC-7 in-memory cases, the two reader edge
  cases, and `AC-7 control: a probe-named file is skipped ...`. The rule they
  exercise was watched to fail against the real tree outside the framework
  (next section), and the reader's failure mode (returns nothing / returns
  everything) is what the edge case pins.

### AC-7 measured outside the framework (the suite fails at import-time reads)

Because every `GatedFs.readFile` is red in RED, the real-tree AC-7 case has
executed no assertion. The same rule was run as a scratch lune script over
`SourceScan.classifierList("test", "tests")` with the raw module:

    # before the migration (reader present, requires not yet changed)
    74 files scanned; 8 offenders:
      tests/helpers/RateLimitSpec.luau
      tests/helpers/SourceScan.luau
      tests/helpers/TuningSpec.luau
      tests/net/phase_union_guard_test.luau
      tests/server/projection_test.luau
      tests/shared/contract_raise_test.luau
      tests/shared/source_guard_test.luau
      tests/shared/tuning_spec_test.luau
    # after the migration
    74 files scanned; 0 offenders:
    # DV-3's mutation, under mutate.sh (the file was restored, verified byte-for-byte)
    $ bash scripts/mutate.sh tests/server/projection_test.luau 's#require("../helpers/GatedFs")#require("@lune/fs")#' -- lune run <scratch>/guard_probe.luau
      163 + 		local fs = require("@lune/fs")
    74 files scanned; 1 offenders:
      tests/server/projection_test.luau
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_server_projection_test.luau.20260930T192529Z.710693.bak) ===

(A first version of the probe reported 9: `gated_fs_test.luau` itself, on its
`NEEDLE` literal. Fixed by spelling the needle in two pieces; see the Contract
amendment.)

### Expected value of every negative control (for GREEN to confirm)

| Control | Where | Threshold / needle | Expected against the real `--gated` | Measured in RED |
|---|---|---|---|---|
| no covers line -> tuning.md not printed, main.ts printed | classify AC-1 | `grep -cx` = 0 and = 1 | 0 / 1 | usage text: 0 / **0** (main.ts red) |
| architecture.md, T-1.md, x.md, build/out.txt not printed | classify AC-1 | `grep -cx` = 0 each | 0 each | 0 each (vacuous on usage text) |
| editing the printed doc moves the hash | classify AC-2 | `h1 != h0` | moves | no path printed -> red |
| editing the unprinted doc leaves the hash | classify AC-2 | `h2 == h3` | unchanged | unchanged; **probe**: mutated `gated_stdin` moved it (`5c44e376... -> 763154ad...`) |
| `--gated docs/wiki/game/nope.md`, `--gated build/out.txt` | classify AC-3 | exit 0, empty | 0, empty | exit 2, usage |
| raw read of each AC-5 path succeeds, non-empty | gated_fs AC-5 | `pcall` ok, `#raw > 0` | ok; architecture.md is 25265 bytes (measured with raw `fs` in a scratch script) | not executed (case red before it) |
| refusal carries no `os error` | gated_fs AC-5 | `string.find == nil` | nil | not executed |
| `gated("docs//wiki/game/tuning.md")` | gated_fs AC-5 | `== false` | false (git does not enumerate that spelling; re-ask prints nothing) | not executed |
| late `docs/wiki/__probe_gated_late.md` refused | gated_fs AC-6 control | first line `==` | refused, first line names the path | not executed |
| `#files >= 10`, self and exempt path listed | gated_fs AC-7 | counts | 74 listed today (measured outside) | 74 |
| `error(..., 0)` first line exact | GatedFs | `string.split(err,"\n")[1]` | exact (measured in a scratch script on lune 0.10.5: `pcall` returns the message with no prefix) | measured |

Timing facts GREEN inherits: a `bash scripts/classify.sh` spawn from lune on
this machine cost 0.76s wall for the failing `--gated` call (usage + exit),
against the Contract's 0.023s CPU figure - so expect the first checked read
to add roughly a second on Windows, once per run, plus one more per miss.
`--list` is unaffected (0.51s, no spawn).

### project-counters (the `harness` gate) re-measured

`bash scripts/gates.sh --fast` was run by the **orchestrator** (not by RED,
per the brief). Its `harness` gate failed 7 cases of
`.claude/tests/project-counters.test.sh` because this RED added two `.luau`
files; the log (`.claude/state/gate-logs/harness.log`) reads
`expected count: 90 / actual count: 92` for format and lint against
`stylua over 92 files` / `selene over 92 files`, `91 / 93` for the
untracked-file cases, with typecheck (17) and every narrow case NOT failing.
Format, lint, typecheck and build PASSed; unit FAILed 422/49 as expected.
So, as TEL-002 RED, TEL-003 RED and HARNESS-011 did: `BASE_FORMAT`/`BASE_LINT`
90 -> 92, the labels that spelled 90/91 -> 92/93, `NARROW_*` and
`BASE_TYPECHECK` untouched (src did not move), a `LAST MEASURED:
HARNESS-022 (RED)` entry added above HARNESS-011's, no assertion relaxed.
Re-run alone, with no lune run in flight:

    $ bash .claude/tests/project-counters.test.sh
      preconditions
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
             expected:
             actual:    M tests/helpers/RateLimitSpec.luau
              M tests/helpers/SourceScan.luau
              M tests/helpers/TuningSpec.luau
              M tests/net/phase_union_guard_test.luau
              M tests/server/projection_test.luau
              M tests/shared/contract_raise_test.luau
              M tests/shared/source_guard_test.luau
              M tests/shared/tuning_controls_test.luau
              M tests/shared/tuning_spec_test.luau
             ?? tests/helpers/GatedFs.luau
             ?? tests/shared/gated_fs_test.luau
      ...
    project-counters: 39 passed, 1 failed

The one failure is the stray-files precondition over this story's own
uncommitted files; it clears at the RED commit (TEL-003's handoff records the
same). Every count case is green at 92/92/17, narrow 17/17/7.

### Deferred verifications, declined in writing

- **DV-1 (AC-8 end to end): cannot run in RED.** `--gated` does not exist, so
  every read is red for that reason and deleting a covers line would change
  nothing observable. Left to GATES as written.
- **DV-2 (the helper's check discriminates): cannot run in RED.** Both
  mutations need a real `--gated` to make AC-4 stay green while AC-5/AC-6 go
  red; today all three are red before the check runs. Left to GATES. One note
  for the second mutation: "drop the `./` strip" is pinned by
  `AC-5: a backslash path and a ./ prefix are normalised ...`, and "return the
  cached answer without re-asking" is pinned by the AC-6 case (the warm-up
  read fills the cache before the probe exists, on purpose).
- **DV-3 (the AC-7 guard fires on the real tree): the in-framework run cannot
  discriminate in RED** (the real-tree case reads through `GatedFs`). The rule
  was measured outside the framework instead, above, including the exact
  DV-3 mutation under `mutate.sh`. GATES should still run the in-framework
  command once `--gated` exists, and expects the message to name
  `tests/server/projection_test.luau`. Note the Contract's example expression
  matches the require form actually written (`require("../helpers/GatedFs")`).

### Things GREEN should know

- **Only `scripts/classify.sh` changes.** Everything under `tests/` is frozen.
  If the helper's parsing turns out wrong against the real output, that is a
  return to RED, not a tweak to `--gated`'s format to fit it.
- `--gated` is spawned from the repository root with `cd "$ROOT"` already in
  classify.sh; the fixture tests run it from `$GFIX`, so the `HARNESS_ROOT`
  it derives must be the script's own root, as `--list` does today.
- The AC-2 moving case edits whichever `docs/` path `--gated` prints first.
  With the fixture's single covers line that is `tuning.md`, and the
  preceding assertion pins that it is exactly that path.
- The AC-6 probe `tests/helpers/__probe_gated_late.luau` is written under
  `tests/helpers/` and removed in the same case; a run killed midway leaves a
  valid strict Luau file that says it is safe to delete. `docs/wiki/__probe_gated_late.md`
  likewise for the control. Neither is in the tree now.
- Story text in `## Context` §1 says "no file captures it at load"; that was
  wrong for `tuning_controls_test.luau` (Contract amendment). Nothing else
  reads at require time: `--list` exits 0 with no spawn after the fix.

## Regressions

**RED, 2026-09-30 - not a return, but one case is green on arrival and was
earned by a reverted mutation.** `AC-2: editing the doc --gated did not print
leaves the hash unchanged` pins behaviour HARNESS-021 built, so it passed on
its first execution. Mutating `gated_stdin` (`.claude/hooks/lib.sh:673`) to
keep every `docs` path made exactly that case go red, and the restore was
verified:

    $ bash scripts/mutate.sh .claude/hooks/lib.sh 's/if (lp ~ cr\[i\]) { print; next }/if (1) { print; next }/' -- bash .claude/tests/classify.test.sh
    === mutate: .claude/hooks/lib.sh (1 line(s) changed by s/if (lp ~ cr\[i\]) { print; next }/if (1) { print; next }/) ===
      673 -       for (i = 1; i <= n; i++) if (lp ~ cr[i]) { print; next }
      673 +       for (i = 1; i <= n; i++) if (1) { print; next }
    ...
        FAIL AC-2: editing the doc --gated did not print leaves the hash unchanged
             expected: 5c44e37692dbbc8e8e2ec16ab8c17696d8e9a8d4
             actual:   763154ad117e293aebdce0c58102fc9ccf48eba9
    ...
    classify: 46 passed, 13 failed
    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_hooks_lib.sh.20260930T192210Z.698724.bak) ===

Unmutated, the same suite is `classify: 47 passed, 12 failed`: the one extra
failure is that case and nothing else moved.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-30T20:34:47Z
    commit: bfe22c1
    tree:   60d95aaa2bca459288dde28bcab412154f4e859d
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 92)
    PASS         lint (1s, observed 92, floor 1)
    PASS         typecheck (3s, observed 17)
    PASS         unit (64s, observed 471, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 57746)
    PASS         harness (19s, observed 40)
    UNCONFIGURED mutation

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

### Entering RED (Lead PO, /advance-story, 2026-09-30)

- **PO decision 1: a clean tree, by stash.** The main checkout held the
  uncommitted third-pass `docs/wiki/game/{loop,mechanics,playtest,roles,tuning}.md`,
  which belong to ROUND-006. Measured against them, `lune run test` gave
  `445 passed, 7 failed`: `round_seconds` spec 420, module 480, plus the
  `signal_rate_limit_seconds` provenance row and four `tuning_controls` cases.
  That would put foreign reds inside this story's RED and block `unit` in GATES.
  The user chose to stash them:
  `stash@{0}: On main: ROUND-006 third-pass game docs (stashed for HARNESS-022, 2026-09-30)`.
  **They are restored with `git stash pop` when ROUND-006 starts.** They never go
  into a HARNESS-022 commit. `docs/backlog/stories/ROUND-006.md` stays untracked
  and is not this story's either.
- **Re-verified before dispatch:** `unit` required (`project.conf:377`). The eight
  `@lune/fs` requirers under `tests/` and the `fs.*` member counts match
  measurement §1. The Files table's classifications match `classify.sh`.
  HARNESS-021 is `phase: DONE`. There is no epic, so no done-when gap.
- **Baseline on the clean tree, at `b8a0ebe`:** `lune run test` gives
  `452 passed, 0 failed`, and `bash .claude/tests/classify.test.sh` gives
  `classify: 38 passed, 0 failed`.

### RED verified by the orchestrator (Lead PO, 2026-09-30)

- `lune run test` (orchestrator's own run): `422 passed, 49 failed`, 0 `LOAD FAIL`,
  exit 1. This reproduces RED's count exactly. An independent per-block parser
  (a FAIL header through the next `pass`/`FAIL`/summary line, where the block
  must contain `--gated`) printed `blocks without --gated: 0`. The Contract's
  original expression, `grep -A1 ... | grep -vc -- '--gated'`, printed `54` on
  this run. It counts `--` group separators, which confirms RED amendment 4.
  With `--no-group-separator` it printed `6`, as RED reported. By file:
  gated_fs 11, phase_union_guard 9, tuning_spec 7, tuning_controls 6,
  contract_raise 5, source_guard 3, and 2 each for projection, raw_remote_guard
  and roblox_runtime_guard, plus 1 each for projection_controls and
  rate_limit_provenance.
- `bash .claude/tests/classify.test.sh`: `classify: 47 passed, 12 failed`. All 12
  are AC-1..AC-3 cases failing on `unknown option --gated` (exit 2).
- The acceptance criteria are byte-identical to `main`, checked by diffing the
  section. There is no diff under `scripts`, `lune`, `src`, `.claude/hooks` or
  `.claude/harness`.
- Read: `GatedFs.luau` is lazy, keeps a whole-tree set, re-asks once per miss,
  memoises, fails closed with code/stdout/stderr, and refuses at level 0. The
  `gated_fs_test.luau` needles are `==` on the first line. AC-6 removes the probe
  under `pcall`. The AC-7 guard lists files through `classifierList`. The
  `SourceScan.walk` collector is inert when no collector is passed.
- **Admissibility, `bash scripts/gates.sh --fast` (orchestrator's run):**
  format PASS (92), lint PASS (92), typecheck PASS (17), build PASS, unit FAIL
  (`422 passed, 49 failed`, the expected red). `harness` FAILED 7 cases in
  `project-counters.test.sh`, `expected count: 90 / actual count: 92`, because
  RED's two new `.luau` files move BASE_FORMAT/BASE_LINT, as TEL-002 RED,
  TEL-003 RED and HARNESS-011 each did. The test-developer was sent back and
  moved the literals 90 -> 92 with a LAST MEASURED entry. Nothing was relaxed:
  the orchestrator read the diff, which changes only the two constants and
  their labels. Re-run: `project-counters: 39 passed, 1 failed`. The one failure
  is the "no stray .luau files" precondition listing this story's uncommitted
  test files, which clears at the commit (the same as TEL-002 and TEL-003).
  **The RED tests are admissible.**
- DV-1 and DV-2 are declined by RED in the handoff, as briefed, and stay owned
  by GATES. DV-3 was run by RED outside the framework only, because the
  real-tree case is red through `GatedFs` in RED. GATES still runs DV-3
  in-framework.
- Reminder for GREEN's dispatch: take the freeze snapshot right after
  `phase.sh set ... GREEN`, over `tests` and `.claude/tests/classify.test.sh`
  and `.claude/tests/project-counters.test.sh`.

### GREEN (feature-developer, 2026-09-30)

**Model:** ran on **Opus 5.5** (`claude-opus-5-5`), the planned `opus`. No
override was reported to the dispatch.

**What changed.**
- `scripts/classify.sh`: new `--gated [PATHSPEC...]` mode. It enumerates
  with `git ls-files --cached --others --exclude-standard -- <pathspecs, default .>`,
  pipes the list once through `classify_stdin | gated_stdin`, drops the category
  column (`cut -f2-`) and prints `LC_ALL=C sort -u`. It exits 0 on an empty
  answer. It returns the pipeline's status under `pipefail`, so a failing stage
  is an error and never a shorter list. `--gated` with `--only` or `--list`, in
  either order, is a usage error (exit 2). `--only` and `--list` with each other
  behave as before. The usage text and header comment are updated, and the usage
  `sed` range is now 5-9, for the new example line. `lib.sh` is not redefined
  or touched.
- `.claude/skills/quality-gates/SKILL.md`: one sentence at the end of the
  covers-over-a-doc paragraph.
- `project.conf`, `paths.conf`, `lib.sh` and `stack.md` were not touched. The
  freeze held: `bash scripts/frozen.sh verify` printed
  `frozen: OK - 77 path(s) unchanged`.

**Final outputs (tail lines, verbatim).**

    $ bash .claude/tests/classify.test.sh
      --gated lists what the gate tree hash covers, and only that (HARNESS-022, AC-1..AC-3)
    classify: 59 passed, 0 failed
    $ lune run test                   # exit 0, 135s wall on this run
    471 passed, 0 failed              # 0 FAIL blocks, 0 LOAD FAIL
    $ lune run test -- --list         # exit 0, 0.44-1.1s wall, no spawn
    471 tests
    $ bash .claude/tests/project-counters.test.sh
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
    project-counters: 39 passed, 1 failed

The one project-counters failure is the stray-file precondition over this
story's uncommitted test files, as RED predicted. Every count case passed at
BASE 92/92/17, narrow 17/17/7.

**Handoff controls, measured against the shipped `--gated`.** These come from a
scratch lune script that requires the real `tests/helpers/GatedFs.luau`, run
from the repository root. They are not inferred from the passes.

| Control | Expected (handoff) | Measured |
|---|---|---|
| AC-5 first line, `docs/wiki/architecture.md` | `read outside the gate hash: docs/wiki/architecture.md` | exactly that (`==` true); no `os error`; raw read ok, 25265 bytes (matches RED's figure) |
| AC-5 first line, `docs/wiki/game/loop.md` | same shape | exactly that; no `os error`; raw read ok, 28945 bytes |
| AC-5 first line, `.claude/commands/advance-story.md` | same shape | exactly that; no `os error`; raw read ok, 20293 bytes |
| AC-4 reads | equal to raw | tuning.md 17523 B, stack.md 35167 B, Scaffold.luau 1210 B, each `==` raw |
| `gated("docs//wiki/game/tuning.md")` | false | false |
| `./` prefix and backslash forms of a covered doc | true | true, true |
| AC-6 late `tests/helpers/__probe_gated_late.luau` | allowed on the re-ask | allowed; returned its 36 bytes; the re-ask spawn took 1.5s; the probe was removed |
| AC-6 control, late `docs/wiki/__probe_gated_late.md` | refused, naming it | first line `read outside the gate hash: docs/wiki/__probe_gated_late.md`; removed |
| AC-7 real tree | 0 offenders | the case passes: `no test file other than tests/helpers/GatedFs.luau names @lune/fs in code` |
| classify AC-1 control (no covers line) | tuning.md 0, main.ts 1 | pass (suite 59/0) |
| classify AC-2 moving / static | moves / unchanged | both pass |
| classify AC-3 nope.md, build/out.txt | exit 0, empty | pass; `git ls-files --others` on a nonexistent pathspec measured to exit 0 |
| whole-tree `--gated` | tuning.md and stack.md among docs | 155 paths; `docs/` lines are exactly `docs/wiki/game/tuning.md` and `docs/wiki/stack.md` (the Context measured 153 of 265 at `c54148d`; this tree adds GatedFs.luau and gated_fs_test.luau) |

**Cost (the Contract's Q2).** On this machine the first `GatedFs.gated()`
spawn of `bash scripts/classify.sh --gated` took **1.58s** by `os.clock`
(on Windows that tracks wall time), and a per-miss re-ask took about 1.5s.
`bash scripts/classify.sh --gated` run alone took 0.93-1.92s wall across six
runs. A plain `bash scripts/classify.sh src/x.luau`, which does no enumeration,
took 1.72-1.79s over three runs at the same time. So on Windows the cost is
bash startup plus sourcing `lib.sh`, not the pipeline. The Contract's
0.14s/0.023s figures are the pipeline and the CPU, not the wall cost. RED's
0.76s was taken on a quieter machine. The unit run took 135s wall, against the
~56s baseline. That difference is **not explained** by this story's spawns: one
whole-tree ask plus roughly ten miss re-asks at about 1.5s each comes to about
15-20s. The machine was visibly loaded, because the same bare classify call
varied by 2x. I have not measured this further. GATES should compare the
`unit` gate's duration against a baseline taken on the same machine at the
same time.

**Not run, as briefed:** `gates.sh` (fast or full) and `selftest.sh`. DV-1,
DV-2 and DV-3 stay with GATES.

### GREEN verified by the orchestrator (Lead PO, 2026-09-30)

- **Freeze:** a snapshot was taken right after `phase.sh set HARNESS-022 GREEN`,
  over every file `git ls-files --cached --others --exclude-standard -- tests`
  returns, plus `.claude/tests/classify.test.sh`,
  `.claude/tests/project-counters.test.sh` and the absent
  `tests/helpers/__probe_gated_late.luau` (77 paths). At the end of GREEN:
  `frozen: OK — 77 path(s) unchanged since the snapshot for HARNESS-022`.
- **Diff read:** `scripts/classify.sh` gains `--gated`, which runs
  `git ls-files ... | classify_stdin | gated_stdin | cut -f2- | LC_ALL=C sort -u`
  under `pipefail`. It redefines neither function. `--gated` with `--only` or
  `--list` is a usage error. The script `cd`s to the root, so from `docs/` it
  still prints root-relative paths (checked). `SKILL.md` gained one sentence.
- **Lead PO, the end of GREEN:** added the `GatedFs` paragraph to
  `docs/wiki/stack.md` §3. That is a covered doc, so the edit is made before any
  recorded gate run.
- **Orchestrator's runs, after the stack.md edit:**
  `bash .claude/tests/classify.test.sh` gave `classify: 59 passed, 0 failed`.
  `lune run test` gave `471 passed, 0 failed`, exit 0, 0 `LOAD FAIL`, **54s wall
  on an idle machine**, against the 50s baseline. So the feature-developer's
  135s was machine load and not the spawns. No `__probe_gated_late.luau` or
  `src/shared/__ac6*` file was left behind.
- **`bash scripts/gates.sh --fast`:** format PASS (92), lint PASS (92, floor 1),
  typecheck PASS (17), unit PASS (78s, observed 471, floor 443), build PASS
  (57746). harness FAIL: `project-counters: 39 passed, 1 failed`, and the one
  failure is `the working tree carries no stray .luau files`, the precondition
  over this story's uncommitted test files, which clears at the commit (the same
  as TEL-002 and TEL-003). No other harness case failed.
- **Model:** GREEN `feature-developer` was dispatched with `model: opus` and
  resolved to `claude-opus-5-5` (Opus 5.5), as the agent reports. That matches
  the plan.

### GATES (Lead PO, 2026-09-30)

- `phase.sh set HARNESS-022 GATES`, then a fresh freeze snapshot over the same
  77 paths. DV-1, DV-2 and DV-3 ran **before** `gates.sh`. The results are in
  `## Deferred verifications`, "Results".
- **The GATES commit.** A first full `gates.sh` was started on the uncommitted
  tree and then stopped. The `harness` gate's "no stray .luau files"
  precondition fails on any uncommitted `.luau` file, and TEL-003 cleared the
  same failure with a GATES commit. So this story's work was committed as
  `d645e00`. It was staged by name. It excludes `docs/backlog/stories/ROUND-006.md`
  and the stashed ROUND-006 docs.
- **A collision, not a failure.** The first full run on `d645e00` reported
  `harness` FAIL, with `project-counters: 34 passed, 6 failed`, all in the
  typecheck-counter cases
  (`Error opening game/ReplicatedStorage/Shared/__probe_h006_untracked`,
  `reports 5, not 9`). `harness.log` held **two** interleaved summaries,
  `40 passed, 0 failed` and `34 passed, 6 failed`: two `project-counters`
  processes had written to one log at once. The likely second writer is an
  orphan of the stopped run: TaskStop ended its shell, but on Windows its child
  kept going. That is not confirmed. With no bash, lune or toolchain process
  left (checked with `Get-Process`), the full run was repeated alone. It passed,
  with exactly one summary in `harness.log` (`project-counters: 40 passed,
  0 failed`). The story does not touch anything typecheck reads.
- **Recorded result** (written by `gates.sh` in `## Gate results`): commit
  `d645e00`, `result: pass (6 ran, 3 unconfigured, 0 known)`. unit took 37s
  against the 50s baseline.
- **Freeze across GATES:** `frozen: OK — 77 path(s) unchanged since the snapshot for HARNESS-022`.
- **Gate probes:** this story adds or changes no `gate |` line, so
  `## Gate probes` owes nothing. The new check lives in `unit`, and DV-1 is its
  observed failure.

### Phase commits cut at REVIEW (Lead PO, 2026-09-30; the user chose this fix)

- **What happened.** The work of RED, GREEN and GATES was first committed as one
  GATES commit (`d645e00`, never pushed), with a REVIEW commit after it.
  `check-boundaries.sh` then refused the branch:
  `FAIL story HARNESS-022: commit d645e00 changed '.claude/tests/classify.test.sh' while the story was in GATES, which may not write tests`
  (and the same for `project-counters.test.sh`). Its check 3j reads the phase
  from the **committed** frontmatter, commit by commit. The two suites were
  written in RED, but they were first committed at GATES. This was the
  orchestrator's error: HARNESS-021 committed each phase as it went.
- **The fix, which the user chose over a formal return to RED.** A return to
  RED would leave `d645e00` in the PR range, so the check would still fail. The
  two unpushed commits were rebuilt. `2b6c7c6` (**RED**, 14 files) holds
  everything RED wrote: the test files and both `.claude/tests` suites, with
  this story's frontmatter at `phase: RED`. `bfe22c1` (**GATES**, 4 files) holds
  `scripts/classify.sh`, `SKILL.md`, `stack.md` and the story. The RED commit is
  **cut after the fact**, and its story text is this file's final text with
  only the phase line changed.
- **Why this is honest and not a workaround.** The content did not change.
  `git diff d645e00 bfe22c1 -- . ':!docs/backlog/stories/HARNESS-022.md'` is
  empty, and the gate tree hash is `60d95aaa2bca459288dde28bcab412154f4e859d`
  in both records. That these files were written in RED and not after is
  proved by the freeze snapshots, not by the commits: `frozen: OK — 77 path(s)`
  at the end of GREEN and again at the end of GATES. Those 77 paths cover every
  test file and both harness suites, and they were taken immediately after each
  `phase.sh set`.
- **Gates re-run** on `bfe22c1`, alone with no toolchain process running:
  `All required gates passed (6 ran, 3 unconfigured, 0 known)`. `gates.sh`
  recorded it in `## Gate results`.

### REVIEW → DONE (orchestrator, 2026-09-30)

PR [ryanczhang7/first-roblox#40](https://github.com/ryanczhang7/first-roblox/pull/40)
was merged as `9648b50` at 2026-09-30T21:01:49Z, with head `c26b59d`. Timings
from its first and only CI run, on `c26b59d`:

- `gates` job: run [36773823126](https://github.com/ryanczhang7/first-roblox/actions/runs/36773823126), 2m25s in all.
  The "Harness self-test" step took 1m46s and included `classify: 59 passed, 0 failed`
  and `project-counters: 40 passed, 0 failed`. "Run gates" took 22s:
  format 1s, lint 0s, typecheck 2s, **unit 4s** (observed 471, floor 443),
  build 0s and harness 13s. Locally, unit took 37-64s.
- `boundaries` job: run [36773823084](https://github.com/ryanczhang7/first-roblox/actions/runs/36773823084), 8s.

Neither workflow declares a `timeout-minutes` key: `grep -rn timeout .github/workflows/`
finds only a comment about another project. So the limit is GitHub's default
of 6 hours, and nothing is near it. No gate reached REVIEW as *pending CI*.

**Open items carried out of this story:** HARNESS-020's Q4 is still open.
`--gated` exists only in this repository, so a `refresh-harness.sh` from
`../agentic-dev-harness` that lacks it would make every `GatedFs` read fail
closed.
