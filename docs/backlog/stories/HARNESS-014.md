---
id: HARNESS-014
title: plan.sh's unenforced exception is suppressed by any path a story merely mentions
slug: plan-sh-s-unenforced-exception-is-suppre
epic: 
type: fix
status: done
phase: DONE
branch: story/HARNESS-014-plan-sh-s-unenforced-exception-is-suppre
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`.claude/harness/models.conf` carries an `unenforced` exception whose stated
intent is:

> the lock freezes none of the paths this story names, so the contract is not an
> aid to the model here - it is the only enforcement there is. A weaker model
> against a safety net and a weaker model against nothing are different
> propositions

`scripts/plan.sh`'s `contract_unenforced()` decides whether it fires. It did not
fire for `HARNESS-012`, a story both of whose files are `harness` and therefore
writable in every phase — precisely the condition the exception is written for.
The Lead PO had to reason the departure out by hand and write it into that
story's `## Model guidance`, where it is recorded in full.

**The defect in one sentence.** The detector tests *"does the Contract mention
any path that classifies as source?"* when the question it is standing in for is
*"does this story **write** any path the lock freezes?"* — and the two differ
exactly for stories that name fixtures, examples, tool output, or paths inside a
sandbox.

**The mechanism, confirmed against the code at PLANNED.** `contract_unenforced()`
(`scripts/plan.sh:96-110`) greps **every path-shaped token** out of the whole
`## Contract` section:

    grep -oE '\.claude/[A-Za-z0-9_./-]+|[A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+'

classifies each, and sets `enforced=1` the moment one is not `harness`, `docs`
or `ignored`. Run against `HARNESS-012`'s Contract it extracts sixteen tokens,
and **five** of them defeat the exception — not one:

    $ bash scripts/classify.sh <the sixteen tokens>
    harness .claude/hooks/lib.sh          harness .claude/tests/_lib.sh
    harness .claude/tests/                harness CLAUDE.md
    harness scripts/mutate.sh             harness scripts/selftest.sh
    docs    rules.md                      test    mutate.test.sh
    source  5.3.15                        source  classify.sh
    source  i.e                           source  mutate.sh
    source  src/main.ts

Three of those five are not paths at all in any sense a reader would recognise:
`5.3.15` is a bash version number out of a measurement note, `i.e` is an English
abbreviation, and `classify.sh` and `mutate.sh` are bare filenames of harness
scripts whose directory the prose omitted — with no directory they match no rule
in `paths.conf` and fall through to the `source` default. Only `src/main.ts` is a
real path, and it is the fixture file inside a throwaway `make_project_fixture`
repository that the story never writes and no phase of it can touch. Deleting
`src/main.ts` from that Contract would not have changed the verdict.

This is a strictly wider diagnosis than "one fixture mention suppressed it", and
it is why the fix below is a *declaration* rather than a better filter.

**Why it matters, and it is the reason this is worth a story.** The suppression
falls on the **weak** side. It silently downgrades RED's model for exactly the
stories where the phase lock is protecting nothing, which is the opposite of the
exception's intent. And it is silent: nothing in `plan.sh`'s output says the
exception was considered and suppressed, or by what. Confirmed:

    $ bash scripts/classify.sh scripts/mutate.sh .claude/tests/mutate.test.sh
    harness scripts/mutate.sh
    harness .claude/tests/mutate.test.sh

    $ bash scripts/plan.sh models HARNESS-012
    ...
    RED  test-developer  fable  the measured case. With a partitioned contract ...

Both paths HARNESS-012 actually writes are `harness`; the plain `fable` row was
rendered anyway, with no mention of the exception.

**The gate that would fail if this story's artifact broke.** None, and that is a
fact about this repository rather than an omission to fix here — same as
`HARNESS-012` and `HARNESS-013`. Every gate in `project.conf` judges the Luau
project; the one called `harness` runs `.claude/tests/project-counters.test.sh`
and nothing else, which is `HARNESS-008`'s derived answer (it is the one suite a
*product* story can break) rather than an oversight. `bash scripts/classify.sh`
reports both files this story touches as `harness`, not `source`, so `gates.sh`'s
`covers` check does not bite either. What binds this story is
`.github/workflows/gates.yml`'s `run: bash scripts/selftest.sh` step. See PO
decision 4.

## Acceptance criteria

Every criterion is measured against a **fixture story written by the test**, via
`story_with` in `.claude/tests/plan.test.sh`, never against a story in
`docs/backlog/`. That is deliberate and it is a constraint on the tests as much
as on the fix: changing this detector changes which model *future* stories plan
for, so a criterion pinned on a live story would be re-measured every time that
story was edited. The fixtures below are named here and their expected verdicts
are given.

| Fixture | `### Files` table names | Contract prose also names | Expected RED row |
|---|---|---|---|
| **F-DECL-HARNESS** | `scripts/mutate.sh`, `.claude/tests/mutate.test.sh` | `src/main.ts`, `bash 5.3.15(2)`, `i.e.`, bare `classify.sh` | `opus` |
| **F-DECL-SOURCE** | `src/core/world.ts`, `scripts/task.sh` | nothing path-shaped | `fable` |
| **F-NODECL-HARNESS** | *(no table)* | `scripts/plan.sh`, `.claude/tests/plan.test.sh` | `opus` |
| **F-NODECL-SOURCE** | *(no table)* | `src/core/world.ts`, `scripts/task.sh` | `fable` |
| **F-NOPATHS** | *(no table)* | prose with no path-shaped token | `fable` |

F-DECL-HARNESS is `HARNESS-012`'s Contract in miniature, including the four
non-path tokens that defeated it. F-NODECL-HARNESS and F-NODECL-SOURCE are the
existing `T-4` and `T-5` cases at `plan.test.sh:117-133`.

- **AC-1** — Given a story whose `## Contract` contains a `### Files` table,
  when `bash scripts/plan.sh models <id>` runs, then the `unenforced` decision
  is made from the **first column of that table's body rows** and from nothing
  else in the section. Reproduced on **F-DECL-HARNESS**: the RED row is
  `opus` and its reason names the lock.
  *Fails today*: `fable`, because the prose tokens are scanned.

- **AC-2** — Control on AC-1, and it is the control that stops the fix being
  "ignore declared paths": given **F-DECL-SOURCE**, the RED row is `fable`. One
  declared path the lock freezes is still enough for the lock to bite.
  *Passes today*, for a different reason than it will after the fix — which is
  why `## Deferred verifications` mutation 2 has to make it go red.

