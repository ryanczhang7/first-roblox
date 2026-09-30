---
id: HARNESS-020
title: Harness source is frozen during RED
slug: harness-source-is-frozen-during-red
epic: 
type: chore
status: done
phase: DONE
branch: story/HARNESS-020-harness-source-is-frozen-during-red
depends_on: [HARNESS-009]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

This is the half `HARNESS-009` deliberately left out (its `## Out of scope`, "The
other half of the exposure: harness *source* is not frozen during RED").
`HARNESS-009` closed the law-2 hole for the harness's own suites with check 3j in
`scripts/check-boundaries.sh`. This story closes the law-1 hole that mirrors it:

    $ bash scripts/classify.sh scripts/check-boundaries.sh .claude/hooks/phase-guard.sh
    harness	scripts/check-boundaries.sh
    harness	.claude/hooks/phase-guard.sh

`harness` is in every row of `.claude/harness/phases.conf`, so during RED an agent
can write the harness production code that makes its own new test pass, and the
lock says nothing. For an ordinary project file (`src/**`) that write is refused.
Every harness story in this repository has had its production code under
`scripts/**` or `.claude/hooks/**`, so the lock has not covered the production side of any of them.

### What was measured (on `main` at `4f4fa0c`)

**1. No commit on `main` wrote harness code while its story was at RED.** This uses
the same loop shape as `HARNESS-009`'s baseline: the story id comes from the commit
subject, and the phase comes from `git show "$c:docs/backlog/stories/$id.md"`. The
commits that touch `scripts/**` or `.claude/hooks/**`:

    GREEN  5729736 HARNESS-018   GREEN  a21f142 HARNESS-017   GREEN  b55700a HARNESS-013
    GREEN  db0fd46 HARNESS-009   GREEN  e0cc9f4 HARNESS-012
    REVIEW 08483ab HARNESS-014   REVIEW 2aab234 HARNESS-019   REVIEW 4b0033e BOOT-001
    REVIEW 6338f1c HARNESS-015   DONE   50b4b68 HARNESS-010
    (+ 6 unattributed: harness refreshes 19->27->30, and four direct harness commits)

   RED: **0**. So freezing this code in RED would not have refused anything
   anyone actually did. It is prospective, like 3j.

**2. That zero does not show the hole is small. It shows that a per-commit
check cannot see it.** The direction of the leak is the reverse of 3j's. A test
written in GREEN can only be committed at GREEN or later, and every one of those
phases forbids tests, so 3j sees it. Harness code written in RED is committed
*after* `phase.sh set <id> GREEN` on the ordinary forward path, at a phase that
may write it. Four of the ten commits above are a whole story in one REVIEW
commit (`2aab234`, `08483ab`, `6338f1c`, `4b0033e`), and they carry no record of
which phase wrote which line. Only the lock sees the write when it happens. This
is what decides the choice in `## Notes`.

**3. No harness test helper lives outside `.claude/tests/`.** A legitimate RED
might need to write a helper that is not under `.claude/tests/`, so this was
checked before the predicate was chosen. The suites source exactly one thing from
outside `.claude/tests/`, which is `.claude/hooks/lib.sh`, and they source it as
the code under test (`lib.test.sh`, `settings.test.sh`). They never use it as a
helper they write. `.claude/tests/_lib.sh` is the only test helper. Every other
reference to `scripts/*.sh` in a suite is a subject that the suite runs. So
freezing `scripts/**` and `.claude/hooks/**` in RED takes nothing that RED
legitimately writes.

**4. The prototype does not move the gate tree hash of an unchanged tree.** The
recommended split (below) was applied in a throwaway worktree. There,
`gate_tree_hash_of 01e502b` gives `e852f851933cb64800209a1cce52af276f8304a1` with
and without the split. That is exactly the tree `HARNESS-009`'s `## Gate results`
recorded. With the split, but with `gated_stdin` **not** taught the new category,
the same call gives `cd93a70e2b1c3b305ab5cd3fd47759b15b75c137` (amended; see `## Amendments`). At that point
`scripts/**` and `.claude/hooks/**` have dropped out of the hash. That is AC-6's
negative control, measured.

**The required gate that would fail if this story's artifact broke.** No `gates.sh`
gate reads it. `harness` runs `project-counters.test.sh` only (`project.conf:430`).
The artifact is lock behaviour, pinned in `.claude/tests/phase-guard.test.sh`,
`lib.test.sh`, `classify.test.sh` and `plan.test.sh`. CI's required `gates` job
runs all of those through `scripts/selftest.sh` (`.github/workflows/gates.yml:108`),
before `gates.sh` and in the same job, which is the route `HARNESS-006` §1 and
`HARNESS-009` established. `required_gates` stays empty because there is no
optional gate to promote.

## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

The artifact is a **new path category, `tooling`**, split out of `harness`. It is
the same move that split `manifest` out of `config`. It is **not** a
per-commit check in `check-boundaries.sh`; `## Notes` says why, with the
measurement. **AC-3 follows the user's answer to Q1** (PO decision 1 in `## Notes`).

- **AC-1**: Given any file under `scripts/` or `.claude/hooks/`, when
  `bash scripts/classify.sh <path>` classifies it, then the category printed is
  `tooling`. `bash scripts/classify.sh --list tooling scripts` lists the scripts,
  and `--list harness scripts` lists none of them.

- **AC-2**: Given an active story in `RED`, when a write targets a file under
  `scripts/` or `.claude/hooks/`, by the `Write` tool or by a shell redirect, then
  the phase lock denies it, and the denial names the path and `category: tooling`.
  The case must include an existing file (`scripts/check-boundaries.sh`,
  `.claude/hooks/lib.sh`) and a new one (`scripts/new-tool.sh`).

- **AC-3**: Given an active story in `PLANNED`,
  `REVIEW` or `DONE`, the same writes are denied. Given `GREEN`, `GATES` or
  `SCAFFOLD`, they are allowed. `tooling` is writable in exactly the rows where
  `source` is.

- **AC-4**: Given an active story in `RED`, when a write targets any other
  `harness` path, the lock allows it. The paths are `.claude/tests/x.test.sh`,
  `.claude/tests/_lib.sh`, `.gitignore`, `CLAUDE.md`, `.gitattributes`,
  `.github/workflows/gates.yml`, `.claude/commands/advance-story.md`,
  `.claude/harness/project.conf`, `.claude/harness/paths.conf` and
  `.claude/settings.json`. Each still classifies as `harness`. `rules.md` gives
  these their every-phase permission on purpose, and this story must not take it
  away.

- **AC-5**: Given an active story in `RED`, when the command is
  `bash scripts/mutate.sh scripts/check-boundaries.sh '<expr>' -- <cmd>` (or the
  same with a `.claude/hooks/` file), then the lock allows it. The sanctioned
  mutation keeps working on harness code in every phase. A plain redirect to the
  same file in the same phase is still denied (AC-2), so the exemption is
  `mutate.sh`'s alone.

- **AC-6**: Given a tree, when a file under `scripts/` changes, then
  `gate_tree_hash` changes. The same holds for `.claude/hooks/`. The gates' record
  of "the code they ran against" still covers harness code after the split.
  *Negative control:* with `tooling` absent from `gated_stdin`, the hash of
  `01e502b` measured `cd93a70e…` against `e852f851…`, so a check that passes
  either way asserts nothing.

- **AC-7**: Given the fixture's `phases.conf` edited so that `RED`'s row gains
  `tooling`, then AC-2's write is allowed. Restored, it is denied again. No edit
  to `phase-guard.sh` or `lib.sh` is needed. The verdict comes from
  `phases.conf` through `phase_allows`. It never comes from a path test or a
  list of phase names in the hook.
  *Negative control:* an implementation that special-cases `scripts/*` inside
  the hook passes AC-2 and fails this one. That failure is the whole point of
  the criterion.

- **AC-8**: Given a story whose `## Contract` declares a path under `scripts/` or
  `.claude/hooks/`, when `bash scripts/plan.sh models <id>` runs, then the RED
  `unenforced` exception does **not** fire for that path. The lock now freezes it,
  so it no longer counts as "harness/docs/ignored". A contract that declares only
  `harness` paths (for example `.claude/tests/x.test.sh` and
  `.claude/commands/x.md`) still triggers the exception.

- **AC-9**: Given `CLAUDE.md`'s phase-lock paragraph, which tells an agent that a
  guard bug is fixed in `.claude/tests/phase-guard.test.sh` and the guard, then it
  also says that the fix is never made from inside another story's RED. It is made
  with the lock cleared (`bash scripts/phase.sh clear`) or as its own story.
  (Q3, PO decision 3. This is a documentation criterion, checked by reading the
  file at REVIEW. No suite asserts prose, and none is added for it.)

## Contract

<!-- Amendable by RED in place, with a reason. -->

### Files

| Path | `classify.sh` says today | Who writes it | What changes |
|---|---|---|---|
| `.claude/harness/paths.conf` | `harness` | GREEN | the two `tooling` rules, and the header's category list |
| `.claude/harness/phases.conf` | `harness` | GREEN | `tooling` added to rows `IDLE`, `GREEN`, `GATES`, `SCAFFOLD` |
| `.claude/hooks/lib.sh` | `harness` | GREEN | `gated_stdin` keeps `tooling` (one condition) |
| `.claude/harness/rules.md` | `harness` | GREEN | the phase-permissions table, and one sentence on the category |
| `CLAUDE.md` | `harness` | GREEN | the guard-bug carve-out clause (Q3: yes, PO decision 3) |
| `.claude/tests/phase-guard.test.sh` | `harness` | RED | new `describe`, AC-2, AC-3, AC-4, AC-5, AC-7 |
| `.claude/tests/lib.test.sh` | `harness` | RED | classify cases :26/:28 flip to `tooling`, and the hash cases (AC-6) |
| `.claude/tests/classify.test.sh` | `harness` | RED | `--list tooling` (AC-1) |
| `.claude/tests/plan.test.sh` | `harness` | RED | AC-8, plus re-premising the fixtures listed under "Existing assertions" |

`scripts/phase-guard.sh`, `scripts/plan.sh` and `scripts/check-boundaries.sh`
are **not** in this table on purpose. None of them changes (see "Consumers").

### The predicate, exactly

In `paths.conf`, the harness block becomes:

    # --- Tooling: the harness's own production code ----------------------------
    # Split out of `harness` for the reason `manifest` was split out of `config`:
    # ... (GREEN writes the comment; it must say why .claude/tests/** is NOT here -
    # 3j covers it - and why the rest of `harness` keeps every-phase permission)
    tooling | .claude/hooks/**
    tooling | scripts/**
    harness | .claude/**
    harness | .github/**
    ...

- **The rules must come before `harness | .claude/**`,** because the first match
  wins, and `.claude/hooks/**` would otherwise be `harness`. The old
  `harness | scripts/**` line is **removed**, not left below the new one. A dead
  rule is a trap for the next reader.
- **The two paths are these exactly**, subject to Q2: `.claude/hooks/**` and
  `scripts/**`. The prototype confirmed that nothing else changes category. The
  remaining `harness` paths are `.claude/tests/**`, `.claude/commands|agents|skills/**`,
  `.claude/harness/**`, `.claude/settings.json`, `.claude/state/**`, `.github/**`,
  `CLAUDE.md`, `.gitignore`, `.gitattributes`, `.editorconfig`, `.mailmap` and
  `CODEOWNERS`.
- **The name is `tooling`.** It was chosen because it is not a substring of any
  existing category (`vendor ignored test source config manifest docs harness`),
  and none of them is a substring of it. `harness-code` was rejected because a
  needle `harness` matches it, and `rules.md` lists four of those needle
  failures. The user may rename it. If so, the rename goes in `## Amendments`
  and changes nothing else here.

In `phases.conf`, `tooling` is added immediately after `source` in every row
that has `source`: `IDLE`, `GREEN`, `GATES` and `SCAFFOLD`. That is Q1's
recommended answer. If Q1 is answered "RED only", it is added to every row
except `RED`, and AC-3 is amended to match.

### Consumers of the classifier, and what each sees

These were checked against the tree, not assumed. The files that switch on a
category name are listed first:

| Consumer | Where | Sees `tooling` as | Change? |
|---|---|---|---|
| the lock | `phase-guard.sh:31` → `phase_allows "$cat"` (`lib.sh:772`) | a row lookup in `phases.conf`, generic | **none**. Reused, not re-implemented |
| the gate hash | `gated_stdin`, `lib.sh:629` | dropped, unless listed | **yes**. Add `|| $1 == "tooling"` (AC-6). The `.md` exclusion stays `harness`-only |
| check 3a | `check-boundaries.sh:175-177` counts `source`/`test` | neither, the same as `harness` today | none |
| check 3a-bis | `check-boundaries.sh:263`, prefix grep | unaffected (path, not category) | none |
| check 3j | `check-boundaries.sh:570`, prefix `.claude/tests/` | unaffected | none |
| `covers` check | `gates.sh:585` keeps `source` only | not source, so no gate is asked to cover it | none |
| `plan.sh` lock scan | `plan.sh:219` `harness|docs|ignored) ;;` | **enforced**, which is correct (AC-8) | none |
| `classify.sh --list` | generic | `--list tooling` works | none |
| `inject-state.sh` | `phase_categories` prints the row | shows `tooling` in the row | none |
| `lib.sh:459` | the ignored check, `source` only | tracked paths, n/a | none |

**Rejected as a consumer, correcting `HARNESS-009` `## Notes` B.** That note said a
new category needs "an edit to `.claude/state/README.md`'s table and
`settings.test.sh`'s two-directional check". It does not. Those cover state
*files*, and this adds none. Checked by reading `settings.test.sh`, which never
reads a category.

**Nothing validates the set of categories.** No test or script checks that every
category in `paths.conf` appears somewhere in `phases.conf`. `phase_allows` fails
closed on a category no row lists, so a `paths.conf` rule without its
`phases.conf` column makes `scripts/**` unwritable in **every** phase that has
an active story, GREEN included. GREEN must land the two files together. See
`## Out of scope` for why the refresh path makes this more than theoretical.

### Changed signatures

None. No function changes shape. `gated_stdin` keeps its stdin/stdout contract;
only its predicate widens. Its callers are `gate_tree_hash` / `_hash_blob_listing`
(`lib.sh:651`), `code_changed_since` (`lib.sh:607`) and `check-boundaries.sh`
(which recomputes the hash). They were listed with
`grep -n gated_stdin scripts/*.sh .claude/hooks/*.sh`, and none needs editing.
The caller list to update is empty, and that was confirmed, not assumed.

### Existing assertions that pin today's behaviour, and must change in RED

The prototype (paths.conf, phases.conf and `gated_stdin` as above; nothing else)
was run through the whole of `scripts/selftest.sh` in a throwaway worktree. The
assertions that went red there are the ones that pin `scripts/**` or
`.claude/hooks/**` as `harness`:

    selftest.sh in the prototype: 3 of 21 suites FAILED (exit 1)
      lib:          145 passed, 2 failed
        FAIL classify .claude/hooks/lib.sh   expected: harness  actual: tooling   (lib.test.sh:26)
        FAIL classify scripts/gates.sh       expected: harness  actual: tooling   (lib.test.sh:28)
      plan:         98 passed, 19 failed
        which model each phase runs on
          FAIL a story the lock cannot police keeps RED on the stronger model
          FAIL and says the lock is what is missing
          FAIL a story that DECLARES only harness paths keeps RED on the stronger model, whatever its prose mentions   (T-7)
        the lock-coverage decision is said out loud
          FAIL and it says the exception APPLIES
          FAIL to all 2 paths declared in the ### Files table, not scanned from the text
          FAIL not SUPPRESSED
        the fallback scan counts only path-shaped tokens   (HARNESS-019's block)
          FAIL AC-1 x3, AC-2 x2, AC-3 x2, AC-4 x2   (each "APPLIES for N path(s)" / "not SUPPRESSED")
          FAIL AC-5: HARNESS-018, unmodified, reads Lock coverage: APPLIES from its Contract text
          FAIL AC-5: and is not SUPPRESSED
          FAIL AC-5: so HARNESS-018's RED is on the stronger model because the lock freezes none of its paths
        and written into the story with the plan
          FAIL and it is the same verdict the human plan gave
      harness-gate: 27 passed, 2 failed   <- ENVIRONMENTAL, not this change: see below

The last line is not caused by the change. A fresh worktree has no
`globalTypes.d.luau` or `Packages/`, because both are generated and gitignored,
so the typecheck gate inside `project-counters` could not run. Once those two
were copied in, `project-counters: 40 passed, 0 failed` and
`harness-gate: 29 passed, 0 failed` on the same prototype. Every other suite
passed unchanged: `phase-guard` 197/0, `boundaries` 125/0, `classify` 27/0,
`gates` 74/0, `settings` 20/0 and `refresh` 51/0. **`phase-guard.test.sh` has
no assertion that RED may write `scripts/**`.** Nothing there pins the hole, so
nothing there has to be re-premised.

**So the RED work on existing assertions is 2 in `lib.test.sh` and 19 in
`plan.test.sh`, and the lists above are exhaustive for this tree.** The 19 all
exist for one reason. `HARNESS-014` and `HARNESS-019` used `scripts/*.sh` and
`.claude/hooks/*` as their examples of "a path the lock does not freeze". That
premise is exactly what this story falsifies. RED re-premises each fixture onto a
path that stays `harness` (`.claude/tests/*.test.sh`, `.claude/commands/*.md`,
`.claude/harness/*.conf`), so each assertion keeps its intent. The exception is
`AC-5: HARNESS-018, unmodified`, which reads a real story. Its verdict genuinely
changes to `SUPPRESSED`, and the right correction is the expected value, not the
input. Its point is that the scan of a real story counts only path-shaped tokens,
and that survives the correction. RED may amend this guidance in place if it
finds a better one.

**Earning the 19.** They pass on arrival once re-premised, so they are tests
corrected against existing code. One probe covers most of them: through
`mutate.sh`, remove `harness` from `plan.sh:219`'s `harness|docs|ignored` case.
Every re-premised "APPLIES" assertion must then go red. Paste the run, and name
any of the 19 it did not turn red, together with the second probe that does.
AC-8's new assertion is ordinary RED, and fails until GREEN lands.

Two kinds, and RED treats them differently:

- **An expected value that flips** (for example `lib.test.sh:26`
  `".claude/hooks/lib.sh=harness"` becomes `=tooling`). These are ordinary RED.
  They fail now and pass after GREEN, which is watched to fail for the right
  reason.
- **A fixture whose premise changes** (for example `plan.test.sh` T-7, which
  declares `scripts/mutate.sh` in order to mean "a harness path"). Its intent is
  kept by swapping in a path that is still `harness`, and after that swap it
  **passes on arrival**. It is a test corrected against code that already exists,
  so it is earned by a `mutate.sh` probe on the behaviour it pins, with the output
  pasted into `## Handoff`. For T-7 that probe is dropping `harness` from
  `plan.sh:219`'s case.

### Oracle partition (see `story-authoring`)

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-4, AC-5 | **Mechanical** | Pin exactly: `category: tooling` and `path:     <p>` in the denial (the `assert_blocked` shape in `_lib.sh:185`), one command per path, with no loops that hide which path failed. |
| AC-3 | **Mechanical** | One `set_phase` per phase, and every phase named in the AC is covered. |
| AC-6 | **Settled** | Read the numbers out: `e852f851…` for `01e502b` unchanged, `cd93a70e…` for the broken predicate (amended). Do not re-derive them. Extend the existing `lib.test.sh:329` block ("a hook moves the hash") with "a script moves the hash". |
| AC-7 | **Mechanical, with a required negative control** | The control is the whole criterion. Edit the *fixture's* `phases.conf` (the one `make_fixture` copied), watch the verdict move, restore, and watch it move back. Use a `cp` restore from `$REPO_ROOT`, not `git checkout`: the CRLF lesson in `HARNESS-009`'s handoff. |
| AC-8 | **Mechanical** | Use `models_stdout` and `red_row` in `plan.test.sh`, anchored as they already are. |

### Test-only dependencies

None. The suites are bash. `_lib.sh` already provides `make_fixture`,
`set_phase`, `guard`, `assert_allowed` and `assert_blocked`. No manifest changes.

### Where the tests go

The lock behaviour goes in `.claude/tests/phase-guard.test.sh`, in a new
`describe` modelled on the manifest block at `:115-145`, which is the precedent
for splitting a category out. Classification goes in `lib.test.sh` and
`classify.test.sh`. AC-8 goes in `plan.test.sh`. No new suite: `HARNESS-006`'s
three-part test for one fails here, because each behaviour already has a home.

**The loop for RED is the four suites, not `gates.sh`:**

    bash .claude/tests/phase-guard.test.sh
    bash .claude/tests/lib.test.sh
    bash .claude/tests/classify.test.sh
    bash .claude/tests/plan.test.sh

Run them one at a time. `plan.test.sh` is slow on this machine; budget for it.

### This story's own RED is not protected by what it builds

The lock classifies `scripts/**` and `.claude/hooks/**` as `harness` until GREEN
lands, so this story's RED has the same hole it closes. The orchestrator
therefore takes the freeze by hash, as `HARNESS-015` built it for:

    bash scripts/frozen.sh snapshot scripts/*.sh .claude/hooks/*.sh \
      .claude/harness/paths.conf .claude/harness/phases.conf   # before RED
    bash scripts/frozen.sh verify                               # end of RED

The RED handoff pastes the `verify` line.

## Deferred verifications

<!-- Owner: the phase that runs it. Result pasted in by that phase. -->

**AC-4, AC-5 and AC-6 pass vacuously in RED, as do AC-3's GREEN, GATES and
SCAFFOLD halves.** Today every path involved is `harness`, which is writable in
every phase, and the hash already covers it. So "allowed" and "the hash moves"
are satisfied by a tree that has never heard of `tooling`. RED records the
expected value of each in `## Handoff`.

**DV-1. Owner: GREEN.** Once the split exists, GREEN runs the four suites in one
session and pastes:

| Control | Expected once `tooling` exists |
|---|---|
| AC-2: `echo x >> scripts/check-boundaries.sh` in RED | denied, `category: tooling` |
| AC-4: each of the ten `harness` paths in RED | allowed, and each still classifies `harness` |
| AC-5: `mutate.sh` on `scripts/check-boundaries.sh` in RED | allowed |
| AC-3: `scripts/new-tool.sh` in GREEN, GATES, SCAFFOLD | allowed |
| AC-6: `gate_tree_hash_of 01e502b` | `e852f851933cb64800209a1cce52af276f8304a1`, unchanged |

The AC-4 and AC-5 rows are the ones that matter, because "allowed" is also what
a split that never took effect produces. The distinguishing observation is AC-2's
denial in the **same run**.

**DV-1 result (GREEN, 2026-09-29, against the shipped config; working tree on
`81528ce` plus the GREEN edits).** Every expected value confirmed. One mismatch
with the story's *text*, none with the handoff: see the AC-6 control below.

Direct run of the real hook against a scratch fixture carrying the shipped
`paths.conf`/`phases.conf`, one shell, one session:

    [RED] echo x >> scripts/check-boundaries.sh -> permissionDecision":"deny path:     scripts/check-boundaries.sh category: tooling
    [RED] echo x > .claude/hooks/lib.sh -> permissionDecision":"deny path:     .claude/hooks/lib.sh category: tooling
    [RED] echo x >> .claude/tests/x.test.sh -> ALLOWED / harness
    [RED] echo x >> .claude/tests/_lib.sh -> ALLOWED / harness
    [RED] echo x >> .gitignore -> ALLOWED / harness
    [RED] echo x >> CLAUDE.md -> ALLOWED / harness
    [RED] echo x >> .gitattributes -> ALLOWED / harness
    [RED] echo x >> .github/workflows/gates.yml -> ALLOWED / harness
    [RED] echo x >> .claude/commands/advance-story.md -> ALLOWED / harness
    [RED] echo x >> .claude/harness/project.conf -> ALLOWED / harness
    [RED] echo x >> .claude/harness/paths.conf -> ALLOWED / harness
    [RED] echo x >> .claude/settings.json -> ALLOWED / harness
    [RED] mutate.sh scripts/check-boundaries.sh -> ALLOWED
    [RED] mutate.sh .claude/hooks/lib.sh -> ALLOWED
    [GREEN] echo x > scripts/new-tool.sh -> ALLOWED
    [GATES] echo x > scripts/new-tool.sh -> ALLOWED
    [SCAFFOLD] echo x > scripts/new-tool.sh -> ALLOWED
    gate_tree_hash_of 01e502b = e852f851933cb64800209a1cce52af276f8304a1

The same controls inside the suite, one run, `VERBOSE=1 bash
.claude/tests/phase-guard.test.sh` (excerpt; the AC-2 denials and the AC-4/AC-5
allows are the same run):

    ok   AC-2: RED denies a redirect onto scripts/check-boundaries.sh, as tooling
    ok   AC-2: RED denies a redirect creating scripts/new-tool.sh, as tooling
    ok   allows: AC-3: GREEN allows scripts/new-tool.sh
    ok   allows: AC-3: GATES allows scripts/new-tool.sh
    ok   allows: AC-3: SCAFFOLD allows scripts/new-tool.sh
    ok   allows: AC-4: RED still allows .claude/tests/x.test.sh      (and the other nine, each ok)
    ok   allows: AC-5: RED allows mutate.sh on scripts/check-boundaries.sh
    ok   allows: AC-5: RED allows mutate.sh on .claude/hooks/lib.sh
    ok   AC-5: while a plain redirect onto that same scripts/check-boundaries.sh is denied
    ok   AC-7: the fixture's RED row now lists tooling (the edit landed)
    ok   allows: AC-7: with tooling in RED's row of phases.conf, RED allows scripts/check-boundaries.sh
    ok   AC-7: restored byte for byte from the real phases.conf
    ok   AC-7: restored, RED denies scripts/check-boundaries.sh again
    phase-guard: 242 passed, 0 failed

AC-6 negative control against the **shipped** `gated_stdin`, through
`mutate.sh`:

    632 -       || $1 == "tooling") \
    632 +       ) \
    control: gate_tree_hash_of 01e502b = cd93a70e2b1c3b305ab5cd3fd47759b15b75c137
    === mutate: command exited 0; restored (verified byte-for-byte against .../.claude_hooks_lib.sh.20260929T213802Z.279.bak) ===

This matches the handoff's `cd93a70e…` and the orchestrator's reproduction. It
does **not** match the `81917885…` in AC-6's text and `## Context` §4, which is
the amendment already pending in `## Notes`. The claim holds; the literal is
wrong.

Handoff table, row by row: AC-2 denied/tooling (match); AC-4 allowed/harness x10
(match); AC-5 allowed x2 (match); AC-3 allowed in GREEN/GATES/SCAFFOLD (match);
AC-6 `e852f851…` (match); AC-6 control `cd93a70e…` (match to handoff); AC-6
in-suite control and AC-7 control are mutation probes of DV-2's kind and were
not re-run here; AC-7 instrument 1 (match, `ok` line above). Suite totals equal
RED's prototype numbers exactly: phase-guard 242/0, lib 158/0, classify 36/0,
plan 130/0.

**DV-2. Owner: GATES.** Three mutations through `scripts/mutate.sh`, each against
the shipped config, and each must turn its named assertion red:

1. Drop `|| $1 == "tooling"` from `gated_stdin`. Then "a hook moves the hash"
   and "a script moves the hash" (AC-6) must fail. This is the missing-field kind.
2. Change `tooling | scripts/**` to `tooling | script/**`. Then AC-1's `scripts/`
   case and AC-2's `scripts/` denial must fail, and the `.claude/hooks/` cases
   must stay green. This is the **wrong-value** kind: the rule is still present
   and still parses, and it matches nothing.
3. Add `tooling` to `phases.conf`'s `RED` row. Then AC-2 must fail. This is
   AC-7's mechanism run in the other direction against the real file, and not
   the fixture.

Paste each run's red and its `mutate.sh` restore line.

**DV-2 result (GATES, orchestrator, 2026-09-29, against `2f1b524`).** All three
mutations were made through `mutate.sh`, and each turned exactly its predicted assertions red and was restored
byte-for-byte. Mutation 2 is the wrong-value kind: every `scripts/` case went red, and
no `.claude/hooks/` case did. Mutation 3 also turns AC-7's "restored, denied again"
red, because the fixture copies the mutated real `phases.conf`. Verbatim:

    ### DV-2 mutation 1
    === mutate: .claude/hooks/lib.sh (1 line(s) changed by 632s/|| [$]1 == "tooling") /) /) ===
      632 -       || $1 == "tooling") \
      632 +       ) \
    
    === mutate: running bash -c bash .claude/tests/lib.test.sh 2>&1 | grep -E "^ *FAIL|passed, [0-9]+ failed" ===
        FAIL a hook moves the hash
        FAIL adding a script moves the hash
        FAIL a script moves the hash
    lib: 155 passed, 3 failed
    
    === mutate: command exited 0; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_hooks_lib.sh.20260929T215622Z.56613.bak) ===
      632:       || $1 == "tooling") \
    ### DV-2 mutation 2
    === mutate: .claude/harness/paths.conf (1 line(s) changed by 97s#^tooling | scripts/\*\*$#tooling | script/**#) ===
      97 - tooling | scripts/**
      97 + tooling | script/**
    
    === mutate: running bash -c bash .claude/tests/lib.test.sh 2>&1 | grep -E "^ *FAIL|passed, [0-9]+ failed"; bash .claude/tests/phase-guard.test.sh 2>&1 | grep -E "^ *FAIL|passed, [0-9]+ failed" ===
        FAIL classify scripts/gates.sh
        FAIL classify scripts/check-boundaries.sh
        FAIL classify scripts/new-tool.sh
    lib: 155 passed, 3 failed
        FAIL AC-2: RED denies Write to scripts/check-boundaries.sh, as tooling
        FAIL AC-2: RED denies Write to a NEW scripts/new-tool.sh, as tooling
        FAIL AC-2: RED denies a redirect onto scripts/check-boundaries.sh, as tooling
        FAIL AC-2: RED denies a redirect creating scripts/new-tool.sh, as tooling
        FAIL AC-3: PLANNED denies scripts/check-boundaries.sh
        FAIL AC-3: PLANNED denies scripts/new-tool.sh
        FAIL AC-3: REVIEW denies scripts/check-boundaries.sh
        FAIL AC-3: REVIEW denies scripts/new-tool.sh
        FAIL AC-3: DONE denies scripts/check-boundaries.sh
        FAIL AC-3: DONE denies scripts/new-tool.sh
        FAIL AC-5: while a plain redirect onto that same scripts/check-boundaries.sh is denied
        FAIL AC-5: a mutate.sh payload that writes tooling in RED is still denied
        FAIL allows: AC-7: with tooling in RED's row of phases.conf, RED allows scripts/check-boundaries.sh
        FAIL allows: AC-7: and scripts/new-tool.sh
        FAIL AC-7: restored, RED denies scripts/check-boundaries.sh again
        FAIL AC-7: and scripts/new-tool.sh again
    phase-guard: 226 passed, 16 failed
    
    === mutate: command exited 0; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_paths.conf.20260929T215641Z.57848.bak) ===
      97: tooling | scripts/**
    ### DV-2 mutation 3
    === mutate: .claude/harness/phases.conf (1 line(s) changed by 15s/| vendor,ignored,test,manifest,docs,harness |/| vendor,ignored,test,tooling,manifest,docs,harness |/) ===
      15 - RED      | vendor,ignored,test,manifest,docs,harness | Story is in RED. Production code is frozen: write the failing test first, and let it fail for the right reason. Move to GREEN with: bash scripts/phase.sh set <id> GREEN
      15 + RED      | vendor,ignored,test,tooling,manifest,docs,harness | Story is in RED. Production code is frozen: write the failing test first, and let it fail for the right reason. Move to GREEN with: bash scripts/phase.sh set <id> GREEN
    
    === mutate: running bash -c bash .claude/tests/phase-guard.test.sh 2>&1 | grep -E "^ *FAIL|passed, [0-9]+ failed" ===
        FAIL AC-2: RED denies Write to scripts/check-boundaries.sh, as tooling
        FAIL AC-2: RED denies Write to .claude/hooks/lib.sh, as tooling
        FAIL AC-2: RED denies Write to a NEW scripts/new-tool.sh, as tooling
        FAIL AC-2: RED denies a redirect onto scripts/check-boundaries.sh, as tooling
        FAIL AC-2: RED denies a redirect onto .claude/hooks/lib.sh, as tooling
        FAIL AC-2: RED denies a redirect creating scripts/new-tool.sh, as tooling
        FAIL AC-5: while a plain redirect onto that same scripts/check-boundaries.sh is denied
        FAIL AC-5: and onto that same .claude/hooks/lib.sh
        FAIL AC-5: a mutate.sh payload that writes tooling in RED is still denied
        FAIL AC-7: restored, RED denies scripts/check-boundaries.sh again
        FAIL AC-7: and scripts/new-tool.sh again
    phase-guard: 231 passed, 11 failed
    
    === mutate: command exited 0; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_phases.conf.20260929T220743Z.86688.bak) ===
      15: RED      | vendor,ignored,test,manifest,docs,harness | Story is in RED. Production code is frozen: write the failing test first, and let it fail for the right reason. Move to GREEN with: bash scripts/phase.sh set <id> GREEN

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

### A-1. AC-6's negative-control hash (2026-09-30, approved by the user)

- **Which:** AC-6, its *Negative control* sentence. The same literal also appears in
  `## Context` §4 and in the AC-6 row of the oracle-partition table, and all three
  are corrected.
- **Said:** "with `tooling` absent from `gated_stdin`, the hash of `01e502b`
  measured `81917885…` against `e852f851…`".
- **Says now:** "... measured `cd93a70e…` against `e852f851…`". Nothing else in the
  criterion changed.
- **Why:** the planning prototype's number did not reproduce. The RED subagent
  measured `cd93a70e2b1c3b305ab5cd3fd47759b15b75c137`. The orchestrator
  reproduced it by a different method, without the subagent's code or any change
  to a frozen file (`## Notes`, "AC-6's recorded negative-control hash is
  wrong"): hashing `git ls-tree -r 01e502b` through `classify_stdin | gated_stdin`,
  with and without the `scripts/` and `.claude/hooks/` paths. The calibration run
  reproduced `e852f851…` exactly. GREEN measured the same `cd93a70e…` against the
  shipped `lib.sh` through `mutate.sh`. The criterion's claim, that the broken
  predicate gives a different hash, held throughout. No test reads the literal.
- **Approved by:** the user, in chat ("approve the AC-6 amendment"), after PR #38
  merged. So the correction lands in the DONE commit on `main`.

### REVIEW → DONE (2026-09-30)

PR #38 merged as `faf147f`. CI on `5e0d962`: `boundaries` success (the check ran
in about 1s), `gates` success. In the gates job, the harness self-test took 2m18s and
`Run gates` took 27s, against `timeout-minutes: 45`. No limit is within 10 %, and no gate
reached REVIEW pending CI.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-020` from `.claude/harness/models.conf`.
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

Lock coverage: APPLIES — all 9 path(s) declared in the Contract's ### Files table are harness/docs/ignored, so RED stays on the stronger model.
<!-- plan.sh:generated:end -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- RED - test-developer - claude-opus-5-5 (Opus 5.5; planned `opus`, no override)
- GREEN - feature-developer - claude-opus-5-5 (Opus 5.5; planned `opus`, no override)

## Out of scope

- **A per-commit CI check (option C) is not built here.** `## Context` §2 says
  why it cannot see this leak. If CI evidence that RED touched no production
  code is wanted, it is wanted for `src/**` too, since nothing in
  `check-boundaries.sh` checks that for ordinary source either. That would be a
  separate story, applying to both categories at once.
- **`.claude/settings.json` and `.github/workflows/**` stay `harness`** unless
  Q2 says otherwise. They are harness *configuration*, and freezing them is a
  different argument, with its own blast radius (CI edits from RED, and hook
  wiring).
- **`paths.conf` and `phases.conf` themselves stay writable in every phase.**
  That means RED could, in principle, add `tooling` to its own row. `rules.md`
  keeps those files writable in every phase on purpose. Guarding the guard's
  configuration is its own question, and it is not this one.
- **Upstreaming to `../agentic-dev-harness` (release 55; this tree is 30).**
  `refresh-harness.sh` REPLACES `phases.conf`, `rules.md`, `.claude/hooks/**`,
  `.claude/tests/**` and `scripts/*.sh`, but asks for `paths.conf` to be merged
  by hand with upstream as the base. A refresh after this story would revert
  `phases.conf` and `gated_stdin`. If `tooling` survived in the merged
  `paths.conf`, `scripts/**` would become unwritable in every phase. Check 3j is
  in the same position already (upstream has no 3j). That is a harness-level
  decision for the user, and is recorded as Q4.
- **No change to `plan.sh`, `phase-guard.sh` or `check-boundaries.sh`.** If GREEN
  finds itself editing one of them, the category is being special-cased
  somewhere, and AC-7 exists to catch exactly that. Stop and say so.
- **No new gate.** `## Gate probes` is omitted. The artifact is lock
  configuration, asserted by suites CI already runs.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

All bash, all in the four existing suites; no new suite, no dependency.

| AC | Suite | Level | Tests |
|---|---|---|---|
| AC-1 | `classify.test.sh`, describe "the harness's own code is tooling, not harness" | CLI (`scripts/classify.sh` on a fixture carrying the real scripts/hooks) | `scripts/check-boundaries.sh`, `.claude/hooks/phase-guard.sh`, new `scripts/new-tool.sh` print `tooling`; `--list tooling` accepted (rc 0); `--list tooling scripts` equals git's list of `scripts/` exactly; `--list harness scripts` empty; same pair for `.claude/hooks`; instrument: expected list contains `scripts/check-boundaries.sh` |
| AC-1, AC-4 | `lib.test.sh`, describe "classify: paths.conf rules" | unit (`classify`) | `.claude/hooks/lib.sh`, `.claude/hooks/phase-guard.sh`, `scripts/gates.sh`, `scripts/check-boundaries.sh`, `scripts/new-tool.sh` = `tooling` (the first and third are the two flipped cases); the ten AC-4 paths = `harness` (six added, four already there) |
| AC-2 | `phase-guard.test.sh`, describe "the harness's own code is tooling, and frozen wherever source is" | hook end to end | RED: Write tool and redirect, each onto `scripts/check-boundaries.sh`, `.claude/hooks/lib.sh` (both exist in the fixture) and `scripts/new-tool.sh` (new) - denied, reason names `path:     <p>` then `category: tooling ` |
| AC-3 | same describe | hook | one `set_phase` each: PLANNED, REVIEW, DONE deny the three paths (tooling); GREEN, GATES, SCAFFOLD allow them |
| AC-4 | same describe | hook | RED allows a redirect onto each of the ten paths, one line each |
| AC-5 | same describe | hook | RED allows `mutate.sh scripts/check-boundaries.sh ... -- true` and `mutate.sh .claude/hooks/lib.sh ... -- true`; plain redirects onto the same two files denied (tooling); a mutate.sh payload `cp ... scripts/new-tool.sh` denied (tooling) |
| AC-6 | `lib.test.sh`, describe "gate_tree_hash" | unit | existing "a hook moves the hash", plus "adding a script moves the hash" and "a script moves the hash" |
| AC-7 | `phase-guard.test.sh`, same describe | hook | awk adds `tooling` to the FIXTURE's RED row; instrument asserts it landed; RED then allows `scripts/check-boundaries.sh` and `scripts/new-tool.sh`; `cp` restore from `$REPO_ROOT`, `cmp` asserts byte-identical; both denied again (tooling) |
| AC-8 | `plan.test.sh`, describe "the harness's own code is enforced now" | CLI (`plan.sh`, stdout via `models_stdout`, anchored `red_row`/`lines_matching`) | T-80 declares `scripts/new-tool.sh`: SUPPRESSED by it `(tooling)` from the table, not APPLIES, RED `fable`, not the unenforced row. T-81 the same for `.claude/hooks/phase-guard.sh`. Control T-82 (`.claude/tests/x.test.sh` + `.claude/commands/x.md`): APPLIES for 2 declared paths, not SUPPRESSED, RED `opus` with the unenforced reason |
| (re-premise) | `plan.test.sh` | CLI | the 19 listed in `## Contract`: 16 re-premised onto still-`harness` paths, 3 (HARNESS-018 AC-5) replaced by the corrected verdict (SUPPRESSED by its two tooling paths, no source/test/config offender, not APPLIES, RED `fable`). T-5 and T-8 also re-premised (not in the 19; see Handoff) |
| AC-9 | none | - | prose, checked at REVIEW (story says so) |

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain:
       * the exact command that runs the new tests
       * the failure output, and why it is the RIGHT failure
       * every file touched, and which AC each test covers
       * the EXPORT SHAPE the tests already pin
       * any test that passed on arrival, and the probe or negative control
         that earns it
       * the EXPECTED VALUE of every negative control, as a table
       * anything discovered that changes the approach -->

### Commands (one at a time, never concurrently)

    bash .claude/tests/phase-guard.test.sh
    bash .claude/tests/lib.test.sh
    bash .claude/tests/classify.test.sh
    bash .claude/tests/plan.test.sh        # ~3.5 min here; give it a 600 s timeout
    bash .claude/tests/pipe-readers.test.sh   # must stay 11 passed, 0 failed

### Failure output in RED (tree at `1b8db48` + these test edits)

    phase-guard: 222 passed, 20 failed
      FAIL AC-2: RED denies Write to scripts/check-boundaries.sh, as tooling        not blocked at all
      FAIL AC-2: RED denies Write to .claude/hooks/lib.sh, as tooling               not blocked at all
      FAIL AC-2: RED denies Write to a NEW scripts/new-tool.sh, as tooling          not blocked at all
      FAIL AC-2: RED denies a redirect onto scripts/check-boundaries.sh, as tooling not blocked at all
      FAIL AC-2: RED denies a redirect onto .claude/hooks/lib.sh, as tooling        not blocked at all
      FAIL AC-2: RED denies a redirect creating scripts/new-tool.sh, as tooling     not blocked at all
      FAIL AC-3: {PLANNED,REVIEW,DONE} denies {scripts/check-boundaries.sh,.claude/hooks/lib.sh,scripts/new-tool.sh}  (9 lines, each "not blocked at all")
      FAIL AC-5: while a plain redirect onto that same scripts/check-boundaries.sh is denied   not blocked at all
      FAIL AC-5: and onto that same .claude/hooks/lib.sh                                        not blocked at all
      FAIL AC-5: a mutate.sh payload that writes tooling in RED is still denied                 not blocked at all
      FAIL AC-7: restored, RED denies scripts/check-boundaries.sh again                         not blocked at all
      FAIL AC-7: and scripts/new-tool.sh again                                                  not blocked at all

    lib: 153 passed, 5 failed
      FAIL classify .claude/hooks/lib.sh           expected: tooling  actual: harness
      FAIL classify .claude/hooks/phase-guard.sh   expected: tooling  actual: harness
      FAIL classify scripts/gates.sh               expected: tooling  actual: harness
      FAIL classify scripts/check-boundaries.sh    expected: tooling  actual: harness
      FAIL classify scripts/new-tool.sh            expected: tooling  actual: harness

    classify: 28 passed, 8 failed
      FAIL scripts/check-boundaries.sh classifies as tooling   expected: tooling<TAB>scripts/check-boundaries.sh  actual: harness<TAB>...
      FAIL .claude/hooks/phase-guard.sh classifies as tooling  (same shape)
      FAIL a new file under scripts/ classifies as tooling     (same shape)
      FAIL --list tooling is accepted                          expected: 0  actual: 2   (unknown category)
      FAIL --list tooling scripts lists every script           expected: <every scripts/ file>  actual: <usage error>
      FAIL --list harness scripts lists none of them           expected: ''  actual: scripts/check-boundaries.sh ...
      FAIL --list tooling .claude/hooks lists every hook       (same shape)
      FAIL --list harness .claude/hooks lists none of them     (same shape)

    plan: 118 passed, 12 failed
      FAIL AC-5: HARNESS-018, unmodified, reads Lock coverage: SUPPRESSED from its Contract text   expected 1 actual 0
      FAIL AC-5: suppressed by its real tooling path .claude/hooks/lib.sh                           expected 1 actual 0
      FAIL AC-5: and by its real tooling path scripts/refresh-harness.sh                            expected 1 actual 0
      FAIL AC-5: and is not APPLIES                                                                 expected 0 actual 1
      FAIL AC-5: so HARNESS-018's RED follows the plain plan, because the lock now freezes its paths expected 1 actual 0
      FAIL AC-8: a declared scripts/ path SUPPRESSES the exception, as tooling, from the table       expected 1 actual 0
      FAIL AC-8: and the scripts/ story does not read APPLIES                                       expected 0 actual 1
      FAIL AC-8: so a scripts/ story's RED follows the plain plan                                   expected 1 actual 0
      FAIL AC-8: and not the unenforced row                                                         expected 0 actual 1
      FAIL AC-8: a declared .claude/hooks/ path SUPPRESSES the exception, as tooling, from the table expected 1 actual 0
      FAIL AC-8: and the hooks story does not read APPLIES                                          expected 0 actual 1
      FAIL AC-8: so a hooks story's RED follows the plain plan                                      expected 1 actual 0

    pipe-readers: 11 passed, 0 failed

**Why these are the right failures.** Every one of them is the lock, the
classifier or plan.sh giving today's answer (`harness`, which is writable in
every phase and which plan.sh treats as unenforced). None is a syntax error, a
missing helper, or a timeout. `--list tooling` failing with rc 2 is the
classifier saying the category does not exist yet. `gates.sh --fast` ran: all 6
required gates PASS. That is expected, because no gate reads these suites (see
`## Context`). CI runs them through `selftest.sh`.

**The tests are checked against the intended implementation, not only against
its absence.** The three `## Contract` config edits were applied through nested
`scripts/mutate.sh`, and each file was restored and verified with `cmp`. The
edits: paths.conf gets `tooling | .claude/hooks/**` before `harness | .claude/**`,
and `harness | scripts/**` becomes `tooling | scripts/**`. phases.conf gets
`,source,` → `,source,tooling,`. `gated_stdin` gets `|| $1 == "tooling"`. With
those edits:

    phase-guard: 242 passed, 0 failed
    lib: 158 passed, 0 failed
    classify: 36 passed, 0 failed      (paths.conf edit only)
    plan: 130 passed, 0 failed         (paths.conf edit only)

So nothing else is needed. Specifically, **plan.sh, phase-guard.sh and
check-boundaries.sh need no edit.**

### Files touched

| File | AC |
|---|---|
| `.claude/tests/phase-guard.test.sh` | AC-2, AC-3, AC-4, AC-5, AC-7: new describe after the manifest block, with local helper `assert_tooling_denied` |
| `.claude/tests/lib.test.sh` | AC-1 and AC-4 classify cases (`:26`/`:28` flipped to `tooling`, 3 tooling and 6 harness cases added), AC-6 (two hash cases) |
| `.claude/tests/classify.test.sh` | AC-1 |
| `.claude/tests/plan.test.sh` | AC-8 (new describe, T-80/81/82), AC-5-of-HARNESS-019 corrected, 16+2 fixtures re-premised |
| this story | `## Test plan`, this handoff, a Resolved line |

Nothing else changed. `git diff --stat -- scripts .claude/hooks .claude/harness CLAUDE.md`
is empty, `.claude/state/mutations/` holds no `.bak`, and:

    frozen: OK — 21 path(s) unchanged since the snapshot for HARNESS-020

### Export shape the tests pin

This is not a module, so there are no exported names. What the tests pin:

- `bash scripts/classify.sh <p>` prints `tooling<TAB><p>` for any path under
  `scripts/` or `.claude/hooks/`, including one that does not exist yet.
  `--only tooling` and `--list tooling` are accepted, which follows from the
  category appearing in `paths.conf`.
- `classify <p>` in `lib.sh` returns `tooling` for the same paths. It returns
  `harness` for `.claude/tests/**`, `.claude/commands/**`, `.claude/harness/*.conf`,
  `.claude/settings.json`, `.github/**`, `CLAUDE.md`, `.gitignore` and `.gitattributes`.
- The denial layout is unchanged: `path:     <p>` on one line and
  `category: tooling` on the next. The test anchors on `path:     <p> ` followed
  later by `category: tooling `, with the trailing spaces.
- `plan.sh`'s lock-coverage line names a tooling offender as `` `<p>` (tooling) ``.
  It already does this generically.
- **Not constrained:** where exactly in `paths.conf` the rules sit, as long as
  the `.claude/hooks/**` rule comes before `harness | .claude/**`. Also not
  constrained: the comment wording, and the column position of `tooling` inside
  a phases.conf row. `phase_allows` strips whitespace and matches the category
  as a comma-delimited item.

### Passed on arrival, and what earns each

**Vacuous in RED, and not claimed.** These go to DV-1, owner GREEN:

- AC-3's allowing half (9)
- AC-4 (10 hook assertions, plus the six new `harness` classify cases in lib.test.sh)
- AC-5's two `mutate.sh`-allowed assertions
- AC-6's hook and script hash cases
- AC-7's instrument, its two "allowed with tooling in RED's row" assertions, and its `cmp` restore check
- classify's "there are scripts to list" instrument
- plan's "AC-5: and by no prose or bare filename" guard
- the AC-8 control (T-82)

**Earned by probes.** Each probe was run through `scripts/mutate.sh`, and every
restore was verified by `cmp`:

1. **AC-7's control fires, and it fires hard.** The config edits were applied,
   plus a hook special-case: `phase-guard.sh:32`
   `if ! phase_allows "$cat" || { [ "$cat" = tooling ] && [ "$PHASE" = RED ]; }; then`.

       FAIL allows: AC-7: with tooling in RED's row of phases.conf, RED allows scripts/check-boundaries.sh
            blocked with: ... path:     scripts/check-boundaries.sh   category: tooling ...
       FAIL allows: AC-7: and scripts/new-tool.sh
       phase-guard: 240 passed, 2 failed
       === mutate: command exited 1; restored (verified byte-for-byte ...phase-guard.sh...bak) ===

2. **AC-6's control fires.** paths.conf and phases.conf were split, and
   `gated_stdin` was NOT taught `tooling`:

       FAIL a hook moves the hash            unchanged: abe95fa564484de8ffcbda9c4002a91362d75928
       FAIL adding a script moves the hash   unchanged: abe95fa5...
       FAIL a script moves the hash          unchanged: abe95fa5...
       lib: 155 passed, 3 failed

3. **The re-premised plan.test.sh fixtures.** This is the contract's probe, run
   against TODAY's config (the code they were corrected against):
   `bash scripts/mutate.sh scripts/plan.sh 's/^      harness|docs|ignored) ;;$/      docs|ignored) ;;/' -- bash .claude/tests/plan.test.sh`

       219 -       harness|docs|ignored) ;;
       219 +       docs|ignored) ;;
       FAIL a story the lock cannot police keeps RED on the stronger model
       FAIL and says the lock is what is missing
       FAIL a story that DECLARES only harness paths keeps RED on the stronger model, whatever its prose mentions
       FAIL and it says the exception APPLIES
       FAIL to all 2 paths declared in the ### Files table, not scanned from the text
       FAIL not SUPPRESSED
       FAIL AC-1: a Contract naming two harness paths, plus prose and their bare names, APPLIES for exactly those 2 paths
       FAIL AC-1: and is not SUPPRESSED by the prose or a bare filename
       FAIL AC-1: so RED stays on the stronger model because the lock freezes none of the paths
       FAIL AC-2: the same bare filename ABSENT from the root is not a path, so it APPLIES for 1 path
       FAIL AC-2: with rokit.toml absent the verdict is not SUPPRESSED
       FAIL AC-3: version-like tokens are never counted, even with a file named 5.3.15 at the root, so it APPLIES for 1 path
       FAIL AC-3: and a version number does not SUPPRESS the exception
       FAIL AC-4: a missing partial path that trails another scanned path is not counted twice, so it APPLIES for 1 path
       FAIL AC-4: and the partial path does not SUPPRESS the exception as source
       FAIL AC-5: suppressed by its real tooling path .claude/hooks/lib.sh
       FAIL AC-5: and by its real tooling path scripts/refresh-harness.sh
       FAIL AC-8: a declared scripts/ path SUPPRESSES the exception, as tooling, from the table
       FAIL AC-8: a declared .claude/hooks/ path SUPPRESSES the exception, as tooling, from the table
       FAIL AC-8 control: a contract declaring only harness paths still APPLIES, for both of them
       FAIL AC-8 control: and is not SUPPRESSED
       FAIL AC-8 control: so its RED stays on the stronger model, for the lock's reason
       FAIL and it is the same verdict the human plan gave
       plan: 107 passed, 23 failed
       === mutate: command exited 1; restored (verified byte-for-byte ...scripts_plan.sh...bak) ===

   All 16 re-premised assertions went red, as did the AC-8 control. **None of the
   19 escaped this probe except the three HARNESS-018 `AC-5` assertions.** Those
   were not re-premised: their expected value changed. They are ordinary RED and
   fail above, today. Their replacement "no source/test/config offender" guard is
   earned by probe 4.

4. **Scan filter removed, under the paths.conf edit.** The command:
   `plan.sh:211 paths="$(scanned_paths_filter "$paths")"` → `: no filter`. Result:

       FAIL AC-1 x3, AC-2 x2, AC-3 x2, AC-4 x2   (the re-premised T-70..T-73, incl. T-73's `tests/_lib.sh` partial path)
       FAIL a Contract whose every token is filtered is NOT CONSIDERED, like one naming no paths
       FAIL and neither APPLIES nor SUPPRESSED
       FAIL AC-5: and by its real tooling path scripts/refresh-harness.sh
       FAIL AC-5: and by no prose or bare filename (no source, test or config offender on the line)
       plan: 117 passed, 13 failed

5. **T-5 and T-8.** These are not in the 19, and they pass either way. I
   re-premised them anyway: they are the "one source path is enough" controls,
   and their companion `scripts/task.sh` would otherwise be tooling after GREEN.
   That would leave each with two enforced paths instead of source beside a
   harness path. The probe: `harness|docs|ignored)` → `harness|docs|ignored|source)`.

       FAIL but one source path is enough for the lock to bite
       FAIL but one DECLARED source path is enough for the lock to bite
       FAIL ... and it says the exception was SUPPRESSED / by the source path ... / SUPPRESSED by the declared source path ...
       plan: 103 passed, 27 failed   (the rest are other source-dependent cases and the 12 ordinary-RED AC-5/AC-8)

**plan.test.sh was re-premising and nothing more.** No fixture needed a new
mechanism.

### DV-1: expected values (GREEN confirms in one session)

| Control | Threshold / expected once `tooling` exists | Measured here against the mutate.sh prototype | Today (RED) |
|---|---|---|---|
| AC-2: `echo x >> scripts/check-boundaries.sh` in RED | denied, `path:     scripts/check-boundaries.sh`, `category: tooling` | denied, `category: tooling` | allowed |
| AC-4: each of the ten `harness` paths in RED | allowed, and each classifies `harness` | allowed / `harness` | allowed / `harness` (vacuous) |
| AC-5: `mutate.sh` on `scripts/check-boundaries.sh` and on `.claude/hooks/lib.sh` in RED | allowed | allowed | allowed (vacuous) |
| AC-3: the three paths in GREEN, GATES, SCAFFOLD | allowed | allowed | allowed (vacuous) |
| AC-6: `gate_tree_hash_of 01e502b` | `e852f851933cb64800209a1cce52af276f8304a1`, unchanged | `e852f851933cb64800209a1cce52af276f8304a1` | `e852f851...` |
| AC-6 control: split, with `gated_stdin` NOT taught `tooling` | anything but `e852f851...` | **`cd93a70e2b1c3b305ab5cd3fd47759b15b75c137`**. The story records `81917885...`; see below | n/a |
| AC-6 in-suite control (fixture hash) | the 3 hash cases go red | 3 red, `unchanged: abe95fa5...` | n/a |
| AC-7 control: hook special-case | exactly the 2 AC-7 "allowed" assertions go red | 2 red (probe 1) | n/a |
| AC-7 instrument: fixture RED row lists tooling after the awk | 1 | 1 | 1 |

These are measurements of a **prototype applied by mutate.sh**, not of the
shipped files. Confirming them against what GREEN ships is GREEN's job.

### Discovered: things that affect the approach

- **AC-6's measured negative-control value does not reproduce.** I computed
  `gate_tree_hash_of 01e502b` with this tree's lib.sh. With the full split it is
  `e852f851...`, which matches. With only the paths.conf split, it is
  **`cd93a70e2b1c3b305ab5cd3fd47759b15b75c137`**, not the `81917885...` in
  `## Context` §4 and AC-6. Two other variants: splitting scripts alone gives
  `3b3e5695...`, and splitting hooks alone gives `0e1310c3...`. The *claim* holds,
  because the broken predicate gives a different hash. The *number* does not.
  No test depends on it, so I did not change anything and did not touch the AC.
  This is flagged for the orchestrator.
- **GREEN must land paths.conf and phases.conf together.** The contract already
  says so. If paths.conf lands alone, `scripts/**` is unwritable in GREEN too.
  `phase_allows` fails closed, so every AC-3 "allowed" assertion would go red.
  That failure would be loud, but it would also block GREEN's own next edit.
- DV-2 (GATES) is not mine to run. Probes 1 and 2 above are the same
  mechanisms, run against a mutate.sh prototype, not against shipped config.

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. PASTE THE OUTPUT of every probe. -->

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-29T22:52:40Z
    commit: 1d1bc00
    tree:   b4a9cb21f834bf4a1f1b6111def4985c5cb6090b
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 90)
    PASS         lint (0s, observed 90, floor 1)
    PASS         typecheck (2s, observed 17)
    PASS         unit (30s, observed 452, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 57746)
    PASS         harness (13s, observed 40)
    UNCONFIGURED mutation

## Notes

### The three options, weighed again

`HARNESS-009` weighed these three for the *test* half and chose C. This half
reverses that choice, and the reason is a measurement, not a preference.

**A. Reclassify `scripts/**` and `.claude/hooks/**` as `source`.** This gives the
right lock verdict for free, but it is wrong for every other consumer.
`check-boundaries.sh:175` would count the files as production source, and 3a
would then refuse every harness PR for "source without tests", because
`.claude/tests/**` is `harness` and not `test`. `gates.sh:585` would require a
required gate to `covers` `scripts/**`, and none can. `--list source` would
return harness scripts to every Luau source guard. **Rejected.** The paths are
not this project's product, and `source` means "this project's product" to four
consumers.

**B. A new category, `tooling`. Chosen.** It gives the lock verdict of `source`
and none of `source`'s other meanings. The blast radius was measured, not
inferred (the table in `## Contract`). Exactly one consumer needs a line changed,
which is `gated_stdin`. One more changes its verdict, correctly: `plan.sh`'s
`unenforced` exception. The rest are generic or switch on `source`/`test` only.
There is precedent: `manifest` was split out of `config` for the mirror-image
reason, and `phase-guard.test.sh:115` pins that split in the same shape this
story needs.

**C. A per-commit check in `check-boundaries.sh` (3j's shape). Rejected for
this half.** It worked for tests because a test written in GREEN has no permitted
phase to be committed in later. Harness code written in RED has one: GREEN, the
very next phase. The measurement in `## Context` found 0 RED commits touching
harness code and 4 whole-story REVIEW commits. So C would have refused nothing
historically, and it would still pass the exact sequence it is meant to catch:
write in RED, `phase.sh set GREEN`, commit. It catches the commit, not the
keystroke. That was an acceptable trade for 3j only because the commit was
unavoidable there.

**What B costs that C does not.** B changes three upstream-owned files
(`phases.conf`, `lib.sh` and `rules.md`) and one hand-merged file
(`paths.conf`). C would change one file. A refresh reverts both. For B the
failure mode is louder, because `scripts/**` becomes unwritable, and louder is
better than silently reopening the hole. It is recorded as Q4.

### Consequences for the model plan (AC-8)

`models.conf`'s `except | RED | unenforced` row keeps RED on `opus` when "the
lock freezes none of the paths this story names". Every harness story so far has
qualified, because `scripts/**` was `harness`. After this story, a harness story
whose contract names `scripts/**` or `.claude/hooks/**` does **not** qualify, and
its RED plan moves to `fable`. That is the policy working as written, because the
lock now backs the contract. It does change the planned model for most future
harness stories. The `.claude/tests/**` half is still enforced only by 3j, at CI.
Whether that is enough net for `fable` is the question the exception's reasoning
asks, and the answer here is "the production side is now locked". This is
recorded so it is not a surprise. It is not a question.

### Open questions for the user (settled 2026-09-29, see "PO decisions" below)

**Q1. Which phases freeze `tooling`?**
- *(a) Parity with `source`, recommended:* denied in PLANNED, RED, REVIEW and
  DONE. It is the only rule that needs no new argument ("production code is
  written in GREEN and GATES"), and it is what AC-3 says. Cost: a harness fix from
  PR feedback means returning to GREEN or GATES, which is what `phases.conf`
  already tells REVIEW to do for source. The one DONE-phase harness commit on
  `main` (`50b4b68`, HARNESS-010) would have needed a phase change.
- *(b) RED only:* the title's literal scope, and the smallest change. It leaves
  PLANNED writing production code before any test exists, which is the same law-1
  hole, one phase earlier.

**Q2. Which paths are "harness source"?**
- *(a) `scripts/**` and `.claude/hooks/**`, recommended.* These are executable
  code. They were the stated exposure, and they are measured (in `## Context` §3)
  to hold no RED-written helper.
- *(b) Also `.claude/settings.json` and `.github/workflows/**`.* These are harness
  configuration. `settings.json` wires the hooks, so writing it can switch the lock
  off, which is arguably the bigger hole. Parity with `config` (frozen in RED)
  would say freeze them. But they are a different argument, and on `main` they
  were touched 3 times, all in whole-story REVIEW commits. Recommend a follow-up
  story if wanted.

**Q3. The `CLAUDE.md` guard-bug carve-out.** "If it still blocks a command that
writes nothing, that is a bug in the guard: add the case to
`.claude/tests/phase-guard.test.sh` and fix it there." Under this story, a fix to
`.claude/hooks/phase-guard.sh` made while another story is in RED is denied.
`HARNESS-010` is the worked case: reported from SEAT-002's RED, fixed as its own
story. *Recommended:* accept this, and add one clause to `CLAUDE.md` saying that
the fix is made with the lock cleared (`bash scripts/phase.sh clear`) or as its
own story, never from inside another story's RED. The alternative is leaving
`.claude/hooks/**` as `harness`, which removes the lock itself from the freeze.

**Q4. Upstream.** Should this, and 3j, go to `../agentic-dev-harness`? It is out of
scope here (see `## Out of scope`), but a refresh without it reverts both.

**Minor, not blocking:** the category name `tooling` (`## Contract`).

### PO decisions at PLANNED → RED (2026-09-29, `4f4fa0c`)

The user accepted every recommendation ("accept your recommendations and advance it").

1. **Q1: parity with `source`.** `tooling` is denied in PLANNED, RED, REVIEW and
   DONE, and allowed in IDLE, GREEN, GATES and SCAFFOLD. AC-3 as written.
2. **Q2: `scripts/**` and `.claude/hooks/**` only.** `.claude/settings.json` and
   `.github/workflows/**` stay `harness`. Freezing them is a possible follow-up story.
3. **Q3: yes.** `CLAUDE.md` gains the carve-out clause, and it was added as AC-9
   while the criteria could still change freely. GREEN writes it.
4. **Q4: not decided.** No recommendation was made, so none was accepted. It stays
   in `## Out of scope`, with the risk that a harness refresh reverts both this and 3j.
   It is an open item for the user, and not this story's to settle.
5. **The category name stays `tooling`.**
6. **Gate.** No `gates.sh` gate reads the artifact. CI's required `gates` job runs
   the four suites through `selftest.sh`. `required_gates` stays empty (`## Context`).
7. **Epic.** None, so there is no done-when to check.
8. **Callers of changed signatures.** None change (`## Contract`, "Changed
   signatures"). The orchestrator checked that the `mutate.sh` exemption in
   `phase-guard.sh:215-229` / `lib.sh:270` is keyed on the command's FILE argument,
   not on a category, so AC-5 needs no change to the hook.

### Orchestrator verification of RED (2026-09-29)

- Freeze: `frozen: OK — 21 path(s) unchanged since the snapshot for HARNESS-020`.
  Only the four suites and this story changed, and `.claude/state/mutations/`
  holds only `log`.
- Independent runs, one at a time. `phase-guard: 222 passed, 20 failed`,
  `lib: 153 passed, 5 failed` and `classify: 28 passed, 8 failed` match the
  handoff. `pipe-readers: 11 passed, 0 failed`.

### AC-6's recorded negative-control hash is wrong (pending user approval of an Amendment)

The RED subagent reported that `gate_tree_hash_of 01e502b` with the split, but
without `tooling` in `gated_stdin`, is `cd93a70e…`, not the `81917885…` that
`## Context` §4 and AC-6 record. **Orchestrator reproduction, by a different
method and without the subagent's code or any change to a frozen file.** I
sourced `lib.sh`, took `git ls-tree -r 01e502b`, ran it through today's
`classify_stdin | gated_stdin`, removed the `scripts/` and `.claude/hooks/`
paths (which is exactly what a `tooling` that `gated_stdin` drops removes), and
hashed it the way `_hash_blob_listing` does:

    calibration (all gated):   e852f851933cb64800209a1cce52af276f8304a1   <- matches HARNESS-009's record
    without scripts+hooks:     cd93a70e2b1c3b305ab5cd3fd47759b15b75c137   <- the negative control
    without scripts only:      3b3e5695ebfc6d1ea9ff5a9847b4d243750a29df

So the correct value is `cd93a70e…`. The criterion's claim, that the broken
predicate gives a different hash, still holds, and no test reads the number. Only
the recorded literal in AC-6's text is wrong. Changing AC text after PLANNED needs
an `## Amendments` entry, and that needs the user.

### Sizing: one cycle, not split

GREEN is small: two `tooling` rules, one `phases.conf` column, one
`gated_stdin` condition, and the docs. RED is larger: a new `phase-guard`
describe, 2 flipped `lib.test.sh` cases, and 19 `plan.test.sh` fixtures to
re-premise, earned by one or two probes. A split was considered and rejected.
The split would keep `plan.sh`'s verdict for `tooling` unchanged by adding it to
`plan.sh:219`'s unenforced list, and move AC-8 and the 19 to a follow-up story.
That would make `plan.sh` print "the lock freezes none of the paths" about paths
the lock now freezes. A true statement cannot be deferred by shipping a false
one. The same `paths.conf` line causes both, so both belong in one cycle. If RED
finds the plan.test.sh work to be more than re-premising, it stops and says so.
It does not widen the story.

### Prototype

A throwaway `git worktree` of `4f4fa0c`, in the session scratchpad, with the
three config edits of `## Contract` (the two `tooling` rules, `tooling` in the
`IDLE`/`GREEN`/`GATES`/`SCAFFOLD` rows, and `|| $1 == "tooling"` in
`gated_stdin`) and nothing else, was used to measure `classify.sh`, the
gate-hash values in `## Context` §4, and the whole of `selftest.sh` (the list in
`## Contract`). One run, nothing concurrent. The worktree was removed
afterwards, and none of it is in this tree.
