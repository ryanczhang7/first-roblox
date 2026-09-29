---
id: HARNESS-019
title: Lock coverage counts only path-shaped contract tokens
slug: lock-coverage-counts-only-path-shaped-co
epic: 
type: fix
status: in-review
phase: REVIEW
branch: story/HARNESS-019-lock-coverage-counts-only-path-shaped-co
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

<!-- Why this story exists. Link the epic and any wiki pages that constrain it.
     Name the REQUIRED gate that would fail if this story's artifact broke. If
     only an optional gate can, put it in required_gates above before RED:
     every required gate once passed over a story none of them exercised. -->

`bash scripts/plan.sh write <id>` decides "Lock coverage" (`lock_scan` in
`scripts/plan.sh`). When the Contract has no `### Files` table, it greps the
whole Contract text for anything shaped like `name.ext`, resolves every hit at
the repository root, and classifies it. One `source`, `test` or `config` hit
suppresses the exception, and RED then follows the plain plan onto the weaker
model.

Observed on 2026-09-29 with HARNESS-018. Every file it touched is `harness`,
yet it printed:

    Lock coverage: SUPPRESSED by `1.5` (source), `boundaries.test.sh` (test), `check-boundaries.sh` (source) (+8 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.

`1.5` came from the prose "1.5 MiB". `check-boundaries.sh` and
`boundaries.test.sh` are bare filenames whose real homes are
`scripts/check-boundaries.sh` and `.claude/tests/boundaries.test.sh`, both
`harness`. `hooks/lib.sh` is a partial path of `.claude/hooks/lib.sh`, and at
the root it classifies as `source`. RED was planned onto `fable` for exactly the
kind of story the `unenforced` exception exists to keep on `opus`. HARNESS-014
saw the same failure (`5.3.15`, `i.e`, `classify.sh`, `mutate.sh`), gave stories
the `### Files` table as the remedy, and left the fallback regex alone as "a
separate question". This story answers that question.

The direction of the error matters. A token counted wrongly as `source` fails
toward the WEAK side, silently. A path that is dropped wrongly fails toward
`opus`, which is the safe side. So the fix narrows what counts, and the
`### Files` table remains the way to state a bare new file precisely.

Required gate: none of `project.conf`'s gates run `.claude/tests/plan.test.sh`.
The `harness` gate runs only `project-counters.test.sh`. It is run by CI's
`bash scripts/selftest.sh` step (`.github/workflows/gates.yml`), which is
required for merge. That is the check that fails if this breaks.

## Acceptance criteria

<!-- Each AC is independently testable and phrased as observable behaviour.
     The Test Developer writes at least one failing test per AC.
     An AC that names a statistic, a metric or a threshold names a NEGATIVE
     CONTROL too: the deliberately broken input the metric must reject, and
     roughly what it should score. A criterion can be perfectly testable and
     still be blind to the defect it exists to catch, and that is more
     dangerous than a vague one - it survives review and goes green. -->

- **AC-1** — Given a Contract with no `### Files` table that names
  `scripts/check-boundaries.sh` and `.claude/tests/boundaries.test.sh`, and
  whose prose also contains `1.5 MiB` and the bare filenames
  `check-boundaries.sh` and `boundaries.test.sh`, when `plan.sh` runs, then the
  lock-coverage line reads `APPLIES` for exactly 2 paths scanned from the
  Contract text, and `plan.sh models` puts RED on `opus` with the "lock freezes
  none of the paths" reason.
- **AC-2** — A token with no `/` counts only if it exists in the working tree
  at the repository root. Given a Contract naming `scripts/plan.sh` and a bare
  `rokit.toml`: when `rokit.toml` exists at the root, the line reads
  `SUPPRESSED by` `rokit.toml` (config); when it does not, the line reads
  `APPLIES` for 1 path.
- **AC-3** — A version-like token, meaning digits separated by dots with an
  optional leading `v` (`1.5`, `5.3.15`, `v2.0`), is never counted, even when a
  file of that name exists at the root. Given a Contract naming
  `scripts/plan.sh` and the prose `bash 5.3.15`, `1.5 MiB` and `v2.0`, with a
  file `5.3.15` present at the root, the line reads `APPLIES` for 1 path.
- **AC-4** — A token that contains `/`, does not exist in the tree, and is a
  trailing `/`-segment of another token scanned from the same Contract is the
  same path, and is not counted separately. Given a Contract naming
  `.claude/hooks/lib.sh` and later `hooks/lib.sh`, the line reads `APPLIES` for
  1 path. The control: a `/` path that stands alone and classifies as `source`
  (`src/core/world.ts`) still suppresses, whether or not it exists.
- **AC-5** — HARNESS-018 is the reproduction. Given this repository's own
  `docs/backlog/stories/HARNESS-018.md`, unmodified, `plan.sh` reports
  `Lock coverage: APPLIES` and `plan.sh models` puts RED on `opus`.

## Contract

<!-- Written by the Lead PO BEFORE RED, and AMENDABLE BY RED IN PLACE with a
     reason - GREEN then builds what the amended block says. This is where "RED
     tested one shape and GREEN built another" is prevented, and it is not the
     acceptance criteria: the criteria are frozen and change only through
     ## Amendments; this is a working agreement RED is expected to sharpen.
     One block per thing the story touches:
       * module paths and exported names, exactly
       * exact signatures, and the types the assertions will destructure
       * THE SEMANTICS BEHIND EACH NUMBER - not clamp(latitude) but "latitude
         clamps at +/-85, and dragging DOWN brings the north into view". One
         sentence per number settles a sign error in one line
       * the accessible markup for anything user-facing: roles, labels, what is
         a sibling of what
       * the oracle partition of the criteria (settled / oracle-free /
         mechanical - see story-authoring)
       * baseline measurements the story may read out rather than re-derive,
         each with what it was measured on
       * TEST-ONLY DEPENDENCIES this story is likely to need, by name. RED
         may add them itself, but only inside the dev block - so a library
         production will ALSO use is a GREEN change and is better decided
         here than discovered mid-phase. Where the ecosystem has no dev
         block at all (go.mod, requirements.txt, *.csproj), RED cannot
         declare one and the phase round trip is yours to plan for
       * FOR EVERY EXISTING EXPORT WHOSE SIGNATURE THIS STORY CHANGES: every
         caller, source and test, grep-listed here before dispatch. RED cannot
         find these itself - the old signature still exists during RED, so a
         caller of it still compiles and is absent from RED's typecheck. One
         such file went missing and took 25 tests with it, silently, at GREEN. -->

RED may amend a block here in place, giving a reason. GREEN builds what the
amended block says.

### Files

| Path | `classify.sh` says | Who writes it |
|---|---|---|
| `.claude/tests/plan.test.sh` | `harness` | RED |
| `scripts/plan.sh` | `harness` | GREEN |

Both files are `harness`, so the phase lock permits either write in every
phase. The only thing enforcing RED-before-GREEN here is this contract. RED
writes only `plan.test.sh`, and GREEN writes only `plan.sh`. This story declares
its paths in a table because its own prose is full of exactly the tokens the bug
misreads.

### The filter

It lives in `lock_scan`, applied to the fallback branch only
(`LC_ORIGIN=scanned`). The grep regex that extracts candidates does not change.
The candidates it yields are filtered **before** `classify_many`, in this order:

1. **Version-like: dropped.** A token matching `^v?[0-9]+(\.[0-9]+)+$`.
   Unconditional: this runs even when a file of that name exists.
2. **No `/`: kept only if it exists.** It is kept only if `[ -e "$ROOT/<token>" ]`,
   the working tree resolved from the repository root. A bare `gates.sh` or
   `i.e` does not exist there. `README.md` or `rokit.toml` may.
3. **Contains `/`, does not exist, and is a partial path: dropped.** A token
   `t` is dropped if some other candidate `u` ends in `/t`
   (`.claude/hooks/lib.sh` covers `hooks/lib.sh`). A `/` token that exists, or
   is a suffix of no other candidate, is kept, and that includes paths to new
   files.

What survives goes to `classify_many` unchanged, and the rest of `lock_scan`
(counting, offenders, the `LC_COUNT -gt 0` rule) is untouched. So if every
candidate is filtered, the verdict is `NOT CONSIDERED`, the same as a Contract
naming no paths. `declared_paths` (the `### Files` branch) is not filtered: a
declared path is taken at its word.

Bash, awk and coreutils only (rules.md, Portability). No new fork per token
beyond what bash builtins do. `[ -e ]` and `case` are builtins.

Update the `WHICH PATHS (HARNESS-014)` comment in `plan.sh`. Its "the fallback
scan stands, byte for byte" and "Narrowing its regex is a separate question" are
no longer true. Say what the filter drops and why, and cite HARNESS-018.

### Tests (`.claude/tests/plan.test.sh`)

New cases go in the `describe "the lock-coverage decision is said out loud"`
block or a new `describe` after it. They use the existing `story_with`, `plan`,
`models_stdout`, `red_row`, `lines_matching` and the anchored needles `APPLIES`,
`SUPPRESSED`, `NOT_CONSIDERED` and `SCANNED`. Assertions are anchored and
counted (`assert_eq ... 1 "$(lines_matching ...)"`), never a floating
`assert_contains`. Files the cases create in `$FIX` (`rokit.toml`, `5.3.15`)
are removed straight after the case that needs them, so later cases see the
fixture as it was.

- AC-1: one story, both needles. `APPLIES.*all 2 path[(]s[)] $SCANNED`, and
  `red_row "opus	the lock freezes none of the paths"`.
- AC-2: the same story twice, with `rokit.toml` created, then removed. The
  SUPPRESSED line names `` `rokit.toml` (config) ``.
- AC-3: `touch "$FIX/5.3.15"`, with `APPLIES.*all 1 path`.
- AC-4: `APPLIES.*all 1 path`. The control uses the existing T-5
  (`src/core/world.ts`, suppressed), which must stay green. Add one assertion
  that T-5's SUPPRESSED line still names `src/core/world.ts`, if one does not
  already exist. It does: `F-NODECL-SOURCE`.
- AC-5: `cp "$REPO_ROOT/docs/backlog/stories/HARNESS-018.md"` into
  `$FIX/docs/backlog/stories/`, then the APPLIES needle and
  `red_row "opus	the lock freezes none of the paths"` over `models_stdout
  HARNESS-018`.
- The comment above the `said out loud` block that says "narrowing its regex is
  out of scope" is updated by RED to point here.

Existing cases T-4 (APPLIES on two `/` harness paths), T-5, T-7, T-8 and T-9
must stay green unchanged. They are the regression guard on the parts that do
not move.

### Oracle partition

All five ACs are **mechanical**: exact verdict keywords, exact path counts, and
an exact model name. There is no threshold and no metric.

### Callers of changed signatures

None. `lock_scan`, `contract_unenforced` and `lock_coverage_line` keep their
signatures and outputs. Only the set of paths `lock_scan` considers changes.

## Deferred verifications

<!-- REQUIRED when a verification this story depends on provably cannot run in
     the phase that wants it; omit the section otherwise. Written by the Lead PO
     at PLANNED, and the phase that owns it pastes the result in.
     The case this exists for: a negative control for a round trip, a threshold
     or a codec has to break the real implementation to mean anything, and in
     RED there is no implementation to break. RED naming the control and saying
     it could not run it is the honest answer; RED claiming a verification it
     did not do is the failure. One block per entry:
       * what it verifies, as a falsifiable condition - "with one field dropped
         from the encoder, AC-1's property test MUST fail"
       * why the phase that wants it cannot run it
       * THE PHASE THAT OWNS IT, declared as `Owner: GATES` (or RED, GREEN,
         REVIEW). check-boundaries.sh refuses a PR
         whose block names no phase
       * the RESULT, pasted, once that phase runs it: what was mutated, what
         failed, and that the file was restored - or the word WAIVED with the
         reason. check-boundaries.sh refuses a PR that has neither
     Schedule it into GATES rather than RED where you can: source is writable
     there, and a story that bounced back to RED mid-cycle gets its corrected
     assertions earned by the same mutation, for free. Do THREE mutations rather
     than one, and make one of them a wrong VALUE rather than a missing field: a
     suite that catches an omission can be blind to a corruption, and a codec
     that is uniformly wrong round-trips through itself perfectly. -->

**DV-1: each clause of the filter is pinned by its own assertion.** Owner:
GATES. RED runs against the old `lock_scan`, where nothing is filtered, so the
new cases fail there all together. That does not show that each clause has an
assertion that fails when only that clause breaks. Run three mutations with
`scripts/mutate.sh` against the shipped `scripts/plan.sh`, each running
`bash .claude/tests/plan.test.sh`:

1. Disable the version-like clause. AC-3 MUST fail, because `5.3.15` exists
   in the fixture.
2. Make the no-`/` clause keep every token, regardless of whether it exists.
   AC-1 and AC-2's "absent" case MUST fail.
3. Disable the partial-path clause. AC-4 MUST fail.

Paste each run's failing assertion names, and confirm the restore.

**Result (GATES, 2026-09-29, orchestrator).** All three mutations ran through
`bash scripts/mutate.sh scripts/plan.sh '<expr>' -- bash .claude/tests/plan.test.sh`.
Each one failed exactly the assertions the RED handoff predicted, and nothing
else.

M1: version clause disabled. Expression: `/=~ \^v?/s/&& continue/\&\& :/`.

```
=== mutate: scripts/plan.sh (1 line(s) changed by /=~ \^v?/s/&& continue/\&\& :/) ===
    FAIL AC-3: version-like tokens are never counted, even with a file named 5.3.15 at the root, so it APPLIES for 1 path
    FAIL AC-3: and a version number does not SUPPRESS the exception
plan: 115 passed, 2 failed
=== mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/scripts_plan.sh.20260929T150557Z.854053.bak) ===
```

M2: the no-`/` clause keeps every token. The first attempt,
`s/\*) continue ;; esac/.../`, matched **3** lines of `plan.sh`, two of them
outside the filter. It broke unrelated code (`73 passed, 44 failed`) and proves
nothing, so it is discarded. Its restore was verified byte-for-byte, and the
backup was `scripts_plan.sh.20260929T150915Z.879800.bak`. The re-run was scoped
to the filter's line:

```
=== mutate: scripts/plan.sh (1 line(s) changed by /case "\$t" in \*\/\*)/s/\*) continue ;; esac/*) out="$out$t$NL"; continue ;; esac/) ===
    FAIL AC-1: a Contract naming two harness paths, plus prose and their bare names, APPLIES for exactly those 2 paths
    FAIL AC-1: and is not SUPPRESSED by the prose or a bare filename
    FAIL AC-1: so RED stays on the stronger model because the lock freezes none of the paths
    FAIL AC-2: the same bare filename ABSENT from the root is not a path, so it APPLIES for 1 path
    FAIL AC-2: with rokit.toml absent the verdict is not SUPPRESSED
    FAIL a Contract whose every token is filtered is NOT CONSIDERED, like one naming no paths
    FAIL and neither APPLIES nor SUPPRESSED
    FAIL AC-5: HARNESS-018, unmodified, reads Lock coverage: APPLIES from its Contract text
    FAIL AC-5: and is not SUPPRESSED
    FAIL AC-5: so HARNESS-018's RED is on the stronger model because the lock freezes none of its paths
plan: 107 passed, 10 failed
=== mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/scripts_plan.sh.20260929T151351Z.909169.bak) ===
```

M3: partial-path clause disabled. Expression: `s/keep=0; break/keep=1; break/`.

```
=== mutate: scripts/plan.sh (1 line(s) changed by s/keep=0; break/keep=1; break/) ===
    FAIL AC-4: a missing partial path that trails another scanned path is not counted twice, so it APPLIES for 1 path
    FAIL AC-4: and the partial path does not SUPPRESS the exception as source
    FAIL AC-5: HARNESS-018, unmodified, reads Lock coverage: APPLIES from its Contract text
    FAIL AC-5: and is not SUPPRESSED
    FAIL AC-5: so HARNESS-018's RED is on the stronger model because the lock freezes none of its paths
plan: 112 passed, 5 failed
=== mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/scripts_plan.sh.20260929T150953Z.885765.bak) ===
```

After all four runs, `git diff --stat scripts/plan.sh` still reads
`45 insertions(+), 4 deletions(-)`, which is GREEN's diff and nothing else.
The optional fourth mutation (the existence condition in clause 3, which T-75
guards) was not run.

## Amendments

<!-- Acceptance criteria are frozen once the story leaves PLANNED. If one turns
     out to be wrong or unsatisfiable, stop, put it to the product owner, and
     record the change here: which AC, what it said, what it says now, who
     approved it and why. check-boundaries.sh fails a PR whose criteria differ
     from the base branch without an entry here. Omit the section if unused.
     Where the change came from a subagent's claim that the criterion was
     wrong, record the ORCHESTRATOR'S OWN reproduction of it - different
     inputs, not the subagent's code. That claim is also what an agent says
     when it wants to stop failing. -->

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-019` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table. Only what lies BETWEEN these two markers is rewritten when
this command runs again; the rest of the section is yours and is preserved.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `opus` | the lock freezes none of the paths this story names, so the contract is not an aid to the model here - it is the only enforcement there is. A weaker model against a safety net and a weaker model against nothing are different propositions |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

Lock coverage: APPLIES — all 2 path(s) declared in the Contract's ### Files table are harness/docs/ignored, so RED stays on the stronger model.
<!-- plan.sh:generated:end -->

This story's Contract declares its two paths in a `### Files` table on
purpose. Its prose quotes `1.5`, `5.3.15` and bare filenames, and the pre-fix
fallback would have misread them, which is the bug itself.

**Resolved:**

- PLANNED: `lead-po` role, run inline by the orchestrating session on
  `claude-opus-5-5`. No subagent was dispatched.
- RED: dispatched to the `test-developer` subagent with no model override, so
  it resolved to its definition's `model: opus`. The orchestrator cannot see
  the exact model id behind that alias.
- GREEN: dispatched to the `feature-developer` subagent with no override, so it
  resolved to its definition's `model: opus`. It reported itself as Opus 5.5.
- GATES and REVIEW: run inline by the orchestrating session on
  `claude-opus-5-5`.

**Verdict.** The plan kept RED on `opus` because the `### Files` table
declared two `harness` paths. RED's suite discriminated: 14 new assertions
failed, and each failed for the right reason. GREEN reached 117/0 without
touching the test file (`frozen: OK`, below). This story is not a comparison
between models. It records only that the plan it fixed was followed.

<!-- FILLED BY A TOOL, not by hand: `bash scripts/plan.sh write <id>`, as the
     last step of PLANNED once the ## Contract exists. It renders the per-phase
     plan from .claude/harness/models.conf with the reason for each row. Run it
     again after amending the contract; it rewrites only the region between the
     `plan.sh:generated` markers. Everything you write OUTSIDE them in this
     section is preserved - that is where the two halves below belong.

     Not at story creation: the plan depends on the contract, and the "no
     contract, so RED stays on the stronger model" exception would be baked in
     before anybody had a chance to write one.

     What you add BY HAND is the other half - a departure from the plan, and
     the model each dispatch RESOLVED to. Make a departure falsifiable rather
     than folklore:
       * which phase, which model, and why that phase specifically
       * THE RESOLVED MODEL ACTUALLY DISPATCHED, by name - never the word
         "default". An agent definition's `model:` field, or the session's
         setting, or an override: the orchestrator cannot see which won unless
         it records it. Two stories once compared "the default model" against a
         stronger one, and neither could say what the default had resolved to,
         so the comparison may have been the stronger model against itself
       * what the orchestrator should stay on
       * HOW to brief it differently - a model chosen for judgement wants the
         criteria and the constraints, not a pre-decided test design
       * the ORACLE PARTITION of the criteria: which are settled (read the
         numbers out, do not calibrate), which are oracle-free (invent the
         metric and demand a negative control that fires hard), which are
         mechanical (pin exactly). Measured to matter more than the model
       * a success condition that could come out either way
     Then record the VERDICT against that condition when the phase ends, with
     evidence. The verdict is the part that gets skipped, and without it a model
     choice becomes a habit nobody can argue with. -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

<!-- Explicit non-goals. Prevents the Feature Developer from over-building. -->

- The candidate regex, and `declared_paths`. The `### Files` table stays the
  precise answer, and this story only makes the fallback less wrong.
- A `/` path that genuinely names a file the story does not write, such as
  `src/main.ts` as a fixture inside a throwaway repository (HARNESS-014).
  Telling a mention from a write is not possible from prose. That case still
  suppresses, and the `### Files` table is the remedy.
- Resolving a bare filename to wherever it lives in the tree (`gates.sh` to
  `scripts/gates.sh`). A bare name can match several files, and guessing one is
  a new heuristic. Dropping it errs toward `opus`.
- Re-planning HARNESS-018 or any other DONE story's `## Model guidance`.

## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

One level: `.claude/tests/plan.test.sh`, which drives the real `scripts/plan.sh`
inside a throwaway project fixture (`make_project_fixture`: real `scripts/`,
real `.claude/hooks/`, real `paths.conf`). The fixture has no `.claude/tests/`,
no `rokit.toml` and no `5.3.15`, so what exists at its root is controlled per
case. New cases are in a new `describe "the fallback scan counts only
path-shaped tokens"`, placed after `the lock-coverage decision is said out
loud`. The comment above that block no longer says narrowing is out of scope.
It points here.

| Case | Contract (no `### Files` table) | Asserted | AC |
|---|---|---|---|
| T-70 | `scripts/check-boundaries.sh`, `.claude/tests/boundaries.test.sh`, prose `1.5 MiB`, bare `check-boundaries.sh`, `boundaries.test.sh` | APPLIES `all 2 path(s)` scanned = 1; SUPPRESSED = 0; RED row `opus<TAB>the lock freezes none of the paths` = 1 | AC-1 |
| T-71, present | `scripts/plan.sh` + bare `rokit.toml`, with `$FIX/rokit.toml` created, then removed | SUPPRESSED naming `` `rokit.toml` (config) `` scanned = 1; APPLIES = 0 | AC-2 |
| T-71, absent | the same story, file gone | APPLIES `all 1 path(s)` scanned = 1; SUPPRESSED = 0 | AC-2 |
| T-72 | `scripts/plan.sh` + prose `bash 5.3.15`, `1.5 MiB`, `v2.0`, with `$FIX/5.3.15` created, then removed | APPLIES `all 1 path(s)` scanned = 1; SUPPRESSED = 0 | AC-3 |
| T-73 | `.claude/hooks/lib.sh` and later `hooks/lib.sh` | APPLIES `all 1 path(s)` scanned = 1; SUPPRESSED = 0 | AC-4 |
| T-5 (existing, F-NODECL-SOURCE) | `src/core/world.ts` (not in the fixture) + `scripts/task.sh` | SUPPRESSED by `` `src/core/world.ts` (source) ``; unchanged | AC-4 control, missing half |
| T-75 | `.claude/tests/src/main.ts` and `src/main.ts` (exists in the fixture) | SUPPRESSED by `` `src/main.ts` (source) `` scanned = 1; APPLIES = 0 | AC-4 control, existing half; green on arrival |
| T-76 | only `5.3.15`, `i.e`, `check-boundaries.sh`, `1.5` | NOT CONSIDERED = 1; APPLIES or SUPPRESSED = 0; RED row `fable` = 1 | Contract, "The filter", last paragraph (everything filtered) |
| HARNESS-018 | this repository's `docs/backlog/stories/HARNESS-018.md`, copied unmodified, then removed | APPLIES scanned = 1; SUPPRESSED = 0; RED row `opus<TAB>the lock freezes none of the paths` = 1 | AC-5 |

T-74 is not used. Existing T-4, T-5, T-7, T-8 and T-9 are unchanged and stay
green.

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

**Command:** `bash .claude/tests/plan.test.sh`. It is a harness suite, and no
`project.conf` gate runs it. CI runs it through `bash scripts/selftest.sh`. The
full file took 3m41s locally on this Windows machine. Nothing in it has a
timeout, so there is no budget to size.

**Result against the unmodified `plan.sh`:** `plan: 103 passed, 14 failed`. All
14 failures are the new assertions. Every pre-existing assertion passes.

```
  the fallback scan counts only path-shaped tokens
    FAIL AC-1: a Contract naming two harness paths, plus prose and their bare names, APPLIES for exactly those 2 paths
         expected: 1
         actual:   0
    FAIL AC-1: and is not SUPPRESSED by the prose or a bare filename
         expected: 0
         actual:   1
    FAIL AC-1: so RED stays on the stronger model because the lock freezes none of the paths
         expected: 1
         actual:   0
    FAIL AC-2: the same bare filename ABSENT from the root is not a path, so it APPLIES for 1 path
         expected: 1
         actual:   0
    FAIL AC-2: with rokit.toml absent the verdict is not SUPPRESSED
         expected: 0
         actual:   1
    FAIL AC-3: version-like tokens are never counted, even with a file named 5.3.15 at the root, so it APPLIES for 1 path
         expected: 1
         actual:   0
    FAIL AC-3: and a version number does not SUPPRESS the exception
         expected: 0
         actual:   1
    FAIL AC-4: a missing partial path that trails another scanned path is not counted twice, so it APPLIES for 1 path
         expected: 1
         actual:   0
    FAIL AC-4: and the partial path does not SUPPRESS the exception as source
         expected: 0
         actual:   1
    FAIL a Contract whose every token is filtered is NOT CONSIDERED, like one naming no paths
         expected: 1
         actual:   0
    FAIL and neither APPLIES nor SUPPRESSED
         expected: 0
         actual:   1
    FAIL AC-5: HARNESS-018, unmodified, reads Lock coverage: APPLIES from its Contract text
         expected: 1
         actual:   0
    FAIL AC-5: and is not SUPPRESSED
         expected: 0
         actual:   1
    FAIL AC-5: so HARNESS-018's RED is on the stronger model because the lock freezes none of its paths
         expected: 1
         actual:   0

plan: 103 passed, 14 failed
```

**These are the right failures.** Here is the lock-coverage line each case
actually printed. It was captured by driving the same stories through the same
fixture outside the suite. Each is SUPPRESSED by exactly the token the
corresponding clause is meant to drop, not by a fixture error:

| Case | Printed today |
|---|---|
| T-70 (AC-1) | ``SUPPRESSED by `1.5` (source), `boundaries.test.sh` (test), `check-boundaries.sh` (source), scanned from the Contract text`` |
| T-71 absent (AC-2) | ``SUPPRESSED by `rokit.toml` (config), scanned …``. The token is counted although no such file exists |
| T-72 (AC-3) | ``SUPPRESSED by `1.5` (source), `5.3.15` (source), `v2.0` (source), scanned …`` |
| T-73 (AC-4) | ``SUPPRESSED by `hooks/lib.sh` (source), scanned …`` |
| T-76 | ``SUPPRESSED by `1.5` (source), `5.3.15` (source), `check-boundaries.sh` (source) (+1 more), scanned …`` |
| HARNESS-018 (AC-5) | ``SUPPRESSED by `1.5` (source), `boundaries.test.sh` (test), `check-boundaries.sh` (source) (+8 more), scanned …``. This matches the Context verbatim |

The RED row was `fable	the measured case…` in every one of them.

**Passed on arrival. Each is a guard, not a demand:**

- *T-71 present* (SUPPRESSED by `rokit.toml` (config), APPLIES = 0). Today it
  passes because nothing is filtered. It is the control on clause 2 dropping
  too much: an implementation that drops every no-`/` token fails it.
- *T-75* (SUPPRESSED by `src/main.ts` (source)). This is the control on clause
  3's "does not exist" condition. `src/main.ts` exists in the fixture *and* is a
  trailing segment of `.claude/tests/src/main.ts`. Only the existence check
  keeps it. If clause 3 drops suffixes regardless of existence, the verdict
  becomes APPLIES and this fails.
- *T-76, "RED follows the plain plan"* (`fable`). It passes today because the
  line is SUPPRESSED, and after GREEN because the verdict is NOT CONSIDERED. The
  other two T-76 assertions carry the discrimination.
- *T-5 / F-NODECL-SOURCE* is the existing control for a missing `/` path that
  stands alone, as AC-4 requires.

None of these has been earned by a probe in RED. No filter exists to mutate
yet. The simulated measurements below are the evidence until GATES runs DV-1.

**Files touched:** `.claude/tests/plan.test.sh`: a new `describe` block, plus
the updated comment above `said out loud`. This story file: `## Test plan` and
this section. `scripts/plan.sh` is untouched.

**Shape pinned.** There are no imports. The suite pins only `plan.sh`'s
observable output, which is unchanged in form:
- the human line `Lock coverage: APPLIES — all N path(s) scanned from the
  Contract text are …`, the `SUPPRESSED by `` `p` (cat) ``, …, scanned from the
  Contract text` form, and `NOT CONSIDERED`, all as they print today;
- `plan.sh models` row `RED<TAB>test-developer<TAB>opus<TAB>the lock freezes
  none of the paths…` when the exception applies.

**Not constrained:**
- how the filter is written (awk, a bash loop, `case` globs);
- the order of surviving paths;
- the exact count for HARNESS-018. AC-5 pins APPLIES + scanned, not N. The
  simulation below gives 5, but that depends on what the fixture contains;
- whether `declared_paths` shares any code with the filter. It must not be
  filtered (Contract). T-7 and T-8 guard the declared branch.

**Expected values of the controls: the filter simulated outside the
framework.** I wrote the Contract's three clauses as a scratch bash function.
It is a candidate, not the shipped code. I ran it over the candidates the
existing regex extracts from each case, in a real `make_project_fixture`, under
the three DV-1 mutations. GREEN and GATES must confirm these numbers against
the shipped `lock_scan`. Until then they are claims.

| Case | Correct filter keeps | M1: no version clause | M2: keep every no-`/` token | M3: no partial-path clause |
|---|---|---|---|---|
| T-70 AC-1 | 2: `.claude/tests/boundaries.test.sh`, `scripts/check-boundaries.sh` → APPLIES | same | + `check-boundaries.sh`, `boundaries.test.sh` → **SUPPRESSED** | same |
| T-71 present | `rokit.toml`, `scripts/plan.sh` → SUPPRESSED (config) | same | same | same |
| T-71 absent | 1: `scripts/plan.sh` → APPLIES | same | + `rokit.toml` → **SUPPRESSED** | same |
| T-72 AC-3 | 1: `scripts/plan.sh` → APPLIES | + `5.3.15` (exists) → **SUPPRESSED** | same | same |
| T-73 AC-4 | 1: `.claude/hooks/lib.sh` → APPLIES | same | same | + `hooks/lib.sh` → **SUPPRESSED** |
| T-5 | `scripts/task.sh`, `src/core/world.ts` → SUPPRESSED | same | same | same |
| T-4 | `.claude/tests/plan.test.sh`, `scripts/plan.sh` → APPLIES | same | same | same |
| T-75 | `.claude/tests/src/main.ts`, `src/main.ts` → SUPPRESSED | same | same | same |
| T-76 | nothing → NOT CONSIDERED | same (`5.3.15` does not exist there, so clause 2 drops it) | + `check-boundaries.sh`, `i.e` → **SUPPRESSED** | same |
| HARNESS-018 | 5: `.claude/harness/rules.md`, `.claude/hooks/lib.sh`, `.claude/tests/`, `.claude/tests/pipe-readers.test.sh`, `scripts/refresh-harness.sh` → APPLIES | same | + 11 bare names → **SUPPRESSED** | + `hooks/lib.sh` → **SUPPRESSED** |

(The simulation read HARNESS-018's Contract without `strip_comments`. The count
may differ by the tokens inside comments. It does not affect the verdict.)

**DV-1: declined in RED, in those words.** I cannot run it. It needs the shipped
filter in `scripts/plan.sh` to mutate, and in RED that filter does not exist.
Owner: GATES. The predicted failing assertions, from the table above, are:

1. **Disable the version-like clause.** It fails only
   `AC-3: version-like tokens are never counted, even with a file named 5.3.15 at the root, so it APPLIES for 1 path`
   and `AC-3: and a version number does not SUPPRESS the exception`.
   The other cases survive M1, because their version tokens do not exist and
   clause 2 drops them. That is why AC-3 creates `5.3.15`.
2. **Make the no-`/` clause keep every token.** Predicted to fail:
   - the three `AC-1:` assertions;
   - `AC-2: the same bare filename ABSENT from the root is not a path, so it APPLIES for 1 path`
     and `AC-2: with rokit.toml absent the verdict is not SUPPRESSED`;
   - T-76's `a Contract whose every token is filtered is NOT CONSIDERED, like one naming no paths`
     and `and neither APPLIES nor SUPPRESSED`;
   - the three `AC-5:` assertions.
3. **Disable the partial-path clause.** Predicted to fail:
   - `AC-4: a missing partial path that trails another scanned path is not counted twice, so it APPLIES for 1 path`
     and `AC-4: and the partial path does not SUPPRESS the exception as source`;
   - the three `AC-5:` assertions. HARNESS-018 names both `.claude/hooks/lib.sh`
     and `hooks/lib.sh`.

A fourth mutation is not in DV-1, but it is worth running if GATES has time.
Drop the `does not exist` condition from clause 3, so a suffix is dropped even
when it exists. Predicted to fail:
`AC-4 control: a / path that EXISTS is kept even when another candidate ends in it, and its source suppresses`
and `AC-4 control: so the verdict is not APPLIES`.

**For GREEN.** `[ -e "$ROOT/$token" ]` must resolve against the repository root
that `plan.sh` already uses (the fixture's root when run under the suite), not
the caller's cwd. The suite runs `cd "$FIX" && bash scripts/plan.sh`, so both
happen to agree here. Note one token shape: `.claude/tests/` has a trailing
`/`. It contains `/`, and in the fixture it does not exist. It is a suffix of
nothing, so the Contract keeps it, and it classifies `harness`. That is
harmless, and it is what makes HARNESS-018 count 5.

`bash scripts/gates.sh --fast`: all required gates passed (format, lint,
typecheck, unit, build, harness; coverage unconfigured; 1m47s). That is
expected, because no gate runs `plan.test.sh`. The run only shows that nothing
else broke.

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

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-29T15:19:57Z
    commit: c464266 (working tree had uncommitted changes)
    tree:   e9099b3c150385a994d3fae3080b44c77874dbd9
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 90)
    PASS         lint (0s, observed 90, floor 1)
    PASS         typecheck (2s, observed 17)
    PASS         unit (30s, observed 452, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 57746)
    PASS         harness (13s, observed 40)
    UNCONFIGURED mutation

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Scaffold inventory

<!-- REQUIRED for a bootstrap or chore story that writes production code under
     SCAFFOLD, where nothing forces a test to exist first, and for a spike that
     commits its throwaway code. Omit otherwise.
     One line per production file written, and for anything with behaviour
     rather than configuration, the test that covers it:
       src/core/palette.ts        - src/core/palette.test.ts
       vite.config.ts             - configuration, no behaviour
     check-boundaries.sh refuses the PR if any changed source file is not
     named here. -->

## Notes


**RED, verified by the orchestrator.** An independent run of
`bash .claude/tests/plan.test.sh` against the unmodified `plan.sh` ended
`plan: 103 passed, 14 failed`. All 14 failures were the new assertions, the
same list as in the handoff.

**GREEN, verified by the orchestrator.** An independent run gave
`plan: 117 passed, 0 failed`. `bash scripts/plan.sh HARNESS-018` in this repo
now prints:
`Lock coverage: APPLIES — all 5 path(s) scanned from the Contract text are harness/docs/ignored, so RED stays on the stronger model.`
That matches the 5 the handoff predicted. The only change is in
`scripts/plan.sh`: a new `scanned_paths_filter` and one call to it on the
scanned branch of `lock_scan`.

**Freeze, RED → GREEN:** `frozen: OK — 1 path(s) unchanged since the snapshot for HARNESS-019`
(`.claude/tests/plan.test.sh`). A new snapshot was taken at GREEN → GATES.

**Freeze, GREEN → GATES:** `frozen: OK — 1 path(s) unchanged since the snapshot for HARNESS-019`.