- **AC-3** — Given a story whose `## Contract` contains **no** `### Files`
  table, the decision is made exactly as it is today, by scanning the whole
  section. Three cases: **F-NODECL-HARNESS** gives `opus`, **F-NODECL-SOURCE**
  gives `fable`, **F-NOPATHS** gives `fable` (a contract naming no paths at all
  does not trigger the exception — today's `[ -n "$paths" ] || return 1`).
  *Passes today.* The backward-compatibility guard: the fallback is what every
  story written before this one relies on. Sit these beside the existing
  assertions at `plan.test.sh:117-133`; do not rewrite them.

- **AC-4** — Given any story with a contract, when `bash scripts/plan.sh <id>`
  runs (the human form), then its output carries exactly one **lock-coverage
  line**, and that line states three things: which of the two sources the paths
  came from, whether the exception **applied** or was **suppressed**, and — when
  suppressed — at least one path that suppressed it together with the category
  `classify.sh` gave it.
  *Fails today*: nothing of the kind is printed, so the decision is invisible
  and a wrong verdict has to be found by reading the source.
  *Control:* the three verdicts are asserted by **anchored, mutually
  non-matching** needles (see the Contract). On **F-DECL-HARNESS** the line says
  `APPLIES`; on **F-NODECL-SOURCE** it says `SUPPRESSED` and names
  `src/core/world.ts` and `source`; on **F-NOPATHS** it says `NOT CONSIDERED`.

- **AC-5** — Given the same story, when `bash scripts/plan.sh write <id>` runs,
  then the same lock-coverage line appears **inside** the generated region of
  `## Model guidance` — between `<!-- plan.sh:generated:begin -->` and
  `<!-- plan.sh:generated:end -->` — and running `write` a second time leaves
  **exactly one** copy of it (counted, not searched for) and leaves prose
  written outside the markers untouched.
  *Fails today.* This is where it has to land: the departure in `HARNESS-012`
  was written by hand into this very section because nothing put it there.

- **AC-6** — Given any story, when `bash scripts/plan.sh models <id>` runs, then
  its stdout is **exactly six lines**, each one
  `PHASE<TAB>agent<TAB>model<TAB>why`, and carries no lock-coverage line and
  nothing else. *Passes today.*
  This is the **negative control on AC-4 and AC-5**. Three callers parse that
  stream field-wise and would swallow a stray line without complaining:
  `cmd_both` (`plan.sh:231`) and `cmd_write` (`plan.sh:309`) both
  `while IFS=$'\t' read -r ph agent model why`, and `scripts/phase.sh:126` runs
  `awk -F'\t' '$1 == p { print $3 }'`. A note leaking into `cmd_models` would put
  a junk row in every story's rendered table and a blank model in
  `phase.sh show`. The existing assertion at `plan.test.sh:80` counts only lines
  *containing a tab*, so it cannot see this; the count must be of **all** lines.

## Contract

Written before RED. **RED may amend any block in place, with a reason**, and
GREEN builds what the amended block says.

### Files

| Path | `classify.sh` says | Who writes it |
|---|---|---|
| `scripts/plan.sh` | `harness` | GREEN |
| `.claude/tests/plan.test.sh` | `harness` | RED |

**Both classify as `harness`, so the phase lock permits writing either of them in
every phase.** Nothing will stop RED editing `scripts/plan.sh`, or GREEN editing
the frozen test file. The law still applies in full (`CLAUDE.md` laws 1 and 2);
here it is honoured by the agents rather than enforced by the hook. Say so in
the handoff, and show `git diff --stat scripts/plan.sh` empty at the end of RED.
That this story is *about* that condition does not exempt it from it.

### The command that runs these tests

    bash scripts/selftest.sh plan

One suite. `bash scripts/selftest.sh` with **no** argument runs all 19 suites,
takes 10-25 minutes on this machine, and two overlapping runs corrupt each
other — do not use it as the inner loop.

*Amended in RED (measurement, not a change of intent):* one `plan.sh models`
call measured **75 s** on this machine at RED, against a fixture story, not the
25-45 s the dispatch brief quoted. The suite now makes 29 such calls (20 before
this story, 9 added by it), so `bash scripts/selftest.sh plan` alone is
**~35-40 minutes here** and outlives the 600 s foreground cap — run it in the
background and read the log. On CI it is seconds; the cost is Windows fork
overhead in `classify` and `conf_rows`, not a hang.

### The shape of the fix

Observable behaviour is the contract; the structure below is the intended shape
and GREEN may deviate if it can hold all six criteria.

1. **`contract_unenforced()` gains a declared source.** When the `## Contract`
   section contains a `### Files` heading followed by a markdown table, the
   path list is the **first column of that table's body rows**, with backticks
   and surrounding whitespace stripped, and rows skipped whose first column is
   empty, is a separator (`^:?-{3,}:?$`), or is the literal word `Path`. Two
   things this must get right, both drawn from the measurement above:
   - the table **header** row carries `` `classify.sh` `` in its second column
     in this repository's own convention, and `classify.sh` classifies as
     `source` — so an implementation that scans the whole table rather than its
     first column reproduces the bug it is fixing;
   - `### Files` must not be treated as a section terminator. `section()` splits
     on `^## `, and `### Files` does not match it, so the heading is inside the
     Contract body already.

2. **The fallback is unchanged.** With no `### Files` heading, or a heading that
   yields no rows, the path list is today's whole-section scan, byte for byte —
   same regex, same `sort -u`, same "one non-harness path is enough" rule, same
   `return 1` when there are no paths at all.

3. **A lock-coverage line is emitted, once, in two places.** Rendered by one
   function so the two cannot drift, and printed by `cmd_both` (indented under
   the model plan, where a human reads it) and by `cmd_write` (inside the
   generated region, beneath the table, where the next agent reads it).

4. **`cmd_models`' stdout does not change.** Six tab-separated rows and nothing
   else (AC-6). The lock-coverage line is rendered by its own function and
   called by the two commands that have a human-readable stream; it never goes
   through the TSV.

5. **`models.conf` is not edited.** The exception's rows, its wording and its
   condition names stay exactly as they are. This story changes only how the
   `unenforced` condition is *evaluated* and whether the evaluation is stated.

### The lock-coverage line, verbatim

Three verdicts, and their keywords are chosen to be **mutually non-matching
substrings** so that no needle for one can be satisfied by another. `rules.md`'s
"an assertion's needle is part of the assertion" names four real cases of
exactly this, one of which was satisfied by the string meaning the opposite.

    Lock coverage: APPLIES — all <N> path(s) declared in the Contract's ### Files table are harness/docs/ignored, so RED stays on the stronger model.
    Lock coverage: SUPPRESSED by `src/core/world.ts` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
    Lock coverage: NOT CONSIDERED — this contract names no paths.

*Amended in RED:* the `SUPPRESSED` form above originally read
``SUPPRESSED by `src/core/world.ts` (source) — the phase lock …`` with no source
clause, while the first bullet below says the clause appears in the `APPLIES`
and `SUPPRESSED` forms alike. The bullet is the intent (AC-4 asks the line to
state which source the paths came from on *every* verdict that has paths), so
the verbatim line now carries it. The tests pin that a `SUPPRESSED` line
contains both the offending `` `path` (category) `` and one of the two source
clauses; they do **not** pin the order of those two fragments or the exact
punctuation between them, which stays GREEN's choice.

- The source clause is one of `declared in the Contract's ### Files table` or
  `scanned from the Contract text`, and appears in the `APPLIES` and
  `SUPPRESSED` forms alike.
- `SUPPRESSED by` names up to **three** offending paths, each with its category
  in parentheses, in the order the path list produced them, followed by
  ` (+N more)` when there are more.
- In `cmd_both` the line is indented to sit under the model plan; in the
  generated region it starts at column 0 on its own line. So assertions anchor
  as `^[[:space:]]*Lock coverage: <VERDICT>` and **count** with `grep -cE`.

**The line is expected to look absurd on a bad fallback verdict, and that is the
point.** A story whose prose mentions `i.e.` will read
``Lock coverage: SUPPRESSED by `i.e` (source) …``. That is the cheapest possible
signal that the heuristic has misfired, and it is the reason narrowing the
extraction regex is deliberately *not* in this story (see `## Out of scope`).

### The test the story adds

New and extended blocks in `.claude/tests/plan.test.sh`.

- `story_with <id> <type> <phase> <ac-count>` takes section bodies on stdin as
  `CONTRACT:` lines and emits one `## Contract` body line per `CONTRACT:` line.
  A `### Files` table is several lines, so **RED must check whether `story_with`
  can emit a multi-line contract as written** — `sed -n 's/^CONTRACT://p'` over
  a multi-line heredoc does produce several lines, so it should — and if it
  cannot, add a sibling helper rather than changing `story_with`'s signature, so
  that the fourteen existing cases that use it keep their exact invocation.
- The existing `T-4` and `T-5` cases at `plan.test.sh:117-133` are AC-3's first
  two rows. **Extend beside them; do not rewrite them.** Their comments carry
  the reasoning for the exception itself.
- The existing row-count assertion at `plan.test.sh:80` counts lines containing
  a tab. AC-6 needs a count of **all** lines, which is a different assertion, so
  it is added rather than edited.
- Assertions on the lock-coverage line are **counts** with two-end anchoring
  (above), never `assert_contains` on the whole output — the word `SUPPRESSED`
  floating anywhere in a multi-paragraph human output is not evidence that the
  line was emitted once, in the right place, with the right subject.
- AC-5 needs the generated-region check: extract between `GEN_BEGIN` and
  `GEN_END` and count the line inside **that** slice, not in the whole file.
  The existing `describe "a write preserves the story's own guidance"` block at
  `plan.test.sh:290` already pins that prose outside the markers survives a
  re-run; AC-5's "exactly one copy after two writes" sits beside it.

Helpers available: `plan`, `story_with`, `ordinary` (`.claude/tests/plan.test.sh`),
`make_project_fixture`, `describe`, `assert_eq`, `assert_contains`, `_ok`,
`_bad`, `summary` (`.claude/tests/_lib.sh`). No new dependency of any kind:
bash, git, awk and coreutils only, which is the standing constraint on every
suite in `.claude/tests/`.

### Callers of anything whose behaviour changes

`contract_unenforced()` is private to `scripts/plan.sh` and has one call site,
`cmd_models` at `plan.sh:117`. No signature and no CLI argument changes, and no
subcommand is added. The three consumers of `cmd_models`' stdout — `cmd_both`
(`plan.sh:231`), `cmd_write` (`plan.sh:309`) and `scripts/phase.sh:126` — are
unaffected **because** AC-6 says that stream does not change; they are listed
here so that the AC-6 control is visibly aimed at something real rather than
being a formality.

### Baseline measurements the story may read out

Measured by the Lead PO at PLANNED on this machine, 2026-09-22, against
`scripts/plan.sh` and `scripts/classify.sh` as they stand on
`story/HARNESS-012-...`:

    the sixteen tokens contract_unenforced() extracts from HARNESS-012's
    ## Contract, and what classify.sh calls each — the table in ## Context.
    Five are `source`, one is `test`, so enforced=1 and the exception is
    suppressed. Only one of those six (`src/main.ts`) is a real path, and it
    is a fixture inside a throwaway repository.

    $ bash scripts/plan.sh models HARNESS-012 | grep '^RED'
    RED	test-developer	fable	the measured case. ...

    $ bash scripts/classify.sh scripts/mutate.sh .claude/tests/mutate.test.sh
    harness	scripts/mutate.sh
    harness	.claude/tests/mutate.test.sh

Read these out. Do not re-derive the token list, and do not "calibrate" the
regex — that is `## Out of scope`.

### Oracle partition of the criteria

| Criteria | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-3 | **Settled** — the fixture table and its expected verdicts are given, and the token measurement behind F-DECL-HARNESS was taken at PLANNED | Read them out. Build the five fixtures exactly as the table describes, including the four non-path tokens in F-DECL-HARNESS's prose; they are the reproduction, not decoration. |
| AC-4, AC-5 | **Mechanical** — an output line with fixed wording and a fixed location | Pin exactly. Anchor and count; the three verdict keywords must be shown not to match one another. |
| AC-6 | **Mechanical** — a stream's shape, and the control on the other two | Pin exactly: exactly six lines, each with three tabs. "It has six rows with tabs" is the assertion that already exists and cannot see the defect. |

Nothing here is oracle-free: there is no metric to invent. The places a blind
assertion could hide are AC-4's verdict needles and AC-6's line count, and both
are addressed above.

## Deferred verifications

Three mutations. Two break a decision and are caught by a verdict assertion;
the third leaves every verdict correct and corrupts only the stream shape, which
is the direction a suite is most often blind in.

1. **The fallback dropped.** With `contract_unenforced()` made to return 1
   whenever there is no `### Files` table, **AC-3's F-NODECL-HARNESS case must
   go red** (its RED row would become `fable`) and AC-1's must stay green. If
   AC-3 stays green, the fallback is untested and every story written before
   this one is unguarded.

2. **Declared source paths ignored.** With the table-derived path list filtered
   to drop anything that classifies as `source`, **AC-2 must go red** (
   F-DECL-SOURCE's RED row would become `opus`) while AC-1, AC-4 and AC-5 stay
   green. This is the mutation that separates "read what the story declares"
   from "assume harness-only", and a fix indistinguishable from the latter has
   not been verified.

3. **The lock-coverage line routed through `cmd_models`.** With the note printed
   on `cmd_models`' stdout instead of by its own function, **AC-6 must go red
   and AC-4 must stay green** — the line still reaches the human output, by the
   wrong road. If AC-6 does not catch it, then every rendered `## Model
   guidance` table would silently gain a junk row and `phase.sh show` would
   print a blank model, with the whole suite green. This is the corruption, not
   the omission, and it is the one worth doing.

**Why RED cannot run any of them.** There is nothing to mutate in RED: the
declared-path branch, the fallback branch and the lock-coverage function are all
what GREEN is about to write. `scripts/plan.sh` is also not RED's to edit under
the law, even though the lock would permit it.

**Owner: GATES.**

Recipe — `mutate.sh` will mutate `scripts/plan.sh` directly, since it is not the
script doing the running:

    bash scripts/mutate.sh scripts/plan.sh '<expression>' -- bash scripts/selftest.sh plan

Paste the results here: for each of the three, the expression, the red, and the
restore.

### Results — run by the Lead PO at GATES, 2026-09-23

Run one at a time on this machine: a concurrent suite costs a measured ~4x (see
`## Notes`). Each is one `mutate.sh` invocation, which restores the file and
verifies the restore with `cmp` before printing.

**Mutation 1 — the fallback dropped. PREDICTION HELD.**

The fallback branch is made to report `enforced` unconditionally, so the
`unenforced` exception can never fire without a `### Files` table:

    $ bash scripts/mutate.sh scripts/plan.sh \
        's@    LC_ORIGIN=scanned@    LC_ORIGIN=scanned; enforced=1@' \
        -- bash scripts/selftest.sh plan
    === mutate: scripts/plan.sh (1 line(s) changed by s@    LC_ORIGIN=scanned@    LC_ORIGIN=scanned; enforced=1@) ===
    === mutate: running bash scripts/selftest.sh plan ===
        FAIL a story the lock cannot police keeps RED on the stronger model
        FAIL and says the lock is what is missing
    plan: 82 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../.claude/state/mutations/scripts_plan.sh.20260923T173645Z.329038.bak) ===

Red: exactly AC-3's F-NODECL-HARNESS (T-4), both its assertions. Green: AC-1
(T-7), AC-2 (T-8), AC-3's other two rows (T-5, T-9), every AC-4 and AC-5
assertion, and AC-6's six. **So the fallback is tested**, and every story
written before this one is guarded rather than merely unchanged.

RED's prediction table allowed for collateral here — T-5's AC-4
`SUPPRESSED`/`scanned from` assertions going red too, *if* the mutation emptied
the path list rather than only the verdict. It did not: this mutation leaves the
list intact and flips only `enforced`, so T-5 still names its offender and the
collateral did not occur. The narrower mutation is the better one, because the
two failures it produces are unambiguous.

`git diff --stat scripts/plan.sh` after the run is the GREEN diff unchanged
(163 insertions, 12 deletions); line 171 reads `    LC_ORIGIN=scanned` again.

**Mutation 2 — declared source paths ignored. PREDICTION HELD.**

`declared_paths` is made to drop any declared path under `src/`, which is this
repository's `source` tree — i.e. the fix degraded into "a story with a `### Files`
table is harness-only". Scoped to the table reader deliberately: adding `source`
to the `harness|docs|ignored)` arm instead would ALSO have taken AC-3's T-5 red,
and the story requires AC-3 to stay green under this mutation. A mutation that
damages more than the behaviour it is aimed at proves less, not more.

    $ bash scripts/mutate.sh scripts/plan.sh \
        's@      print col@      if (col !~ "^src/") print col@' \
        -- bash scripts/selftest.sh plan
        FAIL but one DECLARED source path is enough for the lock to bite
        FAIL SUPPRESSED by the declared source path, and the paths came from the table
        FAIL not APPLIES
    plan: 81 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../.claude/state/mutations/scripts_plan.sh.20260923T174935Z.366342.bak) ===

