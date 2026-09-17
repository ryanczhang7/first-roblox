---
id: HARNESS-008
title: The fast loop cannot see a harness suite it just broke
slug: the-fast-loop-cannot-see-a-harness-suite
epic: 
type: chore
status: todo
phase: PLANNED
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
  **under 30 s** on this machine.
  *Semantics:* the whole `selftest.sh` is 10-55 minutes here, so "run everything
  in `--fast`" is not the answer and this criterion is what rules it out. The
  band is a budget, not a measurement to be widened later: if the only honest
  implementation exceeds it, that is a finding to raise, not a number to move.

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
`.claude/tests/project-counters.test.sh`, which is ~13 s locally and is the one
suite that reads the real tree. Something like:

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

### The phase lock enforces nothing here

`.claude/harness/project.conf` and `.claude/tests/**` both classify as `harness`,
writable in every phase - as in `HARNESS-006` and `HARNESS-007`. The RED/GREEN
split is honoured, not enforced; the orchestrator reads the diff at each
boundary.

### This story does not bump `VERSION`

Same reason as `HARNESS-007`: the check is scoped to non-story branches on
unbootstrapped repos, and this is neither. `SEAT-001` changed `project.conf` on a
story branch and `check-boundaries.sh` passed without one.

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

_(rendered by `bash scripts/plan.sh write HARNESS-008` at the end of PLANNED.)_

## Notes

**Mutations for acceptance**, via `bash scripts/mutate.sh`:

1. Mark the new gate `slow`. Predicted: AC-2 goes red - `--fast` stops running
   it. This is the mutation that matters, because marking it slow is the tempting
   way to make AC-6 pass.
2. Point the gate's command at a suite that does not exist. Predicted: AC-4's
   evidence control fires rather than the gate silently passing.

**Where this came from.** `SEAT-001`'s `## PO ruling on the return to RED from
REVIEW`, which records the incident, the two candidate fixes and why neither was
done inside that story.

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

