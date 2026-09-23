---
id: HARNESS-013
title: mutate.sh's early-exit paths leak the backup they print about
slug: mutate-sh-s-early-exit-paths-leak-the-ba
epic: 
type: fix
status: in-progress
phase: RED
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

**Amended by RED, 2026-09-23 — the `head -1` rows are a race, not a settled
value.** The first run of the finished suite went red at P-N through `head -1`
as well as at `head -0` and `true`:

    FAIL reader 'head -1': nothing but the log is left under mutations/
         expected:
         actual:   src_main.ts.20260923T203350Z.62501.bak src_main.ts.20260923T203350Z.62501.new
    FAIL reader 'head -1': exactly one log line says CHANGED NOTHING - command not run
         expected: 1
         actual:   0

Re-measured outside the framework, in a fresh `make_project_fixture`, five runs
per provocation: P-N through `head -1` was clean with one log line 5/5, P-S
through `head -1` clean 5/5. So the table's `head -1` rows are the *usual*
outcome, not a guaranteed one. The mechanism: `head -1` exits after the first
line, and today both blocks print their first line **before** the file work; if
`head` is scheduled and exits between the writer's first and second `printf`,
the second write is SIGPIPE and the block dies above its log append and its
`rm`. "Four short lines fit the pipe buffer" is true and is about blocking; it
does not cover a reader that closes the pipe between two writes. `head -4`
cannot trip either way — it reads every line both blocks print and then waits
for EOF, so the writer has nothing left to write when the pipe closes.

What this changes: **nothing in the criteria** — AC-1 to AC-4 already demand
the post-condition at all four readers, and after the fix every reader is
deterministic because nothing is printed before the file work is done. What it
changes for **GATES** is deferred verifications 1 and 2: "`head -1` ... must
stay green" under the un-reorder is not a reliable control on this machine;
`head -4` is, and is the row to read as "stays green". A `head -1` red under
mutation 1 or 2 is this race, not a defect in the sweep.

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


**Mutations 4-6, added by the Lead PO at PLANNED. Owner: RED.** The three above
earn the *fix*: each breaks something this story builds, and a file assertion
catches it. They leave four criteria unearned. AC-4, AC-5's first assertion,
AC-6 and AC-7 all **pass today**, which `rules.md` says is the shape of an
assertion that could be asserting nothing and nothing would notice — and
mutations 1-3 do not move any of them.

**These three are RED's, not GATES's, and the difference is not bookkeeping.**
Mutations 1-3 cannot run in RED because they un-reorder code GREEN has not
written yet. Mutations 4-6 mutate code that exists **today**, pinning assertions
that pass **today** — which is exactly `rules.md`'s recipe for a test written
while the implementation already exists: mutate the specific production
behaviour it claims to pin, watch that one assertion go red, revert. That recipe
belongs to the phase that writes the assertion. Run them through
`scripts/mutate.sh` by the copy recipe below, one mutation and one run each, and
paste the red into `## Handoff` as well as here.

4. **The `sed`-rejected path given a log line.** With a `printf ... >> "$LOG"`
   added to the `exit 2` block, AC-4's zero-count **must** go to 1 and go red,
   and AC-2's count must stay at 1. This earns PO decision 2 — the decision that
   this path writes nothing — and it is the only thing that does: an absence
   assertion against a path that has never written a line is satisfied by a
   `grep` pointed at the wrong file, by a misspelled needle, and by the needle
   the Contract warns about. It also proves the anchoring from the other side:
   if AC-4 goes to 1 only when the *ordinary* expression is in the log too, the
   trailing `(\t.*)?$` is not doing its job.

   **Result (RED, 2026-09-23, this machine).** Expression, through the copy
   recipe:

       $ cp scripts/mutate.sh scripts/__mutate_probe.sh
       $ bash scripts/__mutate_probe.sh scripts/mutate.sh 's/^  exit 2$/  printf "%s\t%s\t%s\tREJECTED\n" "$STAMP" "$REL" "$EXPR" >> "$LOG"; exit 2/' -- bash scripts/selftest.sh mutate
       === mutate: scripts/mutate.sh (155 line(s) changed by ...) ===
         120 -   exit 2
         120 +   printf "%s	%s	%s	REJECTED
         121 - fi
         121 + " "$STAMP" "$REL" "$EXPR" >> "$LOG"; exit 2
       (GNU sed rendered `\t` and `\n` in the replacement as a literal tab and
        newline inside the double-quoted format, which is still one valid
        `printf` writing one tab-separated line; the "155 lines changed" is the
        line shift that newline causes, not 155 edits.)

   The red — the four assertions that moved, and only those:

       an expression sed rejects leaves no backup, no working copy and no .err through a closed pipe
         FAIL reader 'head -1': no log line names the rejected expression
              expected: 0
              actual:   1
         FAIL reader 'head -4': no log line names the rejected expression
              expected: 0
              actual:   1
         FAIL and still no log line names the rejected expression
              expected: 0
              actual:   1
         FAIL while the control's line is still the only one in the log
              expected: 1
              actual:   2

       mutate: 121 passed, 12 failed

   Read against the prediction: AC-4's zero went to 1 wherever the mutated
   block reached its log write (`head -1`, `head -4`, unpiped) and stayed 0 at
   `head -0` and `true`, where SIGPIPE at the first `printf` still kills the
   block above the write — the file assertions there stayed red as at
   baseline. AC-2's count stayed at 1 (no new failure in the changed-nothing
   block). The needle block `the needle for the rejected path does not match
   the ordinary one` stayed green: `REJECTED_LINE` moved only in the block
   where a rejected-expression line was actually written, so the trailing
   `(\t.*)?$` is doing its job from this side too. The other 8 of the 12
   failures are the baseline reds (AC-1/2 at `head -0`, `true` and — the race,
   see the Contract amendment — at `head -1`; AC-3 at `head -0`, `true`).

   Restore: `=== mutate: command exited 1; restored (verified byte-for-byte
   against .../scripts_mutate.sh.20260923T203911Z.73001.bak) ===`;
   `git diff --stat scripts/mutate.sh` empty; `git status --short` shows only
   `.claude/tests/mutate.test.sh` and this story; no `scripts/__mutate_probe.sh`.

