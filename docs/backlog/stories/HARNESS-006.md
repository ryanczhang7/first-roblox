---
id: HARNESS-006
title: A gate's file count is what the tool read, not a list beside it
slug: a-gate-s-file-count-is-what-the-tool-rea
epic: 
type: chore
status: done
phase: DONE
branch: story/HARNESS-006-a-gate-s-file-count-is-what-the-tool-rea
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Found while closing `EPIC-00`, whose whole reason for existing is `stack.md` §2:
**every tool in this ecosystem prints nothing when it is happy, and exits 0 just
as quietly when pointed at a directory that does not exist.** `evidence` and
`floor` lines are the answer to that. Three of them do not work.

The `format`, `lint` and `typecheck` gates each end with a counter of the shape

    n=$(git ls-files -- src tests lune | ... *.luau ... | wc -l) && echo "stylua over $n files"

and the `evidence` regex asserts that `n` is at least 1. The counter is a
**second, independent enumeration** that happens to sit next to the tool. It does
not observe the tool, and it shares nothing with it but a path list typed twice.
So it is wrong in two directions at once:

**1. It does not move when the tool's target narrows** — the failure `floor`
exists to catch. Measured on this repository today:

    $ stylua --check src && n=$(git ls-files -- src tests lune | ...) && echo "stylua over $n files"
    stylua over 38 files

`stylua` read 7 files. The gate reported 38, matched its evidence regex, cleared
its floor and exited 0. Dropping `tests` and `lune` from a lint target is exactly
*"a lint target narrowed to one directory"* — named in `project.conf`'s own
comments as a thing `floor` catches — and no floor on this stack can catch it,
because the number is not derived from what the tool was asked to read.

**2. It under-reports a story's own new files until they are committed.**
`git ls-files` lists *tracked* files; `stylua` and `selene` walk the directory and
read untracked ones too. `ROUND-005` recorded `observed 34` locally and 38 on CI,
for four test files that were on disk and read in both runs. `ROUND-004` showed
30 against 34, for the same reason. The lag is harmless against today's floor of
1 and would silently fail a gate the moment anyone set a floor near the real
count — which is the one thing a floor is for.

Neither symptom is a wrong number to correct. The counter is measuring the wrong
thing, and the number it prints has never been the number of files the tool read.

**Which required gate would fail if this story's artifact broke:** `lint`.
`format` is optional on this stack and `typecheck` is required, but `lint` is the
gate whose counter is hardest to derive (see the Contract) and the one whose
regression would be quietest.

## Acceptance criteria

- **AC-1** — Given the `format` gate, when it is run with its target narrowed to
  `src` alone, then the count it reports is the number of files `stylua` actually
  read (**7** on this tree), not the number in a list beside it (**38**).
  *Control:* today's command reports 38 and **must** fail this. A test that only
  asserts "the count is at least 1" cannot tell the two apart.
- **AC-2** — Given the `format` gate on the unnarrowed tree, when a `.luau` file
  exists on disk and is **not yet tracked by git**, then it is included in the
  count.
  *Control:* a counter built on `git ls-files` alone omits it and **must** fail
  this. This is the `ROUND-005` symptom, reproduced as a test rather than as an
  anecdote.
- **AC-3** — Given the `lint` gate, when it is run with its target narrowed to
  `src` alone, then the count it reports moves with the target.
  *Semantics:* `selene` has no per-file output to count (see the Contract), so
  the count stays derived — but from the **same** path list the tool is handed,
  not from a second copy of it. The two cannot disagree if there is only one.
- **AC-4** — Given the `lint` gate, when an untracked-but-not-ignored `.luau`
  file exists on disk, then it is counted.
- **AC-5** — Given the `typecheck` gate, when its target narrows, then its count
  moves with it, by the same rule as AC-3.
- **AC-6** — Given a `.luau` file that `.gitignore` covers, when any of the three
  gates runs, then it is **not** counted.
  *Semantics:* ignored means generated, not authored (`rules.md`). A counter that
  swept in build output would inflate every gate on this stack and would do it
  invisibly, which is this story's own defect pointing the other way.
- **AC-7** — Given all three gates on the unmodified tree, when they run, then
  each reports the same count as `bash scripts/gates.sh` reported before this
  story: `format` 38, `lint` 38, `typecheck` 7.
  *Semantics:* the fix corrects what is measured, not the measurement. A change
  that moved the baseline would mean one of the two numbers was wrong in a way
  this story has not explained, and that is a finding, not a pass.

## Contract

Changes `.claude/harness/project.conf` only — the `format`, `lint` and
`typecheck` gate commands and, if the shape of the output changes, their
`evidence` regexes. No script under `scripts/` changes. No `floor` moves.

### What each tool can actually report, measured rather than assumed

All three were run on this tree before the story was written, so RED starts from
facts:

| Tool | Can it report the files it read? | Measured |
|---|---|---|
| `stylua` | **Yes.** `--check -v` prints `debug: formatted <path> in <time>` per file, on stderr | `stylua --check -v src tests lune 2>&1 \| grep -c '^debug: formatted '` → **38**; over `src` alone → **7** |
| `selene` | **No.** `--display-style Json2` emits only `{"type":"Summary","errors":0,"warnings":0,"parse_errors":0}` — diagnostics per finding, nothing per file | no per-file line exists to count |
| `luau-lsp analyze` | **No** per-file line in `analyze`'s output; `--timetrace` writes a `trace.json` rather than printing | nothing to count on stdout |

So `format` gets a **true** counter and the other two cannot. That asymmetry is
the Contract, not a compromise to be papered over.

### The three commands

**`format` — count the tool's own output.**

    stylua --check -v src tests lune 2>&1 | tee /dev/stderr | grep -c '^debug: formatted '

or whatever shape RED finds keeps the exit status of `stylua` rather than of
`grep` — `set -o pipefail` is NOT in effect inside a `project.conf` command, and
a pipeline's status is its last element's, so a naive pipe turns a formatting
failure into a pass. **That is the trap in this story** and it is worse than the
bug being fixed: it would make the gate green on unformatted code. RED writes a
test for it: AC-1's narrowing test proves the count is right; a separate case
must prove an unformatted file still FAILS the gate.

> **Amended in RED, 2026-09-16 - one factual correction; the decision stands.**
>
> *"`set -o pipefail` is NOT in effect inside a `project.conf` command"* is
> **wrong**. It is in effect. `scripts/gates.sh` line 41 is `set -uo pipefail`
> and line 410 runs each gate as `( cd "$ROOT/$cwd" && eval "$cmd" ) 2>&1 | tee
> "$log"` - a subshell, which inherits shell options. `project.conf`'s own
> BOOT-001 header says the same thing from the other side: *"gates.sh runs with
> `set -o pipefail`, so on a tree with no .luau files grep exits 1, the whole
> `n=$(...)` assignment exits 1, and THE COUNT LINE IS NEVER PRINTED."*
>
> Two consequences, and the requirement is unchanged by either:
>
> 1. A naive pipe does **not** silently pass under `gates.sh` today - it fails,
>    because `pipefail` rescues it. It would pass under any other runner
>    (`bash -c`, `doctor.sh`, a human at a prompt). A gate whose correctness is
>    borrowed from the runner's shell options is one refactor of `gates.sh` away
>    from the exact failure this Contract names, so the requirement stands and
>    RED pins it **twice**: once under `pipefail`, as `gates.sh` runs it, and
>    once without - which is the assertion that discriminates (probe 5).
> 2. The *live* hazard in the suggested `format` command is the other end:
>    **`grep -c` exits 1 when it counts nothing.** Under `pipefail` a target with
>    no `.luau` files then produces an opaque `exit 1` instead of the diagnosis
>    BOOT-001 designed - *"ran but produced no evidence of work"*. RED pins that
>    as AC-1's empty boundary: exit 0, and no evidence match. See `## Handoff`,
>    finding 2, for the shapes that satisfy it.

**`lint` and `typecheck` — one path list, named once.** Assign the target to a
shell variable and hand the same variable to both the tool and the counter, so
narrowing one narrows the other by construction:

    T="src tests lune"; selene $T && n=$(git ls-files --cached --others --exclude-standard -- $T | ...) && echo "selene over $n files"

Two things changed from today's line, and both are load-bearing:

- `--cached --others --exclude-standard` instead of bare `git ls-files`. Tracked
  **and** untracked-but-not-ignored, which is what `selene` walks. Measured on
  this tree: **38**, matching the tool, where bare `git ls-files` gives 38 only
  because `ROUND-005` has since been committed.
- The target lives in `$T`, referenced twice, never typed twice.

