---
id: HARNESS-014
title: plan.sh's unenforced exception is suppressed by any path a story merely mentions
slug: plan-sh-s-unenforced-exception-is-suppre
epic: 
type: fix
status: todo
phase: PLANNED
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
    Lock coverage: SUPPRESSED by `src/core/world.ts` (source) — the phase lock freezes it, so RED follows the plain plan.
    Lock coverage: NOT CONSIDERED — this contract names no paths.

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
