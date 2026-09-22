---
id: HARNESS-013
title: mutate.sh's early-exit paths leak the backup they print about
slug: mutate-sh-s-early-exit-paths-leak-the-ba
epic: 
type: fix
status: todo
phase: PLANNED
branch: story/HARNESS-013-mutate-sh-s-early-exit-paths-leak-the-ba
depends_on: [HARNESS-012]   # its finish() trap and its piped test helpers are what this builds on
required_gates: []          # gate ids that are optional for the repo but binding for THIS story
---

## Context

`HARNESS-012` fixed the case where `scripts/mutate.sh` left a `.bak`/`.new` pair
under `.claude/state/mutations/` with no `log` entry after a restore that
**succeeded**. It did so by moving the restore, the single log append and the
conditional cleanup into a `finish()` EXIT trap installed before the first byte
reaches either stream.

It did not fix the two paths that exit **above** that trap, and that was scope
rather than oversight: HARNESS-012's Contract pinned the trap's installation
point by line number, "immediately after the changed-nothing check". Both paths
above it still print first and clean up afterwards:

| Path | `mutate.sh` today | Order |
|---|---|---|
| `exit 2` — `sed` rejected the expression | lines 116-121 | 2 `printf`s (one of which *reads* `$NEW.err`) → `rm -f "$NEW" "$NEW.err" "$BAK"` → `exit 2` |
| `exit 3` — the expression changed nothing | lines 126-134 | 4 `printf`s → log append → `rm -f "$NEW" "$BAK"` → `exit 3` |

A reader that closes the pipe before **any** byte gets through reproduces
exactly the defect HARNESS-012 removed: SIGPIPE kills the shell at the first
`printf`, and the backup, the working copy and (on the `exit 2` path) the `.err`
file are all left behind with no log line.

**What this is about, stated honestly.** `bash scripts/mutate.sh ... 2>&1 |
head -30` — the idiom that produced HARNESS-012's bug — never trips this. Both
blocks print only two to four short lines, which fit the pipe buffer, so nothing
blocks and the cleanup runs. It needs `head -0`, or a reader that exits without
reading at all. So this story closes an invariant; it is not a failure agents are
hitting today.

The invariant is the one `.claude/harness/rules.md` and
`.claude/state/README.md:62` both state: *a `.bak` left behind under
`mutations/` means a restore failed and `mutate.sh` exited 90 saying so*. Today
that sentence has two remaining counter-examples, and a signal with a known
exception is a signal people learn to discount — which is the reasoning
HARNESS-012's own `## Context` already sets out. The residual is recorded in
HARNESS-012's `## Notes`, under "GREEN, by the Feature Developer", as "One
residual, reported rather than fixed, and reproducible"; the `exit 2` half was
found while planning this story and is new.

**The gate that would fail if this story's artifact broke.** None, and that is a
fact about this repository rather than an omission to fix here. Every gate in
`project.conf` judges the Luau project; the one called `harness` runs
`.claude/tests/project-counters.test.sh` and nothing else, which is
`HARNESS-008`'s derived answer — it is the one suite a *product* story can
break. `bash scripts/classify.sh` reports both files this story touches as
`harness`, not `source`, so `gates.sh`'s `covers` check does not bite either.
What binds this story is `.github/workflows/gates.yml`'s
`run: bash scripts/selftest.sh` step, which runs every suite in
`.claude/tests/`. See PO decision 3 for why `required_gates` stays `[]`.

## Acceptance criteria

All criteria are measured in a `make_project_fixture` repository against
`src/main.ts` holding `export const clamp = (v) => Math.min(90, v)`, with
`.claude/state/mutations/` removed before each run, and invoked as

    bash scripts/mutate.sh src/main.ts '<EXPR>' -- true 2>&1 | <READER>

`2>&1` is deliberate: it is the shape an agent actually writes, and after
HARNESS-012 moved every banner to stderr it is what keeps these cases exercising
SIGPIPE at all. Two provocations and four readers are used throughout:

- **P-N** — `s/NOT_IN_THE_FILE/x/`, the "expression changed nothing" path (exit 3).
- **P-S** — `s/90/-90` (unterminated), the "sed rejected the expression" path (exit 2).
- Readers: `head -0`, `true`, `head -1`, `head -4`. The first two close the pipe
  before reading anything; the last two are the widths that already pass, and
  they are swept rather than dropped so that a fix cannot hold at one end by
  breaking the other.

