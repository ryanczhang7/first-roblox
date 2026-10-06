---
id: HARNESS-023
title: The stray-luau precondition sees a file inside a new directory
slug: the-stray-luau-precondition-sees-a-file
epic: 
type: fix
status: in-review
phase: REVIEW
branch: story/HARNESS-023-the-stray-luau-precondition-sees-a-file
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Two harness suites that read the real tree open with a precondition meant to
guarantee that the counter baselines they pin describe a committed tree:

    stray="$( cd "$REPO_ROOT" && git status --porcelain -- src tests lune | grep -E '\.luau$' || true )"
    assert_eq "the working tree carries no stray .luau files, so the baselines mean what they say" "" "$stray"

**The defect.** Default `git status --porcelain` (untracked mode `normal`)
collapses a new untracked directory to ONE line naming the directory -
`?? src/shared/channel/` - which does not end in `.luau`, so the `grep` drops
it. A new `.luau` file that sits in a NEW directory is therefore never reported
as stray, and the precondition passes on an uncommitted tree whose counts it
claims to vouch for. Found during CHAN-002 GREEN (2026-10-05), where
`src/shared/channel/Presets.luau` was new in a new directory.

**Second, smaller defect in the same line, found while planning.** `|| true`
swallows a failing `git status` as well as an empty `grep`. If git cannot run
(not a repository, missing root), stdout is empty and the precondition reports
"no stray files". A precondition that passes when its instrument did not run is
the needle-cannot-fail case in rules.md.

**PO reproduction (2026-10-06, git 2.55.0.windows.5)**, in a throwaway repo
with `src/shared/A.luau` committed and `src/shared/channel/Presets.luau` new:

    default:   ?? src/shared/channel/
    filtered:  []                              <- the precondition's view: "clean"
    all:       ?? src/shared/channel/Presets.luau   (--untracked-files=all)
    not-a-repo (.git removed), same pipeline:  []   <- also "clean"

**Every call site with this defect** (`grep -rn 'git status' scripts .claude`):

| File | Line | Role |
|---|---|---|
| `.claude/tests/project-counters.test.sh` | 599 | precondition before the baselines |
| `.claude/tests/harness-gate.test.sh` | 184 | precondition: "a clean tree below is one" |
| `.claude/tests/harness-gate.test.sh` | 430 | postcondition after the probe is removed |

All three are fixed (they are byte-identical pipelines, so one helper fixes all
three; leaving two would leave the defect in the suite that wraps the first).
The other `git status` calls were checked and are NOT this defect - see
`## Out of scope`.

**Required gate that would fail if this broke.** The `harness` gate (required,
not slow) runs `project-counters.test.sh`, whose precondition will call the
helper fail-closed: a MISSING or ERRORING helper turns that gate red. A helper
that runs but regresses to the collapsed listing (AC-1) is caught only by the
new suite, which `scripts/selftest.sh` runs - CI's "Harness self-test" step
(`.github/workflows/gates.yml:108`), not a `gates.sh` gate. That is the same
coverage every harness-machinery suite has; adding the new suite to the
`harness` gate is out of scope (it would change a gate and need gate probes).

## Acceptance criteria

The helper is `scripts/stray-luau.sh` (see `## Contract`). "Reported" means its
stdout carries a line naming that file's path.

- **AC-1** (the bug) - Given a git repository whose `src/shared/A.luau` is
  committed, and an untracked `src/shared/channel/Presets.luau` inside the
  untracked directory `src/shared/channel/`, when the stray check runs, then it
  reports `src/shared/channel/Presets.luau` by its file path (not the directory)
  and exits 0. The same holds two directories deep
  (`tests/new/deeper/X.luau`) and when the repository's own config sets
  `status.showUntrackedFiles=no`.
- **AC-2** - Given a committed tree with an untracked `src/shared/B.luau` placed
  directly in the existing directory `src/shared/`, when the stray check runs,
  then it reports `src/shared/B.luau` and exits 0. (Existing behaviour; must
  survive the fix.)
- **AC-3** - Given a repository whose `.luau` files under `src`, `tests` and
  `lune` are all committed and unmodified, when the stray check runs, then it
  prints nothing and exits 0 - including when that tree also holds an untracked
  non-`.luau` file (`src/shared/notes.md`, and a new directory
  `src/newdir/` containing only `readme.txt`), an untracked `.luau` covered by
  `.gitignore`, and an untracked `.luau` outside the three roots
  (`docs/X.luau`). And given a committed `.luau` that is then modified, it is
  reported.
