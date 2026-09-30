---
id: HARNESS-021
title: A gate record goes stale when a doc the tests read changes
slug: a-gate-record-goes-stale-when-a-doc-the
epic: 
type: fix
status: done
phase: DONE
branch: story/HARNESS-021-a-gate-record-goes-stale-when-a-doc-the
depends_on: [HARNESS-020]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Found on 2026-09-30 while planning ROUND-006. A green gate record can stand over
a red suite.

`gated_stdin` (`.claude/hooks/lib.sh:629`) is the one definition of "the code the
gates ran against". `gates.sh` records its hash in `## Gate results`
(`gates.sh:191`), `check-boundaries.sh` recomputes it and refuses a mismatch
(`check-boundaries.sh:367-374`), and the Stop hook asks whether it moved
(`code_changed_since`, `lib.sh:575`, called from `gate-reminder.sh:98`). It keeps
`source`, `test`, `config`, `tooling` and non-`.md` `harness`, and it drops
`docs` on purpose, because the story file that records the hash lives under
`docs/` and cannot be part of it.

But two `docs` files are **inputs to the `unit` gate**. `lune run test` reads them
at test time, so editing either one after a recorded gate run changes what `unit`
would report, and the recorded stamp still matches.

### What was measured (on `claude/admiring-darwin-a22af7` at `762a99f`, identical to `main`)

**1. Which docs the tests read. There are two, not one.**

    $ bash scripts/classify.sh docs/wiki/game/tuning.md docs/wiki/stack.md
    docs	docs/wiki/game/tuning.md
    docs	docs/wiki/stack.md

    $ grep -rln 'wiki/game/tuning.md' tests/ | wc -l
    12
      tests/helpers/{LobbyGateContract,RateLimitSpec,RoundEndingContract,TuningFakes,TuningSpec}.luau
      tests/net/rate_limit_provenance_test.luau
      tests/server/{lobby_gate,phase_machine,round_config,round_ending}_test.luau
      tests/shared/{tuning_spec,tuning}_test.luau

The actual reads are `fs.readFile(TuningSpec.SPEC_PATH)` (`TuningSpec.luau:42/240`,
`tuning_spec_test.luau:98`) and `fs.readFile(RateLimitSpec.SPEC_PATH)`
(`RateLimitSpec.luau:39/139`). Both constants are `"docs/wiki/game/tuning.md"`.