5. **One of the four "changed nothing" lines deleted.** With the third `printf`
   of the `exit 3` block removed, AC-6's four-line assertion **must** go red —
   *and the existing `assert_contains "changed nothing"` at
   `mutate.test.sh:132` must stay green.* Both halves are the point: the second
   is what shows AC-6 is sharper than the assertion it sits beside, rather than
   a fourth restatement of it.

   **Result (RED, 2026-09-23, this machine).**

       $ cp scripts/mutate.sh scripts/__mutate_probe.sh
       $ bash scripts/__mutate_probe.sh scripts/mutate.sh '/the command would have passed for the same reason it passes now/d' -- bash scripts/selftest.sh mutate
       === mutate: scripts/mutate.sh (144 line(s) changed by /the command would have passed for the same reason it passes now/d) ===
         129 -   printf '  the command would have passed for the same reason it passes now. Check the\n' >&2
         129 +   printf '  expression against the file and try again.\n' >&2
       (one line deleted; the count is the shift of everything below it)

   The red — one assertion, and the one beside it green:

       a mutation that mutates nothing proves nothing
                                               <- no FAIL: `it says the expression changed nothing` stayed green

       and says so in full: the whole explanation, on stderr, before exit 3
         FAIL line 3 of 4 is on stderr, entire
              expected: 1
              actual:   0

       mutate: 126 passed, 7 failed

   Both halves as required: AC-6's third-line assertion went red, the existing
   `assert_contains "changed nothing"` did not, and nothing else moved — the
   other 6 failures are the baseline reds at `head -0` and `true` (in this run
   the `head -1` race did not fire). Lines 1, 2 and 4 stayed at 1, so the
   assertion that moved is the one naming the deleted line.

   Restore: `=== mutate: command exited 1; restored (verified byte-for-byte
   against .../scripts_mutate.sh.20260923T205039Z.93356.bak) ===`;
   `git diff --stat scripts/mutate.sh` empty; no `scripts/__mutate_probe.sh`.

**Correction to mutation 6, by the orchestrator at the end of RED — the second
clause of this entry was wrong, and RED was right to probe it rather than follow
it.** As written, the entry predicted that moving the trap back below the banner
would turn *both* AC-7's `head -0`/`true` rows **and** the existing width sweep
red. RED reported that it turns only the former. Reproduced independently, in a
throwaway fixture whose **own copy** of `mutate.sh` was edited (the repository's
was never touched), five runs per cell, `s/90/-90/`:

    UNMUTATED                        trap 256, banner 258, running 267
        head -0   leftovers=0/5
        head -1   leftovers=0/5
        head -3   leftovers=0/5
    MUT-6   (trap below banner+diff) trap 261, banner 257, running 267
        head -0   leftovers=5/5      <- AC-7 red, as the entry says
        head -1   leftovers=0/5      <- the sweep stays GREEN
        head -3   leftovers=0/5
    MUT-6b  (trap below `running`)   trap 267, banner 257, running 266
        head -0   leftovers=5/5
        head -1   leftovers=5/5      <- the sweep goes red here, not under MUT-6
        head -3   leftovers=5/5

Why: with the trap below the banner and the diff, the shell's **next own write**
is the `running` line at `mutate.sh:267`, by which time the trap exists. A
`head -N` with N >= 1 takes the banner without the writer blocking, so no SIGPIPE
lands in the unprotected window at all. Only a reader that takes **nothing** —
`head -0`, `true` — dies in it. That is exactly the property AC-7's two new rows
were added to pin and the sweep's widths 1..30 cannot reach, which is the point
of AC-7 rather than an argument against it.

**So the entry now reads:** under mutation 6, AC-7's `head -0` and `true`
assertions must go red, and **the existing width sweep must stay green** — its
staying green is part of the evidence, not a failure. Mutation **6b** (the trap
moved below the `running` line) is the variant that reddens the sweep, and RED
ran it too; both outputs are below. Either is acceptable as the earning probe.
A PO instruction that names a mechanism is checkable, not sacred; this one did
not hold, and the report is the valuable half of the exchange.