- **AC-4** (fail closed) - Given a directory that is not a git repository, when
  the stray check runs against it, then it exits non-zero and writes a message
  to stderr naming the directory; it never exits 0 with empty output.
- **AC-5** - All three call sites listed in `## Context` use the helper instead
  of their own `git status` pipeline, and each fails its assertion when the
  helper reports a file OR exits non-zero. After the change, no
  `git status --porcelain -- src tests lune` pipeline remains anywhere under
  `.claude/tests/` outside the new suite's own fixture code.

## Contract

**RED may amend any block below, in place, with a reason; GREEN builds what the
amended block says.**

### Where each part lives, and why (the design decision)

The defect sits inside a test file, which is why this needs deciding. The
"production code" is the stray-detection pipeline; the tests are the
preconditions that consume it and a new suite that pins it. Putting the fix
back in the test files would leave nothing for GREEN to do and nothing to watch
fail: `.claude/tests/**` may change only in a commit whose story says
`phase: RED` (check-boundaries 3j), so fix and regression test would land in
the same RED commit, and the assertion would pass on its first run - the
"written against code that already exists" case rules.md says satisfies
nothing.

So the detection is **extracted into a project-owned script under `scripts/`**:

| File | Category (`classify.sh`) | Written in | Why |
|---|---|---|---|
| `.claude/tests/stray-luau.test.sh` (new) | harness | RED | the regression suite; 3j requires a `phase: RED` commit |
| `.claude/tests/project-counters.test.sh` (line 599) | harness | RED | call site switches to the helper; 3j again |
| `.claude/tests/harness-gate.test.sh` (lines 184, 430) | harness | RED | same |
| `scripts/stray-luau.sh` (new) | tooling | GREEN | production code: frozen in RED by the lock, writable in GREEN |

This is the shape law 1 wants: in RED the helper does not exist, so every
fixture case and all three call sites are red; GREEN writes only
`scripts/stray-luau.sh`; no `.claude/tests/**` file changes after the RED
commit. `refresh-harness.sh` replaces only the `scripts/*.sh` upstream ships
("your own scripts and subdirectories untouched"), and upstream ships no
`stray-luau.sh`, so the helper survives a refresh - as do both suites, which
upstream does not ship either. `scripts/lib.sh`-style placement in an UPSTREAM
file was rejected for that reason.

**3j, concretely.** Commit the RED work (all three `.claude/tests` files) while
the story file in that same commit says `phase: RED`: run
`bash scripts/phase.sh set HARNESS-023 RED` first, and do not commit the test
changes after moving to GREEN. The memory note "counter baselines move in RED"
is the same rule. If GREEN or GATES finds a test file needs any change (a
reflow, a needle), return to RED and record it under `## Regressions`.

### `scripts/stray-luau.sh`

    bash scripts/stray-luau.sh [<repo-root>]

- `<repo-root>` defaults to the script's parent directory
  (`$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`). Call sites pass
  `"$REPO_ROOT"` explicitly.
