---
id: HARNESS-002
title: The bootstrap and spike arms of section 3a are never exercised
slug: production-code-cannot-arrive-without-te
epic: 
type: chore
status: in-progress
phase: GREEN
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

**File written:** `.claude/tests/boundaries.test.sh`.
*Amended at RED (Test Developer):* this paragraph said the file classifies as
`test` via `**/*.test.*` and is therefore frozen in GREEN and GATES. It is
not: `bash scripts/classify.sh .claude/tests/boundaries.test.sh` prints
`harness`, because `harness | .claude/**` at `paths.conf:79` precedes the
`test` rules and the first match wins. `harness` is writable in **every**
phase, so the phase lock freezes neither this suite in GREEN nor
`scripts/check-boundaries.sh` (also `harness`) in RED. Nothing here is
protected by the lock; the freeze is honoured by role, and GREEN must not
touch the suite for the same reason it never would - not because a hook
would stop it. RED used `mutate.sh` for every mutation regardless.

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

**Why AC-1 cannot use `refused` or assert a clean exit - and why AC-2 can.**
*Amended at RED (Test Developer):* as written this paragraph said neither
could, because the fixture stories carry no `## Gate results`. Measured at
RED against the unmutated script: the bootstrap fixture exits 1 for exactly
that reason, but the **spike** fixture exits **0** - `check-boundaries.sh`
prints `spike story; gate record not required` and waives the gate-record
rule for spikes. So AC-1 asserts the PRESENCE of this rule's `ok` line and
the ABSENCE of law 1's refusal (the shape of `accepts_manifest` at line 57,
for the reason recorded there), and AC-2 asserts those **and** `$rc -eq 0`,
because `$rc` is what CI acts on and it is available there. Asserting
`rc -eq 0` for the bootstrap fixture would still be a test that can never
pass.

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

- **PLANNED** - `lead-po`, **Opus 5** (`claude-opus-5`), the session model. As
  planned.
- **RED** - `test-developer`, **Fable 5.1** (`claude-fable-5-1`), dispatched with
  an explicit `model: fable` override on the Agent call. As planned; no session
  setting or agent-definition value beat it, and the subagent reported the same
  name back independently.

**Verdict on the RED row, against the condition `models.conf` sets for it** -
that a partitioned contract lets the weaker model write sharper negative
controls than the stronger model produced without one. **The condition held,
and it could have come out the other way.** Evidence, all of it things the
brief did NOT tell it to do:

1. It found the contract's needle analysis incomplete and sharpened it. The
   contract said AC-4 should match law 1's sentence; RED worked out *why* on
   its own - under M3 a `fix` story is **still refused**, for an empty
   inventory, so a needle for "any refusal" would score the mutant caught when
   it was not - and pasted the output proving it.
2. It found a negative control the contract had ruled out. The contract said
   neither acceptance could assert a clean exit; RED found
   `check-boundaries.sh:320` exempts a spike from the gate-record rule, so the
   spike fixture *can* assert `rc -eq 0`, and added a twelfth assertion. That
   is the only assertion in the block checking the status CI acts on rather
   than the message text.
3. It reported a finding that **weakened its own story** rather than inflating
   it: M3 was already dead before this story (see `## Notes`). An agent
   optimising for a clean result does not volunteer that.

Against that: it got one thing wrong in the same direction the contract did -
nothing, in fact, that the contract had right. The contract's own error (the
`test` classification) was found *by* RED, not by the orchestrator.

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

All twelve new assertions live in one `describe` block,
`"the inventory arm is exactly bootstrap, chore and spike"`, appended to
`.claude/tests/boundaries.test.sh` just above `summary`. Level: integration -
a real two-branch fixture repository driven through the real
`scripts/check-boundaries.sh`, because the contract under test is the
script's routing of a story *type*, which lives nowhere else. Every fixture is
built with the existing `scaffold_story <type>` (bootstrap, spike) or with
`story_on_branch`, which RED generalised to take an optional type so AC-4 can
build a `fix` story without a `## Scaffold inventory` it has no business
carrying.

