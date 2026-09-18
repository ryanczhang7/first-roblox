---
id: HARNESS-002
title: The bootstrap and spike arms of section 3a are never exercised
slug: production-code-cannot-arrive-without-te
epic: 
type: chore
status: todo
phase: PLANNED
branch: story/HARNESS-002-production-code-cannot-arrive-without-te
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Filed from `docs/wiki/audits/enforcement-mutants-2026-09-15.md`, cluster C2.

**The original premise no longer holds, and the criteria were rewritten at
PLANNED because of it.** The audit recorded that `.claude/tests/boundaries.test.sh`
had no fixture exercising any branch of section 3a, and that the string
"Production code ships with the test that demanded it" appeared nowhere in the
suite. Commit `8edf687` ("Harness refresh 19 -> 27, part 1") added
`describe "production code arrives with tests, or with an inventory"` at
`.claude/tests/boundaries.test.sh:1280`, which covers all three mutants the
audit named. Verified by the orchestrator before the phase moved, against a
baseline of `boundaries: 83 passed, 0 failed` (the audit's baseline was 41):

| Audit ref | Line today | Expression | Suite under the mutant | Verdict |
|---|---|---|---|---|
| E4 | 223 | the `src`/`tst` predicate replaced by `false` | 78 passed, **5 failed** | killed |
| E5 | 228 | `228s#if ! #if #` | 79 passed, **4 failed** | killed |
| E6 | 234 | the per-file `grep -qF` short-circuited to `true` | 81 passed, **2 failed** | killed |

Each run was made with `bash scripts/mutate.sh`, which restored the file and
verified the restore byte-for-byte against its backup. The full output, with the
exact expressions, is in `## Notes`. The audit's line numbers (146/151/157) had
shifted to 223/228/234.

**What is still exposed, and what this story now covers.** Section 3a's case arm
at `scripts/check-boundaries.sh:225` is `bootstrap|chore|spike)` - three story
types are routed to the `## Scaffold inventory` check instead of to law 1's
refusal. Every fixture in the suite is `feature` (via `story_on_branch`) or
`chore` (via `scaffold_story`, called three times, always with `chore`). Neither
`bootstrap` nor `spike` is exercised anywhere. So narrowing that arm - dropping
`bootstrap`, dropping `spike`, or widening it to `*)` - changes behaviour that no
assertion observes. The bootstrap exception in `rules.md` is the rule the whole
`SCAFFOLD` phase depends on, and it is the one arm of the three with no test.

**Measured, not inferred.** The orchestrator ran that mutation at PLANNED before
rewriting the criteria, because a gap nobody has demonstrated is a hypothesis:

```
bash scripts/mutate.sh scripts/check-boundaries.sh \
  '225s#bootstrap|chore|spike)#chore)#' -- bash .claude/tests/boundaries.test.sh

boundaries: 83 passed, 0 failed
=== mutate: command exited 0; restored (verified byte-for-byte against
    .claude/state/mutations/scripts_check-boundaries.sh.20260918T142638Z.734.bak) ===
  225:     bootstrap|chore|spike)
```

**It survived** - byte-identical to the 83/0 baseline, exit 0. The bootstrap
exception can be deleted outright from the enforcement script and the whole
suite stays green. That is what this story now exists to fix.

**Correction to the guard named when this story was filed.** The original
Context said the required gate was `unit` (`bash scripts/selftest.sh`). That is
wrong for this project on both halves: `unit` is `lune run test` (Luau), and the
`harness` gate runs only `bash .claude/tests/project-counters.test.sh` - because
`HARNESS-008` measured the full `selftest.sh` at 10-55 minutes on this machine
and deliberately kept it out of the gates.

**No `gate |` row in `project.conf` runs `boundaries.test.sh`.** The artifact of
this story is guarded by the **"Harness self-test" step at
`.github/workflows/gates.yml:108`** (`bash scripts/selftest.sh`), which is a
required step of the required `gates` workflow, and by `bash scripts/ci-local.sh`
locally. `required_gates` cannot name it, because it is a workflow step rather
than a gate id. PO decision, recorded here rather than resolved by adding a
gate: a regression in this artifact is caught by CI and not by
`bash scripts/gates.sh`, and adding a gate for it would put ~13 minutes on every
story's gate run to protect a file only harness stories touch.

## Acceptance criteria

- **AC-1** - Given a `bootstrap` story whose diff changes source files and no
  test file, and whose `## Scaffold inventory` names every changed source file,
  when `check-boundaries.sh` runs, then it reports
  `every changed source file is named in ## Scaffold inventory` and does NOT
  emit law 1's refusal.
  *Semantics:* this is the bootstrap exception in `rules.md`. If the arm stops
  routing `bootstrap`, the one story type that is ALLOWED to write source
  without tests is refused for writing source without tests, and `SCAFFOLD`
  becomes unusable.
- **AC-2** - Given a `spike` story in the same situation, when
  `check-boundaries.sh` runs, then it reports the same acceptance.
- **AC-3** - Given a `bootstrap` story whose `## Scaffold inventory` omits one
  of two changed source files, when `check-boundaries.sh` runs, then it FAILs
  naming the omitted file and exits non-zero.
  *Negative control for AC-1 and AC-2:* without it, an arm that accepts every
  `bootstrap` story unconditionally satisfies both, and the per-file check is
  never shown to run on that arm at all.
- **AC-4** - Given a `fix` story whose diff changes a source file and no test
  file, when `check-boundaries.sh` runs, then it FAILs with
  `Production code ships with the test that demanded it` and exits non-zero.
  *Negative control for the width of the arm:* `fix` is not one of the three
  types and must not be routed to the inventory check. This is what refuses a
  widening of the arm to `*)`, which every other criterion here would accept.

**Mutants these criteria are required to kill**, all on
`scripts/check-boundaries.sh:225`, to be run and pasted by the phase that owns
each one:

| Mutant | Expression | Must be caught by |
|---|---|---|
| M1 | drop `bootstrap` from the arm | AC-1 |
| M2 | drop `spike` from the arm | AC-2 |
| M3 | widen the arm to `*)` | AC-4 |

## Contract

**Nothing in `scripts/check-boundaries.sh` changes.** This story adds
assertions only. No exported signature changes, so there are no callers to
list; `scripts/check-boundaries.sh` is invoked by
`.github/workflows/boundaries.yml:25` and by `scripts/ci-local.sh`, and both are
untouched.

**File written:** `.claude/tests/boundaries.test.sh` - classified `test` by
`paths.conf` (`**/*.test.*`), so it is writable in RED and frozen in GREEN and
GATES. Confirm with `bash scripts/classify.sh .claude/tests/boundaries.test.sh`.

**Helpers that already exist and must be reused rather than reinvented**, all in
that file unless noted:

| Helper | Line | Semantics |
|---|---|---|
| `scaffold_story <type>` | 1315 | Inventory body on stdin. Writes `docs/backlog/stories/T-1.md` on a fresh `story/T-1-fixture` branch cut from `main`, frontmatter `type: <type>`, `phase: REVIEW`. **Already parameterised by type** - `scaffold_story bootstrap` and `scaffold_story spike` need no new helper. Does NOT commit; callers run `commit_all`. |
| `story_on_branch` | ~1005 | Body on stdin, but `type: feature` is hardcoded and it DOES commit. Not usable for AC-4, which needs `fix`. |
| `commit_all [msg]` | 64 | Stages and commits everything in the fixture. |
| `run_boundaries` | 32 | Runs the script in the fixture against `main` with `GITHUB_HEAD_REF=` and `PR_HEAD_SHA=` cleared. Sets **both** `$out` and `$rc` as globals. |
| `refused <what> <needle>` | 40 | Asserts `$out` contains the needle **and** `$rc` is non-zero. The right helper for AC-3 and AC-4. |
| `assert_contains <what> <needle> <haystack>` | `_lib.sh:43` | Substring only, no status. The right helper for AC-1 and AC-2. |

**Why AC-1 and AC-2 cannot use `refused` or assert a clean exit.** These fixture
stories carry no `## Gate results`, so every run of them also fails with
`## Gate results was not written by scripts/gates.sh`. What AC-1 and AC-2 assert
is therefore the PRESENCE of this rule's `ok` line, not a zero exit - the same
shape as the existing `accepts_manifest` helper at line 57 and for the reason
recorded there. Asserting `rc -eq 0` here would be a test that can never pass.

**AC-4 needs a `fix`-typed fixture and there is no helper for one.**
`scaffold_story` writes a `## Scaffold inventory` section, which a `fix` story
has no business carrying; `story_on_branch` hardcodes `feature`. RED writes the
fixture inline or generalises one of the two - its choice, but say which in the
handoff.

**Exact strings the assertions match.** Anchored on the message rather than on a
fragment a differently-worded refusal would also satisfy:

- acceptance: `ok    every changed source file is named in ## Scaffold inventory`
- per-file refusal: `not named in ## Scaffold inventory:` followed by the path
- law 1 refusal: `Production code ships with the test that demanded it`
- the `note` the arm emits before the inventory check, which names the type and
  so distinguishes the three arms from each other:
  `source file(s) without tests - allowed for a '<type>' story`

That last string is the one that makes AC-1 and AC-2 distinguishable from each
other and from the existing `chore` case. A test asserting only the acceptance
line would pass under M1 if some other fixture happened to reach the same
branch; asserting the type-naming note as well pins which arm ran.

**Oracle partition.** All four criteria are **mechanical**: the strings above are
already emitted by code that exists, and the story pins them. Nothing here is
oracle-free and nothing needs calibrating. The negative controls are AC-3 and
AC-4, and both are real runs of the real script rather than metrics.

**Baseline the story may read out rather than re-derive:** `boundaries: 83
passed, 0 failed`, measured by the orchestrator at PLANNED on commit `cffcb4a`,
Windows 11 / Git Bash. The suite takes **~13 minutes** on this machine - budget
for that rather than assuming a fast loop. Four new assertions are expected; a
run reporting fewer than 83 passes after GREEN is a regression, not a rounding
difference.

**Test-only dependencies:** none. The suite is bash, git and coreutils, and
`rules.md` forbids reaching for python here.

## Model guidance

Planned by `bash scripts/plan.sh write HARNESS-002` from `.claude/harness/models.conf`.
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
## Out of scope

- **Adding a gate that runs `boundaries.test.sh`.** PO decision recorded in
  `## Context`: the ~13-minute cost lands on every story, and `HARNESS-008`
  already settled that the full self-test stays out of the gates. CI covers it.
- **Re-testing E4, E5 and E6.** They are killed by assertions that already
  exist; the evidence is in `## Context` and `## Notes`. Do not add duplicate
  fixtures for them.
- **Section 3a's other branches** - the empty-inventory check, the per-file
  check and law 1's predicate. Covered, and verified covered.
- **`scripts/check-boundaries.sh` itself.** No production change is in scope; if
  one turns out to be needed, that is a finding to raise, not a fix to make.
- **Editing the audit document.** It is a record of a run on commit `7b6f6db`.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. -->

## Gate results

## Notes

**Supersession evidence.** The three mutation runs that retired the original
criteria, made at PLANNED on commit `cffcb4a` against
`bash .claude/tests/boundaries.test.sh` (baseline `83 passed, 0 failed`):

```
================ MUTANT E4 ================
expr: 223s#\[ "$src" -gt 0 \] && \[ "$tst" -eq 0 \]#false#
    FAIL and the refusal names the file it missed
         expected to contain: src/helper.ts
         actual:               ok    story files validated
         ok    source changes accompanied by test changes (1 source, 0 test)
    FAIL an inventory naming every file is accepted
         expected to contain: ok    every changed source file is named in ## Scaffold inventory
boundaries: 78 passed, 5 failed
=== mutate: command exited 1; restored (verified byte-for-byte against
    .claude/state/mutations/scripts_check-boundaries.sh.20260918T062810Z.1483071.bak) ===

================ MUTANT E5 ================
expr: 228s#if ! #if #
    FAIL and the refusal names the file it missed
         expected to contain: src/helper.ts
    FAIL an inventory naming every file is accepted
         expected to contain: ok    every changed source file is named in ## Scaffold inventory
         FAIL  story T-1: source changed without tests, and ## Scaffold inventory is empty.
boundaries: 79 passed, 4 failed
=== mutate: command exited 1; restored (verified byte-for-byte against
    .claude/state/mutations/scripts_check-boundaries.sh.20260918T064039Z.1513478.bak) ===

================ MUTANT E6 ================
expr: 234s#grep -qF -- "$p" ||#true ||#
    FAIL a source file missing from the inventory
         expected a refusal saying: not named in ## Scaffold inventory:
         ok    every changed source file is named in ## Scaffold inventory
    FAIL and the refusal names the file it missed
         expected to contain: src/helper.ts
boundaries: 81 passed, 2 failed
=== mutate: command exited 1; restored (verified byte-for-byte against
    .claude/state/mutations/scripts_check-boundaries.sh.20260918T065011Z.1534485.bak) ===
```

E4's third line of output - `ok source changes accompanied by test changes (1
source, 0 test)` - is precisely the symptom the audit predicted: the rule off,
reporting a pass in the same breath. It is now caught.

The audit entry for C2 should be read as **closed on E4-E6 and open on the arm**.
`docs/wiki/audits/enforcement-mutants-2026-09-15.md` is a record of a run on
commit `7b6f6db` and is not edited by this story.