Red: exactly the three the handoff named — AC-2's T-8 assertion, and T-8's two
AC-4 halves. Green: AC-1, AC-3 (all three rows), AC-4 on the scanned fixtures,
AC-5, AC-6's six.

The handoff's sharpest prediction also held: **T-8's `exactly one lock-coverage
line` stayed green** while the two assertions about what that line SAYS went red.
The line still existed; it said the wrong thing. That is the distinction between
"a line is emitted" and "the right line is emitted", and the suite draws it.

So the fix is verified to read what the story DECLARES rather than to assume a
declaring story is harness-only — which is the one substitution that would have
passed AC-1 and AC-3 while being wrong.

**Mutation 3 — the lock-coverage line routed through `cmd_models`. PREDICTION
HELD, ON BOTH SIDES, WITH ONE UNPREDICTED EXTRA CATCH.**

Read the story's wording exactly: the note is printed on `cmd_models`' stdout
*instead of* by its own function. That is three edits, not one — inject the call
into `cmd_models`, and stub out both dedicated call sites — and the distinction
matters. Merely ADDING the call would have put two lines in `cmd_both`'s output
and taken AC-4 red for a reason that has nothing to do with the corruption being
tested. The mutation has to be the plausible wrong implementation, not damage.

    $ bash scripts/mutate.sh scripts/plan.sh \
        's@  local type contract_has=0 unenforced=0@&; lock_coverage_line "$file"@; 375s@.*@  :@; 462s@.*@    :@' \
        -- bash scripts/selftest.sh plan
    === mutate: scripts/plan.sh (3 line(s) changed by ...) ===
        FAIL when the exception applies: stdout is exactly six lines
        FAIL when the exception applies: and every one of them is PHASE<TAB>agent<TAB>model<TAB>why
        FAIL when it is suppressed: stdout is exactly six lines
        FAIL when it is suppressed: and every one of them is PHASE<TAB>agent<TAB>model<TAB>why
        FAIL when it is not considered: stdout is exactly six lines
        FAIL when it is not considered: and every one of them is PHASE<TAB>agent<TAB>model<TAB>why
        FAIL and names a model that can actually be dispatched
        FAIL the generated region carries the lock-coverage line, once
        FAIL and it is the same verdict the human plan gave
        FAIL at column 0, beneath the table
        FAIL and nowhere else in the story file
        FAIL writing again leaves exactly one copy in the file
        FAIL still inside the generated region
    plan: 71 passed, 13 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../.claude/state/mutations/scripts_plan.sh.20260923T180124Z.401242.bak) ===

Three readings, and the third is the one that was not predicted.

1. **AC-6 went red on all six**, across all three verdict branches. The control
   works: a note leaking into the stream `cmd_both`, `cmd_write` and
   `scripts/phase.sh:126` all parse field-wise cannot reach `main` unnoticed.
2. **AC-4 stayed green on every fixture**, which is the half that is easy to get
   wrong and which RED reasoned out in advance: `cmd_both` re-emits the leaked
   tab-less line through its own `printf '    %-9s …'`, so the anchored needle
   still counts exactly 1. The human output looks fine. **That is the whole
   point of AC-6 existing** — the corruption is invisible to the assertion a
   reader would expect to catch it, and visible only to the one written for it.
   RED's prediction that AC-5 would go red as collateral also held, all six.
3. **UNPREDICTED: `and names a model that can actually be dispatched` went red
   too.** That is an assertion older than this story, which `cut -f3`s each row
   and requires `opus|fable|sonnet|haiku`. On the leaked tab-less line, field 3
   is the whole line, so it reported a model nobody can dispatch. Nothing in
   the handoff predicted it. It is the same corruption seen from a third angle
   — and it is the concrete form of the damage `## Deferred verifications`
   describes as "`phase.sh show` would print a blank model". An existing guard,
   written for a different reason, independently catches this leak.

6 + 6 + 1 = 13. `git diff --stat scripts/plan.sh` after the run is the GREEN
diff unchanged; lines 248, 375 and 462 all read as they did before.

