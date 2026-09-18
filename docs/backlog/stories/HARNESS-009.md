---
id: HARNESS-009
title: The harness's own test suites obey the test freeze
slug: the-harness-s-own-test-suites-obey-the-t
epic: 
type: chore
status: todo
phase: PLANNED
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
which defines `phase_allows <category>` at `lib.sh:756`. Two properties of it
decide how 3j calls it, and both were checked rather than assumed:

- **It reads the global `$PHASE`, not an argument.** So 3j sets `PHASE` to the
  phase read out of the commit before calling it, and restores it afterwards -
  in a subshell, or by saving and reassigning. Calling `phase_allows test`
  without that asks about the *working tree's* phase and silently answers a
  different question for every commit. This is the single most likely way to
  build a check that passes its own tests and inspects nothing.
- **It fails closed.** A phase matching no row in `phases.conf` returns 1
  (`lib.sh:769-782`, with the comment recording the `GREEN.` production defect).
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

### Provenance

Investigated from the `HARNESS-002` `## Notes` finding, on `main` at `cffcb4a`,
before that story's PR (#14) merged. Every measurement in `## Context` was taken
on this branch rather than quoted: the phase table by driving the real hook
through a `make_fixture` carrying the real `paths.conf` and `phases.conf`, the
83/0 pair by `scripts/mutate.sh` and a clean baseline run, the classification
lines by `scripts/classify.sh` and by sourcing `gated_stdin` from
`.claude/hooks/lib.sh`. The mutation restored byte-for-byte and
`.claude/state/mutations/` holds only its `log`.
