---
id: HARNESS-015
title: Proving a frozen file was untouched needs a check that works when the previous phase is uncommitted
slug: proving-a-frozen-file-was-untouched-need
epic: 
type: fix
status: done
phase: DONE
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

- **AC-6** — Given any invocation, `scripts/frozen.sh` writes nothing outside
  `.claude/state/` — in particular it never modifies a path it was asked to
  freeze — and `bash .claude/tests/settings.test.sh` still
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
| `.claude/settings.json` | `harness` | GREEN (added by RED, see below) |
| `.claude/commands/complete-story.md` | `harness` | GREEN (added at GATES by the Lead PO: GREEN put the one-bullet mirror of the `advance-story.md` guidance in its ordered-steps list, which the brief allowed) |

*Amended by RED:* `.claude/settings.json` added. RED pinned the new README row
as `Hand-editable` **`no`** (argued under "The state README row" below), and
`settings.test.sh` fails a `no` row that has no `Write`/`Edit`/`MultiEdit` deny
rules, so AC-6 cannot pass without three lines in `settings.json`. That makes
it a file this story writes. If the orchestrator prefers `yes`, it is a
one-token change to `ROW_RE` in the test before GREEN starts, and this row goes.

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

An appearance and a disappearance are both `CHANGED` lines, with `ABSENT`
standing in for the hash on the missing side and a trailing word naming the
direction, so a single anchored count of `^frozen: CHANGED` counts every
divergence (pinned by the Lead PO at PLANNED, so AC-4's "names it as added"
has an exact form):

    frozen: CHANGED — <path>: recorded ABSENT, now <hash> (added)
    frozen: CHANGED — <path>: recorded <hash>, now ABSENT (deleted)

The dash is U+2014, as written. Exit codes: `verify` exits 0 on `OK` only, and
1 on `CHANGED` or `NO SNAPSHOT`. No active story (no `current-story.env`) is a
non-zero exit from either verb with a message naming the missing story;
its wording is RED's to pin in this block. `snapshot` with no paths is a
usage error, non-zero. Neither is an AC; RED may test them and GREEN builds
what RED pins.

**Pinned by RED (amendment, the parts the block above left open):**

- **No active story**, from either verb, exit **1**, this exact line:

      frozen: NO STORY — no active story (.claude/state/current-story.env is missing); start one with bash scripts/phase.sh set <ID> <PHASE>

  (`<ID>` and `<PHASE>` are literal text.) Chosen so it matches none of the
  three verdict needles: `^frozen: NO SNAPSHOT` does not match `frozen: NO STORY`.
  A snapshot refused this way writes no `frozen-*.tsv`.