6. **The trap installed late again — HARNESS-012's own defect.** With the
   `trap ... EXIT` line moved back below the banner, AC-7's assertions at
   `head -0` and at `true` **must** go red, and the existing width sweep at
   `mutate.test.sh:276` must go red with them. AC-7 is a regression pin on
   another story's fix, so nothing this story writes can make it fail; without
   this it is an assertion with no demonstrated failure mode at all. Restoring
   the line is the whole revert — do not "fix" anything else while it is moved.

   **Result (RED, 2026-09-23, this machine) — two runs, because the entry
   makes two predictions and the first placement confirmed only one.**

   *Run 6, the mutation as written — the `trap` line moved to directly below
   the banner (after the `awk ... | head -20 >&2` line):*

       $ cp scripts/mutate.sh scripts/__mutate_probe.sh
       $ bash scripts/__mutate_probe.sh scripts/mutate.sh '/^trap finish EXIT INT TERM$/d; /| head -20 >&2$/a trap finish EXIT INT TERM' -- bash scripts/selftest.sh mutate
       === mutate: scripts/mutate.sh (5 line(s) changed by ...) ===
         256 - trap finish EXIT INT TERM
         ...
         260 + trap finish EXIT INT TERM

       the ordinary mutating run stays clean at the readers that close the pipe unread
         FAIL reader 'head -0': nothing but the log is left under mutations/
              expected:
              actual:   src_main.ts.20260923T210147Z.113805.bak src_main.ts.20260923T210147Z.113805.new
         FAIL reader 'head -0': exactly one log line names the run
              expected: 1
              actual:   0
         FAIL reader 'true': nothing but the log is left under mutations/
              expected:
              actual:   src_main.ts.20260923T210152Z.114046.bak src_main.ts.20260923T210152Z.114046.new
         FAIL reader 'true': exactly one log line names the run
              expected: 1
              actual:   0

       mutate: 121 passed, 12 failed

   AC-7's `head -0` and `true` assertions went red, as required. **The
   existing width sweep did not**, contrary to this entry's second sentence,
   and the reason is mechanical rather than a defect in the sweep: with the
   trap installed after the banner's `awk | head -20`, the shell's own next
   write is the `=== mutate: running ... ===` line, and the trap exists by
   then. `head -1` reads the banner and closes the pipe; the `awk`/`head -20`
   children die of SIGPIPE, not the shell; the shell dies at the `running`
   write **inside** the trap's protection, after the file work — clean. Only
   a reader that closes the pipe before the very first write reaches the
   unprotected banner `printf`. So AC-7's two readers pin something the sweep
   cannot: "installed before the first byte", not "installed before the
   shell's second own write". The remaining 8 failures are the baseline reds.

   *Run 6b, the trap moved below the `running` line instead, to measure the
   entry's second claim rather than explain it away:*

       $ cp scripts/mutate.sh scripts/__mutate_probe.sh
       $ bash scripts/__mutate_probe.sh scripts/mutate.sh '/^trap finish EXIT INT TERM$/d; /=== mutate: running %s ===/a trap finish EXIT INT TERM' -- bash scripts/selftest.sh mutate
       === mutate: scripts/mutate.sh (12 line(s) changed by ...) ===
         256 - trap finish EXIT INT TERM
         ...

       a reader that closes the pipe early leaves no backup, and logs once
         FAIL N=1: no .bak or .new is left behind
              expected:
              actual:   src_main.ts.20260923T210532Z.122149.bak src_main.ts.20260923T210532Z.122149.new
         FAIL N=1: exactly one log line names the run
              expected: 1
              actual:   0
         FAIL N=1: src/main.ts is byte-identical after
              expected: 4788c78ab31d1ca7cfae8570c7e6840852dddbd1
              actual:   7c6b75ddfa588f69017b7d61a75d0c8701f848fe
         FAIL N=2: ... (same three)
         FAIL N=3: ... (same three)
         (N=4, 5, 6, 30 green)

       the ordinary mutating run stays clean at the readers that close the pipe unread
         FAIL reader 'head -0': nothing but the log is left under mutations/
         FAIL reader 'head -0': exactly one log line names the run
         FAIL reader 'true': nothing but the log is left under mutations/
         FAIL reader 'true': exactly one log line names the run
         FAIL reader 'head -1': nothing but the log is left under mutations/
         FAIL reader 'head -1': exactly one log line names the run
         FAIL reader 'head -1': src/main.ts is byte-identical after
              expected: 4788c78ab31d1ca7cfae8570c7e6840852dddbd1
              actual:   7c6b75ddfa588f69017b7d61a75d0c8701f848fe

       mutate: 109 passed, 24 failed

   This is HARNESS-012's defect in full — the mutated file left in the tree
   with no log line — and both the sweep (N ≤ 3, where `head` closes the pipe
   before the `running` write; clean from N = 4, where that write has already
   landed) and AC-7 (now at `head -1` too) catch it. The needle block and the
   unpiped-run block stayed green in both runs; the other 8 failures are the
   baseline reds.

   Restore, both runs: `restored (verified byte-for-byte against
   .../scripts_mutate.sh.20260923T205811Z.106293.bak)` and
   `.../scripts_mutate.sh.20260923T210342Z.118288.bak)`; `git diff --stat
   scripts/mutate.sh` empty after each; no `scripts/__mutate_probe.sh`.

**Why RED cannot run mutations 1-3.** There is nothing to un-reorder in RED: the
reordered code is what GREEN is about to write, and `scripts/mutate.sh` is not
RED's to edit under the law even though the lock would permit it.

**Owner: GATES** — mutations 1, 2 and 3. **Owner: RED** — mutations 4, 5
and 6, for the reason above.

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

- **RED** — `test-developer`, resolved `fable` (`claude-fable-5-1`). As planned:
  the dispatch passed `model: fable` explicitly, so the plan and the resolution
  agree and neither a session setting nor the agent definition decided it. The
  agent confirmed the same name from inside the dispatch. All three success
  conditions above were met — see "Verdict on the `fable` experiment" in
  `## Notes`, where they are checked against the tree rather than against the
  report.

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

All in `.claude/tests/mutate.test.sh`, at the level the contract lives: the real
`scripts/mutate.sh` copied into a `make_project_fixture`, driven through a real
pipe, judged by what is left on disk and in the log. Bash, git and coreutils
only. Nothing existing was rewritten; `piped_run`, `leftovers()`, the width
sweep and the `a mutation that mutates nothing proves nothing` block keep their
exact text.

**Helpers and needles added** (after `lines_in`):

| Name | What it is |
|---|---|
| `piped_expr_run <READER> <EXPR> <command...>` | sibling of `piped_run`: expression and reader as arguments, same `2>&1` merged stream, same `${PIPESTATUS[0]}` captured in the same shell via `$STFILE`; `PIPED_OUT`, `PIPED_ST` (recorded, never asserted) |
| `entries_but_log` | `ls "$MUTDIR" \| grep -v '^log$'` — everything under `mutations/` except the log, by name; sees `.new.err` |
| `count_exact <str> <line>` | whole-line, literal count (`grep -cxF`) in a captured stream |
| `NOTHING_LINE` | `^<STAMP_RE>\tsrc/main\.ts\ts/NOT_IN_THE_FILE/x/\tCHANGED NOTHING - command not run$` |
| `REJECTED_LINE` | `^<STAMP_RE>\tsrc/main\.ts\ts/90/-90(\t.*)?$` — the trailing `(\t.*)?$` is what stops it matching `s/90/-90/` |
| `EARLY_READERS` | `('head -0' 'true' 'head -1' 'head -4')`, read out from the Contract |

