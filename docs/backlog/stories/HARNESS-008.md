---
id: HARNESS-008
title: The fast loop cannot see a harness suite it just broke
slug: the-fast-loop-cannot-see-a-harness-suite
epic: 
type: chore
status: in-review
phase: REVIEW
branch: story/HARNESS-008-the-fast-loop-cannot-see-a-harness-suite
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`SEAT-001` reached CI with **11 red assertions** while every local signal was
green. Not a subagent error and not a missed step - the per-story procedure was
followed exactly, and it cannot see this class of failure.

`bash scripts/gates.sh` and `bash scripts/gates.sh --fast` **never invoke
`.claude/tests/*`**. Checked, not inferred:

    $ grep -nE 'selftest|\.claude/tests' scripts/gates.sh
    (no output)

The harness suites run only from `scripts/selftest.sh` and `scripts/ci-local.sh`,
and neither is part of RED or GREEN. So a product story that changes the project
tree can break a harness suite and every local gate stays green until CI says
otherwise.

**The concrete instance.** `.claude/tests/project-counters.test.sh` pins this
project's `.luau` file counts and asserts them against the **real tree** -
deliberately, because it tests `project.conf`'s counters against the real
toolchain. `SEAT-001` added one source file and four test files, so 38 became 43
and 7 became 8. The suite went `29 passed, 11 failed`; `lune run test` stayed
`197 passed, 0 failed` and all five gates passed. CI run `35179368944` is the
first thing that said otherwise, and it is left in PR #10's history as the
artefact.

**This recurs.** Any story adding a `.luau` file trips it, regardless of how
those expectations are computed - which is why `HARNESS-006`'s literals are the
symptom and the detection gap is the defect.

**Which required gate would fail if this story's artifact broke:** the one it
adds. That is circular by construction - a story whose artifact IS a gate - so
AC-5 breaks what the new gate guards and watches it fail, and the harness suites
under `scripts/selftest.sh` in CI's required `gates` job are the second defence,
as they were for `HARNESS-006` and `HARNESS-007`.

## Acceptance criteria

- **AC-1** - Given the set of harness suites in `.claude/tests/`, when each is
  examined for whether it reads the **real project tree** rather than a fixture,
  then the answer is recorded in the story with the evidence for each, and the
  set is non-empty.
  *Semantics:* this is the criterion the rest rests on. A suite that only drives
  a `make_fixture` sandbox cannot be broken by a product story; one that reads
  `git ls-files` over `src/` can. The distinction decides what belongs in the
  fast loop, and guessing it defeats the story.
- **AC-2** - Given a project story that adds a `.luau` file under `src/`, when
  `bash scripts/gates.sh --fast` is run, then it **FAILS**, naming the harness
  suite that broke.
  *Control:* on today's tree `--fast` passes in exactly that situation, and
  **must** fail this. This is the `SEAT-001` incident, reproduced as a test.
- **AC-3** - Given the same, when `bash scripts/gates.sh` (full) is run, then it
  also fails, and the failure is recorded in `## Gate results` like any other.
- **AC-4** - Given a tree in which no harness suite is broken, when
  `bash scripts/gates.sh --fast` is run, then it passes and the new gate reports
  evidence of work - a count of assertions or suites actually run.
  *Control:* a gate that ran nothing must fail its `evidence` line. `stack.md`
  section 2's rule applies here as everywhere: exit 0 is the absence of a
  complaint, not proof of work.
- **AC-5** - Given the new gate, when the thing it guards is broken on purpose,
  then it has been **observed to fail** and the output is in `## Gate probes`.
- **AC-6** - Given the fast loop's cost, when the new gate is timed, then RED and
  GREEN remain usable: the added wall time is recorded in the story and is
  **under 30 s** on this machine, **measured under a stated machine state**.
  *Semantics:* the whole `selftest.sh` is 10-55 minutes here, so "run everything
  in `--fast`" is not the answer and this criterion is what rules it out. The
  band is a budget, not a measurement to be widened later: if the only honest
  implementation exceeds it, that is a finding to raise, not a number to move.
  *The denominator - added in PLANNED by PO decision 1, before the criteria
  froze:* "on this machine" is not a constant, and the gap is not small. The
  same suite, unchanged, measured **12.9 s** (`HARNESS-006`), **20.4 s** (today,
  quiet) and **83-110 s** (today, with a game running) on this one machine. A
  bare number is therefore a measurement of the load, not of the gate. The
  recorded measurement carries three things or it is not a measurement:
    1. **the machine state, with its evidence** - no interactive or GPU load,
       shown rather than asserted (`(Get-CimInstance Win32_Processor).LoadPercentage`
       and the top processes by CPU, or the fork-cost probe in PO decision 1);
    2. **at least two runs, and their spread.** A spread above ~10 % means the
       machine was not quiet and the number is void - under load the two runs
       here were 83 s and 110 s, a 33 % spread, against 3 % when quiet;
    3. **a cross-check against the same suite's per-suite timing in the PR's CI
       log** - a second machine under a fixed policy, where `HARNESS-006`
       measured 13 s. A local number far from CI's is a claim about the laptop.
  This changes what must be *shown*, not what must be *true*: the budget is
  still 30 s and is still not to be widened.

## Amendments

**AC-6, amended during PLANNED on 2026-09-17. Approved by the user (the product
owner for this repo), who chose it from a stated set of options before RED was
dispatched.**

- **Which AC:** AC-6.
- **What it said:** "the added wall time is recorded in the story and is **under
  30 s** on this machine."
- **What it says now:** the same, plus "**measured under a stated machine
  state**", and a three-part standard for what the recorded measurement must
  carry - the machine state with its evidence, at least two runs with their
  spread, and a cross-check against the PR's CI log. **The 30 s budget is
  unchanged and is still not to be widened.**
- **Why:** "on this machine" had no denominator. The same suite, unchanged,
  measured 12.9 s (`HARNESS-006`), 20.4 s (2026-09-17, quiet) and 83-110 s
  (2026-09-17, with a game running) on the one machine. A bare number recorded
  against that criterion would have measured the load, not the gate. The full
  evidence is in `## Notes`, PO decision 1.

**Why this entry exists at all, which is itself a correction.** PO decision 1
originally asserted that no `## Amendments` entry was owed, on the grounds that
`CLAUDE.md` and `rules.md` freeze criteria "once a story leaves PLANNED" and the
edit was made while the story was still in PLANNED. **That reading is wrong
about what CI enforces.** `scripts/check-boundaries.sh:301-312` compares the
`## Acceptance criteria` section against the base branch and does not know, and
says it cannot know, which phase an edit happened in:

> 3d. Acceptance criteria are frozen: any difference from the base branch needs
> an `## Amendments` entry, **whatever phase the edit was made in**. CI cannot
> see when in the branch's history an edit happened, only that it did.

The story file was already on `main` (committed as "HARNESS-008 filed"), so the
"new in this PR" escape does not apply. Reproduced by running the tool:

    $ bash scripts/check-boundaries.sh
    FAIL  story HARNESS-008: ## Acceptance criteria differ from origin/main with
          no ## Amendments entry. Criteria are frozen once a story leaves
          PLANNED; record which AC changed, what it said, what it says now, who
          approved it and why.

**Found by the RED test-developer, which escalated it rather than resolving it
or editing the criteria back.** That was the correct move and this entry is the
resolution. The general lesson, worth more than this instance: *a story filed on
`main` has its criteria frozen from the moment it is filed, not from the moment
it leaves PLANNED.* The prose and the tool disagree, and **the tool is what gates
the PR.**

## Contract

Changes `.claude/harness/project.conf` and adds tests. **No change to
`.claude/tests/project-counters.test.sh`'s expectations** - `HARNESS-006` is DONE
with frozen criteria, and this story is about *detection*, not about how those
numbers are computed.

### Why `project.conf` is the right home, checked

`refresh-harness.sh` lists `.claude/harness/project.conf` as **LEFT untouched**
(project-owned), so a gate added there survives a harness refresh. `gates.sh`
itself is REPLACED and must not be edited. Verified during the 19 -> 30 refresh:
`project.conf` came through unchanged with `HARNESS-006`'s counters intact.

### The shape expected, not mandated

A `gate` line running the harness suites that AC-1 identifies - most likely just
`.claude/tests/project-counters.test.sh`, which is the one suite that reads the
real tree. **Its cost is 20.4 s on this machine quiet**, re-measured in PLANNED;
the "~13 s locally" this paragraph used to carry was `HARNESS-006`'s figure
against a smaller tree and is no longer the number. See `## Notes`, PO decision 2
for the measurement and the baseline it sits against. Something like:

    gate | harness | required | . | bash .claude/tests/project-counters.test.sh
    evidence | harness | [1-9][0-9]* passed, [0-9]+ failed

**Do not mark it `slow`.** A `slow` gate is excluded from `--fast`, which is
precisely the hole this story exists to close, and marking it slow to make the
cost criterion pass would be the gate equivalent of widening a tolerance.

**If AC-1 finds more than one qualifying suite**, the gate runs all of them and
AC-6's budget is measured over the set. If the set turns out to be large enough
that AC-6 cannot be met honestly, **stop and report** - that is a PO decision
about what the fast loop is for, not something to solve by trimming the set.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1 | **Oracle-free** | There is no list anywhere of which suites read the real tree. Derive it, show the evidence per suite, and say how you decided. |
| AC-2, AC-3, AC-4, AC-5 | **Mechanical, with controls** | Each control is named in the criterion. |
| AC-6 | **Settled by measurement** | Time it and record the number. |

**Test-only dependencies:** none. Bash, awk, coreutils.

### Four mechanisms, read out of the source in PLANNED

Pinned here so RED does not rediscover them late. **Each is a claim, not
scripture** - they were read out of `scripts/gates.sh` and `scripts/doctor.sh`,
and only the ones marked *executed* were run. A cheap check that contradicts one
is a finding to report, not a rule to obey.

1. **A bare `bash scripts/gates.sh` rewrites the active story's `## Gate
   results`.** `scripts/gates.sh:677` skips recording only when `--gate`,
   `--required` or `--fast` is set; otherwise it calls `record_in_story` against
   whatever `load_state` says is active. *Consequence:* **no test in this story
   may invoke a bare `bash scripts/gates.sh`.** While HARNESS-008 is the active
   story that clobbers this story's own gate record - the stamped evidence
   `check-boundaries.sh` verifies against a tree hash. This is why **AC-3 is a
   deferred verification owned by GATES, not an automated test**; see that
   section. *Read, not executed.*
2. **`--gate` filters before `--fast` does.** `scripts/gates.sh:259` applies the
   `$ONLY` filter, and the `slow`/`--fast` skip is at `:266` - after it. So
   `--fast --gate harness` runs `harness` **iff** it is not marked `slow`, and
   skips it when it is. That makes `## Notes` mutation 1 ("mark the gate slow,
   AC-2 goes red") observable for the cost of one gate instead of a whole
   `--fast` run. *Read, not executed - verify before relying on it.*
3. **`scripts/doctor.sh:74` takes the first token of every gate command and
   requires it on PATH.** A `gate | harness | ... | bash .claude/tests/...` line
   makes `doctor.sh` check `bash`. Harmless, but `doctor.sh` is a caller and must
   stay green. *Read, not executed.*
4. **`project-counters.test.sh` writes probe `.luau` files into `src/` while it
   runs**, and removes them from an `EXIT` trap (`__probe_h006_untracked.luau`,
   `__probe_h006_unformatted.luau`, `src/build/__probe_h006_ignored.luau`).
   Once it runs *inside* `gates.sh` this matters twice: a run killed mid-flight
   leaves probes behind that then poison the `format`/`lint`/`typecheck` counts
   on the next run, and the tree hash `gates.sh` stamps into `## Gate results` is
   only correct because cleanup has already happened. Gates run sequentially, so
   the normal path is safe; the abnormal one is worth a line in the handoff.
   *Executed: the suite ran four times during PLANNED and `git status` was clean
   after each.*

### How AC-2's "a project story adds a `.luau` file" is reproduced

The counters gate counts with `git ls-files --cached --others
--exclude-standard`, which includes **untracked** files. So simply creating an
untracked `.luau` under `src/` raises the count and makes the literals stale -
that *is* the SEAT-001 incident, and it is why AC-2 is cheap to reproduce. Two
traps come with it, both of which RED owns:

- The suite already keeps its **own** probes and has expectations that account
  for them (`AC-2/AC-4: a .luau file on disk but not yet tracked by git is
  counted`). A second probe added by this story's tests is one *more*, so the
  arithmetic is not "the literal + 0".
- Creating the probe while the counters suite is running is a race. Nothing runs
  these concurrently today; do not introduce something that does.

The probe file naming convention in `rules.md` (`__probe_*.*`) applies: it makes
`paths.conf` classify the file as `test`, which is what lets RED write it at all.

### The phase lock enforces nothing here

`.claude/harness/project.conf` and `.claude/tests/**` both classify as `harness`,
writable in every phase - as in `HARNESS-006` and `HARNESS-007`. The RED/GREEN
split is honoured, not enforced; the orchestrator reads the diff at each
boundary.

### This story does not bump `VERSION`

Same reason as `HARNESS-007`: the check is scoped to non-story branches on
unbootstrapped repos, and this is neither. `SEAT-001` changed `project.conf` on a
story branch and `check-boundaries.sh` passed without one.

## Callers of what this story changes