- **Usage errors exit 2**: `snapshot` with no paths, no verb at all, and any
  verb other than `snapshot`/`verify` (the test uses `fix`, since "no third
  verb" is a decision). The usage text is not pinned. A usage error writes no
  `frozen-*.tsv`.
- **`snapshot` exits 0** on success, including for a path that does not exist
  (it records `ABSENT`). Its output is not pinned.
- **The snapshot file**: `.claude/state/frozen-<STORY_ID>.tsv`, one row per
  argument **in argument order**, `<path><TAB><hash>` with the path exactly as
  given, `ABSENT` for a missing path, nothing else in the file. A second
  snapshot for the same story replaces the file. Reason for pinning the format
  rather than leaving it to GREEN: "overwrites rather than accumulates" needs
  something to count, and the step-1 shape already said this; the behavioural
  half (a path only the first snapshot named is no longer checked, and the OK
  count is the second snapshot's) is pinned as well.
- **The `<path>` in a `CHANGED` line** is the path as recorded, i.e. as given
  to `snapshot`. `<N>` in the `OK` line is the number of rows.
- **Comparison is by content**: a file rewritten to identical bytes verifies OK.

### The state README row (pinned by RED, AC-6)

GREEN adds exactly one row to `.claude/state/README.md`'s table matching

    ^\| `frozen-\*\.tsv` \| `scripts/frozen\.sh` \|.*\| no \|$

i.e. first cell `` `frozen-*.tsv` `` (a glob, as the table already writes
`gate-logs/*.log` and `mutations/*.bak`, because there is one file per story),
second cell `` `scripts/frozen.sh` ``, `Read by` free, `Hand-editable` **no**.
GREEN therefore also adds to `.claude/settings.json`'s deny list, exactly:

    "Write(./.claude/state/frozen-*.tsv)",
    "Edit(./.claude/state/frozen-*.tsv)",
    "MultiEdit(./.claude/state/frozen-*.tsv)"

which is what `settings.test.sh` greps for (fixed-string) given that row.

**Why `no`.** The README's own test for `no` is "its contents are read as
evidence", and that is exactly what this file is: `verify` exits 0 when the
recorded hashes equal the current ones, so an agent in the phase being checked
that writes the current hashes into `frozen-<ID>.tsv` with `Write` or `Edit`
forges an OK the same way hand-writing `RESULT=pass` into `last-gate-run`
forges a gate run. The cost is the one the README names - three deny rules,
and the file cannot be hand-deleted with those tools - and it is small, since
the only legitimate way to change it is to re-run `snapshot`, which the rules
do not block (`scripts/frozen.sh` writes it from inside a script, as
`phase.sh` writes the denied `current-story.env`). **What `no` does not buy**:
an agent can still re-run `bash scripts/frozen.sh snapshot` mid-phase and
re-baseline. That hole is in the design, not the table, and wiring the
snapshot to the phase transition (Out of scope) is what would close it.

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

*Checked by RED:* `grep -rn frozen.sh scripts .claude --exclude-dir=worktrees`
finds only the new suite (exit 1 once it is excluded); the one other hit, under
`.claude/worktrees/`, is a stale copy of this story file. *Added by RED:*
`.claude/settings.json` gains three deny rules (see "The state README row");
it is read live by the Claude Code runtime and by `settings.test.sh`, and by
nothing else in the tree.

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

### Results — run by the Lead PO in GATES, 2026-09-24, before `gates.sh`

The script under test was `scripts/frozen.sh` at blob `4348808650b9b8624278fc98891fe71ca689086e`,
and it is at the same blob after all three runs. `.claude/state/mutations/`
holds only `log`, so no `.bak` was left behind.

**1. `verify` made permissive — RAN, caught.** The non-zero exit was dropped:

    $ bash scripts/mutate.sh scripts/frozen.sh 's/\[ "\$bad" -eq 0 \] || exit 1/[ "$bad" -eq 0 ] || true/' -- bash scripts/selftest.sh frozen
    === mutate: scripts/frozen.sh (1 line(s) changed by ...) ===
      AC-1: ... verifies as unchanged                         (no failures)
      AC-2: a frozen file modified after the snapshot fails verify, ...
        FAIL verify exits 1 when a frozen file changed after the snapshot
        FAIL verify prints no OK line when a frozen file changed
        FAIL verify exits 1 when one of two frozen paths changed
        FAIL no OK line when any frozen path changed
        FAIL verify exits 1 when both frozen paths changed
      AC-4: a path absent at snapshot time and created before verify is reported as added
        FAIL verify exits 1 when a frozen-absent path now exists
        FAIL no OK line when a frozen-absent path appeared
        FAIL [contract] verify exits 1 when a frozen file was deleted
        FAIL [contract] no OK line when a frozen file was deleted
    frozen: 71 passed, 9 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_frozen.sh.20260924T144058Z.66822.bak) ===

As predicted: AC-2 and AC-4 went red and AC-1 stayed green. RED measured 75/5
against its scratchpad implementation. Here the mutated script also falls
through to print the OK line, so the four "no OK line" assertions fire as well.
That is the same behaviour caught by more needles, not blast radius.

**2. `verify` answering from `git diff --quiet` — RAN, caught. This is the
premise.**

    $ bash scripts/mutate.sh scripts/frozen.sh 's/\[ "\$now" = "\$recorded" \] \&\& continue/git diff --quiet -- "$p" 2>\/dev\/null \&\& continue/' -- bash scripts/selftest.sh frozen
      AC-1: a file with an uncommitted change from the previous phase, untouched since the snapshot, verifies as unchanged
        FAIL verify exits 0 when the frozen file is untouched, despite its non-empty git diff
        FAIL verify prints exactly one OK line naming 1 path and the active story
        FAIL verify prints no CHANGED line for an untouched file
        FAIL verify of two untouched paths exits 0
        FAIL the OK line counts both paths
        FAIL no CHANGED line when neither frozen path moved
        FAIL a file rewritten back to identical content verifies as unchanged (hash, not mtime)
        FAIL and says OK for 1 path
      AC-2: ...
        FAIL the changed untracked test file is named with both hashes
        FAIL one CHANGED line per changed path
      AC-4: ...
        FAIL verify exits 1 when a frozen-absent path now exists
        FAIL the CHANGED line records ABSENT, the new hash, and (added)
        FAIL exactly one CHANGED line
        FAIL no OK line when a frozen-absent path appeared
        FAIL [contract] verify exits 1 when a frozen file was deleted
        FAIL [contract] the CHANGED line records the old hash, ABSENT, and (deleted)
        FAIL [contract] no OK line when a frozen file was deleted
      AC-5: ...
        FAIL control: back under story A, the same record verifies OK (exit 0)
        FAIL control: and the OK line names story A
    frozen: 61 passed, 19 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_frozen.sh.20260924T144416Z.72386.bak) ===

**Exactly RED's corrected prediction: 61 passed, 19 failed.** Every AC-1 case
went red. The first AC-2 case, a *tracked* file changed again, stayed green,
because its diff is non-empty either way. The wider red over untracked and
absent paths is `git diff`'s blindness to untracked files, as RED recorded, not
blast radius. The suite therefore answers the question `git diff` gets wrong,
not merely whether some check exists.

