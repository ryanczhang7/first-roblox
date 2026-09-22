---
id: HARNESS-012
title: mutate.sh leaves a backup and no log when its output is piped
slug: mutate-sh-leaves-a-backup-and-no-log-whe
epic: 
type: fix
status: todo
phase: PLANNED
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

## Handoff: RED -> GREEN

## Regressions

## Gate results

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