| AC | Assertion name (as printed by the suite) | What it pins |
|---|---|---|
| AC-1 | `a bootstrap story is routed to the inventory arm, by name` | the `note` naming `'bootstrap'` - which arm ran |
| AC-1 | `and a bootstrap inventory naming every file is accepted` | the `ok    every changed source file is named in ## Scaffold inventory` line |
| AC-1 | `and a bootstrap story is not refused under law 1` | absence of `Production code ships with the test that demanded it` |
| AC-2 | `a spike story is routed to the inventory arm, by name` | the `note` naming `'spike'` |
| AC-2 | `and a spike inventory naming every file is accepted` | the same `ok` line |
| AC-2 | `and a spike story is not refused under law 1` | absence of law 1's refusal |
| AC-2 | `and a spike with a complete inventory exits clean, so CI would merge it` | `$rc -eq 0` - available for spike only, see the contract amendment |
| AC-3 | `control: the incomplete bootstrap still enters the bootstrap arm` | the `note` naming `'bootstrap'` on the refused fixture |
| AC-3 | `control: a bootstrap source file missing from the inventory is refused` | `not named in ## Scaffold inventory:` AND `$rc` non-zero (`refused`) |
| AC-3 | `control: and the bootstrap refusal names the file it missed` | `src/helper.ts` in the refusal |
| AC-4 | `control: a fix story whose source moved alone is refused under law 1` | `Production code ships with the test that demanded it` AND `$rc` non-zero |
| AC-4 | `control: and a fix story is never excused by name` | absence of `allowed for a 'fix' story` - the line `*)` would print |

Why AC-1 and AC-2 carry the type-naming `note` and not only the `ok` line: the
`ok` line is also what the three existing `chore` fixtures print, so on its own
it cannot tell a bootstrap that reached the inventory arm from a chore that
did. The note names the type; it is the needle whose negation is not also a
match.

Why AC-4 matches law 1's sentence and not "any refusal": under M3 (`*)`) a
`fix` story is *still refused* - for an empty `## Scaffold inventory` - so a
needle for "exit non-zero with some FAIL" would call the mutant caught when it
was not. The smoke preview in `## Regressions` shows exactly that output.

Edges the story implies and how they are covered: *empty* inventory and *one
of many missing* are the existing chore cases and are out of scope by the
story's own list; AC-3 re-pins *one of two missing* on the bootstrap arm
specifically, because a per-file check that runs on chore's arm has not been
shown to run on bootstrap's until a bootstrap fixture is refused by it.
## Handoff: RED -> GREEN

**GREEN is a no-op on the code.** `scripts/check-boundaries.sh` already
satisfies every assertion below (the clean run is 95/0) and this story's
`## Out of scope` forbids changing it. What GREEN has to do is **verify, not
build**:

1. Run the command below and confirm `boundaries: 95 passed, 0 failed` -
   twelve more than the 83 baseline the contract lets you read out.
2. Confirm `scripts/check-boundaries.sh` is byte-identical to `main`
   (`git diff main -- scripts/check-boundaries.sh` prints nothing). If it is
   not, something other than this story touched it: stop.
3. Confirm `.claude/state/mutations/` holds only `log` - no `.bak` - which is
   what a verified restore leaves behind.
4. Do NOT touch `.claude/tests/boundaries.test.sh`. Note that the phase lock
   will not stop you: it classifies as `harness` (see the contract amendment),
   which is writable in every phase. The freeze is by role.

**Command that runs these tests:**

    bash .claude/tests/boundaries.test.sh

It is one file and there is no way to run a subset. On this machine each run
took **2m20s** (local, Windows 11 / Git Bash, 2026-09-18, four consecutive
runs at 14:36-14:45Z) - not the ~13 minutes the contract budgeted; that
figure may be from a colder cache or a busier machine. CI runs it through the
"Harness self-test" step of `gates.yml` (`bash scripts/selftest.sh`), and no
`gates.sh` gate runs it. `VERBOSE=1` prints the `ok` lines too.

**Current state - green on arrival, by design:**

    ### clean  started 2026-09-18T14:36:14Z
    boundaries: 95 passed, 0 failed
    ### clean  exit=0 finished 2026-09-18T14:38:36Z

There is no verbatim *failure* output from the clean run to paste because
there was none: the implementation exists and is correct. The red that earns
each assertion is the three mutation runs in `## Regressions`, made with
`bash scripts/mutate.sh` and restored byte-for-byte.