**Blocks** (describe → assertions → AC):

| Block | Assertions | AC |
|---|---|---|
| `and says so in full: the whole explanation, on stderr, before exit 3` — sits directly after the existing changed-nothing block; P-N unpiped, stderr captured alone (`2>&1 1>/dev/null`) | exit 3; each of the four lines counted entire on stderr = 1; `src/main.ts` sha unchanged; `ran-marker` absent | AC-6 |
| `an expression that changes nothing leaves no backup through a closed pipe, and logs once` — P-N × 4 readers, `mutations/` removed before each | `entries_but_log` = ""; `count_lines NOTHING_LINE` = 1; sha unchanged | AC-1, AC-2 |
| `an expression sed rejects leaves no backup, no working copy and no .err through a closed pipe` — P-S × 4 readers, then in ONE directory: P-N unpiped (control), sed's own complaint measured directly, P-S unpiped with stderr captured alone | per reader: `entries_but_log` = ""; `count_lines REJECTED_LINE` = 0; sha unchanged. Then: control `NOTHING_LINE` = 1; sed complaint non-empty; exit 2; heading line entire = 1; `"  $sed_complaint"` entire = 1; sha unchanged; `REJECTED_LINE` = 0; total log lines = 1; `entries_but_log` = "" | AC-3, AC-4 (with its control), AC-5 |
| `the ordinary mutating run stays clean at the readers that close the pipe unread` — `s/90/-90/` × 4 readers | `entries_but_log` = ""; `count_lines RUN_LINE` = 1; sha unchanged | AC-7 |
| `the needle for the rejected path does not match the ordinary one` — P-N added to the log the AC-7 sweep left (one ordinary line) | total lines = 2; `RUN_LINE` = 1; `NOTHING_LINE` = 1; `REJECTED_LINE` = 0; floating `grep -cF 's/90/-90'` = 1 (the false alarm the anchor prevents) | the instrument for AC-4; Model-guidance success condition 3 |

**Cost.** 16 new `mutate.sh` processes. Suite went from ~146 s to 402 s on this
machine (one full run, nothing else running). No per-test timeout exists in this
runner; the ceiling that matters is the orchestrator's 600 s foreground cap on a
single `bash scripts/selftest.sh mutate`, and 402 s sits under it with margin.
Each of the three probes below is one full suite under the copy recipe, ~7 min.

**Passes on arrival, and what earns each** — see `## Deferred verifications`
4, 5 and 6 and the handoff: AC-4 (mutation 4), AC-5's first assertion and AC-6
(mutation 5; mutation 3, GATES's, earns AC-5's second), AC-7 (mutation 6). The
needle-demonstration block passes on arrival too and is an instrument check,
earned by mutation 4's other half: the `REJECTED_LINE` count moves to 1 only
when a line with the rejected expression is actually written, not because an
ordinary line is present.

## Handoff: RED -> GREEN

**Model.** RED ran on `fable` (`claude-fable-5-1`), as planned; no override was
passed to this dispatch.

### The command

    bash scripts/selftest.sh mutate

One suite, 402 s on this machine with nothing else running (was ~146 s after
HARNESS-012; 16 new `mutate.sh` processes). Do not run bare
`bash scripts/selftest.sh` as the inner loop.

### Files touched

| File | What |
|---|---|
| `.claude/tests/mutate.test.sh` | the only test file: helpers `piped_expr_run`, `entries_but_log`, `count_exact`; needles `NOTHING_LINE`, `REJECTED_LINE`; array `EARLY_READERS`; one block after the existing changed-nothing block (AC-6); four blocks at the end (AC-1/2, AC-3/4/5, AC-7, needle demonstration). Nothing existing was edited. |
| `docs/backlog/stories/HARNESS-013.md` | `## Contract` amended (baseline table: the `head -1` race), `## Test plan`, this section, `## Deferred verifications` 4, 5, 6 results |

**`scripts/mutate.sh` was not edited.** The lock would have allowed it — both
files classify as `harness` — and the law still applies. Checked against the
tree after the last probe's restore:

    $ git diff --stat scripts/mutate.sh
    $ git status --short
     M .claude/tests/mutate.test.sh
     M docs/backlog/stories/HARNESS-013.md

No `scripts/__mutate_probe.sh` remains. The four probe runs each restored the
file and verified it with `cmp` (their verdict lines are pasted under
`## Deferred verifications`).