**3. A wrong value — RAN, caught by exactly one assertion.** This was added by
the Lead PO because the snapshot row and the verdict line are a small format.
The direction label of an addition was swapped:

    $ bash scripts/mutate.sh scripts/frozen.sh 's/suffix=" (added)"/suffix=" (deleted)"/' -- bash scripts/selftest.sh frozen
        FAIL the CHANGED line records ABSENT, the new hash, and (added)
    frozen: 79 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_frozen.sh.20260924T144719Z.78180.bak) ===

The prediction was a single assertion, and it was a single assertion. Every
other check still passes on a line that is now wrong in one word, so AC-4's
whole-line needle is what catches it; a floating `grep CHANGED` would not.
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

### Amendment 1 — AC-6: "reads and writes" became "writes"

- **Which AC:** AC-6.
- **What it said:** "Given any invocation, `scripts/frozen.sh` reads and writes
  nothing outside `.claude/state/`, and `bash .claude/tests/settings.test.sh`
  still passes …"
- **What it says now:** "Given any invocation, `scripts/frozen.sh` writes
  nothing outside `.claude/state/` — in particular it never modifies a path it
  was asked to freeze — and `bash .claude/tests/settings.test.sh` still passes …"
  The rest of the criterion is unchanged.
- **Who approved it:** the user (ryanczhang7), on 2026-09-23, choosing the
  "writes only" option the Lead PO put to them.
- **When:** at PLANNED→RED, before RED was dispatched and before any test
  existed, so no test was written against the old wording.
- **Why:** no correct implementation can meet the "reads" half. Both verbs have
  to hash the frozen paths themselves, which lie outside `.claude/state/` by
  definition, and `git hash-object` reads `.git/`. The criterion was therefore
  either untestable or false for every correct script. This was the Lead PO's
  own finding, not a subagent's claim.
- **Why it is here and not only in `## Notes`:** the story was committed to
  `main` while PLANNED, so `check-boundaries.sh` compares against that wording,
  and PO decision 6 in `## Notes` alone was invisible to it. Found by
  `check-boundaries.sh` on the first REVIEW commit (6338f1c).

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

- PLANNED→RED, `lead-po` (orchestrator session): `claude-opus-5-5`.
- RED, `test-developer`: dispatched with no `model` override, so the agent
  definition's `model: opus` applied. That alias resolves to `claude-opus-5-5`,
  the same model as the session. As planned. The verdict against the plan's
  claim that the contract is the only enforcement: the six freeze-record hashes
  were unchanged after RED (see Notes), so RED stayed inside its remit.

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

