---
id: HARNESS-015
title: Proving a frozen file was untouched needs a check that works when the previous phase is uncommitted
slug: proving-a-frozen-file-was-untouched-need
epic: 
type: fix
status: todo
phase: PLANNED
branch: story/HARNESS-015-proving-a-frozen-file-was-untouched-need
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Every harness story so far has proved that a phase respected the law by showing
a diff is empty. `HARNESS-001` line 529, `HARNESS-012` lines 349/399/429/705,
`HARNESS-013` line 156 and `HARNESS-014`'s own Contract all say some form of:

> show `git diff --stat scripts/mutate.sh` empty at the end of RED

That check is **correct in the RED direction and silently wrong when mirrored to
GREEN**, and nothing in the repository says so. The asymmetry is not about the
files; it is about what is committed.

- **At RED**, the frozen file is *source*. Its last committed state is the
  previous story's merge, and RED has not touched it, so `git diff --stat` is
  genuinely empty. The check works.
- **At GREEN**, the frozen file is a *test*, and RED's work on it **is not
  committed** — the whole story is one branch and commits at GATES→REVIEW. So
  `git diff --stat <test file>` shows RED's own additions on any healthy GREEN.
  The check cannot pass. Worse, the only way to satisfy it is for GREEN to have
  **reverted the tests**, which is the exact violation it was written to detect.

**How this was found, and it is not hypothetical.** During `HARNESS-014`'s GREEN
phase the Lead PO's dispatch brief mirrored the convention and required
`git diff --stat .claude/tests/plan.test.sh` to be empty. The feature-developer
refused the instruction, explained why it could never hold, and substituted the
right check unprompted: the file's **blob hash**, recorded before the phase and
compared after —

    $ git hash-object .claude/tests/plan.test.sh
    fc05cedeed467f8f3ea4583db83725b1cc1c54c1

which the orchestrator then confirmed independently against the `index
bf15990..fc05ced` line in RED's own diff. That is recorded in `HARNESS-014`'s
`## Notes` under "Correction 1". The agent was right and the brief was wrong.

**Why it is worth a story rather than a note.** Three reasons, in order of
weight:

1. **The failure mode is a false negative on the law's most important
   invariant.** An agent that meets an unsatisfiable check has three options:
   report it (what happened here, and it depended on the agent being careful),
   quietly ignore it, or "fix" it by reverting the frozen file. The third is
   catastrophic and the second is invisible. A check that cannot pass teaches
   agents that checks are advisory.
2. **It bites hardest exactly where the phase lock does not.** For a story whose
   files all classify as `harness` — every `HARNESS-*` story, including this one
   — the lock permits RED to write the mechanism and GREEN to rewrite the frozen
   tests. The freeze is honoured by agents, so the *verification* of it is the
   only enforcement there is. That is the same argument `models.conf`'s
   `unenforced` exception rests on.
3. **There is no sanctioned way to do it right.** `git hash-object` is the
   answer, but it is folklore until it is written down: it worked here because
   one agent happened to think of it and record the hash *before* starting.
   Nothing prompts that, and after the fact it is unrecoverable.

**What this story is not.** It is not a claim that any shipped check is broken:
the RED-direction checks in the stories above are all valid, and CI's
`check-boundaries.sh` does not use this pattern at all — it reads the committed
diff, where the question does not arise. This is about the per-phase check an
orchestrator and a subagent perform *before* anything is committed.
## Acceptance criteria

The artifact is `scripts/frozen.sh`, a two-verb helper, plus the guidance that
makes it the convention. Every criterion is measured against a fixture
repository written by the test (`make_project_fixture`), never against a story
in `docs/backlog/`.

- **AC-1** — Given a file with uncommitted changes from a previous phase, when
  `bash scripts/frozen.sh snapshot <paths...>` runs and the file is **not**
  subsequently modified, then `bash scripts/frozen.sh verify` exits 0 and
  reports the path as unchanged. *This is the case `git diff --stat` gets
  wrong*: the diff is non-empty throughout and the verdict must still be
  "untouched".

- **AC-2** — Given the same snapshot, when the file **is** modified before
  `verify` runs, then `verify` exits non-zero, names that path, and prints both
  the recorded and the current hash. A verify that cannot distinguish these two
  cases is the check this story exists to replace.