- Runs `git -C "$root" status --porcelain --untracked-files=all -- src tests lune`.
  `--untracked-files=all` is the fix: it lists every untracked FILE and also
  overrides a `status.showUntrackedFiles` config value (AC-1's third case).
- Prints every porcelain line whose path ends in `.luau`, unchanged (`?? path`,
  ` M path`, `A  path`, `R  old -> new.luau`, ...), one per line, to stdout.
  Exit 0 whether or not anything printed - the caller decides what stray means.
- Ignored files are not reported (git's default; AC-3).
- If `git status` exits non-zero, or `<repo-root>` is not a directory: print
  `stray-luau: cannot read git status in <repo-root>` (plus git's own stderr) to
  stderr and exit 2. It must not filter git's failure through a `grep || true`.
  Under `set -o pipefail` a `grep` that matches nothing exits 1; take git's
  status separately (capture output, then filter) rather than piping and
  testing `$?`.
- **On success, stderr is silent.** git can print warnings on a successful run
  (on this Windows checkout `git add` emits `warning: in the working copy of
  ... LF will be replaced by CRLF`), and the call sites merge stderr into
  `$stray` with `2>&1`. So the helper captures git's stderr and prints it only
  on the failure path; a warning on a successful run must not reach the caller
  and turn a clean tree into a "stray" one.
- bash, git, grep/awk only. No python (rules.md, Portability).

### Call sites (AC-5) - the fail-closed shape

Each of the three becomes, in substance:

    stray="$(bash "$REPO_ROOT/scripts/stray-luau.sh" "$REPO_ROOT" 2>&1)"; stray_rc=$?
    assert_eq "the stray-luau check ran (exit 0)" "0" "$stray_rc"
    assert_eq "<the existing message, unchanged>" "" "$stray"

`2>&1` is deliberate: in RED the script is missing, bash prints
`No such file or directory`, and that text lands in `$stray`, so the
precondition is red for a visible reason rather than silently empty. Keep each
existing assertion message verbatim. Adding the `stray_rc` assertion changes
each suite's assertion count; nothing pins those counts (harness-gate's needles
are `[1-9][0-9]* passed, 0 failed` and `[1-9][0-9]* failed`), so that is safe -
RED confirms by grep.

### `.claude/tests/stray-luau.test.sh` (new)

- Sources `_lib.sh`; uses `describe`/`assert_eq`/`assert_contains`/`summary`.
- Builds each fixture with `mktemp -d` + `git init -q` OUTSIDE this checkout,
  commits with `-c user.email=... -c user.name=...` (CI has no identity), and
  removes them in an `EXIT` trap. **Never** writes under the real `src/`: a
  transient `.luau` under `src/` collides with a concurrent typecheck gate run
  and with project-counters' baselines (memory: concurrent-test-and-gate-runs-collide).
- Invokes the helper as `bash "$REPO_ROOT/scripts/stray-luau.sh" "$fixture"`.
- For AC-1's config case, set the fixture's own config
  (`git -C "$fx" config status.showUntrackedFiles no`), not the user's global.
- Needles: assert the exact expected line with an anchored match
  (`grep -cx '?? src/shared/channel/Presets.luau'`, expecting `1`), never a
  floating substring - `?? src/shared/channel/` is a prefix of the right answer
  and of the wrong one. For the "nothing" cases assert the full output is `""`.
- No toolchain needed (bash + git + coreutils), so it runs anywhere selftest
  runs.

### Oracle partition

All five criteria are **mechanical**: git's porcelain format and the exit-code
contract are fixed. Pin exactly; leave nothing open-ended. Nothing is
oracle-free and no number needs calibrating.

### Baselines

Unchanged. The helper is a `.sh`, not a `.luau`; `BASE_FORMAT`, `BASE_LINT`,
`BASE_TYPECHECK` and the narrow counts in `project-counters.test.sh` do not
move. If they appear to, something else changed the tree.

### Test-only dependencies

None.

### Changed exports and their callers

No existing export changes signature. The three pipelines being replaced are
listed in `## Context` and are the complete list (`grep -rn 'git status'
scripts .claude --include=*.sh`, 2026-10-06).

## Deferred verifications

### DV-1 - the regression case pins the flag

- **Condition.** With `--untracked-files=all` removed from
  `scripts/stray-luau.sh`, AC-1's new-directory assertions (and its
  `showUntrackedFiles=no` case) MUST fail, and AC-2/AC-3/AC-4 must stay green.
  With the flag in place, everything is green.
- **Why not RED.** There is no helper in RED to mutate; every case is red
  because the file is missing, which proves nothing about which assertion pins
  the flag.
- **Owner: GATES.** Run via
  `bash scripts/mutate.sh scripts/stray-luau.sh 's/ --untracked-files=all//' -- bash .claude/tests/stray-luau.test.sh`.
- **Result (GATES, 2026-10-06):** `bash scripts/mutate.sh scripts/stray-luau.sh 's/ --untracked-files=all//' -- bash .claude/tests/stray-luau.test.sh` -> `stray-luau: 53 passed, 9 failed`; red: "reports exactly the one file, by its path", "the line '?? src/shared/channel/Presets.luau' appears once", "reports exactly tests/new/deeper/X.luau", "reports the file despite status.showUntrackedFiles=no", "three lines, no more", "'?? src/shared/channel/Presets.luau' once", "'?? lune/jobs/Build.luau' once", and the two modified+new-directory counts. AC-2/3/4/5 green, as the handoff predicted. `restored (verified byte-for-byte ...)`.

### DV-2 - the fail-closed path is pinned

- **Condition.** With the helper's git-failure branch neutralised (exit 0
  instead of 2), AC-4 MUST fail. Exact expression is GREEN's to report, since it
  depends on how the branch is written.
- **Owner: GATES.**
- **Result (GATES, 2026-10-06):** `bash scripts/mutate.sh scripts/stray-luau.sh 's/exit 2/exit 0/' -- bash .claude/tests/stray-luau.test.sh` -> `stray-luau: 60 passed, 2 failed`; red: "exits 2, never 0" and "exits 2" (AC-4, both fixtures). Stderr message still printed, so its `assert_contains` stayed green, as predicted. `restored (verified byte-for-byte ...)`.

