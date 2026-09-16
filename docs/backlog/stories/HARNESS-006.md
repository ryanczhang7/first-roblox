---
id: HARNESS-006
title: A gate's file count is what the tool read, not a list beside it
slug: a-gate-s-file-count-is-what-the-tool-rea
epic: 
type: chore
status: todo
phase: PLANNED
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

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

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