### Verbatim failure output — first run of the finished suite, untouched `mutate.sh`

    === mutate ===
    ...
      an expression that changes nothing leaves no backup through a closed pipe, and logs once
        FAIL reader 'head -0': nothing but the log is left under mutations/
             expected:
             actual:   src_main.ts.20260923T203329Z.61895.bak src_main.ts.20260923T203329Z.61895.new
        FAIL reader 'head -0': exactly one log line says CHANGED NOTHING - command not run
             expected: 1
             actual:   0
        FAIL reader 'true': nothing but the log is left under mutations/
             expected:
             actual:   src_main.ts.20260923T203339Z.62193.bak src_main.ts.20260923T203339Z.62193.new
        FAIL reader 'true': exactly one log line says CHANGED NOTHING - command not run
             expected: 1
             actual:   0
        FAIL reader 'head -1': nothing but the log is left under mutations/
             expected:
             actual:   src_main.ts.20260923T203350Z.62501.bak src_main.ts.20260923T203350Z.62501.new
        FAIL reader 'head -1': exactly one log line says CHANGED NOTHING - command not run
             expected: 1
             actual:   0

      an expression sed rejects leaves no backup, no working copy and no .err through a closed pipe
        FAIL reader 'head -0': nothing but the log is left under mutations/ - no .bak, .new or .new.err
             expected:
             actual:   src_main.ts.20260923T203410Z.63063.bak src_main.ts.20260923T203410Z.63063.new src_main.ts.20260923T203410Z.63063.new.err
        FAIL reader 'true': nothing but the log is left under mutations/ - no .bak, .new or .new.err
             expected:
             actual:   src_main.ts.20260923T203416Z.63301.bak src_main.ts.20260923T203416Z.63301.new src_main.ts.20260923T203416Z.63301.new.err

      the ordinary mutating run stays clean at the readers that close the pipe unread

      the needle for the rejected path does not match the ordinary one

    mutate: 125 passed, 8 failed

    1 of 1 harness suite(s) FAILED.

Every failure is a file left behind or a log line missing after a run that
never mutated anything — the assertion, not an error in the harness. Six of the
eight are the Contract's table exactly. The two at P-N `head -1` are a **race**
the table does not show (see "What I found" and the Contract amendment): 5/5
clean outside the suite, red in 4 of the 5 suite runs today. The
`src/main.ts is byte-identical` assertions passed at every reader on both
paths, which is the table's `src_ok=yes`.

### One line per test, and the AC it covers