One suite, `.claude/tests/frozen.test.sh`, integration level: it runs the real
`scripts/frozen.sh` (copied into a `make_project_fixture` repo at fixture
creation) as a subprocess and asserts on its exit status and whole-line,
counted output. That is the level the contract lives at; there is no smaller
unit to test. One fixture, reset between cases with `git reset --hard` +
`git clean -fdx` (which also empties the fixture's `.claude/state/`, since the
fixture's `.gitignore` does not cover it). The active story is written by a
local `activate <ID>` helper in `phase.sh`'s format, because `set_phase`
hard-codes `T-1` and AC-5 needs two ids. `_lib.sh` is unchanged.

"The previous phase's uncommitted work" is `previous_phase_edit`: the tracked
`src/main.ts` modified and an untracked `tests/red.test.ts` created - the two
forms RED's work takes on a real GREEN.

| Block | What it pins | AC |
|---|---|---|
| script exists | `scripts/frozen.sh` is in the fixture (a one-line first failure in RED) | - |
| AC-1 (1 path) | uncommitted-modified file, snapshot, `git diff` asserted **non-empty at verify time**, verify exits 0, exactly one `OK … 1 path(s) … HX-1` line, zero `CHANGED`, zero `NO SNAPSHOT` | AC-1 |
| AC-1 (2 paths) | tracked-modified + untracked file, OK line counts `2`, exit 0 | AC-1 |
| AC-1 (same bytes) | file scribbled then rewritten to identical content verifies OK - hash, not mtime | AC-1 |
| AC-2 (1 path) | modified after snapshot: exit 1, exact `CHANGED — src/main.ts: recorded <old>, now <new>` with both hashes computed by the test via `git hash-object`, one `CHANGED`, zero `OK` | AC-2 |
| AC-2 (1 of 2) | only the untracked test file changed: exit 1, exact line for it, exactly one `CHANGED` (the untouched path is not named) | AC-2 |
| AC-2 (2 of 2) | both changed: exit 1, two `CHANGED` lines | AC-2 |
| AC-3 | no snapshot: exit 1, exact `NO SNAPSHOT … HX-3 …` line, zero `OK`, zero `CHANGED` | AC-3 |
| AC-4 (added) | absent at snapshot (asserted), created later: exit 1, exact `recorded ABSENT, now <hash> (added)`, one `CHANGED`, zero `OK` | AC-4 |
| AC-4 [contract] | absent and still absent: exit 0, OK 1 path | Contract |
| AC-4 [contract] | the mirror: deleted file, exit 1, exact `recorded <hash>, now ABSENT (deleted)`, zero `OK` | Contract |
| AC-5 | snapshot under `HX-A`, switch to `HX-B`: exit 1, `NO SNAPSHOT` naming **B** (count 1) and not A (count 0), zero `OK`, zero `CHANGED`; then the **executed control**: back under A, the same record verifies OK, exit 0 | AC-5 |
| snapshot file [contract] | `.claude/state/frozen-<ID>.tsv` exists; exact content `<path>\t<hash>`; a second snapshot replaces it (exact content, argument order, `ABSENT` row); behaviourally, a path only the first snapshot named is no longer checked and OK counts 2 | Contract |
| refusals [contract] | no active story: both verbs exit 1 with the exact `NO STORY` line, no `OK`, no tsv written; `snapshot` with no paths, no verb, and verb `fix`: exit 2, no tsv written, no `OK` | Contract |
| AC-6 controls | the `fingerprint` instrument moves for a write to a frozen file, a file under a gitignored dir, a new empty dir, `git add`, `git hash-object -w`; does **not** move for a same-bytes rewrite or a write under `.claude/state/` | AC-6 (instrument) |
| AC-6 (7 cases) | fingerprint identical before/after: snapshot (tracked-modified, untracked, absent paths), verify OK, verify CHANGED (does not restore or stage), verify NO SNAPSHOT, snapshot no paths, snapshot/verify with no story | AC-6 |
| AC-6 README | the real `.claude/state/README.md` has exactly one row matching `` ^\| `frozen-\*\.tsv` \| `scripts/frozen\.sh` \|.*\| no \|$ `` | AC-6 |
| AC-6 settings | `bash .claude/tests/settings.test.sh` (real repo, read-only) exits 0 | AC-6 |

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

Test Developer, RED, 2026-09-24. Model: dispatched as `test-developer`,
declared `model: opus`; no override was given in the dispatch.

### Command

    bash scripts/selftest.sh frozen

About 1m40s on this machine (fixture creation and ~200 git calls on Windows).
Never bare `selftest.sh` as the inner loop.

### Failure output (RED), and why it is the right failure

`bash -n .claude/tests/frozen.test.sh` is clean. The run, verbatim (excerpt; the
full run is 45 FAIL blocks of the same shape):

    === frozen ===

      the script under test exists in the fixture
        FAIL scripts/frozen.sh is present
             no such file in the fixture (copied from /c/Users/ryanc/Projects/first-roblox/scripts at fixture creation)

      AC-1: a file with an uncommitted change from the previous phase, untouched since the snapshot, verifies as unchanged
        FAIL snapshot of an uncommitted-modified file exits 0
             expected: 0
             actual:   127
        FAIL verify exits 0 when the frozen file is untouched, despite its non-empty git diff
             expected: 0
             actual:   127
        FAIL verify prints exactly one OK line naming 1 path and the active story
             expected: 1
             actual:   0
      ...
      AC-5: a snapshot taken for story A does not answer for story B
        FAIL snapshot for story A exits 0
             expected: 0
             actual:   127
        FAIL verify under story B, with only A's snapshot on disk, exits 1
             expected: 1
             actual:   127
        FAIL it prints NO SNAPSHOT naming story B
             expected: 1
             actual:   0
        FAIL control: back under story A, the same record verifies OK (exit 0)
             expected: 0
             actual:   127
      ...
      AC-6: the new state file is in the real .claude/state/README.md table, and settings.test.sh still passes
        FAIL README has exactly one row: | `frozen-*.tsv` | `scripts/frozen.sh` | ... | no |
             expected: 1
             actual:   0

    frozen: 35 passed, 45 failed

    1 of 1 harness suite(s) FAILED.

Right failure: every exit assertion reads `127` (bash: no such file) and every
verdict count reads `0`, because `scripts/frozen.sh` does not exist; the README
row is absent. Nothing fails on syntax, a helper or the fixture. Unlike a
module import, the suite does *run* every assertion in RED - a missing script
is a runtime 127, not a load failure - so the 35 passes below are real
executions, not skipped ones.

`bash scripts/gates.sh --fast` at the end of RED: **all green** - format,
lint, typecheck, unit, build, harness PASS, coverage UNCONFIGURED. Expected and
consistent with PO decision 4: no gate runs `frozen.test.sh` (the `harness`
gate ran `project-counters`, 40 assertions), so this suite is judged only by
CI's `selftest.sh` step, which runs it with the same command as above and no
instrumentation - there is no slower command for it to fail under. No timeout
exists in the suite to budget.

### The 35 that pass in RED, and what earns each

- **Preconditions** (4): `git diff` non-empty at verify time (x2), the two
  hashes differ, `tests/later.test.ts` absent at snapshot. Test integrity, not
  behaviour; they must pass.
- **"Zero of the other verdict"** counts (14): e.g. "no OK line when a frozen
  file changed". Green on arrival because a missing script prints nothing.
  Each is paired with an exit-status assertion and an exact-line count in the
  same case, which are red; they exist to catch an implementation that prints
  two contradictory verdicts, and they are earned by the scratch runs below
  (under the `git diff` mutation, 3 of them go red).
- **"No tsv written"** (2): same reasoning; paired with exit assertions.
- **AC-6 fingerprint controls** (7): these are the negative controls for the
  instrument and they ran for real in RED - see the table.
- **AC-6 untouched** (7): green on arrival *because nothing ran*. A missing
  script writes nothing. They are earned only by the controls proving the
  fingerprint would have moved; GREEN must re-read them against the shipped
  script, where they mean something.
- **`settings.test.sh` exits 0** (1): green on arrival, a regression guard. It
  is earned in conjunction with the README-row assertion: probed in a scratch
  copy of the tree (below), a `no` row without the deny rules makes it exit 1.

### Files touched

- `.claude/tests/frozen.test.sh` - new.
- `docs/backlog/stories/HARNESS-015.md` - `## Contract` (amended: Files table,
  pinned edge cases, the README row; Callers checked), `## Test plan`, this
  section.
- Nothing else. Re-hashed at the end of RED, identical to the freeze record:
  `scripts/frozen.sh` ABSENT, `README.md` 6d5bbf9…, `advance-story.md` 8a200bc…,
  `SKILL.md` 3aac04d…, `settings.test.sh` 915b546…, `_lib.sh` f6a8caa…. No
  `_lib.sh` helper was needed; `activate`, `fz`, `count_line`, `count_re`,
  `fingerprint` and `fp_moves` are local to the suite.

### The interface the tests pin (fact, not suggestion)

Run as `cd <repo> && bash scripts/frozen.sh <verb> [args]`, stdout and stderr
merged by the test (so either stream is fine for any line). U+2014 dashes.

| Invocation | Exit | Output line(s), matched whole-line and counted |
|---|---|---|
| `snapshot <path>...`, story active | 0 | not pinned |
| `verify`, all rows match | 0 | exactly one `frozen: OK — <N> path(s) unchanged since the snapshot for <ID>` |
| `verify`, a row differs | 1 | one `frozen: CHANGED — <path>: recorded <old>, now <new>` per differing row, and no OK line |
| … recorded absent, now present | 1 | `frozen: CHANGED — <path>: recorded ABSENT, now <hash> (added)` |
| … recorded present, now absent | 1 | `frozen: CHANGED — <path>: recorded <hash>, now ABSENT (deleted)` |
| `verify`, no `frozen-<ID>.tsv` for the active id | 1 | `frozen: NO SNAPSHOT — nothing recorded for <ID>; take one before the phase starts`, no OK, no CHANGED |
| either verb, no `current-story.env` | 1 | `frozen: NO STORY — no active story (.claude/state/current-story.env is missing); start one with bash scripts/phase.sh set <ID> <PHASE>` (literal `<ID>`/`<PHASE>`), no tsv written |
| `snapshot` (no paths), no verb, any other verb | 2 | not pinned; no tsv written |

- The active id is `STORY_ID=` from `.claude/state/current-story.env`; the
  test writes it in `phase.sh`'s format (a leading `#` comment line, then
  `STORY_ID=`, `STORY_SLUG=`, `STORY_TYPE=`, `PHASE=`, `BRANCH=`, `UPDATED=`).