### DV-3 - a wrong value, not a missing flag

- **Condition.** With the `.luau` filter widened to every path (e.g. the
  `\.luau$` anchor removed or the filter dropped), AC-3's non-`.luau` cases MUST
  fail.
- **Owner: GATES.**
- **Result (GATES, 2026-10-06):** `bash scripts/mutate.sh scripts/stray-luau.sh '/^printf/s/awk .*/cat/' -- bash .claude/tests/stray-luau.test.sh` (filter dropped) -> `stray-luau: 61 passed, 1 failed`; red: "prints nothing: none of the four distractors is a stray .luau under the three roots" (AC-3). `restored (verified byte-for-byte ...)`. A first attempt with a mis-quoted expression was refused by mutate.sh (`the expression changed nothing`) and ran nothing.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-023` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `REPO_ROOT/scripts/stray-luau.sh` (source), `scripts/lib.sh` (tooling), `scripts/phase.sh` (tooling) (+1 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- PLANNED - `lead-po` - resolved `claude-opus-5-5` (Opus 5.5), per the agent's
  own environment; the dispatch named no override. Matches the plan (`opus`).
- RED - `test-developer` - dispatched with explicit `model: fable`; resolved
  `claude-fable-5-1` (Fable 5.1) per the agent's report. Matches the plan.
  Orchestrator verified: `stray-luau: 28 passed, 34 failed`, every failure the
  missing helper (exit 127, `No such file or directory`).
- GREEN - `feature-developer` - no override; resolved `claude-opus-5-5`
  (Opus 5.5) per the agent's report. Matches the plan. Wrote only
  `scripts/stray-luau.sh`. Orchestrator verified `stray-luau: 62 passed, 0
  failed` and, before leaving GREEN: `frozen: OK — 4 path(s) unchanged since
  the snapshot for HARNESS-023` (the three suites and `_lib.sh`).

**Brief for RED (oracle partition):** every AC is mechanical - pin git's
porcelain lines and the exit codes exactly, with anchored needles. There is no
oracle-free criterion and no number to calibrate. The negative controls that
need the implementation are DV-1..3, owned by GATES; RED names their expected
outcome and declines to run them.

## Out of scope

- **Other `git status` calls in the harness.** Checked, not the same defect:
  - `scripts/gates.sh:190` - tests only whether output is EMPTY (dirty-tree
    note); a collapsed `?? dir/` line is still non-empty, so it is correct.
  - `scripts/ci-local.sh:169` and `scripts/refresh-harness.sh:124` - both drop
    `??` lines on purpose, so untracked collapse cannot matter.
  - `.claude/tests/frozen.test.sh:109` - already passes `--untracked-files=all`.
- **The lint and typecheck gate counters** (`project.conf:350`, `:376`) use
  `git ls-files --cached --others --exclude-standard`, which lists files, not
  directories. Not affected; not touched.
- **Adding `stray-luau.test.sh` to the `harness` gate** or changing any
  `project.conf` gate or evidence line. CI's selftest runs it.
- **Paths needing git quoting** (spaces, non-ASCII), which porcelain v1 prints
  as `"..."` so the line ends in `.luau"`. No Luau module here has such a name;
  `-z` parsing is not this story.
- **Generalising the helper** to other extensions or roots. It answers the one
  question its three callers ask.
- **Any change to the counter baselines or to what project-counters measures.**

## Design notes

Not user-facing.

## Test plan

All in `.claude/tests/stray-luau.test.sh` unless stated. Every fixture is a
throwaway repository under one `mktemp -d` directory outside the checkout
(`src/shared/A.luau`, `tests/T.luau`, `lune/L.luau` committed; `.gitignore`
covers `src/build/`), removed by the EXIT trap. The helper is run with stdout,
stderr and exit status captured separately. Every expected porcelain line is
matched as a whole line and counted (`grep -cxF`); every "nothing" case
compares the full stdout to `""`.