**The brief named only tuning.md. A second doc is read too:**
`tests/shared/contract_raise_test.luau:418` runs
`fs.readFile("docs/wiki/stack.md")` and asserts three whole lines of it (that
story's AC-3). `grep -rn 'readFile\|readDir' tests lune src` finds no other read of
a `docs/` path. `docs/wiki/architecture.md` is **mentioned** in two test comments
(`RoundEndingContract.luau:17`, `TelemetryContract.luau:55`) but never read. That
makes it this story's control document.

**2. What the hash does today, and what it would do.** Prototyped without editing
any file. `lib.sh` was sourced, `git ls-tree -r 762a99f` was piped through
`classify_stdin`, the named docs were relabelled as kept, and the result was hashed
the way `_hash_blob_listing` does. The script is in `## Notes`, "Prototype".

| Kept in addition to today's set | `gate_tree_hash_of 762a99f` |
|---|---|
| nothing. This is the calibration, and it equals the real `gate_tree_hash_of` | `b4a9cb21f834bf4a1f1b6111def4985c5cb6090b` |
| `docs/wiki/game/tuning.md` | `b961aa7c58a1e50f2e4bfeb137d773328f272df9` |
| `tuning.md` + `docs/wiki/stack.md` | `c2529f0d78a04ef3f4d4cebcf24b1c3bd0a0201a` |
| all 24 non-backlog docs, i.e. "hash all docs" | `5baa97c0d6a70713a0b7066f82510e11f28d565e` |

**3. Open gate records that a change to the hash would invalidate: none.**
`grep -h '^phase:' docs/backlog/stories/*.md | sort | uniq -c` gives
`35 phase: DONE`, which is every story. `check-boundaries.sh` verifies only the
story that claims the PR's branch (`check-boundaries.sh:180-200`), so DONE
records are never re-verified. The other worktree (`relaxed-sammet-f42b48`) is
a detached HEAD at `c464266` (HARNESS-018 DONE) with nothing in flight. The one
live exposure is ROUND-006, which is being planned elsewhere. See
`## Out of scope`.

**The required gate that would fail if this story's artifact broke.** None of the
`gates.sh` gates reads it. The artifact is `gated_stdin` and `code_changed_since`,
which are pinned in `.claude/tests/lib.test.sh`, `boundaries.test.sh`,
`gate-reminder.test.sh` and `phase-guard.test.sh`. CI's required `gates` job runs
all four through `scripts/selftest.sh`. That is the route HARNESS-006 §1,
HARNESS-009 and HARNESS-020 used. `required_gates` stays empty because there is
no optional gate to promote.

**This story's RED is protected by what HARNESS-020 built.** `.claude/hooks/lib.sh`
is `tooling`, which is frozen in RED, so no `frozen.sh` snapshot is needed.

## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

The artifact is **option B** in `## Notes`. A `covers` line in `project.conf`, the
existing declaration of "which paths each gate reads", brings a `docs` path into
the gated set. Classification does not change, so the phase lock, check 3a, the
`covers` check, `plan.sh` and `classify.sh` all see exactly what they see today.

- **AC-1** (the bug, reproduced). Take a fixture whose `project.conf` has
  `covers | unit | docs/wiki/game/tuning.md`. When that file's content changes,
  then `gate_tree_hash` changes.
  *Control, the same edit without the covers line:* the hash does **not** change.
  That is today's behaviour, and it shows the covers line is the cause, not
  some broader change.
  *Control, the unread doc:* with the covers line present, an edit to
  `docs/wiki/architecture.md` (which no gate reads) leaves the hash unchanged, and
  so does an edit to `docs/notes.md`. So the fix is not "hash all docs".

- **AC-2** (end to end, through the gate record). Given a fixture story whose gate
  record was written by `gates.sh` with the covers line in `project.conf`:
  - when `docs/wiki/game/tuning.md` is edited and committed, then
    `check-boundaries.sh` refuses with `gates were recorded against tree`, exits
    non-zero, and names the recorded hash and the current hash **by value**.
  - *Control:* after a fresh record, an edit to `docs/wiki/architecture.md` is
    committed. `check-boundaries.sh` then prints the line
    `ok    gate record matches the working tree (tree <rec>)`, where `<rec>` is the
    recorded hash by value, and it does not print
    `gates were recorded against tree`.

- **AC-3** (the covers arm admits docs, and only the docs that can be hashed).
  Given `covers | unit | docs/**` and `covers | unit | .claude/commands/**` in
  `project.conf`:
  - an edit to the story file `docs/backlog/stories/T-1.md` does **not** move
    `gate_tree_hash`, because the record cannot hash itself.
  - an edit to `.claude/commands/advance-story.md` does **not** move it.
    Harness prompts stay out: the `.md` exclusion is not reopened through
    `covers`.
  - *Control:* an edit to `docs/wiki/architecture.md`, matched by the same
    `docs/**` glob, **does** move it. So the glob is live, and the backlog
    exclusion is specific rather than "covers does nothing".

- **AC-4** (a project that declares nothing is unchanged). Given a fixture whose
  `project.conf` has only `covers | unit | src/**`, or has no `project.conf`, the
  `gate_tree_hash` it computes equals the hash of the same tree with no covers
  arm at all. An upgrade therefore moves no existing record in a project that
  lists no doc.

- **AC-5** (the Stop hook agrees with the hash). Given an active story in `GREEN`,
  a stamped gate run, and `covers | unit | docs/wiki/game/tuning.md`:
  - when `docs/wiki/game/tuning.md` is edited afterwards, the Stop hook warns and
    the warning names `docs/wiki/game/tuning.md`.
  - *Control:* after a fresh stamp, an edit to `docs/wiki/architecture.md` leaves
    it silent.

  (Today `code_changed_since` prunes the whole of `docs/` before it walks
  (`lib.sh:582` and `:586`). So even with `gated_stdin` fixed, the hook would
  never see tuning.md, and the two answers the comment at `lib.sh:566-569` says
  "cannot drift apart" would drift.)

- **AC-6** (the lock does not move). With the covers line present in the
  fixture's `project.conf`, `bash scripts/classify.sh docs/wiki/game/tuning.md`
  prints `docs`. A write to it is **allowed** in each of `IDLE`, `PLANNED`, `RED`,
  `GREEN`, `GATES`, `REVIEW`, `SCAFFOLD` and `DONE`, by the `Write` tool and by a
  shell redirect. The Game Designer and the Lead PO write this file, and they
  write it in PLANNED.

- **AC-7** (this project declares its two readers). `.claude/harness/project.conf`
  carries `covers | unit | docs/wiki/game/tuning.md` and
  `covers | unit | docs/wiki/stack.md`, each with a comment that names the test
  file that reads it. `gates.sh --audit` (the config check) accepts both lines.
  The real-tree numbers and the proof that the runner really reads them are
  DV-1 and DV-2.

## Contract

<!-- Amendable by RED in place, with a reason. -->

### Files

| Path | `classify.sh` says | Who writes it | What changes |
|---|---|---|---|
| `.claude/hooks/lib.sh` | `tooling` | GREEN | `gated_stdin` gains the covers arm. `code_changed_since` stops pruning `docs/`. Both comment blocks are updated |
| `.claude/hooks/gate-reminder.sh` | `tooling` | GREEN | the header comment at `:26-29` only ("never docs" becomes "never docs no gate covers") |
| `scripts/check-boundaries.sh` | `tooling` | GREEN, optional | the refusal text at `:374`, "Source, test or config changed", may add "or a doc a gate covers". The needle `gates were recorded against tree` must not change |
| `.claude/skills/quality-gates/SKILL.md` | `harness` | GREEN | one paragraph by the `covers` section (`:278-291`): a `covers` glob over a doc also puts that doc in the gate hash |
| `.claude/harness/project.conf` | `harness` | **Lead PO**, at the end of GREEN (DV-1) | the two covers lines of AC-7, with comments |
| `.claude/tests/lib.test.sh` | `harness` | RED | AC-1, AC-3 and AC-4, extending the `gate_tree_hash: covers what the gates judge, and only that` block (`:343`) |
| `.claude/tests/boundaries.test.sh` | `harness` | RED | AC-2, extending `the gate record is a stamp on a tree, not a sentence about one` (`:1412`) |
| `.claude/tests/gate-reminder.test.sh` | `harness` | RED | AC-5, beside `a harness prompt is not code the gates judge` (`:259`) |
| `.claude/tests/phase-guard.test.sh` | `harness` | RED | AC-6, a new `describe` |
| `.claude/tests/classify.test.sh` | `harness` | RED | AC-6's classify half (`docs`, unchanged) |

`paths.conf`, `phases.conf`, `plan.sh`, `gates.sh` and `classify.sh` are **not** in
this table on purpose. Option B changes no category (see "Consumers").

### The predicate, exactly

`gated_stdin` keeps its stdin/stdout contract: `"<category>\t<path>"` in, the kept
lines out. A line is kept when **either** of these holds:

1. **today's arm, unchanged:** the category is `source`, `test`, `config` or
   `tooling`, or it is `harness` and the path does not end in `.md`. In every case
   the path must not start with `.claude/state/`.
2. **the covers arm, new:** the category is `docs`, the path does **not** start
   with `docs/backlog/`, and the path matches the glob (field 3) of at least one
   `covers` line in `$HARNESS_DIR/project.conf`.

- **The covers arm is restricted to `docs`.** `vendor` and `ignored` are generated.
  Harness `.md` files are prompts, and it was measured that no gate reads one:
  `grep -nE '\.md|docs/' .claude/tests/project-counters.test.sh` matches only
  comments. A broad glob such as `**` must not bring any of these in (AC-3).
- **`docs/backlog/` is excluded by prefix**, like `.claude/state/`. The story
  file records the hash, so it cannot be an input to it. Without this rule,
  `covers | unit | docs/**` would make every record stale the moment `gates.sh`
  wrote it.
- **The glob dialect is the paths.conf one.** Reuse `_G2R_AWK` (`lib.sh:499`), as
  `classify_stdin` and `glob_matches` already do. Do not write a third glob
  converter. Read the conf through `ENVIRON`, not `-v`, for the same backslash
  reason as `classify_stdin:528`.
- **A missing `project.conf`, or one with no `covers` lines,** means that the
  covers arm keeps nothing (AC-4). The `lib.test.sh` fixture has no
  `project.conf`, so this is the path the existing hash cases take.
- **The gate id in field 2 is not consulted.** A covers line that names an
  unknown gate is already a config FAIL in `gates.sh:536`, so `gated_stdin` does
  not need a second opinion about it. Covers lines of optional gates count as
  well. The hash is "what the gates ran against", and that includes optional
  gates.

`code_changed_since`: remove `-path "$HARNESS_ROOT/docs" -prune -o` (`:582`) and
`docs` from the `case` at `:586`. The candidates then pass through
`classify_stdin | gated_stdin` as they do today, and that pipeline decides.
Cost: `find docs -type f | wc -l` gives `65` files, well inside the hook's
twenty-second budget.

### Consumers of the classifier, and what each sees under option B

These were checked against the tree with
`grep -nE 'classify_stdin|classify\.sh|gated_stdin|gate_tree_hash|code_changed_since|phase_allows' scripts/*.sh .claude/hooks/*.sh`,
and the category switches with `grep -nE '"docs"|docs\)|docs\|'`.

| Consumer | Where | Effect of option B |
|---|---|---|
| the gate hash | `_hash_blob_listing` `lib.sh:654`, via `gate_tree_hash` `:667` / `gate_tree_hash_of` `:690` | **changes**: covered docs enter it (AC-1 to AC-4) |
| the Stop hook | `code_changed_since` `lib.sh:575` → `gate-reminder.sh:98` | **changes**: the `docs/` prune goes (AC-5) |
| `gates.sh` records | `gates.sh:191` `tree="$(gate_tree_hash)"` | follows the hash, no edit |
| check-boundaries recompute | `check-boundaries.sh:367/369` | follows the hash, no edit |
| the lock | `phase-guard.sh:32` → `phase_allows "$cat"` | **none**. tuning.md is still `docs`, and `docs` is in all 8 `phases.conf` rows (AC-6) |
| check 3a | `check-boundaries.sh:174-177` counts `source` / `test` | **none**. A tuning.md-only PR has `src=0, tst=0`, exactly as today |
| `covers` check | `gates.sh:585` keeps `source` only | **none**. A docs covers line is never asked to be "covered" |
| `covers` config validation | `gates.sh:531-539` | accepts it: the gate id is known and the glob is non-empty (AC-7) |
| `plan.sh` lock scan | `plan.sh:219` `harness\|docs\|ignored) ;;` | **none**. tuning.md is still `docs`, which is unenforced and correct, since the lock does not freeze it |
| `classify.sh --list` / `--only` | generic | **none**. `--list docs` still includes tuning.md |
| `inject-state.sh` | `phase_categories` `lib.sh:805` | **none** |
| `refresh-harness.sh` | `:218-238` | `project.conf` is left untouched (project-owned), so the declaration survives a refresh. `lib.sh` is replaced, so the reader does not, unless it goes upstream (Q4 of HARNESS-020, still open) |

### Changed signatures

None. `gated_stdin`, `gate_tree_hash`, `gate_tree_hash_of` and
`code_changed_since` keep their shapes. `gated_stdin` gains an implicit read of
`$HARNESS_DIR/project.conf`, in the same way `classify_stdin` reads `paths.conf`.
Its callers are `lib.sh:607` and `lib.sh:654`, and none needs editing.

### Existing assertions that pin today's behaviour

**Predicted: none flip.** `lib.test.sh:357` ("a docs file does not move the hash")
edits `docs/notes.md` in a fixture that has no `project.conf`. Under AC-4 that
stays true, and it stays in place as a control. The only covers lines in any
suite are `gates.test.sh:260-261,320`, and all are `src/**` globs.
`gate-reminder.test.sh:273` writes a `project.conf` without covers lines.
`boundaries.test.sh`'s `story_blocked` (`:241`) writes one without covers lines.
**This is a prediction from reading, not a run.** RED runs each touched suite
before its edits and records the baseline counts in `## Handoff`, which turns it
into a measurement.

`story_blocked` rewrites `project.conf` through `write_conf` on every call. AC-2
needs the covers line in place **before** its `gates.sh` run, so RED extends the
helper, for example with an optional extra-conf argument or an env var, rather
than appending after the call. An append after the call would change
`project.conf`, which is itself hashed, and the record would go stale for the
wrong reason.

### Oracle partition (see `story-authoring`)

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-3, AC-4 | **Mechanical, with the controls as stated** | Pin exactly. Each edit gets its own `gate_tree_hash` before and after, compared with the `if [ "$a" = "$b" ]` / `_ok` / `_bad` shape of `lib.test.sh:360`. No loop that hides which path failed. Every "does not move" case is paired with a "does move" case in the same fixture, so an implementation that never keeps anything cannot pass the block |
| AC-2 | **Mechanical, needles by value** | Reuse `rec_tree_of_fixture`, `fix_tree_hash`, `assert_sha40` and `assert_differ` (`boundaries.test.sh:1465-1497`). The control's needle is the whole line `ok    gate record matches the working tree (tree $rec)`, by value. A bare `gate record matches` also floats over a message that names a different tree |
| AC-5 | **Mechanical** | `assert_warns` with the needle `docs/wiki/game/tuning.md`, and `assert_silent` for the control. `assert_silent` asserts empty output, not the absence of one phrase, so it cannot be satisfied by a different message |
| AC-6 | **Mechanical, regression pin** | One `set_phase` per phase and one assertion per phase, using `assert_allowed` from `_lib.sh`. This passes on arrival. Earn it (see below) |
| AC-7 | **Settled** | The two paths are the measured readers above. Read them out, do not re-derive them |

**Earning what passes on arrival.**
- AC-6 passes today and is expected to pass afterwards. Earn it once:
  `bash scripts/mutate.sh .claude/harness/phases.conf 's/^RED\( *| *vendor,ignored,test,manifest,\)docs,/RED\1/' -- bash .claude/tests/phase-guard.test.sh`
  must turn the RED case red. `make_fixture` copies the real `phases.conf`, so the
  mutation reaches the fixture. Paste the output into `## Handoff`.
- AC-4's cases and AC-1's "unread doc" control pass today too, because nothing is
  kept. They are not vacuous, because each is paired with a "does move" case in
  the same block, and that case fails in RED. State that pairing in the handoff.
- AC-3's "the story file does not move it" also passes today, for the wrong
  reason: nothing in `docs/` is kept yet. It becomes meaningful once the covers
  arm exists. This is **DV-3** (owner GATES).

### Test-only dependencies

None. The suites are bash, and `_lib.sh` already provides `make_fixture`,
`make_project_fixture`, `write_conf`, `set_phase`, `assert_allowed` and
`assert_blocked`.

### The loop for RED (one at a time, never concurrently)

    bash .claude/tests/lib.test.sh
    bash .claude/tests/boundaries.test.sh
    bash .claude/tests/gate-reminder.test.sh
    bash .claude/tests/phase-guard.test.sh
    bash .claude/tests/classify.test.sh

Not `gates.sh` and not `selftest.sh` in RED. `gates.sh` stamps the active story,
and a whole selftest run takes 10-25 minutes here and collides with any overlapping
run.

## Deferred verifications

<!-- Owner: the phase that runs it. Result pasted in by that phase. -->

**DV-1. Real-tree hash, three settled values. Owner: GREEN.** Once `gated_stdin`
has the covers arm, the orchestrator runs
`CLAUDE_PROJECT_DIR="$PWD" bash -c '. .claude/hooks/lib.sh; gate_tree_hash_of 762a99f'`
three times, one session, and pastes each result:

| `project.conf` state | expected |
|---|---|
| shipped, no doc covers lines yet (AC-4 on the real tree) | `b4a9cb21f834bf4a1f1b6111def4985c5cb6090b`, unchanged from today |
| + `covers \| unit \| docs/wiki/game/tuning.md` | `b961aa7c58a1e50f2e4bfeb137d773328f272df9` |
| + `covers \| unit \| docs/wiki/stack.md` (the AC-7 state) | `c2529f0d78a04ef3f4d4cebcf24b1c3bd0a0201a` |

**Result (GREEN, orchestrator as Lead PO, 2026-09-30, one session).** Command:
`CLAUDE_PROJECT_DIR="$PWD" bash -c '. .claude/hooks/lib.sh; gate_tree_hash_of 762a99f'`,
with `paths.conf` unmodified (`git diff --stat -- .claude/harness/paths.conf` is empty):

    shipped project.conf, no doc covers lines  -> b4a9cb21f834bf4a1f1b6111def4985c5cb6090b   (match)
    + covers | unit | docs/wiki/game/tuning.md -> b961aa7c58a1e50f2e4bfeb137d773328f272df9   (match)
    + covers | unit | docs/wiki/stack.md       -> c2529f0d78a04ef3f4d4cebcf24b1c3bd0a0201a   (match)

All three equal the settled values. The two covers lines are now in
`project.conf`, with comments naming the test file that reads each doc (AC-7).

These values depend on the working tree's `paths.conf` as well, so a mismatch
means that file changed first. Diff it before suspecting the code. The Lead PO
writes the two lines here, between the runs.

**DV-2. The runner really reads the two docs. Owner: GATES.** This is "a claim
about what a runner discovers is checked by running the runner". The covers lines
assert that `unit` reads these files, so break each one and watch `unit` fail:

    bash scripts/mutate.sh docs/wiki/game/tuning.md '<a §-table value, changed>' -- lune run test
    bash scripts/mutate.sh docs/wiki/stack.md '<one of AC-3's three sentences, reworded>' -- lune run test

Each must report failures (`[1-9][0-9]* failed`), and `mutate.sh` must confirm the
restore. Paste both. If either stays green, the covers line for it is a false
claim. Stop and put that to the user. Do not delete the line quietly.

**DV-3. AC-3's backlog exclusion is live. Owner: GATES.** In RED, "the story file
does not move the hash" passes because nothing in `docs/` is kept at all. Once
GREEN lands, run
`bash scripts/mutate.sh .claude/hooks/lib.sh '<drop the docs/backlog/ prefix test>' -- bash .claude/tests/lib.test.sh`.
The story-file case must go red, and the `architecture.md` "does move" case must
stay green. Paste the output.

### Deferred verification results (GATES, orchestrator, 2026-09-30)

**DV-2: PASSED.** `unit` really reads both docs:

    $ bash scripts/mutate.sh docs/wiki/game/tuning.md 's/^| `players_min` | 4 |/| `players_min` | 5 |/' -- lune run test
      28 - | `players_min` | 4 | **derived** | ...
      28 + | `players_min` | 5 | **derived** | ...
    447 passed, 5 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_game_tuning.md.20260930T172938Z.321894.bak) ===

    $ bash scripts/mutate.sh docs/wiki/stack.md 's/^\*not\* counted against the 511\.$/*not* counted against the 512./' -- lune run test
      246 - *not* counted against the 511.
      246 + *not* counted against the 512.
            ...\tests\shared\contract_raise_test:433: docs/wiki/stack.md has no line reading:
    451 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../docs_wiki_stack.md.20260930T173030Z.326380.bak) ===