- Snapshot file: `.claude/state/frozen-<ID>.tsv`, exact content
  `<path>\t<hash>` per argument in order, `ABSENT` for a missing path, path as
  given, hash = `git hash-object <path>` run in the repo. Replaced, not
  appended, by a second snapshot.
- Paths passed by the tests are always clean repo-relative (`src/main.ts`,
  `tests/red.test.ts`, `tests/later.test.ts`), run from the repo root.
- `.claude/state/README.md`: one row matching
  `` ^\| `frozen-\*\.tsv` \| `scripts/frozen\.sh` \|.*\| no \|$ ``, and
  `.claude/settings.json` gains `Write(`, `Edit(`, `MultiEdit(./.claude/state/frozen-*.tsv)`
  so that `settings.test.sh` still exits 0. Why `no` is argued in the Contract.
- AC-6: nothing outside `.claude/state/` may change - no file content, no new
  file or directory (including under ignored dirs), no staging, no new git
  object (so `git hash-object` **without** `-w`), HEAD unchanged.

**Not constrained** (GREEN's choice): `snapshot`'s output; the usage text;
whether verify also prints lines for unchanged rows (only the verdict lines
are counted, so an extra `frozen: OK`/`CHANGED`-prefixed line would break the
counts - anything else is free); stdout vs stderr; how `ROOT` is found
(`dirname BASH_SOURCE`/.. as `phase.sh` does is what the fixture supports);
running from a subdirectory; absolute or `./`-prefixed paths; paths with
spaces; duplicate paths; an empty or malformed tsv; a `current-story.env`
with an empty `STORY_ID`; transient temp files (a `mktemp` removed before
exit is invisible to the fingerprint - AC-6 as tested is "leaves nothing").

### Negative controls - expected and measured

In RED the fixture has no `frozen.sh`, so the first two rows below ran for real
now; the rest were measured by running this suite against a **scratch
candidate** `frozen.sh` in a copy of the tree under the session scratchpad
(never in the repo). They are claims about the shipped script until GREEN
reruns them.

| Control | Expected | Measured | Where |
|---|---|---|---|
| fingerprint on 5 forbidden writes (frozen file, ignored `dist/leak`, empty dir, `git add`, `hash-object -w`) | moves (5/5) | moves 5/5 | RED, real |
| fingerprint on same-bytes rewrite, write under `.claude/state/` | still (2/2) | still 2/2 | RED, real |
| AC-5: A's record consulted under A | exit 0, `OK — 1 path(s) … HX-A` | exit 0, count 1 | candidate |
| AC-5: same record under B (id ignored would say OK) | exit 1, NO SNAPSHOT for HX-B | exit 1, count 1 | candidate |
| README row absent / Written-by cell misspelt | row count 0, suite red | 0 and 0; `frozen: 78 passed, 2 failed` for the misspelling (row + settings) | candidate |
| `no` row present, no deny rules | `settings.test.sh` exits 1 | exit 1, `frozen-*.tsv: not hand-editable, but settings.json has no "Write(./.claude/state/frozen-*.tsv)"` (and Edit, MultiEdit); `frozen: 79 passed, 1 failed` | candidate |
| row + the three rules | all green | `frozen: 80 passed, 0 failed` | candidate |

### Deferred verifications - declined, with predictions

Both mutations need `scripts/frozen.sh`, which RED does not write. **I
declined both; they are GATES'.** What I did instead, and what it is *not*: I
applied each to the scratch candidate above and ran this suite. That is
evidence the suite discriminates against *a* implementation, not against the
shipped one.

1. **`verify` made permissive** (candidate: `[ "$bad" -eq 0 ] || exit 1` →
   `exit 0`). Predicted and measured on the candidate: **AC-1 green; AC-2 red**
   on all three exit assertions (1-of-1, 1-of-2, 2-of-2); **AC-4 red** on
   `verify exits 1 when a frozen-absent path now exists` and on the `(deleted)`
   exit; everything else green - `frozen: 75 passed, 5 failed`. The CHANGED
   line counts stay green because the candidate still printed them; the
   "zero OK" counts stay green because the candidate exits before printing OK.
   If GREEN's permissive expression lets the OK line print too, the zero-OK
   counts go red as well - more red, same verdict.
2. **`verify` answering from `git diff --quiet -- <path>`** (candidate: the
   comparison replaced by `! git -C "$ROOT" diff --quiet -- "$p"`). Predicted
   and measured: **AC-1 red** (all eight AC-1 assertions, including the 2-path
   and same-bytes cases); **the first AC-2 case stays green**, exactly as the
   story predicts (`src/main.ts` is tracked, so a re-modified file still has a
   diff). **But not all of AC-2 stays green**, and the story's prediction is
   too broad there: the 1-of-2 and 2-of-2 cases change `tests/red.test.ts`,
   which is *untracked*, and `git diff` cannot see untracked files - so the
   mutant misses it (2 assertions red). Likewise AC-4 `(added)` (4 red) and
   `(deleted)` (3 red), and the AC-5 control (2 red, because `src/main.ts`
   has a diff). Total `frozen: 61 passed, 19 failed`. That is the premise
   proved twice over: `git diff` is wrong about uncommitted-modified files
   *and* blind to untracked ones, which is what a new RED test file is.
   GATES should expect this wider red, not treat it as blast radius.

### Discovered, for GREEN

- `settings.json` is now in scope (three deny lines), because the row is `no`.
  It is read live by the runtime; adding deny rules only restricts. If the
  orchestrator rules `yes` instead, change `| no |` to `| yes |` in `ROW_RE`
  (RED's edit) and drop the settings work.
- This machine has `core.autocrlf` on; the fixture prints `LF will be replaced
  by CRLF` from `git diff`/`status` (silenced in the suite). `git hash-object`
  applies the same clean filter in the test and in the script, so the hashes
  agree; do not compute hashes any other way (e.g. `sha1sum` of a blob
  header) or they will diverge on CRLF files.
- The scratch candidate that passes all 80 is ~45 lines of bash; the Contract's
  intended shape is sufficient.

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

    run:    2026-09-24T17:23:09Z
    commit: e44fba1 (working tree had uncommitted changes)
    tree:   4b6c2608ca462d60cd6e4c9f07f7c343202e8932
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 79)
    PASS         lint (0s, observed 79, floor 1)
    PASS         typecheck (4s, observed 16)
    PASS         unit (47s, observed 355, floor 355)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 47816)
    PASS         harness (39s, observed 40)
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