- **AC-1** — Given **P-N** piped into any of the four readers, when `mutate.sh`
  has returned, then the only entry under `.claude/state/mutations/` is `log`:
  no `.bak`, no `.new`, nothing else.
  *Fails today at `head -0` and at `true`* — a `.bak`/`.new` pair is left.
  Measured below.

- **AC-2** — Same runs: `.claude/state/mutations/log` gains **exactly one** line
  for that run, and that line names the file (`src/main.ts`), the expression
  (`s/NOT_IN_THE_FILE/x/`) and the outcome `CHANGED NOTHING - command not run`.
  Exactly one, **counted** with an anchored needle — not "at least one", and
  never `assert_contains` on the log's text, which is satisfied by two lines as
  happily as by one.
  *Fails today at `head -0` and at `true`*: the log file does not exist at all.

- **AC-3** — Given **P-S** piped into any of the four readers, when `mutate.sh`
  has returned, then `.claude/state/mutations/` contains nothing but
  (optionally) `log`: no `.bak`, no `.new`, and no `.new.err`.
  *Fails today at `head -0` and at `true`*: all three are left. The `.err` file
  is why this assertion enumerates the directory rather than reusing
  HARNESS-012's `leftovers()` helper, whose pattern is `\.(bak|new)$` and would
  not see it.

- **AC-4** — Same runs, and the unpiped one: the log gains **zero** lines naming
  the expression `s/90/-90`. The `sed`-rejected path records nothing today and
  records nothing after this story. *Passes today.*
  *Control, because this is an absence assertion and an absence is equally what
  a run that never happened produces:* the same case also asserts that a **P-N**
  run in the same directory does produce its one line, so "zero" cannot be
  satisfied by a missing or unwritable log. And the needle must be anchored at
  **both** ends — `s/90/-90` is a proper prefix of the ordinary expression
  `s/90/-90/`, so a floating match would count the ordinary path's log line and
  report a failure that is not there. See the Contract.

- **AC-5** — Given **P-S** run unpiped, when it returns, then it still exits
  **2**, and stderr still carries `mutate: sed rejected the expression:` **and**
  the indented text of `sed`'s own complaint. *Passes today.*
  This is the **negative control on the fix's shape**: the printing on this path
  reads `$NEW.err`, which the reorder deletes. A fix that moves the `rm` above
  the `printf`s without first capturing that text satisfies AC-3 completely and
  silently drops the only line that says *why* the expression was refused. If
  AC-5 cannot be made to fail by that mutation, the suite is not discriminating
  (see `## Deferred verifications`).

- **AC-6** — Given **P-N** run unpiped, when it returns, then it still exits
  **3**, stderr still carries all four lines of the "changed nothing"
  explanation (beginning `mutate: the expression changed nothing in`),
  `src/main.ts` is byte-identical, and the command never ran.
  *Passes today.* The contract the reorder must not break.

- **AC-7** — Given the **ordinary mutating** expression `s/90/-90/` piped into
  any of the four readers, when `mutate.sh` has returned, then no `.bak`/`.new`
  remains, exactly one anchored log line names the run, and `src/main.ts` is
  byte-identical. *Passes today at every reader, including `head -0` and `true`*
  — this is HARNESS-012's fix, and it is written down here so that a story
  reordering the code above the trap cannot quietly undo it.

## Contract

Written before RED. **RED may amend any block in place, with a reason**, and
GREEN builds what the amended block says.

### Files

| Path | `classify.sh` says | Who writes it |
|---|---|---|
| `scripts/mutate.sh` | `harness` | GREEN |
| `.claude/tests/mutate.test.sh` | `harness` | RED |

**Both classify as `harness`, so the phase lock permits writing either of them in
every phase.** Nothing will stop RED editing `scripts/mutate.sh`, or GREEN
editing the frozen test file. The law still applies in full (`CLAUDE.md` laws 1
and 2); here it is honoured by the agents rather than enforced by the hook. Say
so in the handoff, and show `git diff --stat scripts/mutate.sh` empty at the end
of RED. HARNESS-012 was briefed this way and both agents honoured it.

### The command that runs these tests

    bash scripts/selftest.sh mutate

