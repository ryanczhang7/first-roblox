---
id: HARNESS-012
title: mutate.sh leaves a backup and no log when its output is piped
slug: mutate-sh-leaves-a-backup-and-no-log-whe
epic: 
type: fix
status: in-progress
phase: GREEN
branch: story/HARNESS-012-mutate-sh-leaves-a-backup-and-no-log-whe
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`scripts/mutate.sh` can leave a `.bak`/`.new` pair under
`.claude/state/mutations/` with **no `log` entry, after a restore that
succeeded**. That is a false alarm in a signal two documents make load-bearing:

- `.claude/harness/rules.md`: *"A `.bak` left behind under `mutations/` means a
  restore failed and `mutate.sh` exited 90 saying so; everything else it cleans
  up."*
- `.claude/state/README.md:62`: *"**A `.bak` left behind means a restore
  failed.**"*

And `.claude/tests/mutate.test.sh:116` — `describe "a restore that cannot be
verified is loud, and keeps the backup"` — is the test that makes the sentence
true. Today the tree can produce the same artefact with nothing wrong, so an
agent following the documented procedure ("put the file back from the backup,
check it with `cmp`, then delete the backup") is sent to repair a file that was
never broken, and the next agent to see a real leftover has been taught to
discount it.

**The mechanism.** The restore-and-check block at `scripts/mutate.sh:151-165` is
straight-line code in this order: `cp` the backup back (152) → `cmp` (154) →
print the verdict to **stdout** (156) → print the restored lines to **stdout**
(157-160) → append to the log (161) → `rm -f "$NEW" "$BAK"` (163) → `exit`. When
the caller closes the pipe early — `bash scripts/mutate.sh ... | head -30` is how
it was hit — SIGPIPE kills the shell at one of the two stdout writes: **after**
the restore, **before** the log and the cleanup. The `trap on_exit EXIT INT TERM`
at line 145 still fires, which is why the tree is left correct; it restores and
does nothing else.

**How it was found.** `NET-003` GREEN, 2026-09-22, left
`.claude/state/mutations/src_net_Wrapper.luau.20260922T165540Z.3977788.{bak,new}`
with no `log` line for that timestamp. `cmp` showed the `.bak` byte-identical to
the working `src/net/Wrapper.luau`, `git diff` showed only the intended change,
and the suite was green. Recorded under `NET-003`'s `## Notes`; nothing under
`.claude/state/**` is committed, so there is no artefact of it in git.

**The gate that would fail if this story's artifact broke.** None — and that is a
fact about this repository rather than an omission to fix here. Every gate in
`project.conf` judges the Luau project (`src`, `tests`, `lune`); the one called
`harness` runs `.claude/tests/project-counters.test.sh` and nothing else.
`bash scripts/classify.sh` reports both files this story touches as `harness`,
not `source`, so `gates.sh`'s `covers` check does not bite either. What binds
this story is `.github/workflows/gates.yml:108` — `run: bash scripts/selftest.sh`
— which runs every suite in `.claude/tests/`, this story's included. See PO
decision 2 in `## Notes` for why `required_gates` stays `[]` rather than growing
a new gate.

## Acceptance criteria

The reproduction is AC-1 through AC-3, measured in a `make_project_fixture`
repository against `src/main.ts` holding
`export const clamp = (v) => Math.min(90, v)` and the expression `s/90/-90/`,
invoked as `bash scripts/mutate.sh src/main.ts 's/90/-90/' -- <command> 2>&1 |
head -N`. `2>&1` is deliberate and is the shape an agent actually writes; it is
also what keeps these criteria exercising SIGPIPE after AC-6 moves the banners
(see the Contract).

- **AC-1** — Given a mutation run whose output is piped into a reader that closes
  the pipe early, when `mutate.sh` has returned, then no `.bak` and no `.new`
  file remains under `.claude/state/mutations/`. Holds for **every** pipe width
  `N` in `1 2 3 4 5 6 30`, not one chosen width: where the pipe closes decides
  which line dies, and the post-condition must not depend on it.
  *Fails today at N ≤ 5* — measured below.

- **AC-2** — Same run, same widths: `.claude/state/mutations/log` gains
  **exactly one** line for that run, and that line names the file (`src/main.ts`)
  and the expression (`s/90/-90/`). Exactly one, counted — not "at least one".
  Both the normal path and the new trap can reach the append, and a fix that
  logs twice has replaced a missing record with a lying one.
  *Fails today at N ≤ 5*: the log file does not exist at all.

- **AC-3** — Same run, same widths: `src/main.ts` is byte-identical to its
  content before the run (`git hash-object`), whatever the pipe did.
  *Passes today* at every width — this is the one property the existing
  `on_exit` trap already delivers, and it is written down so that a fix which
  restructures the restore cannot quietly lose it.

- **AC-4** — Given a run whose restore cannot be verified — the existing case,
  provoked by `-- sh -c 'rm -f .claude/state/mutations/*.bak'` — when
  `mutate.sh` returns, then it still exits **90**, still prints
  `COULD NOT RESTORE`, and the `.bak` (when one survives) is still **kept**,
  not cleaned up. *Passes today.* This is the **negative control on the fix
  itself**: an unconditional `rm -f "$NEW" "$BAK"` in an EXIT trap satisfies
  AC-1 and AC-2 completely and destroys the only signal the harness has for a
  failed restore. If AC-4 cannot be made to fail by that mutation, the suite is
  not discriminating (see `## Deferred verifications`).

- **AC-5** — Given an ordinary unpiped run that succeeds, when it returns, then
  the log gains exactly one line, ending in the outcome field
  `restored (verified)`, and no `.bak`/`.new` remains — i.e. the fix changes
  nothing about the path that already worked. *Passes today.*

- **AC-6** — Given any run, when its stdout is inspected on its own
  (`2>/dev/null`), then stdout contains **none** of `mutate.sh`'s own
  `=== mutate: ` banner, diff, verdict or restored-line output, and contains
  the mutated command's own output unchanged. Every status line goes to stderr.
  *Fails today*: all of it is on stdout. See PO decision 1 in `## Notes` for
  why this is in the story rather than deferred, and what it costs.

## Contract

Written before RED. **RED may amend any block in place, with a reason**, and
GREEN builds what the amended block says.

### Files

| Path | `classify.sh` says | Who writes it |
|---|---|---|
| `scripts/mutate.sh` | `harness` | GREEN |
| `.claude/tests/mutate.test.sh` | `harness` | RED |

**Both classify as `harness`, so the phase lock permits writing either of them in
every phase.** Nothing will stop RED editing `mutate.sh`, or GREEN editing the
frozen test file. The law still applies in full (`CLAUDE.md` laws 1 and 2); here
it is honoured by the agents rather than enforced by the hook. Say so in the
handoff.

### The command that runs these tests

    bash scripts/selftest.sh mutate

One suite, seconds. `bash scripts/selftest.sh` with no argument runs all of them
and takes 10-25 minutes on this machine — do not use it as the inner loop.

### The shape of the fix

Observable behaviour is the contract; the structure below is the intended shape
and GREEN may deviate if it can hold all six criteria.

1. **One `EXIT INT TERM` trap, installed before the first write to any output
   stream** — i.e. before the banner at `mutate.sh:135`, immediately after `$NEW`
   survives the "changed nothing" check at line 127. Today's trap is installed at
   line 145, which is already too late: at `head -1` the shell dies at line 135,
   before the file is even mutated, and leaks the `.bak`/`.new` pair anyway. It
   replaces the present `on_exit`; there is exactly one trap when GREEN is done.

2. **Inside the trap, the file operations come first and the printing comes
   last.** Restore → `cmp` → append the log → clean up **only if the restore
   verified** → *then* print. This ordering is the fix, not a style: if the
   trap prints before it cleans up, and the stream it prints to is the closed
   one, the trap dies exactly where the straight-line code dies today and the
   bug is reproduced inside its own fix. Nothing before the printing writes to
   stdout or stderr.

3. **The log is appended exactly once** (AC-2). A flag the trap checks, or a
   single append that only the trap performs — not both a straight-line append
   and a trap append.

4. **Cleanup stays conditional on a verified restore** (AC-4). `rm -f "$NEW"
   "$BAK"` runs only on the verified path; the unverified path keeps the `.bak`,
   removes the `.new`, and exits 90, exactly as lines 167-179 do now.

5. **Exit statuses are unchanged**: 2 usage, 3 changed-nothing, 90 unverified
   restore, otherwise the command's own. A run killed by SIGPIPE dies by signal
   and `mutate.sh` cannot choose its own status — that is the caller's problem
   and is out of scope.

### The log line

Three tab-separated leading fields in every case, as today: `STAMP`, `REL`,
`EXPR`. The final outcome field is one of:

| Case | Outcome field |
|---|---|
| command completed, restore verified | `restored (verified)` — unchanged |
| command completed, restore unverified | `COULD NOT RESTORE` — unchanged |
| run died before the command completed | `INTERRUPTED` + tab + one of `restored (verified)`, `COULD NOT RESTORE`, `not mutated` |

The third row is new and is what makes AC-2 satisfiable at `N = 1`, where the
command never runs at all. `not mutated` covers a death before line 139, where
the working file was never touched. AC-2 asserts only the first three fields, so
RED may amend this table's wording without touching a criterion.

### Streams (AC-6)

- **stdout**: the mutated command's own output, and nothing else.
- **stderr**: every `=== mutate: ... ===` banner, the diff lines, the
  `running <cmd>` line, the verdict, the restored lines, and all existing error
  output.

**Callers that read `mutate.sh`'s output — the whole list, grepped.**
`.claude/tests/mutate.test.sh` is the only one. Its `mutate()` helper at line 30
is `( cd "$FIX" && bash scripts/mutate.sh "$@" 2>&1 )`, and the two invocations
that bypass it (lines 62, 152, 169) use `>/dev/null 2>&1`. So every existing
assertion reads the merged stream and is unaffected by AC-6 — **RED confirms
that by running the suite, rather than taking this paragraph's word for it.**
`.claude/hooks/lib.sh`, `.claude/hooks/phase-guard.sh`,
`.claude/tests/lib.test.sh` and `.claude/tests/phase-guard.test.sh` reference
`mutate.sh` as a *command string* the guard must recognise; none of them runs it
or reads its output. No signature and no CLI argument changes, so there is no
caller list beyond this.

### The test the story adds

A new `describe` block in `.claude/tests/mutate.test.sh`, sweeping the pipe
widths in AC-1. Three things about its shape, because the existing helpers
cannot express it:

- **The suite's `mutate()` helper cannot be used.** It is a command substitution,
  which never closes the pipe early. The new case needs its own invocation.
- **Read `mutate.sh`'s own status with `${PIPESTATUS[0]}`, in the same shell as
  the pipeline.** The pipeline's `$?` is the *reader's*, and `head` exits 0 —
  measured below. `PIPESTATUS` evaluated outside a subshell that contains the
  pipeline reports the subshell, not `mutate.sh`; that mistake was made while
  writing this story and it reported `0` for a run that died of SIGPIPE.
- The assertion needles must be anchored (`rules.md`, "an assertion's needle is
  part of the assertion"). AC-2 is a **count** — `grep -c` on a line naming both
  the file and the expression, asserted `= 1` with `assert_eq`, never
  `assert_contains` on the log's text, which is satisfied by two lines as
  happily as by one.

Helpers available: `make_project_fixture`, `describe`, `assert_eq`,
`assert_contains`, `_ok`, `_bad`, `summary`, `set_phase` (`.claude/tests/_lib.sh`).
No new dependency of any kind: bash, git and coreutils only, which is the
standing constraint on every suite in `.claude/tests/`.

### Baseline measurements the story may read out

Measured by the Lead PO at PLANNED on this machine, 2026-09-22, bash 5.3.15(2)
(cygwin), in a `make_project_fixture` repository, `touch ran-marker` as the
payload so that "did the command run" is observable:

    2>&1 | head -N     log written    command ran    .bak left
    N = 1              no             NO             yes
    N = 2              no             NO             yes
    N = 3              no             NO             yes
    N = 4              no             yes            yes
    N = 5              no             yes            yes
    N = 6              yes            yes            no
    N = 7, 8, 10, 30   yes            yes            no

    2>/dev/null | head -N (stdout only): same cut, command never runs at N = 1.

    In every one of those runs, src/main.ts came back byte-identical.

Two readings of that table matter and both are in the criteria:

- **The leftover pair is produced by a run whose restore succeeded.** AC-1/AC-3.
- **At `N ≤ 3` the probe never ran and the pipeline reported 0.** `head` exits 0,
  and `mutate.sh`'s SIGPIPE status (141 = 128+13) is swallowed by the pipe unless
  the caller reads `PIPESTATUS[0]` or has `pipefail` set. An agent piping a
  mutation into `head` can be handed a clean exit for a probe that did not
  happen — the "instrument reading it" hazard in `rules.md`, with the instrument
  being one line of shell. This story cannot fix the exit status (see
  `## Out of scope`); AC-6 removes the common way to trip over it, and the
  header comment records the rest.

### Oracle partition of the criteria

| Criteria | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-3 | **Settled** — the table above was measured; the widths and the expected today-values are given | Read them out. Do not re-derive the cut, do not "calibrate" a width. Assert the post-condition at every listed width. |
| AC-4, AC-5 | **Mechanical** — an existing contract this story must not break | Pin exactly. AC-4 already has a test at `mutate.test.sh:116`; extend or sit beside it, do not rewrite it. |
| AC-6 | **Mechanical** — a stream split | Pin exactly: stdout is asserted to contain the command's output and to contain no `=== mutate: `. Anchor both halves; "stdout is empty" is the wrong assertion, because the command's own output belongs there. |

Nothing here is oracle-free: there is no metric to invent. The one place a
blind assertion could hide is AC-2's count, which is why it is a count.

## Deferred verifications

**The negative control on the fix's shape.** With the cleanup in GREEN's EXIT
trap made **unconditional** — `rm -f "$NEW" "$BAK"` on every path, not only the
verified one — AC-4's assertions **must** go red: the `.bak` would be deleted
after a restore that could not be verified, and the harness's one signal for a
failed restore would be gone while AC-1 and AC-2 stayed green. A fix that
satisfies this story and cannot be caught doing that has not been verified.

**Why RED cannot run it.** There is no trap to make unconditional in RED; the
code being mutated is what GREEN is about to write.

**Owner: GATES.**

One workable recipe, written down because `mutate.sh` refuses to mutate itself
(`scripts/mutate.sh:93`) and the obvious invocation therefore exits 2:

    cp scripts/mutate.sh scripts/__mutate_probe_copy.sh
    bash scripts/__mutate_probe_copy.sh scripts/mutate.sh \
      '<expression making the cleanup unconditional>' \
      -- bash scripts/selftest.sh mutate
    rm -f scripts/__mutate_probe_copy.sh

The *running* script is the copy and the *target* is the real one, which is what
the self-check permits; the copy lives under `scripts/` so that its `ROOT`
resolves to the repository root. Delete the copy afterwards and confirm
`git status` is clean — a stray `scripts/__mutate_probe_copy.sh` is a file CI
would carry. GATES may use any other recipe that restores the file and proves it.

Paste the result here: the expression, the red, and the restore.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-012` from `.claude/harness/models.conf`.
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

**Departure: RED runs on `opus`, not the planned `fable`.**

The `unenforced` exception in `models.conf` is written for exactly this story —
"the lock freezes none of the paths this story names, so the contract is not an
aid to the model here, it is the only enforcement there is" — and it did not
fire. It did not fire because `plan.sh`'s `contract_unenforced` greps *every*
path-shaped token out of the `## Contract` section, and this contract mentions
`src/main.ts`: the fixture file inside a throwaway `make_project_fixture`
repository, which this story never writes and which no phase of it can touch.
One `source`-classified mention is enough to suppress the exception, and the
suppression falls on the weak side rather than the safe one.

The fact the departure rests on is checkable and was checked:

    $ bash scripts/classify.sh scripts/mutate.sh .claude/tests/mutate.test.sh
    harness scripts/mutate.sh
    harness .claude/tests/mutate.test.sh

Both paths this story actually writes are `harness`, so the phase lock will
permit RED to rewrite `scripts/mutate.sh` and GREEN to rewrite the frozen test
file. Nothing but the agents' own discipline separates the test from the fix,
which is the condition the exception names.

**Success condition, and it can come out either way.** RED on `opus` must end
with `git status --short` naming `.claude/tests/mutate.test.sh` and this story
file and nothing else — in particular `git diff --stat scripts/mutate.sh` empty
— and a handoff whose control table names AC-4's unconditional-cleanup mutation
as the control on the fix's shape. If it delivers that, the departure bought
nothing observable and the next harness-only story should take the `fable` row
and save the cost. If RED edits `scripts/mutate.sh`, or hands GREEN a fix
disguised as a test, the exception's intent is confirmed and the right repair is
`plan.sh`'s detector, not this story's model row. Record the verdict here when
RED ends.

The oracle partition for RED is in `## Contract`, "Oracle partition of the
criteria" — carry it into the dispatch prompt verbatim; it is the half of the
brief that was measured to matter more than the model.

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

- **Anything about `mutate.sh`'s exit status through a pipe.** A shell killed by
  SIGPIPE cannot choose what `head` reports, and no change inside `mutate.sh`
  can make `mutate ... | head -1` exit non-zero. The documentation half is in
  scope — the header comment gains a line saying to capture with `2>&1` and read
  `${PIPESTATUS[0]}` — the behaviour is not.
- **Redesigning the output format.** The banner text, the diff rendering, the
  `head -20` cap on the diff, the changed-line count, the restored-line listing:
  all unchanged. AC-6 moves which *stream* they go to and nothing else.
- **The exit-code contract**: 2, 3, 90 and pass-through stay exactly as they are.
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

## Test plan

**Level.** Shell integration, and there is no cheaper level that can falsify any
of this. The subject is what a *process* leaves on disk when a signal kills it
mid-function; there is no unit beneath "a process, a pipe and a reader that stops
reading". Every case runs the real `scripts/mutate.sh` inside a throwaway
`make_project_fixture` repository, against `src/main.ts` holding
`export const clamp = (v) => Math.min(90, v)` and the expression `s/90/-90/`,
exactly as the Contract specifies.

**Blocks, and which criterion each one carries.** All in
`.claude/tests/mutate.test.sh`.

| Block (`describe`) | AC | What it asserts |
|---|---|---|
| `a reader that closes the pipe early leaves no backup, and logs once` (new) | AC-1, AC-2, AC-3 | Swept over `N` in `1 2 3 4 5 6 30`: no `.bak`/`.new` survives; exactly one anchored log line names `src/main.ts` and `s/90/-90/`; `git hash-object src/main.ts` is unchanged |
| `the sweep above really does close the pipe early` (new) | instrument | `head -1` lets exactly one line through, and an untruncated run of the same command is longer than one line |
| `an ordinary unpiped run still logs once and cleans up` (new) | AC-5 | Exactly one anchored log line; exactly one whose final field is `restored (verified)`; no leftovers; file byte-identical |
| `stdout is the command's output; mutate.sh's own goes to stderr` (new) | AC-6 | stdout contains the payload, contains zero `=== mutate: ` banners, and equals the payload exactly; stderr contains the banner, the verdict and the restored line |
| `a restore that cannot be verified is loud, and keeps the backup` (extended in place) | AC-4 | The two existing assertions untouched, plus a second provocation in which the backup **survives**: exit 90, `COULD NOT RESTORE`, `.bak` count 1, `.new` count 0 |

**Why AC-4 had to be extended rather than only re-read.** The existing case
provokes the unverified restore with `rm -f .claude/state/mutations/*.bak`, so
the backup is destroyed by the command itself and "the `.bak` is kept" is
unassertable there - measured: zero `.bak` files after that run. The story's
`## Deferred verifications` requires that an *unconditional* cleanup in GREEN's
EXIT trap turn AC-4 red, and neither existing assertion moves under that
mutation: exit 90 and the `COULD NOT RESTORE` message both survive it. So a
second provocation sits beside the first - the command replaces `src/main.ts`
with a *directory*, so the restoring `cp` lands inside it, `cmp` cannot verify,
and the backup is still on disk to be kept or deleted. Without it the deferred
verification could not have gone red and the suite would not have been
discriminating. The original block's lines are unchanged.

**Why the sweep needs its own invocation shape.** The suite's `mutate()` helper
is a command substitution, which reads to EOF and never closes the pipe early.
`piped_run <N> <command...>` runs `bash scripts/mutate.sh ... 2>&1 | head -N`
and reads `${PIPESTATUS[0]}` *in the same shell as the pipeline*, writing it to a
file so the value survives the command substitution. `2>&1` is deliberate: it is
the shape an agent writes, and it is what keeps these cases exercising SIGPIPE
after AC-6 moves the banners to stderr.

**Anchoring.** The log needle is a two-end-anchored ERE over the three
tab-separated leading fields every log line carries -
`^[0-9]{8}T[0-9]{6}Z<TAB>src/main\.ts<TAB>s/90/-90/(<TAB>.*)?$` - and it is
**counted** with `grep -cE` and compared with `assert_eq` to `1`.
`assert_contains` on the log's text would be satisfied by two lines as happily as
by one, and a fix that logs twice has replaced a missing record with a lying one.
The AC-6 absence assertion (zero banners on stdout) is paired with two positive
ones in the same case - the payload is on stdout, the banner and verdict are on
stderr - so it cannot be satisfied by a `mutate.sh` that prints nothing anywhere.

**Out of scope, honoured.** `mutate.sh`'s exit status through a pipe is recorded
(`PIPED_ST`) and deliberately **not** asserted: a shell killed by SIGPIPE cannot
choose what `head` reports. No assertion re-derives the width at which the cut
falls, and none touches the banner text, the diff rendering, the `head -20` diff
cap, the changed-line count or the exit-code contract.

## Handoff: RED -> GREEN

### The command

    bash scripts/selftest.sh mutate

146 s on this machine (Windows, cygwin bash 5.3.15(2)); 55 s before this change,
measured by running `git show HEAD:.claude/tests/mutate.test.sh` from a temporary
copy. Do **not** run `bash scripts/selftest.sh` with no argument as an inner
loop: it runs all 16 suites, takes 10-25 minutes here, and two overlapping runs
corrupt each other.

### The verbatim failure output

Captured from `bash scripts/selftest.sh mutate` on 2026-09-22, exit 1. The run
reproduces identically; the `.bak` filenames carry the stamp of the run shown.

```
=== mutate ===

  the command sees the mutation

  a failing command is the point, not an error

  a mutation that mutates nothing proves nothing

  how much it changed is reported, because one line is the useful case

  usage errors happen before anything is touched

  a restore that cannot be verified is loud, and keeps the backup

  it refuses to mutate the script that is running

  the log is what the story quotes

  it works with the phase lock on, in every phase

  a reader that closes the pipe early leaves no backup, and logs once
    FAIL N=1: no .bak or .new is left behind
         expected: 
         actual:   src_main.ts.20260922T192040Z.127184.bak src_main.ts.20260922T192040Z.127184.new 
    FAIL N=1: exactly one log line names the run
         expected: 1
         actual:   0
    FAIL N=2: no .bak or .new is left behind
         expected: 
         actual:   src_main.ts.20260922T192044Z.127482.bak src_main.ts.20260922T192044Z.127482.new 
    FAIL N=2: exactly one log line names the run
         expected: 1
         actual:   0
    FAIL N=3: no .bak or .new is left behind
         expected: 
         actual:   src_main.ts.20260922T192050Z.127799.bak src_main.ts.20260922T192050Z.127799.new 
    FAIL N=3: exactly one log line names the run
         expected: 1
         actual:   0
    FAIL N=4: no .bak or .new is left behind
         expected: 
         actual:   src_main.ts.20260922T192052Z.128101.bak src_main.ts.20260922T192052Z.128101.new 
    FAIL N=4: exactly one log line names the run
         expected: 1
         actual:   0
    FAIL N=5: no .bak or .new is left behind
         expected: 
         actual:   src_main.ts.20260922T192057Z.128441.bak src_main.ts.20260922T192057Z.128441.new 
    FAIL N=5: exactly one log line names the run
         expected: 1
         actual:   0

  the sweep above really does close the pipe early

  an ordinary unpiped run still logs once and cleans up

  stdout is the command's output; mutate.sh's own goes to stderr
    FAIL and no === mutate: banner is
         expected: 0
         actual:   3
    FAIL and nothing else is either
         expected: PAYLOAD-ON-STDOUT
         actual:   === mutate: src/main.ts (1 line(s) changed by s/90/-90/) ===
           1 - export const clamp = (v) => Math.min(90, v)
           1 + export const clamp = (v) => Math.min(-90, v)
         
         === mutate: running sh -c echo PAYLOAD-ON-STDOUT ===
         PAYLOAD-ON-STDOUT
         
         === mutate: command exited 0; restored (verified byte-for-byte against /tmp/tmp.WaIYoyYSe4/.claude/state/mutations/src_main.ts.20260922T192139Z.130854.bak) ===
           1: export const clamp = (v) => Math.min(90, v)
    FAIL the banner is on stderr
         expected to contain: === mutate: 
         actual:               
    FAIL and so is the verdict
         expected to contain: restored (verified byte-for-byte
         actual:               
    FAIL and so is the line put back
         expected to contain: Math.min(90, v)
         actual:               

mutate: 61 passed, 15 failed

1 of 1 harness suite(s) FAILED.
```

15 red, 61 green. The 39 assertions that existed before this story all still
pass, which settles the Contract's claim that AC-6 breaks no existing caller:
every one of them reads the merged stream through `mutate()` or discards both
streams, so moving the banners cannot move them. RED confirmed that by running
the suite rather than by taking the paragraph's word for it.

### One line per assertion, and which AC it covers

New, in `a reader that closes the pipe early leaves no backup, and logs once`
(21 assertions, three per width `N` in `1 2 3 4 5 6 30`):

- `N=$n: no .bak or .new is left behind` - **AC-1**. Lists the names of any
  `*.bak`/`*.new` under `.claude/state/mutations/` after the run; expects none.
- `N=$n: exactly one log line names the run` - **AC-2**. `grep -cE` of the
  two-end-anchored stamp/file/expression line, compared to `1`.
- `N=$n: src/main.ts is byte-identical after` - **AC-3**. `git hash-object`
  before and after.

New, in `the sweep above really does close the pipe early` (2):

- `head -1 lets exactly one line through` - the **instrument**, not the subject.
  If `piped_run` ever stopped truncating, all 21 sweep assertions would keep
  passing and would have stopped testing anything.
- `and an untruncated run of the same command is longer than that` - the other
  half; without it, a `mutate.sh` that printed one line would satisfy the first.

New, in `an ordinary unpiped run still logs once and cleans up` (4): **AC-5** -
one anchored log line; one whose final field is `restored (verified)`; no
leftovers; file byte-identical.

New, in `stdout is the command's output; mutate.sh's own goes to stderr` (6):
**AC-6** - payload present on stdout; zero `=== mutate: ` on stdout; stdout
equals the payload exactly (the Contract's "and nothing else"); banner, verdict
and restored line present on stderr.

Added to the existing `a restore that cannot be verified is loud, and keeps the
backup` (4): **AC-4** - exit 90, `COULD NOT RESTORE`, `.bak` count 1, `.new`
count 0, under a provocation the backup survives.

### Files touched

- `.claude/tests/mutate.test.sh` - the only code file. +177 lines; no existing
  line modified or deleted.
- `docs/backlog/stories/HARNESS-012.md` - `## Test plan`,
  `## Handoff: RED -> GREEN` and `## Regressions` only.

`git diff --stat scripts/mutate.sh` is **empty**. Both files classify as
`harness`, so the phase lock permitted RED to edit `scripts/mutate.sh` and would
not have stopped it; the separation here is the agent's discipline, not the
hook's, and this line is the record the Contract asked for.

### The shape these tests already pin, as fact

A test already exercises each of these, so a GREEN that contradicts one fails
rather than merely disagreeing.

**Invocation.** `bash scripts/mutate.sh <FILE> '<SED-EXPR>' -- <command> [args]`,
with `$ROOT` the repository root, the command executed from `$ROOT`, and file
paths resolved against `$ROOT`. Unchanged; no argument added or removed.

**Artefacts.** The backup and working copy live under
`$ROOT/.claude/state/mutations/` and end in `.bak` and `.new`. The tests delete
that whole directory before each case, so `mutate.sh` must still create it
(`mkdir -p`) before writing anything into it - including before appending the log
on the interrupted path.

**The log.** `$ROOT/.claude/state/mutations/log`, appended. Every line begins
with exactly three tab-separated fields, in this order:
`<STAMP><TAB><REL><TAB><EXPR><TAB>...`, where `STAMP` matches
`[0-9]{8}T[0-9]{6}Z`, `REL` is the path as given on the command line
(`src/main.ts`, not absolute) and `EXPR` is the expression verbatim
(`s/90/-90/`). The tests match `^STAMP<TAB>REL<TAB>EXPR` and allow any tail or
none, so the `INTERRUPTED` row of the Contract's table is free in its wording.
One line per run - not two. The verified-completion line must still **end** with
the field `restored (verified)`; nothing else about that line is pinned beyond
the three leading fields.

**Streams.** stdout carries the mutated command's output and nothing else - the
AC-6 case asserts exact equality with the payload. stderr carries the
`=== mutate: ` banners, the verdict text beginning `restored (verified
byte-for-byte`, and the restored source line. `COULD NOT RESTORE` is asserted
only through the *merged* stream, so it stays where it already is.

**Exit codes.** 2 usage, 3 changed-nothing, 90 unverified restore, otherwise the
command's own - all still asserted by the pre-existing blocks, which are frozen
from here.

**Not constrained, and therefore GREEN's choice.** How the trap is written and
what it is called; whether the "already logged" flag is a variable or a marker
file; the wording of the `INTERRUPTED` outcome field; where in the line the
changed-line count and the command go; the order of the stderr lines; whether the
diff still goes through `head -20`; and whether `mutate.sh` gains the
header-comment line about `2>&1` and `${PIPESTATUS[0]}` (the Contract says it
should; no test reads it).

### Which assertions were observed red, and which were green on arrival

`scripts/mutate.sh` already exists, so this is **not** an ordinary RED where the
implementation is absent. Stated plainly:

| Assertions | AC | Status in RED |
|---|---|---|
| 10 of the 21 sweep assertions (`N <= 5`, AC-1 and AC-2) | AC-1, AC-2 | **Observed red.** The bug, reproduced. |
| 5 of the 6 stream assertions | AC-6 | **Observed red.** |
| 7 sweep assertions (one per width, AC-3) | AC-3 | **Green from the start.** Today's `on_exit` trap already restores; written down so a restructured fix cannot lose it. |
| 4 sweep assertions (`N = 6, 30`, AC-1 and AC-2) | AC-1, AC-2 | **Green from the start.** The widths where nothing truncates. |
| 4 AC-4 assertions | AC-4 | **Green from the start.** The contract the fix must not break. |
| 4 AC-5 assertions | AC-5 | **Green from the start.** |
| 1 of the 6 stream assertions (payload on stdout) | AC-6 | **Green from the start.** Today the payload is on stdout along with everything else. |
| 2 instrument assertions | - | **Green from the start.** They pin the test's own apparatus. |

The green-from-the-start ones carry **no evidence yet**. They were not earned
with a mutation of `scripts/mutate.sh`, deliberately: the story assigns that to
GATES as a deferred verification, and mutating the file RED is forbidden to write
would have muddied the RED diff. GREEN and GATES should treat them as unproven
regression guards until the deferred control runs.

One thing this RED does **not** inherit from the usual one: the suite is bash and
nothing was missing, so it did **not** fail at import. All 76 assertions
executed, and every number in the control table below was measured by the
framework rather than claimed outside it - with the single exception marked as
GATES's.

### Negative controls, with their measured values

| Control | Guards against | Expected | Measured in RED |
|---|---|---|---|
| `.bak` count after an unverifiable restore (directory provocation) | An unconditional `rm -f "$NEW" "$BAK"` in GREEN's EXIT trap | `1` | `1` |
| `.new` count in the same run | The unverified path keeping the wrong file | `0` | `0` |
| Anchored log-line count in the sweep | An absence assertion passing because the run never happened | `1` per run | `0` at `N <= 5`, `1` at `N = 6, 30` |
| `lines_in "$PIPED_OUT"` at `N = 1` | `piped_run` silently ceasing to truncate | `1` | `1` |
| Lines in an untruncated `-- true` run | The row above passing on a `mutate.sh` that prints one line | `> 1` | `8` |
| `=== mutate: ` count on stdout | - | `0` | `3` |
| Banner, verdict and restored line on stderr | A fix that satisfies AC-6 by printing nothing anywhere | present | **absent** - all three red today |
| `${PIPESTATUS[0]}` of the piped run (recorded, never asserted) | Reading the pipeline's `$?`, which is `head`'s | - | `141` at `N = 1..5`, `0` at `N = 6, 30`; the pipeline's own `$?` is `0` at every width |

The first two rows are the control the story's `## Deferred verifications`
names. They are **green today and must go red under GATES's mutation**; if they
do not, the suite is not discriminating and the fix has not been verified.

### Declined: the deferred verification is GATES's, not RED's

**I did not run the unconditional-cleanup control, and I am not claiming it.**
There is no EXIT trap to make unconditional yet - the code being mutated is what
GREEN is about to write. The story assigns it to GATES and it stays there.

What RED did contribute is the only thing that makes it *runnable*: the two
`.bak`/`.new` count assertions above, without which the mutation the story
describes turns nothing red. GATES should expect the failure to read

    FAIL and the backup is KEPT, which is what rules.md reads as the signal
         expected: 1
         actual:   0

in the block `a restore that cannot be verified is loud, and keeps the backup`,
and nowhere else.

### What GREEN should know before starting

- **The restore must COPY the backup back, not move it.** The AC-4 directory
  provocation leaves `src/main.ts` as a directory, so `cp "$BAK" "$FILE"` lands
  *inside* it; a `mv` would consume the backup and turn "the backup is KEPT" red
  for a reason that has nothing to do with the cleanup.
- **The interrupted path must log even when the command never ran.** Measured: at
  `N <= 3` the payload (`touch ran-marker`) never executes, because the shell
  dies at the banner before `cp "$NEW" "$FILE"`. AC-2 still demands one log line
  there, which is what the Contract's `INTERRUPTED ... not mutated` row is for.
- **The trap must create `.claude/state/mutations/` itself.** Every sweep
  iteration deletes the directory first.
- **Nothing before the printing may write to either stream.** The tests will
  reproduce the bug inside the fix if the trap prints before it logs and cleans
  up: `2>&1` merges both streams into the same closed pipe, so moving a write to
  stderr does not by itself make it safe.
- **Cost.** The suite went from 55 s to 146 s on this machine, all of it in the
  seven extra `mutate.sh` processes - roughly 9 s per invocation here, which is
  process-spawn cost on Windows. On CI it is cheap: `gates.yml` runs
  `selftest.sh` on `ubuntu-latest` and records 31 s for **all** suites there
  against 21-27 min on `windows-latest`, so the same seven processes should cost
  a couple of seconds. The 146 s and 55 s are local measurements I took; the CI
  figure is the workflow file's own recorded measurement, not one I ran. That job
  has no `timeout-minutes`.
- **No gate judges this file.** `bash scripts/gates.sh --fast` is fully green
  with these tests red - `format`, `lint`, `typecheck`, `unit`, `build` and
  `harness` all PASS, `coverage` UNCONFIGURED - because every gate judges the
  Luau project and `harness` runs only `project-counters.test.sh`. That is PO
  decision 2, confirmed rather than assumed: the shape of the RED failure lives
  in `selftest.sh`, which CI runs as its own step, not in any gate. Nothing in
  the new test file trips a lint rule or a timeout, so the tests are admissible
  to everything that will judge them.

### Contract amendments

None. Every block of `## Contract` was buildable as written, and nothing in it
contradicted what I measured. The baseline table was re-measured before being
read out and reproduced exactly - no log line and a leftover pair at `N <= 5`,
both clean at `N = 6` and `30`, `src/main.ts` byte-identical at every width, the
command not running at `N <= 3`, `${PIPESTATUS[0]}` = 141 where the shell died.

The one place I went beyond the Contract's "The test the story adds" - which
describes a single new `describe` block - is the AC-4 extension and the AC-5 and
AC-6 blocks. Those are required by the criteria rather than a change to them, so
they are recorded here instead of as an amendment.

## Regressions

<!-- Empty by design, and this is not an omission. `## Regressions` records a
     test corrected on a RETURN from GREEN or GATES, earned with a reverted
     mutation. HARNESS-012 is in its first RED and has never left it: no test
     was corrected, no production behaviour was mutated, and `scripts/mutate.sh`
     is untouched. The evidence for this phase is the verbatim failure output in
     `## Handoff: RED -> GREEN` above.

     The assertions that were green on arrival are listed there too, together
     with the control that will earn them - the unconditional-cleanup mutation
     the story assigns to GATES under `## Deferred verifications`. -->

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-22T20:03:00Z
    commit: 97deb03 (working tree had uncommitted changes)
    tree:   ce1cc65bc181a038267412ef20fc97efbff80fdc
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 79)
    PASS         lint (1s, observed 79, floor 1)
    PASS         typecheck (3s, observed 16)
    PASS         unit (40s, observed 355, floor 355)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 47816)
    PASS         harness (25s, observed 40)
    UNCONFIGURED mutation

## Notes

### PO decisions made at PLANNED

**PO decision 1 — the banners move to stderr (AC-6), in this story rather than a
later one, and the cost is recorded.** The brief asked for a deliberate decision
either way. In favour: stdout then means exactly one thing, the mutated
command's own output; and `mutate ... | head -30`, the idiom that produced this
bug, stops being able to kill `mutate.sh` at all, including the `N ≤ 3` case
where the probe never ran and the caller saw 0. Against, and this is real: an
agent capturing evidence with `> out.txt` would no longer capture the
`restored (verified)` verdict that `## Regressions` and `## Gate probes` are
meant to show. Decided on the observed usage — mutations in this repository are
run through the Bash tool, whose transcript carries both streams, and the failure
actually seen was a pipe, not a redirect — and mitigated by the header-comment
line in `## Out of scope`. **AC-6 is not sufficient on its own**, which is why it
is not the whole fix: `2>&1 | head -N` puts both streams down one pipe and
reproduces the SIGPIPE exactly, so the trap in the Contract is required
regardless. Reversing this decision later costs one commit and no test rewrite,
since every existing assertion reads the merged stream.

**PO decision 2 — `required_gates` stays `[]`, and no gate is added.** The rule
in `story-authoring` is to name the required gate that would fail if the story's
artifact broke, and to fix it here if the answer is "none or an optional one".
The answer here is "none", and the fix is not available cheaply: every gate in
`project.conf` judges the Luau project, `harness` runs only
`project-counters.test.sh`, and `required_gates` can only name a gate that
exists. What does run this story's artifact is
`.github/workflows/gates.yml:108`, `bash scripts/selftest.sh`, on every PR — so
the criteria are not unexercised, they are exercised by a CI step rather than by
a gate id. The `covers` check in `gates.sh` does not fire either, because
`bash scripts/classify.sh scripts/mutate.sh .claude/tests/mutate.test.sh`
reports both as `harness`, not `source`. Recorded so that a reader does not
mistake the empty `required_gates` for nobody having asked.

**PO decision 3 — AC-1 and AC-2 sweep seven pipe widths rather than pinning
one.** A single width is a test of where SIGPIPE happened to land in one
version of the output; the invariant the harness actually needs is that the
post-condition does not depend on that. The sweep also keeps the case alive
after AC-6 moves the banners and the line numbering shifts underneath it.

**PO decision 4 — the criteria were not changed after this file was written, so
this story carries no `## Amendments` section.** If one turns out to be wrong,
that is where it goes, after the orchestrator reproduces the finding on its own
inputs.

### Reproduction, by the Lead PO at PLANNED

The table in the Contract is this repository's own, not the brief's: built with
`make_project_fixture` from `.claude/tests/_lib.sh`, `touch ran-marker` as the
payload, `.claude/state/mutations/` removed between runs, `pipefail` off so the
pipeline's status is what a plain shell would report. It reproduced both symptoms
the brief describes, at the same cut.

### For the phases that follow

- `gates.sh` stamps the **active** story, so a gate or `ci-local.sh` run started
  from this worktree writes into whatever story is active — check
  `bash scripts/phase.sh show` before running either.
- `bash scripts/selftest.sh` in full takes 10-25 minutes here and two overlapping
  runs corrupt each other. Use `bash scripts/selftest.sh mutate` while working,
  and run the whole suite once, alone, before the PR.
- `bash scripts/gates.sh --list` is minutes slow on this machine (seconds on CI).
  It is fork cost in the config parse, not a hang.

### GREEN, by the Feature Developer

**Resolved model: `opus` (`claude-opus-5`).** The planned model for GREEN, with
no override in the dispatch. Recorded here because the dispatch asked; the
`## Model guidance` **Resolved:** block belongs to the orchestrator.

**The mechanism the whole fix rests on was measured, not assumed.** The Contract
says an EXIT trap still fires when the shell dies of SIGPIPE, and the story reads
today's leftover-free `src/main.ts` as evidence of it. That evidence does not
actually separate the two hypotheses: at `N = 1..3` the file is never mutated and
at `N = 4, 5` the straight-line `cp` at line 152 has already restored it, so
AC-3 would hold at every width whether or not the trap ran. So it was probed
directly, 5 runs out of 5, with a script whose trap touches a marker file before
it prints:

    run 1 writer=141 fired=yes trapprinted=no reachedend=no
    ... (5/5 identical)

Two facts, both load-bearing: bash **does** run the EXIT trap on a SIGPIPE death,
and the trap then **dies at its own first write**. The second is why the
Contract's "file work first, printing last" is the fix rather than a style
preference - a trap that printed first would have produced `fired=yes` and
nothing else, exactly as the straight-line code does today.

**Negative controls from the handoff, re-measured against the shipped script.**
All eight agree with RED; none diverged.

| Control | RED | GREEN, measured against `scripts/mutate.sh` as shipped |
|---|---|---|
| `.bak` count, directory provocation | `1` | `1` |
| `.new` count, same run | `0` | `0` |
| Anchored log-line count in the sweep | `0` at `N <= 5`, `1` at `N = 6, 30` | `1` at every width `1 2 3 4 5 6 30` - the fix |
| `lines_in "$PIPED_OUT"` at `N = 1` | `1` | `1` |
| Lines in an untruncated `-- true` run | `8` | `8` |
| `=== mutate: ` count on stdout | `3` | `0` |
| Banner, verdict, restored line on stderr | absent | present (all three) |
| `${PIPESTATUS[0]}` of the piped run | `141` at `N = 1..5`, `0` at `N = 6, 30` | identical |

The last row is worth a sentence: AC-6 moved every banner to stderr, and the cut
did **not** move, because the sweep captures with `2>&1`. That is the Contract's
stated reason for `2>&1` and it held.

The handoff's claim about the older AC-4 provocation was also checked rather
than taken: `-- sh -c 'rm -f .claude/state/mutations/*.bak'` leaves `bak=0`
against the shipped fix, so it could never have caught an unconditional cleanup.
The directory provocation beside it reports `bak=1 new=0`, which is the control
that can.

**For GATES: where to apply the unconditional-cleanup mutation.** The
conditional cleanup is one identifiable place, `scripts/mutate.sh:216` - the
unverified branch inside `finish()`:

        if [ "$restore" = "COULD NOT RESTORE" ]; then
          rm -f "$NEW" 2>/dev/null          # <- line 216
        else
          rm -f "$NEW" "$BAK" 2>/dev/null
        fi

Suggested expression, which makes the unverified path delete the backup too:

    s|rm -f "\$NEW" 2>/dev/null|rm -f "\$NEW" "\$BAK" 2>/dev/null|

It matches exactly one line - checked with `sed` into a scratch copy and
`diff`, which reported `216c216` and nothing else. **I did not run the control**
and am not claiming it: that is the story's deferred verification and it is
GATES's. Use the copy recipe in `## Deferred verifications`; `mutate.sh` still
refuses to mutate itself.

**One residual, reported rather than fixed, and reproducible.** The `exit 3`
"the expression changed nothing" path still prints before it cleans up, and it
sits **above** the trap - which is where the Contract's "shape of the fix" put
the trap boundary, explicitly and by line number. Against a reader that closes
the pipe before reading anything it leaks the same false alarm this story
exists to remove, 3 runs out of 3:

    $ bash scripts/mutate.sh src/main.ts 's/NOPE/x/' -- true 2>&1 | head -0
    exit-3 writer=141 leftovers=[src_main.ts.<stamp>.<pid>.bak
                                 src_main.ts.<stamp>.<pid>.new ] loglines=0

    the same run on the mutating expression, for contrast:
    normal writer=141 leftovers=[] loglines=1 file-restored=yes

It does **not** reproduce at `head -1..5`, the widths AC-1 sweeps: that path
writes only four short lines, which fit the pipe buffer before the reader exits.
No criterion covers it, and the repair is either a three-line reorder in the
exit-3 block (log, `rm`, then print) or moving the trap above the changed-nothing
check - the second of which the Contract ruled out by naming the insertion point.
Left alone deliberately, since GREEN adding production behaviour no test demands
is the thing this harness asks GREEN not to do. It is a one-commit follow-up
story if the product owner wants the invariant closed.