- **AC-3** — Given `snapshot` was never run for the active story, when `verify`
  runs, then it exits non-zero with a message saying no snapshot exists — it
  does **not** exit 0. A missing snapshot is the after-the-fact case that is
  unrecoverable, and reporting "nothing changed" there is the false negative in
  its purest form.

- **AC-4** — Given a path that does not exist at snapshot time, when it is
  created before `verify`, then `verify` exits non-zero and names it as added.
  Freezing a file includes freezing its absence: a phase that *creates* a test
  file it was forbidden to touch is the same violation.

- **AC-5** — Given a snapshot taken for story A, when the active story is B,
  then `verify` refuses rather than comparing against A's record. The snapshot
  is stored per story under `.claude/state/`, which is machine-local and
  `.gitignore`d, and a stale record silently answering for the wrong story is
  how `gates.sh` stamping the active story has already bitten this repository.

- **AC-6** — Given any invocation, `scripts/frozen.sh` reads and writes nothing
  outside `.claude/state/`, and `bash .claude/tests/settings.test.sh` still
  passes with the new state file named in `.claude/state/README.md`'s table with
  a yes/no for whether `Write`/`Edit` may touch it. That suite checks the README
  against `settings.json` in both directions, so a new state file that is not in
  the table fails it.
## Contract

Written before RED. **RED may amend any block in place, with a reason**, and
GREEN builds what the amended block says.

### Files

| Path | `classify.sh` says | Who writes it |
|---|---|---|
| `scripts/frozen.sh` | `harness` | GREEN |
| `.claude/tests/frozen.test.sh` | `harness` | RED |
| `.claude/state/README.md` | `harness` | GREEN |
| `.claude/commands/advance-story.md` | `harness` | GREEN |
| `.claude/skills/tdd-cycle/SKILL.md` | `harness` | GREEN |

**Every path here classifies as `harness`, so the phase lock permits writing any
of them in every phase** — RED could write `frozen.sh`, GREEN could rewrite the
frozen test file, and nothing would stop either. The law still applies in full.
This story is *about* verifying that freeze, so a phase that crosses the line
here would be evidence against its own subject. Verify it with the artifact's
own predecessor: `git hash-object` before and after, per Correction 1 in
`HARNESS-014`.

Note for `scripts/plan.sh`: this table is what the `unenforced` exception now
reads (`HARNESS-014`), and all five rows are `harness`, so RED is planned for
`opus`. That is the exception working as intended rather than a departure.

### The command that runs these tests

    bash scripts/selftest.sh frozen

One new suite. `bash scripts/selftest.sh` with **no** argument runs every suite
and takes 10-25 minutes on this machine; two overlapping runs corrupt each
other. Do not use it as the inner loop. Note that `plan` is now ~19 min alone
(~40 under contention), so the full selftest has grown — budget for it once,
before the PR.

### The shape of the fix

Observable behaviour is the contract; the structure below is the intended shape
and GREEN may deviate if it can hold all six criteria.

1. **`bash scripts/frozen.sh snapshot <path>...`** — resolves the active story
   from `.claude/state/current-story.env` (as `phase.sh` does), and writes
   `.claude/state/frozen-<STORY_ID>.tsv`: one row per path, `<path><TAB><hash>`,
   where the hash is `git hash-object <path>` for a file that exists and the
   literal `ABSENT` for one that does not. Overwrites any previous snapshot for
   that story — a phase boundary is the moment to re-take it, not to accumulate.
2. **`bash scripts/frozen.sh verify`** — reads that file, recomputes, and exits
   0 only when every row still matches. Otherwise it prints one line per
   divergence naming the path, the recorded hash and the current one (or
   `ABSENT`/`ADDED`), and exits 1. No snapshot for the active story is exit 1
   with its own distinct message, never exit 0 (AC-3).
3. **No third verb**, no `--fix`, no auto-snapshot on `phase.sh set`. Wiring it
   into the phase transition is a real question and a separate one; doing it
   here would mean this story's own RED could not be verified by the tool it is
   building, which is a circularity worth avoiding once.

### The three verdict strings

Chosen mutually non-matching, for the reason `rules.md` gives:

    frozen: OK — <N> path(s) unchanged since the snapshot for <STORY_ID>
    frozen: CHANGED — <path>: recorded <hash>, now <hash>
    frozen: NO SNAPSHOT — nothing recorded for <STORY_ID>; take one before the phase starts

`OK` is not a substring of `NO SNAPSHOT` and neither contains `CHANGED`. Anchor
every needle (`^frozen: OK`) and **count** it; `assert_contains "OK"` would be
satisfied by a line saying the opposite, which is the failure `rules.md` records
four real cases of.