**One line per assertion** (twelve, in one `describe` block, in order):

| # | Assertion | AC | Dies under |
|---|---|---|---|
| 1 | `a bootstrap story is routed to the inventory arm, by name` | AC-1 | M1 |
| 2 | `and a bootstrap inventory naming every file is accepted` | AC-1 | M1 |
| 3 | `and a bootstrap story is not refused under law 1` | AC-1 | M1 |
| 4 | `a spike story is routed to the inventory arm, by name` | AC-2 | M2 |
| 5 | `and a spike inventory naming every file is accepted` | AC-2 | M2 |
| 6 | `and a spike story is not refused under law 1` | AC-2 | M2 |
| 7 | `and a spike with a complete inventory exits clean, so CI would merge it` | AC-2 | M2 |
| 8 | `control: the incomplete bootstrap still enters the bootstrap arm` | AC-3 | M1 |
| 9 | `control: a bootstrap source file missing from the inventory is refused` | AC-3 | M1 |
| 10 | `control: and the bootstrap refusal names the file it missed` | AC-3 | M1 |
| 11 | `control: a fix story whose source moved alone is refused under law 1` | AC-4 | M3 |
| 12 | `control: and a fix story is never excused by name` | AC-4 | M3 |

**Files touched:**

- `.claude/tests/boundaries.test.sh` - the new `describe` block appended
  above `summary`, and `story_on_branch` generalised to
  `story_on_branch [type]` with `type` defaulting to `feature`. Every
  existing call site passes no argument, so their behaviour is unchanged; the
  clean run's 83 pre-existing assertions still pass. **AC-4's `fix` fixture
  is built with `story_on_branch fix`** - that is the choice the contract left
  to RED: generalise rather than write inline, because `story_on_branch`
  already carries the filled `## Handoff` a `feature|fix` story needs to get
  past the handoff rule, and a `fix` story has no business carrying the
  `## Scaffold inventory` that `scaffold_story` writes.