**PO decision 6 — AC-6 changed at PLANNED, with the user, before RED.** It
said the script "reads and writes nothing outside `.claude/state/`". No correct
implementation can meet that: both verbs have to hash the frozen paths
themselves, and git reads `.git/` to do it. On 2026-09-23 the user chose
"writes only", and the criterion now says it writes nothing outside
`.claude/state/` and never modifies a path it was asked to freeze. The story had
not left PLANNED, so this is not an `## Amendments` entry.

**PO decision 7 — AC-4's verdict line pinned in the Contract.** "Names it as
added" had no exact form, and the Contract's step 2 said only "(or
`ABSENT`/`ADDED`)". It is now a `CHANGED` line with `ABSENT` on the recorded
side and a trailing `(added)`, plus the mirror `(deleted)` case, so that one
anchored count covers every divergence. Exit codes for the edge cases are
pinned there too.

**PO decision 8 — no epic to check against.** `epic:` is empty. Like the
harness stories before it, this is maintenance with no parent done-when, so
there is no epic-level gap to close.

### Freeze record taken by the Lead PO at PLANNED→RED

The lock does not enforce this story's split (every path is `harness`), so the
files RED must not touch were hashed before dispatch, on the story branch:

    scripts/frozen.sh                    ABSENT
    .claude/state/README.md              6d5bbf93676aecfbd4ef9973ea5ed1e0cbbfc83e
    .claude/commands/advance-story.md    8a200bc95948736ddd71fe556c9b2573993d1d3d
    .claude/skills/tdd-cycle/SKILL.md    3aac04dacd33358e8a6ec3a88df824533a5a25f2
    .claude/tests/settings.test.sh       915b54691ae4b97f8b9d3994671a36d8c72ab73b
    .claude/tests/_lib.sh                f6a8caaff667ae509c0ec063ad0e6ca82cba65ba