**Verdict on all three.** Every must-go-red went red, every must-stay-green
stayed green, the one piece of collateral the handoff flagged as likely occurred
and was flagged, and the only surprise made the suite look better rather than
worse. The prediction table is evidence now, not a claim.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-014` from `.claude/harness/models.conf`.
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

**No departure. RED runs on the planned `fable` — and note what that means for
this story in particular.**

The table above says `fable` because `contract_unenforced()` scanned this
story's own `## Contract`, found `src/core/world.ts`, `src/main.ts` and
`classify.sh` in the fixture descriptions, and suppressed the `unenforced`
exception. **That is the very defect this story exists to fix, happening to this
story.** Read the RED row as an exhibit, not as a considered answer: after the
fix, the same command would read this story's `### Files` table, see two
`harness` paths, and render `opus`.

It is taken anyway, and deliberately. `HARNESS-012` departed from this row for
exactly this reason, carried a success condition written to come out either way,
and recorded the verdict:

> the departure bought nothing observable, and the next harness-only story
> should take the `fable` row and save the cost.

Departing again on a hunch would replace a recorded verdict with a habit, which
is the thing `models.conf` exists to prevent. So the plan stands and the
experiment runs a second time — on the story that is about the experiment.

**Success condition, and it can come out either way.** RED on `fable` must end
with all three of:

1. `git status --short` naming `.claude/tests/plan.test.sh` and this story file
   and nothing else, and `git diff --stat scripts/plan.sh` **empty** — checked
   by the orchestrator against the tree, not reported by the agent. The lock
   permits the write; the law forbids it, and this story is about that gap.
2. A handoff whose control table names all three mutations in
   `## Deferred verifications`, and declines them explicitly as GATES's rather
   than claiming them.
3. The three verdict keywords (`APPLIES`, `SUPPRESSED`, `NOT CONSIDERED`)
   asserted by anchored, counted needles, with the *demonstration* that none of
   them matches another — not a claim that they do not. The Contract asks for
   this explicitly because `rules.md` carries four real cases of a needle
   satisfied by the string meaning the opposite.

If it delivers all three, `HARNESS-012`'s verdict is confirmed a second time,
the `fable` row stands for harness stories generally, and this story's own fix
then makes the row *correct* as well as adequate. If RED edits `scripts/plan.sh`,
hands GREEN a fix disguised as a test, or writes a floating needle where the
Contract asked for an anchored count, the `unenforced` exception's intent is
confirmed against the weaker model, `HARNESS-012`'s verdict should be reversed,
and the repair is the policy row in `models.conf` — not an ad-hoc departure on
the next story. Record the verdict here when RED ends.

The oracle partition for RED is in `## Contract`, "Oracle partition of the
criteria" — carry it into the dispatch prompt **verbatim**; it is the half of the
brief that was measured to matter more than the model.

**Resolved:**

- **PLANNED** — `lead-po`, resolved `opus` (`claude-opus-5`). As planned; no
  override was passed, so the agent definition's own `model: opus` is what
  resolved it.

- **RED** — `test-developer`, resolved `fable` (`claude-fable-5-1`), as planned.
  The agent reported the resolved name and no override was passed.

**Verdict on the success condition above: the `fable` row stands, and
`HARNESS-012`'s verdict is confirmed a second time.** All three conditions were
checked by the orchestrator against the tree rather than read out of the report:

1. `git status --short` named `.claude/tests/plan.test.sh` and this story file
   and nothing else; `git diff --stat scripts/plan.sh` empty. The one mutation
   of `scripts/plan.sh` went through `scripts/mutate.sh` and is in
   `.claude/state/mutations/log` as `restored (verified)`, with no `.bak` left
   behind. The lock permitted the write the law forbids, and it was not made —
   on the story that is about that gap.
2. The handoff's control table names all three deferred mutations, predicts a
   must-go-red and a must-stay-green set for each, and declines all three to
   GATES explicitly rather than claiming them. It also flags collateral the
   story's own prediction missed (mutation 3 will likely take AC-5 red beside
   AC-6), which is the report being sharper than the brief rather than agreeing
   with it.
3. The three verdict keywords are asserted by anchored, counted needles, and the
   demonstration is a matrix — `100 010 001 000` over the three verbatim lines
   **plus** `Lock coverage: NOT SUPPRESSED by anything`, the line meaning the
   opposite that `rules.md`'s fourth case is about. It went further than asked
   and measured the forbidden floating needle scoring 1 on that same line, so
   the anchoring is shown to be load-bearing rather than stated to be.

So the harness-only story does not need the stronger model on RED, twice over.
The next departure from this row needs evidence, not a hunch.


<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

## Out of scope

- **Narrowing the extraction regex.** Making `i.e`, `5.3.15` and bare filenames
  like `mutate.sh` stop counting as paths is a real improvement and a separable
  one, with its own controls and its own risk: a stricter pattern that requires
  a `/` would stop seeing `CLAUDE.md`, and one that rejects numeric extensions
  is a guess about what a story's prose contains. This story makes a bad
  fallback verdict **visible** (AC-4), which is the cheap half and the half that
  tells a later story whether the expensive half is needed. Candidate follow-up,
  not this story.
- **Making `### Files` mandatory**, in the template, in `story-authoring`, or in
  `check-boundaries.sh`. The fallback stays, and a story without a table is not
  malformed.
- **`.claude/harness/models.conf`.** No row is edited, no exception is added or
  removed, and the `unenforced` condition keeps its name and its wording. This
  story changes how the condition is evaluated and whether the evaluation is
  said out loud.
- **The `no-contract` and `type=bootstrap` exceptions**, `has_content`,
  `strip_generated`, `cmd_next`, `next_phase`, `AC_MANY` and the
  `advance-story` / `complete-story` recommendation. None of them is touched.
- **Adding a subcommand.** No `plan.sh paths <id>`; the lock-coverage line goes
  where the two existing human-readable outputs already are. A third surface is
  a third thing to keep in step.
- **`scripts/classify.sh` and `.claude/harness/paths.conf`.** The categories are
  correct; the defect is in what was handed to them.
- **Re-planning any existing story.** Changing this detector changes what future
  stories plan for, so no criterion is measured against a story in
  `docs/backlog/`, and `HARNESS-012`'s recorded `## Model guidance` — departure,
  success condition and verdict — is left exactly as it stands. It is history,
  not a fixture.
- **Adding a gate for `.claude/tests/**`.** Making `selftest.sh` a gate is a real
  question and this is not the story for it: it costs 10-25 minutes per
  `gates.sh` run here, two overlapping runs corrupt each other, and a story that
  adds a gate owes `## Gate probes`. This story adds no gate and changes no
  `evidence` line, so it has no `## Gate probes` section.
- **`scripts/mutate.sh`.** The other residual of `HARNESS-012`, filed as
  `HARNESS-013`. Nothing here touches it.

## Test plan

All in `.claude/tests/plan.test.sh`, at one level: the harness's own suite,
driving the real `scripts/plan.sh` inside a `make_project_fixture` repository
against fixture stories written by `story_with`. Nothing is measured against a
story in `docs/backlog/`. Fixture ids added: `T-7` (F-DECL-HARNESS), `T-8`
(F-DECL-SOURCE), `T-9` (F-NOPATHS); `T-4` and `T-5` (F-NODECL-HARNESS,
F-NODECL-SOURCE) are the existing cases, untouched.

| Assertion (as it prints) | AC | Fixture | Command | Red at RED? |
|---|---|---|---|---|
| a story that DECLARES only harness paths keeps RED on the stronger model, whatever its prose mentions | AC-1 | T-7 | `models` | **yes** — renders `fable` |
| but one DECLARED source path is enough for the lock to bite | AC-2 | T-8 | `models` | no — passes today for the wrong reason; deferred mutation 2 makes it red |
| a story the lock cannot police keeps RED on the stronger model / and says the lock is what is missing | AC-3 | T-4 | `models` | no (pre-existing) |
| but one source path is enough for the lock to bite | AC-3 | T-5 | `models` | no (pre-existing) |
| a contract naming no paths at all follows the plain plan | AC-3 | T-9 | `models` | no |
| no verdict needle matches another verdict's line, nor its own negation | AC-4 instrument | verbatim lines | none | no — it checks the needles, not the code |
| F-DECL-HARNESS: exactly one lock-coverage line / says APPLIES / to all 2 paths declared … / not SUPPRESSED / not NOT CONSIDERED | AC-4 | T-7 | `<id>` (cmd_both) | **yes** — the 1-counts; the 0-counts pass vacuously today |
| F-NODECL-SOURCE: exactly one / SUPPRESSED / by `src/core/world.ts` (source) / scanned from the text / not APPLIES / not NOT CONSIDERED | AC-4 | T-5 | `<id>` | **yes** (1-counts) |
| F-NOPATHS: exactly one / NOT CONSIDERED / not APPLIES / not SUPPRESSED | AC-4 | T-9 | `<id>` | **yes** (1-counts) |
| F-DECL-SOURCE: exactly one / SUPPRESSED by the declared source path, and the paths came from the table / not APPLIES | AC-2 (visible half) | T-8 | `<id>` | **yes** (1-counts) |
| the generated region carries the lock-coverage line, once / same verdict as the human plan / at column 0, beneath the table / nowhere else in the story file | AC-5 | T-7 | `write` | **yes** — first three; "nowhere else" is 0 today and reads as a `1 != 0` failure |
| writing again leaves exactly one copy in the file / still inside the generated region / brief outside the markers untouched | AC-5 | T-7 | `write` ×2 | **yes** — first two |
| `<verdict>`: stdout is exactly six lines / every one of them is PHASE<TAB>agent<TAB>model<TAB>why | AC-6 | T-7, T-8, T-9 | `models` (stdout only) | no — the negative control on AC-4/5; deferred mutation 3 makes it red |