### Guidance, which is half the story

A helper nobody is told to use is folklore with a shebang. GREEN also edits:

- **`.claude/commands/advance-story.md`** — at RED→GREEN and GREEN→GATES, the
  orchestrator snapshots the frozen paths before dispatching and verifies after.
  State plainly that `git diff --stat` answers the wrong question here, and why:
  the previous phase's work is uncommitted, so a non-empty diff is the healthy
  case and an empty one means the frozen file was reverted.
- **`.claude/skills/tdd-cycle/SKILL.md`** — the same, one paragraph, where the
  RED→GREEN handoff is described.

Both are `harness` and both are GREEN's, not RED's.

### Callers of anything whose behaviour changes

None. `scripts/frozen.sh` is new; no existing script, hook or gate reads it, and
nothing in `project.conf` runs it. `.claude/state/README.md` gains a row, which
`.claude/tests/settings.test.sh` reads (AC-6) — that is the only existing suite
this story can break, and it is named in AC-6 for that reason.

### Oracle partition of the criteria

| Criteria | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2 | **Settled** — the mechanism is `git hash-object`, and `HARNESS-014` measured the real hash (`fc05ced…`) through a real RED→GREEN boundary | Read it out. AC-1 is the case `git diff` gets wrong: the fixture must have an uncommitted change present throughout, or the test proves nothing. |
| AC-3, AC-4, AC-5 | **Mechanical** — three refusals | Pin exactly, each with its own anchored needle, and assert the exit status as well as the text. A refusal that exits 0 is the defect. |
| AC-6 | **Mechanical** — an existing contract this story must not break | Run `.claude/tests/settings.test.sh` and pin that it passes; do not rewrite it. |

Nothing here is oracle-free. The place a blind assertion could hide is AC-3:
"no snapshot" is exactly the state a fresh fixture is in, so an AC-1 test that
forgot to snapshot would report `NO SNAPSHOT` and, with a floating needle, could
still look green. Assert the exit status.
## Deferred verifications

Two mutations. Both break a decision the suite claims to pin, and the second is
the one that matters, because it is the direction this whole story is about.

1. **`verify` made permissive.** With `frozen.sh`'s comparison inverted or its
   non-zero exit dropped so that a changed file still exits 0, **AC-2 must go
   red** (and AC-4 with it, if the same line governs both) while AC-1 stays
   green. If AC-2 stays green, `verify` is a check that always passes, which is
   strictly worse than the `git diff --stat` it replaces — that one at least
   failed loudly.

2. **`verify` made to answer from the working-tree diff instead of the
   snapshot.** With the hash comparison replaced by `git diff --quiet -- <path>`,
   **AC-1 must go red** — the uncommitted change from the previous phase makes
   the diff non-empty and the healthy case would be reported as a violation.
   AC-2 stays green, because a file changed *again* also has a non-empty diff.
   **This is the mutation that proves the story's premise.** A suite that stays
   green under it has tested that some check exists, not that this check answers
   the question `git diff` gets wrong, and every acceptance criterion above
   would be satisfiable by the very defect that prompted the story.

**Why RED cannot run either.** `scripts/frozen.sh` does not exist until GREEN
writes it; there is nothing to mutate, and it is not RED's to write under the
law even though the lock would permit it.

**Owner: GATES.**

Recipe — `mutate.sh` mutates the script under test directly, since it is not the
script doing the running:

    bash scripts/mutate.sh scripts/frozen.sh '<expression>' -- bash scripts/selftest.sh frozen

Paste the results here: for each, the expression, the red, and the restore.
Scope each mutation to the behaviour it names — a mutation that reds more than
it predicts measures blast radius rather than discrimination, which `HARNESS-014`
had to correct for twice (its mutations 2 and 3).
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
Planned by `bash scripts/plan.sh write HARNESS-015` from `.claude/harness/models.conf`.
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

Lock coverage: APPLIES — all 5 path(s) declared in the Contract's ### Files table are harness/docs/ignored, so RED stays on the stronger model.
<!-- plan.sh:generated:end -->

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

- **Wiring `snapshot` into `phase.sh set`.** The obvious next step, and
  deliberately not here: this story's own RED must be verifiable by the tool it
  builds, and a tool that only runs as a side effect of a phase transition
  cannot be used on the story that creates it. Candidate follow-up once the
  helper has been used by hand for a story or two.