- `docs/backlog/stories/HARNESS-002.md` - `## Test plan`, this section,
  `## Regressions`, and two in-place amendments to `## Contract`: the file's
  classification (`harness`, not `test`), and the spike fixture's exit status
  (`check-boundaries.sh` waives the gate-record rule for a spike - it prints
  `spike story; gate record not required` - which is what licenses assertion
  #7's `rc -eq 0`).

**Export shape pinned:** none in the usual sense - nothing is imported. What
the tests pin is the stdout and exit status of `scripts/check-boundaries.sh`
when run from a fixture repository with `GITHUB_HEAD_REF=` and `PR_HEAD_SHA=`
cleared, against `main`, for a story of the given `type:`:

- the `note` line contains `source file(s) without tests - allowed for a
  '<type>' story` with `<type>` being exactly the frontmatter type;
- the acceptance line is exactly `ok    every changed source file is named in
  ## Scaffold inventory` (four spaces after `ok`);
- the per-file refusal contains `not named in ## Scaffold inventory:` and the
  omitted path, with a non-zero exit;
- law 1's refusal contains `Production code ships with the test that demanded
  it`, with a non-zero exit;
- a `spike` story with a complete inventory and no `## Gate results` exits 0.

Not constrained: the wording of anything else the script prints, the order of
the lines, and whether the count in the note is `1` or `2` - the fixture's
`src/main.ts` already exists with the same content on `main`, so only
`src/helper.ts` is a changed file and the note says `1 source file(s)`; the
assertions do not depend on that number.

**Negative controls and their expected values.** All are mechanical - the
contract has no calibrated thresholds - and all twelve assertions have
executed against the shipped script (nothing fails at import here), so the
values are measured, not claimed:

| Control | Threshold | Expected under correct script | Measured (clean run) | Measured under its mutant |
|---|---|---|---|---|
| AC-3 (#8-#10) | `$rc != 0` and refusal names `src/helper.ts` | refused, `rc=1` | passed (refused with the file named) | M1: 3 of 3 red, the run went to law 1 instead |
| AC-4 (#11-#12) | `$rc != 0` and message is law 1's | refused, `rc=1` | passed | M3: 2 of 2 red, the run printed `allowed for a 'fix' story` and refused for an EMPTY inventory instead |
| #7 spike exit | `$rc == 0` | `0` | `0` (measured directly at RED; output in the contract amendment) | M2: red, `rc=1` |

**Things GREEN and the orchestrator should know:**

- **M3 was already killed before this story.** Under `*)` the existing
  assertion `a feature story whose source moved alone` (line ~1291) also goes
  red, because a `feature` story is routed to the inventory arm too - so the
  full run under M3 is 3 failed, not the 2 the AC-4 block alone gives. The
  story's `## Context` says widening the arm "changes behaviour that no
  assertion observes"; that was true of M1 and M2 (measured at PLANNED as
  83/0 under `chore)`) and is **not** true of M3. AC-4 is still a real
  criterion - it pins that `fix` specifically is refused, and the handoff
  rule at `feature|fix)` makes `fix` a type with routing of its own - but it
  is the second observer of M3, not the first. No criterion changes; recorded
  so nobody reads the AC-4 kill as evidence the suite was previously blind
  there.
- **The phase lock protects nothing this story touches.** Both the suite and
  the script classify as `harness` (contract amendment). RED made every
  mutation through `mutate.sh` anyway, and GREEN should treat the suite as
  frozen by rule rather than by hook.
- **The spike fixture exits 0** because of the gate-record waiver for spikes.
  If a later story changes that waiver, assertion #7 is the one that will
  notice, and it will be right to.
- Timings above are all **local**; none are from CI. The suite sets no
  timeouts and has no hooks, so there is no budget to size.
- `bash scripts/gates.sh --fast` at the end of RED: all six required gates
  PASS (format, lint, typecheck, unit 197, build, harness 40), coverage
  unconfigured. That is the expected shape here rather than a red test gate,
  because no gate runs this suite - the PO decision in `## Context`.
- Model: this dispatch ran on **Fable 5.1** (`claude-fable-5-1`), which is the
  planned `fable` row; no override was reported to me.

## Regressions

The implementation existed before every assertion in this story, so each one
went green on its first run and "watch it fail" is replaced, not waived: one
mutation of the specific behaviour each block pins, one run of the whole
suite, one verified restore. All three were made with
`bash scripts/mutate.sh scripts/check-boundaries.sh '<expr>' -- bash .claude/tests/boundaries.test.sh`
on 2026-09-18, in sequence immediately after the clean run, Windows 11 / Git
Bash. The `###` lines are the driver's timestamps; everything between them is
the suite's and `mutate.sh`'s own output. The non-verbose suite prints only
`describe` headers and `FAIL` blocks, so the headers of blocks with no failure
are omitted here for length; nothing else is.

Clean run, immediately before the three mutants:

```
### clean  started 2026-09-18T14:36:14Z
boundaries: 95 passed, 0 failed
### clean  exit=0 finished 2026-09-18T14:38:36Z
```

**M1 - drop `bootstrap` from the arm. Caught by AC-1 (#1-#3) and AC-3 (#8-#10): 6 red.**

```
### M1  started 2026-09-18T14:38:36Z
=== mutate: scripts/check-boundaries.sh (1 line(s) changed by 225s#bootstrap|chore|spike)#chore|spike)#) ===
  225 -     bootstrap|chore|spike)
  225 +     chore|spike)

=== mutate: running bash .claude/tests/boundaries.test.sh ===

  the inventory arm is exactly bootstrap, chore and spike
    FAIL a bootstrap story is routed to the inventory arm, by name
         expected to contain: source file(s) without tests - allowed for a 'bootstrap' story
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
    FAIL and a bootstrap inventory naming every file is accepted
         expected to contain: ok    every changed source file is named in ## Scaffold inventory
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
    FAIL and a bootstrap story is not refused under law 1
         refused: ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
    FAIL control: the incomplete bootstrap still enters the bootstrap arm
         expected to contain: source file(s) without tests - allowed for a 'bootstrap' story
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
    FAIL control: a bootstrap source file missing from the inventory is refused
         expected a refusal saying: not named in ## Scaffold inventory:
         actual:                    ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
    FAIL control: and the bootstrap refusal names the file it missed
         expected to contain: src/helper.ts
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.

boundaries: 89 passed, 6 failed

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260918T143836Z.29657.bak) ===
  225:     bootstrap|chore|spike)
### M1  exit=1 finished 2026-09-18T14:40:58Z
```

**M2 - drop `spike` from the arm. Caught by AC-2 (#4-#7): 4 red.**

```
### M2  started 2026-09-18T14:40:58Z
=== mutate: scripts/check-boundaries.sh (1 line(s) changed by 225s#bootstrap|chore|spike)#bootstrap|chore)#) ===
  225 -     bootstrap|chore|spike)
  225 +     bootstrap|chore)

=== mutate: running bash .claude/tests/boundaries.test.sh ===

  the inventory arm is exactly bootstrap, chore and spike
    FAIL a spike story is routed to the inventory arm, by name
         expected to contain: source file(s) without tests - allowed for a 'spike' story
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
           spike story; gate record not required
    FAIL and a spike inventory naming every file is accepted
         expected to contain: ok    every changed source file is named in ## Scaffold inventory
         actual:               ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
           spike story; gate record not required
    FAIL and a spike story is not refused under law 1
         refused: ok    story files validated
         ok    harness state not tracked
         FAIL  1 source file(s) changed with no test changes. Production code ships with the test that demanded it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
           spike story; gate record not required
    FAIL and a spike with a complete inventory exits clean, so CI would merge it
         expected: 0
         actual:   1

boundaries: 91 passed, 4 failed

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260918T144058Z.52945.bak) ===
  225:     bootstrap|chore|spike)
### M2  exit=1 finished 2026-09-18T14:43:20Z
```

**M3 - widen the arm to `*)`. Caught by AC-4 (#11-#12): 2 red, plus the pre-existing feature assertion: 3 red in all.**

```
### M3  started 2026-09-18T14:43:20Z
=== mutate: scripts/check-boundaries.sh (1 line(s) changed by 225s#bootstrap|chore|spike)#*)#) ===
  225 -     bootstrap|chore|spike)
  225 +     *)

=== mutate: running bash .claude/tests/boundaries.test.sh ===

  production code arrives with tests, or with an inventory
    FAIL a feature story whose source moved alone
         expected a refusal saying: Production code ships with the test that demanded it
         actual:                    ok    story files validated
         ok    harness state not tracked
           1 source file(s) without tests - allowed for a 'feature' story, so the inventory must account for them
         FAIL  story T-1: source changed without tests, and ## Scaffold inventory is empty. Name every production file written and the test that covers it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
         ok    ## Handoff is filled in

  the inventory arm is exactly bootstrap, chore and spike
    FAIL control: a fix story whose source moved alone is refused under law 1
         expected a refusal saying: Production code ships with the test that demanded it
         actual:                    ok    story files validated
         ok    harness state not tracked
           1 source file(s) without tests - allowed for a 'fix' story, so the inventory must account for them
         FAIL  story T-1: source changed without tests, and ## Scaffold inventory is empty. Name every production file written and the test that covers it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
         ok    ## Handoff is filled in
    FAIL control: and a fix story is never excused by name
         excused: ok    story files validated
         ok    harness state not tracked
           1 source file(s) without tests - allowed for a 'fix' story, so the inventory must account for them
         FAIL  story T-1: source changed without tests, and ## Scaffold inventory is empty. Name every production file written and the test that covers it.
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
         ok    ## Handoff is filled in

boundaries: 92 passed, 3 failed

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260918T144320Z.74260.bak) ===
  225:     bootstrap|chore|spike)
### M3  exit=1 finished 2026-09-18T14:45:45Z
```

After the chain: `git status --short scripts/` is empty,
`cmp scripts/check-boundaries.sh <(git show HEAD:scripts/check-boundaries.sh)`
is silent, and `.claude/state/mutations/` contains only `log`.

**Why AC-4's needle is law 1's sentence and not "any refusal".** The M3 block
above shows it: under `*)` the `fix` fixture is still refused (`FAIL  story
T-1: source changed without tests, and ## Scaffold inventory is empty`) and
still exits non-zero - it has simply been excused by name (`allowed for a
'fix' story`) and then refused by a different rule. A needle for "some FAIL
and rc != 0" would have called that mutant caught. The same output was seen
first in a 6-second smoke preview (helpers + the new block assembled in a
scratch file outside the tree) run before the full chain; it agreed with the
full runs on every assertion that dies, and is not pasted because the full
runs are the evidence.

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

### Orchestrator's verification of RED

RED's handoff makes three claims that contradict the contract, and a mutation
table. A table is a claim until somebody runs one, so these were reproduced by
the orchestrator rather than accepted.

**1. "M3 was already dead before this story" - CONFIRMED, on a different input.**
RED measured M3 against the *new* suite. The claim is about the *old* one, so
the orchestrator stashed the new block and ran M3 against the pre-story suite:

```
$ git stash push -- .claude/tests/boundaries.test.sh
$ bash scripts/mutate.sh scripts/check-boundaries.sh \
    '225s#bootstrap|chore|spike)#*)#' -- bash .claude/tests/boundaries.test.sh

    FAIL a feature story whose source moved alone
         FAIL  story T-1: source changed without tests, and ## Scaffold
               inventory is empty.
boundaries: 82 passed, 1 failed
=== mutate: command exited 1; restored (verified byte-for-byte ...) ===
```

82 + 1 = 83, the baseline. The pre-existing `feature` assertion already caught
M3. **So this story closes M1 and M2 - the bootstrap and spike arms - and AC-4
is a type-specific observer of a mutant that was already covered.** That is a
narrower delivery than the Context as first written implied, and it is recorded
here rather than left for a reader to discover.

**2. The M2 row of the handoff table - CONFIRMED exactly.** Run by the
orchestrator against the new suite:

```
    FAIL a spike story is routed to the inventory arm, by name
    FAIL and a spike inventory naming every file is accepted
    FAIL and a spike story is not refused under law 1
    FAIL and a spike with a complete inventory exits clean, so CI would merge it
boundaries: 91 passed, 4 failed
=== mutate: command exited 1; restored (verified byte-for-byte ...) ===
```

`91 passed, 4 failed`, and the four are exactly AC-2's four. Note the refusal a
spike story receives under M2: `Production code ships with the test that
demanded it` - the exception deleted, which is the failure this story exists to
make observable.

**3. "The suite classifies as `harness`, not `test`" - CONFIRMED; the contract
was wrong.**

```
$ bash scripts/classify.sh .claude/tests/boundaries.test.sh scripts/check-boundaries.sh
harness	.claude/tests/boundaries.test.sh
harness	scripts/check-boundaries.sh
```

`harness | .claude/**` precedes every `test` rule in `paths.conf` and the first
match wins. **The phase lock froze nothing this story touched** - both the suite
and the script under test are writable in every phase. The freeze held by role
discipline alone. This is a general property worth knowing: the harness's own
test suites are not protected by the harness's own lock.

**Tree state after all verification:** `scripts/check-boundaries.sh` byte-identical
to `main`, `.claude/state/mutations/` holding only `log`, no `.bak`.

### GREEN was a no-op, verified rather than delegated

The handoff named four things GREEN had to VERIFY rather than build. No
subagent was dispatched; the orchestrator ran each one. Output, in order:

```
$ bash .claude/tests/boundaries.test.sh
  the inventory arm is exactly bootstrap, chore and spike
boundaries: 95 passed, 0 failed

$ git diff main -- scripts/check-boundaries.sh
   [no diff]

$ ls .claude/state/mutations/
log

$ git diff --stat HEAD -- .claude/tests/boundaries.test.sh
   [no diff]

$ git diff --name-only main...HEAD
   .claude/tests/boundaries.test.sh
   docs/backlog/stories/HARNESS-002.md
```

95/0 reproduced independently of RED. The script under test is byte-identical
to `main`, the mutations directory holds only its log, the suite is untouched
since the RED commit, and **no source or config file is in this story's diff at
all** - which is the strongest form of "GREEN built nothing".

`bash scripts/gates.sh --fast` at the end of GREEN: all six required gates
PASS (format 43, lint 43, typecheck 8, unit 197, build 25103, harness 40),
coverage unconfigured. A partial run, so not recorded as evidence - the full
run before REVIEW is what judges the story.

### The audit entry

The audit entry for C2 should be read as **closed on E4-E6 and open on the arm**.
`docs/wiki/audits/enforcement-mutants-2026-09-15.md` is a record of a run on
commit `7b6f6db` and is not edited by this story.