| Assertion (as printed) | Asserts | AC |
|---|---|---|
| `unpiped, it still exits 3` | rc = 3 for P-N unpiped | AC-6 |
| `line N of 4 is on stderr, entire` (×4) | each of the four changed-nothing lines, matched entire on stderr alone, count = 1 | AC-6 |
| `and src/main.ts is byte-identical` / `and the command never ran` | sha unchanged; `ran-marker` absent | AC-6 |
| `reader 'R': nothing but the log is left under mutations/` (P-N, ×4) | `ls mutations/ \| grep -v '^log$'` empty | AC-1 |
| `reader 'R': exactly one log line says CHANGED NOTHING - command not run` (×4) | `count_lines NOTHING_LINE` = 1 | AC-2 |
| `reader 'R': src/main.ts is byte-identical after` (P-N, ×4) | sha unchanged | AC-1 (the table's `src_ok`) |
| `reader 'R': nothing but the log is left under mutations/ - no .bak, .new or .new.err` (P-S, ×4) | directory enumeration empty | AC-3 |
| `reader 'R': no log line names the rejected expression` (×4) | `count_lines REJECTED_LINE` = 0 | AC-4 |
| `control: a changed-nothing run in the same directory logs its one line` | `NOTHING_LINE` = 1 in the directory the P-S unpiped run then uses | AC-4 control |
| `sed's own complaint about s/90/-90 is non-empty` | guard on the AC-5 needle | AC-5 |
| `unpiped, the rejected expression still exits 2` | rc = 2 | AC-5 |
| `and stderr carries the heading, entire` | `mutate: sed rejected the expression:` count = 1 on stderr | AC-5 |
| `and sed's own complaint, indented by two spaces` | `"  " + sed's own first line` count = 1 on stderr | AC-5 (target of GATES's mutation 3) |
| `and still no log line names the rejected expression` / `while the control's line is still the only one in the log` | `REJECTED_LINE` = 0; total lines = 1 | AC-4 (unpiped) |
| `and nothing but the log is left under mutations/` | enumeration empty after the unpiped P-S | AC-3 (unpiped) |
| `reader 'R': nothing but the log is left under mutations/` / `exactly one log line names the run` / `src/main.ts is byte-identical after` (`s/90/-90/`, ×4) | enumeration empty; `RUN_LINE` = 1; sha unchanged | AC-7 |
| `the log holds exactly two lines` / `RUN_LINE counts the ordinary run once` / `NOTHING_LINE counts the changed-nothing run once` / `REJECTED_LINE, anchored, counts zero beside them` / `whereas a floating grep -F for s/90/-90 would count the ordinary line` | 2 / 1 / 1 / 0 / 1 | instrument for AC-4; success condition 3 |

### The shape the tests pin (stated as fact — a test already depends on it)

- **Invocation**: `bash scripts/mutate.sh src/main.ts '<EXPR>' -- <command...>`, run from the fixture root. Unchanged.
- **Exit statuses**: 2 for a `sed`-rejected expression, 3 for changed-nothing, unpiped. Unchanged.
- **Streams**: both explanations on **stderr** (the tests capture stderr alone with `2>&1 1>/dev/null`; a line moved to stdout fails `count_exact`). Unchanged.
- **The four changed-nothing lines, verbatim and entire**, in this order is not asserted, but each line is:
  `mutate: the expression changed nothing in src/main.ts.` /
  `  A probe that does not alter behaviour cannot show a test discriminates:` /
  `  the command would have passed for the same reason it passes now. Check the` /
  `  expression against the file and try again.`
- **The rejected-expression heading, entire**: `mutate: sed rejected the expression:`; then a line that is exactly two spaces followed by the first line `sed -e 's/90/-90' src/main.ts` itself writes to stderr on the machine running the suite (measured in the test, not transcribed — on GNU sed 4.9 here: `sed: -e expression #1, char 8: unterminated `s' command`). If GREEN captures `$NEW.err` into a variable and prints it with `printf '  %s\n'` per line, or `sed -e 's/^/  /' <<< "$captured"`, this holds. A trailing newline dropped by `$(...)` is fine; an extra blank line is fine; the text altered or missing is not.
- **The log line for changed-nothing, entire**: `<STAMP>\tsrc/main.ts\ts/NOT_IN_THE_FILE/x/\tCHANGED NOTHING - command not run` — same three leading fields, same outcome text, exactly one per run, at every reader and unpiped.
- **No log line for the rejected path** — nothing whose first three fields are `<STAMP>\tsrc/main.ts\ts/90/-90` — at every reader and unpiped.
- **Post-condition of `.claude/state/mutations/` after either early exit, at every reader**: contains `log` and nothing else (P-N), or nothing but optionally `log` (P-S). `.bak`, `.new`, `.new.err` all gone.
- **`src/main.ts` byte-identical** after every run in this story.

**Not constrained**, so still GREEN's choice: how the `.err` text is captured
(variable, `$(cat)`, `mapfile`), whether `rm -f` precedes or follows the log
append within the block, the exact ordering of the two `rm`s, `finish()` and the
trap (the story says do not touch them; nothing here asserts on them either
way), and `mutate.sh`'s exit status through a pipe (`PIPED_ST` is recorded in
the helper and never asserted).

### Negative controls — expected values

The suite does not fail at import (it is bash; every assertion ran), so these
were all **observed in the first run**, not only computed. "Wrong
implementation" is what a plausible bad fix would produce.

| Control | Where | Expected | Observed, RED | A wrong implementation would give |
|---|---|---|---|---|
| P-N run logs its one line in the directory the P-S run then uses | AC-4 control | `NOTHING_LINE` = 1 | 1 | 0 if the log were missing/unwritable — then AC-4's 0 would be vacuous |
| Total lines in that log after the unpiped P-S | AC-4 | 1 | 1 | 2 if the rejected path gained a log line (mutation 4 measured: **2**) |
| `REJECTED_LINE` beside one ordinary `s/90/-90/` line and one P-N line | needle block | 0 | 0 | 1 with a floating or front-only anchor |
| floating `grep -cF 's/90/-90'` on that same log | needle block | 1 | 1 | 0 would mean the prefix is absent and the demonstration empty |
| `RUN_LINE` / `NOTHING_LINE` on that log | needle block | 1 / 1 | 1 / 1 | — |
| sed's own complaint is non-empty | AC-5 | non-empty | `sed: -e expression #1, char 8: unterminated `s' command` | empty would make `"  "` the needle |
| `line 3 of 4` under mutation 5 | AC-6 | 0, others 1, old `assert_contains` green | **0; 1,1,1; green** | — |
| AC-7 `head -0` / `true` under mutation 6 | AC-7 | red (leftovers, log 0) | **red, 4 assertions** | — |
| Existing sweep under mutation 6 (trap after banner) | sweep | story said red | **green** — see "What I found" | — |
| Existing sweep under mutation 6b (trap after `running`) | sweep | red N ≤ 3, green N ≥ 4 | **red 1,2,3 (9 assertions); green 4,5,6,30** | — |

### Tests that passed on arrival, and what earns each

| Passed on arrival | Earned by | Red produced |
|---|---|---|
| AC-4 (`no log line names the rejected expression`, ×4 + unpiped) | mutation 4 (RED, done) | 0 → 1 at `head -1`, `head -4`, unpiped; control total 1 → 2; AC-2 unmoved; needle block unmoved |
| AC-5 first assertion (exit 2) and heading | not separately earnable without breaking the path itself; the heading's `count_exact` is exercised by the same instrument mutation 5 exercises on AC-6 | — |
| AC-5 second assertion (sed's complaint) | **mutation 3 — GATES's**, declined here | — |
| AC-6 (four lines entire) | mutation 5 (RED, done) | `line 3 of 4` 1 → 0; `it says the expression changed nothing` stayed green |
| AC-7 (`s/90/-90/` at `head -0`, `true`, `head -1`, `head -4`) | mutation 6 (RED, done; plus 6b) | `head -0` and `true` red under 6; `head -1` red as well under 6b |
| needle demonstration block | mutation 4's other half | `REJECTED_LINE` moved only in the block where a rejected line was written |

Full output for 4, 5, 6 and 6b is under `## Deferred verifications`.

### Declined: mutations 1, 2 and 3 are GATES's

They un-reorder the `exit 3` block, un-reorder the `exit 2` block, and blank
the captured `$NEW.err` text — code GREEN has not written yet. There is nothing
in today's `mutate.sh` to mutate for them, and `scripts/mutate.sh` is not RED's
to edit. Not attempted, not claimed. For mutation 3 specifically: the assertion
it must turn red is `and sed's own complaint, indented by two spaces`, and the
one that must stay green is `and stderr carries the heading, entire` — both in
the block `an expression sed rejects leaves no backup, no working copy and no
.err through a closed pipe`.

### What I found that GREEN and GATES should know

1. **P-N through `head -1` is a race today, not a settled pass.** Red in the
   first suite run and in 3 of the 4 probe runs; 5/5 clean standalone. It fires
   when `head` exits between the block's first and second `printf`. After the
   fix — file work before any write — every reader is deterministic, so GREEN
   need do nothing extra. GATES: under mutations 1 and 2, "`head -1` must stay
   green" is not reliable here; `head -4` is the row that must stay green.
2. **Mutation 6 as specified does not turn the old sweep red** (trap after the
   banner protects the shell's second own write); mutation 6b (trap after the
   `running` line) does, at N ≤ 3. AC-7's `head -0`/`true` rows are what pin
   "before the first byte". Neither finding changes any criterion.
3. **The `.err` capture is where the fix can go quietly wrong.** The AC-5 needle
   is sed's real message, measured in the test, indented by exactly two spaces
   and matched entire. Capture the text before the `rm`, print it after.
4. **Timing.** Suite 402 s alone, 425–564 s under a probe (the machine was
   busier). The orchestrator's foreground cap is 600 s; a detached launch was
   used for the probes and is safe here (`nohup ... &` inside `( )` survives
   the tool returning).

### `bash scripts/gates.sh --fast`

Run at the end of RED, 652 s on this machine (the `--list` parse is the slow
part here, as `## Notes` warns):

    --- gate summary ---
    PASS         format (2s, observed 79)
    PASS         lint (2s, observed 79, floor 1)
    PASS         typecheck (5s, observed 16)
    PASS         unit (77s, observed 355, floor 355)
    UNCONFIGURED coverage
    PASS         build (1s, observed 47816)
    PASS         harness (31s, observed 40)

    --fast skipped: integration mutation
    This is a subset, not a verdict. The full run before REVIEW is what judges the story.

    (not recorded in the story: a partial run is not evidence of anything)

    All required gates passed (6 ran, 1 unconfigured, 0 known).

The shape is the one the story predicts (PO decisions 3 and 8): **no gate is
red, because no gate runs this suite** — `harness` runs
`project-counters.test.sh` only, and `.claude/tests/mutate.test.sh` classifies
as `harness`, not `source`, so no `covers` line bites. The red for this story is
`bash scripts/selftest.sh mutate`, which CI runs at
`.github/workflows/gates.yml:108`. Format, lint and typecheck are green with the
new test file in the tree, so nothing about the tests is inadmissible; there is
no timeout in this runner to budget against beyond the 600 s foreground cap
noted above.

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

### PO decisions made at PLANNED→RED, by the orchestrator

**PO decision 7 — three more deferred verifications, owned by RED.** Written up
in `## Deferred verifications` as mutations 4, 5 and 6. The block as planned
earned the *fix* and left four criteria — AC-4, AC-5's first assertion, AC-6 and
AC-7 — passing on their first run with no demonstrated failure mode. `rules.md`
is explicit that such an assertion "could assert nothing at all and nothing would
notice". They are RED's rather than GATES's because the behaviour each one pins
exists today, so the mutation can be made today; mutations 1-3 cannot, which is
the whole difference. Cost: three `scripts/mutate.sh` runs in RED at roughly two
and a half minutes each.

**PO decision 8 — no change to `required_gates`, and the reasoning was checked
rather than inherited.** PO decision 3's claim was verified against the tree at
dispatch, not taken on trust:

    $ grep -E '^(gate|covers) ' .claude/harness/project.conf
    gate | harness | required | . | bash .claude/tests/project-counters.test.sh
    ... no `covers` line names .claude/** or scripts/** ...
    $ bash scripts/classify.sh scripts/mutate.sh .claude/tests/mutate.test.sh
    harness scripts/mutate.sh
    harness .claude/tests/mutate.test.sh
    $ grep -rn selftest .github/workflows/
    .github/workflows/gates.yml:108:        run: bash scripts/selftest.sh

So `gates.sh`'s `covers` check cannot bite on either file, the `harness` gate
runs a different suite, and `gates.yml:108` is what actually executes this
story's artifact on every PR. `required_gates: []` stands.

### Callers of every signature this story changes

Required before dispatch, because during RED the old shape still exists and its
callers still pass — so a missed one surfaces only after GREEN. Enumerated with
`grep -rn` over the tree (stale copies under `.claude/worktrees/**` excluded;
they are not on any branch this story merges into):

| Symbol | Callers found | Consequence |
|---|---|---|
| `piped_run` | `.claude/tests/mutate.test.sh:280` (the 7-width sweep, 21 assertions) and `:298` (the instrument check) — nowhere else in the repo | **Its signature must not change.** The Contract's "add a sibling helper" is what keeps those 22 assertions at their exact invocation. |
| `leftovers()` | `mutate.test.sh:281`, `:321` | Unchanged. AC-1 and AC-3 enumerate the directory instead, because `leftovers()`'s `\.(bak\|new)$` cannot see `.new.err`. |
| `mutate.sh`'s CLI shape | `.claude/hooks/lib.sh` (`mutate_targets`), `.claude/hooks/phase-guard.sh:221`, asserted in `.claude/tests/lib.test.sh:418-425` | Untouched: this story changes the **order of statements inside two blocks**, not the argument grammar. |
| the `exit 2` stderr text | **nothing asserts it today** | Which is why AC-5 is new, passes on arrival, and is the target of deferred verification 3. |
| the `exit 3` stderr text | `mutate.test.sh:132`, `assert_contains "changed nothing"` | AC-6 sits beside it and is sharper; deferred verification 5 requires the old one to stay green while the new one goes red. |

No exported signature changes, so there is no call site to update — the risk this
check exists to catch is absent here, and that is now a recorded fact rather than
an assumption.

### Independent reproduction of the baseline, by the orchestrator at PLANNED→RED

The Contract's baseline table is a **settled oracle** RED is told to read out
rather than re-derive, so it was re-measured here with a probe written from
scratch — not the PO's script — in a fresh `make_project_fixture`, `pipefail`
off, `${PIPESTATUS[0]}` captured in the same shell as the pipeline,
`.claude/state/mutations/` removed before every run:

    == P-N  s/NOT_IN_THE_FILE/x/ ==
      reader=head -0  writer=141  leftovers=[.bak .new]  loglines=0  src_ok=yes
      reader=true     writer=141  leftovers=[.bak .new]  loglines=0  src_ok=yes
      reader=head -1  writer=3    leftovers=[]           loglines=1  src_ok=yes
      reader=head -4  writer=3    leftovers=[]           loglines=1  src_ok=yes
      UNPIPED         status=3    leftovers=[]           loglines=1
           | mutate: the expression changed nothing in src/main.ts.
           |   A probe that does not alter behaviour cannot show a test discriminates:
           |   the command would have passed for the same reason it passes now. Check the
           |   expression against the file and try again.

    == P-S  s/90/-90 (unterminated) ==
      reader=head -0  writer=141  leftovers=[.bak .new .new.err]  loglines=0
      reader=true     writer=141  leftovers=[.bak .new .new.err]  loglines=0
      reader=head -1  writer=2    leftovers=[]                    loglines=0
      reader=head -4  writer=2    leftovers=[]                    loglines=0
      UNPIPED         status=2    leftovers=[]                    loglines=0
           | mutate: sed rejected the expression:
           |   sed: -e expression #1, char 8: unterminated `s' command

    == contrast: ordinary s/90/-90/ ==
      head -0 / true / head -1 / head -4   writer=141  leftovers=[]  loglines=1

Every cell matches the Contract, including the three readings the criteria rest
on: the working file is intact on both leaking paths (`src_ok=yes`), `head -1`
already hides the defect, and the ordinary path reports `writer=141` while being
completely clean.

The needle hazard was reproduced too — both expressions into one log:

    20260923T201850Z  src/main.ts  s/90/-90/            1 line(s) ... restored (verified)
    20260923T201853Z  src/main.ts  s/NOT_IN_THE_FILE/x/ CHANGED NOTHING - command not run

    anchored REJECTED_LINE  ^<STAMP>\tsrc/main\.ts\ts/90/-90(\t.*)?$   = 0   correct
    floating  grep -F 's/90/-90'                                        = 1   the false alarm
    anchored NOTHING_LINE                                               = 1   correct

So the Contract's warning is not hypothetical: a floating needle for AC-4 reports
a leak that does not exist, and the trailing `(\t.*)?$` is what prevents it.
This is the reproduction RED is expected to redo in its own suite (success
condition 3), and it is recorded here so that "1 and 0, not 1 and 1" is a
measured fact before RED starts rather than a claim checked only afterwards.

### Independent reproduction of RED's two escalations, by the orchestrator

RED returned with two claims that contradicted something written down before it
started: one against the Contract's own baseline table, one against a mechanism
named in a PO-written deferred verification. `rules.md` and the orchestrator's
standing rules require both to be reproduced on **different inputs, without
reusing the subagent's code**, before they are accepted. Both were, and both
hold. Neither changes an acceptance criterion, so this story still carries no
`## Amendments` section.

**1. The `head -1` race is real, and it is a load effect.** RED measured 5/5
clean standalone and red in 4 of 5 suite runs, which on its own is a
frequency claim with no mechanism attached. The orchestrator's probe — written
before dispatch, for the PLANNED baseline, and reused unchanged — was run idle
and then again under deliberate 6-way CPU contention:

    idle, no other load
      P-N  s/NOT_IN_THE_FILE/x/  head -1   n=40   leftovers 0/40   no-log 0/40
      P-N  s/NOT_IN_THE_FILE/x/  head -2   n=40   leftovers 0/40   no-log 0/40

    under 6-way CPU contention
      P-N  s/NOT_IN_THE_FILE/x/  head -1   n=25   leftovers 16/25  no-log 16/25
      P-S  s/90/-90              head -1   n=25   leftovers  0/25  no-log 25/25
      P-N  s/NOT_IN_THE_FILE/x/  head -4   n=15   leftovers  0/15  no-log  0/15

16 of 25 against 0 of 40 settles it: the `head -1` row is scheduling-dependent,
not settled, and RED's amendment of the baseline table is correct.

**The `head -4` row is the part that matters**, because it is RED's *mechanism*
rather than its observation, and it could have come out either way. RED said
`head -4` "cannot trip either way — it reads every line both blocks print and
then waits for EOF". Under the same contention that made `head -1` fail 64 % of
the time, `head -4` was clean 15/15. The explanation survives a test that could
have falsified it.

**One refinement the orchestrator's data adds, and GATES should have it.** The
race needs the **shell's own** second write to be the one that meets the closed
pipe. That is why `P-S` at `head -1` shows `leftovers 0/25` above while `P-N`
shows 16/25: the `exit 2` block's second write is `sed -e 's/^/  /' "$NEW.err"`,
a *child process*, so the SIGPIPE kills the child and the parent shell survives
to reach its `rm`. The `exit 3` block's four writes are all the shell's own.
So, for deferred verifications 1 and 2:

| Row | Under un-reorder | Reliable control? |
|---|---|---|
| P-N `head -0`, `true` | red | **yes** |
| P-N `head -1` | red or green, load-dependent | **no** — read `head -4` instead |
| P-N `head -4` | green | **yes** |
| P-S `head -0`, `true` | red | **yes** |
| P-S `head -1`, `head -4` | green | **yes** (not subject to the race, for the reason above) |

**2. Mutation 6's second clause was wrong.** Reproduced and corrected in place
under `## Deferred verifications`; the measurement is pasted there. The entry
was the orchestrator's own, RED probed the mechanism instead of following it,
and the mechanism did not hold.

**Verdict on the `fable` experiment — `HARNESS-012`'s verdict is confirmed a
second time.** All three success conditions in `## Model guidance` were met, and
checked against the tree rather than taken from the report:

1. `git status --short` named `.claude/tests/mutate.test.sh` and this story file
   and nothing else; `git diff --stat scripts/mutate.sh` was empty; the diff is
   **237 insertions, 0 deletions**, so nothing existing was rewritten either.
2. The handoff's control table names all three GATES mutations and declines them
   explicitly, with the assertion each must move.
3. `REJECTED_LINE` carries its trailing `(\t.*)?$`, and the demonstration is in
   the **suite** rather than only in the handoff — a block asserting 2 / 1 / 1 /
   0 against one log, plus the floating `grep -cF` at 1 to show the false alarm
   the anchor prevents.

Beyond the conditions, RED probed two written-down mechanisms and reported that
one of them did not hold. The `fable` row in `models.conf` stands for harness
stories, and no departure should be proposed on the next one without a success
condition of its own.