- **`check-boundaries.sh`.** It reads the *committed* diff, where this question
  does not arise, and it is CI's. Nothing here touches it.
- **Retrofitting the existing stories.** `HARNESS-001`, `-012`, `-013` and
  `-014` all carry `git diff --stat … empty` in their RED direction, where it is
  **valid**. They are history and are left exactly as they stand.
- **Making the check mandatory**, in `check-boundaries.sh` or a hook. The
  failure this story addresses is an agent meeting an unsatisfiable instruction;
  the fix is an instruction that can be satisfied, not a new refusal.
- **`gates.sh`'s tree stamp.** It already hashes the tree it ran against and
  `check-boundaries.sh` already compares it. That is the same idea at the commit
  level and it works; this story is the per-phase, pre-commit case.
- **Any `src/**` file.** This is harness maintenance; no gate in `project.conf`
  reads `.claude/tests/**` or `scripts/**`, and `required_gates` stays `[]` for
  the same reason as `HARNESS-012` PO decision 2, `HARNESS-013` PO decision 3
  and `HARNESS-014` PO decision 4. What binds this story is
  `.github/workflows/gates.yml`'s `bash scripts/selftest.sh` step.
## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

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

### PO decisions made at PLANNED

**PO decision 1 — a script, not only a paragraph.** The defect is that the
correct check is folklore: it worked in `HARNESS-014` because one agent thought
of `git hash-object` and recorded the hash *before* starting, which after the
fact is unrecoverable. A paragraph telling agents to do that by hand is one more
instruction to mirror wrongly. A two-verb script is testable, which a convention
is not, and this harness's law wants the artifact to be something a failing test
can demand.

**PO decision 2 — the guidance ships with it, in the same story.** A helper
nobody is told to use changes nothing. `advance-story.md` and `tdd-cycle` are
`harness`, GREEN writes both, and the story is not done without them.

**PO decision 3 — no auto-snapshot on `phase.sh set`, deliberately.** Recorded
as declined rather than forgotten; the circularity argument is in
`## Out of scope`.

**PO decision 4 — `required_gates` stays `[]`.** Same answer and same reasoning
as the three harness stories before it; no gate reads `.claude/tests/**`, and
`required_gates` can only name a gate that exists.

**PO decision 5 — `depends_on: []`.** This story needs nothing from
`HARNESS-014` beyond its *evidence*. `HARNESS-014` is where the defect was
observed and where Correction 1 is recorded, but none of its code is a
dependency: `git hash-object` is git's, and the fixture helpers exist already.
The two touch no file in common.

### Confirmation of the mechanism, by the Lead PO at PLANNED

The claim in `## Context` was checked rather than assumed, and the check
narrowed it:

    $ grep -rn "diff --stat" .claude/commands/ .claude/agents/ .claude/skills/
    (no match for this pattern)

    $ grep -rn "diff --stat" docs/backlog/stories/*.md
    HARNESS-001:529, 698   HARNESS-012:349, 399, 429, 705
    HARNESS-013:156, 395   HARNESS-014 (Contract)

So the pattern is a **story convention**, not an instruction in any command,
agent or skill file — and every existing use is in the RED direction, where it
is valid. The invalid mirror was written by the Lead PO into a GREEN dispatch
brief during `HARNESS-014` and caught by the feature-developer. That is a
narrower and more accurate diagnosis than "the harness tells agents to do a
broken check", and it changes the fix: there is no wrong instruction to delete,
there is a missing one to add.

The blob hash that demonstrates the working check is in `HARNESS-014`'s
`## Notes`, cross-checked there against the `index bf15990..fc05ced` line of
RED's own diff.

### For the phases that follow

- **`gates.sh` stamps the *active* story.** Run `bash scripts/phase.sh show`
  before any `gates.sh` or `ci-local.sh` run started from a worktree.
- **Run one thing at a time on this machine.** Measured at `HARNESS-014`: the
  same `gates.sh --fast` is ~4x slower with another suite in flight (`unit`
  302 s vs 75 s, `harness` 90 s vs 38 s).
- **`selftest.sh plan` is now ~19 minutes alone.** The full `selftest.sh` has
  grown with it; budget one run before the PR rather than using it as a loop.
- **The phase lock will not enforce this story's RED→GREEN separation.** All
  five files are `harness`. Use `git hash-object` before and after each phase —
  which is, pointedly, the thing this story exists to make routine.
