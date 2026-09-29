---
id: HARNESS-009
title: The harness's own test suites obey the test freeze
slug: the-harness-s-own-test-suites-obey-the-t
epic: 
type: chore
status: in-progress
phase: RED
branch: story/HARNESS-009-the-harness-s-own-test-suites-obey-the-t
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`CLAUDE.md` law 2 says **"Tests are frozen during GREEN."** For the harness's own
suites under `.claude/tests/`, nothing mechanically enforces that. Observed twice
already and recorded both times without a fix: `HARNESS-006` §4 ("The phase lock
enforces nothing here - restated because it is the risk") and `HARNESS-002`
`## Notes` ("the harness's own test suites are not protected by the harness's own
lock"). Neither filed the consequence as work; this story is that.

**The cause is rule ordering, not a decision.** `harness | .claude/**` in
`.claude/harness/paths.conf` precedes every `test` rule and the first match wins:

    $ bash scripts/classify.sh .claude/tests/boundaries.test.sh scripts/check-boundaries.sh
    harness	.claude/tests/boundaries.test.sh
    harness	scripts/check-boundaries.sh

`paths.conf` has two commits in its whole history (`82cc645` initial, `29404fe`
the M0-M2 plan) and neither mentions `.claude/tests`. The `harness` category has
a documented reason to stay writable in every phase - `.gitignore`,
`project.conf`, `paths.conf`, and `rules.md` argues that case explicitly - but
that argument is about *configuration whoever needs it adds in the phase they
need it*. It was never made about test suites, and the suites inherit the
permission only because they live under `.claude/`.

### The exposure, measured rather than inferred

**1. The hook permits the write, in every phase.** The real `phase-guard.sh`
driven through the real `paths.conf`/`phases.conf` (the fixture copies both), a
`Write` to each path:

    PHASE    .claude/tests/boundaries.test.sh   tests/main.test.ts (an ordinary test)
    RED      ALLOWED                            ALLOWED
    GREEN    ALLOWED                            DENIED
    GATES    ALLOWED                            DENIED
    REVIEW   ALLOWED                            DENIED
    DONE     ALLOWED                            DENIED

`scripts/check-boundaries.sh` is ALLOWED in all five as well - so the script is
not frozen during RED either, which is law 1 pointing the other way. That half is
`## Out of scope` below, for a reason given there.

**2. A weakened harness assertion is invisible to its own suite.** Not "could
be" - run. One needle widened at `.claude/tests/boundaries.test.sh:1298`, from
the refusal it is meant to pin to a substring present in the output anyway:

    $ bash scripts/mutate.sh .claude/tests/boundaries.test.sh \
        '1298s#Production code ships with the test that demanded it#story#' \
        -- bash .claude/tests/boundaries.test.sh

    boundaries: 83 passed, 0 failed
    === mutate: command exited 0; restored (verified byte-for-byte ...) ===

Baseline on the same tree, unmutated: **`boundaries: 83 passed, 0 failed`**.
Identical verdict, identical count. The assertion still runs and still passes;
what it matches is no longer what it claims. This is precisely the "needle that
cannot fail" failure in `rules.md`, and it is the reason CI cannot be the backstop:
**a weakened test passes, which is what weakening means.**

**3. So CI does not catch it.** The chain, each link checked:

| Link | Does it catch a weakened harness assertion? |
|---|---|
| `.claude/hooks/phase-guard.sh` | **No** - `harness` is writable in every phase (measured above) |
| `.github/workflows/gates.yml` -> `scripts/selftest.sh` | **No** - it runs the suite, and the suite is green (83/0) |
| `scripts/gates.sh` | **No** - the `harness` gate runs `project-counters.test.sh` only; no other suite is a gate |
| `scripts/check-boundaries.sh` 3a | **No** - see below |
| the gate tree stamp | **Partially** - see below |

Check 3a counts `source` and `test` after `classify_stdin`. A harness suite is
neither, so a harness-only diff reaches the reassuring branch. `HARNESS-002`'s
own PR is the worked example - its real diff against `main`:

    harness	.claude/tests/boundaries.test.sh
    docs	docs/backlog/stories/HARNESS-002.md

`src=0`, `tst=0`, and 3a prints `ok  source changes accompanied by test changes
(0 source, 0 test)`. There is no guard on `.claude/tests` anywhere:

    $ grep -n '\.claude/tests' scripts/check-boundaries.sh .claude/hooks/*.sh scripts/gates.sh
    (no output)

**The one thing that does fire is the gate tree stamp, and it is not enough.**
`gated_stdin` keeps `harness` (non-`.md`, not under `.claude/state/`), so both
paths are in the hash:

    $ printf '%s\n' .claude/tests/boundaries.test.sh scripts/check-boundaries.sh \
        | classify_stdin | gated_stdin
    harness	.claude/tests/boundaries.test.sh
    harness	scripts/check-boundaries.sh

Editing a suite after a recorded run therefore invalidates the stamp and forces
`bash scripts/gates.sh` to be run again. But the re-run is green - the suite was
weakened, and `gates.sh` does not run it in any case. The stamp proves *when* the
code changed, never *whether the change was legal*. It is a staleness check
wearing the costume of a freeze.

### Why this matters here specifically

This is not a hypothetical about some future project. Nine of this repository's
stories are harness stories, and for every one of them **the artifact under test
is a harness suite** - the exact files the lock does not cover. The freeze has
held on role discipline alone, and there is a commit on `main` showing how thin
that is. `0bce924`, SEAT-001:

    SEAT-001: correct HARNESS-006's stale counter literals (return to RED)

    Taken as a return to RED rather than patched from REVIEW, because the only
    legal fix is a write REVIEW forbids.

REVIEW does **not** forbid it: `project-counters.test.sh` is `harness`, which
REVIEW permits, and the hook stayed silent. The author reasoned correctly from
`CLAUDE.md` rather than from the tool - and then committed with the frontmatter
still reading `phase: REVIEW`. The discipline was done by hand (the corrected
assertions were earned by mutation and pasted into `## Regressions`), and the
machine recorded nothing. That is the good case. The bad case is the same silence
with nobody reasoning.

**The required gate that would fail if this story's artifact broke:** `harness`
is not it - it runs `project-counters.test.sh` only. This story's artifact is an
assertion in `.claude/tests/boundaries.test.sh`, which runs in CI's required
`gates` job via `scripts/selftest.sh` (the step precedes `gates.sh` in the same
job), exactly as `HARNESS-006` §1 established. `required_gates` stays empty for
that reason: there is no optional gate to promote.
## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

The artifact is a new check in `scripts/check-boundaries.sh` - **not** a change to
`paths.conf` or `phases.conf`. `## Contract` says why, and the alternatives are
weighed in `## Notes`.

- **AC-1** — Given a commit on the branch that changes a file under
  `.claude/tests/`, when the story file *at that commit* records a phase whose
  `phases.conf` row does **not** include `test`, then `check-boundaries.sh`
  refuses, naming the abbreviated commit, the path, and the phase.

- **AC-2** — Given the same commit but with a committed phase whose row **does**
  include `test` (`RED`, `SCAFFOLD`), then `check-boundaries.sh` does not refuse
  on account of it, and says so on a line reporting how many such commits were
  checked.

- **AC-3** — Given a branch with no commit touching `.claude/tests/`, then the
  check is silent: it prints neither a refusal nor the `ok` line of AC-2. (The
  `ok` line must be evidence that something was inspected, not furniture. This is
  the `harness state not tracked` defect named at `check-boundaries.sh:164` - a
  rule that reported a pass in the same breath as a refusal - and the
  `red_manifest_checked` counter at `:566` is the shape that avoids it.)

- **AC-4** — Given the phase set in `phases.conf` is changed so that some phase
  gains or loses `test`, then AC-1's verdict for that phase follows it, with no
  edit to `check-boundaries.sh`. The permitted-phase set is **read from
  `phases.conf`**, never written out as a literal list of phase names.
  *Negative control:* a test that pins `GREEN` by name would pass today and keep
  passing after `phases.conf` changed underneath it; the assertion must therefore
  drive a fixture whose `phases.conf` row has been edited, and observe the
  verdict move.

- **AC-5** — Given a commit under a phase that forbids `test`, when that commit
  changes `.claude/harness/project.conf`, `.gitignore`, `CLAUDE.md`, a file under
  `.claude/commands/`, or any other `harness` path **outside** `.claude/tests/`,
  then the check does not refuse. The narrowing is the point: `rules.md` gives
  those their every-phase permission deliberately, and this story must not
  withdraw it.

## Contract

<!-- Amendable by RED in place, with a reason. -->

### Where the check goes, and why not in the lock

**In `scripts/check-boundaries.sh`, as a new per-commit check after 3i.** The
three candidates were weighed in `## Notes`; this is the one that changes the
verdict for exactly the paths in question and for nothing else. The phase lock
sees a path and never a diff, and it cannot see *which commit* a write belongs
to - which is the same reason 3i (the RED dev-dependency rule) lives here rather
than in the hook, and this check is deliberately built in its image.

### The shape, exactly

A new section `3j`, after the 3i block that ends at `check-boundaries.sh:568` and
before `exit $fail`. It reuses 3i's loop verbatim in structure:

    for c in $(git rev-list "$BASE"..HEAD 2>/dev/null); do
      ph_at="$(git show "$c:$sfile" 2>/dev/null | sed -nE 's/^phase:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
      ...
      for f in $(git diff-tree --no-commit-id --name-only -r "$c" 2>/dev/null); do

Two counters in 3i's idiom, `harness_test_checked` and `harness_test_problem`,
and the trailing `ok` guarded by `checked > 0 && problem == 0` - which is what
AC-3 pins.

**The predicate for "this phase may write tests"** is read from `phases.conf`,
not hardcoded (AC-4). The reader already exists and must be reused rather than
re-implemented - `check-boundaries.sh` already sources `.claude/hooks/lib.sh`,
which defines `phase_allows <category>` at `lib.sh:772` (re-measured at `c464266`; `:756` when planned). Two properties of it
decide how 3j calls it, and both were checked rather than assumed:

- **It reads the global `$PHASE`, not an argument.** So 3j sets `PHASE` to the
  phase read out of the commit before calling it, and restores it afterwards -
  in a subshell, or by saving and reassigning. Calling `phase_allows test`
  without that asks about the *working tree's* phase and silently answers a
  different question for every commit. This is the single most likely way to
  build a check that passes its own tests and inspects nothing.
- **It fails closed.** A phase matching no row in `phases.conf` returns 1
  (`lib.sh:785-798` at `c464266`, with the comment recording the `GREEN.` production defect).
  So a commit whose story frontmatter carries a garbled phase is refused rather
  than waved through, which is the behaviour this story wants. Do not add an
  escape hatch for it.

Three readers of one predicate cannot disagree; three predicates would.

**The path predicate is the literal prefix `.claude/tests/`**, not the
classifier. `classify` returns `harness` for these paths and that is exactly the
fact being worked around; routing through it would return `harness` for
`.claude/commands/advance-story.md` too and take AC-5 with it. The prefix is
matched with `case "$f" in .claude/tests/*)`, anchored at the start - an
unanchored match would also catch a hypothetical `docs/.claude/tests/x`.

**A commit with no story file** (`ph_at` empty, e.g. `git show` fails) is
skipped, as 3i skips it: `[ -n "$ph_at" ] || continue`. The story-less case is
already handled upstream - every check from 3b is gated behind `sid`.

### Baselines this story may read out rather than re-derive

Measured on `main` at `cffcb4a`, on this branch:

| Measurement | Value |
|---|---|
| `bash .claude/tests/boundaries.test.sh` | `83 passed, 0 failed` |
| the same, with the `:1298` needle widened | `83 passed, 0 failed` |
| commits on `main` touching `.claude/tests/` under a phase that forbids `test` | 4 (`1b6729a`, `0bce924`, `dc56a74`, `4b0033e`), all committed at `REVIEW` |

The third row is the one that can bite, and it is **not** a reason to weaken the
check - see `## Notes`, "The four REVIEW commits".

**Re-measured at PLANNED → RED, on `main` at `c464266` (PO decision 1 in
`## Notes`).** The third row is stale: the same loop now finds **15** attributable
commits (plus 5 unattributed harness refreshes/initial) touching `.claude/tests/`
under a phase whose row lacks `test`:

    5729736 HARNESS-018 GREEN    85f9954 HARNESS-011 GATES    fb963d9 TEL-003 GATES
    5043ee3 TEL-002 GATES        6338f1c HARNESS-015 REVIEW   08483ab HARNESS-014 REVIEW
    cdde349 NET-003 GREEN        8aecfa5 NET-001 GREEN        fcf9a91 TEL-001 GREEN
    dabf267 SEAT-002 GREEN       50b4b68 HARNESS-010 DONE     1b6729a HARNESS-008 REVIEW
    0bce924 SEAT-001 REVIEW      dc56a74 HARNESS-006 REVIEW   4b0033e BOOT-001 REVIEW

All on `main`, so none is in any future PR's `$BASE..HEAD`; the check is
prospective. The first row is the instructive one: HARNESS-018's GREEN commit
rewrote pipe plumbing in six suites. Under 3j that work belongs in RED.

### Oracle partition of the criteria (see `story-authoring`)

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-3 | **Mechanical** | Pin exactly: the refusal text, the commit abbreviation, the `ok` line and its absence. Precision beats invention. |
| AC-4 | **Mechanical, with a required negative control** | The control is the whole criterion. Edit the fixture's `phases.conf` and watch the verdict move; an assertion naming `GREEN` as a literal satisfies AC-1 and asserts nothing about AC-4. |
| AC-5 | **Mechanical** | One fixture commit per named path. `.gitignore` and `project.conf` are the two that `rules.md` argues for by name; do not drop them. |

### Test-only dependencies

None. The suites are bash, and `.claude/tests/_lib.sh` already provides
`make_project_fixture`, `story`, `set_phase` and `commit_all`. No manifest
changes this story, in any phase.

### Changed signatures

None. This story adds a check; it changes no existing export. The caller list is
therefore empty - confirmed, not assumed.

### Where the tests go

`.claude/tests/boundaries.test.sh`, inside a new `describe`. Not a new suite:
`HARNESS-006` §"A new suite" gives the three-part test for when a new file is
warranted, and this fails it - the check is `check-boundaries.sh` behaviour, and
`boundaries.test.sh` is where `check-boundaries.sh` behaviour is asserted.

**The loop for this story is `bash .claude/tests/boundaries.test.sh`, not
`bash scripts/gates.sh`** - the same consequence `HARNESS-006` recorded for RED.
On Windows the suite takes ~4 minutes; budget for it rather than assuming a hang.

## Deferred verifications

<!-- Owner: the phase that runs it. Result pasted in by that phase. -->

**AC-2, AC-3 and AC-5 are "does not refuse" assertions, and they pass vacuously
in RED.** The check does not exist yet, so nothing refuses anything: an assertion
that `check-boundaries.sh` accepts a `project.conf` change under GREEN is
satisfied in RED by a script that has never heard of `.claude/tests`. Three of
five criteria are therefore unverified for the whole of RED, and that is the
`rules.md` negative-control case, not an excuse.

**Owner: GREEN.** RED records, in `## Handoff`, each of these controls with the
value it *expects* once the check exists. GREEN confirms the measured value
against it and pastes the output here. Specifically:

| Control | Expected once 3j exists |
|---|---|
| AC-2 fixture (RED-phase commit touching `.claude/tests/`) | accepted, and the `ok` line reports `1` commit checked |
| AC-3 fixture (no `.claude/tests/` commit at all) | accepted, and **no** `ok` line for 3j appears in the output |
| AC-5 fixtures (`project.conf`, `.gitignore`, `CLAUDE.md`, `.claude/commands/*` under GREEN) | accepted, and no `ok` line for 3j - none of them is under `.claude/tests/` |

The AC-3 and AC-5 rows are the ones that matter: "accepted" is also what a
*broken* 3j that never fires produces. The distinguishing observation is the
**presence or absence of the `ok` line**, which is why AC-3 pins it. GREEN
confirms that distinction by running the AC-1 fixture in the same session and
showing the `ok` line does appear there.

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

Planned by `bash scripts/plan.sh write HARNESS-009` from `.claude/harness/models.conf`.
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

- RED - test-developer - Fable 5.1 (`claude-fable-5-1`), as planned; no override reported to me at dispatch.
- GREEN - feature-developer - Opus 5.5 (`claude-opus-5-5`), as planned; no override. Stopped at 124/1: test #15 ("a commit with no story file to read is skipped") has a false premise - the fixture's `main` already carries `T-1.md` at `phase: PLANNED` (suite line ~216-218), so the "before the story" commit has a story file and PLANNED forbids `test`. Returned for RED.
- RED (return) - test-developer - Fable 5.1 (`claude-fable-5-1`), as planned; no override reported to me at dispatch. Remit: the one defective test; source untouched.

## Out of scope

**`paths.conf` and `phases.conf` are not touched.** A rule-ordering change there
re-classifies every path in the project, and `.claude/tests/classify.test.sh` and
`.claude/tests/phase-guard.test.sh` both assert the current behaviour. The
reasoning against it is in `## Notes`.

**The other half of the exposure: harness *source* is not frozen during RED.**
`scripts/check-boundaries.sh`, `.claude/hooks/phase-guard.sh` and the rest of
`scripts/**` are `harness`, so RED can write the production code that makes its
own new test pass - law 1 with the same hole law 2 has. It is real, and it is
deliberately not this story:

- It is a **separate behaviour**, so a separate RED→GREEN cycle. Doing both here
  is the "two features joined by and" sizing failure in `story-authoring`.
- It is **not the same fix**. The `.claude/tests/` prefix is a clean, narrow
  predicate. "Harness source" is not: `harness` also covers `.gitignore`,
  `CLAUDE.md`, `.gitattributes`, `.github/**`, and every `.claude/**` markdown
  prompt - all of which `rules.md` argues must stay writable in every phase, some
  by name. Freezing `scripts/**` in RED needs a predicate nobody has written yet,
  and getting it wrong withdraws a permission the harness documents.
- It is **lower yield**. Weakening a test is silent by construction; writing
  harness source in RED still has to survive the story's own tests and the gate
  stamp.

File it as its own story if this one lands. Do not widen this one to reach it.

**No new gate.** `## Gate probes` is omitted for that reason. The artifact is an
assertion inside a suite CI already runs via `scripts/selftest.sh`.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

One level only: the existing integration harness in
`.claude/tests/boundaries.test.sh`, which runs the real `scripts/check-boundaries.sh`
against a two-branch fixture repository. That is where `check-boundaries.sh`
behaviour is asserted, and 3j is per-commit behaviour of that script - a unit
test of a predicate would not see the commit loop, which is the thing most likely
to be built wrong (contract: "the single most likely way to build a check that
passes its own tests and inspects nothing").

New `describe "the harness's own suites obey the test freeze"`, placed directly
after the 3i block whose shape it copies. 30 assertions, run by
`bash .claude/tests/boundaries.test.sh`. One fixture helper, `suite_story
<phase> <path>...`: first commit appends to each path with the story in `<phase>`,
second commit moves the story to REVIEW (manifest_story's shape, so the tip
never carries the offending phase), and `$c7` is the offending commit's 7-char
sha.

| # | Assertion (as named in the suite) | AC | Kind |
|---|---|---|---|
| 1 | a suite edited in GREEN is refused, naming the commit, the path and the phase | AC-1 | red in RED |
| 2 | and in GATES | AC-1 | red in RED |
| 3 | the verdict follows the phase AT THE COMMIT, not the phase at the tip (tip moved to RED) | AC-1 / contract `$PHASE` trap | red in RED |
| 4 | nor the phase in the environment (`PHASE=RED` exported into the run) | AC-1 / contract `$PHASE` trap | red in RED |
| 5 | a garbled phase in the commit's frontmatter fails closed (`GREEN.`) | contract "fails closed" | red in RED |
| 6 | a suite edited in RED is not refused | AC-2 | vacuous in RED |
| 7 | and the ok line reports the one commit inspected (`(1 commit(s))`, whole-line) | AC-2 | red in RED |
| 8 | SCAFFOLD may write a suite too | AC-2 | vacuous in RED |
| 9 | and is counted the same way | AC-2 | red in RED |
| 10 | two suites in one commit count as one commit | AC-2 (unit is commits, not files) | red in RED |
| 11 | two RED commits are both fine | AC-2 | vacuous in RED |
| 12 | and both are counted (`(2 commit(s))`) | AC-2 | red in RED |
| 13 | a branch that touches no suite is not refused | AC-3 | vacuous in RED |
| 14 | and 3j prints no ok line for it - nothing was inspected | AC-3 | vacuous in RED |
| 15 | a commit with no story file to read is skipped, as 3i skips it | contract "no story file" | vacuous in RED |
| 16 | and not counted | contract / AC-3 | vacuous in RED |
| 17-22 | GREEN may still write `.claude/harness/project.conf`, `.gitignore`, `CLAUDE.md`, `.claude/commands/advance-story.md`, `scripts/new-tool.sh`, `docs/.claude/tests/x.md` (one commit per path, one run) | AC-5 (+ unanchored-prefix trap) | vacuous in RED |
| 23 | and none of them counts as a suite inspection | AC-5 / AC-3 | vacuous in RED |
| 24 | when GREEN's row gains test, the same GREEN commit is accepted | AC-4 | vacuous in RED |
| 25 | and counted as inspected | AC-4 | red in RED |
| 26 | phases.conf restored byte-for-byte | fixture hygiene | passes |
| 27 | restored, the same commit is refused again - the row was the cause | AC-4 (control) | red in RED |
| 28 | when RED's row loses test, a RED commit is refused, naming RED | AC-4 | red in RED |
| 29 | phases.conf restored byte-for-byte | fixture hygiene | passes |
| 30 | restored, the RED commit is accepted again | AC-4 (control) | vacuous in RED |

Edges covered: zero / one / many commits (AC-3, AC-2, #12); one commit with
many files (#10); every phase kind (`test` row, no `test` row, no row at all);
the tip and the environment carrying a permitting phase while the commit does
not (#3, #4); the prefix trap (`docs/.claude/tests/`); a commit before the story
file exists (#15).

Not covered, deliberately: the 15 historical commits on `main` (they are outside
every future `$BASE..HEAD`, confirmed below); `paths.conf`/`phases.conf` changes
in this repo (out of scope); harness *source* in RED (out of scope).

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

### Command

    bash .claude/tests/boundaries.test.sh

Not `gates.sh`: no gate runs this suite (CI runs it via `scripts/selftest.sh`).
~4.5 minutes on this Windows machine; budget for it. `VERBOSE=1` prints the
passing assertions too.

### Failure output (verbatim, second run, this tree)

Baseline before the block, **re-measured on this tree** by running the
committed (`HEAD`) suite from the scratchpad against the real `_lib.sh`:
`boundaries: 95 passed, 0 failed`. The contract's `83` was taken at `cffcb4a`
and is stale at `c464266` (HARNESS-016/017/018 added assertions since); it is
the "verify any number you depend on" case, and the exposure argument does not
change with it. With the block:

```
  the harness's own suites obey the test freeze
    FAIL a suite edited in GREEN is refused, naming the commit, the path and the phase
         expected a refusal saying: story T-1: commit 74f1b77 changed '.claude/tests/x.test.sh' while the story was in GREEN, which may not write tests
         actual:                    ok    story files validated
         ok    harness state not tracked
         ok    source changes accompanied by test changes (0 source, 0 test)
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         FAIL  story T-1: ## Gate results was not written by scripts/gates.sh. Run 'bash scripts/gates.sh' - it records its own result; a pasted summary is not evidence.
         ok    ## Handoff is filled in
    FAIL and in GATES
         expected a refusal saying: story T-1: commit d995dd8 changed '.claude/tests/x.test.sh' while the story was in GATES, which may not write tests
         [same output]
    FAIL the verdict follows the phase AT THE COMMIT, not the phase at the tip
         expected a refusal saying: story T-1: commit 9cda1f8 changed '.claude/tests/x.test.sh' while the story was in GREEN, which may not write tests
         actual:                    ok    story files validated
         ok    harness state not tracked
         ok    source changes accompanied by test changes (0 source, 0 test)
         FAIL  story T-1 is in phase 'RED'; a PR should be opened from REVIEW or DONE
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         ok    ## Handoff is filled in
    FAIL nor the phase in the environment
         expected a refusal saying: story T-1: commit 9cda1f8 changed '.claude/tests/x.test.sh' while the story was in GREEN, which may not write tests
         [same output]
    FAIL a garbled phase in the commit's frontmatter fails closed
         expected a refusal saying: story T-1: commit 616ecca changed '.claude/tests/x.test.sh' while the story was in GREEN., which may not write tests
         [same output as the first]
    ok   a suite edited in RED is not refused
    FAIL and the ok line reports the one commit inspected
         expected: 1
         actual:   0
    ok   SCAFFOLD may write a suite too
    FAIL and is counted the same way
         expected: 1
         actual:   0
    FAIL two suites in one commit count as one commit
         expected: 1
         actual:   0
    ok   two RED commits are both fine
    FAIL and both are counted
         expected: 1
         actual:   0
    ok   a branch that touches no suite is not refused
    ok   and 3j prints no ok line for it - nothing was inspected
    ok   a commit with no story file to read is skipped, as 3i skips it
    ok   and not counted
    ok   GREEN may still write .claude/harness/project.conf
    ok   GREEN may still write .gitignore
    ok   GREEN may still write CLAUDE.md
    ok   GREEN may still write .claude/commands/advance-story.md
    ok   GREEN may still write scripts/new-tool.sh
    ok   GREEN may still write docs/.claude/tests/x.md
    ok   and none of them counts as a suite inspection
    ok   when GREEN's row gains test, the same GREEN commit is accepted
    FAIL and counted as inspected
         expected: 1
         actual:   0
    ok   phases.conf restored byte-for-byte
    FAIL restored, the same commit is refused again - the row was the cause
         expected a refusal saying: story T-1: commit f6adb78 changed '.claude/tests/x.test.sh' while the story was in GREEN, which may not write tests
         [same output as the first]
    FAIL when RED's row loses test, a RED commit is refused, naming RED
         expected a refusal saying: story T-1: commit 91d815d changed '.claude/tests/x.test.sh' while the story was in RED, which may not write tests
         [same output as the first]
    ok   phases.conf restored byte-for-byte
    ok   restored, the RED commit is accepted again

boundaries: 113 passed, 12 failed
```

**Why this is the right failure.** Every one of the 12 is either "expected a
refusal saying `… changed '.claude/tests/x.test.sh' while the story was in
<PHASE> …`" with an `actual:` that contains no such line, or "expected: 1 /
actual: 0" for the whole-line count of 3j's `ok` line. Nothing in
`check-boundaries.sh` mentions `.claude/tests` (`grep -c '3j\|harness suites
changed only' scripts/check-boundaries.sh` -> `0`), so no refusal and no `ok`
line is exactly what a script without 3j prints. The only `FAIL` inside the
`actual:` blocks is the pre-existing gate-record rule (fixture stories carry no
`## Gate results`), which is why the "accepted" assertions read the absence of
3j's text rather than a clean exit - `accepts_manifest`'s shape, for
`accepts_manifest`'s reason. The 95 pre-existing assertions all still pass:
113 passed = 95 baseline + 18 vacuous/hygiene passes in the new block, and the
12 failures are all inside the new block (30 = 18 + 12).

Note for GREEN on the `refused` helper: it checks the message AND a non-zero
exit, but the fixture already exits non-zero on the gate-record rule, so the
exit half is not load-bearing here. `problem` (not `note`) is what 3j must call;
the message check is what pins it.

### Files touched

| File | What |
|---|---|
| `.claude/tests/boundaries.test.sh` | new `describe "the harness's own suites obey the test freeze"` (after the 3i block, ~line 891-1105); helpers `SUITE_OK`, `suite_refusal`, `ok_line_count`, `accepts_suite`, `no_suite_ok_line`, `suite_story`, `phases_edit`, `phases_restore`; 30 assertions. Nothing outside the block changed. |
| `docs/backlog/stories/HARNESS-009.md` | `## Test plan`, this section, `## Model guidance` Resolved line |

`scripts/check-boundaries.sh`, `.claude/hooks/lib.sh`, `paths.conf`,
`phases.conf`: **untouched** (`git status` shows only the two files above). The
lock would not have stopped a write there - that is this story's subject - so
this is stated rather than assumed.

### The strings the tests pin, verbatim

GREEN builds exactly these; every other word of the message is the
implementer's choice.

**Refusal** (via `problem`, so it prints with the `FAIL  ` prefix and sets
`fail=1`). Matched as ONE substring carrying commit, path and phase:

    story $sid: commit ${c%${c#???????}} changed '$f' while the story was in $ph_at, which may not write tests

i.e. for the fixture:

    story T-1: commit 74f1b77 changed '.claude/tests/x.test.sh' while the story was in GREEN, which may not write tests

The commit is the first 7 characters of the full sha (3i's
`${c%${c#???????}}`); the test computes it as `git rev-parse HEAD | cut -c1-7`
on the offending commit. `$ph_at` is the phase string as read from the
committed frontmatter, so a garbled `GREEN.` is echoed as `GREEN.`. Anything
may follow the pinned text (a remedy sentence is a good idea: `bash
scripts/phase.sh set <id> RED`, and `## Regressions`).

**ok line** (via `ok`, so `ok    ` prefix). Matched as a WHOLE LINE with
`grep -Fxc`, so the count is exact and `(11 commit(s))` does not satisfy
`(1 commit(s))`:

    ok    harness suites changed only where the phase may write tests ($harness_test_checked commit(s))

Printed only when `checked > 0 && problem == 0`; the count is **commits** that
touched `.claude/tests/` under a permitting phase (not files - #10 pins that:
two files in one commit -> `1`; #12: two commits -> `2`).

**Absence needles** used by the "accepted" assertions: the substring
`which may not write tests` (refusal) and `harness suites changed only where the
phase may write tests` (ok line). Both are unique to 3j; nothing else in the
script prints them today (`grep -c` above).

### What the tests constrain, and what they do not

Constrained:
- Per-commit over `git rev-list "$BASE"..HEAD`, phase read from `$sfile` **at
  that commit** (#3: tip says RED, commit says GREEN -> refused).
- The phase predicate is `phase_allows test` from lib.sh with `PHASE` set to
  the commit's phase (#4: `PHASE=RED` in the environment must not change the
  verdict; #5: unknown phase refused; AC-4: the verdict moves when the fixture's
  `phases.conf` rows change, both directions, with no edit to the script).
- Path predicate: anchored prefix `.claude/tests/` (AC-5 includes
  `docs/.claude/tests/x.md`, which must NOT be refused).
- A commit with no readable story file is skipped and not counted (#15, #16).

Not constrained (implementer's choice): variable names, where inside the 3i ->
`exit $fail` gap the block sits, the remedy text after the pinned prefix,
whether one refusal is printed per file or per commit (the fixture has one file
per offending commit in every AC-1 case; #10's two-file commit is under RED so
it is counted, not refused), and how `PHASE` is scoped (subshell or
save/restore - **but see the `set -u` note below**).

### Verified mechanisms (checked, not assumed)

- `phase_allows` reads global `$PHASE`, not an argument, and fails closed.
  Driven directly from a shell sourcing lib.sh:
  `RED -> allows test; GREEN -> refuses; SCAFFOLD -> allows; REVIEW -> refuses;
  'GREEN.' -> refuses; ZZZ -> refuses; '' -> refuses`.
- **`check-boundaries.sh` runs `set -uo pipefail` and never sets `PHASE`.**
  With `PHASE` unset, `phase_allows test` aborts: `lib.sh: line 779: PHASE:
  unbound variable`. So 3j must assign `PHASE` (in a subshell or with
  save/restore of `${PHASE:-}`) before every call - an implementation that
  relies on the environment happening to carry one will either abort the whole
  script or read the wrong phase (#4 covers the second; the first would show up
  as every assertion in the suite failing at once).
- `HARNESS_DIR` comes from `CLAUDE_PROJECT_DIR`, which check-boundaries.sh sets
  to its own `$ROOT`, so in the fixture `phase_allows` reads the FIXTURE's
  `phases.conf` - which is what makes the AC-4 edit reach the predicate.
- Notes item 1 ("RED should confirm this rather than take it from here"): a PR's
  `$BASE..HEAD` does contain the story's own commits in every phase. Checked on
  the last three merges into `main`; e.g. PR #35 (HARNESS-018), range
  `45a7aa0..df40a58`: `df40a58 REVIEW`, `ab88676 GATES`, `e868f59 GATES`,
  `5729736 GREEN (6 files under .claude/tests/)`, `fa02e8f RED (1)`,
  `6213c3c PLANNED`. 3j would have refused `5729736`, exactly as the contract's
  re-measurement says. The RED commit is at RED and passes.
- **Changed signatures: none, confirmed.** `grep -rn phase_allows scripts
  .claude/hooks .claude/tests` finds one caller (`phase-guard.sh:32`) and
  comments; 3j adds a caller and changes no signature. Nothing outside
  `check-boundaries.sh` reads `red_manifest_*` or 3i's ok line, so nothing else
  needs to change. Caller list to update: empty.

### Tests that pass on arrival, and what earns them

The 18 vacuous passes (#6, #8, #11, #13-#24 except #7/#9/#10/#12, #26, #29, #30
in the Test plan table) are "does not refuse" / "no ok line" readings. In RED
nothing refuses, so they cannot fail. They are NOT earned by a probe in this
phase - there is nothing to mutate - and the story's `## Deferred verifications`
already assigns them to GREEN. What earns them in GREEN is the positive
controls in the same block: the AC-1 fixture's refusal (#1) and the AC-2
fixture's ok line (#7) run in the same session, so a 3j that never fires cannot
pass #1/#7 while vacuously passing #13/#14. GREEN should also run the
`mutate.sh` probe below once 3j exists, to show the absence assertions bite.

**Declined, in those words:** I cannot run the deferred verifications for AC-2,
AC-3, AC-5. They require 3j to exist. Owner: GREEN.

### Expected value of every control (claims until GREEN measures them)

| Control (fixture) | Threshold / needle | Expected once 3j exists | Measured in RED |
|---|---|---|---|
| AC-1: GREEN commit touching `.claude/tests/x.test.sh`, tip REVIEW | refusal string with `74f1b77`-shaped sha, path, `GREEN` | refused, exit 1 | no refusal (0 matches) |
| AC-1: same at GATES | `… in GATES, …` | refused | no refusal |
| trap: tip at RED, commit at GREEN | `… in GREEN, …` | refused | no refusal |
| trap: `PHASE=RED` exported, commit at GREEN | `… in GREEN, …` | refused | no refusal |
| garbled `GREEN.` | `… in GREEN., …` | refused | no refusal |
| AC-2: RED commit | no refusal; `ok … (1 commit(s))` exact line count | accepted, count line = 1 | accepted (vacuous), count = 0 |
| AC-2: SCAFFOLD commit | same | accepted, 1 | accepted (vacuous), 0 |
| AC-2: one RED commit, two files | `(1 commit(s))` | 1 | 0 |
| AC-2: two RED commits | `(2 commit(s))` | accepted, 2 | accepted (vacuous), 0 |
| AC-3: GREEN commit touching `src/main.ts` only | no refusal AND no ok line | accepted, no ok line | accepted, no ok line (vacuous) |
| no-story-file commit touching `.claude/tests/` | no refusal, no ok line | skipped: accepted, no ok line | same (vacuous) |
| AC-5: GREEN commits, one each: `project.conf`, `.gitignore`, `CLAUDE.md`, `.claude/commands/advance-story.md`, `scripts/new-tool.sh`, `docs/.claude/tests/x.md` | no `changed '<path>' while the story was in` per path; no ok line | accepted x6, no ok line | same (vacuous) |
| AC-4a: fixture `phases.conf` GREEN row gains `test`; the AC-1 commit | no refusal; ok line = 1 | accepted, 1 | accepted (vacuous), 0 |
| AC-4a control: file restored, same commit | refusal `… in GREEN, …` | refused | no refusal |
| AC-4b: RED row loses `test`; RED commit | refusal `… in RED, …` | refused | no refusal |
| AC-4b control: restored | no refusal | accepted | accepted (vacuous) |

Suggested GREEN probe once 3j is in (allowed in every phase; restores and
`cmp`s): make the phase read the tip instead of the commit, e.g.

    bash scripts/mutate.sh scripts/check-boundaries.sh \
      's/ph_at="$(git show "$c:$sfile"/ph_at="$(git show "HEAD:$sfile"/' \
      -- bash .claude/tests/boundaries.test.sh

Expected: #3 ("the verdict follows the phase AT THE COMMIT") goes red and the
rest of the block stays green - note the 3i loop has the same line, so check the
expression hits only the 3j copy (anchor on a 3j-only neighbour, or use a line
number as the story's `## Context` did).

### Things GREEN should know

- The fixture has **no `.gitattributes`** and this machine has
  `core.autocrlf=true`, so `git checkout -- <file>` inside the fixture writes
  CRLF. The first run of this block failed its own "restored byte-for-byte"
  check on content that was identical modulo line endings; `phases_restore` now
  `cp`s from `$REPO_ROOT` as `make_fixture` does. Not a 3j concern, but it is
  why `phase_allows` strips `\r` and 3j should read the phase with the same
  `tr -d '[:space:]'` 3i uses.
- Two commits on a PR can carry the same `.claude/tests/` path; the count is
  per commit, not per path, and a commit is counted once however many suite
  files it touches.
- The lock did not and will not stop a write to `scripts/check-boundaries.sh`
  in RED (out of scope, named in the story). I did not touch it; GREEN should
  diff `scripts/` against `c464266` before starting and find nothing.

### Gates

`bash scripts/gates.sh --fast` at the end of RED, this tree:

```
PASS         format (1s, observed 90)
PASS         lint (0s, observed 90, floor 1)
PASS         typecheck (2s, observed 17)
PASS         unit (28s, observed 452, floor 443)
UNCONFIGURED coverage
PASS         build (0s, observed 57746)
PASS         harness (13s, observed 40)
--fast skipped: integration mutation
All required gates passed (6 ran, 1 unconfigured, 0 known).
```

All green, and that is the expected shape here rather than a problem: no gate
runs `boundaries.test.sh` (`harness` runs `project-counters.test.sh` only; the
story's `## Context` measured this), so the test gates cannot be red on account
of this story. The red lives in `scripts/selftest.sh`, which CI's required
`gates` job runs before `gates.sh`. What the run confirms is that the new block
trips no lint/format gate (their targets are Luau under `src tests lune`; bash
under `.claude/tests/` is outside every target set). Not recorded in the story,
as a `--fast` run never is.

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

### Return 1: GREEN -> RED, 2026-09-29 - the "no story file" case inherited one

**Which test.** `.claude/tests/boundaries.test.sh`, the AC-3 pair
`a commit with no story file to read is skipped, as 3i skips it` and
`and not counted` (the block under `# A commit made before the story file
exists on the branch`).

**What it asserted, and what was wrong.** It claimed to build a branch whose
first commit touches `.claude/tests/x.test.sh` *before* the story file exists,
and asserted 3j neither refuses that commit nor counts it. The premise was
false: the suite uses one shared `$FIX`, and its `main` already carries
`docs/backlog/stories/T-1.md` at `phase: PLANNED` (the 3d anchor, suite lines
214-218). A branch cut from `main` inherits that file, so `git show
"$c:$sfile"` read `PLANNED` for the "pre-story" commit, `PLANNED` does not list
`test`, and 3j refused it - correctly, per AC-1. The test was asserting the
wrong world, not the wrong behaviour.

**How found.** GREEN (Opus 5.5) ran the suite at `124 passed, 1 failed` with
3j refusing `commit 5f443fa changed '.claude/tests/x.test.sh' while the story
was in PLANNED`; the orchestrator reproduced it independently in a plain-git
repo (see `## Notes`, "GREEN escalation").

**What it asserts now.** The same two things - no refusal, no ok line - but
against a commit that genuinely lacks the story: the pre-story commit now
`git rm`s `docs/backlog/stories/T-1.md` alongside its append to `x.test.sh`,
and the next commit re-adds the story at `REVIEW`. Neither `accepts_suite` nor
`no_suite_ok_line` was touched. One `mkdir -p docs/backlog/stories` was added
before `_story_file REVIEW`, because `git rm` drops the emptied directory -
without it the re-add silently failed (`line 547: .../T-1.md: No such file or
directory`), HEAD had no story, `sid` was empty, 3j never ran, and the
assertion passed vacuously: the first probe of this correction came back
`125 passed, 0 failed` *with the skip mutated away*, which is how the missing
`mkdir` was found. Verified before the real probes, in a throwaway repo: the
pre-story commit lists `.claude/tests/x.test.sh docs/backlog/stories/T-1.md`
with `phase=[]`, the next lists only the story with `phase=[REVIEW]`; and
`PHASE=""; phase_allows test` returns `1` (fails closed), so removing the skip
must produce a refusal.

**What earns it - probe 1, the skip (earns "is skipped").** Line 589 of
`scripts/check-boundaries.sh` is 3j's `[ -n "$ph_at" ] || continue` (541 is
3i's). Replaced with `:` so an empty phase reaches `phase_allows`:

    $ bash scripts/mutate.sh scripts/check-boundaries.sh '589s/^  \[ -n "\$ph_at" \] || continue$/  :/' -- bash .claude/tests/boundaries.test.sh
    === mutate: scripts/check-boundaries.sh (1 line(s) changed by 589s/^  \[ -n "\$ph_at" \] || continue$/  :/) ===
      589 -   [ -n "$ph_at" ] || continue
      589 +   :
    === mutate: running bash .claude/tests/boundaries.test.sh ===
    ...
        FAIL a commit with no story file to read is skipped, as 3i skips it
             refused: ok    story files validated
             ...
             FAIL  story T-1: commit 4bc80e3 changed '.claude/tests/x.test.sh' while the story was in , which may not write tests. A harness suite is a test, and law 2 freezes tests outside RED; the lock cannot see this because the path classifies as harness. Return to RED ('bash scripts/phase.sh set T-1 RED'), make the change there, and record why in ## Regressions.
    ...
    boundaries: 124 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260929T165707Z.1195090.bak) ===
      589:   [ -n "$ph_at" ] || continue

Exactly one failure, the corrected assertion, and the message names the empty
phase (`while the story was in ,`) on the pre-story commit.

**What earns it - probe 2, the count (earns "and not counted").** Probe 1
cannot red the companion: a refused commit prints no ok line either way. So a
second mutation makes the skip *count* what it skips:

    $ bash scripts/mutate.sh scripts/check-boundaries.sh '589s/^  \[ -n "\$ph_at" \] || continue$/  [ -n "$ph_at" ] || { harness_test_checked=$((harness_test_checked+1)); continue; }/' -- bash .claude/tests/boundaries.test.sh
    === mutate: scripts/check-boundaries.sh (1 line(s) changed by ...) ===
      589 -   [ -n "$ph_at" ] || continue
      589 +   [ -n "$ph_at" ] || { harness_test_checked=$((harness_test_checked+1)); continue; }
    === mutate: running bash .claude/tests/boundaries.test.sh ===
    ...
        FAIL and not counted
             3j reported an inspection where nothing under .claude/tests/ changed: ok    story files validated
    ...
    boundaries: 124 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260929T170108Z.1212077.bak) ===
      589:   [ -n "$ph_at" ] || continue

Again exactly one failure, the companion. Both probes were local runs
(Windows, Git Bash); each suite run is ~4.5 min here, run one at a time.

**GREEN is a no-op.** This return touched only the suite and the story;
`scripts/check-boundaries.sh` still holds GREEN's uncommitted 3j, byte-for-byte
(both restores verified by `cmp`, `.claude/state/mutations/` holds only `log`).
Unmutated run after the correction:

    $ git diff --stat scripts/check-boundaries.sh | tail -1
     1 file changed, 35 insertions(+)        # GREEN's 3j, unchanged by this return
    $ bash .claude/tests/boundaries.test.sh
    boundaries: 125 passed, 0 failed

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Notes

### The three options, weighed

**A. `test | .claude/tests/**` above the harness rules in `paths.conf`.**
The obvious fix, and it does work for law 2: the suites would be frozen in GREEN,
GATES, REVIEW and DONE, writable in RED and SCAFFOLD, exactly as an ordinary test
is. The gate stamp is unaffected (`gated_stdin` keeps `test` as well as
`harness`), and check 3a would start counting these files as `tst`, which
incidentally repairs the blind spot described in `## Context`.

Rejected for this story on **blast radius, not on correctness**. It re-classifies
every path under `.claude/tests/` for every consumer of the classifier at once -
the lock, `check-boundaries.sh`, `gate_tree_hash`, `code_changed_since`,
`classify.sh --list` - and `classify.test.sh` and `phase-guard.test.sh` both
assert today's answers. It also reaches further than it looks: `_lib.sh` and any
future non-test helper under that directory come along. That is a change worth
making deliberately, with its own story and its own reading of the two suites it
breaks; it is not a change to make as the incidental mechanism of this one.

**B. A new category** (`harness_test`, or splitting `harness` into prompt/code/
test). The most principled answer and the most expensive: a category is a new
column in `phases.conf`, a new case in every consumer, and an edit to
`.claude/state/README.md`'s table and `settings.test.sh`'s two-directional check.
It buys nothing over A for *this* exposure. Worth revisiting only if the
`## Out of scope` harness-source half is also taken on, where a category split is
genuinely the natural shape.

**C. A check in `check-boundaries.sh`. Chosen.** It changes the verdict for
`.claude/tests/**` and for nothing else; it needs no new category and no
re-classification; it follows 3i, which already does per-commit phase-aware diff
inspection, so it is a second instance of an existing pattern rather than a new
one. Its limitation is honest and worth stating: **it catches the commit, not the
keystroke.** An agent can still write the file mid-GREEN and see no denial; CI
refuses the PR afterwards. That is strictly weaker than the lock, and it is the
same trade `rules.md` already accepts for the RED manifest rule - the lock sees a
path, never a diff, so the per-commit questions have to be asked here.

### The four REVIEW commits

`1b6729a`, `0bce924`, `dc56a74` and `4b0033e` each touch `.claude/tests/` with
the committed story phase at `REVIEW`, which forbids `test`. So 3j would have
refused all four had it existed. Two things follow, and neither is "loosen it":

1. **They are on `main`, not on a branch.** `check-boundaries.sh` iterates
   `git rev-list "$BASE"..HEAD`, so a PR sees its own story commits. The RED
   commits of those same stories (`cdc2031`, `8012d8b`, `af393f8`) are correctly
   at `RED` and pass. RED should confirm this rather than take it from here - it
   is a claim about what `$BASE..HEAD` contains, and this story's whole subject
   is claims that were never run.
2. **`0bce924` is a true positive.** Its message says the edit was "taken as a
   return to RED... because the only legal fix is a write REVIEW forbids", and the
   frontmatter it committed says `phase: REVIEW`. The intent was right, the
   `phase.sh set` never happened, and nothing noticed. A check that refuses that
   commit is doing its job: the fix is one `bash scripts/phase.sh set <id> RED`
   before the edit, which is what `rules.md` already prescribes for exactly this
   situation ("A gate failure whose only legal fix is a write the current phase
   forbids is a return to RED").

If this turns out to be noisy in practice, the answer is a story recording why -
not a widened predicate. Loosening a comparison to reach green is the move
`rules.md` names as always a weakening.

### PO decisions at PLANNED → RED (2026-09-29, `c464266`)

1. **The baseline of violating commits on `main` is 15, not 4** (table in
   `## Contract`). No AC changes: every one of them is on `main`, outside any
   future `$BASE..HEAD`, and the growth is the exposure this story names, not
   noise. Stories that edit suite *plumbing* (HARNESS-018-shaped) will now need
   to do it in RED; that is law 2 applied, and it is the intended effect.
2. **This story's own commits.** The practice on this repo is one commit per
   phase, so this story's `boundaries.test.sh` change is committed with
   `phase: RED` and 3j passes its own PR. A GREEN/GATES/REVIEW commit here that
   touched `.claude/tests/` would be refused by the check it adds - correctly.
3. **Gate.** Unchanged from `## Context`: no `gates.sh` gate reads
   `boundaries.test.sh`; CI's required `gates` job runs it via
   `scripts/selftest.sh`. `required_gates` stays empty.
4. **Epic.** None; no done-when to check.
5. **Deferred verifications are owned by GREEN**, not GATES, because the
   controls are "does not refuse" readings that GREEN observes the moment 3j
   exists; nothing needs source broken to run them. Accepted as planned.

### Orchestrator verification of RED (2026-09-29)

- Diff scope: only `.claude/tests/boundaries.test.sh` and this story changed;
  `git diff --stat c464266 -- scripts .claude/hooks .claude/harness` is empty,
  and `grep -c '3j\|harness suites changed only' scripts/check-boundaries.sh` is `0`.
- Independent run of `bash .claude/tests/boundaries.test.sh`:
  `boundaries: 113 passed, 12 failed` (exit 1). All 12 failures are in the new
  describe and show no 3j refusal or ok line. The only refusals present come
  from pre-existing checks (gate record, REVIEW phase). The failure is correct.
- `bash scripts/gates.sh --fast`: `All required gates passed (6 ran, 1
  unconfigured, 0 known)`. This is expected, because no gate reads
  `boundaries.test.sh` (PO decision 3). The new block trips neither format nor lint.
- Accepted for GREEN: the subagent found that `check-boundaries.sh` runs under
  `set -u` and never sets `PHASE`, so 3j must assign it before calling
  `phase_allows`. The suite baseline was re-measured at 95/0 on this tree,
  replacing 83/0 at `cffcb4a`.

### GREEN escalation: one frozen test is wrong (2026-09-29, pending user decision)

GREEN (Opus 5.5) added 3j and stopped at `boundaries: 124 passed, 1 failed`. The failing test is
`a commit with no story file to read is skipped, as 3i skips it`. 3j refused
`commit 5f443fa changed '.claude/tests/x.test.sh' while the story was in PLANNED`.
The claim is that the test's premise is false, because the fixture's `main` already carries `T-1.md` at
`phase: PLANNED` (boundaries.test.sh:214-218, one shared `$FIX`). The
"pre-story" commit therefore inherits a story file, and AC-1 requires the refusal.

**Orchestrator reproduction, independent of the subagent's code and on different inputs.** I used a fresh
plain-git repo, not the fixture: `main` carries `Z-9.md` at `phase: DONE`, and a branch
commit touches `.claude/tests/q.test.sh`. `git show "$c:…/Z-9.md" | sed …` gave
`[DONE]`, not empty. After `git rm` of the story it gave `[]`. So only a commit that
genuinely lacks the file skips, and the test must create one, for example with `git rm` in the
pre-story commit. I also read `:214-218` to confirm the inherited `PLANNED` file. Freeze held:
`frozen: OK — 22 path(s) unchanged since the snapshot for HARNESS-009`.

### Provenance

Investigated from the `HARNESS-002` `## Notes` finding, on `main` at `cffcb4a`,
before that story's PR (#14) merged. Every measurement in `## Context` was taken
on this branch rather than quoted: the phase table by driving the real hook
through a `make_fixture` carrying the real `paths.conf` and `phases.conf`, the
83/0 pair by `scripts/mutate.sh` and a clean baseline run, the classification
lines by `scripts/classify.sh` and by sourcing `gated_stdin` from
`.claude/hooks/lib.sh`. The mutation restored byte-for-byte and
`.claude/state/mutations/` holds only its `log`.