| AC | `describe` block | What it pins |
|---|---|---|
| AC-1 | new .luau inside a NEW directory | stdout is exactly `?? src/shared/channel/Presets.luau`; that line counted once; `?? src/shared/channel/` counted zero; exit 0; stderr `""`. Fixture control: the old pipeline prints `""` here (the defect) |
| AC-1 | two directories deep under tests/ | stdout exactly `?? tests/new/deeper/X.luau`; neither `?? tests/new/` nor `?? tests/new/deeper/` present; exit 0; stderr `""` |
| AC-1 | `status.showUntrackedFiles=no` set with `git -C $fx config` | fixture controls: the config is `--local`, plain `git status` prints nothing; helper still prints exactly `?? src/shared/channel/Presets.luau`, exit 0 |
| AC-2 | new .luau directly in an existing directory | stdout exactly `?? src/shared/B.luau`; exit 0; stderr `""`. Fixture control: the old pipeline already reported this |
| AC-1/AC-2 | three strays at once (existing dir, new dir, new dir under lune/) | exactly 3 lines; each of the three file lines once; no collapsed `?? src/shared/channel/` or `?? lune/jobs/` line |
| AC-3 | committed, unmodified tree | stdout `""`, exit 0, stderr `""` |
| AC-3 | distractors: `src/shared/notes.md`, `src/newdir/readme.txt`, ignored `src/build/Gen.luau`, `docs/X.luau` | fixture controls: git sees all four (`--ignored`), `Gen.luau` is `!!`; helper stdout `""`, exit 0 |
| AC-3 | committed `src/shared/A.luau` modified | stdout exactly ` M src/shared/A.luau`; and with a new-dir file added too, exactly 2 lines, each once, no collapsed line |
| AC-4 | directory that is not a repository | fixture controls: `rev-parse` exits 128, the old pipeline prints `""`; helper exits 2, stdout `""`, stderr contains `stray-luau: cannot read git status in <dir>` |
| AC-4 | root that does not exist | exit 2, stdout `""`, stderr names the path |
| AC-5 | call sites | `project-counters.test.sh` has the exact Contract call line and the `stray_rc` assertion once each; `harness-gate.test.sh` twice each; the three original messages survive verbatim; `grep -lF 'git status --porcelain -- src tests lune' .claude/tests/*.sh` minus this file is empty, and the needle is shown live by matching this file |
| AC-5 | "fails its assertion when the helper exits non-zero" | demonstrated by running the two suites in RED: `project-counters: 39 passed, 2 failed` on the two precondition assertions (see Handoff) |

Out-of-scope items pinned cheaply: a `.luau` outside the three roots and an
ignored `.luau` (both in the AC-3 distractor case). Not pinned: quoted paths,
other extensions, other roots.

## Handoff: RED -> GREEN

**Dispatch.** RED ran on the `test-developer` agent, resolved model
`claude-fable-5-1` (Fable 5.1) per the agent's own environment; the dispatch
prompt named no override. Matches the plan (`fable`).

### Commands

    bash .claude/tests/stray-luau.test.sh                       # seconds; bash + git only
    PATH="$HOME/.rokit/bin:$PATH" bash .claude/tests/project-counters.test.sh   # ~20 s
    PATH="$HOME/.rokit/bin:$PATH" bash .claude/tests/harness-gate.test.sh       # minutes; runs gates.sh --fast --gate harness
    bash scripts/gates.sh --fast

### Failure output in RED (verbatim, trimmed), 2026-10-06, this worktree

`bash .claude/tests/stray-luau.test.sh` -> `stray-luau: 28 passed, 34 failed`,
exit 1. Every failure is the helper being absent (bash exit 127), which is the
first thing the story requires:

      the script under test exists
        FAIL scripts/stray-luau.sh is present
             no such file: /d/first-roblox/.claude/worktrees/vigilant-engelbart-e5ebd4/scripts/stray-luau.sh

      AC-1: a new .luau inside a NEW directory is reported by its file path, not collapsed to the directory
        FAIL exit 0 when a stray file is found (the caller decides what stray means)
             expected: 0
             actual:   127
        FAIL reports exactly the one file, by its path
             expected: ?? src/shared/channel/Presets.luau
             actual:
        FAIL the line '?? src/shared/channel/Presets.luau' appears once
             expected: 1
             actual:   0
        FAIL stderr is silent on success
             expected:
             actual:   bash: /d/first-roblox/.claude/worktrees/vigilant-engelbart-e5ebd4/scripts/stray-luau.sh: No such file or directory
      ...
      AC-4: a directory that is not a git repository fails closed
        FAIL exits 2, never 0
             expected: 2
             actual:   127
        FAIL stderr names the directory
             expected to contain: stray-luau: cannot read git status in /tmp/tmp.1ynElrj1gE/not-a-repo
             actual:               bash: /d/first-roblox/.claude/worktrees/vigilant-engelbart-e5ebd4/scripts/stray-luau.sh: No such file or directory
      ...
      AC-5: the three call sites use the helper, fail-closed, and the old pipeline is gone from .claude/tests

    stray-luau: 28 passed, 34 failed