Level choice: there is no cheaper level. `contract_unenforced()` is a private
function of a script with no library form, and every criterion is about what
the three subcommands print, so the test is the subcommand run against a
fixture story. The four zero-count assertions per verdict (`not APPLIES`, …)
are the story's required demonstration that the needles are mutually
exclusive, and they pass vacuously until GREEN emits any line at all — the
matrix assertion above them is what shows they *can* discriminate.

Edges: empty (F-NOPATHS: a contract with no path tokens), one (F-DECL-SOURCE:
a single declared source path), many (F-DECL-HARNESS: two declared harness
paths against four suppressing prose tokens), the `Path` header row and the
`|---|` separator inside the declared table, and idempotence (two writes).
Not covered, deliberately: the ` (+N more)` overflow beyond three offenders
(no fixture; the Contract states the format and GREEN owns it), a
`### Files` heading with an empty table (Contract says fall back; no fixture,
see handoff), and `no-contract` / `type=bootstrap` interactions, which are
`## Out of scope`.

## Handoff: RED -> GREEN

### The command

    bash scripts/selftest.sh plan

**~42 minutes on this machine** (started 23:15:32, exit at 23:57:31 on
2026-09-22; 29 `plan.sh` calls at ~75 s each). It outlives the 600 s foreground
cap, so run it in the background to a log file and block on the log — a second
run started while one is in flight corrupts both. Seconds on CI.
`VERBOSE=1` names every assertion, not just the failures.

### Verbatim failure output at RED

`scripts/plan.sh` unchanged (`git diff --stat scripts/plan.sh` empty — the lock
permits the write, the law forbids it, and it was not made). Every failure
below is an assertion of this story's own, reporting a count of `0` where it
expects `1`; nothing failed at load, on a timeout, or on a helper.

    === plan ===

      which model each phase runs on
        FAIL a story that DECLARES only harness paths keeps RED on the stronger model, whatever its prose mentions
             expected: 1
             actual:   0

      the lock-coverage decision is said out loud
        FAIL F-DECL-HARNESS: the human plan carries exactly one lock-coverage line
             expected: 1
             actual:   0
        FAIL and it says the exception APPLIES
             expected: 1
             actual:   0
        FAIL to all 2 paths declared in the ### Files table, not scanned from the text
             expected: 1
             actual:   0
        FAIL F-NODECL-SOURCE: exactly one lock-coverage line
             expected: 1
             actual:   0
        FAIL and it says the exception was SUPPRESSED
             expected: 1
             actual:   0
        FAIL by the source path, with the category classify.sh gave it
             expected: 1
             actual:   0
        FAIL and says the paths were scanned from the text, there being no table
             expected: 1
             actual:   0
        FAIL F-NOPATHS: exactly one lock-coverage line
             expected: 1
             actual:   0
        FAIL and it says the exception was NOT CONSIDERED
             expected: 1
             actual:   0
        FAIL F-DECL-SOURCE: exactly one lock-coverage line
             expected: 1
             actual:   0
        FAIL SUPPRESSED by the declared source path, and the paths came from the table
             expected: 1
             actual:   0

      and written into the story with the plan
        FAIL the generated region carries the lock-coverage line, once
             expected: 1
             actual:   0
        FAIL and it is the same verdict the human plan gave
             expected: 1
             actual:   0
        FAIL at column 0, beneath the table
             expected: after
             actual:   not-after
        FAIL and nowhere else in the story file
             expected: 1
             actual:   0
        FAIL writing again leaves exactly one copy in the file
             expected: 1
             actual:   0
        FAIL still inside the generated region
             expected: 1
             actual:   0

    plan: 66 passed, 18 failed

    1 of 1 harness suite(s) FAILED.

18 red: AC-1 (1), AC-4 (11, of which 2 are the visible half of AC-2 on
F-DECL-SOURCE), AC-5 (6). 66 green: the 48 that were there before this story,
plus AC-2, AC-3 (F-NOPATHS), the six AC-6 shape checks, the needle matrix, the
eight zero-count needles and "the brief outside the markers is untouched".

The AC-1 failure was also reproduced by hand before the suite ran: the T-7
Contract as `story_with` writes it, put through today's extraction and
`classify.sh`, yields `5.3.15`, `classify.sh`, `i.e`, `src/main.ts` as `source`
and renders `RED  test-developer  fable` — the four tokens the story's PLANNED
measurement names, on this tree, and nothing else.

### What each test asserts, and which AC

The table in `## Test plan` is the per-assertion list. Fixture ids: `T-7` =
F-DECL-HARNESS, `T-8` = F-DECL-SOURCE, `T-9` = F-NOPATHS, `T-4`/`T-5` =
F-NODECL-HARNESS/-SOURCE (pre-existing, untouched).

### Files touched

- `.claude/tests/plan.test.sh` — 226 lines added, none removed or changed.
  Two insertions: after the `T-5` case (fixtures T-7/T-8/T-9, `models_stdout`,
  `red_row`, `assert_tsv_shape`) and before `summary` (two new `describe`
  blocks: `the lock-coverage decision is said out loud`, `and written into the
  story with the plan`, plus `generated`).
- `docs/backlog/stories/HARNESS-014.md` — `## Contract` amended twice in
  place (below), `## Test plan`, this section. Nothing else.

### Contract amendments made in RED

1. **`### The lock-coverage line, verbatim`** — the `SUPPRESSED` example had no
   source clause while its own bullet says the clause appears in both forms.
   The example now reads ``SUPPRESSED by `src/core/world.ts` (source), scanned
   from the Contract text — …``. Reason in place.
2. **`### The command that runs these tests`** — added the measured cost (75 s
   per `plan.sh` call, ~42 min per suite run here). Measurement, not intent.

### The shape the tests already pin (fact, not suggestion)

There is no import: the tests drive `scripts/plan.sh` as a subcommand inside a
`make_project_fixture` copy. What they pin is the **output**:

**`bash scripts/plan.sh models <id>` — stdout only** (stderr is discarded by
`models_stdout`, so a diagnostic on stderr is neither required nor forbidden):

- exactly six lines, every one `PHASE<TAB>agent<TAB>model<TAB>why` with all
  four fields non-empty (`awk -F'\t' 'NF != 4'` counts 0). Asserted on T-7,
  T-8 and T-9 — one per verdict — so the line must not leak on any branch.
- the `unenforced` verdict is read from the RED row itself: exactly one line
  matching `^RED<TAB>test-developer<TAB>opus<TAB>the lock freezes none of the
  paths`. That prefix is `models.conf`'s own `unenforced` reason, which is
  frozen (`## Out of scope`), so it distinguishes this exception from
  `no-contract` (also `opus`). Plain-plan cases assert exactly one
  `^RED<TAB>test-developer<TAB>fable<TAB>`.

**`bash scripts/plan.sh <id>` (cmd_both) — stdout+stderr merged** (`plan`):

- exactly one line matching `^[[:space:]]*Lock coverage: ` — counted, so a
  second copy anywhere (from `cmd_next`, from a stderr echo) fails.
- the verdict keyword directly after `Lock coverage: `, one of exactly:
  `APPLIES`, `SUPPRESSED by `, `NOT CONSIDERED` (regexes `APPLIES`,
  `SUPPRESSED`, `NOT_CONSIDERED` in the test; the third has a trailing space
  after `by`).
- `APPLIES` on T-7 must match `all 2 path[(]s[)] declared in the Contract's
  ### Files table` later on the same line — i.e. the literal
  `all <N> path(s) declared in the Contract's ### Files table` with `N=2`, the
  count of declared body rows.
- `SUPPRESSED` on T-5 must match, later on the same line, both
  `` `src/core/world.ts` [(]source[)] `` and `scanned from the Contract text`
  — as two separate assertions, so **their relative order is not pinned**.
- `SUPPRESSED` on T-8 must match `` `src/core/world.ts` [(]source[)] `` **and
  then** `declared in the Contract's ### Files table` later on the line — one
  regex, so here **path-then-source-clause order is pinned**. Emit the offending
  path(s) before the source clause and both fixtures pass.
- `NOT CONSIDERED` on T-9: only the keyword is pinned.
- indentation: `^[[:space:]]*` — anything from column 0 to the model-plan
  indent is accepted.

**`bash scripts/plan.sh write <id>`** (T-7 only):

- inside the slice strictly between `<!-- plan.sh:generated:begin -->` and
  `<!-- plan.sh:generated:end -->`: exactly one `^[[:space:]]*Lock coverage: `
  line; it matches the same `APPLIES … all 2 path(s) declared …` needle as the
  human form; it begins at **column 0** (`/^Lock coverage: /`) and its line
  number is greater than that of the last line beginning with `|` in the slice.