One suite. It was 146 s on this machine after HARNESS-012 and each new
`mutate.sh` process costs roughly 9 s here, so budget accordingly.
`bash scripts/selftest.sh` with **no** argument runs all 19 suites, takes 10-25
minutes on this machine, and two overlapping runs corrupt each other — do not
use it as the inner loop.

### The shape of the fix

Observable behaviour is the contract; the structure below is the intended shape
and GREEN may deviate if it can hold all seven criteria.

1. **The `exit 3` block** (`scripts/mutate.sh:126-134`, the
   `if cmp -s "$BAK" "$NEW"; then` body) is reordered to: append the log line →
   `rm -f "$NEW" "$BAK"` → the four `printf`s → `exit 3`. Three lines moved;
   nothing else in the block changes, and the four messages keep their present
   wording and their present stream.

2. **The `exit 2` block** (`scripts/mutate.sh:116-121`, the
   `if ! sed -e "$EXPR" "$BAK" > "$NEW" 2>"$NEW.err"; then` body) is reordered
   the same way, with one extra step that is the whole trap of this story:
   **the contents of `$NEW.err` must be captured into a shell variable before
   the `rm`**, because the second `printf` renders that file. Intended order:
   read `$NEW.err` into a variable → `rm -f "$NEW" "$NEW.err" "$BAK"` → print
   the two messages, the second still indented by two spaces → `exit 2`.

3. **Nothing above the printing writes to either stream**, in both blocks. That
   ordering is the fix, not a style: if the block prints before it cleans up,
   and the stream it prints to is the closed one, it dies exactly where it dies
   today and the bug is reproduced inside its own fix. `2>&1` puts both streams
   down the same closed pipe, so moving a write to stderr does not by itself
   make it safe. This is the same sentence HARNESS-012's Contract carries, and
   for the same measured reason.

4. **The log vocabulary does not grow.** The `exit 3` path keeps its single
   `CHANGED NOTHING - command not run` line, verbatim. The `exit 2` path keeps
   writing nothing (AC-4, and PO decision 2).

5. **Exit statuses are unchanged**: 2 usage and rejected expression, 3
   changed-nothing, 90 unverified restore, otherwise the command's own. A run
   killed by SIGPIPE dies by signal and `mutate.sh` cannot choose its own
   status — that is the caller's problem and is out of scope.

6. **`finish()` and the trap's installation point are not touched.** See PO
   decision 1 for why the alternative shape lost.

### The test the story adds

New `describe` blocks in `.claude/tests/mutate.test.sh`. Three things about
their shape, because the existing helpers cannot express them:

- **`piped_run` hardcodes the expression `s/90/-90/`** and its reader is always
  `head -"$n"`. Both cases here need a different expression, and two of the four
  readers are not `head -N`. **Add a sibling helper rather than change
  `piped_run`'s signature**, so that HARNESS-012's 21 sweep assertions keep
  their exact invocation and this story cannot be blamed for moving them. The
  intended shape:

      piped_expr_run <READER> <EXPR> <command...>

  where `<READER>` is a command word list (`head -0`, `head -4`, `true`) and the
  helper runs `bash scripts/mutate.sh src/main.ts "<EXPR>" -- <command> 2>&1 |
  <READER>`, leaving what the reader let through in `PIPED_OUT` and
  `mutate.sh`'s own status in `PIPED_ST`.

- **Read `mutate.sh`'s status with `${PIPESTATUS[0]}`, in the same shell as the
  pipeline**, via the scratch-file trick `piped_run` already uses. The
  pipeline's `$?` is the *reader's*, and `head` and `true` both exit 0;
  `PIPESTATUS` evaluated outside a subshell that contains the pipeline reports
  the subshell. Either mistake hands back a clean 0 for a probe that never
  happened. Recorded as `PIPED_ST`, never asserted (out of scope).

- **Enumerating the mutations directory.** AC-1 and AC-3 assert on *everything*
  under `.claude/state/mutations/` except `log`, not on `\.(bak|new)$`:
  `ls "$MUTDIR" | grep -v '^log$'` must be empty. HARNESS-012's `leftovers()`
  helper cannot see the `.new.err` file, and an assertion that cannot see the
  file it is about is the failure mode `rules.md` calls "a needle that cannot
  fail".