The 28 passes are: the fixture controls (old pipeline prints nothing for the
new-directory cases and for the non-repo; `--local` config set; distractors
visible to git; `rev-parse` exits 128), the `count_line ... == 0` absences
(trivially 0 on empty output - they bite only once output exists, which is
why each sits beside a positive `== 1` or a full-output `assert_eq`), and the
AC-5 call-site assertions (see "green on arrival" below).

`bash .claude/tests/project-counters.test.sh` -> `project-counters: 39 passed,
2 failed`, exit 1. The two are the precondition, red for the visible reason the
Contract wanted:

        FAIL the stray-luau check ran (exit 0)
             expected: 0
             actual:   127
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
             expected:
             actual:   bash: /d/first-roblox/.claude/worktrees/vigilant-engelbart-e5ebd4/scripts/stray-luau.sh: No such file or directory

Every other project-counters assertion (39) is unchanged and green, so the
baselines did not move (Contract, "Baselines").

`bash .claude/tests/harness-gate.test.sh` -> `harness-gate: 25 passed, 6
failed`, exit 1 (local run, ~6 min on this Windows machine). All six are
downstream of the missing helper: its own two precondition assertions, the two
AC-4 "gate passes on a clean tree" assertions (the `harness` gate is red
because project-counters' precondition is), and its two postcondition
assertions:

        FAIL the stray-luau check ran (exit 0)
        FAIL the working tree carries no stray .luau files, so 'a clean tree' below is one
        FAIL the gate command exits 0 on the unmodified tree
             expected exit 0; got 1
             ...
             project-counters: 39 passed, 2 failed
        FAIL and its output carries project-counters' own summary line, all passed
             no line matching /^project-counters: [1-9][0-9]* passed, 0 failed$/
        FAIL the stray-luau check ran (exit 0)
        FAIL the probe is gone and the tree is clean again
    harness-gate: 25 passed, 6 failed

The 25 that pass include every AC-2 "with one .luau added under src/ the gate
fails and names the suite" case - which is as it should be, since the gate
fails either way in RED.

`bash scripts/gates.sh --fast` -> exit 1, the intended shape: every
non-test gate green, the one gate that runs the changed suite red on the new
precondition and nothing else (no timeout, no config error, no lint on the
new file - it is a `.sh` under `.claude/tests`, outside the stylua/selene
targets):

    --- gate summary ---
    PASS         format (0s, observed 182)
    PASS         lint (0s, observed 182, floor 1)
    PASS         typecheck (2s, observed 30)
    PASS         unit (105s, observed 1172, floor 507)
    UNCONFIGURED coverage
    PASS         build (0s, observed 117327)
    FAIL         harness (13s, exit 1) -> .claude/state/gate-logs/harness.log

    --fast skipped: integration mutation
    1 required gate(s) failed.

The harness gate's log ends in the project-counters precondition failure
quoted above. Baselines 182 / 182 / 30 did not move. The `harness` gate is
13 s here; no timeout in any touched file (the new suite has none, and the
call-site edits add one `bash` invocation each).

Timings above are all from a local run; nothing was measured on CI.

### Green on arrival, and what earns it

The AC-5 block (10 assertions) passes in RED because this phase made the
call-site change itself - 3j puts both in the same RED commit. Earned by running
the same anchored needles against the **pre-change** files at HEAD:

    $ for f in project-counters.test.sh harness-gate.test.sh; do
        git show "HEAD:.claude/tests/$f" | grep -cxF -- 'stray="$(bash "$REPO_ROOT/scripts/stray-luau.sh" "$REPO_ROOT" 2>&1)"; stray_rc=$?'
        git show "HEAD:.claude/tests/$f" | grep -cF  -- 'git status --porcelain -- src tests lune'
      done
    project-counters.test.sh CALL lines at HEAD: 0      (suite expects 1)
    project-counters.test.sh old pipeline at HEAD: 1    (suite expects 0 files)
    harness-gate.test.sh CALL lines at HEAD: 0          (suite expects 2)
    harness-gate.test.sh old pipeline at HEAD: 2        (suite expects 0 files)

So against HEAD, "calls the helper the fail-closed way" fails (0 != 1, 0 != 2)
and "no other suite still runs the old pipeline" fails (two files listed). The
"needle is live" assertion shows the leftover grep matches this suite's own
fixture helper, so an empty result cannot come from a dead needle.

The fixture controls (labelled `fixture control:`) are also green in RED by
design: they pin the FIXTURE, not the helper - that the old pipeline really
reports nothing for the new-directory and not-a-repo cases on this git
(2.55.0.windows.5), which is what makes DV-1 and DV-2 discriminating.

### Files touched

- `.claude/tests/stray-luau.test.sh` - new (AC-1..AC-5)
- `.claude/tests/project-counters.test.sh` - line ~599: the one precondition
  replaced with the Contract's fail-closed shape (AC-5); message verbatim
- `.claude/tests/harness-gate.test.sh` - lines ~184 and ~430: same (AC-5);
  both messages verbatim. The postcondition's `assert_eq` now reads `$stray`
  rather than an inline `$( ... )`, which is the Contract's shape.
- `docs/backlog/stories/HARNESS-023.md` - `## Test plan`, this section
- Nothing under `scripts/`, `src/`, `.claude/harness/`. No test dependency.

`grep -rn 'git status --porcelain -- src tests lune' .claude scripts` now
matches only `stray-luau.test.sh` (its header comment, its `old_pipeline`
fixture helper, and the AC-5 needle). Nothing pins the two suites' assertion
counts: harness-gate's needles are `[1-9][0-9]* passed, 0 failed` /
`[1-9][0-9]* failed`, and its two literal `40 passed` / `0 passed` strings are
instrument self-tests on constants, not counts of a real run. The "Changed
exports and their callers" list in the Contract was checked against the tree:
the three pipelines in `## Context` were the only ones, and no other export
changed.

### The shape the tests pin (facts, not suggestions)

- Path: `scripts/stray-luau.sh`, invoked as `bash "$REPO_ROOT/scripts/stray-luau.sh" "<root>"`.
  Always called with an explicit root; the no-argument default is NOT tested.
- `<root>` is the path the caller passed, used verbatim in the error message:
  `stray-luau: cannot read git status in <root>` must appear on **stderr** for
  (a) a directory that is not inside any repository and (b) a path that does not
  exist. In both cases exit **2** and stdout **empty**. git's own `fatal:` may
  accompany it on stderr; the test uses `assert_contains`.
- Success: exit **0** whether or not anything is printed; stdout is the porcelain
  lines whose path ends in `.luau`, **unchanged** (`?? src/shared/B.luau`,
  ` M src/shared/A.luau` with the leading space), one per line, no trailing
  blank line beyond what `$(...)` strips, no header, no summary. **stderr empty**
  on every success run - the test captures stderr to a file separately from
  stdout, so a warning on stderr is a failure even though the call sites merge it.
- Must list untracked FILES inside untracked directories and must override a
  repo-local `status.showUntrackedFiles=no` (i.e. `--untracked-files=all` on
  the command line).
- Must not report: ignored `.luau` (`.gitignore` of the fixture, not
  `--ignored`), non-`.luau` files, `.luau` outside `src tests lune`
  (`docs/X.luau`).
- Order of lines is git's (sorted by path); the multi-stray cases count lines
  rather than pin order, so sort is not constrained.
- Not constrained: implementation language inside bash/git/grep/awk, how git's
  status and output are captured, the no-arg default root, quoted paths.

### Deferred verifications - declined in RED, expected outcomes

None of DV-1..3 can run in RED: there is no `scripts/stray-luau.sh` to mutate,
and every assertion below is already red for that reason. Owner stays GATES.

| DV | Mutation | Expected red (and only these) | Expected to stay green |
|---|---|---|---|
| DV-1 | `s/ --untracked-files=all//` | AC-1 new-dir: "reports exactly the one file" (actual `""`), "'...Presets.luau' appears once" (0); AC-1 deeper: "reports exactly tests/new/deeper/X.luau"; AC-1 config: "reports the file despite status.showUntrackedFiles=no"; AC-1/AC-2 together: "three lines" (actual 1), the Presets and Build `once` lines (0); AC-3 modified+newdir: "exactly two lines" (1) and the Presets `once` line. The collapsed-directory `== 0` lines stay green because `?? src/shared/channel/` does not end in `.luau` and the filter drops it - they would go red only if the filter were ALSO widened (DV-3) | every AC-2, AC-3-clean, AC-3-distractor, AC-3-modified-only, AC-4 and AC-5 assertion; all exit-0 and stderr-silent lines |
| DV-2 | neutralise the git-failure branch to exit 0 (GREEN names the exact expression) | AC-4 non-repo: "exits 2, never 0" (actual 0); AC-4 missing root: "exits 2". The stderr `assert_contains` lines go red too if the message is dropped with the exit code; stdout-empty lines may stay green | everything in AC-1..3, AC-5 |
| DV-3 | drop the `\.luau$` filter / widen to every path | AC-3 distractors: "prints nothing: none of the four distractors..." (actual lists `?? src/newdir/readme.txt` and `?? src/shared/notes.md`; `docs/X.luau` and the ignored file still absent because of the pathspec and `.gitignore`); AC-1/AC-2 "three lines" and AC-3 "exactly two lines" stay green (no non-.luau distractors in those fixtures) | AC-1, AC-2, AC-4, AC-5, AC-3-clean, AC-3-modified-only |

If DV-1 turns ANY AC-4 or AC-3 assertion red, or DV-3 leaves the distractor
case green, the suite is not pinning what this table says and the story comes
back to RED.

### Notes for GREEN

- The `2>&1` at the call sites merges the helper's stderr into `$stray`. On this
  Windows checkout `git add` emits CRLF warnings on stderr; `git status` did not
  in RED's probing, but the Contract's rule stands: capture git's stderr and
  emit it only on the failure path.
- Under `set -o pipefail`, `grep` matching nothing exits 1; take git's exit
  status separately from the filter (the Contract says so; the AC-3 clean case
  is exactly where a naive pipeline would turn exit 0 into exit 1).
- The missing-root case: `git -C <missing>` fails with its own message; the
  helper's `cannot read git status in <root>` line must still be printed (the
  test `assert_contains` it) and the exit must be 2, not git's 128 or bash's 1.