- the whole story file contains exactly one `^[[:space:]]*Lock coverage: `
  line, after one write and after two. So it must live inside the markers —
  outside them `strip_generated` would keep it and the second write would
  duplicate it.
- prose put under `## Model guidance` by `put_guidance` before the first write
  survives both writes once.

**Deliberately not constrained** (implementer's choice): the wording after the
verdict beyond the fragments above, including the em-dash (`—`) the Contract
shows — none of the needles contains it, so a plain `-` would pass; the exact
punctuation between the path list and the source clause; the ` (+N more)`
overflow and the order of several offenders (no fixture has more than one);
whether the declared list is de-duplicated or sorted; how a `### Files`
heading with **no body rows** is treated (Contract says fall back; no fixture
pins it); what `cmd_both` prints for a story with **no** contract (T-2 is not
run through `cmd_both`; AC-4 says "any story with a contract"); anything on
stderr; the `NOT CONSIDERED` line's tail.

### Tests that passed on arrival, and what earns each

| Assertion(s) | Why green today | What earns it |
|---|---|---|
| AC-2 `but one DECLARED source path is enough for the lock to bite` (T-8) | the scan finds `src/core/world.ts` in the table text, as it finds anything | deferred mutation 2 (GATES) — the story's own reason for that mutation |
| AC-3 `a contract naming no paths at all follows the plain plan` (T-9) | today's `[ -n "$paths" ] \|\| return 1` at `plan.sh:100` | **not** by deferred mutation 1 — with no table, "return 1" is what T-9 expects, so it stays green there. Earned in RED with `mutate.sh` instead, below |
| AC-6 × 6 (`stdout is exactly six lines`, `every one … PHASE<TAB>…`) | nothing leaks today | deferred mutation 3 (GATES). Measured now so the numbers are on record: 6 lines and 0 malformed rows on each of T-7, T-8, T-9 |
| `no verdict needle matches another verdict's line, nor its own negation` | it tests the instrument, not the code | run outside the framework as well (below); it cannot go red by a change to `plan.sh`, and is not meant to |
| the eight `not APPLIES` / `not SUPPRESSED` / `not NOT CONSIDERED` zero-counts | vacuous: no line exists yet | they become meaningful the moment the sibling 1-count goes green in GREEN; the matrix shows each would count 1 on the wrong verdict |
| `and the brief outside the markers is untouched` (T-7) | `strip_generated` already preserves prose (T-50 block) | pinned by the existing T-50 assertions, which went through their own RED; this one is a regression guard for AC-5's last clause |

**The T-9 probe, run in RED.** The behaviour it pins already exists, so it is
the "test written against code that already exists" case and the observation
is replaced, not waived. The command is a one-call reproduction of the T-9
assertion (same `make_project_fixture`, same story body, same `red_row`
count) so the probe costs one `plan.sh` call rather than the 42-minute suite;
it was run green against the intact file first, then under the mutation that
makes a no-paths contract trigger the exception:

    $ REPO=$PWD bash <scratch>/probe-t9.sh
    RED	test-developer	fable
    probe-t9: 1 passed, 0 failed

    $ bash scripts/mutate.sh scripts/plan.sh \
        's/\[ -n "\$paths" \] || return 1/[ -n "$paths" ] || return 0/' \
        -- bash <scratch>/probe-t9.sh
    === mutate: scripts/plan.sh (1 line(s) changed by s/\[ -n "\$paths" \] || return 1/[ -n "$paths" ] || return 0/) ===
      100 -   [ -n "$paths" ] || return 1
      100 +   [ -n "$paths" ] || return 0

    === mutate: running bash .../probe-t9.sh ===
    RED	test-developer	opus
        FAIL a contract naming no paths at all follows the plain plan
             expected: 1
             actual:   0

    probe-t9: 0 passed, 1 failed

    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude/state/mutations/scripts_plan.sh.20260923T050701Z.133154.bak) ===
      100:   [ -n "$paths" ] || return 1

`git diff --stat scripts/plan.sh` empty afterwards; no `.bak` left under
`.claude/state/mutations/`. GREEN must keep that `return 1` (or its
equivalent) on the fallback branch — the Contract's point 2 says so, and this
is the assertion that would catch its loss.

### Negative controls — expected values, and what was measured

All assertions in this suite ran (there is no import to fail at), so the
values below are **measured in the suite at RED**, not claims. GREEN should
confirm each still holds against the shipped script, and that the vacuous
zeros stay zero once the ones become one.

| Control | Threshold / expected | Measured at RED |
|---|---|---|
| Needle matrix over the four probe lines (APPLIES, SUPPRESSED, NOT CONSIDERED, and `NOT SUPPRESSED by anything`), each cell = count of that needle on that line | `100 010 001 000 ` — identity, and all-zero on the negation | `100 010 001 000 ` (in the suite, and by hand outside it) |
| The same probe, with the **floating** needle the Contract forbids (`grep -c SUPPRESSED` on `Lock coverage: NOT SUPPRESSED by anything`) | 1 — i.e. it would accept the opposite; the anchored needle above counts 0 on the same line | 1 (by hand, outside the suite) |
| AC-6, T-7 (verdict will be APPLIES): all-lines count / malformed-row count | 6 / 0 | 6 / 0 |
| AC-6, T-8 (SUPPRESSED): same | 6 / 0 | 6 / 0 |
| AC-6, T-9 (NOT CONSIDERED): same | 6 / 0 | 6 / 0 |
| Existing row count at `plan.test.sh:80` (lines containing a tab, T-1) | 6 — and note this control is **blind** to a leaked note, which is why AC-6 counts all lines | 6 |
| Zero-count verdict needles on each `cmd_both` output (2 per fixture, 8 total) | 0 | 0 (vacuous until GREEN) |
| `and nowhere else in the story file` after one `write`, T-7 | exactly 1 line in the whole file | 0 today (red); GREEN: 1 |
| Sixteen-token baseline (read out from PLANNED, confirmed on this tree for the T-7 miniature) | `5.3.15`, `classify.sh`, `i.e`, `src/main.ts` classify `source`; `scripts/mutate.sh`, `.claude/tests/mutate.test.sh` classify `harness` | as expected, by hand |

### Deferred verifications — declined, with the predictions GATES will check

All three in `## Deferred verifications` are **GATES's, not RED's**, and I did
not run any of them: there is nothing to mutate — the declared-path branch, the
fallback branch and the lock-coverage function are what GREEN is about to
write — and `scripts/plan.sh` is not RED's to touch even though the lock would
let it. What RED owes is the prediction, so that the mutation is a check on
the suite and not a guess:

| Mutation (owner GATES) | Must go red | Must stay green | Likely collateral (not the point of the control) |
|---|---|---|---|
| 1. fallback dropped (`contract_unenforced` returns 1 with no `### Files` table) | T-4 `a story the lock cannot police keeps RED on the stronger model` and `and says the lock is what is missing` (AC-3) | AC-1 (T-7), AC-2 (T-8), all T-7 AC-4/AC-5, AC-6 ×6 | T-5's AC-4 `SUPPRESSED`/`scanned from` assertions may go red too if the mutation empties the path list rather than only the verdict (the line would read `NOT CONSIDERED`) |
| 2. declared source paths dropped from the table-derived list | T-8 `but one DECLARED source path is enough for the lock to bite` (AC-2); T-8 `SUPPRESSED by the declared source path, and the paths came from the table` and `not APPLIES` (AC-2's visible half, filed under AC-4 in the file) | AC-1, AC-3 (T-4, T-5, T-9), T-7/T-5/T-9 AC-4, AC-5, AC-6 | T-8 `exactly one lock-coverage line` stays green — the line exists, it says the wrong thing |
| 3. lock-coverage line printed on `cmd_models`' stdout | AC-6: `stdout is exactly six lines` on all three fixtures (7), and `every one of them is PHASE<TAB>…` (1 malformed row) | AC-4 on every fixture — `cmd_both`'s `printf '%-9s …'` re-emits the tab-less line indented, so `^[[:space:]]*Lock coverage: ` still counts 1 | AC-5 will probably go red as well: `cmd_write`'s row loop would render the note as `\| Lock coverage: … \| \| \| \|`, which the column-0 needle does not match. That is the junk-row corruption AC-6 exists to catch, seen from the other side |

The recipe is in `## Deferred verifications`; each result goes there, not here.

### `gates.sh --fast` at the end of RED — the shape, not a pass

    PASS         format (1s, observed 79)
    PASS         lint (3s, observed 79, floor 1)
    PASS         typecheck (6s, observed 16)
    PASS         unit (136s, observed 355, floor 355)
    UNCONFIGURED coverage
    PASS         build (1s, observed 47816)
    PASS         harness (52s, observed 40)

    --fast skipped: integration mutation
    (not recorded in the story: a partial run is not evidence of anything)
    All required gates passed (6 ran, 1 unconfigured, 0 known).

**Green, and that is the predicted shape for this story, not a contradiction
of RED.** `## Context` says which gate would fail if this story's artifact
broke: none — every gate in `project.conf` judges the Luau project, and
`harness` runs `project-counters.test.sh` alone. The red for this story is in
`bash scripts/selftest.sh plan` (above), which CI runs as
`.github/workflows/gates.yml`'s separate `bash scripts/selftest.sh` step.
Lint and typecheck green means nothing in the test file trips a gate; there
is no timeout to budget, because no gate runs it.

Run twice (00:00-00:23 and 00:25-00:46 on 2026-09-23; ~20 min of each is the
config parse, the gates themselves ~4 min). **The first run failed `typecheck`
and seven `harness` cases, and that was the worktree, not the story**: this
worktree was created without `globalTypes.d.luau`, the gitignored Roblox type
dump `task install` fetches, so `test -s globalTypes.d.luau` failed silently
inside the typecheck command. Copied in from the main checkout (806,997
bytes, the size `environment.md` records for luau-lsp 1.69.0; it classifies
`vendor`, writable in every phase, and `git status` does not see it). Anyone
running gates from a fresh worktree of this repository will meet the same
thing; `bash scripts/task.sh install` is the documented fix.

### What RED found that GREEN should know

- **Cost.** 75 s per `plan.sh` call here. The suite is frozen in GREEN so it
  cannot grow, but an implementation that classifies each declared path with a
  separate `classify` fork *and* still runs the whole-section scan would add
  another forkful per call. Read the table, classify its rows, and skip the
  scan when there were rows.
- **The header row.** The fixtures carry this repository's exact convention,
  `| Path | \`classify.sh\` says | Who writes it |` then `|---|---|---|`. The
  first column of those two rows is `Path` and `---`; skip them by content, as
  the Contract says, not by position.
- **`section()` already includes `### Files`.** Confirmed: the T-7 Contract
  body arrives with both `###` headings inside it. No change to `section`.
- **`story_with` handles multi-line contracts as written.** Checked (the
  story asked): `sed -n 's/^CONTRACT://p'` emitted all eleven lines of T-7's
  body in order. No sibling helper was needed.
- **The two `2>` choices are deliberate and different.** `models_stdout` drops
  stderr because AC-6 is about the stream the parsers read; `plan` merges it
  because AC-4 is about what a human sees. Do not "fix" either.
- **Model.** This RED ran on the planned `fable` (`claude-fable-5-1`), no
  override reported to me. The `## Model guidance` success condition's three
  items: (1) `git status --short` names the two files only and
  `git diff --stat scripts/plan.sh` is empty — for the orchestrator to check
  against the tree; (2) the three mutations are named and declined above;
  (3) the verdict needles are anchored, counted, and demonstrated
  non-matching by the matrix, in the suite and by hand.

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A corrected test written against code that already exists passes
     on its first run whether or not it asserts anything: earn it by mutating
     the specific production behaviour it pins through `bash scripts/mutate.sh`,
     pasting the red, and confirming the revert. check-boundaries.sh refuses a
     PR whose Regressions section describes a failure without showing one. -->

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-23T18:22:12Z
    commit: 7aca86b (working tree had uncommitted changes)
    tree:   5120515c3ae6901a78b52b1afedfa018f44a5db8
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 79)
    PASS         lint (1s, observed 79, floor 1)
    PASS         typecheck (3s, observed 16)
    PASS         unit (31s, observed 355, floor 355)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 47816)
    PASS         harness (30s, observed 40)
    UNCONFIGURED mutation

## Notes

### PO decisions made at PLANNED

**PO decision 1 — the fix is a declaration, not a better filter.** The brief
offered four directions. The measurement settles it: five of HARNESS-012's
sixteen extracted tokens defeat the exception and only one of them is a path,
so any amount of regex tuning is chasing a moving target in prose that will
always be free-form. A `### Files` table is already this repository's own
convention — HARNESS-012's Contract has one, HARNESS-013's has one, and it names
the writer per path, which is exactly the "does this story **write** it"
question the detector is standing in for. Reading it is precise, cheap and
inspectable. The fallback stays so that nothing written before this story
changes.

**PO decision 2 — the announcement (AC-4, AC-5) is in this story, not a later
one.** It is what makes the remaining fallback safe: a story without a `###
Files` table still gets the old heuristic, and the old heuristic will still be
wrong sometimes. A wrong verdict that says what it was wrong about is a
one-minute fix; a silent one cost HARNESS-012's Lead PO a hand-written departure
and a success condition. It is also two printf sites and one rendering function,
not a new surface — and AC-6 is the control that stops it leaking into the TSV
three other callers parse.

**PO decision 3 — no `plan.sh paths <id>` subcommand.** Considered, for tests
and for humans, and dropped: the tests can interrogate the two outputs that
already exist, and a third surface is a third thing to keep in step with the
other two. Recorded so a reader sees it was declined rather than forgotten.

**PO decision 4 — `required_gates` stays `[]`, and no gate is added.** Same
answer and same reasoning as HARNESS-012's PO decision 2 and HARNESS-013's PO
decision 3: no gate in `project.conf` reads `.claude/tests/**`, `required_gates`
can only name a gate that exists, and `.github/workflows/gates.yml`'s
`bash scripts/selftest.sh` step is what actually runs this story's artifact on
every PR. Recorded so that an empty `required_gates` does not read as nobody
having asked.

**PO decision 5 — `depends_on` is empty, deliberately.** This story needs
nothing from `HARNESS-012` or `HARNESS-013`: `contract_unenforced()`,
`plan.test.sh` and `classify.sh` all exist on `main` today, and every criterion
is measured against a fixture the test writes. It touches no file either of the
other two touches, so the three can be in flight at once. HARNESS-012 is the
*evidence* for this story, not a dependency of it.

**PO decision 6 — the criteria were not changed after this file was written, so
this story carries no `## Amendments` section.** If one turns out to be wrong,
that is where it goes, after the orchestrator reproduces the finding on its own
inputs.

### Confirmation of the mechanism, by the Lead PO at PLANNED

The description in `## Context` is not taken from the brief. `contract_unenforced()`
was read at `scripts/plan.sh:96-110`, its extraction was replayed by hand over
`HARNESS-012`'s `## Contract` through the same `section` / `strip_comments` /
`grep -oE` pipeline the function uses, and the resulting sixteen tokens were put
through `bash scripts/classify.sh` in one call. The brief's account — one
fixture mention suppressing the exception — is correct as far as it goes and
understates the defect by four tokens, three of which are not paths at all.
`bash scripts/plan.sh models HARNESS-012` was run to confirm the rendered RED row
is `fable`.

### For the phases that follow

- **`gates.sh` stamps the *active* story.** A `gates.sh` or `ci-local.sh` run
  started from a worktree writes its record into whatever story is active, which
  may not be this one. Run `bash scripts/phase.sh show` before either.
- **The inner loop is `bash scripts/selftest.sh plan`** — one suite. A bare
  `bash scripts/selftest.sh` runs all 19 suites, takes 10-25 minutes on this
  machine, and two overlapping runs corrupt each other. Run the whole suite
  once, alone, before the PR.
- **A full `bash scripts/gates.sh` run exceeds 10 minutes here**, and
  `bash scripts/gates.sh --list` is minutes slow on this machine (seconds on
  CI). That is fork cost in the config parse, not a hang.
- **The phase lock will not enforce this story's RED→GREEN separation.** Both
  files are `harness`. The law still does — and this story is about the
  exception that exists because of that, so a phase that quietly crosses the
  line here would be evidence against its own subject.

### What GREEN built, and the controls it confirmed

**Shape.** `scripts/plan.sh` only; `.claude/tests/plan.test.sh` untouched
(`git hash-object` before and after: `fc05cede…`). Four new functions between
`field()` and `cmd_models()`, and two call sites:

- `declared_paths <contract-body>` — the `### Files` table's **first column**,
  rows dropped by content (`Path`, `^:?-{3,}:?$`, empty). The table ends at the
  next `###` heading, so T-7's `### Measurement` prose is outside it.
- `lock_scan <file>` — declared list first; the whole-section scan, byte for
  byte, only when the table yielded no rows; caches its verdict per file.
- `contract_unenforced <file>` — now two lines over `lock_scan`'s result. RED's
  `[ -n "$paths" ] || return 1` becomes `[ "$LC_COUNT" -gt 0 ] || { LC_ORIGIN=
  none; return 0; }` after the classify pass: the same verdict (`NOT
  CONSIDERED`, RED on the plain plan) for the same input. It is deliberately
  **one** guard and not two — an early `[ -n "$paths" ] || return 0` as well
  would have meant either could be mutated with the other still returning the
  right answer, and a rule no mutation can break is a rule no test pins. The
  probe RED ran to earn T-9 was re-run against this line:

      $ bash scripts/mutate.sh scripts/plan.sh \
          's/\[ "\$LC_COUNT" -gt 0 \] || { LC_ORIGIN=none; return 0; }/[ "$LC_COUNT" -gt -1 ] || { LC_ORIGIN=none; return 0; }/' \
          -- bash <scratch>/probe-t9.sh
      === mutate: scripts/plan.sh (1 line(s) changed by ...) ===
        190 -   [ "$LC_COUNT" -gt 0 ] || { LC_ORIGIN=none; return 0; }
        190 +   [ "$LC_COUNT" -gt -1 ] || { LC_ORIGIN=none; return 0; }

      RED	test-developer	opus	the lock freezes none of the paths this story names, ...
          FAIL a contract naming no paths at all follows the plain plan
               expected: 1
               actual:   0
      probe-t9: 0 passed, 1 failed

      === mutate: command exited 1; restored (verified byte-for-byte against
          .../.claude/state/mutations/scripts_plan.sh.20260923T161346Z.143572.bak) ===
        190:   [ "$LC_COUNT" -gt 0 ] || { LC_ORIGIN=none; return 0; }

  `git diff --stat scripts/plan.sh` showed only this story's own change
  afterwards and no `.bak` was left behind.