Helpers available: `make_project_fixture`, `describe`, `assert_eq`,
`assert_contains`, `_ok`, `_bad`, `summary`, `set_phase` (`.claude/tests/_lib.sh`),
plus `mutate`, `sha`, `reset_src`, `count_lines`, `count_files`, `leftovers`,
`lines_in`, `piped_run`, `STAMP_RE`, `RUN_LINE`, `VERIFIED_LINE`
(`.claude/tests/mutate.test.sh`). No new dependency of any kind: bash, git and
coreutils only, which is the standing constraint on every suite in
`.claude/tests/`.

### The needles, and the one that will bite

Every log assertion is a **count** through `count_lines`, compared with
`assert_eq`. Two new needles, both anchored at both ends against the three
tab-separated leading fields every log line carries:

    NOTHING_LINE = ^<STAMP_RE>\tsrc/main\.ts\ts/NOT_IN_THE_FILE/x/\tCHANGED NOTHING - command not run$
    REJECTED_LINE = ^<STAMP_RE>\tsrc/main\.ts\ts/90/-90(\t.*)?$

**`REJECTED_LINE` is the hazard.** `s/90/-90` is a proper prefix of the ordinary
expression `s/90/-90/`, so an unanchored needle for AC-4 matches the *ordinary*
path's log line and reports a leak that does not exist. The trailing
`(\t.*)?$` is what makes the expression field terminate at a tab or at
end-of-line, and it is load-bearing: `rules.md`'s "an assertion's needle is part
of the assertion" is about exactly this. RED should prove the anchoring works by
running both expressions into the same log and checking the counts come out 1
and 0, not 1 and 1.

### Baseline measurements the story may read out