- Snapshot the frozen tests before starting:
  `bash scripts/frozen.sh snapshot .claude/tests/stray-luau.test.sh .claude/tests/project-counters.test.sh .claude/tests/harness-gate.test.sh`.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-10-06T15:49:18Z
    commit: 1c6aa59 (working tree had uncommitted changes)
    tree:   048f9aa816e02a2e1b05f60432f3df38fd1f970b
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 182)
    PASS         lint (0s, observed 182, floor 1)
    PASS         typecheck (2s, observed 30)
    PASS         unit (104s, observed 1172, floor 507)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 117327)
    PASS         harness (13s, observed 41)
    UNCONFIGURED mutation

## Notes

- **Commands.** New suite: `bash .claude/tests/stray-luau.test.sh` (seconds;
  bash + git). Call sites: `bash .claude/tests/project-counters.test.sh` (needs
  the toolchain on PATH; ~20 s) and `bash .claude/tests/harness-gate.test.sh`
  (minutes on Windows - it runs `gates.sh --fast --gate harness`). Do not run
  two selftest or gate runs at once (memory: selftest-is-slow-and-collides).
- **3j, restated for every phase.** All `.claude/tests/**` edits land in a
  commit whose story file says `phase: RED`. GREEN and GATES write only
  `scripts/stray-luau.sh` (and docs). A needed test edit after RED is a return
  to RED with a `## Regressions` entry, never an edit in place.