These are re-checked at the end of RED. `_lib.sh` is on the list because RED
may want a helper there, and a change to it would affect every suite. If RED
needs one, it says so in the handoff rather than adding it quietly.

### End of RED: the orchestrator's own verification

**The freeze held.** Re-hashed after the test-developer returned: all six
entries above are identical, and `scripts/frozen.sh` is still `ABSENT`.
`git status --short` shows only the story file and the new
`.claude/tests/frozen.test.sh`. `bash -n` on the suite is clean.

**The suite fails, and for the right reason.** I ran it myself, separately from
the agent's run:

    $ bash scripts/selftest.sh frozen
        FAIL scripts/frozen.sh is present
             no such file in the fixture (copied from .../scripts at fixture creation)
        FAIL verify exits 0 when the frozen file is untouched, despite its non-empty git diff
             expected: 0
             actual:   127
        ...
        FAIL README has exactly one row: | `frozen-*.tsv` | `scripts/frozen.sh` | ... | no |
    frozen: 35 passed, 45 failed
    1 of 1 harness suite(s) FAILED.

Every red is exit 127 or a zero count of a verdict line, both caused by the
missing script, plus the missing README row. None is a harness or syntax
error. The script is missing at run time, not at load, so every assertion
executed. The 35 that pass fall into four groups:
- preconditions and executed controls (the fingerprint controls, and the AC-1
  non-empty-diff precondition);
- "zero of the other verdict" counts, each paired with a red exit assertion;
- the `settings.test.sh` guard;
- seven AC-6 `expect_untouched` cases. These are green on arrival because a
  missing script writes nothing. The fingerprint controls show the instrument
  can move; GREEN must re-read these seven against the real script.

**The tests are admissible.** `bash scripts/gates.sh --fast` exits 0 with every
required gate PASS (unit 355, harness 40, build, lint, typecheck). This is
expected, not a false green: no project gate reads `.claude/tests/**`
(PO decision 4), so these tests are judged only by CI's `selftest.sh` step.

**PO decision 9 — the new state file is `Hand-editable: no`, as RED pinned it.**
`verify` reads `frozen-<ID>.tsv` as evidence of what a phase did. Hand-writing
current hashes into it forges an OK, the same forgery a hand-written
`RESULT=pass` in `last-gate-run` would be. So GREEN also writes the three
`Write`/`Edit`/`MultiEdit(./.claude/state/frozen-*.tsv)` deny rules into
`.claude/settings.json`, which RED added to the Files table.

I checked that `settings.test.sh` can carry a glob row before accepting this.
Both its directions compare the rule string literally against the README's
first cell (lines 96 and 115–120). A `frozen-*.tsv` row with rules spelled
`Write(./.claude/state/frozen-*.tsv)` therefore satisfies both directions, and
this is not a design trap for GREEN.

Known limit, recorded by RED: `no` does not stop an agent re-running `snapshot`
mid-phase to reset the baseline. Only the auto-snapshot declined in PO
decision 3 would close that.