`typecheck`'s target is `src` alone and its `--ignore='Packages/**'` stays as it
is.

### The oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-3, AC-5 | **Mechanical** | The narrowed and unnarrowed counts are measured above. Pin them. |
| AC-2, AC-4, AC-6 | **Mechanical, with controls** | Both controls are named in the criteria. Create the untracked and the ignored file inside the test and remove them; do not depend on a file the repository happens to have. |
| AC-7 | **Settled** | 38 / 38 / 7, read out of this story. Do not re-derive them — re-deriving with the new command is what AC-7 exists to detect. |

### Where the tests live

`.claude/tests/gates.test.sh` is the existing suite for `gates.sh` behaviour and
`.claude/tests/profiles.test.sh` for the stack profiles. A counter is a property
of *this project's* `project.conf` rather than of `gates.sh`, so RED decides
between extending `gates.test.sh` and adding a suite beside it — and says which,
and why, in `## Test plan`. `scripts/selftest.sh` must discover it either way.

**Test-only dependencies:** none. Bash, awk and coreutils, per `rules.md`
portability. Do not reach for python.

### The phase lock enforces nothing on this story, and that is the risk

Checked before dispatch rather than discovered mid-cycle:

    $ bash scripts/classify.sh .claude/harness/project.conf .claude/tests/gates.test.sh
    harness	.claude/harness/project.conf
    harness	.claude/tests/gates.test.sh

`harness` is writable in **every** phase. So the artifact this story fixes and
the tests that pin it are both writable in RED, in GREEN and in GATES, and
nothing mechanical stops RED from writing the fix or GREEN from rewriting a test.
This is the *role* dimension of `rules.md` — *"nothing checks which agent wrote a
file"* — with the *phase* dimension absent too.

Two consequences, both to be stated in the dispatches:

1. **The RED→GREEN discipline here is honoured, not enforced.** RED writes tests
   that fail against today's `project.conf` and does not touch `project.conf`.
   GREEN changes `project.conf` and does not touch a test. The lock will not
   catch either of them; the orchestrator reads the diff at each boundary and is
   the only check there is.
2. **`check-boundaries.sh`'s "source changes accompanied by test changes" will
   not fire**, because there are no `source`-classified changes. Its silence here
   is not evidence of anything, and must not be reported as though it were.

There is no `## Scaffold inventory` for the same reason: nothing is written under
SCAFFOLD, and no production file under `src/` changes. This is a `chore` that
touches configuration and tests only.

### No signature changes

Nothing exports anything. There are no callers to grep.

## Deferred verifications

<!-- Nothing is deferred. Every control this story names is producible in RED:
     the gate commands already exist, so a control is a command line RED can run
     against today's project.conf and watch report the wrong number. That is the
     unusual luxury of a story that fixes a measurement rather than adding a
     behaviour - the "implementation" is already there and already wrong, so RED
     can observe the defect rather than predict it. The consequence is the one
     rules.md names: every test here is written against code that exists and
     will pass on its first run, so EVERY assertion needs earning by mutation
     through scripts/mutate.sh, with the output pasted into ## Regressions. -->

## Model guidance

**Resolved model of every dispatch, by name:**

| Phase | Agent | Declared | Resolved in this session |
|---|---|---|---|
| RED (and the probe re-run) | `test-developer` | `model: opus` | **Opus 5**, no override |
| GREEN | `feature-developer` | `model: opus` | **Opus 5** (`claude-opus-5`), no override |

The criterion to brief carefully is the **pipefail trap** in the Contract's
`format` command. A gate that counts its tool's output through a pipe takes the
pipe's exit status, and the obvious implementation makes `format` pass on
unformatted code. The dispatch must say: *prove the gate still fails on a badly
formatted file*, as its own case, not as a corollary of the counting tests.

The second is that this story's tests all run against an implementation that
already exists. There is no ordinary RED here. Say so, and say that every
assertion is earned by `bash scripts/mutate.sh` — one mutation, one run, one
revert, output pasted.

## Out of scope

- **`floor` values.** None moves. `unit` stays at 175 and `lint` at 1. Whether a
  floor near the real count is now safe to set is a judgement for the story that
  sets one, and it is a different argument from this one.
- **The `build` gate.** Its evidence is a byte count of the artefact it produced,
  which is already a measurement of the tool's own output and has neither defect.
- **The `unit` gate.** `lune run test` prints `N passed, M failed` — its own
  count, from the runner. It is the example the other three should have followed.
- **`coverage`, `integration`, `mutation`.** Unconfigured on this stack;
  `EPIC-00` records why and nothing here changes it.
- **Propagating the fix to `.claude/skills/stack-profiles/reference/`.** The
  `roblox-luau` profile carries the same counter shape and other projects will
  copy it. That is a real follow-up and it is deliberately not bundled: a change
  to a shared profile is judged by the harness's own selftest, not by this
  project's gates, and mixing the two puts a change nothing here can verify into
  a story whose whole point is verified measurement. File it when this lands.
- **macOS verification of anything.** Unrelated, still open, recorded in
  `EPIC-00`.


---

## PO decisions at PLANNED -> RED

### 1. The required gate, and the part of it `lint` cannot cover

The `## Context` names `lint`, and that is right but incomplete. This story's
artifact **is** a gate counter, so "which required gate fails if it breaks"
splits in two and both halves have to be named or the answer is comfortable
rather than true:

- **A counter that stops producing a number fails `lint`, loudly.** The evidence
  line is `selene over [1-9][0-9]* files`; a counter that prints nothing, or
  `over 0 files`, fails the regex and the required `lint` gate FAILS with *"ran
  but produced no evidence of work"*. Same for `format` (optional) and
  `typecheck` (required).
- **A counter that produces a plausible but wrong number fails nothing.** That is
  the entire defect this story exists to fix, so by construction no gate in
  `project.conf` can be the guard for it. The guard is this story's own tests
  under `.claude/tests/`.

**Those tests run in CI's required `gates` job**, checked rather than assumed:

    $ grep -nE '^\s+- name:|^\s+run:' .github/workflows/gates.yml
    91:      - name: Harness self-test
    92:        run: bash scripts/selftest.sh
    ...
    103:      - name: Run gates
    104:        run: bash scripts/gates.sh

`scripts/selftest.sh` runs *before* `gates.sh`, inside the same required job, so
a failing harness test fails the required check even though it is not a gate in
`project.conf`. `required_gates` therefore stays empty: there is no optional gate
to promote, and adding a `selftest` gate to `project.conf` would duplicate a CI
step and change `ci-local.test.sh`'s derived step list — scope this story does not
have, and recorded in `## Out of scope` rather than taken.

**Consequence RED must know:** the loop for this story is
`bash scripts/selftest.sh`, not `bash scripts/gates.sh`. `gates.sh --fast` is
still run at the end of RED and GREEN — the Contract changes three gate commands,
so whether those commands still *run* is exactly what `--fast` answers — but it
is not where this story's assertions live.

### 2. No signature changes, so the caller list is empty

Nothing exports anything. `project.conf` is read by `scripts/gates.sh` and
`scripts/doctor.sh` through the parser in `.claude/hooks/lib.sh`; this story
changes the *content* of three `gate |` lines and possibly three `evidence |`
lines, not the file's format, so no parser changes and no caller does. Confirmed:
the Contract adds no field and removes none.

### 3. The Contract is pinned as written, with one clarification

`## Contract` was written with the tool behaviour measured first — `stylua -v` at
38 and 7, `selene --display-style Json2` with no per-file line, `luau-lsp analyze`
with none — so RED is not asked to discover any of that. It stands unamended,
with one thing made explicit that the Contract implies:

**The `format` command's exit status must be `stylua`'s, and RED tests that
directly.** The Contract names the trap; this pins the assertion. A case must
exist in which a badly formatted file is on disk and the `format` gate FAILS.
Without it the story can ship a gate that counts beautifully and passes on
unformatted code, which is strictly worse than the bug being fixed.

### 4. The phase lock enforces nothing here — restated because it is the risk

`## Contract` has the classification output. Both `.claude/harness/project.conf`
and `.claude/tests/*.test.sh` are `harness`, writable in every phase. The
orchestrator reading the diff at each boundary is the only thing separating RED
from GREEN on this story, so both dispatches carry it and both boundaries get a
`git diff` read rather than a report.

### 5. AC-7's baselines are settled, and are re-measured now so the number is
this branch's rather than a memory

    $ bash scripts/gates.sh --fast
    PASS  format (observed 38)   PASS  lint (observed 38, floor 1)
    PASS  typecheck (observed 7)

38 / 38 / 7, on a clean tree at the branch point. AC-7 says these must not move.
RED reads them out of here; it does not re-derive them with the new command,
because re-deriving is what AC-7 exists to detect.

### 6. Toolchain

`lune`, `rojo`, `selene`, `stylua` and `luau-lsp` resolve under `~/.rokit/bin`.
Every dispatch carries `export PATH="$HOME/.rokit/bin:$PATH"` so that a subagent
inheriting a stale shell does not read `command not found` as a broken gate.

---


## PO ruling at RED -> GREEN

**RED is accepted.** Every number below was re-run by the orchestrator.

**The suite.** `bash scripts/selftest.sh` → **15 suites, 1 FAILED in 561 s**;
`project-counters: 30 passed, 10 failed`, and the other 14 suites `ok`. **No
pre-existing harness suite went red.** The ten failures, verbatim:

    FAIL the format gate names 'src tests lune' exactly once
    FAIL the lint gate names 'src tests lune' exactly once
    FAIL the typecheck gate names 'src' exactly once
    FAIL narrowing the format target to src reports 7, not 38
    FAIL does not report a count it did not read
    FAIL narrowing the lint target to src reports 7, not 38
    FAIL narrowing the typecheck target to src/shared reports 5, not 7
    FAIL AC-2: format counts the untracked file (38 -> 39)
    FAIL AC-4: lint counts the untracked file (38 -> 39)
    FAIL typecheck counts the untracked file (7 -> 8)

**RED wrote no implementation.** `git diff -- .claude/harness/project.conf` and
`git diff -- .gitignore` are both empty; `git status --porcelain` is the story
plus the one new suite and nothing else. That matters more here than on an
ordinary story, because PO decision 4 established that the phase lock permits
RED to write `project.conf` — the separation is honoured, not enforced, and this
is the check that it was.

**Admissibility.** `bash scripts/gates.sh --fast` on a quiet tree:

    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (2s, observed 7)
    PASS         unit (5s, observed 175, floor 175)
    UNCONFIGURED coverage
    PASS         build (0s, observed 20721)

38 / 38 / 7 — the AC-7 baselines, unmoved. Green is the correct shape for RED on
*this* story: PO decision 1 established that no gate in `project.conf` can guard
a plausible-but-wrong count, so `--fast` answers only whether the three commands
still run. `selftest.sh` is the red one, and it is red.

### The three Contract corrections, reproduced before they were accepted

RED reported that the `## Contract` was wrong on three points and amended it in
place, which the Contract permits. A subagent saying the contract is wrong is
also what a subagent says when it wants to stop failing, so all three were
re-derived by the orchestrator with its own constructions rather than by
re-running RED's code.

**1. `pipefail` IS in effect inside a gate command. The Contract was wrong.**

    $ bash -c 'set -uo pipefail; cmd="(exit 7) | cat"; ( eval "$cmd" ); echo "with pipefail rc=$?"'
    with pipefail rc=7
    $ bash -c 'set -uo;          cmd="(exit 7) | cat"; ( eval "$cmd" ); echo "without pipefail rc=$?"'
    without pipefail rc=0

`gates.sh:41` is `set -uo pipefail` and `gates.sh:410` runs the gate as
`( cd "$ROOT/$cwd" && eval "$cmd" )` — a subshell inherits shell options.
**This weakens the Contract's own warning:** I wrote that a naive pipe would make
`format` pass on unformatted code. Under pipefail it would not; `stylua`'s
non-zero status propagates and the gate fails. The *decision* still stands and
RED kept it — the command must carry `stylua`'s status on its own, because a gate
whose correctness is borrowed from the runner's shell options breaks the moment
`doctor.sh`, `bash -c` or a person runs it — but it stands for a weaker reason
than the one I gave.

**2. `grep -c` exits 1 when it counts nothing**, which under pipefail turns an
empty target into an opaque failure rather than BOOT-001's *"ran but produced no
evidence of work"*:

    $ bash -c 'set -uo pipefail; ( eval "printf %s\\n hello | grep -c zzz" ); echo "rc=$?"'
    0
    rc=1

A real hazard the Contract created and did not name. RED pinned both halves.

**3. The Contract's `T="src tests lune"; selene $T` shape breaks `doctor.sh`.**

    $ printf '%s' 'T="src tests lune"; selene $T && n=$(git ls-files)' | awk '{print $1}'
    T="src

`doctor.sh:74` is `exe=$(printf '%s' "$cmd" | awk '{print $1}')` followed by
`command -v`, so that shape makes doctor report a permanently MISSING tool called
`T="src`. Nothing else in the repository would have noticed, because doctor is
not a gate. **The Contract's suggested shape is withdrawn**; GREEN picks any shape
that keeps the first token a real executable and names the target once.

### One measurement of my own, stronger than RED claimed

RED reported the two file *counts* agree at 38. The orchestrator compared the two
*sets*:

    $ stylua --check -v src tests lune 2>&1 | sed -n 's/^debug: formatted \(.*\) in .*$/\1/p' | tr '\\' '/' | sort > stylua.set
    $ git ls-files --cached --others --exclude-standard -- src tests lune | grep '\.luau$' | sort > git.set
    stylua: 38  git: 38
    --- differences ---
    (none)

Identical file for file, not merely equal in count. That is what justifies using
a git pathspec as the counter for `lint` and `typecheck` at all: `selene` and
`luau-lsp analyze` cannot report their own sets, so the only honest argument for
the pathspec is that it provably matches what the one tool that *can* report
actually reads. It does.

### The stale probes, found and corrected

Nine of RED's ten `## Regressions` probes were captured against a 37-assertion
draft and pasted beside a baseline from the shipped 40-assertion suite. Caught by
arithmetic — probe totals summing to 37 next to a baseline of `30 passed, 10
failed` — and confirmed by reproducing probe 2, which gave `29 passed, 11 failed`
against RED's recorded `26 passed, 11 failed`.

RED re-ran all ten against the shipped suite. Every total now sums to 40, every
probe still goes red, and **no `**Earns:**` line changed** — only the always-green
count moved, by the three assertions added after the drafts were taken. The
substance was never in doubt; the paste was. A pasted total that does not
correspond to the artefact being shipped is the exact failure mode `## Regressions`
exists to prevent, and `check-boundaries.sh` cannot tell a stale paste from a
current one — only arithmetic can.

**Probe 1 was reproduced independently too**, because its total is deceptive:
`30 passed, 10 failed`, identical to the baseline, yet a *different* ten. Four
assertions went red and four went green. Confirmed line for line by the
orchestrator. The four that went green are the finding:

> Hard-wiring the counter to `src` satisfies AC-1 and AC-3 outright. AC-7 is the
> only thing that refuses it.

AC-7 was written as a conservatism — *the fix corrects what is measured, not the
measurement* — and probe 1 shows it is load-bearing instead. Recorded here
because a criterion that turns out to be the only guard against a whole class of
wrong fix should not stay filed under "settled".

### A discarded measurement, recorded rather than quietly re-run

An orchestrator `gates.sh --fast` taken while RED's probe re-run was in flight
reported `typecheck (observed 5)` and a failing `unit`. Both are artefacts of
sampling a tree mid-mutation: `.claude/state/mutations/log` shows three probes at
`175822Z`, `175836Z` and `175851Z`, each `restored (verified)`, and the `-- src/shared`
mutation was live when the gate ran. The `unit` failure was `source_guard_test`,
which enumerates the source tree and saw a probe scratch file. **That run is void
and is not the one recorded above.** Noted because a discarded measurement that
goes unmentioned is indistinguishable from one that was never taken. Operational
rule for the rest of this story: do not measure the tree while a subagent holds
`mutate.sh`.

### Ruling 1 — the `doctor.sh` guard stays, though it is outside the ACs

RED added one assertion no acceptance criterion asks for: that each gate
command's first token is a real executable. It guards a BOOT-001 invariant that
**this story's own Contract would have broken**, and nothing else in the
repository would have caught it. A regression guard that has already caught the
Lead PO once has earned its place. It is recorded here as a deliberate scope
addition rather than left to look like drift.

### Ruling 2 — GREEN corrects the workflow comment that would silently delete this suite

`.github/workflows/gates.yml` carries a comment recommending that the
`Harness self-test` step move to `boundaries.yml`, on the stated ground that the
step *"needs only bash and git"*. After this story that is false: the new suite
shells out to `stylua`, `selene`, `rojo` and `luau-lsp`. Checked —
`boundaries.yml` installs no toolchain and runs only `check-boundaries.sh`.

Acting on that comment would make the suite fail on a runner with no toolchain,
and the failure would read as a broken gate rather than a misplaced step. The
file classifies as `harness`, so GREEN may write it. **GREEN updates that comment
to record the new dependency.** It is one comment, in the same commit as the
change that creates the dependency, which is the only moment anyone will connect
the two.

### Ruling 3 — `## Gate probes` is required from GATES, freshly

Three gate commands change, so the non-negotiable applies: *a gate that has never
been observed to fail is not a gate.* RED's probes 6, 7 and 8 break each tool and
watch the gate fail, but they were run against the **old** commands and live in
`## Regressions`. GATES breaks each of the three **new** commands and records
that in `## Gate probes`. No floor moves in this story, so no floor needs one.

### What GREEN is accountable for

1. Make the ten red assertions green **without touching
   `.claude/tests/project-counters.test.sh`.** Tests are frozen. If one is wrong,
   stop and say so — the lock will not stop you, which is exactly why this is
   written down.
2. Solve the two `format` requirements **together**: the command's exit status
   must be `stylua`'s, *and* an empty target must exit 0 with a count the evidence
   regex refuses. Solving either alone fails the other.
3. Keep the first token of every gate command a real executable (ruling 1's
   guard), and name each target exactly once.
4. Update the `gates.yml` comment (ruling 2).
5. **Confirm RED's negative-control values against the shipped `project.conf`** —
   the two tables in `## Handoff`. Then run the three `## Notes` mutations and
   compare against RED's predicted `5 / 1-2 / 1`. Record it in
   `## GREEN: control values confirmed`.
6. End with `bash scripts/selftest.sh` *and* `bash scripts/gates.sh --fast`, and
   report both. The first is where this story's assertions live; the second is
   whether the three rewritten commands still run at all.

**Resolved model of the RED dispatch:** `test-developer`, whose definition
declares `model: opus`; resolved to **Opus 5**, no override in play. The same
agent was resumed for the probe re-run, on the same model.

---


## PO acceptance at GREEN -> GATES

**GREEN is accepted.** Re-run by the orchestrator, not read off the report.

**The suite.** `bash .claude/tests/project-counters.test.sh` → **40 passed, 0
failed**. All ten red assertions turned.

**The rest of the harness.** `bash scripts/selftest.sh` → **15 harness suite(s)
passed in 491 s**, every suite `ok`, none failed. No collision.

**GREEN wrote no test.** `git diff -- .claude/tests/` is empty. As at RED, this
is the check that matters most on this story: PO decision 4 established that the
lock would have permitted the edit, so the freeze held because it was honoured.

**Admissibility.** `bash scripts/gates.sh --fast` on a quiet tree:

    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (1s, observed 7)
    PASS         unit (5s, observed 175, floor 175)
    UNCONFIGURED coverage
    PASS         build (0s, observed 20721)

**38 / 38 / 7 — AC-7 holds, produced by an entirely new mechanism.** That is the
criterion doing its job: the numbers are the same and nothing about how they are
obtained is.

### The mutation table, confirmed rather than quoted

Mutation 3 was re-run by the orchestrator — chosen because it is the
single-assertion case, which is the one a wrong prediction shows up in:

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@git ls-files --cached --others --exclude-standard -- $GATE_LINT_TARGET@git ls-files -- $GATE_LINT_TARGET@' \
        -- bash .claude/tests/project-counters.test.sh

      FAIL AC-4: lint counts the untracked file (38 -> 39)
    project-counters: 39 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/.claude_harness_project.conf.20260916T184913Z.332314.bak) ===

`39 passed, 1 failed`, the single predicted assertion, nothing else. All three of
GREEN's totals sum to 40, matching the shipped suite — the arithmetic that caught
the stale probes at RED, applied again.

**Mutation 1 came in at 6 red against RED's predicted 5**, and the extra is
explained rather than waved through: with the literal `src tests lune` gone from
the command, the empty-boundary case has nothing to narrow, runs over `src` and
reports 7. Wider than predicted, in the direction the story wants. Nothing
amended — `## Notes` is guidance, not criteria.

### The two `format` requirements, verified directly rather than through the suite

These are the subtle half of the story, so the orchestrator ran the shipped gate
command itself rather than trusting an assertion about it.

**Empty target — BOOT-001's design, not an opaque failure:**

    $ cmd=$(grep '^gate | format' .claude/harness/project.conf | cut -d'|' -f5-)
    $ ( eval "${cmd//src tests lune/docs}" ); echo "rc=$?"
    stylua over 0 files
    rc=0

Exit 0, and a count the evidence regex refuses — *"ran but produced no evidence
of work"*. The Contract's suggested `grep -c` would have exited 1 here under
`pipefail` and reported a broken gate instead.

**Exit status is stylua's, and the diff survives:**

    $ printf 'local x   =   1\nreturn x\n' > src/shared/__probe_po_unformatted.luau
    $ ( eval "$cmd" ); echo "rc=$?"
    Diff in src\shared\__probe_po_unformatted.luau:
    1        |-local x   =   1
        1    |+local x = 1
    2   2    | return x
    stylua over 39 files
    rc=1

Three things at once: the gate FAILS on unformatted code, **the diff reaches the
log**, and the count moved 38 → 39 for an untracked file. The middle one is
GREEN's own deviation earning itself — the Contract's `grep -c` would have
swallowed the diff, leaving a failing `format` gate with no diff to act on. That
is a defect the Contract would have shipped and the story did not ask anyone to
look for.

### GREEN's three deviations from the Contract, each accepted

1. **One `stylua` run, status via `${PIPESTATUS[0]}`.** A second `-v` run used
   only for counting would be a second enumeration — this story's own defect,
   reintroduced. Checked: `gates.sh:411` is already `rc=${PIPESTATUS[0]}` in the
   same position, `gates.sh` is `#!/usr/bin/env bash`, and nothing else evaluates
   a gate command (`doctor.sh:71` extracts it only to read `awk '{print $1}'`;
   `task.sh` reads `task |` lines). The bashism is safe where it sits.
2. **The awk pass passes non-debug output through** rather than counting with
   `grep -c`. Justified above by the diff that survives.
3. **`typecheck` assigns `${GATE_TYPE_TARGET:=src}` on `test -d`, not inside the
   pipeline.** Pipeline elements run in subshells, so an assignment there is lost
   and the counter meets an unbound variable under `set -u`. Correct.

### The `:=` trapdoor is accepted, and here is why it is not this story's defect

An **exported** `GATE_LINT_TARGET` or `GATE_TYPE_TARGET` in the caller's
environment beats the `:=` default and narrows the gate. GREEN flagged it and
documented it in `project.conf`. It stays, because it narrows **the tool and the
counter together**: a gate run that way lints less and *says so*, reporting the
smaller number honestly. That is a different and lesser fault than the one this
story fixes, which was a gate reporting 38 while reading 7. Naming the target
once is what buys that property, and the only alternative — writing the list
twice — is the defect itself. The variable names are deliberately long and
gate-specific; `project.conf` says not to shorten them.

### `.github/workflows/gates.yml` — ruling 2 discharged

The comment recommending the self-test move to `boundaries.yml` now records that
the suite needs the toolchain, that `boundaries.yml` installs none, that the step
must follow `bash scripts/task.sh install`, and that the suite is deliberately
not skippable on a missing tool. It states what the paragraph used to say and why
it is no longer true, rather than quietly replacing it.

### Still outstanding, and owned by GATES

**`## Gate probes`, freshly, against the new commands** (ruling 3). Three gate
commands changed, so *a gate that has never been observed to fail is not a gate*
applies to all three. RED's probes 6, 7 and 8 broke each tool, but against the
**old** commands; they are evidence about a configuration that no longer exists.
GATES breaks each of the three new commands and records the output. No floor
moved in this story, so no floor needs a probe.

GREEN deliberately did not run a full `bash scripts/gates.sh`, and that is right:
a stamp written now is one GATES immediately supersedes.

**Resolved model of the GREEN dispatch:** `feature-developer`, declared
`model: opus`, dispatched with no override, resolved to **Opus 5**
(`claude-opus-5`).

---

## Test plan

### Where the tests live, and why

**A new suite: `.claude/tests/project-counters.test.sh`.** Not extra cases in
`.claude/tests/gates.test.sh`, for three reasons:

1. `gates.test.sh` tests `scripts/gates.sh` - the liveness *machinery* - against
   a throwaway fixture whose gate commands are `printf`s. This story tests *this
   project's* `project.conf` against the real tree and the real toolchain. They
   are different subjects with different dependencies.
2. `scripts/refresh-harness.sh` **replaces** `.claude/tests/` wholesale from
   upstream for every file upstream ships, and **keeps** any file it does not
   (`KEPT .claude/tests/<x> (upstream does not ship it - yours)`). Cases added
   to `gates.test.sh` would be deleted by the next harness refresh; a suite
   upstream has never heard of survives.
3. `scripts/selftest.sh` globs `.claude/tests/*.test.sh`, so either placement is
   discovered. Only one of them still exists after a refresh.

**Level:** the real gate commands, parsed out of the real `project.conf` and run
against the real tree. Not a copy of the command pasted into the test - a test
carrying its own copy asserts nothing about the file the gates actually read.
The command is taken with the same field split `gates.sh` uses
(`cut -d'|' -f5-`, and `-f3-` for `evidence`), and the count is read out of the
command's output by the rule `project.conf`'s own header documents: *the first
run of digits at or after the start of the first evidence match*. So the tests
pin **the number a `floor` would be compared against**, and they do not dictate
the wording of the line that carries it. GREEN may reshape the output freely as
long as the `evidence` regex keeps matching it.

### How "the target narrows" is expressed

A gate's target is narrowed by replacing the **first occurrence** of the path
list in the command text, then running the result. That is only an honest
narrowing if the path list occurs **once** - which is what AC-3 and AC-5
literally require (*"the two cannot disagree if there is only one"*). So every
narrowing case is paired with an occurrence-count case, and **neither is
evidence without the other**: with two copies, "first occurrence" could be the
counter's copy rather than the tool's, and a gate could satisfy a narrowing case
while counting a list its tool never saw. Probe 1 in `## Regressions` is that
hazard demonstrated.

### The cases

| AC | Test (suite: `project-counters`) | Red today? |
|---|---|---|
| AC-1 | `the format gate names 'src tests lune' exactly once` | **RED** (2) |
| AC-1 | `narrowing the format target to src reports 7, not 38` | **RED** (38) |
| AC-1 | `exits 0 on a target with no .luau files, rather than dying on grep's empty count` | green (earned: probe 5, 8) |
| AC-1 | `does not report a count it did not read` (target `docs`) | **RED** (reports 38) |
| AC-2 | `AC-2: format counts the untracked file (38 -> 39)` | **RED** (38) |
| AC-2 | `AC-2: the format gate still passes with the untracked file present` | green (earned: probe 8) |
| AC-3 | `the lint gate names 'src tests lune' exactly once` | **RED** (2) |
| AC-3 | `narrowing the lint target to src reports 7, not 38` | **RED** (38) |
| AC-4 | `AC-4: lint counts the untracked file (38 -> 39)` | **RED** (38) |
| AC-4 | `AC-4: the lint gate still passes with the untracked file present` | green (earned: probe 6) |
| AC-5 | `the typecheck gate names 'src' exactly once` | **RED** (2) |
| AC-5 | `narrowing the typecheck target to src/shared reports 5, not 7` | **RED** (7) |
| AC-5 | `typecheck counts the untracked file (7 -> 8)` | **RED** (7) |
| AC-5 | `the typecheck gate still passes with the untracked file present` | green (earned: probe 7) |
| AC-6 | `the scratch file really is ignored (precondition)` | green (earned: probe 9) |
| AC-6 | `format / lint / typecheck does not count the ignored file (38 / 38 / 7)` | green (earned: probe 3) |
| AC-6 | `the {format,lint,typecheck} gate still passes with an ignored .luau file present` | green (earned: probes 8, 6, 7) |
| AC-7 | `format / lint / typecheck reports 38 / 38 / 7 files on the unmodified tree` | green (earned: probes 1, 2) |
| AC-7 | `the {format,lint,typecheck} gate passes on the unmodified tree` | green (earned: probes 8, 6, 7) |
| PO decision 3 | `stylua itself rejects the scratch file (precondition)` | green (control, measured) |
| PO decision 3 | `under pipefail, as scripts/gates.sh runs it` | green (earned: probe 4) |
| PO decision 3 | `and without pipefail, so the exit status is stylua's and not grep's` | green (earned: probes 4, 5) |

Edges covered beyond the criteria's own wording: **empty** (a format target with
no `.luau` files at all), **one more than baseline** (the untracked and the
ignored file, +1 each), and **many** (38 / 7 unnarrowed). The `## Out of scope`
items are untouched - no `floor` is read or asserted anywhere in the suite.

### AC-7 is read, never derived

`BASE_FORMAT=38`, `BASE_LINT=38`, `BASE_TYPECHECK=7` are constants at the top of
the suite, taken from AC-7 and PO decision 5. They are not computed from
anything. Re-deriving them with the new counter is the thing AC-7 exists to
detect, and probes 1 and 2 show they fire.

### What the suite does NOT constrain

The wording of the count line, whether the count comes from the tool's output or
from a path list, the flags the tools are given, the `evidence` regexes, and
whether the target lives in a shell variable or is simply written once. All of
that is GREEN's choice; the suite reads whatever `project.conf` says.

## Handoff: RED -> GREEN

### The loop

    bash .claude/tests/project-counters.test.sh     # this story's assertions, ~20 s
    bash scripts/selftest.sh                        # all 15 harness suites, ~13 min on Windows
    bash scripts/gates.sh --fast                    # does project.conf still RUN

**Not `lune run test`.** This story's assertions are in `.claude/tests/`, not in
`tests/`. `scripts/selftest.sh` runs before `scripts/gates.sh` in CI's required
`gates` job, so a red suite here fails a required check (PO decision 1).

### Files touched in RED

| File | What |
|---|---|
| `.claude/tests/project-counters.test.sh` | **new**, the whole suite |
| `docs/backlog/stories/HARNESS-006.md` | `## Test plan`, `## Regressions`, this section, and one amendment inside `## Contract` (marked, dated, reason given) |

`git diff -- .claude/harness/project.conf` is **empty**. Nothing else was
touched. `.claude/state/mutations/` holds `log` and no `.bak`.

### The failure, verbatim

`bash .claude/tests/project-counters.test.sh` -> `30 passed, 10 failed`, 20.0 s
wall on this machine (Windows 11, Git Bash, warm). Verbatim:

```
  preconditions

  AC-7: the three gates report the same counts as before this story

  a gate names its target once, so the tool and the counter cannot disagree
    FAIL the format gate names 'src tests lune' exactly once
         expected: 1
         actual:   2
    FAIL the lint gate names 'src tests lune' exactly once
         expected: 1
         actual:   2
    FAIL the typecheck gate names 'src' exactly once
         expected: 1
         actual:   2

  every gate command starts with a real executable, so doctor.sh can find the tool

  AC-1: the format count is the number of files stylua read
    FAIL narrowing the format target to src reports 7, not 38
         expected count: 7
         actual count:   38
         evidence regex: stylua over [1-9][0-9]* files
         gate output (last 6 lines):
         stylua over 38 files

  AC-1, empty boundary: a format target with no .luau files claims no work
    FAIL does not report a count it did not read
         expected the evidence regex NOT to match, so that gates.sh
         reports 'ran but produced no evidence of work'
         evidence regex: stylua over [1-9][0-9]* files
         gate output (last 6 lines):
         stylua over 38 files

  AC-3: the lint count moves with the target selene was handed
    FAIL narrowing the lint target to src reports 7, not 38
         expected count: 7
         actual count:   38
         evidence regex: selene over [1-9][0-9]* files
         gate output (last 6 lines):
         Results:
         0 errors
         0 warnings
         0 parse errors
         selene over 38 files

  AC-5: the typecheck count moves with the target luau-lsp was handed
    FAIL narrowing the typecheck target to src/shared reports 5, not 7
         expected count: 5
         actual count:   7
         evidence regex: analyze over [1-9][0-9]* files
         gate output (last 6 lines):
         Created sourcemap at sourcemap.json
         [INFO] Loading definitions file: @roblox - globalTypes.d.luau
         [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
         [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
         analyze over 7 files

  AC-2/AC-4: a .luau file on disk but not yet tracked by git is counted
    FAIL AC-2: format counts the untracked file (38 -> 39)
         expected count: 39
         actual count:   38
         evidence regex: stylua over [1-9][0-9]* files
         gate output (last 6 lines):
         stylua over 38 files
    FAIL AC-4: lint counts the untracked file (38 -> 39)
         expected count: 39
         actual count:   38
         evidence regex: selene over [1-9][0-9]* files
         gate output (last 6 lines):
         Results:
         0 errors
         0 warnings
         0 parse errors
         selene over 38 files
    FAIL typecheck counts the untracked file (7 -> 8)
         expected count: 8
         actual count:   7
         evidence regex: analyze over [1-9][0-9]* files
         gate output (last 6 lines):
         Created sourcemap at sourcemap.json
         [INFO] Loading definitions file: @roblox - globalTypes.d.luau
         [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
         [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
         analyze over 7 files

  AC-6: a .luau file .gitignore covers is not counted

  the format gate FAILS on a badly formatted file, however it counts

project-counters: 30 passed, 10 failed
```

**Why this is the right failure.** Every one of the ten is the assertion itself,
against a command that ran to completion and printed a number: the gate exited
0, the evidence regex matched, and the number was the wrong number. Not one is an
error, a missing file or a timeout.

### One line per failing test

| # | Test | Asserts | AC |
|---|---|---|---|
| 1 | `the format gate names 'src tests lune' exactly once` | the path list is not typed twice | AC-1 |
| 2 | `the lint gate names 'src tests lune' exactly once` | ditto | AC-3 |
| 3 | `the typecheck gate names 'src' exactly once` | ditto | AC-5 |
| 4 | `narrowing the format target to src reports 7, not 38` | the count follows the tool's target | AC-1 |
| 5 | `does not report a count it did not read` | a target with no `.luau` files reports no work | AC-1 (empty boundary) |
| 6 | `narrowing the lint target to src reports 7, not 38` | the count follows the tool's target | AC-3 |
| 7 | `narrowing the typecheck target to src/shared reports 5, not 7` | ditto | AC-5 |
| 8 | `AC-2: format counts the untracked file (38 -> 39)` | on-disk-but-untracked is counted | AC-2 |
| 9 | `AC-4: lint counts the untracked file (38 -> 39)` | ditto | AC-4 |
| 10 | `typecheck counts the untracked file (7 -> 8)` | ditto, third gate (Contract) | AC-5 |

### The shape the tests already pin - stated as fact, not suggestion

There is nothing to import and nothing to export; the analogue is **what the
suite reads out of `.claude/harness/project.conf`, and how**. A wrong guess here
is a red suite, so:

**Read, and therefore fixed:**

- `gate | <id> | <req> | <cwd> | <command>` and `evidence | <id> | <regex>` keep
  their field layout. The suite splits on `|` exactly as `gates.sh` does -
  `cut -d'|' -f5-` for a gate command, `-f3-` for an evidence regex - so a new
  field, a renamed kind or a moved column breaks it. The Contract already says
  no field is added or removed.
- The gate ids stay `format`, `lint`, `typecheck`.
- **Every gate keeps an `evidence` line whose regex matches its own output**, and
  the count is the first run of digits at or after the start of that match. That
  is how the suite reads "the count the gate reports", and it is the same rule
  `gates.sh` uses to feed a `floor`. If you change the wording of the count line,
  change the `evidence` regex in the same commit or every count assertion fails.
- **`format`'s target is the literal string `src tests lune`, appearing exactly
  once** in the command. Same for `lint`. **`typecheck`'s target is the literal
  string `src`, appearing exactly once.** The narrowing tests replace that one
  occurrence; the uniqueness tests assert there is only one.
- **The first whitespace-delimited token of each gate command is an executable on
  PATH** (`scripts/doctor.sh` line 74 depends on it - see finding 5).
- `format` must exit non-zero when an unformatted `.luau` file is on disk, **both
  under `pipefail` and without it**.

**Deliberately not constrained - your choice:**

- Whether the count comes from the tool's output or from a path list.
- The wording of the count line (`stylua over N files`, `N files`, anything the
  evidence regex matches).
- The evidence regexes themselves.
- The tool flags (`-v`, `--display-style`, redirections, `tee`, temp files).
- Whether the target lives in a shell variable or is simply written once.
- The `floor` lines - out of scope, and nothing in the suite reads one.

### Every assertion that passed on arrival, and what earns it

**Twenty of the thirty.** This story has no "fails at import" problem: the
implementation exists, the suite loads, and **every assertion in it executed** in
RED. So the controls below are *measured*, not claims - unlike the usual RED
handoff. What is still GREEN's job is confirming they hold against the **shipped**
`project.conf`, because a rewrite of the three commands can make a control
vacuous without making it red.

`## Regressions` has the ten probes in full. Summary of which earns what:

| Green-on-arrival assertion | Earned by |
|---|---|
| AC-7 `format`/`lint` report 38 | probe 1 |
| AC-7 `typecheck` reports 7 | probe 2 |
| AC-6 all three "does not count the ignored file" | probe 3 (and 1, 2) |
| AC-6 `the scratch file really is ignored` | probe 9 |
| `under pipefail, as scripts/gates.sh runs it` | probe 4 |
| `and without pipefail ...` | probes 4 and **5** (5 fires it alone) |
| `exits 0 on a target with no .luau files` | probes 5 and 8 |
| `the {format,lint,typecheck} gate passes ...` (7 assertions) | probes 8, 6, 7 |
| `the {format,lint,typecheck} gate's first token is on PATH` | probe 10 |

### Negative controls: expected value and the value measured

Measured in RED, outside any framework ambiguity - these are the commands the
suite runs, and their real results on this tree at this commit.

| Control | What it asserts | Expected | **Measured in RED** | Goes red when |
|---|---|---|---|---|
| `git ls-files -- src/shared/__probe_h006_untracked.luau` | the AC-2/AC-4 scratch file is genuinely untracked | empty | **empty** | the file is committed |
| `git check-ignore -q src/shared/__probe_h006_untracked.luau` | ... and genuinely not ignored | rc 1 | **rc 1** | `.gitignore` grows a rule for it |
| `git check-ignore -q src/build/__probe_h006_ignored.luau` | the AC-6 scratch file really is ignored | rc 0 | **rc 0** | probe 9 (`build/` commented out) |
| `stylua --check src/shared/__probe_h006_unformatted.luau` | the "badly formatted" file really is | rc != 0 | **rc 1** | `stylua.toml` stops caring about `local x   =   1` |
| `git status --porcelain -- src tests lune \| grep '\.luau$'` | the tree carries no stray `.luau`, so 38/38/7 mean what they say | empty | **empty** | a developer leaves a scratch module behind |
| occurrences of the target in the gate command, before narrowing | the narrowing is not a silent no-op | >= 1 | **2, 2, 2** | the target is renamed - the suite says so by name |

Tool-level facts the suite's numbers rest on, re-measured in RED rather than
taken on trust:

| Measurement | Value |
|---|---|
| `stylua --check -v src tests lune 2>&1 \| grep -c '^debug: formatted '` | **38** |
| ... over `src` | **7** |
| ... over `src/shared` | **5** |
| `git ls-files --cached --others --exclude-standard -- src tests lune` (`.luau` only) | **38** |
| the two file **sets** above, sorted and compared | **identical** (modulo `\` vs `/` in stylua's paths) |
| with one untracked `.luau` added | both **39** |
| with one `.gitignore`d `.luau` added under `src/build/` | both still **38** - `stylua` honours `.gitignore` |
| `find src tests lune -name '*.luau' -type f \| wc -l` | **38** clean, **39** with the ignored file - i.e. `find` fails AC-6 |
| `stylua --check -v docs 2>&1 \| grep -c '^debug: formatted '` | prints `0`, **grep exits 1** |

These agree with the Contract. Nothing in it needed correcting except the
`pipefail` sentence (finding 1).

### Findings that change the implementation approach

**1. `pipefail` IS in effect inside a gate command.** The Contract said it is
not; it is. `gates.sh` line 41 `set -uo pipefail`, line 410
`( cd "$ROOT/$cwd" && eval "$cmd" ) 2>&1 | tee "$log"` - a subshell inherits
shell options. Amended in place inside `## Contract`, with the decision
unchanged: the command must still carry `stylua`'s exit status on its own,
because a gate whose correctness is borrowed from the runner's shell options
fails the moment anything else runs it (`doctor.sh`, `bash -c`, a human). Two
assertions pin it, and probe 5 shows the `nopipefail` one is the discriminating
half.

**2. `grep -c` exits 1 when it counts nothing, and under `pipefail` that is a
real failure.** So the Contract's suggested
`stylua --check -v ... | grep -c '...'` turns *a target with no `.luau` files*
into an opaque `exit 1`, where BOOT-001's design calls for exit 0 plus a count
the evidence regex refuses - *"ran but produced no evidence of work"*. The
suite's empty boundary pins both halves. Shapes that satisfy it, for reference
rather than as instruction: capture to a variable and test separately
(`out=$(stylua --check -v ... 2>&1); rc=$?; n=$(printf '%s\n' "$out" | grep -c ... || true)`),
or `{ grep -c ... || true; }`, or `grep -c ...; :`. Whatever you pick, the
**status must still come from `stylua`**, so the two requirements have to be
solved together rather than one at a time.

**3. `stylua`'s per-file lines go to stderr, and carry native path separators.**
`debug: formatted src\shared\Clock.luau in 1.2ms` on Windows,
`src/shared/Clock.luau` on Linux. `2>&1` is required, and a regex anchored on
`^debug: formatted ` is portable where one anchored on a path shape is not. CI is
`ubuntu-latest`; this machine is Windows. Both must count 38.

**4. `tee /dev/stderr` is unnecessary and slightly harmful.** `gates.sh` already
captures the gate's stdout *and* stderr into the log (`( ... ) 2>&1 | tee`), so
`tee /dev/stderr` only duplicates 38 debug lines into it. Harmless to the tests
either way - they read whatever the command prints - but there is no reason for
it.

**5. The first token of a gate command must stay a real executable, which rules
out the Contract's `T="src tests lune"; selene $T` shape.** `scripts/doctor.sh`
line 74 is `exe=$(printf '%s' "$cmd" | awk '{print $1}')` followed by
`command -v`, so that shape makes doctor report a permanently MISSING tool called
`T="src`. `project.conf`'s own BOOT-001 header warns about exactly this. doctor
is not a gate, so nothing else in the repository would have noticed - hence the
guard added in RED, earned by probe 10. Shapes that satisfy **both** it and "the
target is named once", none of them mandated:

- `selene ${T:=src tests lune} && n=$(git ls-files --cached --others --exclude-standard -- $T | ...)`
  - unquoted so it word-splits, and `${T:=...}` assigns on first use. First token
    `selene`.
- `sh -c 'T="src tests lune"; selene $T && ...'` - first token `sh`, which is on
  PATH. doctor then checks `sh` rather than `selene`; acceptable only because
  `task | lint | . | selene src tests lune` already exists to keep doctor
  checking `selene`, which is the reason that task line is there.
- for `typecheck`, whose target is the single word `src`, a variable is barely
  needed at all - the tool argument and the counter pathspec can be the same
  `${T:=src}`.

**6. Nothing in the suite reads a `floor`,** so no floor moves and none can be
accidentally satisfied by this change. `floor | lint | 1` still passes trivially
at 38.

**7. New dependency on the toolchain in `scripts/selftest.sh`.** Before this
story every harness suite needed only bash, git and coreutils. This one shells
out to `stylua`, `selene`, `rojo` and `luau-lsp`, because the counts it pins are
facts about what those tools read. That is fine today: `.github/workflows/gates.yml`
installs the pinned toolchain **before** the `Harness self-test` step. It stops
being fine if anyone acts on the comment in that workflow suggesting the selftest
step move to `boundaries.yml`, which installs nothing. Flagged here, and in the
suite's own header, because the failure would look like a broken gate rather than
a misplaced step.

### The `## Notes` mutations, predicted against the shipped `project.conf`

The story predicts one red per mutation. Two of the three are measurably wider
than that once the fix is in, because the fix makes the tool and the counter the
same thing - which is the point.

| Mutation (`## Notes`) | Predicted red | Count |
|---|---|---|
| 1. Narrow the `format` target back to `src` | `format reports 38 files on the unmodified tree`; `format does not count the ignored file (still 38)`; `AC-2: format counts the untracked file (38 -> 39)`; `narrowing the format target to src reports 7, not 38` (which reports *"does not contain the target"*, because there is no longer a `src tests lune` to narrow); `the format gate names 'src tests lune' exactly once` (0, not 1) | **5** |
| 2. Put the `format` counter back behind a bare pipe | `and without pipefail, so the exit status is stylua's and not grep's`. If the same mechanism also carried the empty-target exit status, `exits 0 on a target with no .luau files` goes with it | **1-2** |
| 3. Revert `--cached --others --exclude-standard` to bare `git ls-files` in the `lint` counter | `AC-4: lint counts the untracked file (38 -> 39)` | **1**, as the story predicts |

Mutation 1's breadth is the story's own thesis: after the fix, narrowing the
target narrows the count, so a narrowing mutation moves every count assertion for
that gate at once. If it makes only **one** assertion red, the counter is still a
second enumeration and the fix did not land.

Measured analogues, on today's unfixed conf, are probes 1, 5 and (for mutation 3)
the fact that `AC-4: lint counts the untracked file` is red right now.

### `bash scripts/gates.sh --fast`

    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (2s, observed 7)
    PASS         unit (9s, observed 175, floor 175)
    UNCONFIGURED coverage
    PASS         build (0s, observed 20721)
    All required gates passed (5 ran, 1 unconfigured, 0 known).

Expected, and it is the right shape for **this** story: RED here does not make a
gate go red, because the artifact under test *is* the gate configuration and
`## PO decisions` 1 says no gate in `project.conf` can be the guard for a
plausible-but-wrong number. The guard is `scripts/selftest.sh`, which is red.
`--fast` answers the only question it can answer here - whether the three
commands still run - and the three counts it printed are the AC-7 baselines,
unmoved.

### `bash scripts/selftest.sh`

`15 harness suite(s)`, 770 s on this machine, `1 ... FAILED`:

    boundaries: 60 passed, 0 failed        phase-guard: 145 passed, 0 failed
    ci-local: 15 passed, 0 failed          phase: 24 passed, 0 failed
    classify: 25 passed, 0 failed          profiles: 44 passed, 0 failed
    doctor: 21 passed, 0 failed            project-counters: 30 passed, 10 failed
    gate-reminder: 27 passed, 0 failed     refresh: 38 passed, 0 failed
    gates: 74 passed, 0 failed             settings: 20 passed, 0 failed
    lib: 136 passed, 0 failed
    mutate: 39 passed, 0 failed
    new-story: 22 passed, 0 failed

    [13/15] project-counters FAILED rc=1 (17s)
    1 of 15 harness suite(s) FAILED in 770s.

**No pre-existing suite went red.** 690 passing assertions before, 720 after,
and the only failures anywhere are this story's ten.

### Two things to know before you start

**The phase lock will not stop you editing a test.** `.claude/tests/*.test.sh`
and `.claude/harness/project.conf` both classify `harness`, writable in every
phase (PO decision 4). GREEN changes `project.conf` and touches no test. If a
test looks wrong, that is a return to RED with a note here - not an edit.

**Run the suite, not just the gates.** `gates.sh --fast` will pass for you the
whole time, before and after. It passed in RED with the defect fully present.

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

**Every probe below was run against the suite exactly as it ships, whose
baseline is `project-counters: 30 passed, 10 failed` (40 assertions). Each
block's totals therefore sum to 40, and the FAIL lists are complete - not an
excerpt - so the arithmetic can be checked without re-running anything.**

*(An earlier pass of this section carried totals from a 37-assertion draft,
measured before the `doctor.sh` first-token guard was added. All ten were
re-run; every probe still goes red and **every probe still earns exactly the
assertions recorded for it** - only the passing totals moved, by the three
always-green assertions the guard added. The re-run is why the backup
timestamps below are all `20260916T1758`-`1800`.)*

**This story has not returned to RED.** The section is used for the other thing
`rules.md` puts here: the probes that earn an assertion which passes on its
first execution. Every test in this story is written against an implementation
that already exists, so `## Deferred verifications` is right that **every**
green-on-arrival assertion needs one. Ten probes, each `bash scripts/mutate.sh`
- one mutation, one run, one verified revert. Never `sed -i`: `project.conf` and
`.gitignore` both classify `harness` and the lock would have allowed it, which
is exactly why it would have been working around the lock (law 5, PO decision 4).

**How to read a block.** Ten assertions are red on an unmutated tree - the
AC-1/2/3/4/5 cases listed in `## Handoff`. A probe is informative in both
directions, so each block names the assertions that turned red **in addition**
to those ten, and the ones that went green, which is often the more interesting
half.

---

### Probe 1 - narrow the `format` and `lint` counters, leave the tools alone

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@git ls-files -- src tests lune@git ls-files -- src@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (2 line(s) changed by s@git ls-files -- src tests lune@git ls-files -- src@) ===
      284 - gate | format    | optional | . | stylua --check src tests lune && n=$(git ls-files -- src tests lune | ...
      284 + gate | format    | optional | . | stylua --check src tests lune && n=$(git ls-files -- src | ...
      285 - gate | lint      | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | ...
      285 + gate | lint      | required | . | selene src tests lune && n=$(git ls-files -- src | ...
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL format reports 38 files on the unmodified tree
        FAIL lint reports 38 files on the unmodified tree
        FAIL the typecheck gate names 'src' exactly once
        FAIL does not report a count it did not read
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL format does not count the ignored file (still 38)
        FAIL lint does not count the ignored file (still 38)
    project-counters: 30 passed, 10 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175822Z.92783.bak) ===

**Earns:** AC-7 `format reports 38`, AC-7 `lint reports 38`, AC-6 `format does
not count the ignored file`, AC-6 `lint does not count the ignored file`.

**And the reason AC-7 exists, shown rather than argued:** four assertions went
*green* under this mutation - `narrowing the format target to src reports 7`,
`narrowing the lint target to src reports 7`, and both `names 'src tests lune'
exactly once` cases. Hard-wiring the counter to `src` satisfies AC-1 and AC-3
outright. AC-7 is the only thing that refuses it. (Same total as the baseline,
different ten: four in, four out.)

---

### Probe 2 - narrow the `typecheck` counter alone

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@-- src | while@-- src/shared | while@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@-- src | while@-- src/shared | while@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL typecheck reports 7 files on the unmodified tree
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL typecheck does not count the ignored file (still 7)
    project-counters: 29 passed, 11 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175836Z.95283.bak) ===

**Earns:** AC-7 `typecheck reports 7`, AC-6 `typecheck does not count the ignored
file`. `narrowing the typecheck target to src/shared reports 5` went green -
probe 1's lesson again, on the third gate.

---

### Probe 3 - count with `find` instead of `git ls-files`

The plausible wrong fix. `find` sees untracked files, so it satisfies AC-2 and
AC-4 - and it sees **ignored** files too.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@git ls-files -- src tests lune@find src tests lune -name "*.luau" -type f@; s@git ls-files -- src |@find src -name "*.luau" -type f |@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (3 line(s) changed by s@git ls-files -- src tests lune@find src tests lune -name "*.luau" -type f@; s@git ls-files -- src |@find src -name "*.luau" -type f |@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL format does not count the ignored file (still 38)
        FAIL lint does not count the ignored file (still 38)
        FAIL typecheck does not count the ignored file (still 7)
    project-counters: 30 passed, 10 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175851Z.97561.bak) ===

**Earns:** all three AC-6 count assertions. All three AC-2/AC-4 untracked
assertions went **green** under it - so AC-6 is precisely and only what stands
between GREEN and a `find`-based counter. Worth knowing before implementing.

---

### Probe 4 - drop `stylua`'s exit status from the `format` gate

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@stylua --check src tests lune &&@stylua --check src tests lune ;@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@stylua --check src tests lune &&@stylua --check src tests lune ;@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL under pipefail, as scripts/gates.sh runs it
        FAIL and without pipefail, so the exit status is stylua's and not grep's
    project-counters: 28 passed, 12 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175919Z.101314.bak) ===

**Earns:** both halves of *"the format gate FAILS on a badly formatted file"* -
PO decision 3. Nothing else moved: a gate that stops gating on formatting still
counts 38 / 39 / 38 perfectly, which is the whole point of the decision.

---

### Probe 5 - the naive pipe, exactly as the Contract warns

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@stylua --check src tests lune@stylua --check -v src tests lune 2>\&1 | grep -c "^debug: formatted " > /dev/null@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@stylua --check src tests lune@stylua --check -v src tests lune 2>\&1 | grep -c "^debug: formatted " > /dev/null@) ===
      284 + gate | format    | optional | . | stylua --check -v src tests lune 2>&1 | grep -c "^debug: formatted " > /dev/null && n=$(git ls-files -- src tests lune | ...
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL exits 0 on a target with no .luau files, rather than dying on grep's empty count
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL and without pipefail, so the exit status is stylua's and not grep's
    project-counters: 29 passed, 11 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175933Z.102734.bak) ===

**Earns:** the `nopipefail` half of PO decision 3 **alone** - `under pipefail, as
scripts/gates.sh runs it` stayed green, because `gates.sh` really does run gate
commands under `pipefail` (see `## Handoff`, finding 1). The two modes therefore
discriminate from each other, which is the only reason to have both.

**Also earns** the empty-target exit-status assertion, and by the same stroke
demonstrates finding 2: `grep -c` exits 1 when it counts nothing, so this shape
turns a target with no `.luau` files into an opaque `exit 1` instead of *"ran but
produced no evidence of work"*. `does not report a count it did not read` went
green here for the same reason - the chain died before the `echo`. Both halves of
that boundary case are thus individually earned.

---

### Probe 6 - point `selene` at a directory that does not exist

Each count assertion is guarded by an `exit 0` assertion on the same run; without
one, a gate that failed could still have printed a plausible number.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@selene src tests lune &&@selene src tests lune nosuchdir \&\&@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@selene src tests lune &&@selene src tests lune nosuchdir \&\&@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the lint gate passes on the unmodified tree
        FAIL lint reports 38 files on the unmodified tree
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: the lint gate still passes with the untracked file present
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL the lint gate still passes with an ignored .luau file present
        FAIL lint does not count the ignored file (still 38)
    project-counters: 25 passed, 15 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175946Z.104114.bak) ===

**Earns:** the three `lint` exit-0 assertions - `the lint gate passes on the
unmodified tree`, `AC-4: the lint gate still passes with the untracked file
present`, `the lint gate still passes with an ignored .luau file present` - and,
incidentally, the two `lint` count assertions probe 1 already earns.

---

### Probe 7 - point `luau-lsp` at a definitions file that does not exist

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@--definitions=globalTypes.d.luau --base-luaurc@--definitions=nosuch.d.luau --base-luaurc@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (2 line(s) changed by s@--definitions=globalTypes.d.luau --base-luaurc@--definitions=nosuch.d.luau --base-luaurc@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the typecheck gate passes on the unmodified tree
        FAIL typecheck reports 7 files on the unmodified tree
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL the typecheck gate still passes with the untracked file present
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL the typecheck gate still passes with an ignored .luau file present
        FAIL typecheck does not count the ignored file (still 7)
    project-counters: 25 passed, 15 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T175959Z.105480.bak) ===

**Earns:** the three `typecheck` exit-0 assertions. It is also the BOOT-001
`[ERROR]`-catching `awk` filter doing its job: `luau-lsp` exits **0** on a
missing definitions file, and only that filter turns the degraded analysis into a
failure. The probe changes two lines - the `typecheck` gate and the `analyze`
task, which carry the same flags. Only the gate line is read by the suite.

---

### Probe 8 - point `stylua` at a directory that does not exist

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@stylua --check src tests lune@stylua --check src tests lune nosuchdir@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@stylua --check src tests lune@stylua --check src tests lune nosuchdir@) ===
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate passes on the unmodified tree
        FAIL format reports 38 files on the unmodified tree
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL exits 0 on a target with no .luau files, rather than dying on grep's empty count
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: the format gate still passes with the untracked file present
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL the format gate still passes with an ignored .luau file present
        FAIL format does not count the ignored file (still 38)
    project-counters: 25 passed, 15 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T180018Z.107586.bak) ===

**Earns:** the three `format` exit-0 assertions, and a second, independent
earning of `exits 0 on a target with no .luau files` (probe 5 is the first).

---

### Probe 9 - stop `.gitignore` covering `build/`

AC-6's whole meaning rests on one precondition: that the scratch file really is
ignored. If `.gitignore` ever stopped covering it, three AC-6 assertions would
keep passing while testing nothing.

    $ bash scripts/mutate.sh .gitignore 's@^build/$@#build/@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .gitignore (1 line(s) changed by s@^build/$@#build/@) ===
      80 - build/
      80 + #build/
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
        FAIL the scratch file really is ignored (precondition - otherwise this case is vacuous)
    project-counters: 29 passed, 11 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.gitignore.20260916T180031Z.108954.bak) ===

**Earns:** the AC-6 precondition, alone. Exactly one assertion moved - the
baseline ten plus it.

---

### Probe 10 - put the `lint` target in a shell variable, exactly as the Contract suggests

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@selene src tests lune &&@T="src tests lune"; selene $T \&\&@' \
        -- bash .claude/tests/project-counters.test.sh

    === mutate: .claude/harness/project.conf (1 line(s) changed by s@selene src tests lune &&@T="src tests lune"; selene $T \&\&@) ===
      285 + gate | lint      | required | . | T="src tests lune"; selene $T && n=$(git ls-files -- src tests lune | ...
    === mutate: running bash .claude/tests/project-counters.test.sh ===
        FAIL the format gate names 'src tests lune' exactly once
        FAIL the lint gate names 'src tests lune' exactly once
        FAIL the typecheck gate names 'src' exactly once
        FAIL the lint gate's first token (T="src) is on PATH, as scripts/doctor.sh requires
        FAIL narrowing the format target to src reports 7, not 38
        FAIL does not report a count it did not read
        FAIL narrowing the lint target to src reports 7, not 38
        FAIL narrowing the typecheck target to src/shared reports 5, not 7
        FAIL AC-2: format counts the untracked file (38 -> 39)
        FAIL AC-4: lint counts the untracked file (38 -> 39)
        FAIL typecheck counts the untracked file (7 -> 8)
    project-counters: 29 passed, 11 failed
    === mutate: command exited 1; restored (verified byte-for-byte against ./.claude/state/mutations/.claude_harness_project.conf.20260916T180044Z.110113.bak) ===

**Earns:** the `doctor.sh` first-token guard, alone - and it is the reason that
guard exists. `scripts/doctor.sh` line 74 takes `awk '{print $1}'` of every gate
command as the tool to look for on PATH, so the Contract's suggested
`T="src tests lune"; selene $T` shape makes doctor report a permanently MISSING
tool called `T="src`. doctor is not a gate; without this assertion nothing in the
repository would ever say so. See `## Handoff`, finding 5, for shapes that
satisfy both this and "the target is named once".

---

After all ten, `git status --porcelain` showed only
`M docs/backlog/stories/HARNESS-006.md` and `?? .claude/tests/project-counters.test.sh`,
and `.claude/state/mutations/` contained `log` and no `.bak` - every restore
completed and was verified byte-for-byte.

## GREEN: control values confirmed

Every number below was measured against the **shipped** `.claude/harness/project.conf`
on this machine (Windows 11, Git Bash), after the three gate commands were
rewritten. Nothing here is copied from `## Handoff`; the RED column is quoted
only so the two can be compared.

### The suite

    $ bash .claude/tests/project-counters.test.sh
    project-counters: 40 passed, 0 failed          (12.9 s)

All ten red assertions are green, and the thirty that were green on arrival
stayed green. `git diff -- .claude/tests/` is empty and the suite file's mtime
is RED's: no test was touched.

### What shipped

    gate | format    | . | stylua --check -v src tests lune 2>&1 | awk '...counts ^debug: formatted ...'; test "${PIPESTATUS[0]}" -eq 0
    gate | lint      | . | selene ${GATE_LINT_TARGET:=src tests lune} && n=$(git ls-files --cached --others --exclude-standard -- $GATE_LINT_TARGET | ...) && echo "selene over $n files"
    gate | typecheck | . | rojo sourcemap ... && test -s globalTypes.d.luau && test -d ${GATE_TYPE_TARGET:=src} && luau-lsp analyze ... $GATE_TYPE_TARGET 2>&1 | awk '...' && n=$(git ls-files --cached --others --exclude-standard -- $GATE_TYPE_TARGET | ...) && echo "analyze over $n files"

Three deviations from shapes `## Contract` and `## Handoff` offered, all
measured rather than argued:

1. **`format` keeps ONE `stylua` run and takes its status from
   `${PIPESTATUS[0]}`**, not from the pipeline and not from a second invocation.
   A second `stylua -v` run purely to count would have been a second
   enumeration - the exact defect this story exists to remove - even though both
   runs would be the same tool on the same target.
2. **The awk pass passes non-debug output THROUGH.** `grep -c`, which the
   Contract suggested, would have swallowed `Diff in <path>:` and left a failing
   `format` gate with no diff in the log. `-v`'s own noise (the multi-line
   `Opt {` / `Config {` dumps, ~55 lines) is suppressed by brace tracking, so
   the log is cleaner than before this story, not noisier.
3. **`typecheck` assigns `${GATE_TYPE_TARGET:=src}` on `test -d`, not on the
   `luau-lsp ... | awk` step.** Every element of a pipeline runs in a subshell,
   so an assignment written on the analyse step would be lost and the counter
   would hit an unbound variable under `set -u`. Measured, not guessed.

### Negative controls: RED's value against the shipped conf

| Control | Expected | RED | **GREEN, measured** | Same? |
|---|---|---|---|---|
| `git ls-files -- src/shared/__probe_h006_untracked.luau` | empty | empty | **empty** | yes |
| `git check-ignore -q src/shared/__probe_h006_untracked.luau` | rc 1 | rc 1 | **rc 1** | yes |
| `git check-ignore -q src/build/__probe_h006_ignored.luau` | rc 0 | rc 0 | **rc 0** | yes |
| `stylua --check src/shared/__probe_h006_unformatted.luau` | rc != 0 | rc 1 | **rc 1** | yes |
| `git status --porcelain -- src tests lune \| grep '\.luau$'` | empty | empty | **empty** | yes |
| occurrences of the target in the gate command | 1 after the fix | **2, 2, 2** | **1, 1, 1** (format, lint, typecheck) | **moved, by design** |
| first token of each gate command | on PATH | `stylua`/`selene`/`rojo` | **`stylua` / `selene` / `rojo`**, all `ok` in `doctor.sh` | yes |

The occurrence control is the one that moved, and it moved because it *is* the
assertion: 2 was the defect, 1 is the fix. Everything else is unchanged, so the
scratch files still test what RED said they test.

Tool-level facts, re-measured against the shipped conf:

| Measurement | RED | **GREEN** |
|---|---|---|
| `stylua --check -v src tests lune 2>&1 \| grep -c '^debug: formatted '` | 38 | **38** |
| ... over `src` | 7 | **7** |
| ... over `src/shared` | 5 | **5** |
| `git ls-files --cached --others --exclude-standard -- src tests lune` (`.luau`) | 38 | **38** |
| the two file **sets**, sorted, `\` normalised to `/` | identical | **identical** (`diff` empty) |
| with one untracked `.luau` present | both 39 | **both 39** |
| with one gitignored `.luau` under `src/build/` | both 38 | **both 38** |
| `find src tests lune -name '*.luau' -type f \| wc -l` | 38 clean / 39 ignored | **38 / 39** - `find` still fails AC-6 |
| `stylua --check -v docs 2>&1 \| grep -c '^debug: formatted '` | prints 0, grep exits 1 | **prints 0, grep exits 1** |

No divergence. The set comparison matters most: `selene` and `luau-lsp` cannot
report their own file sets, so the only honest argument for counting them with a
git pathspec is that the pathspec provably matches what the one tool that *can*
report actually reads. It still does, file for file.

### The three `## Notes` mutations, against the shipped conf

All three through `bash scripts/mutate.sh .claude/harness/project.conf '<expr>'
-- bash .claude/tests/project-counters.test.sh`. Never `sed -i`. Every run
restored and verified byte-for-byte; `.claude/state/mutations/` holds `log` and
no `.bak`.

**Mutation 1 - narrow the `format` target back to `src`.** Predicted **5** red,
**6** observed.

    's@stylua --check -v src tests lune@stylua --check -v src@'

    FAIL format reports 38 files on the unmodified tree
    FAIL the format gate names 'src tests lune' exactly once
    FAIL narrowing the format target to src reports 7, not 38
    FAIL does not report a count it did not read
    FAIL AC-2: format counts the untracked file (38 -> 39)
    FAIL format does not count the ignored file (still 38)
    project-counters: 34 passed, 6 failed

**Divergence, and it is benign.** RED predicted the five it named; the sixth,
`does not report a count it did not read`, follows from the same cause. That
case narrows the target to `docs`, and with the literal `src tests lune` no
longer in the command there is nothing to narrow, so the command runs over `src`
and reports 7 - a count it did not read *for that target*, which is what the
assertion refuses. RED could not have seen it: against the old conf the
empty-boundary case was already red for a different reason. The prediction's
substance holds - narrowing one gate's target moves every count assertion for
that gate at once, which is the story's thesis, and 6 > 1 is the number that
matters.

**Mutation 2 - put the `format` counter back behind a bare pipe.** Predicted
**1-2** red, **1** observed.

    's@; test "${PIPESTATUS\[0\]}" -eq 0@@'

    FAIL and without pipefail, so the exit status is stylua's and not grep's
    project-counters: 39 passed, 1 failed

At the low end of the predicted range, and for the reason the range existed: the
empty-target exit status does **not** ride on the same mechanism in this
implementation. `awk` exits 0 whether it counted anything or not - unlike
`grep -c`, which exits 1 on an empty count - so `exits 0 on a target with no
.luau files` stays green under this mutation and is earned by the
implementation's shape rather than by its status handling. `under pipefail, as
scripts/gates.sh runs it` also stays green, exactly as RED's probe 5 predicted:
under `pipefail` the pipeline still carries `stylua`'s non-zero status. The one
assertion that discriminates is the `nopipefail` half, and it fires.

**Mutation 3 - revert `--cached --others --exclude-standard` to bare
`git ls-files` in the `lint` counter.** Predicted **1** red, **1** observed.

    's@git ls-files --cached --others --exclude-standard -- $GATE_LINT_TARGET@git ls-files -- $GATE_LINT_TARGET@'

    FAIL AC-4: lint counts the untracked file (38 -> 39)
    project-counters: 39 passed, 1 failed

Exactly as predicted. The `ROUND-005` symptom is tested, and it is tested
against a file the test creates rather than one the repository happens to carry.

### The rest of the harness

    $ bash scripts/selftest.sh
    15 harness suite(s) passed in 757s.

    boundaries: 60        gates: 74           phase: 24
    ci-local: 15          lib: 136            profiles: 44
    classify: 25          mutate: 39          project-counters: 40
    doctor: 21            new-story: 22       refresh: 38
    gate-reminder: 27     phase-guard: 145    settings: 20

730 assertions, 0 failed - RED's 720 passing plus the ten that were red. No
suite collided with the rewritten commands.

    $ bash scripts/gates.sh --audit
    Manifest audit passed.

    $ bash scripts/doctor.sh
    ok stylua / selene / rojo / lune / mkdir / rokit / luau-lsp / wally
    Everything this project needs is installed.

`doctor.sh` still resolves the real tool for all three rewritten gates, which is
the invariant ruling 1's guard exists for and the one the Contract's withdrawn
`T="src tests lune"; selene $T` shape would have broken.

### `bash scripts/gates.sh --fast`

    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (3s, observed 7)
    PASS         unit (9s, observed 175, floor 175)
    UNCONFIGURED coverage
    PASS         build (0s, observed 20721)
    All required gates passed (5 ran, 1 unconfigured, 0 known).

**38 / 38 / 7 - AC-7 holds.** The three numbers are now produced by a different
mechanism and are the same numbers, which is the whole of AC-7: the fix corrects
what is measured, not the measurement. No floor moved; `floor | unit | 175` and
`floor | lint | 1` are untouched.

### Ruling 2: the `gates.yml` comment

`.github/workflows/gates.yml` said the `Harness self-test` step *"needs nothing
but bash and git"* and named `boundaries.yml` as its usual right home. Both
statements are now false and the second is actively dangerous: `boundaries.yml`
runs `check-boundaries.sh` and installs no toolchain, so `project-counters`
would fail there on a missing `stylua` and the failure would read as a broken
gate. The comment now records the dependency, says the step must sit after
`bash scripts/task.sh install`, and says why the suite is deliberately not
skippable when a tool is absent. No step moved; only the comment changed.

### One thing GREEN did not do

`## Gate probes` is left empty for GATES, per ruling 3. The three commands have
been observed to fail here - mutations 1 and 2 above, and RED's probes 6, 7 and
8 - but those were runs of the *suite*, not of the gate, and a fresh probe
against the new commands is GATES' job.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-16T19:48:27Z
    commit: 347c9d2
    tree:   ca85af7340427e61410c31eefcb1d5fe047649db
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (2s, observed 7)
    PASS         unit (7s, observed 175, floor 175)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 20721)
    UNCONFIGURED mutation

## Gate probes

Three gate commands changed, so all three are re-probed **against the commands
as they now stand**. RED's probes 6, 7 and 8 in `## Regressions` broke the same
three tools, but they were run against the old commands and against the test
suite; they are evidence about a configuration that no longer exists. Every
probe below goes through **`bash scripts/gates.sh --gate <id>`**, so the output
is the gate runner's verdict and not an `eval` of the command text.

Two kinds of probe, because this story changed two things about each gate:

- **the gate still fails on what it guards** - bad formatting, a lint error, a
  type error. The count is irrelevant to these; they must fail on the tool.
- **the gate still fails on a tool that read nothing** - BOOT-001's *"ran but
  produced no evidence of work"*, which is the half this story rewrote and the
  half nothing had yet watched fail through the runner.

---

### 1. `format` - a badly formatted file on disk

**Broken:** a scratch file `src/shared/__probe_h006_gate_unformatted.luau`
containing `local x   =   1`, which `stylua.toml` reformats. Created by hand and
deleted afterwards, so `mutate.sh` does not apply - the tree is shown clean
below.

    $ printf 'local x   =   1\nreturn x\n' > src/shared/__probe_h006_gate_unformatted.luau
    $ bash scripts/gates.sh --gate format

    === gate: format (optional) ===
    stylua --check -v src tests lune 2>&1 | awk '/^debug: formatted /{n++; next} skip{if ($0 == "}") skip=0; next} /^debug: .*\{$/{skip=1; next} /^debug: /{next} {print} END{print "stylua over " n+0 " files"}'; test "${PIPESTATUS[0]}" -eq 0
    Diff in src\shared\__probe_h006_gate_unformatted.luau:
    1        |-local x   =   1
        1    |+local x = 1
    2   2    | return x
    stylua over 39 files

    --- gate summary ---
    WARN         format (0s, exit 1, optional) -> .claude/state/gate-logs/format.log

**Two things this proves, and both are new in this story.** The gate exited **1**
although the counter ran and printed a number - the status is `stylua`'s, taken
from `${PIPESTATUS[0]}`, not the pipeline's, which is `awk`'s and is always 0.
And the **`Diff in ...` survived the counter**: the awk pass counts
`debug: formatted` lines and passes everything else through, where the
Contract's suggested `grep -c` would have swallowed the diff and left a failing
format gate with nothing in the log to act on. `WARN` rather than `FAIL` is the
severity of an optional gate; `exit 1` is the verdict.

**Reverted:** `rm -f src/shared/__probe_h006_gate_unformatted.luau`, then

    $ bash scripts/gates.sh --gate format
    stylua over 38 files
    PASS         format (0s, observed 38)

---

### 2. `lint` - code `selene` rejects

**Broken:** a scratch file `src/shared/__probe_h006_gate_lintbreak.luau` calling
an undefined global. Created and deleted by hand; tree shown clean below.

    $ printf 'local M = {}\n\nfunction M.go()\n\treturn undefinedGlobalFunction(1)\nend\n\nreturn M\n' > src/shared/__probe_h006_gate_lintbreak.luau
    $ bash scripts/gates.sh --gate lint

    === gate: lint (required) ===
    selene ${GATE_LINT_TARGET:=src tests lune} && n=$(git ls-files --cached --others --exclude-standard -- $GATE_LINT_TARGET | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"
    error[undefined_variable]: `undefinedGlobalFunction` is not defined
      ┌─ src\shared\__probe_h006_gate_lintbreak.luau:4:9
      │
    4 │     return undefinedGlobalFunction(1)
      │            ^^^^^^^^^^^^^^^^^^^^^^^

    Results:
    1 errors
    0 warnings
    0 parse errors

    --- gate summary ---
    FAIL         lint (0s, exit 1) -> .claude/state/gate-logs/lint.log
    1 required gate(s) failed.

**No count line was printed.** `selene` exited 1, the `&&` chain stopped before
the counter, and the gate failed on the tool - so the rewritten counter cannot
manufacture evidence for a run that found errors. That ordering is BOOT-001's
and this story preserved it.

**Reverted:** `rm -f src/shared/__probe_h006_gate_lintbreak.luau`, then

    $ bash scripts/gates.sh --gate lint
    selene over 38 files
    PASS         lint (0s, observed 38, floor 1)

---

### 3. `typecheck` - a real type error under `src`

**Broken:** a scratch file `src/shared/__probe_h006_gate_typebreak.luau`, a
`--!strict` module whose function is annotated `(): number` and returns a
string. Created and deleted by hand; tree shown clean below.

    $ printf -- '--!strict\nlocal M = {}\n\nfunction M.count(): number\n\treturn "not a number"\nend\n\nreturn M\n' > src/shared/__probe_h006_gate_typebreak.luau
    $ bash scripts/gates.sh --gate typecheck

    === gate: typecheck (required) ===
    Created sourcemap at sourcemap.json
    [INFO] Loading definitions file: @roblox - globalTypes.d.luau
    [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
    [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc
    c:\...\src\shared\__probe_h006_gate_typebreak.luau [game/ReplicatedStorage/Shared/__probe_h006_gate_typebreak](5,2): TypeError: Expected this to be 'number', but got 'string'

    --- gate summary ---
    FAIL         typecheck (2s, exit 1) -> .claude/state/gate-logs/typecheck.log
    1 required gate(s) failed.

**A correction to the dispatch, measured.** A real type error does **not** make
`luau-lsp` emit `[ERROR]`; it emits `TypeError:` and exits **1** on its own, so
the gate fails on the exit code and the `awk` filter is not what catches it.
The `[ERROR]` filter exists for the *other* failure - a degraded analysis where
`luau-lsp` exits **0** - which is probed separately at 3b, because this story
moved `$GATE_TYPE_TARGET` into that very pipeline and the filter had not been
watched to fire since.

**Reverted:** `rm -f src/shared/__probe_h006_gate_typebreak.luau`, then

    $ bash scripts/gates.sh --gate typecheck
    analyze over 7 files
    PASS         typecheck (2s, observed 7)

---

### 3b. `typecheck` - the `[ERROR]` filter, on a tool that exits 0

**Broken:** the definitions flag, in the gate line itself, through `mutate.sh`
so the restore is verified.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@--definitions=globalTypes.d.luau --base-luaurc@--definitions=nosuch.d.luau --base-luaurc@' \
        -- bash scripts/gates.sh --gate typecheck

    === gate: typecheck (required) ===
    Created sourcemap at sourcemap.json
    [INFO] Loading definitions file: @roblox - nosuch.d.luau
    [ERROR] Failed to read definitions file nosuch.d.luau. Extended types will not be provided
    [WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
    [INFO] Loading Luau configuration from c:\Users\ryanc\Projects\first-roblox\.luaurc

    --- gate summary ---
    FAIL         typecheck (0s, exit 1) -> .claude/state/gate-logs/typecheck.log
    1 required gate(s) failed.

`luau-lsp` analysed the whole of `src` with no Roblox types, found nothing
wrong and would have exited 0. The `awk` filter is the only thing that turned
that into a failure, and it still does with the target in a variable.

**Reverted:** by `mutate.sh` - *"restored (verified byte-for-byte against
.claude/state/mutations/.claude_harness_project.conf.20260916T190914Z.4987.bak)"*.

---

### 4. Liveness: a gate whose tool read nothing

This is the half the story rewrote, and the reason `evidence` lines exist on
this stack: *exit 0 is not proof of work*. Both probes point a gate at `docs/`,
a directory with no `.luau` file in it, through `mutate.sh`.

**4a. `format` (optional):**

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@stylua --check -v src tests lune@stylua --check -v docs@' \
        -- bash scripts/gates.sh --gate format

    === gate: format (optional) ===
    stylua --check -v docs 2>&1 | awk '...'; test "${PIPESTATUS[0]}" -eq 0
    stylua over 0 files

    --- gate summary ---
    WARN         format (0s, ran but produced no evidence of work: expected /stylua over [1-9][0-9]* files/, optional)

Exactly the BOOT-001 design, and exactly what `## Handoff` finding 2 warned the
obvious implementation would lose: the command **exits 0** and prints a count
the evidence regex refuses, rather than dying on `grep -c`'s empty count with an
opaque `exit 1`. `awk` counts to 0 and exits 0 where `grep -c` counts to 0 and
exits 1.

**4b. `lint` (required), so the severity is visible too:**

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@${GATE_LINT_TARGET:=src tests lune}@${GATE_LINT_TARGET:=docs}@' \
        -- bash scripts/gates.sh --gate lint

    0 errors
    0 warnings
    0 parse errors
    selene over 0 files

    --- gate summary ---
    FAIL         lint (0s, ran but produced no evidence of work: expected /selene over [1-9][0-9]* files/) -> .claude/state/gate-logs/lint.log
    1 required gate(s) failed.

`selene` over a directory with no Luau in it exits 0 and says `0 errors` - the
silent-zero this stack has - and the gate fails anyway. The counter also
survived an empty target and printed `0` rather than exiting 1, which is
BOOT-001's `case`-rather-than-`grep` invariant still holding with the pathspec
now in a variable.

**4c. `typecheck` is different and is recorded rather than forced.** Pointed at
`docs`, the gate fails on the tool before the count: `luau-lsp` prints
`error: no files provided` and exits 1, so the verdict is
`FAIL typecheck (2s, exit 1)`, not *"no evidence of work"*. BOOT-001 measured
the same behaviour and warned against relying on it, which is why the counted
evidence is there as well.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's@${GATE_TYPE_TARGET:=src}@${GATE_TYPE_TARGET:=docs}@' \
        -- bash scripts/gates.sh --gate typecheck

    Created sourcemap at sourcemap.json
    [INFO] Loading definitions file: @roblox - globalTypes.d.luau
    error: no files provided

    --- gate summary ---
    FAIL         typecheck (2s, exit 1) -> .claude/state/gate-logs/typecheck.log

**Reverted:** all three of 4a, 4b and 4c by `mutate.sh`, each reporting
`restored (verified byte-for-byte against ...bak)`.

---

### After every probe

    $ git status --porcelain
     M .claude/harness/project.conf
     M .github/workflows/gates.yml
     M docs/backlog/stories/HARNESS-006.md
    ?? .claude/tests/project-counters.test.sh

    $ git diff -- .claude/tests/        # empty - tests frozen in GATES too
    $ ls .claude/state/mutations/       # log, and no .bak: every restore verified

No floor moved, no gate was added or removed, and no scratch file survives. The
three gates are the ones `## GREEN: control values confirmed` recorded at
38 / 38 / 7.

## Notes

**Mutations the orchestrator should run at acceptance**, against the shipped
`project.conf`. All three go through `bash scripts/mutate.sh
.claude/harness/project.conf '<expr>' -- bash .claude/tests/<suite>`, which
restores the file and verifies the restore; `sed -i` on it is working around the
lock even though the lock would allow it here (law 5, and see the Contract).

1. **Narrow the `format` target back to `src`.** Predicted: AC-1 goes red alone,
   reporting 7 where the unnarrowed tree gives 38. Run this one first — it is the
   defect the story exists for, and it is the mutation today's command survives.
2. **Put the `format` counter back behind a bare pipe**, so the pipeline's exit
   status is `grep`'s. Predicted: the unformatted-file case goes red and the
   counting cases stay green. If it goes green, the pipefail trap has no test and
   the story has shipped a gate that passes on unformatted code — which is worse
   than what it set out to fix.
3. **Revert `--cached --others --exclude-standard` to bare `git ls-files`** in the
   `lint` counter. Predicted: AC-4 goes red alone. If AC-4 stays green it was
   written against a file that happened to be tracked, and the `ROUND-005` symptom
   is still untested.

**Do not raise any floor in this story.** Out of scope, and a floor raised in the
same commit as a counter change makes it impossible to say which of the two moved
a number.

**Where this came from.** Closing `EPIC-00` (see that epic's `## Closed`), whose
goal paragraph is the argument for this story: on this stack *"exit 0 is not proof
of work - it is the absence of a complaint, and a tool with nothing to do does not
complain."* Three of the four counters that exist to answer that were not
answering it.

---

## REVIEW: the PR, and its CI

**PR:** https://github.com/ryanczhang7/first-roblox/pull/8
**Commit:** `dc56a74`. Both required checks pass.

    boundaries   pass   7s      actions/runs/35139688203
    gates        pass   1m14s   actions/runs/35139688204

### The portability claim, settled on Linux rather than asserted

This is the check that mattered, and it is the reason the anchor is
`^debug: formatted ` rather than a path shape. `stylua -v` prints
`src\shared\Clock.luau` on Windows and `src/shared/Clock.luau` on Linux; every
count in this story was measured on Windows. From the CI log:

    [13/15] project-counters ok (13s)
    project-counters: 40 passed, 0 failed
    15 harness suite(s) passed in 48s.
    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (3s, observed 7)

**38 / 38 / 7 on `ubuntu-24.04`, identical to the Windows measurements**, with all
40 assertions green. A counter built on `stylua`'s own output could have been a
Windows-only fact; it is not.

### The new toolchain dependency, exercised

`scripts/selftest.sh` needed only bash and git until this story. The CI run above
is the first in which it shells out to `stylua`, `selene`, `rojo` and `luau-lsp`,
and it passed because the `Harness self-test` step follows the toolchain install
in `gates.yml`. That ordering is now a hard requirement rather than a
convenience, and the comment in that workflow says so — corrected in this same
commit, because the moment the dependency is created is the only moment anyone
will connect the two.

The whole harness suite runs in **48 s** on CI against 491 s locally, so the new
suite costs CI almost nothing: 13 s of it.

### Timings

`project-counters` is 13 s on CI and 12.9 s locally — the one suite whose cost is
dominated by real tool invocations rather than by bash, and therefore the one
that does not benefit from the runner being faster. No `ci-factor` line is
warranted: `coverage`, the gate that usually motivates one, is unconfigured on
this stack, and nothing here is near a timeout.