- `lock_coverage_line <file>` / `lock_offenders` — the one renderer, called by
  `cmd_both` (indented, after the plan) and by `cmd_write` (column 0, after the
  table, **inside** the markers). `cmd_models` never calls it.
- `classify_many` — `classify_stdin` once for the whole path list plus
  `is_ignored` only where the verdict is `source`, instead of `classify`'s four
  processes per path. RED warned that a per-path fork on top of the scan would
  make every call slower; this is the other direction.

**Negative controls, measured against the shipped script** (all through the
frozen suite, and separately through a single-call probe before it):

| Control | RED recorded | GREEN measured |
|---|---|---|
| AC-6 T-7 / T-8 / T-9: all-lines count, malformed rows | 6 / 0 each | 6 / 0 each — the line does not leak on any of the three branches |
| Zero-count verdict needles (`not APPLIES` / `not SUPPRESSED` / `not NOT CONSIDERED`) | 0, vacuously; "8 total" | 0, **while every sibling 1-count is 1** — so they now discriminate. There are **seven** of them, not eight: T-7 and T-5 and T-9 carry two each, T-8 carries one. Benign arithmetic slip in the handoff |
| Needle matrix over the four probe lines | `100 010 001 000 ` | `100 010 001 000 ` (instrument-only; unchanged by this fix, as intended) |
| Existing row count at `plan.test.sh:80` (lines with a tab) | 6 | 6 |
| `and nowhere else in the story file` after one `write`, T-7 | 0 at RED, 1 expected | 1, and still 1 after the second write |

`bash scripts/selftest.sh plan` — **84 passed, 0 failed**, run against the exact
bytes being handed on (11:28:01–11:46:29, 18m28s). `bash scripts/gates.sh
--fast` — `format`, `lint`, `typecheck`, `unit` (355), `build`, `harness` (40)
all PASS, `coverage` UNCONFIGURED, `integration` and `mutation` skipped as
`slow`; not recorded, because a partial run is not evidence.

**Three things the brief said that measurement did not bear out**, all benign:

- one `bash scripts/plan.sh models <id>` call is **39 s** here, not 75 s, and
  the whole suite is **~19 minutes**, not ~42. Same machine, same fixtures.
  `classify_many` accounts for some of it (it replaced up to four forks per
  path with one awk for the list) but not all; treat 39 s and 75 s as the same
  order of magnitude on a machine whose fork cost varies with what else is
  running, rather than as a speed-up this story delivered.
- the handoff's "eight zero-count needles" is **seven**: two each on T-7, T-5
  and T-9, one on T-8.
- **a backgrounded suite run reported `exit code 0` with its log truncated
  mid-suite, twice.** `scripts/selftest.sh plan` at 11:15:04 exited 0 at
  11:23:26 with only the first `describe` header in the log and no summary
  line; an earlier `gates.sh --fast` did the same, stopping after the last
  gate's output with no `--- gate summary ---` and no stamp written to
  `.claude/state/last-gate-run`. Both were re-run and both then completed
  normally, so nothing was wrong with the code — but **exit 0 is not evidence
  that either finished**. Read the log and require its last line
  (`N passed, M failed` / `All required gates passed`) before believing a run.
  This matters for GATES, which owes three mutation runs of ~19 minutes each.

**For GATES.** The three deferred mutations land on the new names:
mutation 1 on the fallback branch in `lock_scan` (the `LC_ORIGIN=scanned` line,
or `declared_paths`' `if [ -n "$paths" ]` above it), mutation 2 on the
`harness|docs|ignored)` arm or on `declared_paths`' output, mutation 3 by adding
a `lock_coverage_line "$file"` call inside `cmd_models`. Nothing about the
mutations' predictions changes. Where a whole-suite run is not needed, the
one-call probe pattern RED used (one `make_project_fixture`, one story body,
one `plan.sh` call, ~40 s) is much cheaper and was used throughout GREEN.

### Orchestrator's verification of GREEN, and two corrections it could not make itself

**Verified against the tree, not read out of the report.** `git status --short`
names `scripts/plan.sh`, `.claude/tests/plan.test.sh` and this story file.
`git hash-object .claude/tests/plan.test.sh` is
`fc05cedeed467f8f3ea4583db83725b1cc1c54c1`, which is the blob RED's own diff
recorded as `index bf15990..fc05ced` — so the frozen suite is byte-identical to
what RED handed over. No acceptance criterion moved. The consolidated guard's
re-probe is in `.claude/state/mutations/log` at `20260923T161346Z`:
`[ "$LC_COUNT" -gt 0 ]` → `-gt -1`, probe `exited 1`, `restored (verified)`, and
`.claude/state/mutations/` holds only `log`.

**Correction 1 — the dispatch brief asked for a check that cannot pass, and
GREEN was right to refuse it.** It required `git diff --stat
.claude/tests/plan.test.sh` to be empty. RED's 226 lines are *uncommitted*, so
that diff shows RED's own work on any healthy GREEN; the instruction would have
been satisfied only by a GREEN that had somehow reverted the tests. The right
check on an uncommitted RED is the **blob hash**, recorded before GREEN starts
and compared after — which is what GREEN substituted, unprompted, and what the
orchestrator confirmed above. The same defect is in this story's GREEN brief and
in the `advance-story` habit it came from; fixing it there is a candidate
follow-up, not this story.

**Correction 2 — the 75 s / 39 s discrepancy is contention, not mystery.**
GREEN measured 39 s per `plan.sh` call against RED's 75 s and recorded both
rather than choosing. The orchestrator can supply what neither agent could see:
throughout RED, this session was running its own `bash scripts/selftest.sh plan`
and `bash scripts/gates.sh --fast` in the background, against the same worktree.
RED's number was taken under load that GREEN's was not. Read 39 s as the
uncontended figure and 75 s as the figure under a competing suite — which is the
one GATES should plan with, since GATES runs three mutation suites and is the
phase most likely to have something else in flight.

**The truncated-log finding is carried forward as the instrument hazard it is.**
GREEN recorded two backgrounded runs reporting `exit code 0` with the log cut
off mid-suite and no summary line. `rules.md`'s "an assertion's needle is part of
the assertion" names a `grep '^ci-local:'` in a waiting loop whose failure mode
was to report a run green; this is the same hazard one level down, in the exit
status rather than the needle. Standing rule for the rest of this story: **a run
is believed only when its log's last line is `N passed, M failed` or
`All required gates passed`.** Exit 0 alone is not evidence that a run finished.

**Correction 2, now measured rather than inferred.** Two `gates.sh --fast` runs
of the same command against the same tree, one taken while a `selftest.sh plan`
run was in flight and one with the machine otherwise idle:

    gate       contended   idle
    format        2s        1s
    lint          3s        1s
    typecheck    18s        3s
    unit        302s       75s
    harness      90s       38s

A ~4x factor on the two long gates, which is the same factor between RED's 75 s
per `plan.sh` call and GREEN's 39 s. So the discrepancy is contention and
nothing else, and the practical rule for GATES is the one that follows from it:
**run one thing at a time on this machine.** Three mutation suites that would be
~19 minutes each alone become something closer to 40 if anything is racing them.

### REVIEW: PR #26, and its CI read as timings rather than a verdict

https://github.com/ryanczhang7/first-roblox/pull/26 — merged 2026-09-23T20:10:29Z
as `ab83e8f`. Both required checks passed first time; no review feedback, no
return to RED from REVIEW.

    boundaries   pass    5s
    gates        pass    2m36s

Per-step, from the gates job (run 35903196744), because the verdict alone is not
the thing to read:

    2. checkout                                    2s
    6. install the pinned toolchain                8s
    8. Harness self-test (bash scripts/selftest.sh)  1m53s   <- this story's own artifact
    9. Show configured gates (--list)              3s
   10. Audit the gate manifest (--audit)           4s
   11. Run gates (bash scripts/gates.sh)          22s

**The step worth watching is 8, and this story grew it.** `.github/workflows/gates.yml`
carries a comment naming the self-test as "the one thing in the repository
guaranteed to grow", with a worked case of a `windows-latest` job reaching 87% of
a 45-minute cap. This story took the `plan` suite from 48 to 84 assertions and
from ~20 to 29 `plan.sh` calls — roughly a 75% increase in the slowest suite —
and step 8 still ran in 1m53s for all 19 suites.

Two reasons that headroom is real rather than luck, both checked:

- **The runner is `ubuntu-latest`** (`gates.yml:10`), not the `windows-latest`
  the comment's worked case is about. The ~40x factor that comment measures is
  process-spawn cost on Windows, which is exactly what this suite is made of —
  it is why the same suite is ~19 minutes on the development machine and 113
  seconds here.
- **No `timeout-minutes` is set on the job**, so the cap is the runner default of
  360 minutes. 2m36s is well under 1% of it.

So the growth this story added is not a pending failure, and the thing that
would make it one is a change of `runs-on` rather than another story's worth of
assertions. Recorded here so the next story that grows the suite has a baseline
to compare against instead of re-deriving one.