- **Expected RED failure.** `stray-luau: ... No such file or directory` for
  every fixture case, and the three call-site preconditions red with that text
  in `$stray` and a non-zero `stray_rc`. The `harness` gate is therefore red
  through RED; that is the design, not a fault.
- **Planning dispatch.** PLANNED was written by the `lead-po` agent, resolved
  model `claude-opus-5-5` (Opus 5.5) as reported by the agent's own
  environment; no override was given in the dispatch prompt.
- **GATES: selftest caught a rule the story missed (2026-10-06).** The first
  full `bash scripts/selftest.sh` failed `lib: 174 passed, 1 failed` -
  `FAIL no shipped script depends on $TMPDIR or mktemp` - because GREEN's
  helper used `mktemp` for a stderr capture file. The Contract did not mention
  that rule (`.claude/tests/lib.test.sh:313`). The feature-developer (resolved
  `claude-opus-5-5`, no override) replaced the capture with: git's stderr
  discarded on the first run, and on failure the same read-only `git status`
  re-run with stderr shown. Source-only fix in GATES; no test changed
  (`frozen: OK — 4 path(s) unchanged`). `selftest.sh lib` -> `lib: 175 passed,
  0 failed`. DV-1..3 were re-run against the fixed helper with identical
  results (53/9, 60/2, 61/1; each `restored (verified byte-for-byte ...)`).
- **Leaving GATES (2026-10-06).** `bash scripts/frozen.sh verify` ->
  `frozen: OK — 4 path(s) unchanged since the snapshot for HARNESS-023`.
  Full `bash scripts/gates.sh` -> `All required gates passed (6 ran, 3
  unconfigured, 0 known).` Full `bash scripts/selftest.sh` (run after gates,
  never concurrently) -> `22 harness suite(s) passed.`