Measured by the Lead PO at PLANNED on this machine, 2026-09-22, in a
`make_project_fixture` repository, against `scripts/mutate.sh` as it stands on
`story/HARNESS-012-...` (i.e. **with** HARNESS-012's fix), with
`.claude/state/mutations/` removed before each run. `writer` is
`${PIPESTATUS[0]}`; 141 is 128+13, death by SIGPIPE.

    P-N  s/NOT_IN_THE_FILE/x/   -- true
      reader      writer   leftovers                 log lines
      head -0     141      .bak .new                 0
      head -1       3      —                         1
      head -2       3      —                         1
      head -4       3      —                         1
      true        141      .bak .new                 0
      unpiped       3      —                         1

    P-S  s/90/-90 (unterminated)   -- true
      reader      writer   leftovers
      head -0     141      .bak .new .new.err
      head -1       2      —
      true        141      .bak .new .new.err
      unpiped       2      —

    Contrast — the ordinary mutating path s/90/-90/ -- true, after HARNESS-012:
      head -0 / head -1 / head -4 / true   writer 141   leftovers —   log lines 1

Three readings of that table matter and all three are in the criteria:

- **The leftovers come from a run in which nothing was ever mutated.** The
  working file is untouched on both paths, so the leftover `.bak` is a pure
  false alarm — AC-1, AC-3.
- **`head -1` is enough to hide it.** Four short lines fit the pipe buffer, so
  the widths HARNESS-012 swept (1 through 30) all pass. That is why this story
  exists as a separate one and why its severity claim in `## Context` is what it
  is.
- **The ordinary path reports `writer=141` even when it is completely clean.**
  The trap does its file work and then dies at its own first write. The status
  through a pipe is not fixable from inside `mutate.sh` and is out of scope; it
  is recorded so nobody reads a 141 as evidence of a leak.

### Oracle partition of the criteria

| Criteria | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-3, AC-7 | **Settled** — the table above was measured; the readers and the expected today-values are given | Read them out. Do not re-derive which reader trips it, do not "calibrate" a width. Assert the post-condition at every listed reader. |
| AC-4, AC-5, AC-6 | **Mechanical** — an existing contract this story must not break | Pin exactly. AC-6 sits beside the existing `a mutation that mutates nothing proves nothing` block at `mutate.test.sh:123`; extend or sit beside it, do not rewrite it. |

Nothing here is oracle-free: there is no metric to invent. The two places a
blind assertion could hide are AC-2's and AC-4's counts, which is why both are
counts with two-end-anchored needles.

## Deferred verifications

Three mutations, because a suite that catches an omission can be blind to a
corruption — and the third here is a *corruption*, not a missing file.

1. **The `exit 3` reorder undone.** With the log append and `rm -f` moved back
   below the four `printf`s in GREEN's `exit 3` block, AC-1's and AC-2's
   assertions at `head -0` and at `true` **must** go red, and the `head -1` and
   `head -4` ones must stay green. If they all stay green, the readers in the
   sweep are not closing the pipe and the sweep is testing nothing.

2. **The `exit 2` reorder undone.** Same move in the `exit 2` block: AC-3's
   assertions at `head -0` and `true` must go red.

3. **The captured `$NEW.err` text thrown away.** With the variable holding
   `sed`'s complaint replaced by an empty string — the file is still deleted,
   the exit code is still 2, and the first message still prints — **AC-5's
   second assertion must go red and nothing else may move.** This is the one
   that matters: mutations 1 and 2 break a file operation and are caught by a
   file assertion, which is the easy direction. Mutation 3 leaves every file
   assertion green and corrupts only what the user is told, which is precisely
   the failure the reorder invites. If AC-5 does not catch it, the story has
   traded a leaked backup for a silent refusal.

**Why RED cannot run any of them.** There is nothing to un-reorder in RED: the
reordered code is what GREEN is about to write, and `scripts/mutate.sh` is not
RED's to edit under the law even though the lock would permit it.

**Owner: GATES.**

One workable recipe, written down because `mutate.sh` refuses to mutate itself
(`scripts/mutate.sh:100-102`) and the obvious invocation therefore exits 2 —
this is HARNESS-012's recipe and it worked there:

    cp scripts/mutate.sh scripts/__mutate_probe.sh
    bash scripts/__mutate_probe.sh scripts/mutate.sh \
      '<expression undoing one of the three>' \
      -- bash scripts/selftest.sh mutate
    rm -f scripts/__mutate_probe.sh

The *running* script is the copy and the *target* is the real one, which is what
the self-check permits; the copy lives under `scripts/` so its `ROOT` resolves
to the repository root. Delete the copy afterwards and confirm `git status` is
clean — a stray `scripts/__mutate_probe.sh` is a file CI would carry. GATES may
use any other recipe that restores the file and proves it.

Paste the results here: for each of the three, the expression, the red, and the
restore.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-013` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table. Only what lies BETWEEN these two markers is rewritten when
this command runs again; the rest of the section is yours and is preserved.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `fable` | the measured case. With a partitioned contract to work from, the brief carries the judgement and the weaker model writes sharper negative controls than the stronger one did without it |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |
<!-- plan.sh:generated:end -->

**No departure. RED runs on the planned `fable`, and the reason is a recorded
verdict rather than taste.**

`HARNESS-012` was the previous harness-only story and it *did* depart, running
RED on `opus` because the `unenforced` exception in `models.conf` failed to fire
for a story both of whose files are `harness`. That departure carried a success
condition written to come out either way, and it came out on the "no difference"
side in full: RED left `git diff --stat scripts/mutate.sh` empty although the
lock would have permitted the write, and its handoff named the control on the
fix's shape and declined it explicitly as GATES's. The verdict recorded in
`HARNESS-012`'s `## Model guidance` is the instruction for this story:

> the departure bought nothing observable, and the next harness-only story
> should take the `fable` row and save the cost.

This is the next harness-only story. It takes the `fable` row. The detector
defect that produced the departure is not worked around here; it is filed as
`HARNESS-014` and left there.

**Success condition, and it can come out either way.** RED on `fable` must end
with all three of:

1. `git status --short` naming `.claude/tests/mutate.test.sh` and this story
   file and nothing else, and `git diff --stat scripts/mutate.sh` **empty** —
   checked by the orchestrator against the tree, not reported by the agent.
2. A handoff whose control table names all three mutations in
   `## Deferred verifications`, and declines them explicitly as GATES's rather
   than claiming them.
3. `REJECTED_LINE` written with its trailing `(\t.*)?$` anchor and *demonstrated*
   to count 1 and 0 rather than 1 and 1 — the Contract's "The needles, and the
   one that will bite". This is the sharpest single thing to look at: the needle
   hazard is spelled out in the Contract, so a floating match here is a failure
   to read the brief, not a failure to invent.

If it delivers all three, `HARNESS-012`'s verdict is confirmed a second time and
the `fable` row should stand for harness stories generally. If RED edits
`scripts/mutate.sh`, hands GREEN a fix disguised as a test, or writes a floating
needle where the Contract asked for an anchored count, then the `unenforced`
exception's intent is confirmed *against the weaker model*, `HARNESS-012`'s
verdict should be reversed, and the right repair is the policy row in
`models.conf` — not an ad-hoc departure on the next story. Record the verdict
here when RED ends.

The oracle partition for RED is in `## Contract`, "Oracle partition of the
criteria" — carry it into the dispatch prompt **verbatim**; it is the half of the
brief that was measured to matter more than the model.

**Resolved:**

- **PLANNED** — `lead-po`, resolved `opus` (`claude-opus-5`). As planned; no
  override was passed, so the agent definition's own `model: opus` is what
  resolved it.

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

- **Anything about `mutate.sh`'s exit status through a pipe.** A shell killed by
  SIGPIPE cannot choose what `head` reports, and no change inside `mutate.sh`
  can make `mutate ... | head -0` exit non-zero. Same boundary HARNESS-012 drew,
  and for the same reason. `PIPED_ST` is recorded by the tests and never
  asserted.
- **Moving the trap above the changed-nothing check.** The other candidate shape
  for this fix. Ruled out in PO decision 1; `finish()` keeps its present
  preconditions and its present installation point, and no refactor of it is in
  scope.
- **Giving the `sed`-rejected path a log line.** Tempting, defensible, and new
  behaviour that no defect demands. AC-4 pins the absence so GREEN cannot drift
  into it. PO decision 2.
- **Redesigning any message.** The four-line "changed nothing" explanation, the
  `mutate: sed rejected the expression:` heading, the two-space indent on
  `sed`'s complaint, the banner text, the diff rendering, the `head -20` diff
  cap, the changed-line count: all unchanged, on the streams they already use.
  This story moves *when* things are printed relative to the file work, and
  nothing else.
- **The exit-code contract**: 2, 3, 90 and pass-through stay exactly as they are.
- **`mutate.sh:111`, the failed-backup path** (`cp "$FILE" "$BAK" || die`). Not
  measured, not in scope. A `cp` that fails there is a real fault, and a
  leftover from it means something — which is the opposite of this story's
  subject.
- **Adding a gate for `.claude/tests/**`.** Making `selftest.sh` a gate is a
  real question and this is not the story for it: it costs 10-25 minutes per
  `gates.sh` run here, two overlapping runs corrupt each other, and a story that
  adds a gate owes `## Gate probes`. This story adds no gate and changes no
  `evidence` line, so it has no `## Gate probes` section.
- **Changing `rules.md` or `.claude/state/README.md`.** Their sentence — a
  leftover `.bak` means a restore failed — is what the fix makes true again.
  Editing the docs to describe the bug would be the other repair, and the wrong
  one.
- **`mutations/` housekeeping**: no pruning, no age-based cleanup, no changes to
  the naming scheme.
- **`.claude/tests/plan.test.sh` and `scripts/plan.sh`.** A different residual of
  HARNESS-012, filed as `HARNESS-014`. Nothing in this story touches them.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain the exact
     command, the verbatim failure output, every file touched and which AC each
     test covers, the shape the tests already pin, any test that passed on
     arrival together with the probe that earns it, and the expected value of
     every negative control as a table. -->

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A corrected test written against code that already exists passes
     on its first run whether or not it asserts anything: earn it by mutating
     the specific production behaviour it pins through `bash scripts/mutate.sh`,
     pasting the red, and confirming the revert. check-boundaries.sh refuses a
     PR whose Regressions section describes a failure without showing one. -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Notes

### PO decisions made at PLANNED

**PO decision 1 — the fix is a reorder in place, not a move of the trap.** The
brief offered two shapes. Reordering the two blocks is three lines in one and
four in the other, keeps `finish()`'s preconditions exactly as HARNESS-012 left
them, and needs no new log vocabulary. Moving the trap above the changed-nothing
check removes the whole class rather than these two instances, and it was
weighed: `finish()` is written against `$CHANGED`, `$LINES`, `$MUTATED`,
`$COMPLETED`, `$BAK` and `$NEW`, and under `set -u` two of those are unset at
`exit 3` time and three are in a half-built state at `exit 2` time, where
`$NEW.err` also exists and `finish()` knows nothing about it. So the trap would
have to learn three states it does not have and the log would grow a `REJECTED`
row and a second `CHANGED NOTHING` row — a larger change, with more new
behaviour, than the class it removes. HARNESS-012's Contract had already pinned
the insertion point deliberately. Recorded so a later reader sees this was
decided rather than inherited. If the reorder turns out to need a third site,
that is the moment to revisit it, in a story of its own.

**PO decision 2 — the `sed`-rejected path still writes no log line.** The
opposite is defensible: the log is the record of every mutation attempt, and a
refused expression is an attempt. But it is new behaviour that no defect
demands, and "GREEN adding production behaviour no test demands" is the thing
this harness asks GREEN not to do. AC-4 pins the absence — with the anchored
needle and the positive companion assertion described in the Contract — so the
decision is enforced rather than merely stated. Reversing it later costs one
line and one assertion.

**PO decision 3 — `required_gates` stays `[]`, and no gate is added.** The rule
in `story-authoring` is to name the required gate that would fail if the story's
artifact broke, and to fix it here if the answer is "none or an optional one".
The answer is "none", and the fix is not available cheaply: every gate in
`project.conf` judges the Luau project, `harness` runs only
`project-counters.test.sh` — `HARNESS-008`'s derived answer, the one suite a
*product* story can break, rather than an omission — and `required_gates` can
only name a gate that exists. What runs this story's artifact is
`.github/workflows/gates.yml`'s `bash scripts/selftest.sh` step, on every PR. So
the criteria are not unexercised; they are exercised by a CI step rather than by
a gate id. Same decision and same reasoning as HARNESS-012's PO decision 2,
recorded again so an empty `required_gates` does not read as nobody having
asked.

**PO decision 4 — the `exit 2` path is in this story, not a third one.** The
brief named only the `exit 3` path. The `exit 2` path was found while
reproducing it at PLANNED, leaks one file *more* (`.new.err`), and takes the
identical repair four lines above. Splitting it out would mean two stories, two
PRs and two `selftest` runs to close one invariant, and the invariant is the
point: "a leftover `.bak` means a restore failed" with one documented exception
left is no better than with two. It also brings the story's sharpest negative
control with it — the `$NEW.err` capture, mutation 3 in
`## Deferred verifications` — which the `exit 3` path alone does not have. The
cost is one extra AC and one extra provocation in the same fixture.

**PO decision 5 — `depends_on: [HARNESS-012]`.** This story reorders code around
the `finish()` trap HARNESS-012 introduced and reuses its test helpers and its
`RUN_LINE` needle. Neither exists on `main` until PR #25 merges, so
`phase.sh set` should refuse to start this one before then; that refusal is the
correct behaviour, not an obstacle.

**PO decision 6 — the criteria were not changed after this file was written, so
this story carries no `## Amendments` section.** If one turns out to be wrong,
that is where it goes, after the orchestrator reproduces the finding on its own
inputs.

### Reproduction, by the Lead PO at PLANNED

The baseline table in the Contract is this repository's own, not the brief's:
built with `make_project_fixture` from `.claude/tests/_lib.sh`, `-- true` as the
payload, `.claude/state/mutations/` removed between runs, `pipefail` off so the
pipeline's status is what a plain shell would report, and `${PIPESTATUS[0]}`
captured in the same shell as the pipeline. It reproduced the `exit 3` symptom
the brief describes, at `head -0` and at `| true`, and found the `exit 2` symptom
beside it. The ordinary mutating path was measured in the same fixture as a
contrast and was clean at every reader, including `head -0`.

### For the phases that follow

- **`gates.sh` stamps the *active* story.** A `gates.sh` or `ci-local.sh` run
  started from a worktree writes its record into whatever story is active, which
  may not be this one. Run `bash scripts/phase.sh show` before either.
- **The inner loop is `bash scripts/selftest.sh mutate`** — one suite. A bare
  `bash scripts/selftest.sh` runs all 19 suites, takes 10-25 minutes on this
  machine, and two overlapping runs corrupt each other. Run the whole suite
  once, alone, before the PR.
- **A full `bash scripts/gates.sh` run exceeds 10 minutes here**, and
  `bash scripts/gates.sh --list` is minutes slow on this machine (seconds on
  CI). That is fork cost in the config parse, not a hang.
- **The phase lock will not enforce this story's RED→GREEN separation.** Both
  files are `harness`. The law still does.