**DV-3: PASSED.** The backlog exclusion is live:

    $ bash scripts/mutate.sh .claude/hooks/lib.sh 's/ && index(tolower(\$2), "docs\/backlog\/") != 1//' -- bash .claude/tests/lib.test.sh
      671 -     $1 == "docs" && n > 0 && index(tolower($2), "docs/backlog/") != 1 {
      671 +     $1 == "docs" && n > 0 {
        FAIL AC-3: under covers | unit | docs/**, the story file docs/backlog/stories/T-1.md does not move the hash
        FAIL AC-3: under covers | unit | .claude/commands/**, a command prompt does not move the hash
        FAIL AC-3: under covers | unit | docs/**, an epic under docs/backlog/ does not move the hash either
    lib: 172 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .../.claude_hooks_lib.sh.20260930T173114Z.327901.bak) ===

The two backlog cases went red, as DV-3 requires. The architecture.md "does move"
control stayed green. The command-prompt failure is a cascade, not a second
defect. That case compares against `h11`, which was taken before the story-file
edit, and the mutated code had already moved the hash off `h11`. That edit is the
first backlog case above. The orchestrator also counts this as the
"suite discriminates" mutation check.

**Freeze.** GREEN ended with `frozen: OK — 6 path(s) unchanged since the snapshot for HARNESS-021`.
GATES ended with the same line, checked before the full `gates.sh` run.

## Amendments

<!-- Acceptance criteria are frozen once the story leaves PLANNED. If one turns
     out to be wrong or unsatisfiable, stop, put it to the product owner, and
     record the change here. -->

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-021` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `.claude/hooks/lib.sh` (tooling), `.claude/hooks/gate-reminder.sh` (tooling), `scripts/check-boundaries.sh` (tooling), declared in the Contract's ### Files table — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

<!-- FILLED BY A TOOL: `bash scripts/plan.sh write <id>`. Hand-written additions
     (departures, resolved models, verdicts) go outside the generated markers. -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- PLANNED, `lead-po` (dispatched by /plan-story), resolved to `claude-opus-5-5` (Opus 5.5). This is the model the subagent reports it runs on. No override was reported.
- RED, `test-developer` (dispatched by /advance-story with `model: fable`), resolved to `claude-fable-5-1` (Fable 5.1), as planned. **Verdict:** the orchestrator re-ran lib and gate-reminder, and each red case and count matched the handoff exactly. The controls were paired, and the AC-6 pins were earned by mutation without being asked twice.
- GREEN, `feature-developer` (dispatched by /complete-story with `model: opus`), resolved to `claude-opus-5-5` (Opus 5.5), as planned. No test file changed: `frozen: OK — 6 path(s) unchanged`.

## Out of scope

- **Re-stamping existing gate records.** All 35 stories on `main` are DONE
  (measured). `check-boundaries.sh` verifies only the story claiming the PR
  branch, so their records are never recomputed. Under the new predicate they
  describe a hash that nobody will recompute. That is historical, and it is not
  wrong.
- **ROUND-006, and any story that records gates before this merges.** Once this
  story lands, with AC-7's two covers lines, the real tree's hash moves
  (`b4a9cb21…` becomes `c2529f0d…` at `762a99f`). A branch that recorded its gates
  earlier and merges `main` afterwards will be refused by `check-boundaries.sh`
  until `gates.sh` is re-run. That refusal is correct, because tuning.md is what
  ROUND-006 is about. It is a cost to plan for, not a defect. It is not fixed
  here, and ROUND-006's content is not touched.
- **Changing what the tests read.** Moving tuning.md's numbers into a Luau
  module, or out of `docs/`, is a game-architecture decision. It is not a
  harness fix.
- **Detecting the next doc a test starts to read.** Option C (see Notes) was
  rejected as the *definition* of the set. A **guard** that fails when a test
  reads a `docs/` path that has no covers line would be the complement: for
  example a Luau test wrapping `fs.readFile`, or a lint over `tests/`. That is a
  project-side story, and a good follow-up. Without it, the next reader leaks
  the way these two did.
- **Upstreaming to `../agentic-dev-harness`.** `lib.sh` is replaced by
  `refresh-harness.sh`, so a refresh without this change silently reverts the
  covers arm. The declaration in `project.conf` survives, but nothing reads it.
  This is HARNESS-020's open Q4, and it stays open.
- **Other gates' non-source inputs.** `.luaurc`, `selene.toml`, `stylua.toml`,
  `rokit.toml` and `default.project.json` are `config` and are already hashed.
  No gate reads any other `docs` path (measured above).
- **The Stop hook's other prunes** (`.git`, `.claude/state`, `node_modules`,
  ignored top-level dirs) are unchanged.

## Test plan

<!-- Filled by the Test Developer during RED. -->

All five suites are bash, run one at a time, against throwaway fixtures
(`make_fixture` / `make_project_fixture`), never against this checkout. The
two docs are the ones AC-7 and `## Context` §1 measured: `tuning.md` is the
read doc, `architecture.md` the unread control. Neither is re-derived here.

| AC | Suite | `describe` block | Assertion (label as printed) | RED status |
|---|---|---|---|---|
| AC-1 | `lib.test.sh` | `gate_tree_hash: a covers line brings the doc a gate reads into the hash (HARNESS-021)` | `AC-1: with covers \| unit \| docs/wiki/game/tuning.md, editing tuning.md moves the hash` | **red** |
| AC-1 control A | same | same | `AC-1 control: the same tuning.md edit without the covers line does not move the hash` | green (paired with the red case above: identical edit, only the conf differs) |
| AC-1 control B | same | same | `AC-1 control: with the covers line, editing architecture.md (unread) does not move the hash`; `... editing docs/notes.md does not move the hash` | green (paired with `AC-1 pair: after the unread-doc edits, a second tuning.md edit still moves the hash`, **red**) |
| AC-1 (content, not mtime) | same | same | `AC-1: restoring tuning.md's content restores the hash` | green (vacuously in RED - the doc is never kept; becomes meaningful with the arm) |
| AC-3 | same | same | `AC-3: under covers \| unit \| docs/**, the story file docs/backlog/stories/T-1.md does not move the hash`; `AC-3: under covers \| unit \| .claude/commands/**, a command prompt does not move the hash`; `AC-3: ... an epic under docs/backlog/ does not move the hash either` | green, for the wrong reason until GREEN (DV-3) |
| AC-3 control | same | same | `AC-3 control: under covers \| unit \| docs/**, editing docs/wiki/architecture.md moves the hash`; `AC-3 control: ... editing tuning.md moves the hash` | **red** |
| AC-4 | same | same | `AC-4: with no project.conf, a doc a gate could read does not move the hash`; `AC-4: covers \| unit \| src/** keeps no doc: tuning.md / docs/notes.md / architecture.md does not move the hash` | green (paired with `AC-4 pair: ... source still moves the hash`, both green) |
| AC-2 | `boundaries.test.sh` | `the gate record is a stamp on a tree, not a sentence about one` | `AC-2: a covered doc changing after the run breaks the stamp`; `AC-2 control: the covered doc moving changes the tree hash`; `AC-2: the doc refusal names the RECORDED tree by value`; `AC-2: and the CURRENT tree by value` | **red** |
| AC-2 control | same | same | `AC-2 control: the record still matches, by value` (whole line, `(tree <rec>)`); `AC-2 control: and no stale-record refusal is printed`; `AC-2 control: and the PR is not refused at all` (`rc` = 0); `AC-2 control: an uncovered doc moving leaves the tree hash where the record put it` | green |
| AC-2 setup | same | same | `AC-2 setup: the covers line is in the committed project.conf` (`grep -cx` over `git show HEAD:...`); `AC-2 setup: and the covered doc is in the commit too`; `AC-2 setup: a record made with the covers line matches the tree it ran on` | green (instruments: the conf and doc reached the commit gates.sh ran on) |
| AC-5 | `gate-reminder.test.sh` | `a doc a covers line names is code the gates judge (HARNESS-021, AC-5)` | `warns: AC-5: a doc a covers line names, edited after the run` (needle `docs/wiki/game/tuning.md`) | **red** |
| AC-5 control | same | same | `silent: AC-5 baseline: the covered doc, untouched since the run`; `silent: AC-5 control: a doc no covers line names, edited after the run` | green |
| AC-6 (lock) | `phase-guard.test.sh` | `a doc a covers line names is still docs, writable in every phase (HARNESS-021, AC-6)` | `AC-6: <PHASE> allows Write to docs/wiki/game/tuning.md` and `allows: AC-6: <PHASE> allows a redirect into docs/wiki/game/tuning.md`, for IDLE, PLANNED, RED, GREEN, GATES, REVIEW, SCAFFOLD, DONE; `blocks: AC-6 control: RED still blocks a source write in the same fixture` | green on arrival; earned by the `phases.conf` mutation in `## Handoff` |
| AC-6 (classify) | `classify.test.sh` | `a doc a covers line names is still docs (HARNESS-021, AC-6)` | `AC-6: docs/wiki/game/tuning.md classifies as docs with the covers line present` (whole output line); `AC-6: and --list docs still returns it` | green on arrival; earned by the `paths.conf` mutation in `## Handoff` |
| AC-7 | - | - | Settled; the Lead PO writes `project.conf` in GREEN and DV-1 verifies it. No selftest assertion written against a file RED cannot write | - |

Shape rules honoured: every edit has its own before/after `gate_tree_hash` and
its own `if [ "$a" = "$b" ]` / `_ok` / `_bad` or `assert_eq`; no loop over
paths. In `phase-guard.test.sh` the eight phases go through one helper called
eight times by name, so a failure names its phase. Hash needles are by value
(`assert_sha40` guards against an empty needle); the control's `ok` line is the
whole line including `(tree <rec>)`.

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. -->

**Dispatch.** RED ran on `claude-fable-5-1` (Fable 5.1), which is the planned
model for RED. No override was reported to the agent.

### The command

One suite at a time, never concurrently (the fixtures are independent but the
runs are slow - phase-guard and boundaries take about ten minutes each here):

    bash .claude/tests/lib.test.sh
    bash .claude/tests/boundaries.test.sh
    bash .claude/tests/gate-reminder.test.sh
    bash .claude/tests/phase-guard.test.sh
    bash .claude/tests/classify.test.sh

`gates.sh --fast` was **not** run in RED, on the orchestrator's instruction:
`gates.sh` stamps the active story's record, and the artifact here is judged by
`selftest.sh`, not by a `gate |` line. GREEN ends with `--fast` as usual.

### Counts, before and after (measured, one suite at a time)

| Suite | Baseline (before any edit) | After RED edits | New assertions | Red |
|---|---|---|---|---|
| `lib.test.sh` | 158 passed, 0 failed | 171 passed, 4 failed | 17 | 4 |
| `boundaries.test.sh` | 125 passed, 0 failed | 135 passed, 4 failed | 14 | 4 |
| `gate-reminder.test.sh` | 27 passed, 0 failed | 29 passed, 1 failed | 3 | 1 |
| `phase-guard.test.sh` | 242 passed, 0 failed | 259 passed, 0 failed | 17 | 0 (earned, below) |
| `classify.test.sh` | 36 passed, 0 failed | 38 passed, 0 failed | 2 | 0 (earned, below) |

**The Contract's prediction "none flip" is now a measurement:** every
pre-existing assertion still passes in every suite (baseline count + new
assertions - red = passed, in each row).

### Verbatim failure output

`bash .claude/tests/lib.test.sh`:

```
    FAIL AC-1: with covers | unit | docs/wiki/game/tuning.md, editing tuning.md moves the hash
         unchanged: 31c7dafb9cedcd6738125b3fbb75bd8fac765bf9
    FAIL AC-1 pair: after the unread-doc edits, a second tuning.md edit still moves the hash
         unchanged: 31c7dafb9cedcd6738125b3fbb75bd8fac765bf9
    FAIL AC-3 control: under covers | unit | docs/**, editing docs/wiki/architecture.md moves the hash
         unchanged: f2a31b3157cda6a7029f4ee4e96f35007aa98d0a
    FAIL AC-3 control: under covers | unit | docs/**, editing tuning.md moves the hash
         unchanged: f2a31b3157cda6a7029f4ee4e96f35007aa98d0a

lib: 171 passed, 4 failed
```

`bash .claude/tests/boundaries.test.sh`:

```
    FAIL AC-2: a covered doc changing after the run breaks the stamp
         expected a refusal saying: gates were recorded against tree
         actual:                    ok    story files validated
         ok    harness state not tracked
         ok    source changes accompanied by test changes (0 source, 0 test)
         ...
    FAIL AC-2 control: the covered doc moving changes the tree hash
         expected: different
         actual:   identical: 3353ba57717ef564c83dcdbf4dccf5c2493693d8
    FAIL AC-2: the doc refusal names the RECORDED tree by value
         said '3353ba57717ef564c83dcdbf4dccf5c2493693d8' but exited 0, so CI would merge this
    FAIL AC-2: and the CURRENT tree by value
         said '3353ba57717ef564c83dcdbf4dccf5c2493693d8' but exited 0, so CI would merge this

boundaries: 135 passed, 4 failed
```

(The last two "said ... but exited 0" lines are the by-value needles matching
the `ok` line's `(tree ...)` while the run exits 0 - they read as red because
`refused` demands both the needle and a non-zero exit. Once the arm exists the
two hashes differ and the refusal names both.)

`bash .claude/tests/gate-reminder.test.sh`:

```
    FAIL warns: AC-5: a doc a covers line names, edited after the run
         the hook said nothing at all

gate-reminder: 29 passed, 1 failed
```

Each red is the assertion the story names, not an import or a config error:
the hash stays where it was (AC-1, AC-3), the record still matches (AC-2), and
the hook is silent (AC-5) - which is the bug reproduced.

### Why each red case fails, and its control

- **AC-1** red: `gated_stdin` drops every `docs` path, so editing tuning.md
  under `covers | unit | docs/wiki/game/tuning.md` leaves the hash at
  `31c7dafb…`. Control A (same `TUNE_A -> TUNE_B` edit, conf without the covers
  line) passes today and must keep passing. Control B (architecture.md and
  docs/notes.md under the covers line) passes today; it is **paired** with
  `AC-1 pair: ... a second tuning.md edit still moves the hash`, which is red,
  in the same conf state - an implementation that keeps nothing passes the
  controls and fails the pair.
- **AC-3** red: the same reason for `docs/**`. The two "does not move" cases
  (story file, command prompt) and the epic case pass today **for the wrong
  reason** - nothing under `docs/` is kept - and are paired with the two red
  `AC-3 control: ... moves the hash` cases in the same conf state. DV-3 (GATES)
  makes the backlog exclusion meaningful by breaking it.
- **AC-4** green on both fixtures (no `project.conf`; `covers | unit | src/**`
  only). "Equals the hash of the same tree with no covers arm" is expressed as
  the observable it implies: **no doc's content is an input**, so editing
  tuning.md, docs/notes.md and architecture.md each leave the hash unchanged
  while a `src/main.ts` edit in the same state moves it (the pair, green
  today and after). A literal equality against a hash "computed without the
  covers arm" would need the test to carry its own copy of gated_stdin's first
  arm, which is the third predicate the `lib.sh` comment refuses to have. The
  first fixture is also the state the pre-existing "a docs file does not move
  the hash" case (`lib.test.sh:357`) runs in; it stays as a control.
- **AC-2** red: `check-boundaries.sh` recomputes the same hash, so after the
  tuning.md commit it prints `ok    gate record matches the working tree (tree
  3353ba57…)` and exits 0. The control (fresh record, architecture.md edited and
  committed) asserts the whole `ok` line **by value**, the absence of
  `gates were recorded against tree`, and `rc = 0`; all pass today and must
  keep passing. Three setup instruments pass: the covers line is in the
  committed `project.conf` (`git show HEAD:… | grep -cx`), tuning.md is in the
  commit (`git ls-tree`), and the record made with the covers line matches the
  tree it ran on.
- **AC-5** red: `code_changed_since` prunes `docs/` before it walks, so the hook
  says nothing. Controls: the covered doc untouched after the stamp is silent;
  architecture.md edited after a fresh stamp is silent. Both pass today.

### Passes on arrival, and what earns it

**AC-6, `phase-guard.test.sh`** (17 assertions: Write + redirect in each of
IDLE, PLANNED, RED, GREEN, GATES, REVIEW, SCAFFOLD, DONE, plus a control that
RED still blocks `src/main.ts` in the same fixture). The sed expression was
dry-run against the real `phases.conf` first and changes exactly line 15.
Earned with:

    bash scripts/mutate.sh .claude/harness/phases.conf 's/^RED\( *| *vendor,ignored,test,manifest,\)docs,/RED\1/' -- bash .claude/tests/phase-guard.test.sh

```
=== mutate: .claude/harness/phases.conf (1 line(s) changed by s/^RED\( *| *vendor,ignored,test,manifest,\)docs,/RED\1/) ===
  15 - RED      | vendor,ignored,test,manifest,docs,harness | Story is in RED. Production code is frozen: ...
  15 + RED      | vendor,ignored,test,manifest,harness | Story is in RED. Production code is frozen: ...

=== mutate: running bash .claude/tests/phase-guard.test.sh ===
  ...
  a doc a covers line names is still docs, writable in every phase (HARNESS-021, AC-6)
    FAIL AC-6: RED allows Write to docs/wiki/game/tuning.md
         blocked with: BLOCKED by the harness phase lock.    story:    T-1   phase:    RED   path:     docs/wiki/game/tuning.md   category: docs  Story is in RED. ...
    FAIL allows: AC-6: RED allows a redirect into docs/wiki/game/tuning.md
         blocked with: BLOCKED by the harness phase lock.    story:    T-1   phase:    RED   path:     docs/wiki/game/tuning.md   category: docs  Story is in RED. ...

phase-guard: 231 passed, 28 failed

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/worktrees/fervent-curran-bab70a/.claude/state/mutations/.claude_harness_phases.conf.20260930T154823Z.215321.bak) ===
```

Exactly the two RED AC-6 assertions went red (the other 26 failures are the
suite's pre-existing RED-writes-docs cases, which the same mutation breaks, as
it should); the other seven phases stayed green because the mutation touched
only the RED row. `git status` shows `phases.conf` unmodified afterwards and
no `.bak` remains under `.claude/state/mutations/`.

**AC-6, `classify.test.sh`** (2 assertions, whole-line `assert_eq`). Earned
with:

    bash scripts/mutate.sh .claude/harness/paths.conf 's/^docs *| *docs\/\*\*$/spec | docs\/**/' -- bash .claude/tests/classify.test.sh

```
=== mutate: .claude/harness/paths.conf (1 line(s) changed by s/^docs *| *docs\/\*\*$/spec | docs\/**/) ===
  116 - docs | docs/**
  116 + spec | docs/**

=== mutate: running bash .claude/tests/classify.test.sh ===
    FAIL AC-6: docs/wiki/game/tuning.md classifies as docs with the covers line present
         expected: docs	docs/wiki/game/tuning.md
         actual:   spec	docs/wiki/game/tuning.md
    FAIL AC-6: and --list docs still returns it
         expected to contain: docs/wiki/game/tuning.md
         actual:

classify: 34 passed, 4 failed

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/worktrees/fervent-curran-bab70a/.claude/state/mutations/.claude_harness_paths.conf.20260930T155621Z.243962.bak) ===
```

(The other two failures are the suite's pre-existing `docs/notes.md` cases.)

**`AC-1: restoring tuning.md's content restores the hash`** is green today
vacuously (the doc is never kept). It is not earned separately: it sits between
two red cases in the same conf state and asserts the hash returns to `h9`, a
value that only exists as a distinct hash once the arm exists. If GREEN wants
it earned, `mutate.sh` on `lib.sh` to hash the path rather than the blob would
do it; not required.

### Files touched

- `.claude/tests/lib.test.sh` - new `describe` after the `gate_tree_hash:
  covers what the gates judge` block (AC-1, AC-3, AC-4). 124 lines added.
- `.claude/tests/boundaries.test.sh` - `story_blocked` gains `STORY_CONF_EXTRA`
  (see below); a `story_blocked_with_docs` wrapper and the AC-2 block at the
  end of `the gate record is a stamp on a tree, not a sentence about one`.
- `.claude/tests/gate-reminder.test.sh` - new `describe` after `a harness
  prompt is not code the gates judge` (AC-5).
- `.claude/tests/phase-guard.test.sh` - new `describe` before `summary` (AC-6).
- `.claude/tests/classify.test.sh` - new `describe` after the tooling block
  (AC-6 classify half).
- This story: `## Test plan`, this section.

No source, tooling, config or `project.conf` was written. No test dependency
was needed.

### The `story_blocked` extension

`story_blocked` now builds its `project.conf` as
`{ cat <<CONF ... CONF; [ -n "$STORY_CONF_EXTRA" ] && printf '%s\n' "$STORY_CONF_EXTRA"; } | write_conf "$FIX"`,
so an extra line lands in the conf **before** `commit_all "T-1 conf"` and the
`gates.sh --story T-1` run. Every existing caller sets no `STORY_CONF_EXTRA`
and gets a byte-identical conf (measured: the pre-existing `story_blocked`
assertions all still pass). `story_blocked_with_docs` first checks out `main`,
writes the two docs untracked, then calls `story_blocked` with
`STORY_CONF_EXTRA='covers | unit | docs/wiki/game/tuning.md'`; the checkout to
main is there because a previous call's branch carried the docs as tracked
files and `story_blocked`'s own `checkout main` removes them (the first RED run
died on a missing `architecture.md` for exactly that reason).

### Export shape the tests pin (stated as fact)

- `gated_stdin` - unchanged contract: `"<category>\t<path>"` lines on stdin,
  kept lines on stdout, no arguments. Tests reach it only through
  `gate_tree_hash` and the hook.
- `gate_tree_hash` - no arguments, prints a 40-hex hash; must be a function
  of blob **content** (the "restoring the content restores the hash" case).
- `code_changed_since <stamp>` - unchanged; the hook's warning must contain the
  path `docs/wiki/game/tuning.md` verbatim.
- `$HARNESS_DIR/project.conf` is read by `gated_stdin`, `covers` lines of the
  form `covers | <gate> | <glob>` with the paths.conf glob dialect; tests use
  `docs/wiki/game/tuning.md`, `docs/**`, `.claude/commands/**`, `src/**`. The
  field-2 gate id in every test conf is `unit`, which each fixture conf also
  declares as a `gate |` line, so nothing pins whether an unknown gate id is
  consulted (the Contract says it is not).
- `check-boundaries.sh` - the needle `gates were recorded against tree` and the
  `ok    gate record matches the working tree (tree <rec>)` line, unchanged.
- **Not constrained:** how `gated_stdin` reads the conf (awk `ENVIRON` per the
  Contract, but no test can see it); what `code_changed_since` prunes other
  than `docs/`; the wording added to the `:374` refusal; the comment blocks.

**Changed signatures: none** - checked against the tree with
`grep -nE 'gated_stdin|gate_tree_hash(_of)?|code_changed_since' scripts/*.sh .claude/hooks/*.sh`:
callers are `lib.sh:607`, `lib.sh:654`, `gates.sh:191`,
`check-boundaries.sh:367/369`, `gate-reminder.sh:98`, all with the shapes the
Contract lists.

### Negative controls: expected values

No suite here fails at import (bash, no missing module), so every control
**ran and was observed**; the table records what each measured in RED and
what it must measure in GREEN.

| Control | Fixture state | Expected | Measured in RED | GREEN must see |
|---|---|---|---|---|
| AC-1 control A: tuning.md `A->B`, no covers line | `lib.test.sh` | unchanged | unchanged (pass) | unchanged |
| AC-1 control B: architecture.md / notes.md under the covers line | same | unchanged from `h9` | unchanged (pass, vacuous) | unchanged, with `h8 != h9` |
| AC-3 story file / command prompt / epic under `docs/**` | same | unchanged from `h11` / `h14` | unchanged (pass, vacuous) | unchanged, with `h11 != h12 != h13` |
| AC-4 doc edits, no conf / `src/**` only | same | unchanged from `h3` / `h5` | unchanged (pass) | unchanged |
| AC-4 pairs: `src/main.ts` edit | same | moves | moves (pass) | moves |
| AC-2 control: architecture.md committed after a fresh record | `boundaries.test.sh` | `rec == now`, `ok … (tree rec)`, `rc 0` | `rec == now`, line printed, `rc 0` (pass) | same |
| AC-5 baseline / control | `gate-reminder.test.sh` | silent | silent (pass) | silent |
| AC-6 control: RED blocks `src/main.ts` | `phase-guard.test.sh` | blocked at that path | blocked (pass) | blocked |

The hashes named in the red output (`31c7dafb…`, `f2a31b31…`, `3353ba57…`) are
fixture hashes and will differ in GREEN; what matters is that they **move**.

### Deferred verifications

- **DV-1** (GREEN, real-tree hashes): declined in RED - the covers arm does
  not exist yet, and `project.conf` is the Lead PO's to write.
- **DV-2** (GATES, the runner really reads the two docs): declined in RED - it
  needs `lune run test` against the real tree; nothing here can stand in for it.
- **DV-3** (GATES, the backlog exclusion is live): declined in RED - the
  prefix test does not exist yet, so there is nothing to mutate. The two
  assertions it will turn red are named in the AC-3 row of `## Test plan`.

### Discovered along the way

- `git grep` has no `-x`; the committed-conf instrument uses
  `git show HEAD:path | grep -cx`. Worth knowing for any future "is this line
  in the commit" needle.
- The AC-2 fixture commits the docs on the story branch, not on `main`, so
  `check 3a` sees `0 source, 0 test` and the only thing left to refuse is the
  stamp - the same shape as the source and test cases above it.
- Nothing about AC-7 is asserted in a suite. A selftest that greps the real
  `project.conf` for the two lines would be a test against a file RED cannot
  write; DV-1 covers it, and `gates.sh --audit` accepting the lines is the
  Lead PO's check at the end of GREEN.

### Contract amendments

None. The Contract's blocks matched what was measured.

## Regressions

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-30T17:36:07Z
    commit: 762a99f (working tree had uncommitted changes)
    tree:   207aaf16c16e0872730e685e0191add92d11282c
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 90)
    PASS         lint (1s, observed 90, floor 1)
    PASS         typecheck (3s, observed 17)
    PASS         unit (56s, observed 452, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 57746)
    PASS         harness (16s, observed 40)
    UNCONFIGURED mutation

## Notes

### The options, weighed

The brief asked for three options. A fourth, "hash all docs", was measured as well,
because it is the obvious one-line fix.

**A. A `paths.conf` rule giving the read docs a category that `gated_stdin` keeps.
Rejected.** There are two forms, and both were measured.

- *Reclassify into an existing category.* The table below shows `phase_allows`
  against the real `phases.conf`, and `gated_stdin` on
  `"<cat>\tdocs/wiki/game/tuning.md"`:

      category  kept by gated_stdin   IDLE PLANNED RED GREEN GATES REVIEW SCAFFOLD DONE
      docs      no                    w    w       w   w     w     w      w        w
      harness   no  (.md excluded)    w    w       w   w     w     w      w        w
      test      yes                   w    -       w   -     -     -      w        -
      config    yes                   w    -       -   w     w     -      w        -
      source    yes                   w    -       -   w     w     -      w        -

  `harness` keeps the lock verdict but is still dropped from the hash, because of
  the `.md` exclusion. `test`, `config` and `source` all freeze tuning.md in
  **PLANNED**, which is the phase where the Game Designer and the Lead PO write
  it. That is the regression the brief forbids. `test` is worse still. Check 3a
  (`check-boundaries.sh:177`) counts `test` files, so a tuning.md edit would
  count as "the tests that came with this source" and would satisfy 3a for a
  source change that has none. `source` would also make `gates.sh:585` demand a
  `covers` for it, and would return it to every `--list source` guard.
- *A new category (for example `spec`).* It must appear in all 8 `phases.conf`
  rows. `phase_allows` fails closed on a category that no row lists. With no
  column, `spec` measured `-` in **every** phase, IDLE included. So a
  `paths.conf` rule landed without its `phases.conf` column locks the file
  everywhere. It also needs `plan.sh:219` taught `spec`, or a contract that names
  tuning.md counts as "enforced" and moves RED to the weaker model for a file the
  lock does not freeze. Three upstream-owned files would change (`phases.conf`,
  `lib.sh`, `plan.sh`) as well as the hand-merged `paths.conf`. **The deciding
  measurement is the refresh path.** `refresh-harness.sh:238-240` tells the
  human to "take upstream as the base and append yours, so upstream wins on any
  overlap". A project rule `spec | docs/wiki/game/tuning.md` appended below
  upstream's `docs | docs/**` is dead, because first match wins. So the fix
  silently reverts on the next refresh, and the file is back in `docs`, out of
  the hash, and nothing says so.
- Underneath both: a category answers **who may write this, in which phase**.
  "A gate reads this" is a different fact, and folding it into a category makes
  the lock carry a fact about the gates.

**B. A declaration in `project.conf`. Chosen, as the existing `covers` line.**
`project.conf` already has the section "What each gate reads", whose header says
"Taken from what each tool was OBSERVED to read". `covers | unit | docs/wiki/game/tuning.md`
is exactly that fact, stated in the file and keyword that already hold it. A
new keyword (for example `reads |`) would be a second name for the same
statement. Measured blast radius: **two functions in one file** (`gated_stdin`
and the `docs/` prune in `code_changed_since`), both in `lib.sh`. Classification
is untouched, so the lock, 3a, the covers check, `plan.sh`, `classify.sh` and
`inject-state.sh` all see what they see today (the table in `## Contract`).
AC-6 is satisfied by construction and pinned anyway. `project.conf` is
project-owned and `refresh-harness.sh` leaves it alone, so the declaration
survives a refresh. Only the reader does not, and that is the same exposure
every harness fix here has (Q4).
*Cost:* `classify.sh docs/wiki/game/tuning.md` still says `docs` for a gated
file. So "is it gated?" is answered by `gated_stdin`, not by the classifier.
That was always true (the `.md` exclusion already made `harness` only partly
gated), and the `gated_stdin` comment will say so.

**C. Derive the set from the tests. Rejected, on measurement.**

    literal read scan  grep -rhoE 'readFile\("docs/[^"]+"\)' tests    -> stack.md only
    broad path scan    grep -rhoE 'docs/[A-Za-z0-9_./-]+\.md' tests   -> architecture.md x2, tuning.md x13, stack.md x7

The literal scan **misses tuning.md**, the file that started this. It is read
through a constant (`SPEC_PATH`). The broad scan brings in **architecture.md**,
which is only mentioned in comments, so every architecture edit would stale the
record. Neither regex is right, and any regex is a needle of the kind `rules.md`
lists. C would also run over 72 test files (`classify.sh --list test tests | wc -l`)
on every hash, including in the Stop hook's twenty-second budget, and on CI
through `git show` of each blob for `gate_tree_hash_of`. As a *guard* it has a
future. See `## Out of scope`.

**D. Hash all docs except `docs/backlog/`. Rejected.** It gives
`5baa97c0…` against `c2529f0d…`, so it covers 24 docs where 2 are read.
`git log --oneline -- docs/wiki | wc -l` is 12 commits, against 1 for tuning.md
and 5 for stack.md. Every product-brief or architecture edit would stale a
record, which is the failure the `.md` exclusion was added to remove ("a recorded
gate hash went stale on a change the gates could not have judged", `lib.sh:621-624`).

### Sizing: one cycle

GREEN is two predicates in one file, plus comments and one skill paragraph. RED is
five suites, each extending a block that already exists. One behaviour: "the gate
hash covers the docs a gate reads". Not split.

### Open questions for the user (none blocking)

- **Q1 (resolved 2026-09-30, user: include it).** stack.md was not in the
  brief. It is measured as read (`contract_raise_test.luau:418`), and AC-7
  covers it alongside tuning.md. The user confirmed during PLANNED that it stays
  in. It is the smaller exposure, because AC-3 of that test pins three
  sentences, not numbers.
- **Q2 (resolved 2026-09-30, user: yes; filed as HARNESS-022).** Should the follow-up guard in `## Out of scope` ("a test reads a doc
  with no covers line") be filed now?

### PLANNED → RED checks (orchestrator, 2026-09-30)

- **ACs testable:** yes. Each has a named suite, a needle and a paired control.
- **Gate that fails if the artifact breaks:** none of the `gate |` lines in
  `project.conf` reads `.claude/hooks/lib.sh` (`covers` lines are `src/**` only).
  The artifact is judged by `selftest.sh` in CI's required `gates` job. No
  optional gate to promote, so `required_gates: []` stands.
- **Changed signatures:** none (see `## Contract`). No caller list is needed.
- **Deferred verifications:** DV-1 (GREEN), DV-2 (GATES) and DV-3 (GATES) each
  name an owner.
- **Epic done-when:** the story has no epic, so there is no done-when gap.
- **Freeze:** `lib.sh`, `gate-reminder.sh` and `check-boundaries.sh` are
  `tooling`, which the lock freezes in RED. No `frozen.sh` snapshot is needed
  for this direction.

### RED verified by the orchestrator (2026-09-30)

The orchestrator re-ran each suite once, one at a time. The counts match the handoff exactly:

    lib: 171 passed, 4 failed            (AC-1 x2, AC-3 control x2)
    boundaries: 135 passed, 4 failed     (AC-2 x4)
    gate-reminder: 29 passed, 1 failed   (AC-5)
    phase-guard: 259 passed, 0 failed    (AC-6, earned by mutation)
    classify: 38 passed, 0 failed        (AC-6, earned by mutation)

Each red case is the one the story names: an unchanged hash, a matching record, or
a silent hook. None is an error. The admissibility run,
`bash scripts/gates.sh --fast`, printed `All required gates passed (6 ran, 1
unconfigured, 0 known)`: format, lint, typecheck, unit (452), build and harness
(40) all passed. That is expected, because no `gate |` line reads `.claude/tests/**`
beyond `project-counters`. The suites are judged by `selftest.sh` in CI.

### GREEN (feature-developer)

Ran on `claude-opus-5-5` (Opus 5.5), the model this agent file declares. No override was reported to me.

**Files changed** (no test file, no `project.conf`):
- `.claude/hooks/lib.sh`: `gated_stdin` gains the covers arm. It is one awk process that reads `$HARNESS_DIR/project.conf` through `ENVIRON` in `BEGIN`, converts each `covers` field-3 glob with the shared `_G2R_AWK`, and keeps a `docs` line outside `docs/backlog/` that matches one of them. Kind and glob are trimmed, and field 3 onward is taken as the glob, as `gates.sh` reads it. The gate id is not consulted. A missing conf or no covers lines keeps nothing. `code_changed_since` no longer prunes `docs/` (the `-path docs -prune` and `docs` in the case are gone). Both comment blocks are updated, including the statement that "is it gated?" is answered by `gated_stdin` and not by the classifier.
- `.claude/hooks/gate-reminder.sh`: header comment only ("never docs no gate covers").
- `scripts/check-boundaries.sh`: the refusal text now reads "Source, test, config or a doc a gate covers changed ...". The needle `gates were recorded against tree` is unchanged.
- `.claude/skills/quality-gates/SKILL.md`: one paragraph after the covers section.

**Suites** (run one at a time): lib 175/0, boundaries 139/0, gate-reminder 30/0, phase-guard 259/0, classify 38/0, gates 74/0. `bash scripts/gates.sh --fast`: all required gates passed (6 ran, 1 unconfigured).

**Negative controls, measured against the shipped code.** I replayed `lib.test.sh:343-504` in a scratch fixture with the assertions made to print hashes:
- AC-4: `h3`=`fb72a68b` held across the tuning.md edit, and `h4` moved (source). `h5`=`89993139` held across the tuning.md, notes.md and architecture.md edits, and `h6` moved.
- AC-1 control A: `h7`=`eaf7e593` held (no covers line).
- AC-1: `h8`=`c8b28b62` != `h9`=`fc63dfe7`. Control B held `h9` across the architecture.md and notes.md edits. `h10`=`56f93175` moved, and restoring the content returned `h9`.
- AC-3: `h11`=`4c440047` held across the story-file edit and the command-prompt edit. `h12`=`e3ab7d1b` and `h13`=`db2ea810` are pairwise distinct. `h14`=`h13`=`db2ea810`: creating an epic under `docs/backlog/` did not move it either, and neither did rewording it.
- AC-2 control and AC-5 baseline/control: passed in the suite. I confirmed these by the shape of the assertions, not by printing values. The AC-2 control's whole-line needle embeds the recorded hash, and `check-boundaries.sh` prints that `ok` line only when `rec == now`. `assert_silent` requires empty output.
- AC-6 control: RED still blocks `src/main.ts` (pass).

**DV-1 preview** (not the record, which the Lead PO writes): `gate_tree_hash_of 762a99f` = `b4a9cb21f834bf4a1f1b6111def4985c5cb6090b` with the shipped `project.conf`. With a scratch `HARNESS_DIR` holding copies of `paths.conf` and `project.conf` plus the covers lines, the results were `b961aa7c58a1e50f2e4bfeb137d773328f272df9` (+tuning.md) and `c2529f0d78a04ef3f4d4cebcf24b1c3bd0a0201a` (+stack.md). All three equal the prototype's values.

### Prototype

The script that produced `## Context` §2. It edits nothing. `S` is the scratchpad,
and `$2` is a space-separated list of docs to treat as kept.

    . .claude/hooks/lib.sh
    c="$1"; keep="$2"
    git ls-tree -r "$c" | awk -F'\t' '{ split($1,a," "); if (a[2]=="blob") print a[3] "\t" $2 }' > "$S/l"
    { awk -F'\t' '{print "B\t" $1 "\t" $2}' "$S/l"
      cut -f2- "$S/l" | classify_stdin \
      | awk -F'\t' -v keep=" $keep " 'BEGIN{OFS="\t"} $1=="docs" && index(keep, " " $2 " ") {$1="spec"} {print}' \
      | awk -F'\t' '($1=="source"||$1=="test"||$1=="config"||$1=="harness"||$1=="tooling"||$1=="spec") && !($1=="harness" && $2 ~ /\.md$/) && index($2,".claude/state/")!=1 {print "C\t" $2}'
    } | awk -F'\t' '$1=="B"{b[$3]=$2;next} $1=="C"{g[$2]=1} END{for(p in b) if(p in g) print b[p] "  " p}' \
      | LC_ALL=C sort | git hash-object --stdin

Calibration: with an empty keep list it prints `b4a9cb21…`, which equals the real
`gate_tree_hash_of 762a99f`.

### REVIEW → DONE (orchestrator, 2026-09-30)

PR [ryanczhang7/first-roblox#39](https://github.com/ryanczhang7/first-roblox/pull/39)
was merged as `c54148d` at 2026-09-30T18:33:11Z. Timings from its first CI run:

- `gates` job: run 36755957868, 2m9s against `timeout-minutes: 45`. The "Harness
  self-test" step took 1m36s and "Run gates" took 16s.
- `boundaries` job: run 36755958085, 5s.

Nothing is near a limit.