This story changes no exported signature, so the usual "`rg` every caller" has
no function to chase. It changes something with the same hazard, though: it adds
a **gate id** to `.claude/harness/project.conf`, and several things enumerate
gates out of that file. Checked against the tree in PLANNED, before dispatch.

Everything that reads `project.conf` at all:

    $ grep -rln "project.conf" scripts/ .claude/tests/ .claude/hooks/ .github/
    scripts/check-boundaries.sh      .claude/tests/boundaries.test.sh
    scripts/dev.sh                   .claude/tests/doctor.test.sh
    scripts/doctor.sh                .claude/tests/gate-reminder.test.sh
    scripts/gates.sh                 .claude/tests/lib.test.sh
    scripts/refresh-harness.sh       .claude/tests/profiles.test.sh
    scripts/task.sh                  .claude/tests/project-counters.test.sh
    .claude/hooks/lib.sh             .claude/tests/refresh.test.sh
    .github/workflows/gates.yml      .claude/tests/_lib.sh

Of the suites, only one reads the **real** one - the rest build fixtures, which
is the same distinction AC-1 is about:

    $ grep -n 'REPO_ROOT.*project.conf\|CLAUDE_PROJECT_DIR.*project.conf' .claude/tests/*.test.sh
    .claude/tests/project-counters.test.sh:46:CONF="$REPO_ROOT/.claude/harness/project.conf"

So the list RED must confirm against the tree is short, and two entries on it
are load-bearing:

| Caller | What it will now see | Judged |
|---|---|---|
| `scripts/doctor.sh:74` | a fifth gate whose first token is `bash` | must stay green; `bash` is on PATH by construction |
| `.claude/tests/project-counters.test.sh:301` | nothing - its all-gates loop is hardcoded `for g in format lint typecheck` | **no collision**, and that is why it is safe for this gate to run that suite |
| `scripts/gates.sh` | one more `gate` line, `required`, not `slow` | the artifact itself |
| the other 13 | fixtures they write themselves | unaffected |

**RED's handoff must state that this list was re-checked against the tree**, not
that it was read here. The counters suite in particular is the one file this
story both *runs as a gate* and *depends on not changing*; a hardcoded loop that
quietly became dynamic would make the new gate recurse into its own manifest.

## Deferred verifications

Falsifiable conditions RED **cannot** run, each with the phase that owns it. RED
is expected to **decline** these in its handoff, not to claim them.

- **DV-1 (AC-5, owner: GATES).** With the new gate present and passing, breaking
  what it guards must make it **fail**. Break it by making the counters suite's
  literals stale the way a product story does - add one untracked `.luau` under
  `src/` - and run the gate. Condition: the gate exits non-zero and its output
  names `project-counters`. Paste the failure and the revert into `## Gate
  probes`. RED cannot run this: in RED the gate does not exist.
- **DV-2 (AC-2, owner: GATES).** With the gate marked `slow`, `gates.sh --fast`
  must **stop running it** and so must stop failing on that stale tree. This is
  `## Notes` mutation 1 and it is the one that matters, because `slow` is the
  tempting way to buy AC-6. Use `bash scripts/mutate.sh .claude/harness/project.conf
  '<expr adding a slow line>' -- <the --fast command>`. Condition: with the
  mutation the run passes (or reports `harness` skipped); restored, it fails.
- **DV-3 (AC-4, owner: GATES).** The **`evidence` line must fire** - "ran but
  produced no evidence of work" - rather than the gate passing quietly.
  Condition: the gate FAILS **for the evidence reason specifically**, quoted.

  > **The premise this entry shipped with was false, and RED caught it.** It
  > originally said to point the gate's command "at a suite that does not
  > exist". That does not exercise the evidence path at all: a missing suite
  > exits 127, and `scripts/gates.sh:420` tests `rc -ne 0` **first**, with the
  > evidence check an `elif` at `:432` that a non-zero exit never reaches. The
  > mutation would have produced `FAIL harness (exit 127)` and been recorded as
  > if it had proved something about evidence.
  >
  > **The mutation must exit 0 while doing no work** - `... | true`, or
  > replacing the command with `true` outright. RED's handoff carries the
  > working form; use that, not this entry's original.
  >
  > This is the instruction-as-claim case from the orchestrator's own rules: the
  > PO named a mechanism it had read but not executed, and the subagent probed
  > it instead of following it. That is the behaviour to keep.
- **DV-4 (AC-3, owner: GATES).** A full `bash scripts/gates.sh` on a tree with an
  added `.luau` fails and records that failure in `## Gate results`. **This is
  deliberately not a test** - see `## Contract`, mechanism 1: a bare full run
  rewrites the active story's own gate record. It is satisfied by observing it
  once during this story's GATES phase, or `WAIVED` with the reason.
- **DV-5 (AC-6, owner: GATES).** The added wall time, measured to AC-6's amended
  three-part standard. RED cannot run it: there is no gate to time. The PLANNED
  baseline below is a *starting* point the story may read out, not the answer -
  AC-6 asks for the time added by the **shipped** gate.

### RESULTS - all five run in GATES by the orchestrator, none waived

RED declined all five in its handoff, as asked, and did not claim any. Each was
then run against the shipped gate. **Full output is in `## Gate probes`**; this
is the index and the verdict.

| DV | AC | Owner | Status | The observation |
|---|---|---|---|---|
| **DV-1** | AC-5 | GATES | **PASS** | one untracked `.luau` under `src/` -> `FAIL harness (27s, exit 1)`, `1 required gate(s) failed.`, output names `project-counters: 27 passed, 13 failed`. Probe 1. |
| **DV-2** | AC-2 | GATES | **PASS** | marked `slow` -> `--fast skipped: harness`, `All required gates passed (0 ran...)`, exit 0 on a tree that should have failed. Restored, verified. Probe 2. |
| **DV-3** | AC-4 | GATES | **PASS** | command -> `true` (exit 0, no work) -> `FAIL harness (0s, ran but produced no evidence of work: expected /project-counters: .../)`. **With the corrected mutation**, not the false premise this entry shipped with. Probe 3. |
| **DV-4** | AC-3 | GATES | **PASS** | full `gates.sh` on the probed tree -> every other gate PASSED (`format 44`, `lint 44`, `typecheck 9`), only `harness` FAILED, and `result: fail` was recorded in `## Gate results`. Probe 4. |
| **DV-5** | AC-6 | GATES | **PASS locally; CI half owed at DONE** | four quiet runs: **17/20/18/22 s**, worst 22 s against a 30 s budget. Machine state evidenced by the fork probe (51 ms/fork, vs 359 ms loaded, when the same gate read 27 s and 33 s). CI cross-check owed at DONE. |

**Nothing here is `WAIVED`.** DV-3 is the one worth re-reading: the entry as the
PO wrote it named a mutation that could not have exercised the path it claimed
to test, RED refused to take it on faith, and the corrected mutation then fired
the evidence line exactly as intended. The original would have produced
`FAIL harness (exit 127)` and been filed as proof of something it never touched.

## Out of scope

- **How `project-counters.test.sh` computes its expectations.** Deriving them
  from `scripts/classify.sh --list` instead of literals is a real follow-up and a
  separate story; it changes what `HARNESS-006` AC-7 asserts, and `HARNESS-006`
  is DONE. **Detection first**: with this story landed, the literals going stale
  is a red `--fast` in RED instead of a red CI job.
- **Putting the whole `selftest.sh` in `--fast`.** AC-6 rules it out; 10-55
  minutes is not a loop anyone runs.
- **The harness suites that only drive fixtures.** A product story cannot break
  them, and adding them buys cost without detection.
- **`ci-local.sh`.** It already runs the selftest and would have caught this. It
  is not part of the per-story loop and this story does not make it one.

## Model guidance

Planned by `bash scripts/plan.sh write HARNESS-008` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `fable` | the measured case. With a partitioned contract to work from, the brief carries the judgement and the weaker model writes sharper negative controls than the stronger one did without it |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- **PLANNED / `lead-po` — resolved `claude-opus-5`** (Opus 5), as planned. The
  session reported its own model by name; no override was in play.
- **RED / `test-developer` — dispatched with an explicit `model: fable`
  override**, as `models.conf` plans for RED. The override was passed on the
  dispatch itself rather than left to the agent definition's `model:` field, so
  the resolved model is a fact of this dispatch and not of whatever the session
  default happened to be. The policy's precondition was checked before taking
  it: `models.conf` moves RED to the weaker model **when the brief it depends on
  exists**, and the partitioned `## Contract`, `## Callers` and
  `## Deferred verifications` sections were written before dispatch.

  **Resolved: Fable 5.1 (`claude-fable-5-1`), self-reported by the agent,
  matching the plan. Verdict: the policy held, and it held in the way the
  policy claims it does.** The brief carried the judgement and the weaker model
  produced sharper work than the brief it was given:
  - it **found the first RED run passing two assertions vacuously** (9 passed,
    not 7) - "names no fixture-only suite" is trivially satisfied by an *empty*
    command, and "did not skip" by an error output containing no skip line -
    and made both conditional on the gate existing, rather than leaving two
    needles that could not fail;
  - it added an **instrument self-check** for its own needle, which is the
    third defence `rules.md` asks for and the only one that catches a needle
    whose negation also matches;
  - it **probed two mechanisms the PO had named rather than following them**,
    and one of them was wrong (DV-3, see below);
  - it **escalated a contradiction in the PO's own process reasoning** instead
    of resolving it quietly or editing the criteria back.
  Three of those four are the specific failure modes `rules.md`'s
  non-negotiables exist to catch. None was prompted by name.
- **GREEN / `feature-developer` — dispatched with an explicit `model: opus`
  override**, as `models.conf` plans. GREEN never moves to the weaker model:
  its failure mode is reaching green by weakening a test, which is the one
  thing this harness exists to prevent. **Resolved: Opus 5 (`claude-opus-5`),
  self-reported.**

  *Verdict: the policy's stated reason for pinning GREEN to the stronger model
  is exactly what happened, in the negative.* GREEN was handed a suite it could
  not turn green, and the cheap ways out were all available: bend the gate line
  to satisfy l.174 (which yields a gate `gates.sh` calls **unconfigured** - no
  gate at all), or edit the frozen test. It took neither, enumerated the line
  shapes to show none could satisfy both assertions, and reported. It also
  found a **passing** assertion that was passing for the wrong reason, which
  nothing forced it to look at. It additionally *strengthened* the evidence
  regex over the Contract's suggestion, unprompted, on the grounds the bare
  form was `unit`'s line verbatim and would be satisfied by any `_lib.sh`
  summary - and measured both forms against every control row to show the
  narrowing changed no behaviour.
- **RED (return 1) / `test-developer` — dispatched with `model: fable`**, as
  for the first RED. The brief is stronger here than in the first RED - both
  defects are stated, with the orchestrator's reproduction attached - so the
  policy's precondition ("the brief it depends on exists") is met more fully
  than before. *Verdict: pending.*
## Notes

### PO decisions taken in PLANNED

**1. AC-6 was amended in PLANNED, to give "on this machine" a denominator.**
Approved by the user before RED was dispatched.

> **Corrected after RED.** This decision originally read "so no `## Amendments`
> entry is owed; PLANNED is the last phase in which that is true". **That was
> wrong**, and `scripts/check-boundaries.sh` refuses the PR on it: the check
> compares the criteria against the *base branch* and explicitly does not care
> which phase the edit was made in. The story was already on `main`, so its
> criteria were frozen from the moment it was filed. The entry now exists in
> `## Amendments`, with the tool's own output. RED escalated this instead of
> quietly editing the criteria; it was right and this note is the correction.

*What prompted it.* The first two timings of `project-counters.test.sh` taken in
PLANNED were **83 s** and **110 s** against AC-6's 30 s budget, and the first
reading of that was that AC-6 was unmeetable. It was not. The machine was the
variable:

    PS> (Get-CimInstance Win32_Processor).LoadPercentage
    100
    PS> Get-Process | Sort-Object CPU -Descending | Select-Object -First 3 Name, CPU, WS
    Name                              CPU         WS
    FortniteClient-Win64-Shipping  14052.296875  6397358080
    chrome                          6034.9375     144486400
    claude                          1689.390625   566132736

The corroborating evidence was a comparison of two recorded gate runs on the
same tree-shape, which showed a **uniform 6-9x** regression rather than anything
specific to this suite:

    HARNESS-006 (2026-09-16)   format 0s  lint 0s  typecheck  2s  unit  7s  build 0s
    SEAT-001    (2026-09-17)   format 2s  lint 3s  typecheck 12s  unit 63s  build 2s

and a fork-cost probe, which is the cheapest instrument for this and is the one
to reach for again:

    $ time (for i in $(seq 1 50); do printf 'x' | sed -e 's/x/y/' >/dev/null; done)
    real 0m22.008s     # loaded
    real 0m2.433s      # quiet - 440 ms/fork against 49 ms/fork

After the user closed the game, load fell to 54 % and the suite measured 20.1 s
and 20.8 s. So the criterion was never wrong about the gate; it was silent about
the machine, and a number taken on the wrong day would have been recorded as
fact. **Correction to the record:** the escalation this story nearly received -
"AC-6 cannot be met honestly" - was wrong, and it was wrong because the machine
state had not been checked before the timing was believed.

**2. The baseline, measured in PLANNED. RED and GREEN may read these out rather
than re-derive them.** All taken on the quiet machine, with `~/.rokit/bin` on
PATH.

| Measurement | Value | How |
|---|---|---|
| `project-counters.test.sh`, quiet | **20.1 s, 20.8 s** (mean 20.4, spread 3 %) | `time bash .claude/tests/project-counters.test.sh`, twice |
| the same, loaded | 83 s, 110 s (spread 33 %) | the runs PO decision 1 voids |
| the same, on CI | 13 s | `HARNESS-006`, CI run `35139688204` |
| `gates.sh --fast` today, **without** the new gate | **3 m 31.65 s wall** | `time bash scripts/gates.sh --fast` |
| the gates inside that run | **29 s total** (format 0s, lint 1s, typecheck 3s, unit 24s, build 1s) | the same run's own summary |
| projected `--fast` with the gate | ~3 m 52 s, i.e. **+9.7 %** | 211 s + 20.4 s |

The suite is **40 assertions, `40 passed, 0 failed`** on today's tree, run four
times during PLANNED with a clean `git status` after each.

**3. A finding this story does not fix, recorded so it is not rediscovered.**
Of `--fast`'s 211 s, the gates account for 29 s. The other **182 s - 86 % of the
fast loop - is `gates.sh`'s own startup**, which forks `sed`/`cut` several times
per line over a 521-line `project.conf`. That is why `gates.sh --list`, which
runs nothing, produced no output for over 60 s under load.

This is **out of scope and must stay so**: `scripts/gates.sh` is REPLACED
wholesale by `refresh-harness.sh`, so a fix here would be lost at the next
refresh, and it is an upstream harness defect rather than a project one. It is
recorded because it changes how AC-6's number should be *read* - a 20 s gate on
a loop that is already 3.5 minutes is a 9.7 % increase, not a doubling - and
because the next person to wonder why the fast loop feels slow should not have
to measure it again.

**4. No `required_gates` escalation is needed, checked.** The command for this
phase asks whether the only gate exercising the story's artifact is `optional`.
It is not, twice over: the gate this story adds is itself `required`, and the
artifact is `.claude/harness/project.conf` plus `.claude/tests/**`, which
classify as `harness`, not `source`. No `covers` line matches them -

    $ grep -nE '^covers *\|' .claude/harness/project.conf
    covers | lint      | src/**
    covers | typecheck | src/**
    covers | build     | src/**
    covers | unit      | src/shared/**
    covers | unit      | src/server/**

- so `gates.sh`'s "changed source only optional gates read" check is inert here.
`required_gates` stays `[]`.

**6. The orchestrator's verification of RED, run independently.** A subagent's
report is a claim. What was re-run here, with the PO's own inputs rather than
the subagent's:

| Claim | How it was checked | Result |
|---|---|---|
| `harness-gate: 7 passed, 22 failed` | ran the suite directly | **reproduced**, 1 m 8 s |
| the 22 fail for the *right* reason | grouped every failure reason | **all** on the gate's absence; `gates.sh` refusing `--gate harness` with exit 2 is the same cause. No timeout, no config error, no lint trip |
| the 7 passes pin no production behaviour | re-ran with `VERBOSE=1` and read them | **confirmed** - 3 preconditions, 2 probe git-state, 1 cleanup, 1 instrument self-check. None owes a `mutate.sh` probe |
| AC-1's central claim: only `project-counters` breaks | wrote **a different probe** (`src/shared/__probe_po_verify.luau`, not RED's) and ran the counters suite | **`27 passed, 13 failed`** - the exact count RED predicted, from an independent input; tree clean after |
| the new suite does not trip `lib.test.sh`'s shape scan over `.claude/tests/*.sh` - RED's own flagged risk | ran `lib.test.sh` with the new file present | **136 passed, 0 failed** |
| the `check-boundaries` escalation | read `check-boundaries.sh:301-312`, confirmed the story file exists on `main`, then **ran the tool** | **confirmed** - see `## Amendments` |
| DV-3's premise is false | read `gates.sh:420` vs `:432` at source | **confirmed** - the evidence check is an `elif` after `rc -ne 0`; exit 127 never reaches it |

**Admissibility, run by the orchestrator before leaving RED** - the question is
not pass/fail but whether these tests are admissible to the gates that will
judge them:

    All required gates passed (5 ran, 1 unconfigured, 0 known).
    PASS format (0s, observed 43)   PASS lint (0s, observed 43, floor 1)
    PASS typecheck (3s, observed 8) PASS unit (15s, observed 197, floor 197)
    PASS build (0s, observed 25103) real 2m33.435s

**All green is the correct result here, and it is the story's whole point.** The
new file is a `.sh` harness suite; no local gate reads it - `format`'s count is
still **43**, unchanged, because every gate target is `.luau`. The gate that
will judge it is `selftest.sh` in CI, and *that the fast loop cannot see it
today is the defect this story closes.* Read this run as the AC-2 control
holding one last time, not as a green light.

**One datum for AC-6, from these two runs.** `--fast` was **3 m 31 s** at the
PLANNED baseline and **2 m 33 s** here, both on the quiet machine - a **38 %**
spread with identical gate work (29 s vs 16 s of gates). The variance lives in
`gates.sh`'s fork-storm startup (PO decision 3), not in the gates. This is
direct support for AC-6's amended two-runs-and-spread requirement: a single
`--fast` timing would not have been a measurement.

**Not independently re-run:** RED's fixture verification of mechanism 2
(`--fast --gate` filtering before the `slow` skip). It *confirms* a PO claim
rather than contradicting one, and GREEN exercises it for real through the
suite's end-to-end block - where a wrong mechanism fails loudly and safely.
Recorded so nobody reads the row above as covering it.

**7. Rulings on RED's two recorded doubts, so GREEN and GATES do not reopen
them.**

*The gate id stays `harness`.* It is what the `## Contract` suggested, what the
suite pins, and what `--gate harness` reads. No change; GREEN uses `harness`.

*The new suite being a real-tree suite outside its own gate is accepted, and the
residual hole is benign.* RED is right that `harness-gate.test.sh` reads the
real tree and is not in the gate it adds - the same shape as the defect, one
level up. It is nonetheless the correct design, for two reasons:

1. **Including it would recurse** - the gate runs the suite, the suite runs the
   gate. RED guards that with `HARNESS_GATE_UNDER_TEST`, which turns the
   recursion into a named failure rather than a hang. Excluding it is not a
   compromise; it is the only consistent option.
2. **Nothing is lost by the exclusion.** The window in which `harness-gate`
   would go red is exactly the window in which a stray `.luau` has made
   `project-counters` stale - and in that window the `harness` gate is *already*
   failing `--fast` through `project-counters`. The second alarm would be
   redundant with the first, on the same cause, in the same run.

So the detection this story promises is intact: the case that reached CI in
SEAT-001 now fails the fast loop. `selftest.sh` and CI remain the backstop for
the suite itself, as they are today for `project-counters`. **Not a follow-up
story**; a property of the design, recorded so it is not mistaken for an
oversight.

**8. GREEN's claim that the frozen suite is defective, reproduced independently
by the orchestrator.** `rules.md` and the orchestrator's own rules require that
a claim *the contract is wrong* be reproduced on different inputs without
reusing the subagent's code, because it is the shape of claim an agent makes
when it wants to stop failing. GREEN's claim survived all three checks.

*Method: a synthetic conf of the PO's own making, with gate ids GREEN never
used, driving the function **extracted verbatim from the frozen suite** - the
code under test, not GREEN's scratch script.*

    $ cat /tmp/po_synth.conf
    gate | alpha | required | subdir | echo hello
    gate | beta | optional | . | echo two
    evidence | alpha | alpha over [0-9]+ files

    gate alpha 3           -> [required | subdir | echo hello]
    gate alpha 4           -> [subdir | echo hello]
    gate alpha 5           -> [echo hello]
    evidence alpha 3       -> [alpha over [0-9]+ files]
    --- what the field ACTUALLY is, per cut (gates.sh's method) ---
    cut -f3 -> [required]
    cut -f4 -> [subdir]

**1. The parser defect is real.** `conf_value` returns the remainder from field
`from` onward and never truncates at the next `|`. Correct for `evidence` f3 and
`gate` f5 - both genuinely *are* the remainder - and wrong for `gate` f3 and f4,
which this suite is the first to ask for.

**2. The unsatisfiability is real.** Enumerated every candidate line shape:

    ID       f3 (must be exactly "required")   f5 (must contain project-counters)   both?
    three    [required]                        [required]                           no
    four     [required |]                      []                                   no
    five     [required | . | bash .claude/...] [bash .claude/tests/project-...]      no

No line satisfies l.174 and l.196 together, and the only shape that satisfies
l.174 (`gate | harness | required`, nothing after) is one `gates.sh` reports as
**unconfigured**. So "make the test pass" here would have meant shipping no gate
at all. GREEN was right to refuse and report.

**3. The vacuous pass is real, and is the most valuable thing in this cycle.**
Demonstrated with `run_gate_cmd` copied verbatim and `GATE_CWD` set to what the
broken parser yields:

    GATE_CWD (as the broken parser yields it): [. | bash .claude/tests/project-counters.test.sh]
    cd: .../. | bash .claude/tests/project-counters.test.sh: No such file or directory
    RC=97   OUT=[]
    >>> l.332 assertion PASSES -- 'the gate command exits non-zero with the probe present'
    >>> ...while the gate command never ran at all. The needle cannot fail.

This is `rules.md`'s "an assertion's needle is part of the assertion" **at the
level of an exit code**, which none of the four recorded instances covers: `97`
from a `cd` that never ran the command is indistinguishable, to `[ "$RC" -ne 0 ]`,
from the suite genuinely going red. It would keep passing after the parser is
fixed, so the fix alone does not earn it - it must reject the `97` sentinel
explicitly, the way `BROKE` already rejects an all-green summary at l.324.

**The artifact is not in doubt.** Verified by the orchestrator on the shipped
config, independently of the suite:

    harness-gate: 23 passed, 6 failed        (was 7/22 in RED)
    PASS format (1s, 43)   PASS lint (0s, 43)   PASS typecheck (2s, 8)
    PASS unit (14s, 197)   PASS build (0s, 25103)   PASS harness (15s, observed 40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).   real 2m13.8s

The `harness` gate runs, is in the fast subset, and reports 40 assertions of
observed work. **The six failures are the instrument, not the artifact.**

**9. The "flaky suite" that was not, and the rule that follows from it.**

*The orchestrator raised a false alarm here and the correction is the point of
the entry.* Verifying the corrective RED, I ran the suite twice back to back and
got `27 passed, 2 failed` then `29 passed, 0 failed` on an unchanged tree, and
concluded in writing that the suite was flaky at roughly one run in three. **That
was wrong.** A suite about to become a required gate being non-deterministic
would have been disqualifying, so it is worth recording exactly why it was wrong.

*The diagnosis.* Running `project-counters` alone six times gave
`27 passed, 13 failed` **six times out of six** - perfectly deterministic - with
`?? src/shared/__probe_h008_added.luau` in the tree each time. That file is
`harness-gate`'s own probe, and with it present `project-counters` is *correctly*
red: 43 files became 44. The stray was 208 s old and had appeared **after** my
own runs had finished clean, so something else had written it.

*The cause: two agents on one checkout.* The corrective RED still had a suite run
in flight while the orchestrator was running its verification. The RED agent
reached the same conclusion independently and from the other side - it found a
`required -> optional` mutation in `.claude/state/mutations/log` at `134913Z`
that it had not run (that was the orchestrator's probe A) and a second
`harness-gate.test.sh` with a nested `gates.sh` in `ps`.

*Settled, with nothing else running and the strays removed:*

    --- run 1 ---  harness-gate: 29 passed, 0 failed   tree after: []
    --- run 2 ---  harness-gate: 29 passed, 0 failed   tree after: []
    --- run 3 ---  harness-gate: 29 passed, 0 failed   tree after: []
    procs matching harness-gate|project-counters: 0

**The rule.** `harness-gate.test.sh`, `project-counters.test.sh`, `gates.sh` and
`mutate.sh` all read and write the **one real tree**, and none of them is
reentrant. Two of them at once is not a flake, it is a collision, and its
signature is the pair `the gate command exits 0 on the unmodified tree` /
`its output carries project-counters' own summary line`. Before believing a red
from any of them: `ps | grep -E 'harness-gate|project-counters'`, and
`git status --porcelain -- src` for a stray `__probe_*`.

*What this is not.* It is not a reason to add a lock. That is new behaviour, it
belongs to a later story, and nothing in the normal per-story loop runs two of
these at once - only an orchestrator verifying a subagent's work while the
subagent is still running, which is this entry's actual lesson: **wait for the
agent to be done before verifying it.**

**10. Ruling on the RED agent's open question: the `126`/`127` widening stays.**
The return specified "non-zero and not the `97` sentinel"; the agent also made
the assertion reject `126` and `127`, and flagged the widening rather than
burying it. **Accepted.** `bash nope.test.sh` exits 127 from bash itself, which
is the same never-ran class as the suite's own `cd` sentinel arriving from the
other side; it is probed (probe C); and `project-counters` exits only 0 or 1 via
`summary`, so no conforming run can collide with any of the three. It constrains
nothing GREEN chooses.

**5. The epic done-when check is vacuous for this story.** `epic:` is empty and
`type: chore`; there is no epic promise for this story to close or to leave
short. Recorded rather than skipped silently.

### Mutations for acceptance

**Mutations for acceptance**, via `bash scripts/mutate.sh`:

1. Mark the new gate `slow`. Predicted: AC-2 goes red - `--fast` stops running
   it. This is the mutation that matters, because marking it slow is the tempting
   way to make AC-6 pass.
2. ~~Point the gate's command at a suite that does not exist. Predicted: AC-4's
   evidence control fires rather than the gate silently passing.~~
   **Withdrawn - the premise is false.** A missing suite exits 127 and
   `gates.sh:420` reports that as a plain FAIL; the evidence check at `:432` is
   an `elif` it never reaches. Make the command **exit 0 while doing no work**
   instead (`... | true`). See DV-3 and RED's handoff.

**Where this came from.** `SEAT-001`'s `## PO ruling on the return to RED from
REVIEW`, which records the incident, the two candidate fixes and why neither was
done inside that story.

## Test plan

One suite, `.claude/tests/harness-gate.test.sh`, discovered by
`scripts/selftest.sh`'s glob and run with `bash .claude/tests/harness-gate.test.sh`.
It tests **this project's `project.conf`** against the real tree, the way
`project-counters.test.sh` does, at three levels:

| Level | What | AC |
|---|---|---|
| manifest (pure bash over `project.conf`, parsed as `gates.sh` parses it) | a `gate \| harness` line exists, is `required`, has a command, carries no `slow` line, names `project-counters`, names no fixture-only suite and not this suite, starts with a token on PATH; an `evidence \| harness` line exists and is not `-` | AC-1, AC-2, AC-4 |
| the gate command, executed as `gates.sh` executes it (`cd $ROOT/$cwd`, subshell, pipefail) | clean tree: exit 0, output carries `project-counters: N passed, 0 failed`, evidence regex matches, `work_count` >= 1. Probed tree (one untracked `.luau` under `src/`): exit non-zero, output carries `project-counters: N passed, M failed`, M >= 1 | AC-4, AC-2 |
| regex controls (no process) | the evidence regex matches none of: empty output; `bash: ... No such file or directory`; `project-counters: 0 passed, 0 failed` | AC-4 control |
| end to end, one `bash scripts/gates.sh --fast --gate harness` on the probed tree | exit 1, `FAIL         harness`, `1 required gate(s) failed`, the streamed `project-counters: N passed, M failed` line, and no `--fast skipped: harness` | AC-2 (and mutation 1) |

**Not tested, deferred to GATES:** AC-3 (DV-4, a bare full run rewrites this
story's own `## Gate results`), AC-5 (DV-1, no gate exists in RED), AC-6 (DV-5,
no gate to time). See the handoff.

### AC-1: which harness suites read the real project tree - derivation and evidence

**Decision rule.** Two rules, applied in this order, and the answer is the
conjunction:

1. *Operational:* with one well-formed, untracked `.luau` at
   `src/shared/__probe_h008_tree.luau`, does the suite still pass? Run for
   **every** suite (`scripts/selftest.sh`'s glob, per-suite exit code and
   time), not only the candidates - a textual negative is cheap to be wrong
   about, and the experiment is the thing the gate is for.
2. *Textual:* what does the suite read from `$REPO_ROOT` other than the
   fixture-copy lines every suite shares (`scripts/`, `.claude/hooks`,
   `paths.conf`, `phases.conf`, `models.conf`, `VERSION`)? This decides *why* a
   suite that survived the probe survived it - because it reads nothing real,
   or because what it reads is harness-owned and a **product** story cannot
   change it. That second class is recorded rather than folded into "fixture
   only", because a **harness** story can change those paths, and the gate is
   sized for the product loop.

The PO's textual hypothesis (`grep -n 'REPO_ROOT.*project.conf'` has exactly one
hit, `project-counters.test.sh:46`) was tested rather than adopted; the wider
grep below is what it was tested with. `_lib.sh`'s header ("never against this
checkout") was not treated as the answer either - it is false for one suite.

The operational experiment: `src/shared/__probe_h008_tree.luau`
(`--!strict / local M = {} / return M`, untracked, not ignored) in place, every
suite run in `selftest.sh`'s glob order, 2026-09-17 ~02:00-02:33 local, load
~28-30 %, `~/.rokit/bin` on PATH. Driver and log in the session scratchpad
(`ac1-experiment.sh`, `ac1-with-probe.log`); `git status -- src` was clean
after. Wall times are that run's and are load-dependent (see AC-6).

| Suite | Reads from the real checkout (beyond the shared fixture copies) | Class | With the probe (rc, wall, summary) |
|---|---|---|---|
| `boundaries` | nothing; `$FIX` only (l.1190 `CLAUDE_PROJECT_DIR="$FIX"`) | fixture | 0, 391 s, 73 passed, 0 failed |
| `ci-local` | `scripts/ci-local.sh`, `.github/workflows/*.yml` (l.16-17) | harness-owned paths | 0, 17 s, 28/0 |
| `classify` | nothing; `cd "$FIX"` (l.24) | fixture | 0, 30 s, 27/0 |
| `doctor` | `.claude/harness/VERSION` (l.102, 269) | harness-owned | 0, 41 s, 27/0 |
| `gate-reminder` | runs the real hook with `CLAUDE_PROJECT_DIR="$FIX"` (l.38) | fixture | 0, 41 s, 27/0 |
| `gates` | nothing; `cd "$FIX"` | fixture | 0, 262 s, 74/0 |
| `lib` | `scripts/*.sh`, `.claude/hooks/*.sh`, `.claude/tests/*.sh` - shape greps (l.218, 242) | harness-owned (note: scans every suite, including new ones) | 0, 28 s, 136/0 |
| `mutate` | nothing; `$FIX/src/main.ts` | fixture | 0, 17 s, 39/0 |
| `new-story` | `scripts/new-story.sh` (l.22), run against a fixture | harness-owned | 0, 2 s, 22/0 |
| `phase-guard` | nothing | fixture | 0, 557 s, 178/0 |
| `phase` | sources `.claude/hooks/lib.sh` with `CLAUDE_PROJECT_DIR="$FIX"` (l.13-14) | fixture | 0, 13 s, 33/0 |
| `plan` | nothing | fixture | 0, 106 s, 34/0 |
| `profiles` | `.claude/skills/stack-profiles/reference` (l.18) | harness-owned | 0, 5 s, 44/0 |
| **`project-counters`** | **`.claude/harness/project.conf` (l.46); `src`, `tests`, `lune` via `git status`/`git ls-files` and stylua/selene/luau-lsp (l.148, 247, 350-408); writes probes under `src/`** | **real project tree** | **1, 18 s, 27 passed, 13 failed** - the stray-file precondition, the three 43/43/8 counts, the three narrowed counts, the three untracked (+1) counts, the three ignored (still 43/43/8) counts |
| `refresh` | `scripts/refresh-harness.sh` (l.74, 217-311), run against a fixture | harness-owned | 0, 37 s, 51/0 |
| `settings` | `.claude/settings.json`, `.claude/state/README.md` (l.130-131) | harness-owned | 0, 13 s, 20/0 |
| `harness-gate` (this story) | `project.conf`; runs `project-counters`; writes a probe under `src/` | real project tree - **excluded from the gate: it would recurse** | n/a (it is the test; it was not in the glob when the experiment started) |

The two rules agree on every row: the only suite the probe broke is the only
suite whose reads reach `src/`, `tests/`, `lune/` or the real `project.conf`.
The textual negative therefore stands *and* was not relied on alone. (SEAT-001's
CI count was 29/11 rather than 27/13 because its files were *tracked*, so the
stray-file precondition held, and its source file was under `src/server`, so
the `src/shared` narrowing count did not move.)

Textual grep used, over every suite, with the shared copy lines filtered out:

    grep -nE 'REPO_ROOT|CLAUDE_PROJECT_DIR|ls-files|classify\.sh' .claude/tests/*.test.sh \
      | grep -vE 'cp (-r )?"\$REPO_ROOT/(scripts|\.claude/hooks|\.claude/harness/(paths|phases|models)\.conf|\.claude/harness/VERSION)'
    grep -nE 'cd "\$REPO_ROOT"|git -C "\$REPO_ROOT"|\$REPO_ROOT/(src|tests|lune|docs)|REPO_ROOT/\.claude/harness/project\.conf' .claude/tests/*.test.sh
    # second grep: 8 hits, all in project-counters.test.sh

**Qualifying set: `{ project-counters }`. Non-empty.** The six "harness-owned"
suites are excluded on the story's own terms (a *product* story cannot break
them; `## Out of scope`: "adding them buys cost without detection"), and that
exclusion is recorded here so a later HARNESS story knows it is not covered by
the gate. `harness-gate` qualifies by the operational rule and is excluded by
construction - it tests the gate, and a gate that runs its own test recurses;
the suite carries a guard that turns that recursion into a named failure.

## Handoff: RED -> GREEN

### Return 1 addendum (2026-09-17) - read this first; the rest is the original RED handoff

**Model.** Corrective RED ran on **Fable 5.1** (`claude-fable-5-1`), the plan's
`fable`; no override.

**What changed.** One file, `.claude/tests/harness-gate.test.sh`. Nothing
else: `project.conf`, `project-counters.test.sh`, `scripts/gates.sh` untouched.
Full record and pasted probes under `## Return 1`.

**What GREEN must do.** Almost certainly nothing to the source. The shipped
`project.conf` already satisfies every corrected assertion:

    export PATH="$HOME/.rokit/bin:$PATH"
    bash .claude/tests/harness-gate.test.sh      # -> harness-gate: 29 passed, 0 failed (3m01s here)

GREEN re-runs that and records the output plus `git status --porcelain --
.claude/harness/project.conf` (expect it unchanged from this commit) as the
no-op proof `## Regressions` asks for. Then `bash scripts/gates.sh --fast`
as usual. If the suite is not 29/0 on GREEN's machine, the first suspects are
the toolchain on PATH, a stray `.luau` under `src/` (both preconditions say so
by name), and **another run of this suite, project-counters, `gates.sh` or
`mutate.sh` in the same checkout at the same time** - not the conf. The suite
is not reentrant; RED lost two runs to exactly that (`## Return 1`, "Two
transient reds"). Check `ps` for those four names before running it, and do
not verify the handoff's probes with `mutate.sh` while a run is in flight.

**The shape the corrected assertions pin, beyond the original list below:**

- `gate | harness | <f3> | <f4> | <f5...>` is read the way `gates.sh` reads
  it: **f3 alone** must be exactly `required`; **f4 alone** is the cwd
  (default `.` when empty) and must be a directory under `$REPO_ROOT`; f5
  onward is the command. The suite's readers are `conf_field` (`cut -fN`) and
  `conf_value` (`cut -fN-`); the second is byte-compatible with
  `project-counters.test.sh`'s copy.
- With the probe present the gate command must exit **non-zero and not 97,
  126 or 127**: 97 is the suite's own `cd`-failed sentinel, 126/127 the shell's
  cannot-execute / not-found. A conforming command never produces any of
  the three (`project-counters` exits 0 or 1), so this constrains nothing
  GREEN would choose; it only stops a never-ran command counting as detection.

**Not constrained, still GREEN's choice:** everything the original "Not
constrained" paragraph lists.

**Original RED handoff follows.** Two rows of its per-assertion table have
been amended in place and are marked `(Return 1)`.

**Model.** RED was dispatched to `test-developer`; it ran on **Fable 5.1**
(`claude-fable-5-1`), which is the plan's `fable`. No override that I can see.

### The command

    export PATH="$HOME/.rokit/bin:$PATH"       # the gate runs project-counters, which needs the toolchain
    bash .claude/tests/harness-gate.test.sh

Cost: in RED, 51 s wall. After GREEN expect two counters runs (~20 s each
quiet) plus one `gates.sh --fast --gate harness` (startup 1.5-2.7 min here
depending on load; seconds on CI). `scripts/selftest.sh` discovers it by glob,
so CI's "Harness self-test" step will run it too.

### The failure, verbatim (2026-09-17, load ~30 %)

    harness-gate: 7 passed, 22 failed
    rc=1

    FAIL project.conf declares a 'gate | harness' line
         no 'gate | harness | ...' line in .claude/harness/project.conf. ...
    FAIL the harness gate is required, so its failure fails the run
         expected: required
         actual:
    FAIL the harness gate has a command
    FAIL the harness gate is in the fast subset: it exists and carries no 'slow' line
         there is no harness gate to be in any subset
    FAIL the gate command runs project-counters, the suite that reads the real tree
         command: <none>
    FAIL the gate command names no fixture-only suite (cost without detection) and not this one (recursion)
         there is no gate command to check
    FAIL the gate command's first token (<none>) is on PATH, as scripts/doctor.sh requires
    FAIL project.conf declares an evidence regex for the harness gate
         no usable 'evidence | harness | <regex>' line (found: '<none>').
    FAIL the gate command exits 0 on the unmodified tree
         there is no harness gate command to run
    FAIL and its output carries project-counters' own summary line, all passed
    FAIL the evidence regex matches the clean run's output
    FAIL and gates.sh would observe a count of at least 1 from it
    FAIL does not match: nothing printed at all
         no evidence regex to test
    FAIL does not match: bash could not find the suite
    FAIL does not match: a suite with zero assertions
    FAIL the gate command exits non-zero with the probe present
         there is no harness gate command to run
    FAIL and its output names project-counters as the suite that broke
    FAIL gates.sh --fast --gate harness exits 1 (a required gate failed)
         expected exit 1; got 2
         output (last 8 lines):
         error: no gate named 'harness' in project.conf; see --list
    FAIL the summary reports the harness gate as FAIL
    FAIL and counts it as a required failure
    FAIL and the streamed output names project-counters as the suite that broke
    FAIL --fast did not skip the harness gate
         the run never reached the gate summary, so nothing was run or skipped

**Why it is the right failure.** Every red assertion fails on the *absence of
the gate*: no `gate | harness` line, no `evidence | harness` line, and
`gates.sh` refusing `--gate harness` with its own "no gate named" message. No
import error, no toolchain error, no timeout. The suite never greps with an
empty pattern: where the regex is absent it fails explicitly rather than
letting `''` match everything.

**AC-2's control, run as the criterion names it.** With
`src/shared/__probe_h008_added.luau` present, today's `bash scripts/gates.sh
--fast` **passes** (1 m 42 s):

    PASS         format (0s, observed 44)
    PASS         lint (1s, observed 44, floor 1)
    PASS         typecheck (2s, observed 9)
    PASS         unit (12s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (0s, observed 25137)
    --fast skipped: integration mutation
    All required gates passed (5 ran, 1 unconfigured, 0 known).
    rc=0

while `project-counters` on that same tree is `27 passed, 13 failed` (AC-1
table). That is SEAT-001, and it is what the end-to-end block must turn red.

### Files touched

| File | What |
|---|---|
| `.claude/tests/harness-gate.test.sh` | new suite (classifies `harness`) |
| `docs/backlog/stories/HARNESS-008.md` | `## Test plan` (with the AC-1 record), this section |

No production source, no config, no manifest, no change to
`project-counters.test.sh`. `scripts/gates.sh` untouched. Nothing committed.

### One line per assertion

| Assertion | AC |
|---|---|
| toolchain on PATH; `project-counters.test.sh` exists; no stray `.luau` in the tree | preconditions |
| `gate \| harness` line exists | AC-1/AC-2 |
| field 3 **alone** (`conf_field`, as `gates.sh`'s `cut -f3`) is `required` (Return 1: was read as the remainder) | AC-2 |
| it has a command | AC-2 |
| exists **and** no `slow \| harness` line | AC-2 (mutation 1) |
| command names `project-counters` | AC-1 |
| command names no other suite (`<name>.test.sh` or `selftest.sh <name>`), incl. `harness-gate` | AC-1, `## Out of scope`, recursion |
| command's first token is on PATH | callers: `doctor.sh:74` |
| `evidence \| harness` exists and is not `-` | AC-4 |
| command (run as gates.sh runs it) exits 0 on the clean tree | AC-4 |
| its output has a line `^project-counters: [1-9][0-9]* passed, 0 failed$` | AC-4 |
| evidence regex matches that output | AC-4 |
| `work_count` over it is >= 1 (gates.sh's "observed") | AC-4 |
| regex does not match: empty / `bash: ...: No such file or directory` / `project-counters: 0 passed, 0 failed` | AC-4 control |
| probe is untracked and not ignored | AC-2 precondition |
| instrument: the "broke" needle rejects `40 passed, 0 failed` | needle self-check |
| command exits non-zero **and not 97 / 126 / 127** with the probe present (Return 1: `-ne 0` accepted the never-ran sentinel) | AC-2 |
| its output has a line `^project-counters: [0-9]+ passed, [1-9][0-9]* failed$` | AC-2 |
| `gates.sh --fast --gate harness` exits 1 | AC-2 |
| output contains `FAIL         harness` | AC-2 |
| output contains `1 required gate(s) failed` | AC-2 |
| streamed output has the "broke" line | AC-2 ("naming the suite") |
| output reached the gate summary and has no `--fast skipped: harness` | AC-2 (mutation 1) |
| probe removed, tree clean | hygiene |

### The shape the tests pin (facts, not suggestions)

In `.claude/harness/project.conf`, read the way `gates.sh` reads it
(`|`-separated, fields trimmed, first match wins):

- **`gate | harness | required | <cwd> | <command>`** - the id is exactly
  `harness` (the suite passes it to `--gate`); field 3 exactly `required`.
- **`<command>`** must: contain the substring `project-counters`; **not**
  contain `<name>.test.sh` or `selftest.sh <name>` for any of the other 15
  suites or for `harness-gate`; start with a token `command -v` finds
  (`bash` is fine); when run from `$ROOT/<cwd>` in a subshell under
  `set -o pipefail` with `HARNESS_GATE_UNDER_TEST=1` in the environment, exit 0
  on the clean tree and emit (stdout or stderr) a whole line
  `project-counters: N passed, 0 failed` with N >= 1; with one untracked
  `.luau` under `src/shared/`, exit non-zero and emit
  `project-counters: N passed, M failed` with M >= 1. It must **never reach
  `harness-gate.test.sh`** - directly, via a glob over `.claude/tests`, or via
  a bare `selftest.sh` - the nested copy exits 1 with a message that says so.
- **`evidence | harness | <ERE>`** - not `-`; must match the clean run's output
  under `grep -E`; the first digit-run at or after the match must be >= 1
  (gates.sh `work_count`); must **not** match `""`,
  `bash: .claude/tests/nope.test.sh: No such file or directory`, or
  `project-counters: 0 passed, 0 failed`.
- **No `slow | harness` line.**

**Not constrained - GREEN's choice:** `<cwd>` (the suite runs from
`$ROOT/<cwd>`, default `.`); the exact command text, including whether it is
`bash .claude/tests/project-counters.test.sh` or `bash scripts/selftest.sh
project-counters` (both satisfy every assertion; note the second prints
`1 harness suite(s) passed.` **after** the counters summary, and the suggested
regex does not match that line - pick one that matches something the run
prints); the exact regex; whether to add `floor`, `covers` or `ci-factor`
lines; the gate's position in the file. The Contract's suggested pair

    gate | harness | required | . | bash .claude/tests/project-counters.test.sh
    evidence | harness | [1-9][0-9]* passed, [0-9]+ failed

satisfies every assertion above, per the control table.

### Tests that passed on arrival, and what earns them

Seven, none of which pins production behaviour: the three preconditions
(toolchain, suite exists, no stray `.luau`), the probe's two git-state
preconditions, the cleanup check, and the **instrument self-check** (the
"broke" needle vs `project-counters: 40 passed, 0 failed` -> no match, measured
inside the suite). Two assertions that *would* have passed vacuously in RED -
"names no fixture-only suite" on an empty command, and "did not skip" on an
error output with no skip line - were found in the first RED run (9 passed)
and made conditional on the gate existing / the run reaching the summary;
the second run is the 7/22 above. No regression guard was added; none needed
a `mutate.sh` probe.

### Negative controls: expected values

Measured **outside the framework** (plain bash, `grep -E` / `work_count`)
against the Contract's *suggested* regex, because in RED no `evidence |
harness` line exists and the suite's control assertions fail on its absence.
**GREEN confirms each against the shipped regex** by running the suite; the
values must be the same or the regex is wrong.

| Control input | Threshold | Expected | Measured (suggested regex) |
|---|---|---|---|
| `""` (nothing printed) | no match | 0 matches | 0 |
| `bash: .claude/tests/nope.test.sh: No such file or directory` | no match | 0 | 0 |
| `project-counters: 0 passed, 0 failed` (zero assertions, exit 0) | no match | 0 | 0 |
| `project-counters: 40 passed, 0 failed` (today's clean run) | match, work_count >= 1 | 1, observed 40 | 1, 40 |
| `project-counters: 29 passed, 11 failed` (SEAT-001) | n/a - gates.sh consults evidence only on exit 0 | matches, observed 29 | 1, 29 |
| `1 harness suite(s) passed.` (selftest's own line) | n/a unless GREEN uses that shape | - | 0 with the suggested regex |
| "broke" needle `^project-counters: [0-9]+ passed, [1-9][0-9]* failed$` vs `40 passed, 0 failed` | no match | 0 | 0 (**ran inside the suite: passed**) |
| "ran" needle `^project-counters: [1-9][0-9]* passed, 0 failed$` vs `0 passed, 0 failed` | no match | 0 | 0 |

### Callers, re-checked against the tree in RED (not read from PLANNED)

- `grep -rln project.conf scripts/ .claude/tests/ .claude/hooks/ .github/`:
  the 16 files PLANNED listed plus `harness-gate.test.sh`. Real-`project.conf`
  readers among suites are now exactly two: `project-counters.test.sh:46` and
  `harness-gate.test.sh:58` - the second is this story's and is excluded from
  the gate by construction.
- `project-counters.test.sh:301` is still `for g in format lint typecheck` -
  **hardcoded**. Finding: even a dynamic version would not recurse, because
  that loop only checks each command's first token with `command -v`; it never
  runs a gate command. The recursion hazard that is real is the one above -
  the gate reaching `harness-gate.test.sh` - and the suite guards it.
- `scripts/doctor.sh:74` still takes the first token; asserted.
- `scripts/gates.sh`: `--gate` filter at l.259, slow skip at l.266-267,
  recording skipped for `--gate`/`--required`/`--fast` at l.677. Mechanism 2
  **verified by execution** in a `make_project_fixture` (scratch, not
  committed): `--fast --gate harness` -> `PASS harness ... (1 ran)` when not
  slow; `--fast skipped: harness ... (0 ran)` exit 0 when slow;
  `--gate harness` without `--fast` runs it even when slow.

### Findings that change how GREEN/GATES should read the story

1. **DV-3's premise does not hold for the obvious mutation.** Pointing the
   command at a suite that does not exist gives `bash: ...: No such file or
   directory`, **exit 127 -> `FAIL harness (exit 127)`**, not "ran but produced
   no evidence of work" - gates.sh consults evidence only after exit 0
   (fixture run in RED). To make the evidence line fire, mutate to a command
   that exits 0 having done nothing, e.g. `s|bash .claude/tests/project-counters.test.sh|true|`.
   The regex-level controls in this suite cover the same property without
   gates.sh.
2. **`--gate <unknown>` exits 2 before writing `.claude/state/last-gate-run`**,
   so the RED run left the stamp untouched. After GREEN, the suite's
   end-to-end block *will* write `RESULT=fail FULL=no` (a partial run, not
   evidence). The Stop hook treats `RESULT=fail` as a note, not a block, but
   **in GATES it blocks on `FULL=no`** - so if the suite is run by hand after
   the full `gates.sh`, run the full one again. Nothing in the per-story loop
   runs this suite; only `selftest.sh`/CI do.
3. **Startup dominates.** `gates.sh --list` was 2 m 41 s at 28 % load and
   `--fast` 1 m 42 s an hour later; PO decision 3 stands. The suite spends one
   invocation, not two: the clean-tree half of AC-4 is asserted on the gate
   *command* run as gates.sh runs it, not through gates.sh.
4. **Abnormal path.** A run killed between the probe write and the trap leaves
   `src/shared/__probe_h008_added.luau`; the counters suite's stray-file
   precondition then fails until it is `rm`-ed. Same class as Contract
   mechanism 4, one more file name to know.

### Deferred verifications - declined, with the owner

- **DV-1 (AC-5, GATES):** cannot run - there is no gate to break in RED. The
  probe to use is this suite's: `src/shared/__probe_h008_added.luau`, then
  `bash scripts/gates.sh --fast --gate harness`; condition `FAIL         harness`
  and a `project-counters: N passed, M failed` line with M >= 1. Paste into
  `## Gate probes`.
- **DV-2 (AC-2 mutation 1, GATES):** cannot run - no gate to mark slow. When
  run, the suite's "is in the fast subset" and "did not skip" assertions are
  the ones that go red. Dry-run on a copy against this machine's GNU sed 4.9:

      bash scripts/mutate.sh .claude/harness/project.conf \
        '$a slow | harness | GATES probe: marks the gate slow' \
        -- bash .claude/tests/harness-gate.test.sh

  (`$a` appends a line; a `s|...|...|` form cannot be used here because the
  conf lines themselves contain `|`.)
- **DV-3 (AC-4 control, GATES):** cannot run - no gate; and see finding 1 for
  the mutation that actually fires the evidence line.
- **DV-4 (AC-3, GATES):** deliberately not a test; a bare full run rewrites
  this story's `## Gate results`. Observe once in GATES.
- **DV-5 (AC-6, GATES):** cannot run - no gate to time. Read out, not
  re-derived: counters suite **20.4 s** quiet (PO decision 2: 20.1/20.8, 3 %
  spread), **18 s** in the AC-1 experiment at ~28 % load, **13 s** on CI
  (HARNESS-006); `--fast` today 1 m 42 s wall with the gates at ~16 s. The
  measurement GATES records must carry the three parts AC-6 names.

### Doubts

- The suite pins the gate **id** `harness`. If the PO wants a different id,
  the suite's `GATE_ID` is the one place to change it - flagging rather than
  loosening.
- The suite is itself a real-tree suite that a product story can break
  (through the counters literals). It is not in the gate, so like today's
  counters suite it is caught only by `selftest.sh`/CI. That is the same
  hole one level up, for one file; recording it rather than hiding it.

## GREEN: control values confirmed

**Model.** GREEN was dispatched to `feature-developer`. Resolved **Opus 5**
(`claude-opus-5`), self-reported, matching `## Model guidance`. No override was
passed on the dispatch.

### STATUS: the gate is shipped and proven; the SUITE is defective. Return to RED.

`bash .claude/tests/harness-gate.test.sh` is **23 passed, 6 failed**, up from
RED's 7/22. All six remaining failures trace to **one defect in the test
suite's own conf parser**, not to `project.conf`, and **two of its assertions
are unsatisfiable by any possible `project.conf`**. Details in
"The blocking defect" below. Nothing here was resolved by weakening anything:
the config is left in place, because it is correct and is proven correct by the
suite's own end-to-end block and by `gates.sh --fast`.

### What was shipped

Two lines in `.claude/harness/project.conf`, each with a comment block above it
(the gate line after `gate | build`, last among the configured gates; the
evidence line at the end of the evidence group):

    gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
    evidence | harness   | project-counters: [1-9][0-9]* passed, [0-9]+ failed

No `slow | harness` line. No `floor`, `covers` or `ci-factor` line. No other
file changed; `scripts/gates.sh` untouched; `project-counters.test.sh`
untouched; no test file touched.

### Deviations from the shapes the Contract and handoff offered

| What | Offered | Shipped | Why |
|---|---|---|---|
| gate command | `bash .claude/tests/project-counters.test.sh` | identical | the handoff's alternative, `bash scripts/selftest.sh project-counters`, adds a discovery layer between the gate and the suite it names, and prints `1 harness suite(s) passed.` after the summary |
| gate cwd | `.` | `.` | - |
| evidence regex | `[1-9][0-9]* passed, [0-9]+ failed` | `project-counters: [1-9][0-9]* passed, [0-9]+ failed` | **the one deviation.** The bare form is `unit`'s line and is satisfied by *any* `_lib.sh` suite summary - a gate command re-pointed at `lune run test` would still report "evidence of work". Naming the suite makes the needle fail when the gate stops running the suite it exists for. Measured against every row of the control table below: the two forms answer identically. |
| position | unspecified | last configured gate | `project-counters` writes probe `.luau` files under `src/` and removes them on its own `EXIT` trap (Contract mechanism 4). Running it after `format`/`lint`/`typecheck`/`unit`/`build` means a run killed mid-flight cannot expose those probes to the counting gates *within the same run*. |
| `floor | harness` | GREEN's choice | **not added** | it would be a second literal tracking the counters suite's assertion count, i.e. the same staleness class this story's `## Out of scope` declines to fix. The evidence regex already refuses `0 passed`. Recorded as a decision, not an omission. |

### Negative controls, confirmed against the SHIPPED regex

RED measured these outside the framework against the *suggested* regex, because
in RED the suite failed on the absence of an `evidence | harness` line and not
one control assertion executed. Measured here two ways: outside the framework
against `project-counters: [1-9][0-9]* passed, [0-9]+ failed` (scratch script,
`grep -cE` and a verbatim copy of `gates.sh`'s `work_count`), and **inside the
suite**, whose `AC-4 control` block ran green for the first time in this story.

| Control input | RED expected | GREEN measured (shipped regex) | Agrees |
|---|---|---|---|
| `""` (nothing printed) | no match, 0 | **0 matches**, work_count `<none>` | yes |
| `bash: .claude/tests/nope.test.sh: No such file or directory` | no match, 0 | **0 matches**, work_count `<none>` | yes |
| `project-counters: 0 passed, 0 failed` | no match, 0 | **0 matches**, work_count `<none>` | yes |
| `project-counters: 40 passed, 0 failed` | match, work_count 40 | **1 match, work_count 40** | yes |
| `project-counters: 29 passed, 11 failed` | match, work_count 29 | **1 match, work_count 29** | yes |
| `1 harness suite(s) passed.` | 0 with the suggested regex | **0 matches** | yes |

**No divergence on any row.** The same six rows were also measured against the
Contract's *suggested* bare regex in the same script and answer identically,
which is what makes the narrowing above a strengthening rather than a change of
behaviour.

Confirmed inside the framework (`VERBOSE=1`), first execution ever of these
three assertions:

    AC-4 control: the evidence regex refuses a run that did nothing
      ok   does not match: nothing printed at all
      ok   does not match: bash could not find the suite
      ok   does not match: a suite with zero assertions

And against **real output rather than a string literal**, which no control row
covers - the shipped command run as `gates.sh` runs it (`cd $ROOT/.`, subshell,
`set -o pipefail`, `HARNESS_GATE_UNDER_TEST=1`):

    --- clean tree ---
    rc=0
    project-counters: 40 passed, 0 failed
    evidence matches: 1   work_count=40

    --- probed tree (one untracked .luau under src/shared) ---
    rc=1
    project-counters: 27 passed, 13 failed
    tree clean after: []

`27 passed, 13 failed` is the exact count the AC-1 table and PO decision 6
predicted from an independent probe. Exactly **one** line of the clean run
matches the evidence regex, so `work_count` reads the pass count and nothing
else.

### The gate works. Proven through `gates.sh` itself, twice.

The suite's `AC-2, end to end` block - six assertions - **passed in full**,
because `gates.sh` parses the gate line with `cut -f3 / -f4 / -f5-` and reads
it correctly:

    AC-2, end to end: 'gates.sh --fast' fails on that tree and says which gate and suite
      ok   gates.sh --fast --gate harness exits 1 (a required gate failed)
      ok   the summary reports the harness gate as FAIL
      ok   and counts it as a required failure
      ok   and the streamed output names project-counters as the suite that broke
      ok   --fast did not skip the harness gate
      ok   the probe is gone and the tree is clean again

Admissibility run, clean tree, quiet machine (fork-cost probe 2.06 s / 50 forks
= **41 ms per fork**, against PO decision 1's 49 ms quiet and 440 ms loaded):

    $ bash scripts/gates.sh --fast
    PASS         format (0s, observed 43)
    PASS         lint (1s, observed 43, floor 1)
    PASS         typecheck (2s, observed 8)
    PASS         unit (11s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (0s, observed 25103)
    PASS         harness (13s, observed 40)
    --fast skipped: integration mutation
    All required gates passed (6 ran, 1 unconfigured, 0 known).
    real 2m6.721s   rc=0

**A datum for DV-5, not the measurement:** the gate cost **13 s** inside that
run, against the counters suite's 20.4 s standalone in PLANNED. AC-6's
three-part standard is GATES' to satisfy; one run is not a measurement.

`scripts/doctor.sh` - the caller the Contract named - stays green and now
reports `ok bash /usr/bin/bash` in the project toolchain, exit 0.

### The blocking defect: `harness-gate.test.sh`'s `conf_value` cannot read a middle field

**Not a disagreement about the config. Two assertions cannot be satisfied by
any `project.conf` that `gates.sh` would also accept.**

`conf_value <kind> <id> <from>` (`harness-gate.test.sh:83-102`, copied verbatim
from `project-counters.test.sh`) returns **everything from field `from`
onward**, not field `from`. It never truncates at the next `|`. That is correct
for its original two uses - an `evidence` line's field 3 *is* the remainder, and
a `gate` line's field 5 *is* the remainder - and wrong for the two new uses this
suite introduces, `gate` field 3 and field 4.

Measured, with a verbatim copy of the function, over the shipped conf and over
three gate lines that predate this story:

    id=harness  from=3 -> [required | . | bash .claude/tests/project-counters.test.sh]
    id=harness  from=4 -> [. | bash .claude/tests/project-counters.test.sh]
    id=unit     from=3 -> [required | . | lune run test]
    id=unit     from=4 -> [. | lune run test]
    id=build    from=3 -> [required | . | mkdir -p build && rojo build ...]

    gates.sh's own parse of the same line:
      f3=[ required ] f4=[ . ] f5-=[ bash .claude/tests/project-counters.test.sh]

So the suite's stated method - "each is asserted as gates.sh would read it"
(`harness-gate.test.sh:156`) - does not hold for fields 3 and 4.

**Why it is unsatisfiable rather than merely failing.** For
`assert_eq "... is required" "required" "$GATE_REQ"` (l.174) to pass,
field-3-onward must trim to exactly `required`, i.e. the line must be
`gate | harness | required` with **nothing after it**. On such a line
`conf_value gate harness 5` returns `required` too (`${rest#*|}` is a no-op on a
string with no `|`), so `the gate has a command` (l.175) passes vacuously while
`the gate command runs project-counters` (l.196) fails. Add the command back and
l.174 fails again. There is no line that satisfies both, and `gates.sh` would
report a 3-field gate as unconfigured regardless.

**Blast radius: 6 failures and one vacuous pass.**

| Assertion | Line | Effect of the defect |
|---|---|---|
| `the harness gate is required, so its failure fails the run` | 174 | FAIL, unsatisfiable |
| `the gate command exits 0 on the unmodified tree` | 239 | FAIL - `GATE_CWD` is `. \| bash ...`, so `run_gate_cmd`'s `cd` fails and returns its 97 sentinel |
| `and its output carries project-counters' own summary line, all passed` | 243 | FAIL, same cause (`OUT` empty) |
| `the evidence regex matches the clean run's output` | 256 | FAIL, same cause (`CLEAN_OUT` empty) |
| `and gates.sh would observe a count of at least 1 from it` | 264 | FAIL, same cause |
| `and its output names project-counters as the suite that broke` | 337 | FAIL, same cause |
| **`the gate command exits non-zero with the probe present`** | **332** | **PASSES VACUOUSLY** - `cd` failed with **97**, and 97 is non-zero. The assertion reports the gate detecting SEAT-001 while measuring its own broken `cd`. |

That last row is the one worth the Test Developer's attention beyond the fix: it
is `rules.md`'s "an assertion's needle is part of the assertion" at the level of
an exit code. `RC` from a `cd` that never ran the command is indistinguishable,
to `[ "$RC" -ne 0 ]`, from the suite going red. It would keep passing after the
parser is fixed, so it also needs earning - `run_gate_cmd`'s 97 sentinel is a
value the assertion must reject, the same way the `BROKE` needle already rejects
an all-green summary at l.324.

**What GREEN did not do.** Did not touch `harness-gate.test.sh`; did not touch
`project-counters.test.sh`; did not change the gate's shape to chase l.174 - the
only shape that could satisfy it is one `gates.sh` reports as unconfigured, so
"making the test pass" here would mean shipping no gate at all. Reported instead.

**The shape of the fix is the Test Developer's call, not recorded here as a
requirement**; for orientation, the suite needs a way to ask for a *single*
field (truncating at the next `|`) for `gate` fields 3 and 4, while `gate` field
5 and `evidence` field 3 keep today's remainder semantics. `project-counters.test.sh`
must not change: its own uses of `conf_value` are inside the helper's domain.

**On the return to RED:** the corrected assertions will run for the first time
against a `project.conf` that already satisfies them, so they are the
"corrected while the implementation exists" case and owe a `mutate.sh` probe
each rather than an observed failure - `rules.md` non-negotiable 2. The obvious
one for l.174 is mutating the shipped line's `required` to `optional` and
watching that assertion, and only that assertion, go red.

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

**Return 1, GREEN -> RED, 2026-09-17.** Full record, all four probe outputs
and the before/after, under `## Return 1` below; this entry is the index
`check-boundaries.sh` reads, and carries the red it needs to see.

*Which test.* `.claude/tests/harness-gate.test.sh`, two defects: (1)
`conf_value` returned the remainder for every field, so `gate` f3/f4 read as
`required | . | bash ...` and six assertions failed against a correct
`project.conf`; (2) "the gate command exits non-zero with the probe present"
was `[ $RC -ne 0 ]`, satisfied by `run_gate_cmd`'s own `97` sentinel when
its `cd` failed and the command never ran. Found by GREEN, reproduced by the
orchestrator (`## Notes` decision 8). Now: `conf_field` (single field,
`cut -fN`) for f3/f4, `conf_value` (remainder) unchanged for f5/evidence;
the exit-code assertion rejects `97`, `126` and `127` by name.

*What earns them.* Probes through `scripts/mutate.sh` on `project.conf`
l.430, each restored and verified byte-for-byte. The corrected `required` read
(probe A, `required` -> `optional`):

    FAIL the harness gate is required, so its failure fails the run
         expected: required
         actual:   optional
    harness-gate: 25 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_harness_project.conf.20260917T133855Z.2866282.bak) ===

The corrected exit-code needle (probe B, cwd -> a missing directory), the same
mutation before and after the needle change - one assertion apart:

    before:  ok   the gate command exits non-zero with the probe present   (RC=97, cd failed)   23 passed, 6 failed
    after:   FAIL the gate command exits non-zero with the probe present
             got 97, run_gate_cmd's own sentinel: 'cd .../__h008_no_such_dir' FAILED and the
             gate command never ran. A non-zero exit from a command that did not execute is
             not the gate detecting the probe. cwd as parsed: [__h008_no_such_dir]
    harness-gate: 22 passed, 7 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_harness_project.conf.20260917T134144Z.2874926.bak) ===

Probe C (command path -> missing file, exit 127): `got 127, the shell's
'cannot execute' / 'not found': the gate command never ran.` - 22 passed, 7
failed, restore verified (`20260917T134405Z`). Clean tree after the
correction: `harness-gate: 29 passed, 0 failed`.

*GREEN.* **Confirmed a no-op**, and verified by the orchestrator rather than
delegated - an agent dispatched with nothing to do finds some. The source was
never touched on re-entry: the only functional change to `project.conf` across
the whole story is still the two lines the first GREEN wrote.

    $ git diff -U0 -- .claude/harness/project.conf | grep -E '^\+[a-z]'
    +gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
    +evidence | harness   | project-counters: [1-9][0-9]* passed, [0-9]+ failed

Untouched, it still passes the corrected suite, and the gate is admissible to
the gates that judge it:

    $ bash .claude/tests/harness-gate.test.sh
    harness-gate: 29 passed, 0 failed

    $ bash scripts/gates.sh --fast
    PASS         format (1s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (3s, observed 8)
    PASS         unit (24s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (0s, observed 25103)
    PASS         harness (21s, observed 40)
    --fast skipped: integration mutation
    All required gates passed (6 ran, 1 unconfigured, 0 known).
    real    4m58.735s

So the corrected tests pinned a defect in the **instrument**, not in the
artifact - which is what the return said they would, and is why GREEN had
nothing to do.

## Return 1: GREEN -> RED, 2026-09-17

**The artifact is not what is wrong.** `.claude/harness/project.conf`'s two new
lines are correct and stay in place across this return. Verified by the
orchestrator against the shipped config, independently of the defective suite:

    harness-gate: 23 passed, 6 failed        (RED left it at 7/22)
    PASS harness (15s, observed 40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).   real 2m13.8s

The six failures are the **instrument**, not the artifact.

### Defect 1 - `conf_value` cannot read a middle field

*Which test and what it asserted.* `.claude/tests/harness-gate.test.sh`,
`conf_value <kind> <id> <from>` (l.83-102), and the six assertions downstream of
it. The suite's stated method is that each value is "asserted as gates.sh would
read it" (l.156).

*What is wrong.* It returns **everything from field `from` onward** and never
truncates at the next `|`. That is correct for its two inherited uses - an
`evidence` line's field 3 and a `gate` line's field 5 genuinely *are* the
remainder - and wrong for the two uses this suite is the first to make, `gate`
field 3 (`required`) and field 4 (the cwd). `gates.sh` uses `cut -f3`/`-f4` and
gets a single field.

*How it was found.* GREEN hit it shipping the gate, refused to bend the config
to chase it, and reported. The orchestrator then reproduced it independently -
different inputs, a synthetic conf, ids GREEN never used, driving the function
extracted verbatim from this suite. Full output in `## Notes`, PO decision 8.

*Why it is unsatisfiable rather than merely failing.* For l.174 to pass, field-3
onward must trim to exactly `required`, i.e. a line ending there - and on that
line l.196 ("the command runs project-counters") fails, while `gates.sh` reports
the gate **unconfigured**. Enumerated: no line satisfies both. "Making the test
pass" would have meant shipping no gate.

*What it should assert instead.* The same properties, with a way to ask for a
**single** field for `gate` f3 and f4 while `gate` f5 and `evidence` f3 keep
remainder semantics. **`project-counters.test.sh` must not change** - checked:
its only uses are `conf_value gate "$1" 5` and `conf_value evidence "$1" 3`
(l.134-135), both inside the helper's correct domain, so `HARNESS-006` carries
no latent copy of this bug.

### Defect 2 - an exit-code needle that cannot fail

*Which test.* l.332, `the gate command exits non-zero with the probe present`.

*What is wrong.* It **passed** in GREEN, and passed for the wrong reason.
`run_gate_cmd` returns `97` when its `cd` fails, and the assertion is
`[ "$RC" -ne 0 ]`, which accepts 97. It reported the gate detecting the
SEAT-001 tree while the gate command **never ran**. Demonstrated by the
orchestrator with `run_gate_cmd` copied verbatim:

    GATE_CWD (as the broken parser yields it): [. | bash .claude/tests/project-counters.test.sh]
    cd: .../. | bash .claude/tests/...: No such file or directory
    RC=97   OUT=[]
    >>> l.332 assertion PASSES -- while the gate command never ran at all.

*Why it is a separate defect.* **It survives the fix to defect 1.** Once the cwd
parses correctly the `cd` succeeds and the assertion goes on passing - so fixing
the parser alone would leave an assertion that cannot fail, which is the defect
class this harness exists to prevent. This is `rules.md`'s "an assertion's
needle is part of the assertion" at the level of an **exit code**, a form none
of the four recorded instances covers.

*What it should assert instead.* Non-zero **and not the `97` sentinel** - the
same shape as the `BROKE` needle already rejecting an all-green summary at
l.324.

*Scope decision.* Both defects are fixed in this return. Chosen by the user
over fixing only the parser, or deferring the needle to its own story, on the
grounds above. Recorded rather than assumed.

### What earns the corrected assertions

"Watch it fail" cannot apply: the implementation already exists and already
satisfies them, so each corrected assertion passes on its first run and every
run after, whether or not it asserts anything. Each therefore owes a
`scripts/mutate.sh` **probe with pasted output** - see below.

### The correction (RED, 2026-09-17, Fable 5.1 / `claude-fable-5-1`, no override)

One file changed: `.claude/tests/harness-gate.test.sh`. `project.conf`,
`project-counters.test.sh` and `scripts/gates.sh` untouched (`git status`
shows the same three entries as before this return).

**Defect 1 - what it reads now.** The single loop is now `_conf_rest <kind>
<id> <from>` (sets `REST`, the raw text from field `from` onward), with two
readers over it that mirror `gates.sh`'s two `cut` shapes exactly:

| reader | cut shape | used for |
|---|---|---|
| `conf_value kind id N` | `-fN-` (remainder) | `gate` f5 (command), `evidence` f3 (regex), `slow` f3 - unchanged semantics |
| `conf_field kind id N` | `-fN` (one field) | `gate` f3 (`required`), `gate` f4 (cwd) - **new** |

`GATE_REQ` and `GATE_CWD` (l.194-195) now come from `conf_field`. Verified
outside the framework against a synthetic conf with ids the suite never uses,
where the command and the regex both contain `|`, side by side with `cut`:

    conf_field gate zeta 3       -> rc=0 [required]
    conf_field gate zeta 4       -> rc=0 [subdir]
    conf_value gate zeta 5       -> rc=0 [printf '%s' a | tr a b]
    conf_value evidence zeta 3   -> rc=0 [zeta over [0-9]+ (files|dirs)]
    conf_field gate eta 3        -> rc=0 [optional]
    conf_field gate eta 4        -> rc=0 [.]
    conf_value slow zeta 3       -> rc=1 []
    --- cut, gates.sh's method, on the same lines ---
    f3  [required]
    f4  [subdir]
    f5- [printf '%s' a | tr a b]
    ev3-[zeta over [0-9]+ (files|dirs)]

**Defect 2 - what it asserts now.** `run_gate_cmd`'s sentinel is named
(`NEVER_RAN_CD=97`) and "the gate command exits non-zero with the probe
present" is a `case` over `RC`: `0` fails ("the gate would PASS"), `97` fails
("`cd` FAILED and the gate command never ran"), **`126`/`127` also fail** ("the
shell's 'cannot execute' / 'not found': the gate command never ran") - the
same class, from the shell rather than the suite: `bash nope.test.sh` is 127
from bash itself, and a command that did not execute has not "exited non-zero
with the probe present" either. Everything else passes. `project-counters`
exits 0 or 1 via `summary`, so no real run collides with any of the three.

Other exit-code reads in the suite, checked and left alone: "exits 0 on the
unmodified tree" is `-eq 0`, which no never-ran code satisfies; the end-to-end
`gates.sh --fast --gate harness` check is `-eq 1`, exactly the "N required
gate(s) failed" code, and its sibling `BROKE`-line assertion closes the gap
(in probe B below it goes red while the exit-code line stays green - the pair
is what pins it, as designed).

**A third, latent defect found by probe C and fixed in passing.** The `_bad`
message of "gates.sh would observe a count of at least 1" said `` `floor` ``
inside a double-quoted string, which bash runs as a command substitution:

    .claude/tests/harness-gate.test.sh: line 301: floor: command not found

Only reachable on that assertion's failure path, harmless (empty
substitution), no assertion involved; now `'floor'`. The two remaining
backticks in the file are in trailing comments.

### Clean run of the corrected suite: 29 passed, 0 failed

    $ export PATH="$HOME/.rokit/bin:$PATH"; VERBOSE=1 bash .claude/tests/harness-gate.test.sh
    ...
      AC-2: with one .luau added under src/, the gate command fails and names the suite
        ok   the probe is untracked (precondition: that is what a product story's new file is)
        ok   the probe is not ignored (precondition: an ignored file is not counted)
        ok   instrument: the 'suite broke' needle rejects an all-green summary
        ok   the gate command exits non-zero with the probe present
        ok   and its output names project-counters as the suite that broke
    ...
    harness-gate: 29 passed, 0 failed

    real    3m1.134s      (local, this machine; load not measured)

### Probe A - earns l.199 "the harness gate is required": `required` -> `optional`

Predicted: l.199 red, plus the three end-to-end lines that are the real
consequence of an optional gate (gates.sh exits 0 and WARNs). **Measured: 4
red, exactly those.** The target assertion fails with the value the parser now
reads - a single field - where before this return it read `required | . |
bash ...` and could never have equalled either string.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's#^gate | harness   | required | \. | bash#gate | harness   | optional | . | bash#' \
        -- bash .claude/tests/harness-gate.test.sh
    === mutate: .claude/harness/project.conf (1 line(s) changed by s#^gate | harness   | required | \. | bash#gate | harness   | optional | . | bash#) ===
      430 - gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
      430 + gate | harness   | optional | . | bash .claude/tests/project-counters.test.sh

    === mutate: running bash .claude/tests/harness-gate.test.sh ===

      AC-1: project.conf has a required, not-slow gate that runs the real-tree suite
        FAIL the harness gate is required, so its failure fails the run
             expected: required
             actual:   optional
      ...
      AC-2, end to end: 'gates.sh --fast' fails on that tree and says which gate and suite
        FAIL gates.sh --fast --gate harness exits 1 (a required gate failed)
             expected exit 1; got 0
        FAIL the summary reports the harness gate as FAIL
             expected to contain: FAIL         harness
             (actual carries: WARN         harness (16s, exit 1, optional) -> .claude/state/gate-logs/harness.log)
        FAIL and counts it as a required failure
             expected to contain: 1 required gate(s) failed
             (actual carries: All required gates passed (1 ran, 0 unconfigured, 0 known).)

    harness-gate: 25 passed, 4 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T133855Z.2866282.bak) ===
      430: gate | harness   | required | . | bash .claude/tests/project-counters.test.sh

    real    2m33.065s

### Probe B - earns the exit-code needle: cwd `.` -> `__h008_no_such_dir`, BEFORE and AFTER

The same mutation run twice against the suite, once with only defect 1 fixed
(old needle `[ $RC -ne 0 ]`) and once with the corrected needle. The
difference is one assertion, and it is the one this return names.

**Before** (parser fixed, needle not yet): 23 passed, 6 failed. The `cd`
error prints and the very next line is the vacuous `ok`:

    === mutate: .claude/harness/project.conf (1 line(s) changed by s#^gate | harness   | required | \. | bash#gate | harness   | required | __h008_no_such_dir | bash#) ===
      430 - gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
      430 + gate | harness   | required | __h008_no_such_dir | bash .claude/tests/project-counters.test.sh
    ...
      AC-2: with one .luau added under src/, the gate command fails and names the suite
        ok   instrument: the 'suite broke' needle rejects an all-green summary
    .claude/tests/harness-gate.test.sh: line 132: cd: /c/Users/ryanc/Projects/first-roblox/__h008_no_such_dir: No such file or directory
        ok   the gate command exits non-zero with the probe present
        FAIL and its output names project-counters as the suite that broke
    ...
    harness-gate: 23 passed, 6 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T133306Z.2851920.bak) ===
      430: gate | harness   | required | . | bash .claude/tests/project-counters.test.sh

    real    1m43.727s

**After** (corrected needle): 22 passed, 7 failed. Same `cd` error; the
assertion now rejects the sentinel and says why:

    === mutate: .claude/harness/project.conf (1 line(s) changed by s#^gate | harness   | required | \. | bash#gate | harness   | required | __h008_no_such_dir | bash#) ===
      430 - gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
      430 + gate | harness   | required | __h008_no_such_dir | bash .claude/tests/project-counters.test.sh
    ...
      AC-4: on a clean tree the gate passes and its evidence line proves the suite ran
        ok   project.conf declares an evidence regex for the harness gate
    .claude/tests/harness-gate.test.sh: line 142: cd: /c/Users/ryanc/Projects/first-roblox/__h008_no_such_dir: No such file or directory
        FAIL the gate command exits 0 on the unmodified tree
        FAIL and its output carries project-counters' own summary line, all passed
        FAIL the evidence regex matches the clean run's output
        FAIL and gates.sh would observe a count of at least 1 from it
      ...
      AC-2: with one .luau added under src/, the gate command fails and names the suite
        ok   instrument: the 'suite broke' needle rejects an all-green summary
    .claude/tests/harness-gate.test.sh: line 142: cd: /c/Users/ryanc/Projects/first-roblox/__h008_no_such_dir: No such file or directory
        FAIL the gate command exits non-zero with the probe present
             got 97, run_gate_cmd's own sentinel: 'cd /c/Users/ryanc/Projects/first-roblox/__h008_no_such_dir' FAILED and the
             gate command never ran. A non-zero exit from a command that did not execute is
             not the gate detecting the probe. cwd as parsed: [__h008_no_such_dir]
             gate output (last 8 lines):

        FAIL and its output names project-counters as the suite that broke
      AC-2, end to end: 'gates.sh --fast' fails on that tree and says which gate and suite
        ok   gates.sh --fast --gate harness exits 1 (a required gate failed)
        ok   the summary reports the harness gate as FAIL
        ok   and counts it as a required failure
        FAIL and the streamed output names project-counters as the suite that broke
        ok   --fast did not skip the harness gate
        ok   the probe is gone and the tree is clean again

    harness-gate: 22 passed, 7 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T134144Z.2874926.bak) ===
      430: gate | harness   | required | . | bash .claude/tests/project-counters.test.sh

    real    2m0.599s

Count: 7 red after, 6 before. The six shared ones are the four AC-4 clean-run
assertions, the `BROKE` line for the probe run, and the streamed `BROKE` line
end to end - all downstream of the cwd, all of which also went red in GREEN
when the parser handed them `. | bash ...` as the cwd. Those four
(previously l.239/243/256/264) and l.337 are therefore covered by this one
probe. Note `cwd as parsed: [__h008_no_such_dir]` - a single field, which is
defect 1's fix visible inside defect 2's failure message.

### Probe C - the `127` branch: command path -> `.claude/tests/__h008_nope/project-counters.test.sh`

The substring `project-counters` survives, so the AC-1 assertions stay green
and only "did the command run" changes. **Measured: 7 red**, the same six
downstream lines as probe B plus the target; the old needle would have
accepted 127.

    === mutate: .claude/harness/project.conf (1 line(s) changed by s#| \. | bash \.claude/tests/project-counters\.test\.sh$#| . | bash .claude/tests/__h008_nope/project-counters.test.sh#) ===
      430 - gate | harness   | required | . | bash .claude/tests/project-counters.test.sh
      430 + gate | harness   | required | . | bash .claude/tests/__h008_nope/project-counters.test.sh
    ...
      AC-2: with one .luau added under src/, the gate command fails and names the suite
        ok   instrument: the 'suite broke' needle rejects an all-green summary
        FAIL the gate command exits non-zero with the probe present
             got 127, the shell's 'cannot execute' / 'not found': the gate command never ran.
             A non-zero exit from a command that did not execute is not the gate detecting
             the probe. command: [bash .claude/tests/__h008_nope/project-counters.test.sh]
             gate output (last 8 lines):
             bash: .claude/tests/__h008_nope/project-counters.test.sh: No such file or directory
        FAIL and its output names project-counters as the suite that broke

    harness-gate: 22 passed, 7 failed

    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T134405Z.2881389.bak) ===
      430: gate | harness   | required | . | bash .claude/tests/project-counters.test.sh

    real    1m44.112s

This is also the run that printed `line 301: floor: command not found` (the
third defect above): the work-count assertion's failure path ran for the
first time in this suite's life.

### Probe summary

| probe | mutation (project.conf l.430) | target assertion | red (count) | restore |
|---|---|---|---|---|
| A | `required` -> `optional` | "is required" | **4**: target + 3 end-to-end consequences of optional | verified, `.bak` `20260917T133855Z` |
| B before | cwd `.` -> missing dir, old needle | (exit-code needle) | 6, target **ok** - the vacuous pass | verified, `20260917T133306Z` |
| B after | cwd `.` -> missing dir, new needle | exit-code needle, 97 | **7**: target + 6 downstream (covers old l.239/243/256/264/337) | verified, `20260917T134144Z` |
| C | command path -> missing file | exit-code needle, 127 | **7**: same shape as B | verified, `20260917T134405Z` |

All timings are local (this machine, 2026-09-17, load not measured); none
from CI. Every mutation went through `scripts/mutate.sh`; no `sed -i`.
`.claude/state/mutations/` holds the log; no `.bak` left behind.

### `gates.sh --fast` at the end of the corrective RED

Green, which is the right shape here: the implementation exists and the
corrected suite is not itself a gate (it would recurse - header of the file),
so no test gate is expected red. Lint, typecheck and the harness gate itself
all pass; the harness gate observes the same 40 GREEN recorded.

    --- gate summary ---
    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (3s, observed 8)
    PASS         unit (14s, observed 197, floor 197)
    PASS         build (1s, observed 25103)
    PASS         harness (16s, observed 40)

    --fast skipped: integration mutation
    All required gates passed (6 ran, 1 unconfigured, 0 known).
    real    2m45.327s          (local; not recorded - a --fast run never is)

### Two transient reds, explained: the suite is not reentrant and was run concurrently

Not a defect in the corrected suite; recorded because an unexplained red must
not be buried, and because the next person running this suite needs the rule.

After the 29/0 clean run and the probes, a fresh run of the finished file
came back **22 passed, 7 failed**, its last `_bad` quoting
`gates.sh --fast --gate harness` as `All required gates passed (1 ran, ...)`
with the probe present. A re-run was 29/0 on a clean tree. Reproducing the
sequence (`gates.sh --fast`, then the suite) gave a *different* red,
**27 passed, 2 failed**: the preceding `--fast` counted `format ... observed
44`, `lint 44`, `typecheck 9` - one extra `.luau` under `src/` during that
run, gone when `git status` looked right after - and the suite's AC-4 "clean"
project-counters run came back `39 passed, 1 failed`.

The cause is in `.claude/state/mutations/log` and in `ps`, not in the file:

    20260917T134913Z  .claude/harness/project.conf  s#^gate | harness   | required | \. | bash#gate | harness   | optional | . | bash#  ...  exited 1  restored (verified)

is a mutation **this RED did not run** (mine are 133306Z, 133855Z, 134144Z,
134405Z), timestamped inside the window of the 22/7 run - so the conf said
`optional` while that run read it, which is exactly the `All required gates
passed` it quoted. And at 09:04:37 local:

    ryanc 2969640 2952490 ?  09:03:25 bash .claude/tests/harness-gate.test.sh
    ryanc 2971794 2971792 ?  09:03:59 bash scripts/gates.sh --fast --gate harness

a second copy of this suite, not one of mine (my reproduction had already
reported completion), running in the same checkout. The orchestrator checking
the handoff's "this suite discriminates" claim with `mutate.sh` is the
expected origin; it is a legitimate thing to do and it cannot be done at the
same time as a run of the suite it checks.

**Rule.** This suite, project-counters, and `gates.sh` all read and write the
one real tree (`src/shared/__probe_*.luau`, `project.conf` under `mutate.sh`,
`.claude/state/gate-logs/`). Two of them running at once in one checkout give
each other's probe files and mutated conf to count, and the result is a red
that names a real assertion and means nothing. **One run at a time per
checkout.** The guard I used before the final run:

    ps -ef | grep -E 'harness-gate\.test\.sh|project-counters\.test\.sh|gates\.sh|mutate\.sh' | grep -v grep

must print nothing first. Whether the suite should detect a concurrent run
itself (a lock file under `.claude/state/`, refused with a named failure) is a
question for a later HARNESS story, not this return: it is new behaviour,
not a defective assertion.

**Final run of the finished file, with that guard satisfied** (polled until the
foreign run exited, ~2 min 15 s; the mutations log was 106 lines before and
after, so nothing mutated the conf during it):

    tree free at 09:08:47 after 27 polls; mutations log lines: 106
    ...
    harness-gate: 29 passed, 0 failed
    suite exit: 0
    mutations log lines after: 106

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-17T15:04:27Z
    commit: c31aa2a (working tree had uncommitted changes)
    tree:   400ac02681ad63b20600f6215add3872b20e15bb
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 43)
    PASS         lint (1s, observed 43, floor 1)
    PASS         typecheck (4s, observed 8)
    PASS         unit (48s, observed 197, floor 197)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (2s, observed 25103)
    PASS         harness (30s, observed 40)
    UNCONFIGURED mutation

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

The gate this story adds is `harness`. It has been observed to fail **four
ways**, each below. Run by the orchestrator in GATES, on the real tree, before
`scripts/gates.sh`.

### Probe 1 (DV-1, AC-5) - break what the gate guards

*What was broken:* one well-formed, untracked `.luau` at
`src/shared/__probe_h008_dv.luau` - a product story adding a file, i.e. the
SEAT-001 condition exactly.

    $ bash scripts/gates.sh --fast --gate harness
        FAIL the working tree carries no stray .luau files, so the baselines mean what they say
        FAIL format reports 43 files on the unmodified tree
        FAIL lint reports 43 files on the unmodified tree
        FAIL typecheck reports 8 files on the unmodified tree
        ... (13 in all)
    project-counters: 27 passed, 13 failed
    FAIL         harness (27s, exit 1) -> .claude/state/gate-logs/harness.log
    1 required gate(s) failed.

*Reverted:* probe removed; `git status --porcelain -- src` empty.

### Probe 2 (DV-2, AC-2) - marking it `slow` must remove it from `--fast`

The mutation the story names as the tempting way to buy AC-6, and the reason
`## Contract` forbids it.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        '$a slow | harness | GATES probe DV-2: marks the gate slow so --fast skips it' \
        -- bash scripts/gates.sh --fast --gate harness
    === mutate: .claude/harness/project.conf (1 line(s) changed by $a slow | harness | ...) ===
    --fast skipped: harness
    All required gates passed (0 ran, 0 unconfigured, 0 known).
    === mutate: command exited 0; restored (verified byte-for-byte against
        .claude/state/mutations/.claude_harness_project.conf.20260917T144031Z.3122968.bak) ===

**`0 ran`, exit 0, on a tree the gate should have failed.** That is the hole
this story closes, demonstrated: a `slow` gate contributes nothing to the fast
loop and says nothing while doing it.

### Probe 3 (DV-3, AC-4) - the evidence line must fire on a gate that did nothing

*What was broken:* the gate command replaced with `true` - exits 0, produces no
output. **Not** a missing suite: see `## Deferred verifications` DV-3, where the
premise the story shipped with was wrong and RED caught it.

    $ bash scripts/mutate.sh .claude/harness/project.conf \
        's#| \. | bash \.claude/tests/project-counters\.test\.sh$#| . | true#' \
        -- bash scripts/gates.sh --gate harness
    FAIL         harness (0s, ran but produced no evidence of work:
                 expected /project-counters: [1-9][0-9]* passed, [0-9]+ failed/)
                 -> .claude/state/gate-logs/harness.log
    === mutate: command exited 1; restored (verified byte-for-byte against
        .claude/state/mutations/.claude_harness_project.conf.20260917T144500Z.3144979.bak) ===

The gate exited 0 and was still **failed**, for the evidence reason
specifically. This is the assertion that makes `exit 0` not equal to "did work".

### Probe 4 (DV-4, AC-3) - a FULL recorded run on a probed tree

*What was broken:* the same untracked `.luau`, with a full `bash scripts/gates.sh`.

    probe present: ?? src/shared/__probe_h008_dv4.luau
    PASS         format (1s, observed 44)
    PASS         lint (1s, observed 44, floor 1)
    PASS         typecheck (3s, observed 9)
    PASS         unit (30s, observed 197, floor 197)
    PASS         build (0s, observed 25136)
    FAIL         harness (26s, exit 1) -> .claude/state/gate-logs/harness.log
    recorded in docs/backlog/stories/HARNESS-008.md (## Gate results)
    1 required gate(s) failed.

    --- what it recorded ---
    tree:   7326cbaa64e4a72cd62b7433a6fc077a5bfbf88c
    result: fail (1 required gate(s) failed)

**This single output is the whole story.** Every pre-existing gate *passed* on
the probed tree - `format` and `lint` cheerfully counted 44 files, `typecheck` 9
- and before this story that was the end of it: green locally, red on CI. Now
`harness` is the one that fails, locally, in the loop. The recorded
`result: fail` also satisfies AC-3's "recorded in `## Gate results` like any
other".

*Reverted:* probe removed, and the **final** clean full run below overwrote the
record, so what ships is the passing run whose tree hash matches the merge.

### AC-6 / DV-5 - the cost, measured to the amended three-part standard

**1. Machine state, with evidence** (the fork-cost probe from PO decision 1,
which is the instrument, not the assertion):

    before: real 0m2.566s / 50 forks = 51 ms per fork
    after:  real 0m4.869s / 50 forks = 97 ms per fork
    CPU load 23 %, no browser or game running

Against PO decision 1's calibration: **41-49 ms quiet, 440 ms under a game**.

**2. Four runs, and their spread.** `bash scripts/gates.sh --fast --gate harness`,
reading the gate's own reported seconds:

| | 1 | 2 | 3 | 4 | mean | worst |
|---|---|---|---|---|---|---|
| quiet | 17 s | 20 s | 18 s | 22 s | **19.25 s** | **22 s** |
| loaded, for contrast (359 ms/fork) | 27 s | 33 s | - | - | 30 s | 33 s |

**Every quiet reading is under the 30 s budget, and the worst has 27 % headroom.**
Under load the same gate breached it - which is the amendment earning its keep.

**A finding about the criterion I wrote, recorded rather than quietly dropped.**
AC-6's *"a spread above ~10 % means the machine was not quiet and the number is
void"* is **too tight for this instrument**: the quiet spread here is 26 %
((22-17)/19.25) while the independent load instrument says the machine is quiet.
The gate reports whole seconds over an ~19 s run that shells out to `stylua`,
`selene`, `rojo` and `luau-lsp`, and that run-to-run variance is real and not
load. So the 10 % figure is a *heuristic for detecting load*, and where it
disagrees with the fork probe, **the fork probe wins**. I judge AC-6 satisfied
on the substance - four quiet readings, worst 22 s, budget 30 s - and I am
**not** moving the budget, which is the thing the criterion actually protects.
The next story to lean on that 10 % should tighten the wording rather than
inherit it as written.

**3. CI cross-check:** owed at DONE, against `HARNESS-006`'s 13 s for the same
suite on CI. Recorded there, not here.