**Correction to `## Deferred verifications` mutation 2, taken from RED.** RED
reports that "AC-2 stays green" is too broad. `git diff --quiet` cannot see an
untracked file, and a new RED test file is untracked. So under mutation 2 the
AC-2 cases on the untracked `tests/red.test.ts`, AC-4 and AC-5's control also
go red. Only the first AC-2 case (a tracked file) is predicted to stay green.
RED measured 61 passed / 19 failed against its own scratchpad implementation.
GATES reads the wider red as the prediction, not as blast radius, and confirms
the count against the shipped script.

### End of GREEN: the orchestrator's own verification

**The freeze held.** Hashed at RED→GREEN, before dispatch, and again after:

    .claude/tests/frozen.test.sh    26e2ba901a7cc4e39e6ab8223a389716ca852028  (both)
    .claude/tests/_lib.sh           f6a8caaff667ae509c0ec063ad0e6ca82cba65ba  (both)
    .claude/tests/settings.test.sh  915b54691ae4b97f8b9d3994671a36d8c72ab73b  (both)

**The suites pass on my own runs:**
`frozen: 80 passed, 0 failed` and `settings: 20 passed, 0 failed`.
`bash scripts/gates.sh --fast` exits 0 with every required gate PASS
(unit 355, harness 40).

**RED's control values, confirmed by the feature-developer against the shipped
script:** the full count is 80/0, as expected. The seven AC-6 `expect_untouched`
cases now exercise the real script. With `frozen.sh` mutated to append to a file
outside `.claude/state/`, exactly those seven went red (`73 passed, 7 failed`),
and `mutate.sh` verified the restore. The AC-5 control verifies OK under A and
NO SNAPSHOT under B.

**Unconstrained choices GREEN made, recorded rather than pinned:**
- an empty `STORY_ID=` prints a `NO STORY` line with different wording, exit 1;
- `verify` with arguments is a usage error, exit 2;
- paths are stored and re-hashed as given, relative to the directory the
  script is run from. Run both verbs from the repo root. A snapshot taken in a
  subdirectory and verified from the root reports every path `(deleted)`. That
  is loud, not a false OK.

**PO decision 10 — the commands' `allowed-tools` lists are left as they are.**
The feature-developer points out that neither `advance-story.md` nor
`complete-story.md` lists `Bash(bash scripts/frozen.sh:*)`. The same is already
true of `mutate.sh` and `plan.sh`, which those commands also instruct. The list
is evidently not meant to be complete, and no suite checks it. Aligning it is a
separate change across every harness script, not this story's.

### GATES: the freeze, checked by the tool this story ships

Right after `phase.sh set HARNESS-015 GATES`, and before the deferred
mutations, the Lead PO snapshotted the frozen tests. It verified them after the
full `gates.sh` run:

    $ bash scripts/frozen.sh snapshot .claude/tests/frozen.test.sh .claude/tests/_lib.sh .claude/tests/settings.test.sh
    frozen: snapshot of 3 path(s) recorded for HARNESS-015 in .claude/state/frozen-HARNESS-015.tsv
    ...
    $ bash scripts/frozen.sh verify
    frozen: OK — 3 path(s) unchanged since the snapshot for HARNESS-015

`frozen.test.sh` is untracked throughout this phase, so `git diff --stat` could
not have seen it at all. This is the case the story exists for, met on its own
first use.

### GATES: the binding check, and a stale gate record from another suite

**Full `bash scripts/selftest.sh`, the CI step that binds this story: 20 of 20
suites passed, exit 0.** It includes `frozen: 80 passed, 0 failed`,
`settings: 20 passed, 0 failed` and `plan: 84 passed, 0 failed`. It took about
two hours on this machine, run alone.

**The full `gates.sh` was run twice.** A full `selftest.sh` run overwrote the
real `.claude/state/last-gate-run` with `RESULT=fail` / `FULL=no` at 16:22Z. The
cause is `harness-gate.test.sh:404`, which runs `gates.sh --fast --gate harness`
against the real repository with a probe planted. The recorded
`## Gate results` were not affected, because partial runs are not recorded, but
the Stop hook then reported the last run as partial. The full `gates.sh` was
re-run once the selftest had finished, and it passed (6 ran, 0 failed). That
second run is what `## Gate results` now holds. The suite's side effect predates
this story and is out of its scope; it has been filed as a separate follow-up.

**The freeze was verified again after the second run:**
`frozen: OK — 3 path(s) unchanged since the snapshot for HARNESS-015`.

### DONE

Merged as `f6c1cbb` via PR #28 on 2026-09-24T17:55:32Z. Both CI jobs passed on
the first run, against head `56afdf0`:

- `gates` (run 36034320378) passed in **2m33s** against
  `timeout-minutes: 45`. The Harness self-test step, which is the one that binds
  this story, took **1m49s**; Run gates took 21s.
- `boundaries` (run 36034320546) passed in 8s.

Every duration is far from its limit. No gate was pending CI. The self-test
takes about 1m49s on CI against about two hours locally, which confirms that
this machine's contention, not the suites, is the local cost.

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
